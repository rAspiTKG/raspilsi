## 4. 外部インタフェース

### 4.1 端子表(BAYER_EX_CORE)

コアの端子です。data は `BAYER_EX_DATA_IF` のインタフェースのポート(i_pix は modport dst、o_pix は modport src)です。

{{PINS:BAYER_EX_CORE}}

### 4.2 端子表(BAYER_EX。論理合成・配置配線のトップ)

`BAYER_EX_CORE` のインタフェースのポートを、`bayer4x2_t` のポート(i_data / o_data)にしたラッパです。論理は持ちません。SystemVerilog で使うときは、どちらをインスタンスにしてもかまいません(機能は同じ。検証は両方で行った。8.5)。

{{PINS:BAYER_EX}}

### 4.3 BAYER_EX_DATA_IF(data だけのインタフェース)

SystemVerilog のインタフェースと modport [R10] で、data だけをまとめています。

```systemverilog
interface BAYER_EX_DATA_IF;
  import BAYER_EX_PKG::*;
  bayer4x2_t data;
  modport src (
    output data
  );
  modport dst (
    input  data
  );
  modport mon (
    input  data
  );
endinterface
```

{{PINS:BAYER_EX_DATA_IF}}

vld と busy はインタフェースに入れず、モジュールのポートにしています。つなぎ方の例(`tb/tb_top.sv` と同じ):

```systemverilog
BAYER_EX_DATA_IF s_i_pix ();
BAYER_EX_DATA_IF s_o_pix ();

assign s_i_pix.data = up_data;     // 送り側の data
assign dn_data      = s_o_pix.data;

BAYER_EX_CORE u_core (
  .clk    (clk)
 ,.rst_n  (rst_n)
 ,.i_cfg  (cfg)
 ,.i_vld  (up_vld)
 ,.o_busy (up_busy)
 ,.i_pix  (s_i_pix)
 ,.o_vld  (dn_vld)
 ,.i_busy (dn_busy)
 ,.o_pix  (s_o_pix)
);
```

### 4.4 data の構造体(bayer4x2_t)

```systemverilog
typedef struct packed {
  logic                                   sof;  // フレームの最初の転送
  logic                                   eol;  // 2ラインの最後(右端)の転送
  logic                                   eof;  // フレームの最後の転送
  logic [BLK_Y-1:0][BLK_X-1:0][PIX_W-1:0] pix;  // 画素 pix[y][x](BLK_Y=2、BLK_X=4、PIX_W=14)
} bayer4x2_t;
```

ビットの並び(packed struct なので、最初に書いたフィールドが上位):

{{PINS:bayer4x2_t}}

### 4.5 転送の規則(vld / busy)

| 信号 | 向き | 内容 |
|---|---|---|
| vld | 送り側 → 受け側 | data が有効 |
| busy | 受け側 → 送り側 | 受け取れない |
| data | 送り側 → 受け側 | 転送(`BAYER_EX_DATA_IF` の data、`bayer4x2_t`) |

- vld=1 かつ busy=0 のクロックで1つ転送します。
- busy=1 の間、送り側は vld と data を保持します。
- vld は busy に組み合わせで依存してはいけません(busy は vld に依存してよい)。
- BAYER_EX の o_vld、o_pix.data、o_busy はすべて FF から出しています。o_busy=1 になるのは、出力が止められている間に入力の転送を受けて、スキッドが埋まったときだけです(6.2)。

{{WAVE:vbd_if}}

検証環境は、この規則を入力側(検証環境の送り方)と出力側(DUT の出し方)の両方でアサーションで確かめています(8.1)。

### 4.6 フレームと転送の並び

画像の幅 W は4の倍数、高さ H は2の倍数です。1転送は、偶数ライン y0 と次のライン y0+1 の、4の倍数の列 x0 から x0+3 までの8画素です。転送は、2ラインずつ、左から右へ並べます。

```
     x: 0  1  2  3 | 4  5  6  7 | …  W-4 … W-1
y=0     ┌─ 転送0 ──┐┌─ 転送1 ──┐      ┌─ 転送 W/4-1 ──┐   ← 1組目の2ライン(最後の転送で eol=1)
y=1     └──────────┘└──────────┘      └───────────────┘
y=2     ┌─ 転送W/4 ┐ …                                    ← 2組目の2ライン
y=3     └──────────┘
 …
y=H-2   … 最後の転送(eol=1、eof=1)
y=H-1
```

| フラグ | 1になる転送 |
|---|---|
| sof | フレームの最初の転送(転送0) |
| eol | 2ラインの最後(右端)の転送 |
| eof | フレームの最後の転送(eol も 1) |

- 1フレームの転送の数は (W/4) × (H/2) です。W=4、H=2 のときは1転送で、sof=eol=eof=1 です。
- コアはフラグを処理に使いません。入力のフラグを、画素と同じ転送の出力にそのまま付けて出します。フラグの並びが規則どおりかは確かめません。
- 色の位置は転送の中の位置(y、x の偶奇)だけで決まるので、コアはフレームの中の位置を数えません(5.1)。

### 4.7 設定(i_cfg)

```systemverilog
typedef struct packed {
  logic                   bypass;  // 1: 補正しない(入力の画素をそのまま出す)
  logic [1:0]             phase;   // Bayer の並び 0:RGGB 1:GRBG 2:GBRG 3:BGGR
  logic [3:0][PIX_W-1:0]  blc;     // 黒レベル [0]R [1]Gr [2]Gb [3]B
  logic [3:0][GAIN_W-1:0] gain;    // ゲイン(U4.12) [0]R [1]Gr [2]Gb [3]B
} cfg_t;
```

{{PINS:cfg_t}}

設定を変えるときの規則:

- コアは i_cfg を毎クロック FF(r_cfg)で受け直します。フレームの最初に取り込む仕組み(シャドウ)はありません。
- i_cfg は、コアの中にデータがないとき、つまり入力したすべての転送が出力されたあとに変えてください。前のフレームの最後の転送(eof=1)が出力側で転送されれば、そのあと入力していない限りコアは空です。
- 変えたクロックに、次のフレームの最初の転送を入力してもかまいません(入力の転送と i_cfg を同じクロックの立ち上がりで取り込むため)。検証は、この最も厳しい時刻で行いました(8.3 の bex_cfg_change_test)。
- コアの中にデータがある間に変えると、その転送の1段目と2段目で違う設定を使うことがあります(結果は保証しません)。

### 4.8 リセット

- rst_n は非同期アサート・同期解除です(clk への同期化は IP の外で行う)。
- リセットするのは有効ビット(入力段・スキッド・PIXCOR の2段)だけです。データの FF と r_cfg はリセットしません。
- リセット中は o_vld=0、o_busy=0 です。リセットの前にコアの中にあったデータは捨てます(出力しない)。
- リセット中の入力の転送は受け取りません(送り側も同じリセットで止めてください)。

{{WAVE:reset}}

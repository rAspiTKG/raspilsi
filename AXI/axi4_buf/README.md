# AXI4 マスタ + ライン単位 scratchpad SRAM (`axi4_master_linebuf`)

画像処理向けの AXI4 マスタ。入力側 AXI (Read) で画像を 1 ラインずつ読み、モジュール内の
scratchpad SRAM にライン単位で格納し、出力側 AXI (Write) へ書き出す。
入力側と出力側のアドレス幅・データ幅、1 画素のビット数、SRAM のライン数を parameter で変えられる。

```
  cmd (src, dst, stride, width, height)
       |
  m_axi_in_*                                                     m_axi_out_*
  AR / R --> [rd engine] --> [FIFO] --> [gearbox] --+
                                       ビート→画素   |
                                                    v
                          scratchpad SRAM (NUM_LINES 本、1 本 = 1 ライン)
                                                    |
  AW / W / B <-- [wr engine] <-- [FIFO] <-- [gearbox] <--+
                                            画素→ビート
```

- 言語: SystemVerilog (`always @(posedge aclk ...)` / `always @(*)` で記述)
- クロック / リセット: 単一クロック `aclk`、非同期リセット `aresetn` (負論理)

## ご要望と parameter の対応

| ご要望 | parameter | 既定値 |
| --- | --- | --- |
| 入力アドレスビット | `IN_ADDR_WIDTH` | 32 |
| 入力データビット | `IN_DATA_WIDTH` | 64 |
| 出力アドレスビット | `OUT_ADDR_WIDTH` | 32 |
| 出力データビット | `OUT_DATA_WIDTH` | 64 |
| scratchpad SRAM のライン数 | `NUM_LINES` | 4 |
| 1 画素あたりのビット数 | `PIXEL_BITS` | 8 |

入力側と出力側は完全に独立で、幅が違っていてよい (例: 32bit で読んで 128bit で書く)。

## ファイル構成

```
rtl/
  axi4_master_linebuf.sv    ... トップ
  axi4_lb_rd_engine.sv      ... AXI4 マスタ読み出しエンジン (AR / R)
  axi4_lb_wr_engine.sv      ... AXI4 マスタ書き込みエンジン (AW / W / B)
  axi4_lb_gearbox.sv        ... ビット幅変換 (ビート <-> 画素ワード)
  axi4_lb_scratchpad.sv     ... ライン単位の scratchpad (SRAM を NUM_LINES 個並べる)
  axi4_lb_sram_sp.sv        ... シングルポート SRAM の動作モデル (マクロに置き換える)
  axi4_lb_fifo.sv           ... 同期 FIFO
  filelist.f                ... 上記のコンパイル順
tb/
  tb_axi4_master_linebuf.sv ... 簡易 TB (自己チェック)
  tb_axi4_lb_gearbox.sv     ... gearbox の単体 TB
  axi4_slave_mem_model.sv   ... 検証用 AXI4 スレーブ + メモリ
sim/
  Makefile                  ... Verilator 5.x 用 (10 構成 + gearbox 14 組)
uvm/                        ... Verilator + UVM 環境
  README.md  tb/  sim/
```

## parameter 一覧

### 入力側 AXI (Read)

| parameter | 既定値 | 内容 |
| --- | --- | --- |
| `IN_ADDR_WIDTH` | 32 | アドレス幅 (12 以上) |
| `IN_DATA_WIDTH` | 64 | データ幅 (8, 16, 32, ..., 1024) |
| `IN_ID_WIDTH` | 4 | ID 幅 |
| `IN_AXI_ID` | 0 | `ARID` に出す値 |
| `IN_MAX_BURST` | 16 | 1 バーストの最大ビート数 (1..256) |
| `IN_FIFO_DEPTH` | 32 | 受信 FIFO の深さ (`IN_MAX_BURST` 以上、かつ 2 以上) |
| `IN_ARCACHE` / `IN_ARPROT` / `IN_ARQOS` / `IN_ARREGION` | `4'b0011` / 0 / 0 / 0 | AR の属性 (固定値として出力) |

### 出力側 AXI (Write)

| parameter | 既定値 | 内容 |
| --- | --- | --- |
| `OUT_ADDR_WIDTH` | 32 | アドレス幅 (12 以上) |
| `OUT_DATA_WIDTH` | 64 | データ幅 (8, 16, 32, ..., 1024) |
| `OUT_ID_WIDTH` | 4 | ID 幅 |
| `OUT_AXI_ID` | 0 | `AWID` に出す値 |
| `OUT_MAX_BURST` | 16 | 1 バーストの最大ビート数 (1..256) |
| `OUT_FIFO_DEPTH` | 32 | 送信 FIFO の深さ (`OUT_MAX_BURST` 以上、かつ 2 以上) |
| `OUT_AWCACHE` / `OUT_AWPROT` / `OUT_AWQOS` / `OUT_AWREGION` | `4'b0011` / 0 / 0 / 0 | AW の属性 (固定値として出力) |

### 画素 / scratchpad SRAM

| parameter | 既定値 | 内容 |
| --- | --- | --- |
| `PIXEL_BITS` | 8 | 1 画素のビット数。SRAM にはこの幅で格納する |
| `PIX_MEM_BITS` | `PIXEL_BITS` を 8 の倍数に切り上げ | メモリ上 (AXI データ内) での 1 画素のビット数。`PIXEL_BITS` と同じにすると隙間なく詰める |
| `PIX_ALIGN_MSB` | 0 | `PIX_MEM_BITS > PIXEL_BITS` のとき、0: 下位詰め / 1: 上位詰め |
| `PIX_PER_WORD` | 1 | SRAM 1 ワードの画素数。1 サイクルに処理する画素数でもある (スループットを参照) |
| `MAX_LINE_PIXELS` | 1920 | 1 ラインの最大画素数 (SRAM 1 個の深さを決める) |
| `NUM_LINES` | 4 | scratchpad のライン数 (= SRAM の個数) |

SRAM は 1 個あたり 深さ `ceil(MAX_LINE_PIXELS / PIX_PER_WORD)` ワード、幅 `PIX_PER_WORD * PIXEL_BITS` ビットで、
これを `NUM_LINES` 個使う。

### コマンド

| parameter | 既定値 | 内容 |
| --- | --- | --- |
| `HEIGHT_WIDTH` | 16 | `cmd_height` のビット幅 |
| `STRIDE_WIDTH` | 24 | `cmd_src_stride` / `cmd_dst_stride` のビット幅 (両方のアドレス幅以下) |

範囲外の値を指定すると、エラボレーション時の `$error` で止まる (IEEE 1800 20.11)。
対応していない合成ツールでは `+define+AXI4_LB_NO_ELAB_CHECK` で外せる。

## ポート

| グループ | 信号 | 内容 |
| --- | --- | --- |
| コマンド | `cmd_valid` / `cmd_ready` | valid/ready。アイドル時だけ `cmd_ready=1` |
| | `cmd_src_addr` / `cmd_dst_addr` | 入力画像 / 出力先の先頭アドレス |
| | `cmd_src_stride` / `cmd_dst_stride` | ライン先頭アドレスの間隔 [バイト] |
| | `cmd_width` / `cmd_height` | 1 ラインの画素数 / ライン数 |
| ステータス | `busy` / `done` / `done_err` | `done` は 1 サイクル。`done_err` は同じサイクルで見る |
| | `err_flags[2:0]` | [0] Read 側エラー / [1] Write 側エラー / [2] コマンドの誤り |
| | `line_in_done` / `line_out_done` | 1 ラインの格納完了 / 出力完了 (各 1 サイクル) |
| | `sp_level` | scratchpad に格納済みで、まだ読み出し終わっていないライン数 |
| 入力側 AXI | `m_axi_in_ar*` / `m_axi_in_r*` | AXI4 マスタ (Read チャネルのみ) |
| 出力側 AXI | `m_axi_out_aw*` / `m_axi_out_w*` / `m_axi_out_b*` | AXI4 マスタ (Write チャネルのみ) |

コマンドのタイミング (サイクル 0 の終わりのクロックエッジで `cmd_valid && cmd_ready` が成立):

```
サイクル    0    1    2   ...  n    n+1
cmd_valid   1    0    0   ...  0    0
cmd_ready   1    0    0   ...  0    1     受付後は完了まで 0
busy        0    1    1   ...  1    0
done        0    0    0   ...  1    0     busy の最終サイクルに 1 サイクルだけ 1
err_flags   -    -    -   ...  E    -     done と同じサイクルで見る
```

## メモリ上の画像フォーマット

- ライン y の先頭アドレス = 先頭アドレス + y × stride
- 1 ラインは画素 0 から順に `PIX_MEM_BITS` ビットずつ、下位ビット・下位アドレスから隙間なく並ぶ
  (little-endian)。1 ライン = `ceil(width × PIX_MEM_BITS / 8)` バイト
- `PIX_MEM_BITS > PIXEL_BITS` のとき、余りのビットは入力では無視し、出力では 0 を書く

| 例 | `PIXEL_BITS` | `PIX_MEM_BITS` | 1 画素のバイト数 |
| --- | --- | --- | --- |
| 8bit グレー | 8 | 8 | 1 |
| 10bit を 16bit に入れる (一般的な形式) | 10 | 16 | 2 |
| 10bit を隙間なく詰める | 10 | 10 | 1.25 |
| RGB888 | 24 | 24 | 3 |
| 12bit を 16bit の上位詰め | 12 | 16 (`PIX_ALIGN_MSB=1`) | 2 |

出力の最終ビートは WSTRB で有効バイトだけを書くので、ラインの後ろ (stride の隙間) のメモリは壊さない。

## 動作

1. コマンドを受けると、1 ラインのバイト数とビート数を計算する
2. 入力側は scratchpad に空きラインがあるときだけ、次のラインの AR を出す (空きラインを 1 本予約する)
3. 読んだビートを画素ワードに変換し、予約したラインの SRAM に先頭から書く
4. 1 ライン分が揃うと出力側が SRAM から読み出し、ビートに詰め直して AXI へ書く
5. 読み出し終わったラインを解放する。2〜5 をライン数ぶん繰り返す
6. 全ラインの B を受けたら `done`

- `NUM_LINES >= 2` なら、あるラインの書き出しと次のラインの取り込みが並行する。
  `NUM_LINES = 1` でも動くが、取り込みと書き出しが交互になるのでスループットは約半分になる
- 出力側が止まると scratchpad が `NUM_LINES` 本まで溜まり、そこで入力側の AR 発行も止まる
- エラー応答 (SLVERR / DECERR) を受けても転送は最後まで続け、`done` のときに `err_flags` で通知する

### SRAM をシングルポートにしている理由

格納はライン単位で、読み出すのは格納が終わったラインだけなので、
「書き込み中のライン」と「読み出し中のライン」は必ず別の SRAM になる。
1 個の SRAM には書き込みか読み出しのどちらかしか来ないので、1RW (シングルポート) で足りる。
同じライン数なら 2 ポート SRAM より面積が小さい。

ラインバッファを SRAM のリング (循環) で持つのは画像処理ハードウェアで一般的な構成
(参考の Darkroom 論文: "line buffers as circularly-addressed SRAMs or BRAMs")。

### バスを塞がないための作り

| 側 | 作り | 理由 |
| --- | --- | --- |
| Read | 受信 FIFO に 1 バースト分の空きがあるときだけ AR を出す | バーストの途中で `RREADY` を下げない |
| Write | 送信 FIFO に 1 バースト分のデータが揃ってから AW を出す | AW を出した後に `WVALID` を途切れさせない |

AXI4 の W チャネルには ID が無いので、AW を出した後に W を止めると、同じスレーブへ書く他のマスタも待たされる。
どちらも簡易 TB と UVM の両方で常時チェックしている。

## スループット

1 サイクルに SRAM へ読み書きできるのは 1 ワード (`PIX_PER_WORD` 画素) なので、上限は次の小さいほうになる。

- 画素側: `PIX_PER_WORD` 画素/サイクル
- AXI 側: アウトスタンディング 1 のため、バーストとバーストの間に数サイクル空く。
  スレーブが待たせない場合でも 1 ビート/サイクルにはならず、最大バースト長が短いほど下がる

```
実測 (簡易 TB、スレーブのストール無し、PERF 行)

 構成                                           画素/サイクル  入力ビート/サイクル  出力ビート/サイクル
 64bit→64bit   8bit 画素  1 画素/ワード  4 ライン     0.92          0.12               0.12
 32bit→128bit 10bit(16)  2 画素/ワード  2 ライン     1.38          0.69               0.17
 64bit→256bit  8bit 画素  8 画素/ワード  4 ライン     5.98          0.75               0.19
   同上で IN_MAX_BURST = 64  (既定は 16)              6.91          0.86               0.22
   同上で IN_MAX_BURST = 256                          7.20          0.90               0.23
 512bit→64bit 12bit(16)  8 画素/ワード  8 ライン     2.70          0.09               0.68
 64bit→64bit  10bit 詰め  4 画素/ワード  1 ライン     1.76          0.28               0.28
```

速度を上げたいときの調整:

- `PIX_PER_WORD × PIX_MEM_BITS` を入力側・出力側のデータ幅以上にする
  (例: 64bit バスで 8bit 画素なら `PIX_PER_WORD=8`)。1 行目は 1 画素/ワードなので画素側が上限になっている
- `IN_MAX_BURST` / `OUT_MAX_BURST` を大きくする (FIFO の深さも同じだけ必要)
- それでも足りなければ、アウトスタンディング数を増やす (下の提案を参照)

## SRAM マクロへの置き換え

`axi4_lb_sram_sp.sv` は動作モデルなので、ASIC ではメモリコンパイラの 1RW マクロに置き換える。

```
ce   : チップイネーブル            we    : 1 = 書き込み / 0 = 読み出し
addr : ワードアドレス              wdata : 書き込みデータ
rdata: ce&&!we の次サイクルに有効 (読み出しレイテンシ 1)
```

- ビット単位のライトマスクは使わない
- 上位は `rdata` を「読み出しの次の 1 サイクルだけ」使う。マクロの出力保持やライトスルーの仕様には依存しない
  (`+define+AXI4_LB_SRAM_POISON` を付けると、それ以外のサイクルの `rdata` を乱数にして確認できる。
  同梱の Makefile は常にこれを付けている)
- SRAM の構成を変えたい場合 (全ラインを 1 個の 2 ポート SRAM にまとめる等) は
  `axi4_lb_scratchpad.sv` を同じポートのまま差し替える
- `axi4_lb_scratchpad.sv` にはシミュレーション用のチェックが入っている。
  合成時は `SYNTHESIS` を define して外す
- 入力側・出力側の FIFO (深さ × データ幅) はフリップフロップで作られる。データ幅が広い構成では
  `IN_MAX_BURST` / `OUT_MAX_BURST` と FIFO の深さを小さくするか、レジスタファイルのマクロに置き換える

## 使用上の制約

- `cmd_src_addr` / `cmd_src_stride` は入力側バス幅 (`IN_DATA_WIDTH/8` バイト) の倍数、
  `cmd_dst_addr` / `cmd_dst_stride` は出力側バス幅の倍数であること。
  違反や `cmd_width > MAX_LINE_PIXELS` は転送せずに `err_flags[2]` で返す
- `cmd_dst_stride` は 1 ラインのバイト数以上であること (ライン同士が重ならない)。これは検査していない
- `cmd_width = 0` または `cmd_height = 0` は何もせずに `done` (エラーにしない)
- 入力 AXI / 出力 AXI / SRAM は同一クロック
- バーストは INCR のみ、`AxSIZE` は常にバス幅。USER 信号は無い
- 実行中のコマンドを中断する機能は無い

## 画像処理を挟む場合

今回は「読んだラインをそのまま書く」構成で、処理は入っていない。処理を入れるときの接続点は
scratchpad の読み出し側になる (以下は未実装。変更が必要な箇所の目安)。

| やりたいこと | 接続点 / 必要な変更 |
| --- | --- |
| 画素ごとの処理 (ゲイン、LUT など。ラインの画素数が変わらない) | `u_rd_fifo` の出力 (`rdf_rd_valid` / `rdf_rd_ready` / `rdf_rd_data` = {ライン最終ワード, `PIX_PER_WORD` 画素}) と `u_gb_out` の間に入れる。valid/busy のモジュールなら `busy = !ready` で読み替える |
| crop / 縮小 (出力の幅・高さが変わる) | 上に加えて、コマンドに出力側の幅・高さを追加し、出力側のビート数と WSTRB (`out_beats_q` / `out_last_strb_q`)、ライン数 (`out_lines_left` / `out_done_left`) を出力サイズから計算する |
| 縦方向のフィルタ (複数ラインを同時に参照) | scratchpad はラインごとに SRAM が分かれているので、読み出しポートをライン数ぶん出せば同時に読める。制御は「1 ラインずつ読んで解放」から「必要なライン数が溜まったら窓を 1 ライン進める」に変える |

## 他に調整できるようにしておくとよい AXI の項目 (提案)

### 今回 parameter にしたもの

| 項目 | parameter | 調整する理由 |
| --- | --- | --- |
| ID 幅と ID の値 | `IN_ID_WIDTH` / `IN_AXI_ID` / `OUT_ID_WIDTH` / `OUT_AXI_ID` | インターコネクトのポートごとに ID 幅が決まる。NI-700 のスレーブ側 (ASNI) は 1〜24bit |
| 最大バースト長 | `IN_MAX_BURST` / `OUT_MAX_BURST` | 長いほど転送効率は上がるが、FIFO が大きくなり、他マスタの待ち時間も伸びる。AXI3 相当の相手なら 16 以下 |
| FIFO の深さ | `IN_FIFO_DEPTH` / `OUT_FIFO_DEPTH` | 最大バースト長以上が必要。面積とのトレードオフ |
| `AxCACHE` | `IN_ARCACHE` / `OUT_AWCACHE` | 既定の `0011` は Modifiable。途中の幅変換でバーストを分割・結合してよいことを示す |
| `AxPROT` | `IN_ARPROT` / `OUT_AWPROT` | セキュア / 非セキュア、特権の区別をするシステム向け |
| `AxQOS` | `IN_ARQOS` / `OUT_AWQOS` | QoS を使わないなら 0。NI-700 は QoS regulator を持つ |
| `AxREGION` | `IN_ARREGION` / `OUT_AWREGION` | NI-700 は AxREGION 非対応なので 0 のままにする |
| 端数ビートの WSTRB | (常に有効) | 「WSTRB は有効なデータを持つバイトレーンだけ 1」という規則に合わせ、ライン外を書かない |
| 画素の詰め方 | `PIX_MEM_BITS` / `PIX_ALIGN_MSB` / `PIX_PER_WORD` | ソフトや前後段のフォーマットに合わせる。スループットも決まる |

### 今回は入れていないが、検討をお勧めするもの

| 項目 | 内容 | 入れる場面 |
| --- | --- | --- |
| アウトスタンディング数 | いまは Read / Write 各 1。同じ ID で先行発行できるようにする | スレーブの応答が遅い (DDR など) と、1 では帯域が落ちる |
| `AxPROT` / `AxQOS` のポート化 | parameter ではなく入力ポートにして、フレームごとに変える | セキュア / 非セキュアのメモリを使い分ける、優先度を動的に変える |
| USER 信号 | `AxUSER` / `WUSER` / `RUSER` / `BUSER` の幅を parameter 化 | システムがサイドバンドを使う場合 (NI-700 は USER 幅を設定できる) |
| 非アラインアドレス | 先頭ビートの WSTRB とバイトずらしに対応する | バス幅の倍数でない位置から読み書きしたい場合 |
| Regular トランザクション | AXI5 で定義された Regular の条件 (バースト長を 1 / 2 / 4 / 8 / 16 に限る等。条件の一覧は実装前に仕様書 A3.1.8 で確認すること) に合わせてバーストを切る | 相手が Regular のみ対応の場合。いまは `min(残り, MAX_BURST, 4KB まで)` で切るので 13 ビートのような長さも出る |
| エラー時の方針 | 最初のエラーで中断、エラーアドレスの保持、割り込み出力 | ソフトで原因を切り分けたい場合 |
| ハンドシェイクのタイムアウト | 一定サイクル応答が無ければ異常終了 | バスのハングを検出したい場合 |
| レジスタスライス | AXI の各チャネル出力にスキッドバッファを挿入 | タイミングが厳しい場合 (前回の `axi4_skid_buffer` が使える) |
| クロック分離 | 入力側と出力側を別クロックにし、ライン単位で受け渡す | 2 つの AXI が別クロックドメインの場合 (SRAM は 2 ポートが必要になる) |
| 低消費電力インタフェース | `busy` を元に Q-Channel (QREQn / QACCEPTn / QACTIVE) を付ける | クロックゲーティングを外部のコントローラで行う場合 |
| パリティ保護 | AXI5 のインタフェースパリティ (`*CHK` 信号) | 機能安全の要求がある場合 |
| 負の stride | stride を符号付きにして下から上へ読む | 上下反転 |

### 既製 IP / 市販ツールで代替できる範囲

- **AXI の読み書き部分 → Arm DMA-350**
  DMA-350 は 2D 転送 (X / Y サイズと Y 方向の stride) と、転送中のデータを外部で加工するための
  AXI4-Stream インタフェースを持っている。NoC に DMA-350 があるなら、AXI の読み書きは DMA-350 に任せ、
  ストリーム側にラインバッファと画像処理を置く構成も取れる。
  ただし DMA-350 のデータ幅は 32 / 64 / 128bit で、今回のように入力と出力でデータ幅を変える使い方は
  このモジュールのほうが向いている
- **AXI プロトコルの確認 → Cadence の AMBA 向け VIP**
  同梱の TB のプロトコルチェック (スレーブモデルと SVA) は、このモジュールが使う範囲に絞った手作りのもの。
  サインオフでは市販の VIP を使うほうが確実。Cadence の AMBA 向け Simulation VIP は AXI3 / AXI4 / AXI5 に対応し、
  BFM・プロトコルチェック・カバレッジモデルを含む。形式検証向けには Formal VIP がある。
  このモジュールは FSM とカウンタが中心で規模が小さいので、形式検証での網羅確認に向いている
- **SRAM → メモリコンパイラの 1RW マクロ**
  `axi4_lb_sram_sp.sv` は動作モデルなので、実チップではマクロに置き換える (上の「SRAM マクロへの置き換え」)

## シミュレーション (簡易 TB)

Verilator 5.052 で確認。

```
cd sim
make            # gearbox 単体 (14 組) + トップ (10 構成)
make gearbox    # gearbox 単体だけ
make top        # トップの全構成
make one CFG=c2 # 1 構成だけ
make lint       # RTL を -Wall で lint (全構成)
```

### 構成

| 名前 | 内容 |
| --- | --- |
| c1 | 既定 (64bit → 64bit、8bit 画素、4 ライン) |
| c2 | 32bit → 128bit、10bit 画素を 16bit コンテナ、2 画素/ワード、2 ライン |
| c3 | 128bit → 32bit、24bit 画素 (RGB888)、3 ライン |
| c4 | 10bit 画素を隙間なく詰める、4 画素/ワード、1 ライン |
| c5 | 512bit → 64bit、12bit 画素を 16bit の上位詰め、8 画素/ワード、8 ライン |
| c6 | 8bit → 16bit、1bit 画素、3 画素/ワード、バースト 256 / 1 |
| c7 | アドレス 40bit / 24bit、ID 幅 1 / 8、16bit 画素、5 ライン、バースト 8 / 32 |
| c8 | 最大幅 1920、64bit → 256bit、8 画素/ワード |
| c9 | 最大幅 1 画素、64bit 画素、5 画素/ワード |
| c10 | 1024bit → 1024bit、13bit 画素を隙間なく詰める、7 画素/ワード、最大幅 4095 |

### テスト項目

| テスト | 内容 |
| --- | --- |
| TEST1 | 基本 (stride がライン長ちょうど) |
| TEST2 | 入力・出力とも 4KB 境界を跨ぐ |
| TEST3 | 幅 / 高さの端 (1 画素、1 ワード前後、最大幅、1 ライン、`NUM_LINES` 前後) |
| TEST4 | 出力側を完全に止める → scratchpad が満杯になり AR も止まる → 再開 |
| TEST5 | READY が VALID を待つスレーブ |
| TEST6 | SLVERR 注入 (入力側 / 出力側 / 両方)、その後の正常フレーム |
| TEST7 | コマンド誤り (幅超過・非アライン)、0 画素 / 0 ライン |
| TEST8 | busy 中に次のコマンドを待たせる |
| TEST9 | ランダムフレーム × 4 条件 (ストール無し / 入力が遅い / 出力が遅い / 両側ストール + READY が VALID を待つ) |

フレームごとに次を確認している。

- 出力先メモリの全バイト。ライン内は入力画像の画素、ライン外 (ガード領域) は元のパターンのまま
- 発行されたバーストの先頭アドレスと長さの列が、ラインごとに `min(残り, MAX_BURST, 4KB まで)` で分割した列と一致
- `err_flags`、ライン完了パルスの回数、書き込みバイト数と範囲
- 常時: AXI 属性、WSTRB、バースト中の `RREADY` / `WVALID`、プロトコル違反 0 件、
  scratchpad の同一ライン同時アクセス 0 件・未書き込みワードの読み出し 0 件

### 実行結果 (この環境)

Verilator 5.052 で全て PASS。ビルド時の警告は 0 件 (警告はエラー扱いでビルドしている)。
RTL は 10 構成とも `verilator --lint-only -Wall` で警告 0 件。

```
$ make lint
lint c1 : clean   ...   lint c10 : clean

$ make
gearbox IN=64 OUT=8 : PASS      (ほか 13 組も PASS)
c1 : PASS    frames=146 pixels=80172  AR bursts=1232 AW bursts=1221 max sp_level=4
c2 : PASS    frames=146 pixels=51185  AR bursts=2040 AW bursts=811  max sp_level=2
c3 : PASS    frames=146 pixels=28818  AR bursts=890  AW bursts=1805 max sp_level=3
c4 : PASS    frames=146 pixels=28434  AR bursts=514  AW bursts=504  max sp_level=1
c5 : PASS    frames=146 pixels=135389 AR bursts=2119 AW bursts=3283 max sp_level=8
c6 : PASS    frames=144 pixels=8378   AR bursts=489  AW bursts=830  max sp_level=2
c7 : PASS    frames=146 pixels=82300  AR bursts=3289 AW bursts=1349 max sp_level=5
c8 : PASS    frames=50  pixels=239793 AR bursts=2062 AW bursts=657  max sp_level=4
c9 : PASS    frames=145 pixels=510    AR bursts=507  AW bursts=507  max sp_level=1
c10: PASS    frames=45  pixels=231846 AR bursts=316  AW bursts=315  max sp_level=2
```

(frames 以降は各構成のログ `sim/<構成>.log` の集計行から抜粋。)

### 検証環境の検出力確認

RTL に 1 箇所ずつバグを入れ (29 種)、簡易 TB を 4 構成で流した結果。29 種すべてが、少なくとも 1 構成で FAIL になった。

```
入れたバグ                                    c1    c2    c4    c5    最初に検出したチェック
最終ビートの WSTRB を全有効にする             検出  検出  検出  検出  WSTRB モニタ
最終ビートの WSTRB を 1 バイト多くする        検出  検出  検出  検出  WSTRB モニタ
ライン幅を超えた画素位置を 0 にしない         -     -     検出  -     メモリ照合
入力側 gearbox をライン末尾で clear しない    検出  -     検出  検出  scratchpad の同時アクセス検出
出力側 gearbox をライン末尾で clear しない    -     -     検出  検出  メモリ照合
空きラインの確認なしに AR を出す              検出  検出  検出  検出  sp_level 上限
入力 stride を 1 ビート分ずらす               検出  検出  検出  検出  バースト列
出力 stride に入力 stride を使う              検出  検出  検出  検出  バースト列
SRAM を 1 ワード多く読む                      検出  検出  検出  検出  未書き込みワードの読み出し検出
ラインの格納を 1 ワード早く終える             検出  検出  検出  検出  未書き込みワードの読み出し検出
入力ビート数の計算を誤る                      検出  検出  検出  検出  バースト列
出力ビート数の計算を誤る                      検出  検出  検出  検出  WSTRB モニタ
出力で画素の上位詰めを行わない                -     -     -     検出  メモリ照合
err_flags の Read / Write を入れ替える        検出  検出  検出  検出  err_flags
コマンドの誤りを検査しない                    検出  検出  検出  検出  SRAM 範囲外書き込み検出
SRAM 読み出し中の 1 ワードを数えない          検出  検出  検出  検出  メモリ照合
読み出しラインを進めない                      検出  検出  -     検出  scratchpad の同時アクセス検出
Read を 4KB 境界で分割しない                  検出  検出  検出  検出  スレーブモデルのプロトコル違反
WVALID を WREADY が来てから出す               検出  検出  検出  検出  WVALID 途切れ
データが揃う前に AW を出す                    検出  検出  検出  検出  WVALID 途切れ
FIFO の空きを確認せずに AR を出す             検出  -     -     -     RREADY 低下
SRAM の書き込みアドレスを進めない             検出  検出  検出  検出  メモリ照合
gearbox の連結位置を誤る                      検出  検出  検出  検出  メモリ照合
AWCACHE の parameter を反映しない             検出  検出  検出  検出  AXI 属性モニタ
sp_level に別のカウンタを出す                 検出  検出  検出  検出  TEST4 の満杯確認
line_out_done を出さない                      検出  検出  検出  検出  ライン完了パルス数
BRESP を無視する                              検出  検出  検出  検出  err_flags
RRESP を無視する                              検出  検出  検出  検出  err_flags
WLAST を先頭ビートで出す                      検出  検出  検出  検出  スレーブモデルのプロトコル違反
```

- c1 / c2 / c4 は上の表の構成。c5 はビルド時間を抑えるため 64bit バスに縮めたもの
  (12bit 画素を 16bit の上位詰め、3 画素/ワード、3 ライン)
- 「-」は、その構成ではバグの影響が出ない組み合わせ
  (例: 上位詰めは c5 だけ、`NUM_LINES=1` の c4 では読み出しラインが常に 0、
  c2 は 1 ビートがちょうど 1 ワードなので gearbox に余りが残らない)。
  複数の構成で流す必要があることを示している
- 「SRAM を 1 ワード多く読む」は、最初は 4 構成とも PASS になった (余分に読んだワードは
  WSTRB と gearbox の clear で捨てられ、出力は正しい)。scratchpad の動作モデルに
  「そのラインにまだ書いていないワードの読み出し」の検出を足して、検出できるようにした
- gearbox 単体 TB でも 4 種 (受付しきい値を小さくする / 連結位置 / clear 無効 / out_last) を入れ、全て FAIL を確認した

UVM 環境での同様の確認は `uvm/README.md` を参照。

## 参考

- AMBA AXI Protocol Specification (Arm IHI 0022)
  - 最新版の入口: https://developer.arm.com/documentation/ihi0022/latest/
  - Issue L (4KB 境界: A3.1 / Regular トランザクション: A3.1.8 / Modifiable: A4.2.2 / USER 信号: A12.5 / パリティ保護: A16.2):
    https://documentation-service.arm.com/static/68b03beb01ae952d9559f9eb
  - Issue E (A3.4.3 "A master must ensure that the write strobes are HIGH only for byte lanes that contain valid data" /
    A4.3.1 Modifiable):
    https://documentation-service.arm.com/static/5f915b62f86e16515cdc3b1c
- Arm CoreLink NI-700 TRM (AXI5 / ACE5-Lite 対応、ASNI の ID 幅 1〜24bit、データ幅 32〜1024bit、
  AxREGION 非対応、QoS regulator、Q-Channel):
  https://documentation-service.arm.com/static/60acf9c4982fc7708ac1cde2
- Arm CoreLink DMA-350 TRM (2D 転送、YADDRSTRIDE、AXI4-Stream インタフェース、データ幅 32 / 64 / 128bit):
  https://documentation-service.arm.com/static/639a4f7f1d698c4dc521c63e
- AMBA Low Power Interface Specification (Q-Channel / P-Channel、Arm IHI 0068):
  https://developer.arm.com/documentation/ihi0068/latest/
- Cadence AMBA VIP Solutions (Simulation VIP):
  https://www.cadence.com/en_US/home/tools/system-design-and-verification/verification-ip/simulation-vip/amba.html
- Cadence Formal VIP for Arm AMBA:
  https://www.cadence.com/en_US/home/tools/system-design-and-verification/verification-ip/formal-vip/amba-arm.html
- Darkroom: Compiling High-Level Image Processing Code into Hardware Pipelines (ラインバッファの構成):
  https://graphics.stanford.edu/papers/darkroom14/darkroom14-low.pdf
- Verilator: エラボレーション時の `$error` (USERERROR、IEEE 1800-2023 20.11):
  https://verilator.org/guide/latest/warnings.html

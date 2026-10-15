# AMBA バスの信号仕様まとめ (AXI4 / APB / AHB5 / AXI4-Lite)

AXI4、APB、AHB5、AXI4-Lite の各信号について、次の 4 点をまとめたものです。

- 意味
- ビット幅の決め方
- 出す値の決め方 (その信号に出す値をどう決めるか)
- 変化タイミング

仕様の節番号は、次の略号を付けて示します。

| 略号 | 仕様 |
|---|---|
| E | AMBA AXI and ACE Protocol Specification (Arm IHI 0022E) |
| H | AMBA AXI and ACE Protocol Specification (Arm IHI 0022H) |
| J | AMBA AXI Protocol Specification (Arm IHI 0022J) |
| APB | AMBA APB Protocol Specification (Arm IHI 0024E) |
| AHB | AMBA AHB Protocol Specification (Arm IHI 0033C、AHB5) |
| AHB-Lite | AMBA 3 AHB-Lite Protocol Specification (Arm IHI 0033A) |

用語 : マネージャ = マスタ、サブオーディネート = スレーブ。APB ではリクエスタ / コンプリータと呼びます。

向きの列 : 信号の表の「マスタ側」「スレーブ側」は、マスタ (マネージャ / リクエスタ) とスレーブ (サブオーディネート / コンプリータ) のモジュールのポートとして見た向き (input / output) です。マスタの output はスレーブの input に、スレーブの output はマスタの input につながります。AHB の HSELx と HREADY はインターコネクト (デコーダ / マルチプレクサ) が出す信号で、HRESP / HRDATA / HEXOKAY もマルチプレクサを通ってマスタに届きます。

注 : 最新の AXI 仕様 (J) では AXI3 / AXI4 / AXI4-Lite の記述が削除され、新規設計には AXI5 系が推奨されています。AXI4 / AXI4-Lite の規則は E を参照しています。

---

## 目次

1. 4 つのプロトコルの比較と信号の向き
2. AXI4
3. APB (APB4)
4. AHB5
5. AXI4-Lite
6. 検証に使えるツール
7. 参考資料

---

## 1. 4 つのプロトコルの比較と信号の向き

### 1.1 比較

| | AXI4 | APB | AHB5 | AXI4-Lite |
|---|---|---|---|---|
| 転送の形 | 5 チャネル (AW / W / B / AR / R) の VALID / READY。バーストは最大 256 ビート | パイプライン無し。1 転送に最低 2 サイクル | アドレスフェーズとデータフェーズの 2 段パイプライン。バーストあり | AXI4 と同じ 5 チャネルで、常に 1 ビート |
| 待ち | 各チャネルの READY=0 | PREADY=0 | HREADYOUT=0 | 各チャネルの READY=0 |
| エラー | BRESP / RRESP | PSLVERR | HRESP (2 サイクルの ERROR 応答) | BRESP / RRESP |
| バイトの選択 | WSTRB | PSTRB (書き込みだけ) | HSIZE と HWSTRB (省略可) | WSTRB |
| 応答の順序 | 同じ ID は順番どおり、ID が違えば順不同 | 順番どおり | 順番どおり | ID が無く、全て順番どおり |
| 命令 / データの区別 | AxPROT[2]=1 が命令 | PPROT[2]=1 が命令 | HPROT[0]=1 がデータ (極性が逆) | AxPROT[2]=1 が命令 |

### 1.2 信号の向きのまとめ

マスタから見た向きです。スレーブから見た向きは、AHB5 以外はこの逆になります。

```text
AXI4
  マスタ output : AWID AWADDR AWLEN AWSIZE AWBURST AWLOCK AWCACHE AWPROT AWQOS AWREGION AWVALID
                  WDATA WSTRB WLAST WVALID
                  BREADY
                  ARID ARADDR ARLEN ARSIZE ARBURST ARLOCK ARCACHE ARPROT ARQOS ARREGION ARVALID
                  RREADY
  マスタ input  : AWREADY WREADY BID BRESP BVALID ARREADY RID RDATA RRESP RLAST RVALID
  両方 input    : ACLK ARESETn

APB
  マスタ output : PSELx PENABLE PADDR PWRITE PWDATA PSTRB PPROT
  マスタ input  : PREADY PRDATA PSLVERR
  両方 input    : PCLK PRESETn

AHB5
  マスタ output : HADDR HTRANS HWRITE HSIZE HBURST HPROT HMASTLOCK HNONSEC HEXCL HMASTER HWDATA HWSTRB
                  (スレーブ側では全て input)
  スレーブ output : HREADYOUT HRESP HRDATA HEXOKAY
                  (HRESP / HRDATA / HEXOKAY はマルチプレクサを通ってマスタの input になる。
                   HREADYOUT はマルチプレクサで選ばれ、マスタと全てのスレーブの HREADY になる)
  インターコネクト output : HSELx (スレーブの input)、HREADY (マスタと全てのスレーブの input)
  両方 input    : HCLK HRESETn

AXI4-Lite
  マスタ output : AWADDR AWPROT AWVALID WDATA WSTRB WVALID BREADY ARADDR ARPROT ARVALID RREADY
  マスタ input  : AWREADY WREADY BRESP BVALID ARREADY RDATA RRESP RVALID
  両方 input    : ACLK ARESETn
```

---

## 2. AXI4

### 2.1 DUT の信号一覧についての注意

1. `DUT_AWVAILD` は `DUT_AWVALID` の綴り違いです。
2. `DUT_WREADY` が 2 回あります。W チャネルの READY は 1 本です。
3. 読み出し側には ARPROT (3bit) と ARQOS (4bit) があるのに、書き込み側に AWPROT (3bit) と AWQOS (4bit) がありません。AXI4 では書き込み側にもあるので、抜けていないか確認してください。DUT に本当に無い場合は、相手側に固定値をつなぎます。AWQOS は 0 です。AWPROT はシステムの保護設計に合わせた値にします。
4. AWLOCK / ARLOCK は AXI4 では 1bit です。

DUT がマネージャなら、AW / W / AR の信号と BREADY / RREADY を出します。サブオーディネートなら、AWREADY / WREADY / ARREADY と B / R の信号を出します。

### 2.2 共通の変化タイミング

- **クロック:** 入力は ACLK の立ち上がりで取り込まれ、出力は立ち上がりの後でだけ変わります。インターフェースの入力から出力への組み合わせパスは作れません (E A3.1.1)。
- **ハンドシェイク:** 転送は、VALID と READY が両方 1 の立ち上がりで成立します。VALID を 1 にしたら、成立するまで下げてはいけません。一緒に出す信号も変えません (E A3.2.1)。成立の後は、次の値に変えるか VALID を 0 にします。VALID=0 の間の値は意味を持ちません。
- **待ってよいもの、いけないもの:** VALID は READY を待ってから上げてはいけません。READY は VALID を待ってから上げてもかまいません。VALID が来る前なら、一度上げた READY を下げてもかまいません (E A3.2.1 / A3.3.1)。
- **リセット:** リセット中は、AWVALID / WVALID / ARVALID と BVALID / RVALID を 0 にします。それ以外の信号は何でもかまいません。VALID を上げてよいのは、ARESETn=1 になった後の立ち上がりからです (E A3.1.2)。
- **チャネル間の順序:**
  - BVALID を 1 にできるのは、AW のハンドシェイクと、最後の W (WLAST=1) のハンドシェイクの両方の後だけです (E A3.3.1)。
  - RVALID を 1 にできるのは、AR のハンドシェイクの後だけです (E A3.3.1)。
  - W は AW より先に来てもかまいません (E A3.3)。

### 2.3 タイミングの例

```text
edge      1  2  3  4  5  6  7      (write, AWLEN=2 -> 3 beats)
AWVALID   1  1  0  .  .  .  .
AWREADY   0  1  .  .  .  .  .      AW handshake at edge 2 (AWADDR etc. held at edges 1-2)
WVALID    1  1  1  1  0  .  .
WREADY    1  0  1  1  .  .  .      W beats accepted at edges 1, 3, 4
WLAST     0  0  0  1  .  .  .      1 only on the 3rd beat
BVALID    0  0  0  0  1  1  0      allowed only after edge 2 (AW) and edge 4 (WLAST beat)
BREADY    .  .  .  .  0  1  .      B handshake at edge 6 (BID/BRESP held at edges 5-6)

edge      1  2  3  4  5            (read, ARLEN=1 -> 2 beats)
ARVALID   1  0  .  .  .
ARREADY   1  .  .  .  .            AR handshake at edge 1
RVALID    0  1  1  1  0            allowed only after the AR handshake
RREADY    .  1  0  1  .            R beats accepted at edges 2 and 4
RLAST     .  0  1  1  .            1 only on the 2nd beat, held while waiting
```

`edge n` の列は、n 番目の ACLK の立ち上がりで取り込まれる値です。`.` は値を問わないことを示します。

### 2.4 ビット幅の決め方

| 区分 | 信号 | 決め方 |
|---|---|---|
| 仕様で固定 | AxLEN 8 / AxSIZE 3 / AxBURST 2 / AxLOCK 1 / AxCACHE 4 / AxPROT 3 / AxQOS 4 / AxREGION 4 / xRESP 2 / VALID・READY・LAST 1 | 変えられない (J 表 A2.1〜A2.5) |
| アドレス | AWADDR / ARADDR | アドレス空間の大きさ。1〜64、既定 32 (J 表 A4.12)。32bit で 4GB |
| データ | WDATA / RDATA | 必要な帯域 (幅 × 周波数)。8 / 16 / 32 / 64 / 128 / 256 / 512 / 1024 から選ぶ (H A1.2.1) |
| ストローブ | WSTRB | データ幅 / 8 (64bit なら 8bit) |
| ID | AWID・BID / ARID・RID | マネージャ側は、順序を分けて同時に出したい流れの数で決める (4bit で 16 通り)。インターコネクトは応答の返し先を区別するビットを足すので、サブオーディネート側は「マネージャ側 + log2(マネージャ数)」が一般的 |

### 2.5 信号ごとの説明

#### グローバル信号

| 信号 | 幅 | マスタ側 | スレーブ側 | 意味 | 出す値の決め方 | 変化タイミング |
|---|---|---|---|---|---|---|
| ACLK | 1 | input | input | バスのクロック | – | 全ての信号は立ち上がりが基準 |
| ARESETn | 1 | input | input | 0 でリセット (負論理) | – | リセット中の VALID の決まりは 2.2 を参照 |

#### Write address チャネル (AW)

AWREADY 以外はマネージャが出します。幅は DUT の信号一覧の値です。

| 信号 | 幅 | マスタ側 | スレーブ側 | 意味 | 出す値の決め方 | 変化タイミング |
|---|---|---|---|---|---|---|
| AWID | 4 | output | input | 書き込みの識別番号。B の BID で同じ値が返る | 順序を守りたい書き込みは同じ ID、独立なものは別 ID にする。同じ ID は出した順に応答が返り、別 ID は順不同。順序を気にしないなら固定値でもよい | AWVALID と一緒に出し、ハンドシェイクまで保持 |
| AWADDR | 32 | output | input | バーストの最初の転送のバイトアドレス | 先頭だけを出す (2 ビート目以降はサブオーディネートが計算)。WRAP は AWSIZE にアラインする。INCR / FIXED は非アラインの開始でもよい (WSTRB で示す)。バースト全体が 4KB 境界をまたいではいけない | 同上 |
| AWLEN | 8 | output | input | 転送回数 - 1 | INCR は 1〜256 回、WRAP は 2 / 4 / 8 / 16 回、FIXED は 16 回まで。途中で打ち切れないので、指定した回数は必ず送る | 同上 |
| AWSIZE | 3 | output | input | 1 転送のバイト数 = 2^AWSIZE | 64bit バスなら通常 3'b011 (8 バイト) で、これが上限 (データ幅を超えてはいけない)。狭い転送は 0〜2 | 同上 |
| AWBURST | 2 | output | input | アドレスの進め方 | 01 INCR (普通のメモリ)、00 FIXED (FIFO など同じアドレス)、10 WRAP (キャッシュラインの折り返し)。11 は予約で使えない | 同上 |
| AWLOCK | 1 | output | input | 0 = 通常、1 = 排他アクセス | 排他の書き込みだけ 1。排他アクセスでは、総バイト数を 2 のべき乗かつ 128 以下にし、アドレスを総バイト数にアラインし、16 ビート以下にする | 同上 |
| AWCACHE | 4 | output | input | メモリ属性。[0] Bufferable、[1] Modifiable、[2] Other Allocate、[3] Allocate | 書き込み先で決める。レジスタは 0000 (Device Non-bufferable) か 0001 (Device Bufferable)。キャッシュしないメモリは 0010 か 0011 (Normal Non-cacheable で、0011 は Bufferable)。[1]=0 なら [3:2] も 0 にする | 同上 |
| AWPROT  | 3 | output | input | 保護属性。[0] 1=特権、[1] 1=Non-secure、[2] 1=命令 | アクセス元のソフトやマネージャの権限で決める | 同上 |
| AWQOS  | 4 | output | input | 優先度。0 が最低、15 が最高 | QoS を使わないなら 0 | 同上 |
| AWREGION | 4 | output | input | リージョン番号。1 つの物理インターフェースを、最大 16 の論理インターフェースとして使うためのもの | 通常はインターコネクトがアドレスデコードの結果で作る。使わないなら 0 | 同上 |
| AWVALID | 1 | output | input | AW の信号が有効 | 出したい書き込みがあれば 1 | リセット後の立ち上がり以降に上げられる。AWREADY を待たずに上げ、ハンドシェイクまで下げない |
| AWREADY | 1 | input | output | AW を受け取れる | 待機中は 1 が推奨。その場合は、来たアドレスを必ず受け取れること (E A3.2.2) | VALID の前でも後でも上げてよい。AWVALID / WVALID を待ってもよい |

#### Write data チャネル (W)

WREADY 以外はマネージャが出します。

| 信号 | 幅 | マスタ側 | スレーブ側 | 意味 | 出す値の決め方 | 変化タイミング |
|---|---|---|---|---|---|---|
| WDATA | 64 | output | input | 書き込みデータ | 使うバイトレーンはアドレスと AWSIZE で決まる。狭い転送ではビートごとにレーンが変わる | WVALID と一緒に出し、ハンドシェイクまで保持。AXI4 には WID が無いので、W は AW と同じ順番で送る |
| WSTRB | 8 | output | input | WSTRB[n] が WDATA[8n+7:8n] の有効を示す | 書くバイトだけ 1。転送の範囲外のレーンは 0 | 同上。WVALID=0 の間は何でもよい (0 か前の値の保持を推奨、E A3.4.3) |
| WLAST | 1 | output | input | バーストの最後の転送 | AWLEN+1 ビート目だけ 1 | 最後のビートと一緒に出す |
| WVALID | 1 | output | input | W が有効 | データを出せるとき 1。AWREADY / WREADY を待ってはいけない | リセット中は 0。ハンドシェイクまで下げない |
| WREADY | 1 | input | output | W を受け取れる | 待機中に 1 にしてよいのは、いつでも 1 サイクルで受け取れる場合だけ | AWVALID / WVALID を待ってから上げてもよい |

#### Write response チャネル (B)

BREADY 以外はサブオーディネートが出します。

| 信号 | 幅 | マスタ側 | スレーブ側 | 意味 | 出す値の決め方 | 変化タイミング |
|---|---|---|---|---|---|---|
| BID | 4 | input | output | 応答する書き込みの ID (幅は AWID と同じ) | 対応する書き込みの AWID と同じ値。同じ ID は AW の順に返す | BVALID と一緒に出し、ハンドシェイクまで保持 |
| BRESP | 2 | input | output | 00 OKAY、01 EXOKAY、10 SLVERR、11 DECERR | 1 トランザクションに 1 つ。排他書き込みの成功は EXOKAY、失敗は OKAY。デコードできないアドレスはインターコネクトが DECERR を返す。排他でない書き込みに EXOKAY を返してはいけない | 同上 |
| BVALID | 1 | input | output | B が有効 | 応答を出せるとき 1 | AW と WLAST のビートの両方のハンドシェイクの後だけ。リセット中は 0 |
| BREADY | 1 | output | input | B を受け取れる | BVALID を待ってから上げてもよい。待機中 1 は、いつでも 1 サイクルで受け取れる場合だけ | 随時 |

#### Read address チャネル (AR)

ARREADY 以外はマネージャが出します。考え方は AW と同じです。

| 信号 | 幅 | マスタ側 | スレーブ側 | 意味 | 出す値の決め方 | 変化タイミング |
|---|---|---|---|---|---|---|
| ARID | 4 | output | input | 読み出しの識別番号。R の RID で同じ値が返る | AWID と同じ考え方 (同じ ID は出した順に応答、別 ID は順不同) | ARVALID と一緒に出し、ハンドシェイクまで保持 |
| ARADDR | 32 | output | input | 読み出しバーストの最初のバイトアドレス | AWADDR と同じ (WRAP はアライン、4KB 境界をまたがない) | 同上 |
| ARLEN | 8 | output | input | 転送回数 - 1 | AWLEN と同じ | 同上 |
| ARSIZE | 3 | output | input | 1 転送のバイト数 = 2^ARSIZE | AWSIZE と同じ | 同上 |
| ARBURST | 2 | output | input | アドレスの進め方 | AWBURST と同じ | 同上 |
| ARLOCK | 1 | output | input | 0 = 通常、1 = 排他アクセス | 排他の読み出しだけ 1。EXOKAY が返れば排他モニタが設定された。OKAY ならそのサブオーディネートは排他アクセスに対応していない | 同上 |
| ARCACHE | 4 | output | input | メモリ属性。[0] Bufferable、[1] Modifiable、[2] Allocate、[3] Other Allocate (AWCACHE と [3:2] の割り当てが逆、E A4.3.3) | 読み出し先のメモリの種類で決める (AWCACHE と同じ考え方) | 同上 |
| ARPROT | 3 | output | input | 保護属性 | AWPROT と同じ | 同上 |
| ARQOS | 4 | output | input | 優先度 | AWQOS と同じ | 同上 |
| ARREGION | 4 | output | input | リージョン番号 | AWREGION と同じ | 同上 |
| ARVALID | 1 | output | input | AR の信号が有効 | 出したい読み出しがあれば 1 | AWVALID と同じ |
| ARREADY | 1 | input | output | AR を受け取れる | 待機中は 1 が推奨 | VALID の前でも後でも上げてよい。ARVALID を待ってもよい |

#### Read data チャネル (R)

RREADY 以外はサブオーディネートが出します。

| 信号 | 幅 | マスタ側 | スレーブ側 | 意味 | 出す値の決め方 | 変化タイミング |
|---|---|---|---|---|---|---|
| RID | 4 | input | output | 読み出しデータの ID | 対応する ARID と同じ値。同じ ID は AR の順に返す。ID が違えば、ビート単位で交互に返してもよい | RVALID と一緒に出し、ハンドシェイクまで保持 |
| RDATA | 64 | input | output | 読み出しデータ | 有効なレーンはアドレスと ARSIZE で決まる | 同上 |
| RRESP | 2 | input | output | ビートごとの読み出し結果 | ビートごとに決める。エラーでも ARLEN+1 ビートを全部返す (E A3.4.4) | 同上 |
| RLAST | 1 | input | output | 最後のビート | ARLEN+1 ビート目だけ 1 | 同上 |
| RVALID | 1 | input | output | R が有効 | データを出せるとき 1 | AR のハンドシェイクの後だけ。リセット中は 0 |
| RREADY | 1 | output | input | R を受け取れる | 待機中 1 は、すぐ受け取れる場合だけ | 随時 |

### 2.6 値の例 (64bit バス)

```text
// 0x0000_1000 から 64 バイトを書く (8 ビート x 8 バイト)
AWADDR   = 32'h0000_1000
AWLEN    = 8'd7          // 8 ビート
AWSIZE   = 3'b011        // 8 バイト / ビート
AWBURST  = 2'b01         // INCR
AWLOCK   = 1'b0
AWCACHE  = 4'b0011       // Normal Non-cacheable Bufferable
AWPROT   = 3'b000        // 非特権 / Secure / データ (TrustZone を使うなら [1] をシステムに合わせる)
AWQOS    = 4'h0
AWREGION = 4'h0
WSTRB    = 8'hFF (全ビート)、WLAST は 8 ビート目だけ 1

// 0x0000_1004 に 4 バイトを 1 回書く (狭い転送)
AWADDR   = 32'h0000_1004
AWLEN    = 8'd0
AWSIZE   = 3'b010        // 4 バイト
WDATA    = {32'h1234_5678, 32'h0000_0000}   // レーン 4〜7 を使う
WSTRB    = 8'hF0
WLAST    = 1'b1
```

---

## 3. APB (APB4)

### 3.1 共通の変化タイミング

- **状態の進み方:** IDLE → SETUP → ACCESS と進みます。SETUP は PSELx=1・PENABLE=0 の 1 サイクルだけで、次が ACCESS (PENABLE=1) です。PREADY=1 で ACCESS が終わり、続く転送があれば SETUP へ、無ければ IDLE に戻ります (APB 4.1)。
- **保持:** SETUP から ACCESS へ移るときと、ACCESS の待ちの間は、PADDR / PPROT / PWRITE / PWDATA / PSTRB を変えません (APB 4.1)。
- **有効なとき:** PSEL は常に有効です。PADDR などは PSEL=1 の間、PREADY は PSEL と PENABLE が 1 の間、PRDATA / PSLVERR は PSEL・PENABLE・PREADY が全て 1 のサイクルで有効です。有効でなくてよい信号は 0 にすることが推奨されています (APB 付録 A)。

### 3.2 タイミングの例

```text
edge      1  2  3  4  5  6      (write A with 1 wait state, then read B without wait)
PSEL      1  1  1  1  1  0      stays HIGH for the next transfer to the same completer
PENABLE   0  1  1  0  1  0      SETUP at 1 and 4, ACCESS at 2, 3 and 5
PWRITE    1  1  1  0  0  .
PADDR     A  A  A  B  B  .      held from SETUP to the end of ACCESS
PWDATA    D  D  D  .  .  .
PREADY    .  0  1  .  1  .      write ends at 3, read ends at 5 (ignored while PENABLE=0)
PRDATA    .  .  .  .  Q  .      valid only when PSEL, PENABLE and PREADY are HIGH
```

### 3.3 ビット幅の決め方

| 信号 | 幅 | 決め方 |
|---|---|---|
| PADDR | ADDR_WIDTH (32 まで) | 周辺回路群のアドレス空間 |
| PWDATA / PRDATA | 8 / 16 / 32 | 周辺回路のレジスタ幅 |
| PSTRB | データ幅 / 8 | 1 バイトに 1 ビット |
| PPROT | 3 | 仕様で固定 |
| その他 | 1 | |

### 3.4 信号ごとの説明

| 信号 | マスタ側 | スレーブ側 | 意味 | 出す値の決め方 | 変化タイミング |
|---|---|---|---|---|---|
| PCLK | input | input | バスのクロック | – | 全ての信号は立ち上がりが基準 |
| PRESETn | input | input | 0 でリセット (負論理) | – | – |
| PSELx | output | input | そのコンプリータを選ぶ | アドレスをデコードし、アクセス先の 1 本だけ 1 | SETUP で 1 にし、転送が終わると 0 (同じコンプリータに続けるなら 1 のまま) |
| PENABLE | output | input | 転送の 2 サイクル目以降 | SETUP の次のサイクルから 1 | 転送が終わったら 0。次の転送は必ず SETUP から |
| PADDR | output | input | バイトアドレス | レジスタのアドレス。データ幅にアラインする (非アラインは結果が不定、APB 2.1.1) | SETUP で出し、転送の終わりまで保持 |
| PWRITE | output | input | 1 = 書き込み、0 = 読み出し | 転送の向き | 同上 |
| PWDATA | output | input | 書き込みデータ | 書き込みのときだけ意味を持つ | 同上 |
| PSTRB | output | input | 書くバイトレーン (PSTRB[n] が PWDATA[8n+7:8n]) | 書くバイトだけ 1。読み出しでは全て 0 (APB 3.2) | 同上 |
| PPROT | output | input | [0] 1=特権、[1] 1=Non-secure、[2] 1=命令 (ヒント) | 主な用途は Secure / Non-secure の区別。持たない場合の既定は 000 | 同上 |
| PREADY | input | output | 1 で転送を終え、0 で ACCESS を延ばす | 応答できたら 1。待ちの要らない周辺回路は 1 に固定してよい (APB 3.1.2) | PENABLE=1 の間だけ意味を持つ (PENABLE=0 の間は何でもよい) |
| PRDATA | input | output | 読み出しデータ | 読み出しの終わりまでに出す | PSEL・PENABLE・PREADY が全て 1 のサイクルで有効 |
| PSLVERR | input | output | エラー応答 (省略可) | エラーなら 1。書き込みエラーでもレジスタが変わっていないとは限らず、読み出しエラーのデータは無効でよい。持たないコンプリータの分は、リクエスタ側の入力を 0 に固定する | 最後のサイクルだけ有効。それ以外は 0 が推奨 (APB 3.4) |

### 3.5 APB5 で追加された信号

- PWAKEUP : 活動の予告。PSELx より 1 サイクル以上前に上げることが推奨 (APB 3.7)
- PNSE : RME 用
- PAUSER などのユーザ信号
- パリティ

### 3.6 値の例 (32bit バス)

```text
// 0x0000_0010 のレジスタに 32bit を書く
PADDR  = 32'h0000_0010
PWRITE = 1'b1
PWDATA = 32'h0000_00A5
PSTRB  = 4'b1111        // 下位 16bit だけなら 4'b0011
PPROT  = 3'b000         // 非特権 / Secure / データ (Non-secure の系なら [1]=1)

// 読み出しでは
PWRITE = 1'b0
PSTRB  = 4'b0000
```

---

## 4. AHB5

### 4.1 共通の変化タイミング

- **2 段の転送:** 転送はアドレスフェーズとデータフェーズの 2 段です。次の転送のアドレスフェーズは、今の転送のデータフェーズと重なります (AHB 3.1)。
- **HREADY=1 の立ち上がり:** 今のデータフェーズが終わり、次のアドレスフェーズが取り込まれます。サブオーディネートが HSELx・アドレス・制御を取り込むのは、HREADY=1 のときだけです (AHB-Lite 4.1)。
- **待ち (HREADY=0) の間:**
  - マネージャは HWDATA を保持します (AHB 6.1.1)。
  - アドレスフェーズの信号も原則保持します。例外は、IDLE→NONSEQ への変更 (変えた後は保持)、固定長バーストの BUSY→SEQ、長さ未定のバーストの BUSY からの変更、ERROR 応答の後です (AHB 3.7)。
- **バーストの間一定:** HSIZE / HWRITE / HPROT / HNONSEC は、バーストの間変えません。
- **リセット:**
  - 非同期でアサートし、HCLK の立ち上がりの後に同期で解除します。
  - リセット中は、マネージャが HTRANS=IDLE、サブオーディネートが HREADYOUT=1 にします (AHB-Lite 7.1.2)。

### 4.2 タイミングの例

```text
edge      1     2     3     4     5      (write A with 1 wait state, then read B)
HTRANS    NSEQ  NSEQ  NSEQ  IDLE  .      address phase of A at 1; B is held at 2 and 3
HADDR     A     B     B     .     .
HWRITE    1     0     0     .     .
HWDATA    .     DA    DA    .     .      data phase of A: held until HREADY is HIGH
HREADY    1     0     1     1     .      A waits at 2 and completes at 3
HRDATA    .     .     .     DB    .      B completes at 4
```

### 4.3 ビット幅の決め方

| 信号 | 幅 | 決め方 |
|---|---|---|
| HADDR | ADDR_WIDTH | 10〜64 を推奨 (以前の版は 32 固定) |
| HWDATA / HRDATA | DATA_WIDTH | 8〜1024 (32 未満と 256 超は非推奨) |
| HWSTRB | DATA_WIDTH / 8 | Write_Strobes を持つ場合だけ |
| HBURST | 0 か 3 | バーストを出さないマネージャは持たなくてよい |
| HPROT | 0 / 4 / 7 | 4 = AHB-Lite 相当、7 = Extended_Memory_Types |
| HMASTER | HMASTER_WIDTH | 0〜8 を推奨。区別したいマネージャ / スレッドの数で決める |
| HTRANS / HSIZE | 2 / 3 | 仕様で固定 |
| その他 (HRESP を含む) | 1 | |

### 4.4 信号ごとの説明

| 信号 | マスタ側 | スレーブ側 | 意味 | 出す値の決め方 | 変化タイミング |
|---|---|---|---|---|---|
| HCLK | input | input | バスのクロック | – | 全ての信号は立ち上がりが基準 |
| HRESETn | input | input | 0 でリセット (唯一の負論理の信号) | – | 非同期でアサート、同期で解除 |
| HADDR | output | input | バイトアドレス | 転送ごとに出し、HSIZE にアラインする。バーストの 2 ビート目以降もマネージャが出す (WRAP は折り返す)。INCR のバーストは 1KB 境界をまたがない (AHB 3.6) | アドレスフェーズ |
| HTRANS | output | input | 00 IDLE / 01 BUSY / 10 NONSEQ / 11 SEQ | 転送が無ければ IDLE、単発やバーストの最初は NONSEQ、続きは SEQ、バーストの途中で休むときは BUSY | アドレスフェーズ |
| HWRITE | output | input | 1 = 書き込み | 転送の向き | バーストの間一定 |
| HSIZE | output | input | 000=8bit、001=16、010=32、011=64 … 111=1024 | データ幅以下 | バーストの間一定 |
| HBURST | output | input | 000 SINGLE / 001 INCR (長さ未定) / 010 WRAP4 / 011 INCR4 / 100 WRAP8 / 101 INCR8 / 110 WRAP16 / 111 INCR16 | 長さが決まっていれば固定長、決まっていなければ INCR | バーストの間一定 |
| HPROT | output | input | [0] 1=データ、[1] 1=特権、[2] Bufferable、[3] Modifiable、[4] Lookup、[5] Allocate、[6] Shareable | 正確な値を作れないマネージャは 4'b0011 (Non-cacheable・Non-bufferable・特権・データ、AHB 3.8) | バーストの間一定 |
| HMASTLOCK | output | input | ロックされた一連の転送 | 分けられては困る一連のアクセスで 1。同じサブオーディネートの領域に限り、最後は IDLE で終える (AHB 3.3) | アドレスフェーズ |
| HNONSEC | output | input | 1 = Non-secure、0 = Secure | アクセス元の状態 | バーストの間一定 |
| HEXCL | output | input | 排他アクセスの転送 | Load / Store-Exclusive の単発の転送で 1 | アドレスフェーズ |
| HMASTER | output | input | マネージャ / スレッドの識別番号 | 排他スレッドを持つマネージャが出し、インターコネクトが一意になるよう変える | アドレスフェーズ |
| HWDATA | output | input | 書き込みデータ | 有効なレーンは HADDR と HSIZE で決まる | データフェーズ。HREADY=1 まで保持 |
| HWSTRB | output | input | 有効なレーンのうち、実際に書くバイト | 書かないバイトは 0 (全部 0 も可)。有効なレーンの外は 0 でも 1 でもよい。読み出しでは 0 が推奨 (AHB 3.5) | データフェーズ。ビートごとに変えてよい |
| HSELx | – | input | 転送がそのサブオーディネート宛て (デコーダが出す) | HADDR をデコードする。どこにも当たらないアドレスはデフォルトのサブオーディネートが受け、NONSEQ / SEQ には ERROR、IDLE / BUSY には OKAY を返す (AHB 4.2.1) | アドレスと同じサイクル |
| HREADYOUT | – (HREADY として受ける) | output | 1 = 完了、0 = 延ばす (マルチプレクサで選ばれて HREADY になる) | 待ちが要る間だけ 0。IDLE / BUSY には待ち無しの OKAY を返す (AHB 3.2) | データフェーズ。リセット中は 1。待ちは 16 サイクル以下が推奨 (AHB-Lite 5.1.2) |
| HRESP | input | output | 0 OKAY / 1 ERROR (マルチプレクサを通ってマスタに届く) | ERROR は 2 サイクル (1 サイクル目は HREADYOUT=0、2 サイクル目は 1)。待ちの間は OKAY (AHB 5.1) | データフェーズ |
| HRDATA | input | output | 読み出しデータ (マルチプレクサを通ってマスタに届く) | OKAY のときだけ必要 | データフェーズの最後 (HREADY=1) だけ有効 (AHB 6.1.2) |
| HEXOKAY | input | output | 排他アクセスの成功 (マルチプレクサを通ってマスタに届く) | 成功なら 1。失敗した排他書き込みはメモリを書かない。排他でない転送と ERROR では 0 | データフェーズの最後 |
| HREADY | input | input | 前の転送の完了 (マルチプレクサが出し、マスタと全てのスレーブが受ける) | データフェーズ中のサブオーディネートの HREADYOUT を選ぶ (直結なら同じ信号) | データフェーズ |

### 4.5 値の例 (32bit バス)

```text
// 0x2000_0004 に 32bit を 1 回書く
HTRANS = 2'b10          // NONSEQ
HADDR  = 32'h2000_0004
HWRITE = 1'b1
HSIZE  = 3'b010         // 32bit
HBURST = 3'b000         // SINGLE
HPROT  = 4'b0011
// 次のサイクル (データフェーズ)
HWDATA = 32'h1234_5678
HWSTRB = 4'b1111

// 0x2000_0010 から INCR4 で読む
HTRANS = NONSEQ, SEQ, SEQ, SEQ
HADDR  = 32'h2000_0010, 32'h2000_0014, 32'h2000_0018, 32'h2000_001C
HBURST = 3'b011         // INCR4
```

---

## 5. AXI4-Lite

### 5.1 AXI4 との違い

信号の意味とタイミングの規則 (ハンドシェイク、リセット、B は AW と W の後、R は AR の後) は AXI4 と同じです。違いは次のとおりです。

- **1 ビートだけ:** 転送は全て 1 ビートで、データは常にバス幅いっぱい (32bit か 64bit) です。AxLEN / AxSIZE / AxBURST / WLAST / RLAST はありません。
- **属性:** 全て Non-modifiable・Non-bufferable で、排他アクセスもありません。AxCACHE / AxLOCK は無く、EXOKAY も使いません。
- **ID が無い:** 応答は全て順番どおりに返します。AXI4 の系につなぐときは、インターコネクトなどが ID を返します。
- **読み書きの順序:** 書き込みと読み出しの間の順序は決まっていません。書いた値を読み戻すときは、B を受け取ってから AR を出します。

### 5.2 信号ごとの説明

| 信号 | マスタ側 | スレーブ側 | 幅の決め方 | 出す値の決め方 | 変化タイミング |
|---|---|---|---|---|---|
| ACLK / ARESETn | input | input | 1 | – (クロックと負論理のリセット) | AXI4 と同じ |
| AWADDR / ARADDR | output | input | アドレス空間 | レジスタのアドレス。普通はデータ幅にアラインし、書くバイトは WSTRB で選ぶ | VALID と一緒に出し、ハンドシェイクまで保持 |
| AWPROT / ARPROT | output | input | 3 (固定) | AXI4 と同じ ([0] 特権、[1] Non-secure、[2] 命令) | 同上 |
| AWVALID / ARVALID | output | input | 1 | 出したいアクセスがあれば 1 | リセット後の立ち上がり以降に上げる。READY を待たずに上げ、ハンドシェイクまで下げない |
| AWREADY / ARREADY | input | output | 1 | 受け取れるとき 1 (待機中は 1 が推奨) | VALID を待ってから上げてもよい |
| WDATA | output | input | 32 か 64 | 書き込みデータ | WVALID と一緒に出し、保持。W は AW より先でもよい |
| WSTRB | output | input | 4 か 8 | 書くバイトだけ 1 | 同上 |
| WVALID | output | input | 1 | データを出せるとき 1 | AXI4 と同じ |
| WREADY | input | output | 1 | 受け取れるとき 1 | AXI4 と同じ |
| BRESP | input | output | 2 | 00 OKAY / 10 SLVERR / 11 DECERR | AW と W の両方を受け取った後でだけ出せる |
| BVALID | input | output | 1 | 応答を出せるとき 1 | AXI4 と同じ |
| BREADY | output | input | 1 | 受け取れるとき 1 | AXI4 と同じ |
| RDATA / RRESP | input | output | 32 か 64 / 2 | 読み出しデータと結果 (EXOKAY は使わない) | AR を受け取った後でだけ出せる |
| RVALID | input | output | 1 | データを出せるとき 1 | AXI4 と同じ |
| RREADY | output | input | 1 | 受け取れるとき 1 | AXI4 と同じ |

### 5.3 タイミングの例

```text
edge      1  2  3  4
WVALID    1  0  .  .
WREADY    1  .  .  .      W accepted at 1 (W before AW is allowed)
AWVALID   0  1  0  .
AWREADY   .  1  .  .      AW accepted at 2
BVALID    0  0  1  0      only after both W (1) and AW (2)
BREADY    .  .  1  .      B accepted at 3
```

---

## 7. 参考資料

- [AMBA AXI and ACE Protocol Specification IHI 0022E (Arm)](https://documentation-service.arm.com/static/5f915b62f86e16515cdc3b1c)
- [AMBA AXI and ACE Protocol Specification IHI 0022H (Arm)](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)
- [AMBA AXI Protocol Specification IHI 0022J (Arm)](https://documentation-service.arm.com/static/63ff0ebd56ea36189d4e7ee7)
- [AMBA APB Protocol Specification IHI 0024E (Arm)](https://documentation-service.arm.com/static/63fe2c1356ea36189d4e79f3)
- [AMBA AHB Protocol Specification IHI 0033C (Arm)](https://documentation-service.arm.com/static/6141bf0d674a052ae36ca811)
- [AMBA 5 AHB Protocol Specification IHI 0033B.b (Arm)](https://documentation-service.arm.com/static/5f91607cf86e16515cdc3b4b)
- [AMBA 3 AHB-Lite Protocol Specification IHI 0033A (ミシガン大学に置かれた写し)](https://web.eecs.umich.edu/~prabal/teaching/eecs373-f12/readings/ARM_IHI0033A_AMBA_AHB-Lite_SPEC.pdf)
- [Learn the architecture - An introduction to AMBA AXI (Arm 102202)](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/102202_0100_01_Introduction_to_AMBA_AXI.pdf?revision=369ad681-f926-47b0-81be-42813d39e132)
- [AXI Protocol Checks and Descriptions (AMD PG101)](https://docs.amd.com/r/en-US/pg101-axi-protocol-checker/AXI-Protocol-Checks-and-Descriptions)
- [AXI4-Lite protocol specification support (Intel)](https://intel.com/content/www/us/en/docs/programmable/683609/24-1/lite-protocol-specification-support.html)
- [Why AXI4 changed the definition of AxCACHE? (Arm Community)](https://community.arm.com/support-forums/f/embedded-forum/12063/why-axi4-changed-the-definition-of-axcache)
- [AXI ID problem for cascaded interconnect design (Arm Community)](https://community.arm.com/support-forums/f/armds-forum/800/axi-id-problem-for-cascaded-interconnect-design)
- [AXI4 transaction : AXI4-Lite と ID (Arm Community)](https://community.arm.com/support-forums/f/soc-design-and-simulation-forum/56445/axi4-transaction/185454)
- [axi_xbar : ID 幅の拡張の例](https://github.com/Aquaticfuller/axi/blob/master/doc/axi_xbar.md)
- [AHB exclusive transfers (vlsiverify)](https://vlsiverify.com/protocols/ahb/exclusive-transfers/)
- [Advanced eXtensible Interface (Wikipedia)](https://en.wikipedia.org/wiki/Advanced_eXtensible_Interface)
- [Cadence Simulation VIP for AMBA](https://www.cadence.com/en_US/home/tools/system-design-and-verification/verification-ip/simulation-vip/amba.html)
- [Cadence Formal VIP for Arm AMBA](https://www.cadence.com/en_US/home/tools/system-design-and-verification/verification-ip/formal-vip/amba-arm.html)
- [Synopsys Verification IP for Arm AMBA](https://www.synopsys.com/verification/verification-ip/amba.html)

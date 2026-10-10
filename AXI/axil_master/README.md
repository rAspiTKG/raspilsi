# AXI4-Lite マスタ + 内部メモリ (`axil_master_mem`)

AXI4-Lite マスタ (Manager)。モジュール内のメモリ (汎用レジスタ) と AXI4-Lite の間で、コマンド 1 つにつき
連続したワードをまとめて転送する。**書き込みコマンドと読み出しコマンドは別々に受け付け、同時に実行できる。**

```
  mem_w_* (ローカル書き込み) --> [内部メモリ 1R1W  MEM_DEPTH ワード] --> mem_r_* (ローカル読み出し)
                                      |  ^
                   書き込みコマンドが読む v  |  読み出しコマンドが書く
  wcmd_* / wr_* --> [書き込みシーケンサ] --+--> [axil_master_engine] --> AW / W  -->
  rcmd_* / rd_* --> [読み出しシーケンサ] --+                           <-- B      <--
                                                                     --> AR     -->
                                                                     <-- R      <--
                                                         axi_wakeup --> (AXI5 の AWAKEUP 用)
```

- 書き込みコマンド: 内部メモリの `[wcmd_mem_addr から wcmd_len ワード]` を、AXI の `wcmd_addr` から順に書く
- 読み出しコマンド: AXI の `rcmd_addr` から `rcmd_len` ワード読み、内部メモリの `[rcmd_mem_addr から]` に入れる
- 応答を待たずに、書き込み / 読み出しそれぞれ `MAX_WR_OUTSTANDING` / `MAX_RD_OUTSTANDING` 個までトランザクションを出す
- 内部メモリは、ローカルポート (`mem_w_*` / `mem_r_*`) から読み書きする
- 言語: SystemVerilog (`always @(posedge aclk ...)` / `always @(*)` で記述)
- クロック / リセット: `aclk`、非同期リセット `aresetn` (負論理)。解除は `aclk` に同期させること (下の「使用上の制約」)
- Arm CoreLink NI-700 など、AXI4-Lite に対応していない AXI4 / AXI5 のスレーブポートには、
  同梱の `axil_to_axi4` を通してつなぐ (下の「AXI4 / AXI5 (NI-700) へのつなぎ方」)

## ファイル構成

```
rtl/
  axil_master_mem.sv       ... トップ (内部メモリ + 書き込み / 読み出しシーケンサ + 転送エンジン)
  axil_master_engine.sv    ... AXI4-Lite マスタの転送エンジン (要求 1 つ = トランザクション 1 つ)。単体でも使える
  axil_master_rs.sv        ... レジスタスライス (AW / W / AR の出力用。VALID とペイロードを FF から直接出す)
  axil_master_sram_2p.sv   ... 内部メモリの動作モデル (1R1W。FF になる。大きければマクロに置き換える)
  axil_to_axi4.sv          ... AXI4-Lite → AXI4 (+ AXI5 の AWAKEUP) の変換 (固定値を出すだけ)
  filelist.f               ... 上記のコンパイル順
tb/
  tb_axil_master_mem.sv    ... トップ (+ axil_to_axi4) の簡易 TB (自己チェック)
  tb_axil_master_engine.sv ... エンジン単体の TB
  axil_slave_mem_model.sv  ... 検証用 AXI4-Lite スレーブ + メモリ (プロトコルチェック付き)
sim/
  Makefile                 ... Verilator 5.x 用 (エンジン 7 構成 + トップ 8 構成)
uvm/                       ... Verilator + UVM 環境
  README.md  tb/  sim/
```

## parameter 一覧

| parameter | 既定値 | 内容 |
| --- | --- | --- |
| `ADDR_WIDTH` | 32 | `AWADDR` / `ARADDR` のビット幅 (log2(`DATA_WIDTH`/8) .. 64) |
| `DATA_WIDTH` | 32 | `WDATA` / `RDATA` のビット幅 (AXI4-Lite なので 32 / 64) |
| `MEM_DEPTH` | 16 | 内部メモリのワード数 (1 ワード = `DATA_WIDTH` ビット)。1 コマンドの最大ワード数でもある |
| `MAX_WR_OUTSTANDING` | 4 | 応答 (B) を待たずに出せる書き込みの数 (1 以上) |
| `MAX_RD_OUTSTANDING` | 4 | 応答 (R) を待たずに出せる読み出しの数 (1 以上) |
| `STOP_ON_ERROR` | 1 | 1 = エラー応答を受けたら、それ以降のトランザクションを出さない / 0 = 最後まで続ける |

`axil_to_axi4` の parameter は `ADDR_WIDTH` / `DATA_WIDTH` / `ID_WIDTH` (既定 4) / `QOS` (既定 4'b0000)。

範囲外の値を指定すると、エラボレーション時の `$error` で止まる (IEEE 1800 20.11)。
対応していない合成ツールでは `+define+AXIL_MASTER_NO_ELAB_CHECK` で外せる。

## ポート

| グループ | 信号 | 内容 |
| --- | --- | --- |
| 書き込みコマンド | `wcmd_valid` / `wcmd_ready` | valid/ready。書き込み側がアイドルのときだけ `wcmd_ready=1` |
| | `wcmd_addr` | AXI の先頭アドレス (`DATA_WIDTH/8` バイトの倍数) |
| | `wcmd_incr` | 1 = 1 トランザクションごとにアドレスを `DATA_WIDTH/8` 進める / 0 = 同じアドレスに繰り返す |
| | `wcmd_mem_addr` | 内部メモリの先頭ワード番号 |
| | `wcmd_len` | トランザクション数 (0 なら何もせず完了) |
| | `wcmd_strb` / `wcmd_prot` | `WSTRB` / `AWPROT` (全トランザクションで共通) |
| 書き込みステータス | `wr_busy` / `wr_done` / `wr_done_err` | `wr_done` は 1 サイクル。以下は `wr_done` と同じサイクルで見る (次のコマンド受付まで保持) |
| | `wr_err_flags[3:0]` | [0] SLVERR / [1] DECERR / [2] コマンドの誤り / [3] EXOKAY (AXI4-Lite では返してはいけない応答) |
| | `wr_err_index` | 最初にエラー応答を受けたトランザクションの番号 (0 始まり)。`wr_err_flags` の [0] [1] [3] のとき有効 |
| | `wr_done_count` | 応答を受けたトランザクションの数 (= バスで完了した数) |
| 読み出しコマンド / ステータス | `rcmd_*` / `rd_*` | 書き込みと同じ (`rcmd_strb` は無い。`ARPROT` は `rcmd_prot`) |
| ローカル書き込み | `mem_w_valid` / `mem_w_ready` | valid/ready。**読み出しコマンドの実行中** (`rd_busy=1`) は `mem_w_ready=0` |
| | `mem_w_addr` / `mem_w_data` | ワード番号 / 書き込みデータ |
| ローカル読み出し | `mem_r_valid` / `mem_r_ready` | valid/ready。**書き込みコマンドの実行中** (`wr_busy=1`) は `mem_r_ready=0` |
| | `mem_r_addr` | ワード番号 |
| | `mem_r_rvalid` / `mem_r_rdata` | 読み出しを受け付けた次のサイクルに `mem_r_rvalid=1` とデータ |
| | `axi_wakeup` | 要求を受けてから全ての応答を受けるまで 1 (レジスタ出力)。AXI5 の `AWAKEUP` 用。AXI4-Lite だけなら未接続でよい |
| AXI4-Lite | `m_axi_aw*` / `m_axi_w*` / `m_axi_b*` / `m_axi_ar*` / `m_axi_r*` | `AWADDR` `AWPROT` `AWVALID` `AWREADY` `WDATA` `WSTRB` `WVALID` `WREADY` `BRESP` `BVALID` `BREADY` `ARADDR` `ARPROT` `ARVALID` `ARREADY` `RDATA` `RRESP` `RVALID` `RREADY` |

ポート宣言の抜粋 (`rtl/axil_master_mem.sv`):

```systemverilog
module axil_master_mem #(
  parameter int unsigned ADDR_WIDTH         = 32
 ,parameter int unsigned DATA_WIDTH         = 32
 ,parameter int unsigned MEM_DEPTH          = 16
 ,parameter int unsigned MAX_WR_OUTSTANDING = 4
 ,parameter int unsigned MAX_RD_OUTSTANDING = 4
 ,parameter bit          STOP_ON_ERROR      = 1'b1
) (
  input  logic                                                 aclk
 ,input  logic                                                 aresetn
 ,input  logic                                                 wcmd_valid
 ,output logic                                                 wcmd_ready
 ,input  logic [ADDR_WIDTH-1:0]                                wcmd_addr
 ,input  logic                                                 wcmd_incr
 ,input  logic [((MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH))-1:0]   wcmd_mem_addr
 ,input  logic [((MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1))-1:0] wcmd_len
 ,input  logic [(DATA_WIDTH/8)-1:0]                            wcmd_strb
 ,input  logic [2:0]                                           wcmd_prot
 ,output logic                                                 wr_busy
 ,output logic                                                 wr_done
 ,output logic                                                 wr_done_err
 ,output logic [3:0]                                           wr_err_flags
 ,output logic [((MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1))-1:0] wr_err_index
 ,output logic [((MEM_DEPTH<1) ? 1 : $clog2(MEM_DEPTH+1))-1:0] wr_done_count
  ...  (読み出しコマンド / ステータス、ローカルポートは同じ形)
 ,output logic                                                 axi_wakeup
 ,output logic [ADDR_WIDTH-1:0]                                m_axi_awaddr
  ...  (AXI4-Lite の 19 本)
);
```

接続例 (`axil_master_mem` + `axil_to_axi4`、メモリ 32 ワード。この記述を含むモジュールは
`verilator --lint-only -Wall` で警告が出ないことを確認している):

```systemverilog
  axil_master_mem #(
    .ADDR_WIDTH(32)
   ,.DATA_WIDTH(32)
   ,.MEM_DEPTH(32)
   ,.MAX_WR_OUTSTANDING(4)
   ,.MAX_RD_OUTSTANDING(4)
   ,.STOP_ON_ERROR(1'b1)
  ) u_axil_master (
    .aclk(aclk)
   ,.aresetn(aresetn)
    // 書き込みコマンド / ステータス
   ,.wcmd_valid(wcmd_valid)
   ,.wcmd_ready(wcmd_ready)
   ,.wcmd_addr(wcmd_addr)
   ,.wcmd_incr(wcmd_incr)
   ,.wcmd_mem_addr(wcmd_mem_addr)        // 5 ビット (0..31)
   ,.wcmd_len(wcmd_len)                  // 6 ビット (0..32)
   ,.wcmd_strb(wcmd_strb)
   ,.wcmd_prot(wcmd_prot)
   ,.wr_busy(wr_busy)
   ,.wr_done(wr_done)
   ,.wr_done_err(wr_done_err)
   ,.wr_err_flags(wr_err_flags)
   ,.wr_err_index(wr_err_index)          // 6 ビット
   ,.wr_done_count(wr_done_count)        // 6 ビット
    // 読み出しコマンド / ステータス
   ,.rcmd_valid(rcmd_valid)
   ,.rcmd_ready(rcmd_ready)
   ,.rcmd_addr(rcmd_addr)
   ,.rcmd_incr(rcmd_incr)
   ,.rcmd_mem_addr(rcmd_mem_addr)
   ,.rcmd_len(rcmd_len)
   ,.rcmd_prot(rcmd_prot)
   ,.rd_busy(rd_busy)
   ,.rd_done(rd_done)
   ,.rd_done_err(rd_done_err)
   ,.rd_err_flags(rd_err_flags)
   ,.rd_err_index(rd_err_index)
   ,.rd_done_count(rd_done_count)
    // 内部メモリのローカルポート
   ,.mem_w_valid(mem_w_valid)
   ,.mem_w_ready(mem_w_ready)
   ,.mem_w_addr(mem_w_addr)
   ,.mem_w_data(mem_w_data)
   ,.mem_r_valid(mem_r_valid)
   ,.mem_r_ready(mem_r_ready)
   ,.mem_r_addr(mem_r_addr)
   ,.mem_r_rvalid(mem_r_rvalid)
   ,.mem_r_rdata(mem_r_rdata)
   ,.axi_wakeup(axi_wakeup)
    // AXI4-Lite (axil_to_axi4 へ。AXI4-Lite のスレーブなら直接つなぐ)
   ,.m_axi_awaddr(l_awaddr)
   ,.m_axi_awprot(l_awprot)
   ,.m_axi_awvalid(l_awvalid)
   ,.m_axi_awready(l_awready)
   ,.m_axi_wdata(l_wdata)
   ,.m_axi_wstrb(l_wstrb)
   ,.m_axi_wvalid(l_wvalid)
   ,.m_axi_wready(l_wready)
   ,.m_axi_bresp(l_bresp)
   ,.m_axi_bvalid(l_bvalid)
   ,.m_axi_bready(l_bready)
   ,.m_axi_araddr(l_araddr)
   ,.m_axi_arprot(l_arprot)
   ,.m_axi_arvalid(l_arvalid)
   ,.m_axi_arready(l_arready)
   ,.m_axi_rdata(l_rdata)
   ,.m_axi_rresp(l_rresp)
   ,.m_axi_rvalid(l_rvalid)
   ,.m_axi_rready(l_rready)
  );
```

`axil_to_axi4` の接続は `rtl/axil_to_axi4.sv` のポート名どおり (`s_axi_*` に上の `l_*` と `axi_wakeup`、`m_axi_*` を相手の AXI4 / AXI5 ポートへ)。

コマンドのタイミング (書き込みも読み出しも同じ。サイクル 0 の終わりのクロックエッジで `wcmd_valid && wcmd_ready` が成立):

```
サイクル      0    1    2   ...  n    n+1
wcmd_valid    1    0    0   ...  0    0
wcmd_ready    1    0    0   ...  0    1     受付後は完了まで 0
wr_busy       0    1    1   ...  1    0
wr_done       0    0    0   ...  1    0     wr_busy の最終サイクルに 1 サイクルだけ 1
wr_err_flags  -    -    -   ...  E    E     wr_done と同じサイクルで見る (次の受付まで保持)
```

`n` の値は下の「転送速度」を参照。書き込み側と読み出し側は独立していて、片方の実行中にもう片方のコマンドをすぐ受け付ける。

ローカルポートのタイミング (サイクル 0 と 1 で読み出し、サイクル 1 と 2 で書き込みを受け付けた場合):

```
サイクル      0    1    2    3
mem_r_valid   1    1    0    0
mem_r_ready   1    1    1    1     書き込みコマンドの実行中だけ 0
mem_r_addr    A0   A1   -    -
mem_r_rvalid  0    1    1    0     読み出しを受け付けた次のサイクルだけ 1
mem_r_rdata   -    D0   D1   -     mem_r_rvalid=1 のサイクルだけ有効
mem_w_valid   0    1    1    0
mem_w_ready   1    1    1    1     読み出しコマンドの実行中だけ 0
```

ローカルの書き込みと読み出しは同じサイクルにも出せる。
コマンドを受け付けるサイクルはまだアイドルなので、同じサイクルに出したローカルアクセスも受け付ける。
書き込みコマンドと同じサイクルのローカル書き込みは、そのコマンドが送るデータに反映される。

## 動作

1. コマンドを受けると内容を検査する。誤りがあればトランザクションを出さずに `*_err_flags[2]` で返す
2. 書き込み: 内部メモリから 1 ワードずつ読んで 2 段の FIFO に入れ、エンジンへ渡す。エンジンは AW と W を同時に出す
3. 読み出し: AR を出し続け、R を受けるたびに `RDATA` を内部メモリに書く (OKAY のときだけ)
4. 全てのトランザクションの応答を受けたら `*_done`

### AXI4-Lite 側の振る舞い

- `AWVALID` / `WVALID` / `ARVALID` とアドレス / データは、レジスタスライスの FF から直接出す。
  VALID は READY まで下げず、その間ペイロードも変えない
  (IHI 0022 L A2.3: "When VALID is asserted, it must remain asserted until the handshake occurs")
- AW と W は同じ要求から同時に出し、それぞれ独立に READY を待つ。AWREADY を待ってから WVALID を出す作りではない
  (A2.3.2.1: "The Manager must not wait for the Subordinate to assert AWREADY or WREADY before asserting AWVALID or WVALID")。
  スレーブが「W を受けてから AWREADY」「AW を受けてから WREADY」のどちらでもデッドロックしない (TB で確認)
- `BREADY` / `RREADY` は常に 1 (応答を待たせない)
- 応答を待たずに `MAX_*_OUTSTANDING` 個まで出す。AXI4-Lite には ID が無いので、応答は出した順に返る前提
- 書き込みと読み出しは同時に動き、**互いの順序は保証しない** (AXI でも読み出しチャネルと書き込みチャネルの間に順序の規則は無い。
  Arm 102202 7 章: "Read and write channels have no ordering rules in relation to each other")。
  書いた値を読み戻すときは、`wr_done` を待ってから読み出しコマンドを出す
- リセット中とリセット解除後の最初のエッジまで、VALID は 0
  (A2.1.2 / PG101 の `AXI_ERRM_AWVALID_RESET` など: "AWVALID is Low for the first cycle after ARESETn goes High")

### 転送速度

`AWREADY` / `WREADY` / `ARREADY` が毎サイクル 1 で、スレーブが AW と W (読み出しは AR) を受けた次のサイクルに
`BVALID` (`RVALID`) を出す場合 (応答の待ち `L = 0`)、コマンドを受け付けてから `*_done` までのサイクル数 (上の図の `n`) は:

| コマンド | `n` |
| --- | --- |
| 書き込み (n_tr 個のトランザクションを出した) | `7 + f(n_tr - 1)` |
| 読み出し (n_tr 個) | `5 + f(n_tr - 1)` |
| 転送しないコマンド (0 ワード / 誤りのあるコマンド) | `1` |

`f(i)` は i 番目のトランザクションを出すサイクル (最初から数えて) で、

- `MAX_*_OUTSTANDING >= 3` なら `f(i) = i` (**1 サイクルに 1 トランザクション**。読み書き同時でもそれぞれこの速度)
- `MAX_*_OUTSTANDING < 3` なら `f(i) = 3 * (i / MAX) + i % MAX` (応答を待つ時間が見える)

例: 既定値 (`MAX_*_OUTSTANDING = 4`) で 16 ワードの書き込みは 22 サイクル、読み出しは 20 サイクル。
固定ぶんは、書き込みが 7 サイクル (内部メモリの読み出し 2、要求、AW / W、B、応答の受け取り、`done`)、
読み出しが 5 サイクル (要求、AR、R、応答の受け取り = 内部メモリへの書き込み、`done`)。

応答の待ちが `L` サイクルあるスレーブでも 1 サイクルに 1 トランザクション出すには、`MAX_*_OUTSTANDING >= L + 3` にする
(要求を受け付けてから応答を受けるまで `L + 2` サイクルかかり、その間に出す数が未完了として残るため)。

簡易 TB と UVM の scoreboard は、理想的なスレーブ (READY が常に 1、`L = 0`) のときの全てのコマンドで、このサイクル数を照合している。

### エラー時の動作

| | `STOP_ON_ERROR=1` (既定) | `STOP_ON_ERROR=0` |
| --- | --- | --- |
| エラー応答 (SLVERR / DECERR / EXOKAY) の後 | エラー応答を受けた**そのサイクルから**新しいトランザクションを出さない。すでに出していたもの (最大 `MAX_*_OUTSTANDING`-1 個) は応答を待って完了させる | 最後まで出す |
| `*_done_count` | `err_index + 1` .. `err_index + MAX_*_OUTSTANDING` (コマンドのワード数が上限) | `*_len` |
| `*_err_index` | 最初にエラー応答を受けたトランザクション | 同じ |
| `*_err_flags` | 受けた応答の種類 (止める前に出していたものの応答も含む) | 受けた応答の種類 |

- エラー応答の読み出しデータは内部メモリに書かない (そのワードは元の値のまま)。止める前に出していた読み出しが OKAY なら、そのデータは書く
- EXOKAY は排他アクセス (AXI4-Lite には無い) の応答で、AXI4-Lite のスレーブは返してはいけない
  (PG101 `AXI4LITE_ERRS_BRESP_EXOKAY` / `AXI4LITE_ERRS_RRESP_EXOKAY`: "A slave must not give an EXOKAY response on an AXI4-Lite interface")。
  受けたら異常として `*_err_flags[3]` で通知し、SLVERR / DECERR と同じ扱いにする
- エラー応答の書き込みが相手に反映されたかどうかは、相手のスレーブ次第
- 理想的なスレーブで止まるまでに出る数は、TB / UVM が正確な値と照合している (止めるのが 1 サイクル遅いと 1 つ多くなる)

### コマンドの誤り (`*_err_flags[2]`。トランザクションは出さない)

| 条件 | 理由 |
| --- | --- |
| `*_mem_addr + *_len > MEM_DEPTH` | 内部メモリの範囲を超える |
| `*_addr` が `DATA_WIDTH/8` の倍数でない | AXI4-Lite はデータバス幅いっぱいのアクセスだけ (下の「AXI4-Lite の制限」) |
| `*_incr=1` で `*_addr + *_len × DATA_WIDTH/8` が `2^ADDR_WIDTH` を超える | アドレスが一周してしまう |

`*_len = 0` は、他の項目が何であっても何もせずに `*_done` (エラーにしない)。

## 内部メモリ

- 1R1W (読み出しポート 1 + 書き込みポート 1) の同期メモリ。`axil_master_sram_2p.sv` は動作モデルで、
  そのまま合成すればフリップフロップになる。ワード数が多い場合はメモリコンパイラの 2 ポート (1R1W) マクロに置き換える
- 書き込みコマンドと読み出しコマンドを同時に動かすため、ポートを分けている
  - 読み出しポート: 書き込みコマンドの送信データ / ローカル読み出し (書き込みコマンドの実行中は使えない)
  - 書き込みポート: 読み出しコマンドの受信データ / ローカル書き込み (読み出しコマンドの実行中は使えない)
- 次の場合の値は**不定** (内部メモリの同じワードを、同時に読み書きすることになるため):
  - 同時に実行している書き込みコマンドと読み出しコマンドの、内部メモリの範囲が重なる
  - 実行中の書き込みコマンドの範囲へのローカル書き込み、実行中の読み出しコマンドの範囲からのローカル読み出し
- 上位は読み出しデータを「読み出しの次の 1 サイクルだけ」使い、同じサイクルの同じアドレスの読み書きに依存しない
  (`+define+AXIL_MASTER_SRAM_POISON` を付けると、それ以外のときの読み出しデータを乱数にして確認できる。
  同梱の Makefile は常にこれを付けている)
- リセットでは内容を消さない。ローカルポートの `MEM_DEPTH` 以上のアドレスは、書き込みを無視し、読み出しは 0 を返す
- 動作モデルにはシミュレーション用のチェック (範囲外アクセス / 同じアドレスの同時読み書きを数える) が入っている。
  合成時は `SYNTHESIS` を define して外す

## AXI4-Lite の制限

AXI4-Lite は AXI4 の一部で、次のトランザクションだけを使う (Intel Platform Designer の AXI4-Lite の説明より):

- "Transactions with a burst length of 1" (1 ビート)
- "Data accesses use the full width of a data bus (32- bit or 64-bit)" (狭いサイズのアクセスは無い。バイト単位の書き込みは `WSTRB` で行う)
- "Non-modifiable and non-bufferable accesses"
- "No exclusive accesses"

このモジュールもこれに従う。アドレスは `DATA_WIDTH/8` バイト単位で、1 トランザクション = 1 ワード。

## AXI4 / AXI5 (NI-700) へのつなぎ方

Arm CoreLink NI-700 TRM (1.3 Compliance) には "NI-700 does not support AXI4-Lite" とあり、
対応するのは "AMBA AXI5, ACE5-Lite, AHB5, APB3, and APB4" (1.1)。AXI4 のマスタについては
"AXI4 masters can connect to NI-700 as long as it supports AWAKEUP" (2.2.2) で、
"Except for wakeup signaling, all other OPTIONAL AXI5 capabilities can be disabled in NI-700 when integrated with an AXI4-based system" (1.1)。
また "Each ASNI has an input signal, AWAKEUP, which must be asserted when the AXI or ACE-Lite AxVALID signal is HIGH" (2.2.2)。

そこで `axil_to_axi4` を通して、AXI4-Lite に無い信号を固定値で出し、`AWAKEUP` を付ける:

| 信号 | 値 | 理由 |
| --- | --- | --- |
| `AxLEN` | 0 | 1 ビート |
| `AxSIZE` | log2(`DATA_WIDTH`/8) | データバス幅いっぱい |
| `AxBURST` | INCR (2'b01) | 1 ビートなので種類は意味を持たないが、INCR が自然 |
| `AxLOCK` | 0 | 排他アクセスは使わない |
| `AxCACHE` | 4'b0000 | Device Non-bufferable (変更不可・バッファ不可) |
| `AxID` | 0 | ID は 1 つ (応答は出した順に返る) |
| `WLAST` | 1 | 1 ビートなので毎回最後 |
| `AxQOS` | parameter `QOS` | 必要なら優先度を設定 |
| `AWAKEUP` | `axi_wakeup` | 要求を受けてから全ての応答を受けるまで 1。`AWVALID` / `ARVALID` と同じエッジで立つ |
| `BID` / `RID` / `RLAST` | (見ない) | ID は 1 つ、ビートは 1 つ |

- NI-700 側の ASNI は AXI5 の任意機能 (wakeup 以外) を無効にした設定にする。`ID_WIDTH` は ASNI の ID 幅に合わせる
- `axi_wakeup` は、要求を受け付けたエッジで立ち、最後の応答を受けたエッジで下がる (FF 出力)。
  TB / UVM で「AxVALID / WVALID が 1 のとき」と「バス上に未完了があるとき」は必ず 1、
  「書き込み / 読み出しのコマンドが両方アイドルのとき」は必ず 0 であることを確認している
- AXI4 のスレーブなら、`AWAKEUP` を未接続にしてそのままつなげる

## `axil_master_engine` を単体で使う場合

内部メモリを使わず、1 トランザクションずつ自分で制御したいときは `axil_master_engine` を直接使う。

| 信号 | 内容 |
| --- | --- |
| `wreq_valid` / `wreq_ready` | 書き込み要求 (valid/ready)。1 要求 = 1 トランザクション |
| `wreq_addr` / `wreq_data` / `wreq_strb` / `wreq_prot` | 内容 |
| `wrsp_valid` / `wrsp_resp` | 応答。B を受けた次のサイクルに 1 サイクルだけ 1。要求を受けた順に出る |
| `rreq_valid` / `rreq_ready` / `rreq_addr` / `rreq_prot` | 読み出し要求 |
| `rrsp_valid` / `rrsp_data` / `rrsp_resp` | 応答。R を受けた次のサイクルに 1 サイクルだけ 1 |
| `wr_busy` / `rd_busy` / `axi_wakeup` | 受け付けて、まだ応答を受けていない要求がある |

- `wreq_ready` / `rreq_ready` は FF だけで決まり、AXI の READY には組合せで依存しない
- 応答に待ったはかけられない (`BREADY` / `RREADY` が常に 1 のため)。`wrsp_*` / `rrsp_*` は毎サイクル受け取ること
- アドレスのアラインは検査しない (上位の責任)

## 使用上の制約

- 1 クロック (`aclk`)。リセットは非同期にかけてよいが、解除は `aclk` に同期させる
  (IHI 0022 L A2.1.2: "The reset signal can be asserted asynchronously, but deassertion can only be synchronous with a rising edge of ACLK")
- 実行中のコマンドを中断する機能は無い (リセット以外)。AXI にはトランザクションを打ち切る規定が無いので、
  応答を返さないスレーブがあるとコマンドは終わらない
- 1 コマンドのトランザクションは、全て同じ方向・同じ `WSTRB` / `PROT`。アドレスは連続 (`*_incr=1`) か固定 (`*_incr=0`)
- 書き込みと読み出しの順序は保証しない (上の「AXI4-Lite 側の振る舞い」)。内部メモリの範囲が重なるコマンドを同時に動かさない

## 他に調整できるようにしておくとよい項目 (提案)

### 今回 parameter / ポートにしたもの

| 項目 | parameter / ポート | 調整する理由 |
| --- | --- | --- |
| アドレス幅 / データ幅 | `ADDR_WIDTH` / `DATA_WIDTH` | AXI4-Lite はデータ 32 / 64bit。アドレスは 64bit まで |
| 未完了数 (読み / 書き別) | `MAX_WR_OUTSTANDING` / `MAX_RD_OUTSTANDING` | スレーブの応答の待ち `L` に対して `L + 3` 以上で 1 サイクル 1 トランザクション。小さくすると FF が減る |
| 内部メモリの深さ | `MEM_DEPTH` | 1 コマンドで運べる最大ワード数でもある |
| エラー時の方針 | `STOP_ON_ERROR` / `*_err_index` / `*_done_count` | レジスタ設定の途中で失敗したら、そこで止めて場所を知りたい |
| `WSTRB` / `PROT` | `wcmd_strb` / `*_prot` | コマンドごとに変えられる |
| wakeup | `axi_wakeup` + `axil_to_axi4` | NI-700 など AXI5 の相手に必要 |
| QoS / ID 幅 | `axil_to_axi4` の `QOS` / `ID_WIDTH` | 相手のインタコネクトの設定に合わせる |

### 今回は入れていないが、検討をお勧めするもの

| 項目 | 内容 | 入れる場面 |
| --- | --- | --- |
| 読み書きの順序指定 | 読み出しコマンドに「実行中の書き込みが終わるまで待つ」ビットを付ける | 書いた直後に読み戻す使い方が多い場合 (いまは `wr_done` を待ってから出す) |
| アドレス付きのテーブル | 内部メモリに {アドレス, データ} の組を持ち、飛び飛びのレジスタを 1 コマンドで設定する | 初期設定シーケンスに使う場合 |
| ポーリング | 読んだ値がマスク付きで期待値になるまで繰り返す | ステータスレジスタのビットを待つ場合 |
| タイムアウト | 応答が来ないときに検出して通知する (AXI では打ち切れないので、検出と割り込みまで) | 応答しないスレーブでハングするのを見つけたい場合 |
| AXI4 のバースト | 連続したアドレスを 1 トランザクションで運ぶ | 相手が AXI4 で、ブロック転送の帯域が欲しい場合 (以前作成したラインバッファ付き AXI マスタを参照) |
| AXI5 の任意機能 | パリティ (`*CHK`)、`USER` 信号、Poison など | 機能安全や NI-700 の保護機能を使う場合 |
| 低消費電力インタフェース | `wr_busy` / `rd_busy` を元に Q-Channel を付ける | このモジュール自体をクロックゲートする場合 |
| レジスタの直接出力 | 内部メモリの内容を信号として並列に出す | 読んだ値を常時参照したい場合 (いまはローカルポートで 1 ワードずつ読む) |

### 既製 IP / 市販ツールで代替できる範囲

- **メモリとペリフェラルの間のブロック転送 → Arm CoreLink DMA-350**。
  AXI5 のマネージャインタフェース (1 または 2 本)、1〜8 チャネル、コマンドのリンク ("one command can fetch the next without CPU intervention")、
  ソフトで設定できるトリガを持つ。転送元が SoC のメモリにあり、DMA を置ける構成なら、このモジュールより汎用で、NI-700 とも同じ AMBA 5 世代
- **AXI4-Lite / AXI5-Lite のプロトコル確認 → Cadence の AMBA 向け Simulation VIP**。
  同梱の TB のプロトコルチェック (スレーブモデルと SVA) は手作りのもの。サインオフでは市販の VIP を使うほうが確実。
  Cadence の AMBA VIP は "AMBA 4 AXI-Lite" と "AMBA 5 AXI-Lite interfaces" を含み、BFM・自動のプロトコルチェック・カバレッジモデルを持つ
- **FPGA での試作時のプロトコル確認 → AMD AXI Protocol Checker (PG101)**。Vivado の IP で、AXI4-Lite の規則 (EXOKAY 禁止など) も確認する
- **内部メモリ → メモリコンパイラの 1R1W マクロ** (ワード数が多い場合)

## シミュレーション (簡易 TB)

Verilator 5.052 で確認。

```
cd sim
make                  # エンジン単体 (7 構成) + トップ (8 構成)
make engine           # エンジン単体だけ
make top              # トップの全構成
make one CFG=c2       # トップを 1 構成だけ
make eng_one ECFG=e2  # エンジン単体を 1 構成だけ
make lint             # RTL を -Wall で lint (全構成。axil_to_axi4 も)
make top EXTRA=-GN_RAND=2400     # ランダムなコマンドの本数を増やす (既定 240 / 方向)
make engine EXTRA=-GN_REQ=20000  # エンジン単体の要求数を増やす (既定 300)
```

### 構成

| 名前 | 内容 |
| --- | --- |
| c1 | 既定 (アドレス 32bit、データ 32bit、メモリ 16 ワード、未完了 4 / 4、エラーで中止) |
| c2 | データ 64bit、メモリ 10 ワード (2 のべき乗でない)、未完了 1 / 1、エラーでも最後まで続ける |
| c3 | アドレス 16bit、メモリ 64 ワード、未完了 2 / 3 |
| c4 | メモリ 1 ワード、未完了 8 / 8、エラーでも最後まで続ける |
| c5 | アドレス 64bit、データ 64bit、メモリ 33 ワード、未完了 16 / 2 |
| c6 | アドレス空間がメモリより狭い (アドレス 6bit = 16 ワード、メモリ 24 ワード)、未完了 3 / 3 |
| c7 | アドレス 12bit、メモリ 2 ワード、未完了 1 / 16、エラーでも最後まで続ける |
| c8 | アドレス 20bit、データ 64bit、メモリ 7 ワード、未完了 5 / 4 |

エンジン単体 (e1〜e7) は、データ幅 32 / 64、アドレス幅 4〜64、未完了 1〜16 (読み書きで別の値) の組み合わせ (`sim/Makefile` の `ECFG_*`)。

### テスト項目 (トップ)

| テスト | 内容 |
| --- | --- |
| TEST1 | 基本 (内部メモリを書き出す → 内部メモリを書き換える → 読み戻す)。書き込みと読み出しを同じサイクルに受け付けて同時に流す |
| TEST2 | 転送数とメモリ位置の端、固定アドレス、`WSTRB` (1 バイトずつ / 乱数 / 0)、`PROT` 全値 (読み書き同時)、アドレス空間の一番上と一番下 |
| TEST3 | 応答の遅延を長くして未完了数が上限まで使われること。READY / 遅延を乱数にして読み書き同時 (AWREADY は W を待つ / WREADY は AW を待つ、も含む) |
| TEST4 | エラー応答 (SLVERR / DECERR / EXOKAY × 先頭 / 中間 / 最後)、全トランザクションがエラー、1 コマンドで 2 種類、READY / 遅延が乱数のときのエラー |
| TEST5 | コマンドの誤り (メモリ範囲 / 非アライン / アドレス空間の一番上を超える)、0 ワード。反対方向のコマンドの実行中にも |
| TEST6 | ローカルポート (毎サイクル連続の読み / 書き、範囲外アドレス、コマンドと同じサイクル、実行中に受け付けられる / 待たされる) |
| TEST7 | 実行中に次のコマンドを出したまま待つ (done の次のサイクルで受け付けられる)。その間、反対方向のコマンドはすぐ受け付けられる |
| TEST8 | ランダム (書き込みコマンド / 読み出しコマンド / ローカルポートを同時に。スレーブの振る舞いとエラー範囲をラウンドごとに変える) |
| TEST9 | 両方のコマンドの実行中にリセット。その後のコマンドが正常に動く |

コマンドごとに次を確認している。

- `*_done_err` / `*_err_flags` / `*_err_index` / `*_done_count`。`STOP_ON_ERROR=1` のエラーでは出た数の範囲
  (理想的なスレーブでは正確な数)
- 理想的なスレーブでの受付から `*_done` までのサイクル数 (上の「転送速度」の式)
- バス上のトランザクションの列 (アドレス / `PROT` / `WDATA` / `WSTRB` / 応答) と、余分なトランザクションが無いこと
- 書き込み: スレーブのメモリ (`WSTRB` のバイトだけ更新、エラーは反映しない)
- 読み出し: 内部メモリ (エラーのワードは元の値のまま)
- 常時: ready / busy / done の関係、ステータスの保持、ローカルポートの ready の規則、`mem_r_rvalid` のタイミング、
  `axil_to_axi4` の固定値と `AWAKEUP`、アイドルの方向のバスに何も出ないこと、
  スレーブモデルのプロトコルチェック 0 件、非アライン 0 件、内部メモリの範囲外アクセス / 同じアドレスの同時読み書き 0 件

スレーブモデルは、仕様上「見てはいけない」値 (`BVALID=0` のときの `BRESP`、`RVALID=0` のときの `RDATA` / `RRESP`、
`BID` / `RID` / `RLAST`) を乱数にしている。

### 実行結果 (この環境)

Verilator 5.052 で全て PASS。ビルド時の警告は 0 件 (警告はエラー扱いでビルドしている)。
RTL は 8 構成とも `verilator --lint-only -Wall` で警告 0 件 (`axil_master_mem` と `axil_to_axi4` の両方)。

```
$ make lint
lint c1 : clean   ...   lint c8 : clean

$ make
engine e1 : PASS  []
engine e2 : PASS  [-GMAX_WR_OUTSTANDING=1 -GMAX_RD_OUTSTANDING=1]
engine e3 : PASS  [-GDATA_WIDTH=64 -GMAX_WR_OUTSTANDING=2 -GMAX_RD_OUTSTANDING=3]
engine e4 : PASS  [-GADDR_WIDTH=64 -GDATA_WIDTH=64 -GMAX_WR_OUTSTANDING=8 -GMAX_RD_OUTSTANDING=5]
engine e5 : PASS  [-GADDR_WIDTH=4 -GMAX_WR_OUTSTANDING=3 -GMAX_RD_OUTSTANDING=2]
engine e6 : PASS  [-GADDR_WIDTH=12 -GMAX_WR_OUTSTANDING=16 -GMAX_RD_OUTSTANDING=1]
engine e7 : PASS  [-GADDR_WIDTH=5 -GDATA_WIDTH=64 -GMAX_WR_OUTSTANDING=1 -GMAX_RD_OUTSTANDING=16]
top c1 : PASS  []
top c2 : PASS  [-GDATA_WIDTH=64 -GMEM_DEPTH=10 -GMAX_WR_OUTSTANDING=1 -GMAX_RD_OUTSTANDING=1 -GSTOP_ON_ERROR=0]
top c3 : PASS  [-GADDR_WIDTH=16 -GMEM_DEPTH=64 -GMAX_WR_OUTSTANDING=2 -GMAX_RD_OUTSTANDING=3]
top c4 : PASS  [-GMEM_DEPTH=1 -GMAX_WR_OUTSTANDING=8 -GMAX_RD_OUTSTANDING=8 -GSTOP_ON_ERROR=0]
top c5 : PASS  [-GADDR_WIDTH=64 -GDATA_WIDTH=64 -GMEM_DEPTH=33 -GMAX_WR_OUTSTANDING=16 -GMAX_RD_OUTSTANDING=2]
top c6 : PASS  [-GADDR_WIDTH=6 -GMEM_DEPTH=24 -GMAX_WR_OUTSTANDING=3 -GMAX_RD_OUTSTANDING=3]
top c7 : PASS  [-GADDR_WIDTH=12 -GMEM_DEPTH=2 -GMAX_WR_OUTSTANDING=1 -GMAX_RD_OUTSTANDING=16 -GSTOP_ON_ERROR=0]
top c8 : PASS  [-GADDR_WIDTH=20 -GDATA_WIDTH=64 -GMEM_DEPTH=7 -GMAX_WR_OUTSTANDING=5 -GMAX_RD_OUTSTANDING=4]
```

`make` (15 本のビルドと実行) は、この環境 (2 コア) で ccache 無しで 2 分 7 秒、
同じソースのビルド結果を ccache が持っていれば 1 分 14 秒。シミュレーション自体は既定の本数で 1 本 0.2 秒程度で、ほとんどがビルドの時間。

理想的なスレーブでの、受付から `*_done` までのサイクル数 (TEST1。メモリ全体を 1 コマンドで転送する。
c6 はアドレス空間 16 ワードを書き込み用 / 読み出し用に分けているので 8 ワード)。全て上の「転送速度」の式どおり:

```
構成  未完了 (書 / 読)  ワード数  書き込み  読み出し
c1    4 / 4             16        22        20
c2    1 / 1             10        34        32
c3    2 / 3             64        101       68
c4    8 / 8             1         7         5
c5    16 / 2            33        39        53
c6    3 / 3             8         14        12
c7    1 / 16            2         10        6
c8    5 / 4             7         13        11
```

例えば c3 の書き込みは未完了 2 なので `7 + 3 × (63 / 2) + 63 % 2 = 101`、c5 の読み出しは未完了 2 なので `5 + 3 × (32 / 2) = 53`。

トップの 1 本あたりの規模 (各ログ `sim/<構成>.log` の集計行から。「書き込み / 読み出し」の形):

```
構成  転送したコマンド  エラー応答あり  途中で止めた  断った  0 ワード  サイクル数を照合
c1    286 / 260         49 / 53         23 / 17       86      33        231
c2    302 / 213         82 / 41         0 / 0         121     43        245
c3    285 / 277         37 / 39         20 / 28       68      35        231
c4    194 / 111         92 / 36         0 / 0         228     110       213
c5    288 / 289         31 / 45         14 / 33       76      26        245
c6    287 / 283         79 / 85         24 / 29       69      28        233
c7    236 / 170         97 / 40         0 / 0         178     79        229
c8    270 / 241         82 / 83         20 / 9        115     51        243

構成  トランザクション  読み書きとも未完了  最大の未完了数 (上限)  ローカルアクセス
c1    1431 / 1043       414                 4 / 4 (4 / 4)          406 / 421
c2    1180 / 688        200                 1 / 1 (1 / 1)          332 / 306
c3    4382 / 3317       1250                2 / 3 (2 / 3)          1332 / 1388
c4    194 / 111         1                   1 / 1 (8 / 8)          52 / 54
c5    2190 / 2034       1106                16 / 2 (16 / 2)        881 / 809
c6    1179 / 1077       669                 3 / 3 (3 / 3)          571 / 628
c7    321 / 206         55                  1 / 2 (1 / 16)         84 / 83
c8    765 / 633         349                 5 / 4 (5 / 4)          267 / 245
```

- 「転送したコマンド」は、断ったコマンドと 0 ワードのコマンドを除いた数。「断った」「0 ワード」は読み書きの合計
- 「途中で止めた」は、`STOP_ON_ERROR=1` でエラー応答を受けて途中で止めたコマンド (c2 / c4 / c7 は `STOP_ON_ERROR=0`)
- 「サイクル数を照合」は、理想的なスレーブで受付から `*_done` までのサイクル数を式と照合したコマンド
- 「読み書きとも未完了」は、書き込みと読み出しの両方にバス上の未完了があったサイクル数
- c4 / c7 はメモリが 1 / 2 ワードなので、1 コマンドのトランザクション数が未完了数の上限より少ない

エンジン単体 (要求ごとに、応答の種類・データ・順番を照合する。READY / 応答の遅延 / エラー応答は乱数):

```
構成  未完了 (書 / 読)  PHASE1 (書 / 読)  応答 書き (エラー)  応答 読み (エラー)  AW が先 / W が先  読み書きとも未完了
e1    4 / 4             300 / 300         950 (45)            800 (38)            162 / 75          694
e2    1 / 1             898 / 898         950 (34)            800 (42)            201 / 95          803
e3    2 / 3             449 / 300         950 (41)            800 (50)            142 / 173         670
e4    8 / 5             300 / 300         950 (37)            800 (34)            112 / 155         645
e5    3 / 2             300 / 449         950 (202)           800 (108)           130 / 120         666
e6    16 / 1            300 / 898         950 (46)            800 (41)            137 / 96          394
e7    1 / 16            898 / 300         950 (216)           800 (85)            150 / 144         408
```

- 「PHASE1」は、理想的なスレーブに書き込みと読み出しを 300 要求ずつ同時に出し、全てを受け付けるまでのサイクル数。
  未完了数の上限が 3 以上なら 300 (1 サイクルに 1 要求)、2 なら 449 (`3 × 149 + 1 + 1`)、1 なら 898 (`3 × 299 + 1`)
- 「AW が先 / W が先」は、スレーブが AW と W を別のサイクルに受け付けたトランザクションの数
  (「AWREADY が W を待つ」「WREADY が AW を待つ」スレーブの設定を含む。残りは同じサイクル)

ランダムの本数を増やした実行も、全構成 PASS。

```
$ make top EXTRA=-GN_RAND=2400       # 8 構成の合計で 39898 コマンド、トランザクション 97944 回 (48 秒)
$ make engine EXTRA=-GN_REQ=20000    # 1 構成あたり 書き込み 63330 / 読み出し 53331 要求 (22 秒)
```

### 検証環境の検出力確認

RTL に 1 箇所ずつバグを入れ (60 種)、簡易 TB を流した結果。60 種すべてが、少なくとも 1 構成で FAIL
(1 種は、一部の構成ではビルド時の警告で止まる) になった。バグを入れない状態では、同じ手順で全構成が PASS する。

転送エンジンとレジスタスライスに入れたバグ (20 種)。エンジン単体 TB の 5 構成 (e1 e2 e3 e5 e6) と、トップ TB の 2 構成 (c1 c2) で流した:

```
入れたバグ                                       e1    e2    e3    e5    e6    c1    c2    最初に検出したチェック
書き込みの未完了数の上限を見ない                 検出  検出  検出  検出  検出  検出  検出  未完了数が上限を超える
書き込みの未完了数の上限が 1 多い                検出  警告  検出  警告  検出  検出  警告  未完了数が上限を超える
W スライスの空きを見ずに書き込み要求を受ける     検出  -     -     検出  検出  検出  -     トランザクションの内容
読み出しの未完了数の上限を見ない                 検出  検出  検出  検出  検出  検出  検出  未完了数が上限を超える
R を受けても読み出しの未完了数を減らさない       検出  検出  検出  検出  検出  検出  検出  rd_busy と未完了数
BREADY を常に 1 にしない                         検出  検出  検出  検出  検出  検出  検出  BREADY / RREADY が常に 1
RREADY を常に 1 にしない                         検出  検出  検出  検出  検出  検出  検出  BREADY / RREADY が常に 1
BRESP を捨てる (常に OKAY)                       検出  検出  検出  検出  検出  検出  検出  応答の種類 (wrsp_resp / rrsp_resp)
RRESP を捨てる (常に OKAY)                       検出  検出  検出  検出  検出  検出  検出  応答の種類 (wrsp_resp / rrsp_resp)
RDATA を取り込まない                             検出  検出  検出  検出  検出  検出  検出  読み出しデータ
axi_wakeup が 1 サイクル遅れる                   検出  検出  検出  検出  検出  検出  検出  axi_wakeup と未完了数
読み出しで axi_wakeup を立てない                 検出  検出  検出  検出  検出  検出  検出  axi_wakeup と未完了数
AWPROT を常に 0 にする                           検出  検出  検出  検出  検出  検出  検出  トランザクションの内容
ARPROT を常に 0 にする                           検出  検出  検出  検出  検出  検出  検出  トランザクションの内容
WSTRB を常に全て 1 にする                        検出  検出  検出  検出  検出  検出  検出  トランザクションの内容
エンジンの wr_busy を出さない                    検出  検出  検出  検出  検出  -     -     wr_busy と未完了数
スライス : 出力が待たされている間の入力を捨てる  検出  -     検出  検出  検出  検出  -     トランザクションの内容
スライス : READY を待たずに出力を上書きする      検出  検出  検出  検出  検出  検出  検出  プロトコル: READY の前にペイロードが変化
スライス : スキッドのデータを出力に移さない      検出  -     検出  検出  検出  検出  -     トランザクションの内容
スライス : スキッドが埋まっていても入力を受ける  検出  -     検出  検出  検出  検出  -     トランザクションの内容
```

トップ (シーケンサ / 内部メモリまわり) と `axil_to_axi4` に入れたバグ (40 種)。トップ TB の 4 構成 (c1 c2 c3 c6) で流した:

```
入れたバグ                                                                     c1    c2    c3    c6    最初に検出したチェック
実行中も書き込みコマンドの ready を出す                                        検出  検出  検出  検出  モニタ: wcmd_ready と wr_busy
done のサイクルに rd_busy を下げる                                             検出  検出  検出  検出  モニタ: rcmd_ready と rd_busy
読み出しコマンド中もローカル書き込みを受ける                                   検出  検出  検出  検出  モニタ: mem_w_ready と rd_busy
書き込みコマンド中もローカル読み出しを受ける                                   検出  検出  検出  検出  モニタ: mem_r_ready と wr_busy
ローカル書き込みを止める条件が逆 (書き込みコマンド中に止める)                  検出  検出  検出  検出  モニタ: mem_w_ready と rd_busy
送信 FIFO の空きを見ずに内部メモリを読む                                       検出  検出  検出  検出  done が来ない (ハング検出)
送信 FIFO の空きを今の個数で判定する                                           検出  検出  検出  検出  トランザクションの内容 (アドレス / PROT / データ / WSTRB / 応答)
送信 FIFO の読み出し位置を進めない                                             検出  検出  検出  検出  トランザクションの内容 (アドレス / PROT / データ / WSTRB / 応答)
内部メモリの読み出し位置を進めない                                             検出  検出  検出  検出  トランザクションの内容 (アドレス / PROT / データ / WSTRB / 応答)
書き込み : エラー応答で止めない (STOP_ON_ERROR が効かない)                     検出  -     検出  検出  done_count (止めるまでに出した数)
読み出し : エラー応答で止めない (STOP_ON_ERROR が効かない)                     検出  -     検出  検出  done_count (止めるまでに出した数)
書き込み : エラー応答のサイクルにはまだ要求を出す (止めるのが 1 サイクル遅い)  検出  -     検出  検出  done_count (止めるまでに出した数)
読み出し : エラー応答のサイクルにはまだ要求を出す (止めるのが 1 サイクル遅い)  検出  -     検出  検出  done_count (止めるまでに出した数)
エラーで止めた後も FIFO の残りを出す                                           検出  -     検出  検出  done_count (止めるまでに出した数)
エラーで止めた後も読み出し要求を出す                                           検出  -     検出  検出  done_count (止めるまでに出した数)
err_index が最後のエラー (書き込み)                                            検出  検出  検出  検出  err_index
err_index が最後のエラー (読み出し)                                            検出  検出  検出  検出  err_index
err_index に出した数を入れる (書き込み)                                        検出  検出  検出  検出  err_index
EXOKAY をエラーとして扱わない (止めない / err_index)                           検出  検出  検出  検出  done_count (止めるまでに出した数)
エラー応答の読み出しデータも内部メモリに書く                                   検出  検出  検出  検出  内部メモリ
エラー応答のときに内部メモリの書き込み位置を進めない                           検出  検出  検出  検出  内部メモリ
書き込みアドレスを 1 バイトずつ進める                                          検出  検出  検出  検出  トランザクションの内容 (アドレス / PROT / データ / WSTRB / 応答)
固定アドレスの読み出しでもアドレスを進める                                     検出  検出  検出  検出  トランザクションの内容 (アドレス / PROT / データ / WSTRB / 応答)
アドレス空間の一番上にちょうど収まる書き込みを断る                             検出  検出  検出  検出  done_count (止めるまでに出した数)
内部メモリの末尾にちょうど収まる読み出しを断る                                 検出  検出  検出  検出  done_count (止めるまでに出した数)
非アラインの書き込みコマンドを断らない                                         検出  検出  検出  検出  done_count (止めるまでに出した数)
0 ワードの書き込みコマンドを誤りにする                                         検出  検出  検出  検出  err_flags
次のコマンドで SLVERR のフラグを消さない                                       検出  検出  検出  検出  err_flags
EXOKAY を wr_done_err に入れない                                               検出  検出  検出  検出  done_err
コマンドの WSTRB を使わない                                                    検出  検出  検出  検出  トランザクションの内容 (アドレス / PROT / データ / WSTRB / 応答)
コマンドの ARPROT を使わない                                                   検出  検出  検出  検出  トランザクションの内容 (アドレス / PROT / データ / WSTRB / 応答)
範囲外のローカル書き込みを無視しない                                           -     検出  -     検出  内部メモリの範囲外アクセス
範囲外のローカル読み出しで 0 を返さない                                        -     検出  -     検出  ローカル読み出しのデータ
待たされたローカル読み出しでも mem_r_rvalid を出す                             検出  検出  検出  検出  モニタ: mem_r_rvalid のタイミング
変換 : AWLEN を 1 にする                                                       検出  検出  検出  検出  モニタ: axil_to_axi4 の固定値
変換 : WLAST を 0 にする                                                       検出  検出  検出  検出  モニタ: axil_to_axi4 の固定値
変換 : ARSIZE を 1 バイトにする                                                検出  検出  検出  検出  モニタ: axil_to_axi4 の固定値
変換 : AWCACHE を Bufferable / Modifiable にする                               検出  検出  検出  検出  モニタ: axil_to_axi4 の固定値
変換 : ARQOS にパラメータを出さない                                            検出  検出  検出  検出  モニタ: axil_to_axi4 の固定値
変換 : AWAKEUP を出さない                                                      検出  検出  検出  検出  モニタ: AxVALID / WVALID と AWAKEUP
```

- 「-」は、その構成ではバグの影響が出ない組み合わせ。複数の構成で流す必要があることを示している
  - e2 / c2 は書き込みの未完了数の上限が 1。レジスタスライスのスキッドが使われず、W スライスがあふれることも無いので、
    スライスのバグと「W スライスの空きを見ずに書き込み要求を受ける」は影響が出ない
    (e3 は上限 2 で、W スライスの 2 段に収まる)。つまり、これらは上限 1〜2 の構成では等価で、上限 3 以上の構成だけで意味を持つ
  - 「エンジンの wr_busy を出さない」は、トップがエンジンの `wr_busy` を使わないので、エンジン単体 TB だけが検出する
  - c2 は `STOP_ON_ERROR=0` なので、エラーで止める動作のバグは出ない
  - c1 / c3 はメモリが 2 のべき乗 (16 / 64 ワード) で、ローカルポートに範囲外のアドレスが無い
- 「警告」は、Verilator のビルド時の警告 (CMPCONST : 比較の結果が常に同じ) でビルドが止まったもの。
  上限が 1 / 3 の構成では、カウンタのビット幅いっぱいの値との `<=` 比較が常に真になる
  (Makefile は警告をエラー扱いにしている)
- 「最初に検出したチェック」は、検出した中で最も左の構成のログで、最初に出たエラー。
  「プロトコル:」はスレーブモデルのプロトコルチェック、「モニタ:」はトップ TB の常時モニタ、
  それ以外はテスト側の照合 (コマンド / 応答ごとの期待値、所要サイクル数、内部メモリの動作モデルのチェックなど)
- 「止めるのが 1 サイクル遅い」は、エラー応答を受けたサイクルにもう 1 つ要求を出してしまうバグ。
  出た数は `err_index+1 .. err_index+MAX` の範囲に収まるので、範囲の照合だけでは見つからない。
  理想的なスレーブで「エラー応答を受けたサイクルで止まるときの正確な数」と照合している (TEST4) ので検出できる
  (例: c1 で `wr_done_count=4 (exp 3..3)`)

UVM 環境での同様の確認は `uvm/README.md` を参照。

## 参考

- AMBA AXI Protocol Specification (Arm IHI 0022 Issue L。Reset: A2.1.2 / Valid-Ready transport: A2.3 /
  Write transaction dependencies: A2.3.2.1):
  https://documentation-service.arm.com/static/68b03beb01ae952d9559f9eb
- Learn the architecture - An introduction to AMBA AXI (Arm 102202 3.0。Channel handshake: 4 章 / Read and write channel ordering: 7 章):
  https://documentation-service.arm.com/static/6560cd802c8b3557fee70a89
- Intel Quartus Prime Pro Edition User Guide: Platform Designer, AMBA 4 AXI-Lite Protocol Specification Support
  (AXI4-Lite のトランザクションの制限):
  https://intel.com/content/www/us/en/docs/programmable/683609/24-1/lite-protocol-specification-support.html
- AMD AXI Protocol Checker (PG101)、AXI Protocol Checks and Descriptions (`AXI4LITE_ERRS_BRESP_EXOKAY` /
  `AXI4LITE_ERRS_RRESP_EXOKAY`、`AXI_ERRM_*VALID_RESET` / `AXI_ERRM_*VALID_STABLE`):
  https://docs.amd.com/r/en-US/pg101-axi-protocol-checker/AXI-Protocol-Checks-and-Descriptions
- Arm CoreLink NI-700 TRM (1.1 / 1.3 Compliance / 1.6.1 / 2.2.2 Clock domain wakeup):
  https://documentation-service.arm.com/static/60acf9c4982fc7708ac1cde2
- Arm CoreLink DMA-350 (Arm Community Blog):
  https://developer.arm.com/community/arm-community-blogs/b/internet-of-things-blog/posts/arm-corelink-dma-350-next-generation-direct-memory-access-for-endpoint-ai
- Cadence AMBA VIP Solutions (AMBA 4 AXI-Lite / AMBA 5 AXI-Lite の Simulation VIP):
  https://www.cadence.com/en_US/home/tools/system-design-and-verification/verification-ip/simulation-vip/amba.html
- Verilator: エラボレーション時の `$error` (USERERROR、IEEE 1800-2023 20.11):
  https://verilator.org/guide/latest/warnings.html

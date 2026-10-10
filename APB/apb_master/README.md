# APB マスタ + 内部メモリ (`apb_master_mem`)

APB マスタ (Requester)。モジュール内のメモリ (汎用レジスタ) と APB の間で、コマンド 1 つにつき
連続したワードをまとめて転送する。

```
  mem_* (ローカルポート) <--> [内部メモリ MEM_DEPTH ワード]
                                    |  ^
                 cmd_write=1 (書く)  v  |  cmd_write=0 (読む)
  cmd_* / done  --> [シーケンサ] --> [apb_master_engine] --> PSEL[n] / PADDR / PWDATA ...
                                                         <-- PREADY[n] / PRDATA / PSLVERR[n]
```

- 書き込みコマンド: 内部メモリの `[cmd_mem_addr から cmd_len ワード]` を、APB の `cmd_addr` から順に書く
- 読み出しコマンド: APB の `cmd_addr` から `cmd_len` ワード読み、内部メモリの `[cmd_mem_addr から]` に入れる
- 内部メモリは、ローカルポート (`mem_*`) から読み書きする
- 言語: SystemVerilog (`always @(posedge pclk ...)` / `always @(*)` で記述)
- クロック / リセット: `pclk`、非同期リセット `presetn` (負論理)
- APB4 相当 (PSTRB / PPROT / PREADY / PSLVERR あり)。APB3 のスレーブにもつなげる (下の「APB の版」を参照)

## ファイル構成

```
rtl/
  apb_master_mem.sv        ... トップ (内部メモリ + シーケンサ + 転送エンジン)
  apb_master_engine.sv     ... APB マスタの転送エンジン (要求 1 つ = 転送 1 回)。単体でも使える
  apb_master_sram_sp.sv    ... 内部メモリの動作モデル (FF になる。大きければマクロに置き換える)
  filelist.f               ... 上記のコンパイル順
tb/
  tb_apb_master_mem.sv     ... トップの簡易 TB (自己チェック)
  tb_apb_master_engine.sv  ... エンジン単体の TB
  apb_slave_mem_model.sv   ... 検証用 APB スレーブ + メモリ (プロトコルチェック付き)
sim/
  Makefile                 ... Verilator 5.x 用 (エンジン 8 構成 + トップ 8 構成)
uvm/                       ... Verilator + UVM 環境
  README.md  tb/  sim/
```

## parameter 一覧

| parameter | 既定値 | 内容 |
| --- | --- | --- |
| `ADDR_WIDTH` | 32 | `PADDR` のビット幅 (1..32) |
| `DATA_WIDTH` | 32 | `PWDATA` / `PRDATA` のビット幅 (8 / 16 / 32) |
| `NUM_SLAVES` | 1 | `PSEL` の本数 (つなぐスレーブ数) |
| `MEM_DEPTH` | 16 | 内部メモリのワード数 (1 ワード = `DATA_WIDTH` ビット) |
| `TIMEOUT_CYCLES` | 0 | `PREADY` 待ちの上限。0 = 無効 (下の「タイムアウト」を参照) |
| `STOP_ON_ERROR` | 1 | 1 = 最初のエラーで残りの転送を中止 / 0 = 最後まで続ける |

範囲外の値を指定すると、エラボレーション時の `$error` で止まる (IEEE 1800 20.11)。
対応していない合成ツールでは `+define+APB_MASTER_NO_ELAB_CHECK` で外せる。

## ポート

| グループ | 信号 | 内容 |
| --- | --- | --- |
| コマンド | `cmd_valid` / `cmd_ready` | valid/ready。アイドル時だけ `cmd_ready=1` |
| | `cmd_write` | 1 = 書き込み (メモリ → APB) / 0 = 読み出し (APB → メモリ) |
| | `cmd_sel` | 相手のスレーブ番号 (0..`NUM_SLAVES`-1)。その番号の `PSEL` だけ立てる |
| | `cmd_addr` | APB の先頭アドレス (`DATA_WIDTH/8` バイトの倍数) |
| | `cmd_incr` | 1 = 1 転送ごとにアドレスを `DATA_WIDTH/8` 進める / 0 = 同じアドレスに繰り返す |
| | `cmd_mem_addr` | 内部メモリの先頭ワード番号 |
| | `cmd_len` | 転送ワード数 (0 なら何もせず完了) |
| | `cmd_strb` | 書き込み時の `PSTRB` (全転送で共通)。読み出しでは無視し、`PSTRB` は 0 を出す |
| | `cmd_prot` | `PPROT` (全転送で共通) |
| ステータス | `busy` / `done` / `done_err` | `done` は 1 サイクル。以下は `done` と同じサイクルで見る (次のコマンド受付まで保持) |
| | `err_flags[2:0]` | [0] PSLVERR を受けた / [1] タイムアウトで打ち切った / [2] コマンドの誤り |
| | `err_index` | 最初にエラーになった転送の番号 (0 始まり)。`err_flags[1:0] != 0` のとき有効 |
| | `done_count` | バスで実行した転送数 (エラーで終わった転送も含む) |
| ローカルポート | `mem_valid` / `mem_ready` | valid/ready。コマンド実行中 (`busy=1`) は `mem_ready=0` |
| | `mem_write` / `mem_addr` / `mem_wdata` | 1 = 書き込み、ワード番号、書き込みデータ |
| | `mem_rvalid` / `mem_rdata` | 読み出しを受け付けた次のサイクルに `mem_rvalid=1` とデータ |
| APB | `paddr` / `pprot` / `penable` / `pwrite` / `pwdata` / `pstrb` | 全スレーブ共通 |
| | `psel[NUM_SLAVES]` | スレーブごと。同時に立つのは 1 本だけ |
| | `pready[NUM_SLAVES]` / `pslverr[NUM_SLAVES]` | スレーブごとに入力 |
| | `prdata[NUM_SLAVES*DATA_WIDTH]` | スレーブ i の分が `[i*DATA_WIDTH +: DATA_WIDTH]` |

スレーブごとの `PREADY` / `PRDATA` / `PSLVERR` はモジュール内で選択するので、外にマルチプレクサは要らない。

接続例 (スレーブ 2 個、メモリ 32 ワード。この記述は `verilator --lint-only -Wall` で警告が出ないことを確認している):

```systemverilog
  apb_master_mem #(
    .ADDR_WIDTH(16)
   ,.DATA_WIDTH(32)
   ,.NUM_SLAVES(2)
   ,.MEM_DEPTH(32)
  ) u_apb_master (
    .pclk(pclk)
   ,.presetn(presetn)
    // コマンド / ステータス
   ,.cmd_valid(cmd_valid)
   ,.cmd_ready(cmd_ready)
   ,.cmd_write(cmd_write)
   ,.cmd_sel(cmd_sel)                  // 1 ビット (0 = スレーブ 0 / 1 = スレーブ 1)
   ,.cmd_addr(cmd_addr)                // 16 ビット
   ,.cmd_incr(cmd_incr)
   ,.cmd_mem_addr(cmd_mem_addr)        // 5 ビット (0..31)
   ,.cmd_len(cmd_len)                  // 6 ビット (0..32)
   ,.cmd_strb(cmd_strb)                // 4 ビット
   ,.cmd_prot(cmd_prot)
   ,.busy(busy)
   ,.done(done)
   ,.done_err(done_err)
   ,.err_flags(err_flags)
   ,.err_index(err_index)              // 6 ビット
   ,.done_count(done_count)            // 6 ビット
    // 内部メモリのローカルポート
   ,.mem_valid(mem_valid)
   ,.mem_ready(mem_ready)
   ,.mem_write(mem_write)
   ,.mem_addr(mem_addr)                // 5 ビット
   ,.mem_wdata(mem_wdata)
   ,.mem_rvalid(mem_rvalid)
   ,.mem_rdata(mem_rdata)
    // APB (スレーブごとの信号は、スレーブ 0 を下位にして連結する)
   ,.paddr(paddr)
   ,.pprot(pprot)
   ,.psel({psel_1, psel_0})
   ,.penable(penable)
   ,.pwrite(pwrite)
   ,.pwdata(pwdata)
   ,.pstrb(pstrb)
   ,.pready({pready_1, pready_0})
   ,.prdata({prdata_1, prdata_0})
   ,.pslverr({pslverr_1, pslverr_0})
  );
```

コマンドのタイミング (サイクル 0 の終わりのクロックエッジで `cmd_valid && cmd_ready` が成立):

```
サイクル    0    1    2   ...  n    n+1
cmd_valid   1    0    0   ...  0    0
cmd_ready   1    0    0   ...  0    1     受付後は完了まで 0
busy        0    1    1   ...  1    0
done        0    0    0   ...  1    0     busy の最終サイクルに 1 サイクルだけ 1
err_flags   -    -    -   ...  E    E     done と同じサイクルで見る (次の受付まで保持)
```

`n` の値は下の「転送速度」を参照。

ローカルポートのタイミング (サイクル 0 と 1 で読み出し、サイクル 2 で書き込みを受け付けた場合):

```
サイクル    0    1    2    3
mem_valid   1    1    1    0
mem_ready   1    1    1    1
mem_write   0    0    1    -
mem_addr    A0   A1   A2   -
mem_rvalid  0    1    1    0     読み出しを受け付けた次のサイクルだけ 1
mem_rdata   -    D0   D1   -     mem_rvalid=1 のサイクルだけ有効
```

コマンドを受け付けるサイクルはまだアイドルなので、同じサイクルに出したローカルアクセスも受け付ける。
その書き込みは、同時に受け付けたコマンドが送るデータに反映される。読み出しは、次のサイクルにコマンド開始前の値が返る。

## 動作

1. コマンドを受けると内容を検査する。誤りがあれば転送せずに `err_flags[2]` で返す
2. 書き込み: 内部メモリから 1 ワード読み、APB の書き込み転送を 1 回行う。これを `cmd_len` 回繰り返す
3. 読み出し: APB の読み出し転送を行い、`PRDATA` を内部メモリに書く。これを `cmd_len` 回繰り返す
4. 全ての転送の応答を受けたら `done`

APB の 1 転送 (AMBA APB Protocol Specification, Arm IHI 0024E 4.1 Operating states):

```
               IDLE  SETUP ACCESS ACCESS SETUP ACCESS IDLE
PSEL[s]         0     1     1      1      1     1      0
PENABLE         0     0     1      1      0     1      0
PREADY[s]       x     x     0      1      x     1      x
PADDR / PWDATA  -     A0    A0     A0     A1    A1     -
                            ^ウェイト     ^次の転送があれば IDLE を挟まず SETUP へ (back-to-back)
```

- SETUP から転送完了まで `PADDR` / `PPROT` / `PWRITE` / `PWDATA` / `PSTRB` は変えない
- 1 コマンドの中の転送は IDLE を挟まずに続ける (2 本目以降は、前の転送が終わった次のサイクルが SETUP)。
  ウェイトが入っても同じ
- 読み出しでは `PSTRB` を全て 0 にする (IHI 0024E 3.2)
- `PSLVERR` は `PSEL && PENABLE && PREADY` のサイクルだけ見る (IHI 0024E 3.4)
- `PENABLE=0` のときの `PREADY` は見ない
- APB の出力は全てレジスタから直接出している (組合せ回路を通らない)

### 転送速度

1 転送は SETUP 1 サイクル + ACCESS (1 + ウェイト数) サイクルで、1 コマンドの中の転送の間に空きサイクルは入らない。
`PREADY` が常に 1 なら 2 サイクルに 1 転送 (APB の最短)。

コマンドを受け付けてから `done` までのサイクル数 (上のタイミング図の `n`):

| コマンド | `n` | ウェイトが無いとき |
| --- | --- | --- |
| 書き込み | 4 + 各転送のサイクル数の合計 | `2 × cmd_len + 4` |
| 読み出し | 3 + 各転送のサイクル数の合計 | `2 × cmd_len + 3` |
| 転送しないコマンド (0 ワード / 誤りのあるコマンド) | 1 | 1 |

- 固定ぶんは、書き込みが 4 サイクル (内部メモリの読み出し、要求、最後の応答、`done`)、
  読み出しが 3 サイクル (要求、最後の応答 = 内部メモリへの書き込み、`done`)
- タイムアウトで打ち切った転送は SETUP 1 サイクル + ACCESS `TIMEOUT_CYCLES` サイクル
- `STOP_ON_ERROR=1` でエラーになったときは、エラーの転送までを数える
- 簡易 TB と UVM の scoreboard は、全てのコマンドでこのサイクル数を照合している

### エラー時の動作

| | `STOP_ON_ERROR=1` (既定) | `STOP_ON_ERROR=0` |
| --- | --- | --- |
| エラー (PSLVERR / タイムアウト) の後 | 残りの転送を中止する。エラーより後の転送はバスに出ない | 最後まで転送する |
| `done_count` | `err_index + 1` | `cmd_len` |
| `err_index` | エラーになった転送 | 最初にエラーになった転送 |

- エラーになった読み出しのデータは内部メモリに書かない (そのワードは元の値のまま)
- エラーになった書き込みが相手に反映されたかどうかは、相手のスレーブ次第
  (IHI 0024E 3.4: "Transactions that receive an error might or might not have changed the state of the peripheral")

### タイムアウト

APB には転送を打ち切る規定が無く、スレーブが `PREADY` を返さないとマスタは待ち続ける。
`TIMEOUT_CYCLES > 0` にすると、ACCESS が `TIMEOUT_CYCLES` サイクル続いても `PREADY` が来ないときに
`PSEL` / `PENABLE` を下げて転送を打ち切り、`err_flags[1]` で通知する
(待てるウェイトは `TIMEOUT_CYCLES-1` サイクルまで)。

これはバスのハングから復帰するための**仕様外の動作**なので、既定 (0) では無効にしてある。
打ち切られたスレーブは転送の途中の状態で残るので、使う場合はスレーブ側をリセットできる構成にしておく。
`STOP_ON_ERROR=0` のときは、打ち切った次のサイクルから次の転送の SETUP に入る
(1 コマンドの相手は同じスレーブなので、その間 `PSEL` は下がらない)。

### コマンドの誤り (`err_flags[2]`。転送は行わない)

| 条件 | 理由 |
| --- | --- |
| `cmd_sel >= NUM_SLAVES` | その番号の `PSEL` が無い |
| `cmd_mem_addr + cmd_len > MEM_DEPTH` | 内部メモリの範囲を超える |
| `cmd_addr` が `DATA_WIDTH/8` の倍数でない | 非アラインの `PADDR` は、スレーブの動作が決まっていない (IHI 0024E: "the result is UNPREDICTABLE") |
| `cmd_incr=1` で `cmd_addr + cmd_len × DATA_WIDTH/8` が `2^ADDR_WIDTH` を超える | アドレスが一周してしまう |

`cmd_len = 0` は、他の項目が何であっても何もせずに `done` (エラーにしない)。

## 内部メモリ

- 1RW (シングルポート) の同期メモリ。`apb_master_sram_sp.sv` は動作モデルで、そのまま合成すれば
  フリップフロップになる。ワード数が多い場合はメモリコンパイラの 1RW マクロに置き換える
- 1 コマンドの中では読むだけか書くだけで、ローカルポートはアイドル時だけ受け付けるので、
  シングルポートで足りる
- 上位は読み出しデータを「読み出しの次の 1 サイクルだけ」使う。マクロの出力保持の仕様には依存しない
  (`+define+APB_MASTER_SRAM_POISON` を付けると、それ以外のサイクルの読み出しデータを乱数にして確認できる。
  同梱の Makefile は常にこれを付けている)
- リセットでは内容を消さない。ローカルポートの `MEM_DEPTH` 以上のアドレスは、書き込みを無視し、読み出しは 0 を返す
- 動作モデルにはシミュレーション用のチェックが入っている。合成時は `SYNTHESIS` を define して外す

## APB の版

| 相手 | つなぎ方 |
| --- | --- |
| APB4 | そのまま |
| APB3 (PSTRB / PPROT が無い) | `pstrb` / `pprot` を未接続にする。`cmd_strb` は全て 1 にする (バイト単位の書き込みはできない) |
| PREADY が無いスレーブ | その `pready` を 1 に固定する (IHI 0024E: "peripherals that have a fixed two cycle access can tie PREADY HIGH") |
| PSLVERR が無いスレーブ | その `pslverr` を 0 に固定する (IHI 0024E 3.4) |
| APB5 | PWAKEUP / USER 信号 / パリティは持っていない (下の提案を参照) |

## `apb_master_engine` を単体で使う場合

内部メモリを使わず、1 転送ずつ自分で制御したいときは `apb_master_engine` を直接使う。

| 信号 | 内容 |
| --- | --- |
| `req_valid` / `req_ready` | 要求 (valid/ready)。1 要求 = 1 転送 |
| `req_write` / `req_sel` / `req_addr` / `req_wdata` / `req_strb` / `req_prot` | 転送の内容 |
| `rsp_valid` | 応答。転送完了の次のサイクルに 1 サイクルだけ 1。要求を受けた順に出る |
| `rsp_rdata` / `rsp_slverr` / `rsp_timeout` | 読み出しデータ / PSLVERR を受けた / タイムアウトで打ち切った |
| `busy` | 転送中、または保留中の要求がある |

- 転送中にも次の要求を 1 つ先に受け付ける。`req_ready` は登録値だけで決まり、`PREADY` には依存しない
- `req_sel >= NUM_SLAVES` の要求は、バスには何も出さずに `rsp_slverr=1` を返す
- `FLUSH_ON_ERROR=1` にすると、エラーで終わった転送より後に受け付けていた要求を、バスに出さずに捨てる
  (捨てた要求には応答を返さない)。エラーの次のサイクルは `req_ready=0`
- アドレスのアラインは検査しない (上位の責任)

## 使用上の制約

- APB マスタは 1 クロック (`pclk`)。分周クロックで APB を動かす `PCLKEN` は持っていない
- 実行中のコマンドを中断する機能は無い (リセット以外)
- 1 コマンドの転送は、全て同じスレーブ・同じ方向・同じ `PSTRB` / `PPROT`
- アドレスは連続 (`cmd_incr=1`) か固定 (`cmd_incr=0`) のどちらか

## NI-700 との関係

Arm CoreLink NI-700 が持つ APB のインタフェースは、NoC 側がマスタになる PMNI (APB Master Network Interface) だけで、
外部の APB マスタを NoC に入れる口は無い。CPU から NoC 経由で APB スレーブのレジスタを読み書きするだけなら、
NI-700 の PMNI がその役目をするので、このモジュールは要らない (PMNI は APB3 / APB4 に対応し、1 個で最大 16 本の APB を持てる)。

このモジュールが役に立つのは、独自 IP の中から、ソフトを介さずに APB スレーブ (PHY や別 IP の設定レジスタなど) を
読み書きしたい場合。

## 他に調整できるようにしておくとよい項目 (提案)

### 今回 parameter / ポートにしたもの

| 項目 | parameter / ポート | 調整する理由 |
| --- | --- | --- |
| アドレス幅 / データ幅 | `ADDR_WIDTH` / `DATA_WIDTH` | APB は PADDR 32bit まで、データ 8 / 16 / 32bit |
| スレーブ数 | `NUM_SLAVES` | `PSEL` の本数。応答の選択も中で行う |
| 内部メモリの深さ | `MEM_DEPTH` | 1 コマンドで運べる最大ワード数でもある |
| タイムアウト | `TIMEOUT_CYCLES` | スレーブが応答しないときにハングしない |
| エラー時の方針 | `STOP_ON_ERROR` / `err_index` / `done_count` | レジスタ設定の途中で失敗したら、そこで止めて場所を知りたい |
| `PSTRB` / `PPROT` | `cmd_strb` / `cmd_prot` | コマンドごとに変えられる |

### 今回は入れていないが、検討をお勧めするもの

| 項目 | 内容 | 入れる場面 |
| --- | --- | --- |
| アドレスデコード | `cmd_sel` の代わりに、`PADDR` の上位ビットから `PSEL` を決める | スレーブを番号ではなくアドレスマップで扱いたい場合 |
| アドレス付きのテーブル | 内部メモリに {アドレス, データ} の組を持ち、飛び飛びのレジスタを 1 コマンドで設定する | 初期設定シーケンスに使う場合 (いまは連続か固定のアドレスだけ) |
| ポーリング | 読んだ値がマスク付きで期待値になるまで繰り返す | ステータスレジスタのビットを待つ場合 |
| `PCLKEN` | クロックイネーブルで APB だけ遅く動かす | 相手が分周クロックの場合 |
| PWAKEUP (APB5) | 転送の前に立てて、スレーブ側のクロックを起こす | スレーブをクロックゲートする場合 |
| USER 信号 (APB5) | `PAUSER` / `PWUSER` / `PRUSER` / `PBUSER` | システムがサイドバンドを使う場合 |
| パリティ保護 (APB5) | `PADDRCHK` などの `*CHK` 信号 | 機能安全の要求がある場合 |
| 低消費電力インタフェース | `busy` を元に Q-Channel を付ける | このモジュール自体をクロックゲートする場合 |
| レジスタの直接出力 | 内部メモリの内容を信号として並列に出す | 読んだ値を常時参照したい場合 (いまはローカルポートで 1 ワードずつ読む) |

### 既製 IP / 市販ツールで代替できる範囲

- **CPU から APB スレーブへのアクセス → NI-700 の PMNI** (上の「NI-700 との関係」)
- **APB プロトコルの確認 → Cadence の AMBA 向け VIP**
  同梱の TB のプロトコルチェック (スレーブモデルと SVA) は手作りのもの。サインオフでは市販の VIP を使うほうが確実。
  Cadence の AMBA 向け Simulation VIP は APB2 / APB3 / APB4 / APB5 に対応し、BFM・プロトコルチェック・カバレッジモデルを含む
- **内部メモリ → メモリコンパイラの 1RW マクロ** (ワード数が多い場合)

## シミュレーション (簡易 TB)

Verilator 5.052 で確認。

```
cd sim
make                  # エンジン単体 (8 構成) + トップ (8 構成)
make engine           # エンジン単体だけ
make top              # トップの全構成
make one CFG=c2       # トップを 1 構成だけ
make eng_one ECFG=e2  # エンジン単体を 1 構成だけ
make lint             # RTL を -Wall で lint (全構成)
make top EXTRA=-GN_RAND=5000     # ランダムなコマンドの本数を増やす (既定 200)
make engine EXTRA=-GN_REQ=20000  # エンジン単体の要求数を増やす (既定 300)
```

### 構成

| 名前 | 内容 |
| --- | --- |
| c1 | 既定 (アドレス 32bit、データ 32bit、スレーブ 1、メモリ 16 ワード、タイムアウト無し、エラーで中止) |
| c2 | データ 8bit、アドレス 12bit、スレーブ 3、メモリ 10 ワード、タイムアウト 8 |
| c3 | データ 16bit、アドレス 16bit、スレーブ 4、メモリ 64 ワード、エラーでも最後まで続ける |
| c4 | スレーブ 2、メモリ 256 ワード、タイムアウト 3、エラーでも最後まで続ける |
| c5 | メモリ 1 ワード、アドレス 8bit、タイムアウト 1 (ウェイトを許さない) |
| c6 | アドレス空間がメモリより狭い (アドレス 5bit、データ 16bit、メモリ 24 ワード)、スレーブ 5、タイムアウト 5 |
| c7 | データ 8bit、スレーブ 16、メモリ 7 ワード、タイムアウト 16、エラーでも最後まで続ける |
| c8 | アドレス 10bit、メモリ 3 ワード、タイムアウト 2、エラーでも最後まで続ける |

エンジン単体 (e1〜e8) は、データ幅 8 / 16 / 32、アドレス幅 3〜32、スレーブ 1〜16、タイムアウト 0〜16、
`FLUSH_ON_ERROR` 0 / 1 の組み合わせ (`sim/Makefile` の `ECFG_*`)。

### テスト項目 (トップ)

| テスト | 内容 |
| --- | --- |
| TEST1 | 基本 (内部メモリ全体を書く → 内部メモリを書き換える → 読み戻す)。所要サイクル数も確認 |
| TEST2 | 転送数とメモリ位置の端、固定アドレス、`PSTRB` (1 バイトずつ / 0)、`PPROT` 全値 |
| TEST3 | スレーブごとに書いて読む (他のスレーブを触らないこと) |
| TEST4 | ウェイトあり (乱数 / 上限) |
| TEST5 | PSLVERR (先頭 / 中間 / 最後の転送、全転送)。その後の正常なコマンド |
| TEST6 | タイムアウト (上限ちょうどのウェイトは完了、1 超えると打ち切り、応答しないワード) |
| TEST7 | コマンドの誤り (メモリ範囲 / スレーブ番号 / 非アライン / アドレス空間の末尾)、0 ワード |
| TEST8 | ローカルポート (連続読み出し、範囲外アドレス、コマンドと同じサイクルの書き込み / 読み出し、実行中は待たされること) |
| TEST9 | busy 中に次のコマンドを出したまま待つ |
| TEST10 | ランダムなコマンド (ウェイト / PSLVERR / ハング / 誤ったコマンドを混ぜる) |
| TEST11 | コマンド実行中のリセット |

コマンドごとに次を確認している。

- `done_err` / `err_flags` / `err_index` / `done_count`
- 受付から `done` までのサイクル数 (上の「転送速度」の式。転送の前後や間に余分なサイクルが無いこと)
- 転送が IDLE を挟まずに続くこと (前の転送の直後に始まった転送の数 == 転送数 - 1)
- バス上の転送の列 (スレーブ番号 / アドレス / 方向 / PWDATA / PSTRB / PPROT / PSLVERR) と、余分な転送が無いこと
- 書き込み: スレーブのメモリ (PSTRB のバイトだけ更新、エラーの転送は反映しない)
- 読み出し: 内部メモリ (エラーの転送のワードは元の値のまま)。内部メモリは毎回全ワードを読み直して照合
- 常時: ステータス信号の関係、`mem_rvalid` のタイミング、PSEL が同時に 2 本立たない、
  スレーブモデルのプロトコルチェック 0 件、打ち切った転送数 == タイムアウトの期待数、内部メモリの範囲外アクセス 0 件

スレーブモデルは、仕様上「見てはいけない」タイミングの出力 (`PENABLE=0` のときの `PREADY`、
完了サイクル以外の `PSLVERR` / `PRDATA`、選択されていないスレーブの出力) を乱数にしている。

### 実行結果 (この環境)

Verilator 5.052 で全て PASS。ビルド時の警告は 0 件 (警告はエラー扱いでビルドしている)。
RTL は 8 構成とも `verilator --lint-only -Wall` で警告 0 件。

```
$ make lint
lint c1 : clean   ...   lint c8 : clean

$ make
engine e1 : PASS  []
engine e2 : PASS  [-GNUM_SLAVES=3 -GTIMEOUT_CYCLES=6 -GFLUSH_ON_ERROR=1]
engine e3 : PASS  [-GDATA_WIDTH=8 -GADDR_WIDTH=5 -GNUM_SLAVES=2 -GTIMEOUT_CYCLES=1]
engine e4 : PASS  [-GDATA_WIDTH=16 -GADDR_WIDTH=12 -GNUM_SLAVES=5 -GFLUSH_ON_ERROR=1]
engine e5 : PASS  [-GTIMEOUT_CYCLES=2 -GFLUSH_ON_ERROR=1]
engine e6 : PASS  [-GNUM_SLAVES=4 -GTIMEOUT_CYCLES=3]
engine e7 : PASS  [-GADDR_WIDTH=3 -GNUM_SLAVES=2 -GFLUSH_ON_ERROR=1]
engine e8 : PASS  [-GDATA_WIDTH=8 -GNUM_SLAVES=16 -GTIMEOUT_CYCLES=16 -GFLUSH_ON_ERROR=1]
top c1 : PASS  []
top c2 : PASS  [-GDATA_WIDTH=8 -GADDR_WIDTH=12 -GNUM_SLAVES=3 -GMEM_DEPTH=10 -GTIMEOUT_CYCLES=8]
top c3 : PASS  [-GDATA_WIDTH=16 -GADDR_WIDTH=16 -GNUM_SLAVES=4 -GMEM_DEPTH=64 -GSTOP_ON_ERROR=0]
top c4 : PASS  [-GNUM_SLAVES=2 -GMEM_DEPTH=256 -GTIMEOUT_CYCLES=3 -GSTOP_ON_ERROR=0 -GN_RAND=60]
top c5 : PASS  [-GADDR_WIDTH=8 -GMEM_DEPTH=1 -GTIMEOUT_CYCLES=1]
top c6 : PASS  [-GADDR_WIDTH=5 -GDATA_WIDTH=16 -GNUM_SLAVES=5 -GMEM_DEPTH=24 -GTIMEOUT_CYCLES=5]
top c7 : PASS  [-GDATA_WIDTH=8 -GNUM_SLAVES=16 -GMEM_DEPTH=7 -GTIMEOUT_CYCLES=16 -GSTOP_ON_ERROR=0]
top c8 : PASS  [-GADDR_WIDTH=10 -GMEM_DEPTH=3 -GTIMEOUT_CYCLES=2 -GSTOP_ON_ERROR=0]
```

`make` (16 本のビルドと実行) は、この環境 (2 コア) で約 2 分
(ccache 無しで 2 分 8 秒。同じソースのビルド結果を ccache が持っていれば 30〜45 秒)。
シミュレーション自体は 1 本 1 秒未満で、ほとんどがビルドの時間。

トップの 1 本あたりの規模 (各ログ `sim/<構成>.log` の集計行から):

```
構成  コマンド  書き込み  読み出し  断った  0 ワード  PSLVERR あり  タイムアウトあり  バス転送  打ち切り  最大ウェイト
c1    268       117       106       35      10        57            0                 1863      0         4
c2    280       118       131       20      11        43            41                1275      41        7
c3    270       122       111       24      13        57            0                 8579      0         4
c4    141       63        62        11      5         19            17                20850     661       2
c5    276       114       120       24      18        64            28                207       28        0
c6    287       102       98        69      18        55            25                1421      25        4
c7    304       136       143       13      12        63            38                1223      74        15
c8    281       114       125       27      15        48            30                455       42        1
```

- 「断った」は `err_flags[2]` で返したコマンド。c6 はアドレス空間が狭いので多い
- 「PSLVERR あり」「タイムアウトあり」はコマンドの数、「打ち切り」は転送の数
  (`STOP_ON_ERROR=0` の c4 / c7 / c8 は、1 コマンドの中で複数の転送を打ち切ることがある)
- エンジン単体は、1 構成あたり 900〜1240 要求 (PSLVERR 53〜207 件、タイムアウト 0〜42 件、存在しないスレーブ番号 0〜87 件)

ランダムの本数を増やした実行も、全構成 PASS。

```
$ make top EXTRA=-GN_RAND=5000       # 8 構成の合計で約 4 万コマンド、バス転送 約 74 万回
$ make engine EXTRA=-GN_REQ=20000    # 1 構成あたり 6 万〜8 万要求
```

### 検証環境の検出力確認

RTL に 1 箇所ずつバグを入れ (66 種)、簡易 TB を流した結果。66 種すべてが、少なくとも 1 構成で FAIL になった。

転送エンジンに入れたバグ (29 種)。エンジン単体 TB の 5 構成 (e1 e2 e3 e5 e6) と、トップ TB の 2 構成 (c2 c3) で流した:

```
入れたバグ                                                             e1    e2    e3    e5    e6    c2    c3    最初に検出したチェック
読み出しで PSTRB を 0 にしない                                         検出  検出  検出  検出  検出  検出  検出  プロトコル: 読み出しで PSTRB が 0 でない
SETUP から PENABLE を立てる                                            検出  検出  検出  検出  検出  検出  検出  プロトコル: SETUP 無しの ACCESS
転送完了後に PENABLE を下げない                                        検出  検出  検出  検出  検出  検出  検出  モニタ: PENABLE=1 で PSEL が 1 本でない
転送完了後に PSEL を下げない                                           検出  検出  検出  検出  検出  検出  検出  プロトコル: SETUP の次が ACCESS でない
PREADY を待たずに転送を終える                                          検出  検出  -     検出  検出  検出  検出  応答に対応する転送が無い
PREADY=0 のときの PSLVERR で転送を終える                               検出  検出  -     検出  検出  検出  検出  応答に対応する転送が無い
書き込みの応答に PRDATA をそのまま出す                                 検出  検出  検出  検出  検出  -     -     書き込みの応答の rsp_rdata
PREADY を常にスレーブ 0 から取る                                       -     検出  検出  -     検出  検出  検出  プロトコル: 完了後も PENABLE=1
PRDATA を常にスレーブ 0 から取る                                       -     検出  検出  -     検出  検出  検出  rsp_rdata と PRDATA の照合
PSLVERR を常にスレーブ 0 から取る                                      -     検出  検出  -     検出  検出  検出  rsp_slverr と PSLVERR の照合
PSEL を常にスレーブ 0 に出す                                           -     検出  検出  -     検出  検出  検出  プロトコル: 完了後も PENABLE=1
保留レジスタが埋まっていても要求を受ける                               検出  検出  検出  検出  検出  検出  検出  転送の内容 (スレーブ / アドレス / 方向 / PPROT)
保留中の要求のデータを使わない                                         検出  検出  検出  検出  検出  検出  検出  PWDATA / PSTRB の照合
保留中の要求のアドレスを使わない                                       検出  検出  検出  検出  検出  検出  検出  転送の内容 (スレーブ / アドレス / 方向 / PPROT)
タイムアウトの判定が 1 サイクル遅い                                    -     検出  検出  検出  検出  検出  -     タイムアウト応答の期待値
上限のサイクルで PREADY が来ても打ち切る                               -     検出  検出  検出  検出  検出  -     予期しないタイムアウト応答
タイムアウトのカウンタを転送ごとに戻さない                             -     検出  検出  検出  検出  検出  -     予期しないタイムアウト応答
エラー後の要求を捨てない                                               -     検出  -     検出  -     検出  -     エラー応答のサイクルの req_ready
エラーの次のサイクルに要求を受けてしまう                               -     検出  -     検出  -     検出  -     エラー応答のサイクルの req_ready
エラー時に保留中の要求を残す                                           -     検出  -     検出  -     検出  -     存在しないスレーブ番号の応答
存在しないスレーブ番号でも PENABLE を出す                              検出  検出  -     検出  -     -     -     モニタ: PENABLE=1 で PSEL が 1 本でない
存在しないスレーブ番号をエラーにしない                                 検出  検出  -     検出  -     -     -     存在しないスレーブ番号の応答
ウェイト中にも応答を出す                                               検出  検出  -     検出  検出  検出  検出  応答に対応する転送が無い
PPROT を出さない                                                       検出  検出  検出  検出  検出  検出  検出  転送の内容 (スレーブ / アドレス / 方向 / PPROT)
転送完了から直接 SETUP に進まない (毎回 IDLE を挟む)                   検出  検出  検出  検出  検出  検出  検出  所要サイクル数 (連続転送)
タイムアウトを応答に出さない                                           -     検出  検出  検出  検出  検出  -     タイムアウト応答の期待値
打ち切り時に PSLVERR の値を拾う                                        -     検出  検出  検出  検出  検出  -     タイムアウト応答の期待値
要求を必ず保留レジスタに 1 サイクル置く (機能は同じで 1 サイクル遅い)  検出  検出  検出  検出  検出  検出  検出  所要サイクル数 (連続転送)
SETUP と ACCESS で PADDR が変わる                                      検出  検出  検出  検出  検出  検出  検出  プロトコル: 転送中に PADDR などが変化
```

トップ (シーケンサ / 内部メモリまわり) に入れたバグ (37 種)。トップ TB の 4 構成 (c1 c2 c3 c6) で流した:

```
入れたバグ                                                                c1    c2    c3    c6    最初に検出したチェック
メモリから読んだ直後のデータを使わない                                    検出  検出  検出  検出  PWDATA / PSTRB の照合
要求が待たされたときに書き込みデータを保持しない                          検出  検出  検出  検出  PWDATA / PSTRB の照合
アドレスを進めない                                                        検出  検出  検出  検出  転送の内容 (スレーブ / アドレス / 方向 / PPROT)
固定アドレスの指定を無視して進める                                        検出  検出  検出  検出  転送の内容 (スレーブ / アドレス / 方向 / PPROT)
アドレスを 1 バイトずつ進める                                             検出  -     検出  検出  転送の内容 (スレーブ / アドレス / 方向 / PPROT)
書き込み時にメモリの読み出し位置を進めない                                検出  検出  検出  検出  PWDATA / PSTRB の照合
読み出し時にメモリの書き込み位置を進めない                                検出  検出  検出  検出  内部メモリの照合
エラーになった読み出しのデータをメモリに書く                              検出  検出  検出  検出  内部メモリの照合
書き込みコマンドの応答でもメモリに書く                                    検出  検出  検出  検出  PWDATA / PSTRB の照合
エラーで中止しない (エンジンは要求を捨てる)                               検出  検出  -     検出  done が来ない (ハング検出)
err_index を最後のエラーで上書きする                                      -     -     検出  -     err_index
done_count に別のカウンタを出す                                           検出  検出  検出  検出  done_count
コマンドの誤りを検査しない                                                検出  検出  検出  検出  err_flags
0 ワードのコマンドでも誤りを報告する                                      検出  検出  検出  検出  err_flags
メモリ範囲ちょうどのコマンドを断る                                        検出  検出  検出  検出  err_flags
メモリ範囲を検査しない                                                    検出  検出  検出  検出  err_flags
アドレス空間の末尾ちょうどのコマンドを断る                                検出  検出  検出  検出  err_flags
アドレス範囲を検査しない                                                  検出  検出  検出  検出  err_flags
非アラインのアドレスを検査しない                                          検出  -     検出  検出  err_flags
スレーブ番号を検査しない                                                  検出  検出  -     検出  err_flags
cmd_strb を使わず全バイト書く                                             検出  検出  検出  検出  PWDATA / PSTRB の照合
cmd_prot を出さない                                                       検出  検出  検出  検出  転送の内容 (スレーブ / アドレス / 方向 / PPROT)
cmd_sel を使わずスレーブ 0 に出す                                         -     検出  検出  検出  転送の内容 (スレーブ / アドレス / 方向 / PPROT)
コマンド実行中もローカルポートを受け付ける                                検出  検出  検出  検出  モニタ: mem_ready と cmd_ready
ローカルポートの範囲外アドレスを検査しない                                -     検出  -     検出  内部メモリの範囲外アクセス
ローカルポートの書き込みでも mem_rvalid を出す                            検出  検出  検出  検出  モニタ: mem_rvalid のタイミング
err_flags の PSLVERR とタイムアウトを入れ替える                           検出  検出  検出  検出  err_flags
最後の 1 つ前の応答で完了にする                                           検出  検出  検出  検出  done_count
タイムアウトを PSLVERR として報告する                                     -     検出  -     検出  err_flags
次のコマンドで err_flags[0] を消さない                                    検出  検出  検出  検出  err_flags
読み出しの要求を 1 つ少なく出す                                           検出  検出  検出  検出  done が来ない (ハング検出)
ローカルポートの書き込みを握手なしで反映する                              検出  検出  検出  検出  PWDATA / PSTRB の照合
done_err にコマンドの誤りを含めない                                       検出  検出  検出  検出  done_err
コマンドと同じサイクルのローカルアクセスを黙って捨てる                    検出  検出  検出  検出  PWDATA / PSTRB の照合
コマンドと同じサイクルの読み出しで mem_rvalid を出さない                  検出  検出  検出  検出  TEST8: コマンドと同じサイクルの読み出し
書き込みの要求を 1 サイクル遅く出す (機能は同じで転送の間に IDLE が入る)  検出  検出  検出  検出  所要サイクル数
転送数を 1 少なく数える                                                   検出  検出  検出  検出  done_count
```

- 「-」は、その構成ではバグの影響が出ない組み合わせ。複数の構成で流す必要があることを示している
  - e1 / e5 はスレーブ 1 個なので、応答の選択のバグは出ない
  - e1 / c1 / c3 はタイムアウト無し。e1 / e3 / e6 / c3 はエラー後の要求を捨てない設定
    (`FLUSH_ON_ERROR=0` / `STOP_ON_ERROR=0`)。それぞれ、タイムアウト / 要求の破棄のバグは出ない
  - e3 は `TIMEOUT_CYCLES=1` (スレーブモデルがウェイトを入れない) なので、ウェイト中の振る舞いのバグは出ない
  - 存在しないスレーブ番号のバグは、その番号を `req_sel` で表せる構成 (e1 / e2 / e5) だけ。
    トップは、そのコマンドをエンジンに渡す前に断るので出ない
  - 「書き込みの応答に PRDATA をそのまま出す」は、トップが書き込みの `rsp_rdata` を使わないので、エンジン単体 TB だけが検出する
  - c2 はデータ 8bit (アドレスが 1 ずつ進むのが正しく、非アラインも無い)。c1 はスレーブ 1 個、
    c3 はスレーブ 4 個 (`cmd_sel` の全ての値が有効)。c1 / c3 はメモリが 2 のべき乗 (ローカルポートに範囲外のアドレスが無い)
  - 「err_index を最後のエラーで上書きする」は、1 コマンドで複数の転送がエラーになる `STOP_ON_ERROR=0` の構成 (c3) だけ
- 「最初に検出したチェック」は、検出した中で最も左の構成のログで、最初に出たエラー。
  「プロトコル:」はスレーブモデルのプロトコルチェック、「モニタ:」は TB の常時モニタ、
  それ以外はテスト側の照合 (コマンド / 応答ごとの期待値、所要サイクル数、内部メモリの動作モデルのチェックなど)
- この確認の過程で、TB に次のチェックを足した
  - **受付から `done` までのサイクル数を、全てのコマンドで照合**。
    「要求を必ず保留レジスタに 1 サイクル置く」は、転送の内容もデータも正しく、1 サイクル遅いだけのバグ。
    トップ TB では、このサイクル数の照合 (全コマンドと TEST1) だけが検出している
  - **IDLE を挟まずに転送が続くことを、コマンドごとに照合**。
    当初はテスト全体の合計で照合していたが、リセットのテスト (TEST11) で期待値を合わせ直していたため、
    それより前のずれが消えていた (「書き込みの要求を 1 サイクル遅く出す」を入れても、c2 では合計の照合が反応しなかった)
  - **コマンドと同じサイクルのローカルアクセス (TEST8)**。書き込みは、そのコマンドが送るワードを書き換えて
    `PWDATA` で確認する。読み出しは、次のサイクルのデータを確認する。
    「コマンドと同じサイクルのローカルアクセスを黙って捨てる」は、この `PWDATA` の照合が最初に検出している

UVM 環境での同様の確認は `uvm/README.md` を参照。

## 参考

- AMBA APB Protocol Specification (Arm IHI 0024E。信号一覧: 2.1 / 書き込み: 3.1 / PSTRB: 3.2 / 読み出し: 3.3 /
  PSLVERR: 3.4 / 状態遷移: 4.1):
  https://documentation-service.arm.com/static/63fe2c1356ea36189d4e79f3
- Arm CoreLink NI-700 TRM (PMNI = APB Master Network Interface、APB3 / APB4、1 個で最大 16 本の APB):
  https://documentation-service.arm.com/static/60acf9c4982fc7708ac1cde2
- Cadence AMBA VIP Solutions (APB2 / APB3 / APB4 / APB5 の Simulation VIP):
  https://www.cadence.com/en_US/home/tools/system-design-and-verification/verification-ip/simulation-vip/amba.html
- Verilator: エラボレーション時の `$error` (USERERROR、IEEE 1800-2023 20.11):
  https://verilator.org/guide/latest/warnings.html

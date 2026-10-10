# Verilator + UVM テストベンチ (apb_master_mem)

`rtl/apb_master_mem.sv` を Verilator と UVM で検証する環境。
制約付きランダム / 機能カバレッジ / clocking block / 仮想シーケンス / SVA を使っている。

## 動作確認した組み合わせ

| 項目 | バージョン |
| --- | --- |
| Verilator | 5.052 (git タグ `v5.052` からビルド) |
| UVM | IEEE 1800.2-2020.3.2 (`chipsalliance/uvm-verilator` のタグ `uvm-2020-3.2`) |
| SMT ソルバ | z3 4.8.12 |
| OS / C++ | Ubuntu 24.04 / g++ 13.3 |

## 構成

```
tb_top
 ├─ apb_if               APB (全スレーブぶん)。clocking block + SVA
 ├─ usr_if               コマンド / ステータス / ローカルポート。clocking block + SVA
 ├─ apb_master_mem       DUT
 └─ uvm_test_top         apbm_smoke_test / apbm_rand_test
     └─ env (apbm_env)
         ├─ usr_agt   sqr / drv (ローカルポートの読み書き、コマンド発行と done 待ち) / mon (ap_start, ap_done, ap_mem)
         ├─ apb_agt   rsp (全スレーブぶんの応答) / mon (転送ごとに apb_item)
         ├─ scb       転送の列・PWDATA・ステータス・所要サイクル数・スレーブのメモリ・内部メモリを照合
         ├─ cov       cg_cmd / cg_strb / cg_sel / cg_result / cg_err / cg_xfer / cg_abort / cg_local ほか
         ├─ vsqr      usr_sqr + スレーブのメモリ / 設定
         ├─ smem      全スレーブぶんのメモリ (responder / scoreboard / vsqr で共有)
         └─ cfg[]     スレーブごとの設定 (ウェイト / PSLVERR の範囲 / 応答しない範囲)
```

DUT がマスタなので、テストベンチ側の APB は応答する側 (Completer) になる。
スレーブの振る舞いは `apb_slv_cfg` に持たせ、仮想シーケンスがコマンドの合間に書き換える。
responder は、仕様上「見てはいけない」タイミングの `PREADY` / `PSLVERR` / `PRDATA` を乱数にしている。

## ファイル

```
uvm/
  tb/
    apbm_params_pkg.sv    ... DUT パラメータ (+define+APBM_xxx=値 で上書き)
    apb_if.sv             ... APB interface / clocking block / SVA
    usr_if.sv             ... ユーザ側 interface / clocking block / SVA
    apbm_uvm_pkg.sv       ... UVM パッケージ (型・コマンドの計算・各クラスの include)
    apb_item.svh          ... monitor が出す APB 転送 1 回分
    apb_slv_mem.svh       ... スレーブのメモリ (apb_slv_mem) とスレーブ設定 (apb_slv_cfg)
    apb_slv_agent.svh     ... APB スレーブの responder / monitor / agent
    usr_agent.svh         ... usr_item (制約) / mem_item / driver / monitor / agent
    apbm_scoreboard.svh   ... scoreboard
    apbm_coverage.svh     ... covergroup
    apbm_env.svh          ... 仮想 sequencer と env
    apbm_seq_lib.svh      ... 仮想シーケンス (smoke / rand)
    apbm_test_lib.svh     ... テスト
    tb_top.sv             ... トップ
  sim/
    Makefile
```

## テスト

| テスト | 内容 |
| --- | --- |
| `apbm_smoke_test` | 基本 (書く → 読み戻す)、転送数とメモリ位置の端、固定アドレス、`PSTRB` (1 バイトずつ / 0)、`PPROT` 全値、各スレーブ、ウェイト、PSLVERR (先頭 / 中間 / 最後 / 全ての転送)、タイムアウト (上限ちょうど / 上限 + 1 / 応答しないワード)、断るコマンド 4 種と 0 ワード 2 種、ローカルポート (空きサイクルあり / 範囲外アドレス / コマンドと同じサイクルの書き込み・読み出し)、アドレス空間の末尾 |
| `apbm_rand_test` | ランダムなコマンドを、ウェイトの設定 4 通りで各 `+CMD_NUM` 本 (4 本に 1 本は、同じサイクルにローカルポートでも 1 ワード書くか読む)。続けて PSLVERR 注入 (位置を変えて `+CMD_NUM` 本と、全ての転送が PSLVERR になる固定アドレスのコマンド 2 本)、タイムアウト注入、断るコマンド / 0 ワード、最後に通常のコマンド 1 本 |

どちらも、コマンドの後に内部メモリの全ワードをローカルポートで読み直す (scoreboard が照合する)。

## scoreboard のチェック内容

| タイミング | チェック |
| --- | --- |
| コマンド受付時 | そのコマンドで起こるはずの転送の列を作る (アドレス / PSLVERR になる転送 / 打ち切る転送 / どこで止まるか) |
| APB 転送ごと | 順番どおりで、スレーブ番号 / アドレス / 方向 / `PPROT` / `PSTRB` (読み出しは 0) が期待どおり |
| | 書き込み : `PWDATA` == 内部メモリの期待値 |
| | `PSLVERR` == 期待値。打ち切りは期待した転送だけで、ACCESS のサイクル数 == `TIMEOUT_CYCLES` |
| | 読み出し : `PRDATA` == スレーブのメモリの期待値 (スレーブ側の確認) |
| | 1 コマンドの中の 2 本目以降の転送は、前の転送が終わった次のサイクルに始まる (IDLE を挟まない)。コマンドの最初の転送は、前のコマンドの転送の直後ではない |
| コマンド完了時 | 期待した転送が全て出ていて余分が無い |
| | `done_err` / `err_flags` / `err_index` / `done_count` == 期待値 |
| | 受付から `done` までのサイクル数 == 期待値 (転送しないコマンドは 1。転送するコマンドは 書き込み 4 / 読み出し 3 + 各転送のサイクル数の合計) |
| | 書き込んだワードがスレーブのメモリに反映されている (`PSTRB` のバイトだけ) |
| ローカル読み出し | 読めたデータ == 内部メモリの期待値 (範囲外のアドレスは 0)。`mem_rvalid` が立っている |
| ローカルアクセス | コマンドの実行中に受け付けられていない |
| 終了時 | スレーブのメモリ全体 == 期待値 (触っていないはずの場所が変わっていないことを含む) |

内部メモリの期待値は、ローカルポートの書き込みと、読み出しコマンドの結果 (エラーの転送は更新しない) から作る。
スレーブのメモリの期待値は、最初のコマンドの時点の内容を写し、書き込みコマンドで更新する。

SVA (interface 内):

| interface | 内容 |
| --- | --- |
| `apb_if` | PSEL は同時に 2 本立たない、PENABLE=1 のときは PSEL がちょうど 1 本、SETUP は 1 サイクルで次は同じ PSEL の ACCESS、SETUP から完了まで PADDR / PPROT / PWRITE / PSTRB / PWDATA を変えない、ウェイト中は PSEL / PENABLE を保つ、打ち切りはタイムアウトの上限のサイクルだけ (そのサイクルでは必ず打ち切る)、完了の次のサイクルは PENABLE=0、読み出しでは PSTRB=0、PADDR はアライン |
| `usr_if` | `cmd_ready` / `mem_ready` は `busy` の反転、`done` は busy の最後の 1 サイクル、`done_err == |err_flags`、ステータスは次のコマンド受付まで変わらない、`mem_rvalid` は読み出しを受け付けた次のサイクルだけ、コマンド / ローカルアクセスの保持 (TB 側) |

`tb_top` では、アイドル中にバスへ何も出していないことと、内部メモリの動作モデルが数えている
範囲外アクセスも UVM のエラーにしている。

## 機能カバレッジ

| covergroup | 内容 |
| --- | --- |
| `cg_cmd` | 方向、転送数 (1 / 中間 / 最大)、アドレスの進め方 (固定 / インクリメント)、内部メモリの位置 (先頭 / 中間 / 末尾まで)、アドレス空間の末尾、`PPROT` 8 値、ウェイトの有無。方向 × 転送数、方向 × 進め方、方向 × ウェイトの cross |
| `cg_strb` / `cg_strb_part` | 書き込みの `PSTRB` (全て 0 / 全て 1) / 一部だけ 1 |
| `cg_sel` | スレーブ (最初 / 最後) × 方向 |
| `cg_result` ほか | 正常 / PSLVERR / メモリ範囲超え / アドレス範囲超え / 0 ワード。`cg_res_timeout` / `cg_res_align` / `cg_res_sel` : タイムアウト / 非アライン / 存在しないスレーブ番号 |
| `cg_err` | エラーになった転送の位置 (先頭 / 中間 / 最後) × 方向 |
| `cg_multi_err` | 1 コマンドの中でエラーになった転送の数 (1 つ / 2 つ以上)。エラーでも最後まで続ける構成 (`STOP_ON_ERROR=0`) だけ |
| `cg_xfer` | 転送ごと : 方向、ウェイト数 (0 / 1 / 2 以上)、back-to-back か、PSLVERR、アドレス空間の最後のワード。方向との cross |
| `cg_abort` | 打ち切った転送の方向 |
| `cg_local` / `cg_local_oor` | ローカルポート : 書き込み / 読み出し、連続アクセス、コマンドと同じサイクル (それぞれ書き込み / 読み出しとの cross) / 範囲外アドレス |

構成によって起こり得ない項目 (スレーブ 1 個での「最後のスレーブ」、タイムアウト無効での打ち切りなど) は、
その covergroup を生成しないことで分母から外している。

## 構成の切り替え

DUT のパラメータは `apbm_params_pkg.sv` の `` `define `` で決まり、Makefile の `CFG` で切り替える。

| CFG | 内容 |
| --- | --- |
| a | 既定 (アドレス 32bit、データ 32bit、スレーブ 3、メモリ 16 ワード、タイムアウト 6、エラーで中止) |
| b | データ 8bit、アドレス 12bit、スレーブ 1、メモリ 10 ワード、タイムアウト無し、エラーでも最後まで続ける |
| c | データ 16bit、アドレス 16bit、スレーブ 4、メモリ 64 ワード、タイムアウト 3、エラーでも最後まで続ける |

構成を足すときは Makefile に `CFG_x := +define+APBM_...` を追加する。
カバレッジを 100% にできるのは、メモリ 3 ワード以上、ウェイトを 2 サイクル以上許す構成
(`TIMEOUT_CYCLES` が 0 または 3 以上)。

## 環境構築 (RHEL 系の例)

動作確認は Ubuntu で行った。以下は同じ依存関係を dnf 向けに置き換えたもの。
RHEL 9 では flex の開発ヘッダや z3 のために CRB と EPEL を有効にする必要がある。

```
# 依存パッケージ
sudo dnf install -y git make autoconf flex bison gcc-c++ perl python3 help2man zlib-devel lz4-devel
sudo dnf install -y z3                       # EPEL 9 に z3 4.8.15 がある

# Verilator 5.052
git clone -b v5.052 https://github.com/verilator/verilator
cd verilator
autoconf
./configure --prefix=$HOME/tools/verilator-5.052
make -j$(nproc)
make install
export PATH=$HOME/tools/verilator-5.052/bin:$PATH

# UVM 1800.2-2020.3.2
git clone -b uvm-2020-3.2 https://github.com/chipsalliance/uvm-verilator $HOME/tools/uvm-verilator
```

## 実行

```
cd uvm/sim
make                                         # ビルド + apbm_smoke_test (CFG=a)
make run TEST=apbm_rand_test SEED=7 NUM=10   # テスト / シード / 本数を指定
make regress                                 # smoke + rand (SEEDS="1 2 3 4 5")
make regress CFG=b                           # 別の構成
make regress_all                             # 全構成で regress + カバレッジ表示
make cov CFG=a                               # その構成の全 run のカバレッジをマージして表示
make run WAVES=1                             # wave.fst を出力 (別ディレクトリに別ビルド)
make clean
```

`UVM_HOME` の既定は `$HOME/tools/uvm-verilator`。別の場所なら `make UVM_HOME=...` で指定する。

実行時の主な plusarg:

```
+UVM_TESTNAME=<test>        テスト選択 (既定 apbm_smoke_test)
+verilator+seed+<n>         乱数シード
+CMD_NUM=<n>                apbm_rand_test の各フェーズのコマンド数 (既定 8)
+CMD_TIMEOUT=<n>            握手 / 完了待ちの上限サイクル (既定 200000)
+UVM_VERBOSITY=UVM_HIGH     monitor の転送ログなどを表示
+UVM_MAX_QUIT_COUNT=<n>,NO  UVM_ERROR が n 件で打ち切る (Makefile は QUIT=200 を渡す)
```

所要時間とディスクの目安 (この環境、2 コア):

| 項目 | 目安 |
| --- | --- |
| ビルド (1 構成) | ccache 無しで約 2 分 (1 分 58 秒)。同じソースのビルド結果を ccache が持っていれば約 20 秒 |
| `apbm_smoke_test` | 1〜4 秒 (構成 a で 1.2 秒、c で 4.2 秒) |
| `apbm_rand_test` (`NUM=8`) | 4〜7 秒 |
| `apbm_rand_test` (`NUM=100`) | 約 50 秒 (構成 a) |
| `make regress_all` (3 構成のビルド + 18 本 + カバレッジ集計) | ccache が効いた状態で 2 分 18 秒〜4 分 3 秒 (2 回の実測)。ccache 無しでは、これに 3 構成ぶんのビルド時間が加わる |
| ビルドディレクトリ `obj_<CFG>` | 1 構成あたり約 0.9GB (g++ の最適化を切っているので大きい)。`make clean` で消える |

## 実行結果 (この環境)

3 構成 × (smoke 1 本 + rand 5 シード) の 18 本が全て PASS (UVM_ERROR / UVM_FATAL / UVM_WARNING とも 0)。
機能カバレッジは 3 構成とも 100% (bin の数は、構成 a が 107、b が 98、c が 108)。

```
$ make regress_all
[a] apbm_smoke_test seed=1 : PASS
[a] apbm_rand_test  seed=1 : PASS
[a] apbm_rand_test  seed=2 : PASS
[a] apbm_rand_test  seed=3 : PASS
[a] apbm_rand_test  seed=4 : PASS
[a] apbm_rand_test  seed=5 : PASS
[a]   covergroup : 100.0% (107/107)
[b] apbm_smoke_test seed=1 : PASS
[b] apbm_rand_test  seed=1 : PASS
[b] apbm_rand_test  seed=2 : PASS
[b] apbm_rand_test  seed=3 : PASS
[b] apbm_rand_test  seed=4 : PASS
[b] apbm_rand_test  seed=5 : PASS
[b]   covergroup : 100.0% (98/98)
[c] apbm_smoke_test seed=1 : PASS
[c] apbm_rand_test  seed=1 : PASS
[c] apbm_rand_test  seed=2 : PASS
[c] apbm_rand_test  seed=3 : PASS
[c] apbm_rand_test  seed=4 : PASS
[c] apbm_rand_test  seed=5 : PASS
[c]   covergroup : 100.0% (108/108)
```

1 本あたりの規模 (scoreboard の集計行から):

```
構成  テスト              コマンド  転送したもの  エラーフラグ付き  バス転送  打ち切り  ローカル書き込み  ローカル読み出し
a     apbm_smoke_test     69        63            20                672       8         386               898
a     apbm_rand_test s=1  59        53            24                482       10        135               949
b     apbm_smoke_test     49        43            12                322       0         134               424
b     apbm_rand_test s=1  49        43            14                252       0         68                492
c     apbm_smoke_test     69        63            20                3142      134       1538              3650
c     apbm_rand_test s=1  59        53            24                2291      74        515               3778
```

- 「転送したもの」に入らない 6 本は、断るコマンド 4 本と 0 ワードのコマンド 2 本
- 構成 b はタイムアウトが無いので、タイムアウトのフェーズのぶんコマンドが少ない

ログの末尾 (CFG=a、`apbm_rand_test`、シード 1):

```
UVM_INFO ../tb/apbm_coverage.svh(464) @ 35385000: uvm_test_top.env.cov [COV] cg_cmd = 100.0 %  cg_result = 100.0 %  cg_err = 100.0 %  cg_xfer = 100.0 %  cg_local = 100.0 %
UVM_INFO ../tb/apbm_scoreboard.svh(386) @ 35385000: uvm_test_top.env.scb [SCB] commands=59 (transferred 53, with error flags 24) bus transfers=482 aborted=10 local writes=135 local reads=949 errors=0
UVM_INFO ../tb/apbm_test_lib.svh(40) @ 35385000: uvm_test_top [TEST] ** TEST PASSED **

--- UVM Report Summary ---

Quit count :     0 of   200
** Report counts by severity
UVM_INFO :   73
UVM_WARNING :    0
UVM_ERROR :    0
UVM_FATAL :    0
```

(`[COV]` の行はその 1 本だけの値。全体の値は `make cov` で全 run をマージして出す。)

コマンド数を増やした実行 (`NUM=100`、シード 11 / 12 / 13) も、3 構成とも PASS (カバレッジ 100%)。
`apbm_rand_test` 1 本が、構成 a / c で 611 コマンド、b で 509 コマンドになる
(シード 11 のバス転送は、a が 5540 回、b が 3281 回、c が 26853 回)。

```
$ make regress CFG=a NUM=100 SEEDS="11 12 13"      # CFG=b / CFG=c も同様
[a] apbm_smoke_test seed=1 : PASS
[a] apbm_rand_test  seed=11 : PASS
[a] apbm_rand_test  seed=12 : PASS
[a] apbm_rand_test  seed=13 : PASS
```

`make run WAVES=1` (`apbm_smoke_test`) も PASS し、`wave.fst` (約 150KB) が出る。

## 検証環境の検出力確認

RTL に 1 箇所ずつバグを入れ (23 種)、`apbm_smoke_test` と `apbm_rand_test` (シード 1) を流した結果。
23 種すべてが `apbm_smoke_test` で FAIL になり、22 種は `apbm_rand_test` でも FAIL になった。
バグを入れない状態では、同じ手順で両方とも PASS する。

```
入れたバグ                                                                構成  smoke  rand   エラーを出したチェック
読み出しで PSTRB を 0 にしない                                            a     検出   検出   apb_if の SVA (読み出しの PSTRB)、SCB (転送の内容)
転送完了後に PENABLE を下げない                                           a     検出   検出   apb_if の SVA (PSEL 無しの PENABLE、完了後の PENABLE)、TOP_CHK (アイドル中のバス出力)
PREADY を待たずに転送を終える                                             a     検出   検出   apb_if の SVA (ウェイト中の保持)、SCB (内部メモリ、PREADY 無しの打ち切り、err_flags)
PSEL を常にスレーブ 0 に出す                                              a     検出   検出   SCB (内部メモリ、転送の内容、スレーブのメモリ)、apb_if の SVA (ウェイト中の保持、完了後の PENABLE)
保留中の要求のデータを使わない                                            a     検出   検出   SCB (スレーブのメモリ、PWDATA、内部メモリ)
タイムアウトの判定が 1 サイクル遅い                                       a     検出   検出   SCB (内部メモリ、余分な転送、打ち切りまでのサイクル数)、apb_if の SVA (上限での打ち切り、ウェイト中の保持)
エラー後の要求を捨てない                                                  a     検出   検出   TOP_CHK (アイドル中のバス出力)、SCB (コマンド外の転送、PRDATA、内部メモリ)
転送完了から直接 SETUP に進まない (毎回 IDLE を挟む)                      a     検出   検出   SCB (転送の間の IDLE、所要サイクル数)
要求を必ず保留レジスタに 1 サイクル置く (機能は同じで 1 サイクル遅い)     a     検出   検出   SCB (所要サイクル数)
要求が待たされたときに書き込みデータを保持しない                          a     検出   検出   SCB (PWDATA、スレーブのメモリ、内部メモリ)
読み出し時にメモリの書き込み位置を進めない                                a     検出   検出   SCB (内部メモリ、スレーブのメモリ、PWDATA)
エラーになった読み出しのデータをメモリに書く                              a     検出   検出   SCB (内部メモリ、スレーブのメモリ、PWDATA)
err_index を最後のエラーで上書きする                                      b     検出   検出   SCB (err_index)
err_index を最後のエラーで上書きする                                      c     検出   検出   SCB (err_index)
done_count に別のカウンタを出す                                           a     検出   検出   SCB (done_count)
コマンドの誤りを検査しない                                                a     検出   検出   apb_if の SVA (PADDR のアライン)、SCB (余分な転送、内部メモリ、スレーブのメモリ)
アドレス空間の末尾ちょうどのコマンドを断る                                a     検出   検出   SCB (転送の数、err_flags、done_count)
cmd_strb を使わず全バイト書く                                             a     検出   検出   SCB (スレーブのメモリ、転送の内容、PWDATA)
コマンド実行中もローカルポートを受け付ける                                a     検出   検出   usr_if の SVA (mem_ready と busy)
ローカルポートの範囲外アドレスを検査しない                                b     検出   -      MEM_CHK (内部メモリの範囲外アクセス)
タイムアウトを PSLVERR として報告する                                     c     検出   検出   SCB (err_flags)
コマンドと同じサイクルのローカルアクセスを黙って捨てる                    a     検出   検出   SCB (内部メモリ、スレーブのメモリ、PWDATA)、usr_if の SVA (mem_rvalid)
コマンドと同じサイクルの読み出しで mem_rvalid を出さない                  a     検出   検出   usr_if の SVA (mem_rvalid)、SCB (mem_rvalid)
書き込みの要求を 1 サイクル遅く出す (機能は同じで転送の間に IDLE が入る)  a     検出   検出   SCB (転送の間の IDLE、所要サイクル数)
```

- 「エラーを出したチェック」は、2 本のログに出た UVM_ERROR を件数の多い順に並べたもの (チェックごとに 3 項目まで)。
  SCB は scoreboard、TOP_CHK / MEM_CHK は `tb_top` のチェック (アイドル中のバス出力 / 内部メモリの動作モデルの範囲外アクセス)
- 「err_index を最後のエラーで上書きする」と「ローカルポートの範囲外アドレスを検査しない」は、構成 a では影響が出ないので、
  影響が出る構成で流した (a はエラーで中止するので、エラーになる転送は 1 コマンドに 1 つだけ。
  a のメモリは 16 ワードで、ローカルポートに範囲外のアドレスが無い)。
  「タイムアウトを PSLVERR として報告する」は、エラーでも最後まで続ける構成 c で流した
- 「ローカルポートの範囲外アドレスを検査しない」は `apbm_rand_test` では検出しない。ランダムテストは
  ローカルポートに範囲内のアドレスしか出さないため。範囲外のアドレスは `apbm_smoke_test` が確認している
- 当初のテストでは、1 コマンドの中で複数の転送がエラーになるのは、構成 c のタイムアウト
  (全ての転送を打ち切るフェーズ) だけだった。全ての転送が PSLVERR になるコマンドを smoke / rand の両方に足し、
  covergroup `cg_multi_err` を加えたので、「err_index を最後のエラーで上書きする」はタイムアウトの無い構成 b でも検出する
- 「要求を必ず保留レジスタに 1 サイクル置く」は、転送の内容もデータも正しく 1 サイクル遅いだけのバグで、
  scoreboard の所要サイクル数の照合だけが検出している
- エラーの多いバグでは、`+UVM_MAX_QUIT_COUNT=200,NO` により 200 件で打ち切られる

## Verilator 5.052 で動かすための注意点

これまでに踏んだものを含め、この環境で守っていること。

1. **駆動は `@(vif.xx_cb)` の直後に行う**
   `get_next_item()` はデルタサイクルを消費するので、その後に `@(vif.drv_cb)` で同期してから駆動する。
   VALID は clocking block で `inout` にし、握手は VALID と READY の両方のサンプル値で判定する。

2. **`dist` と `randomize() with` の値固定を併用しない** (`UNSATCONSTR` になる)

3. **`randomize() with` と rand 動的配列の `size()` 制約を併用しない**

4. **`with {}` 内のローカル変数名を、item のメンバ名や制約ブロック名と重ねない**

5. **`// Verilator ...` で始まるコメントを書かない** (メタコメント扱いで `BADVLTPRAGMA`)

6. **実行時に z3 が必要** (`VERILATOR_SOLVER` で変更可)。FST 波形には lz4 の開発ヘッダも必要

7. **UVM 基底クラスのメソッド名 (`copy` / `compare` / `print` / `clone` など) と同じ名前のメソッドを作らない**

8. **制約式に乗算や加算を書かない**
   制約式も通常の式と同じビット幅規則で評価されるので、桁あふれした解をソルバが選べてしまう
   (Verilator 固有ではない)。`usr_item` はランダム化する項目を単純な範囲制約だけにし、
   メモリ範囲やアドレス空間に収まる位置は `post_randomize()` で計算している。

9. **enum の coverpoint は bins を明示する**
   基底型が `int` の enum を auto bins に任せると、Verilator 5.052 では値ごとの bin ではなく
   64 個の範囲 bin になった。LRM では enum は値ごとに 1 bin。

10. **driver は done を見てから 1 サイクル待って `item_done()` する**
    driver と monitor は同じクロックエッジで done を見る。先にシーケンスへ戻すと、次の操作の準備
    (スレーブ設定の書き換え) が scoreboard の照合より先に走り得る。

11. **エラボレーション時の `$error` は `-Wno-fatal` で警告に下がる**
    UVM ライブラリのために `-Wno-fatal` を付けているので、`-Werror-USERERROR` を併用して
    パラメータチェックがエラーで止まるようにしている。

12. **長さの違う文字列リテラルを `?:` で選んで `%s` に渡さない**
    `wr ? "WRITE" : "READ"` のように書くと、短いほうは長いほうの幅に合わせて上位に 0 が詰められ、
    ログでは先頭に余分な空白が出た。`if` で分けるか、`string` 型の変数に入れてから渡している。

13. **ビルドディレクトリが大きい**
    g++ の最適化を切っている (`--CFLAGS -O0`) ので、`obj_<CFG>` が 1 構成あたり約 0.9GB になる。
    構成を増やしたり、バグ注入のように何度もビルドするときは、使い終わったものを消す。

## Xcelium で流す場合 (参考・この環境では未実行)

```
xrun -64bit -sv -uvm -uvmhome $UVM_HOME -timescale 1ns/1ps \
     -incdir ../tb \
     ../tb/apbm_params_pkg.sv ../tb/apb_if.sv ../tb/usr_if.sv ../tb/apbm_uvm_pkg.sv \
     -F ../../rtl/filelist.f ../tb/tb_top.sv \
     +UVM_TESTNAME=apbm_rand_test -svseed 1 +CMD_NUM=8
```

(`-F` はファイルリスト内のパスを、そのファイルの場所からの相対として読む。)

## 参考

- Verilator Revision History (5.052: "Verilator now supports UVM 2020-3.2"):
  https://verilator.org/guide/latest/changes.html
- Verilator Errors and Warnings (USERERROR: エラボレーション時の `$error`):
  https://verilator.org/guide/latest/warnings.html
- Verilator インストール手順 (z3 / VERILATOR_SOLVER):
  https://verilator.org/guide/latest/install.html
- chipsalliance/uvm-verilator (UVM 2020.3.2):
  https://github.com/chipsalliance/uvm-verilator
- Accellera UVM ダウンロード:
  https://www.accellera.org/downloads/standards/uvm
- Siemens Verification Horizons, A Little Verilog Knowledge Goes A Long Way in Understanding
  How SystemVerilog Constraints Work (制約式のビット幅と桁あふれ):
  https://blogs.sw.siemens.com/verificationhorizons/2019/09/12/verilog-in-constraints/
- AMBA APB Protocol Specification (Arm IHI 0024E):
  https://documentation-service.arm.com/static/63fe2c1356ea36189d4e79f3

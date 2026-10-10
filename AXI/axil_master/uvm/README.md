# Verilator + UVM テストベンチ (axil_master_mem + axil_to_axi4)

`rtl/axil_master_mem.sv` と `rtl/axil_to_axi4.sv` を、Verilator と UVM で検証する環境。
制約付きランダム / 機能カバレッジ / clocking block / 仮想シーケンス / SVA を使っている。
書き込みコマンド・読み出しコマンド・ローカルポートを別々の sequencer で同時に動かす。

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
 ├─ usr_if               書き込み / 読み出しコマンド、ステータス、ローカルポート。clocking block + SVA
 ├─ axil_master_mem      DUT (AXI4-Lite マスタ)
 ├─ axil_to_axi4         DUT (AXI4-Lite → AXI4 + AWAKEUP)
 ├─ axi_if               AXI4 (変換の出口)。clocking block + SVA
 └─ uvm_test_top         axlm_smoke_test / axlm_rand_test
     └─ env (axlm_env)
         ├─ usr_agt   wsqr / wdrv (書き込みコマンド)、rsqr / rdrv (読み出しコマンド)、lsqr / ldrv (ローカルポート)
         │            mon (ap_wstart / ap_wdone / ap_rstart / ap_rdone / ap_mem)
         ├─ axi_agt   rsp (スレーブの応答) / mon (応答まで完了したトランザクションごとに axi_item)
         ├─ scb       トランザクションの列・WDATA・応答・ステータス・所要サイクル数・スレーブのメモリ・内部メモリを照合
         ├─ cov       cg_cmd / cg_len / cg_result / cg_err / cg_stop / cg_conc / cg_held / cg_wr_tr / cg_rd_tr / cg_depth / cg_local ほか
         ├─ vsqr      3 つの sequencer + スレーブのメモリ / 設定
         ├─ smem      スレーブのメモリ (responder / scoreboard / vsqr で共有)
         └─ cfg       スレーブの設定 (READY の確率、AWREADY / WREADY の待ち合わせ、応答の遅延、エラー応答の範囲 2 つずつ)
```

DUT がマスタなので、テストベンチ側の AXI は応答する側 (Subordinate) になる。
スレーブの振る舞いは `axi_slv_cfg` に持たせ、仮想シーケンスが (全てのコマンドが完了してから) 書き換える。
responder は、仕様上「見てはいけない」値 (`BVALID=0` のときの `BRESP`、`RVALID=0` のときの `RDATA` / `RRESP`、
`axil_to_axi4` が見ない `BID` / `RID` / `RLAST`) を乱数にしている。

## ファイル

```
uvm/
  tb/
    axlm_params_pkg.sv    ... DUT パラメータ (+define+AXLM_xxx=値 で上書き)
    axi_if.sv             ... AXI4 interface / clocking block / SVA
    usr_if.sv             ... ユーザ側 interface / clocking block / SVA
    axlm_uvm_pkg.sv       ... UVM パッケージ (型・共通の計算・各クラスの include)
    axi_item.svh          ... monitor が出す AXI トランザクション
    axi_slv_mem.svh       ... スレーブのメモリ (axi_slv_mem) とスレーブ設定 (axi_slv_cfg)
    axi_slv_agent.svh     ... AXI スレーブの responder / monitor / agent
    usr_items.svh         ... cmd_item (制約) / loc_item / mem_item
    usr_agent.svh         ... コマンドの driver (方向ごと) / ローカルポートの driver / monitor / agent
    axlm_scoreboard.svh   ... scoreboard
    axlm_coverage.svh     ... covergroup
    axlm_env.svh          ... 仮想 sequencer と env
    axlm_seq_lib.svh      ... 仮想シーケンス (smoke / rand)
    axlm_test_lib.svh     ... テスト
    tb_top.sv             ... トップ
  sim/
    Makefile
```

## テスト

| テスト | 内容 |
| --- | --- |
| `axlm_smoke_test` | 基本 (書き出す → 読み戻す)、書き込みと読み出しを同じサイクルに受け付けて同時に流す、転送数とメモリ位置の端、固定アドレス、`WSTRB` (1 バイトずつ / 一部 / 0)、`PROT` 全値、アドレス空間の一番上と一番下、エラー応答 (SLVERR / DECERR / EXOKAY × 先頭 / 中間 / 最後、全て、隣り合う 2 種類)、長い応答の遅延 (未完了数が上限まで)、READY / 遅延が乱数 (AWREADY は W を待つ / WREADY は AW を待つ、も含む) の読み書き同時、断るコマンド 3 種と 0 ワード 2 種 (反対方向の実行中にも)、ローカルポート (空きサイクルあり / 連続 / 範囲外アドレス / 読み書き同時 / コマンドと同じサイクル / 実行中に受け付けられる / 待たされる)、実行中に次のコマンドを出したまま待つ |
| `axlm_rand_test` | 8 ラウンド。各ラウンドで、書き込みコマンド・読み出しコマンド (各 `+CMD_NUM` 本、1 割は断るコマンドか 0 ワード) とローカルポートの操作 (`+CMD_NUM` 回、範囲外アドレスも混ぜる) を 3 つのスレッドで同時に流す。スレーブはラウンドごとに、理想的 (READY が常に 1、遅延 0。ラウンド 0 / 3 / 4 / 7) / READY と遅延が乱数 (AW / W の待ち合わせ 4 通り) を切り替える。奇数ラウンドではエラー応答の範囲を読み書き 2 つずつ置き (1 つ目の応答の種類はラウンドごとに SLVERR / DECERR / EXOKAY を回し、2 つ目は乱数)、コマンドの途中でエラーになるよう長いコマンドを多めにする (このラウンドは内部メモリを書き込み / 読み出しで半分ずつ使う)。ラウンド 3 / 7 は理想的なスレーブでエラー応答があるので、`STOP_ON_ERROR=1` で止めるまでに出す数も正確に照合する。最後に断るコマンド / 0 ワードと、アドレス空間の一番上でちょうど終わるコマンド (読み書き 4 本ずつ) |

- 同時に動かす書き込みと読み出しは、スレーブのアドレスを別の窓に分け、内部メモリの範囲は仮想シーケンスが
  使用中の範囲を管理して重ならないようにしている (重なったときの結果は仕様上決まらない)。
  scoreboard は、重なったら「テストベンチの誤り」として報告する
- ラウンドの後には内部メモリの全ワードをローカルポートで読み直す (scoreboard が照合する)

## scoreboard のチェック内容

書き込みと読み出しは、別々の期待値で追う。

| タイミング | チェック |
| --- | --- |
| コマンド受付時 | そのコマンドで出るはずのトランザクションの列を作る (アドレス / 応答 / 書き込みデータ = 受付時の内部メモリ) |
| トランザクションごと | 順番どおりで、アドレス / `PROT` / `WSTRB` / 応答が期待どおり。書き込みは `WDATA` == 内部メモリの期待値 |
| | 読み出し : OKAY なら `RDATA` == スレーブのメモリの期待値 (スレーブ側の確認) で、内部メモリの期待値を更新 |
| コマンド完了時 | `*_done_count` == バスで完了した数。`STOP_ON_ERROR=1` でエラーがあれば `err_index+1 .. err_index+MAX`、理想的なスレーブでは正確な数 (エラー応答を受けたサイクルで止まるときの数)。エラーが無ければ全数 |
| | `*_err_flags` / `*_done_err` == 実際に受けた応答の種類 (+ コマンドの誤り)。`*_err_index` == 最初のエラー応答 |
| | 理想的なスレーブでは、受付から `*_done` までのサイクル数 == 書き込み 7 + f(n-1) / 読み出し 5 + f(n-1) / 転送しないコマンド 1 |
| | 書き込んだワードがスレーブのメモリに反映されている (`WSTRB` のバイトだけ) |
| ローカル読み出し | 読めたデータ == 内部メモリの期待値 (範囲外のアドレスは 0)。`mem_r_rvalid` が立っている。書き込みコマンドの実行中に受け付けられていない |
| ローカル書き込み | 読み出しコマンドの実行中に受け付けられていない |
| (テストベンチの誤り) | 同時に実行中の書き込み / 読み出しコマンドの内部メモリ範囲やスレーブのアドレスが重なる、実行中のコマンドの範囲をローカルポートで触る |
| 終了時 | スレーブのメモリ全体 == 期待値 (触っていないはずの場所が変わっていないことを含む) |

SVA (interface 内):

| interface | 内容 |
| --- | --- |
| `axi_if` | リセット中と解除後の最初のエッジで VALID=0、VALID は READY まで下げずペイロードも変えない (AW / W / AR、テストベンチ側の B / R も)、AXI4-Lite 相当の固定値 (`AxLEN=0` `AxSIZE` `AxBURST=INCR` `AxLOCK=0` `AxCACHE=0000` `AxID=0` `AxQOS` `WLAST=1`)、アドレスのアライン、`BREADY` / `RREADY` が常に 1、`AWAKEUP` (AxVALID / WVALID が 1、または未完了があれば 1)、バス上の未完了数 ≤ 上限 |
| `usr_if` | `*cmd_ready` は `*_busy` の反転、`mem_w_ready` は `rd_busy` の反転、`mem_r_ready` は `wr_busy` の反転、`*_done` は busy の最後の 1 サイクル、`*_done_err == |*_err_flags`、ステータスは次のコマンド受付まで変わらない、`mem_r_rvalid` は読み出しを受け付けた次のサイクルだけ、コマンド / ローカルアクセスの保持 (TB 側) |

`tb_top` では、アイドルの方向のバスに VALID を出していないこと、両方アイドルなら `AWAKEUP=0`、
内部メモリの動作モデルが数えている範囲外アクセス / 同じアドレスの同時読み書きも UVM のエラーにしている。

## 機能カバレッジ

| covergroup | 内容 |
| --- | --- |
| `cg_cmd` | 方向、アドレスの進め方、`PROT` 8 値、スレーブが理想的か。方向との cross |
| `cg_len` | 転送数 (1 / 中間 / 最大)、内部メモリの位置 (先頭 / 中間 / 末尾まで) × 方向 (メモリ 3 ワード以上の構成) |
| `cg_top` | アドレス空間の最後のワードで終わるコマンド × 方向 |
| `cg_strb` | 書き込みの `WSTRB` (全て 0 / 全て 1 / 一部) |
| `cg_result` ほか | 正常 / SLVERR / DECERR / EXOKAY / メモリ範囲超え / 非アライン / 0 ワード × 方向。`cg_res_range` : アドレス範囲超え、`cg_res_multi` : 1 コマンドで 2 種類以上のエラー応答 |
| `cg_err` | 最初のエラー応答の位置 (先頭 / 中間 / 最後) × 方向 |
| `cg_stop` | `STOP_ON_ERROR=1` のとき、途中で止まった / 最後まで出した × 方向 |
| `cg_conc` | 反対方向のコマンドの実行中に受け付けた / 同じサイクルに受け付けた × 方向 |
| `cg_held` | 実行中に出したまま待たされたコマンド × 方向 |
| `cg_wr_tr` | 書き込みトランザクション : AW と W の順 (AW が先 / W が先 / 同時)、応答 4 種、応答の遅延 (0 / 1〜3 / 4 以上)、読み出しと同時に未完了だったか |
| `cg_rd_tr` | 読み出しトランザクション : 応答 4 種、応答の遅延、書き込みと同時に未完了だったか |
| `cg_depth` | バス上の未完了数が上限に達した × 方向 |
| `cg_local` / `cg_local_oor` | ローカルポート : 書き込み / 読み出し × (連続アクセス / コマンドと同じサイクル / 反対方向のコマンドの実行中 / 待たされた) / 範囲外アドレス |

構成によって起こり得ない項目 (メモリ 2 ワード以下での転送数の中間、範囲外アドレスを表せない構成など) は、
その covergroup を生成しないことで分母から外している。

## 構成の切り替え

DUT のパラメータは `axlm_params_pkg.sv` の `` `define `` で決まり、Makefile の `CFG` で切り替える。

| CFG | 内容 |
| --- | --- |
| a | 既定 (アドレス 32bit、データ 32bit、メモリ 16 ワード、未完了 4 / 4、エラーで中止) |
| b | データ 64bit、アドレス 16bit、メモリ 10 ワード、未完了 1 / 2、エラーでも最後まで続ける |
| c | アドレス 64bit、メモリ 24 ワード、未完了 8 / 3、エラーで中止 |

構成を足すときは Makefile に `CFG_x := +define+AXLM_...` を追加する。

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
make                                         # ビルド + axlm_smoke_test (CFG=a)
make run TEST=axlm_rand_test SEED=7 NUM=20   # テスト / シード / 本数を指定
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
+UVM_TESTNAME=<test>        テスト選択 (既定 axlm_smoke_test)
+verilator+seed+<n>         乱数シード
+CMD_NUM=<n>                axlm_rand_test の 1 ラウンドあたりのコマンド数 (既定 8。Makefile は NUM=12 を渡す)
+CMD_TIMEOUT=<n>            握手 / 完了待ちの上限サイクル (既定 200000)
+UVM_VERBOSITY=UVM_HIGH     monitor のトランザクションのログなどを表示
+UVM_MAX_QUIT_COUNT=<n>,NO  UVM_ERROR が n 件で打ち切る (Makefile は QUIT=200 を渡す)
```

所要時間とディスクの目安 (この環境、2 コア):

| 項目 | 目安 |
| --- | --- |
| ビルド (1 構成) | ccache 無しで約 1 分 50 秒 (1 分 47 秒)。同じソースのビルド結果を ccache が持っていれば約 20 秒 (19 秒) |
| `axlm_smoke_test` | 3〜4 秒 (3.1〜3.7 秒) |
| `axlm_rand_test` (`NUM=12`) | 約 10 秒 (8.9〜10.5 秒) |
| `axlm_rand_test` (`NUM=100`) | 75〜80 秒 |
| `make regress_all` (3 構成のビルド + 18 本 + カバレッジ集計) | ccache が効いた状態で 3 分 30 秒。ccache 無しでは、ビルドが 1 構成あたり約 1 分半長くなる |
| ビルドディレクトリ `obj_<CFG>` | 1 構成あたり約 0.95GB (g++ の最適化を切っているので大きい)。`make clean` で消える |

`axlm_rand_test` の実行時間の大半は、制約ソルバ z3 (別プロセス) の処理。シミュレータ自体の CPU 時間は、
`NUM=12` で約 2 秒、`NUM=100` で約 15 秒。

## 実行結果 (この環境)

3 構成 × (smoke 1 本 + rand 5 シード) の 18 本が全て PASS (UVM_ERROR / UVM_FATAL / UVM_WARNING とも 0)。
機能カバレッジは 3 構成とも 100% (bin の数は、構成 a が 182、b が 176、c が 184)。

```
$ make regress_all
[a] axlm_smoke_test seed=1 : PASS
[a] axlm_rand_test  seed=1 : PASS
[a] axlm_rand_test  seed=2 : PASS
[a] axlm_rand_test  seed=3 : PASS
[a] axlm_rand_test  seed=4 : PASS
[a] axlm_rand_test  seed=5 : PASS
[a]   covergroup : 100.0% (182/182)
[b] axlm_smoke_test seed=1 : PASS
[b] axlm_rand_test  seed=1 : PASS
[b] axlm_rand_test  seed=2 : PASS
[b] axlm_rand_test  seed=3 : PASS
[b] axlm_rand_test  seed=4 : PASS
[b] axlm_rand_test  seed=5 : PASS
[b]   covergroup : 100.0% (176/176)
[c] axlm_smoke_test seed=1 : PASS
[c] axlm_rand_test  seed=1 : PASS
[c] axlm_rand_test  seed=2 : PASS
[c] axlm_rand_test  seed=3 : PASS
[c] axlm_rand_test  seed=4 : PASS
[c] axlm_rand_test  seed=5 : PASS
[c]   covergroup : 100.0% (184/184)
```

1 本あたりの規模 (scoreboard と AXI の monitor の集計行から。「書き込み / 読み出し」の形):

```
構成  テスト                         コマンド   転送したもの  エラー応答あり  途中で止めた  サイクル数を照合  反対方向の実行中に受付
a     axlm_smoke_test                79 / 73    73 / 67       13 / 13         10 / 8        58 / 52           33
a     axlm_rand_test s=1             105 / 105  87 / 78       16 / 16         4 / 8         57 / 57           83
a     axlm_rand_test s=11 (NUM=100)  809 / 809  669 / 672     106 / 114       14 / 22       409 / 409         771
b     axlm_smoke_test                83 / 73    77 / 67       15 / 16         0 / 0         62 / 52           33
b     axlm_rand_test s=1             105 / 105  75 / 83       16 / 22         0 / 0         57 / 57           78
b     axlm_rand_test s=11 (NUM=100)  809 / 809  668 / 629     153 / 166       0 / 0         409 / 409         696
c     axlm_smoke_test                79 / 73    73 / 67       13 / 12         10 / 8        58 / 52           33
c     axlm_rand_test s=1             105 / 105  94 / 88       11 / 12         2 / 7         57 / 57           106
c     axlm_rand_test s=11 (NUM=100)  809 / 809  714 / 673     105 / 77        38 / 25       409 / 409         776

構成  テスト                         トランザクション  AW が先 / W が先 / 同時  最大の未完了数  読み書きとも未完了  ローカルアクセス
a     axlm_smoke_test                628 / 559         21 / 46 / 561            4 / 4           151                 348 / 156
a     axlm_rand_test s=1             206 / 173         30 / 52 / 124            4 / 4           88                  106 / 241
a     axlm_rand_test s=11 (NUM=100)  1395 / 1442       240 / 325 / 830          4 / 4           526                 836 / 983
b     axlm_smoke_test                445 / 363         9 / 12 / 424             1 / 2           25                  261 / 111
b     axlm_rand_test s=1             172 / 180         32 / 43 / 97             1 / 2           96                  76 / 145
b     axlm_rand_test s=11 (NUM=100)  1322 / 1105       320 / 270 / 732          1 / 2           534                 559 / 651
c     axlm_smoke_test                832 / 712         41 / 22 / 769            8 / 3           116                 522 / 258
c     axlm_rand_test s=1             249 / 260         35 / 28 / 186            5 / 2           69                  116 / 305
c     axlm_rand_test s=11 (NUM=100)  2041 / 1624       400 / 523 / 1118         6 / 3           700                 828 / 1019
```

- 「コマンド」は断るコマンドと 0 ワードのコマンドを含む数。「転送したもの」はそれ以外
- 「サイクル数を照合」は、理想的なスレーブで受付から `*_done` までのサイクル数を式と照合したコマンド (転送しないコマンドを含む)
- 「反対方向の実行中に受付」は、もう一方の方向のコマンドの実行中に受け付けたコマンドの数 (読み書きの合計)
- 「AW が先 / W が先 / 同時」は、スレーブが書き込みの AW と W を受け付けた順
- 構成 c の `axlm_rand_test` は、未完了数が上限 (8 / 3) まで届かないことがある。上限まで使う場面は
  `axlm_smoke_test` (応答の遅延を長くする項目) が作り、`cg_depth` で確認している

ログの末尾 (CFG=a、`axlm_rand_test`、シード 1):

```
UVM_INFO ../tb/axlm_coverage.svh(581) @ 16465000: uvm_test_top.env.cov [COV] cg_cmd = 100.0 %  cg_result = 95.7 %  cg_conc = 100.0 %  cg_wr_tr = 100.0 %  cg_rd_tr = 93.3 %  cg_local = 100.0 %
UVM_INFO ../tb/axlm_scoreboard.svh(490) @ 16465000: uvm_test_top.env.scb [SCB] write commands=105 (transferred 87, error responses 16, stopped early 4, cycle-exact 57) transactions=206
UVM_INFO ../tb/axlm_scoreboard.svh(491) @ 16465000: uvm_test_top.env.scb [SCB] read commands=105 (transferred 78, error responses 16, stopped early 8, cycle-exact 57) transactions=173
UVM_INFO ../tb/axlm_scoreboard.svh(492) @ 16465000: uvm_test_top.env.scb [SCB] commands started while the other direction was running=83 local writes=106 local reads=241 errors=0
UVM_INFO ../tb/axlm_test_lib.svh(40) @ 16465000: uvm_test_top [TEST] ** TEST PASSED **

--- UVM Report Summary ---

Quit count :     0 of   200
** Report counts by severity
UVM_INFO :   19
UVM_WARNING :    0
UVM_ERROR :    0
UVM_FATAL :    0
```

(`[COV]` の行はその 1 本だけの値。全体の値は `make cov` で全 run をマージして出す。)

コマンド数を増やした実行 (`NUM=100`、シード 11 / 12 / 13) も、3 構成とも PASS (カバレッジ 100%)。
`axlm_rand_test` 1 本が、読み書き 809 本ずつのコマンドになる。

```
$ make regress CFG=a NUM=100 SEEDS="11 12 13"      # CFG=b / CFG=c も同様
[a] axlm_smoke_test seed=1 : PASS
[a] axlm_rand_test  seed=11 : PASS
[a] axlm_rand_test  seed=12 : PASS
[a] axlm_rand_test  seed=13 : PASS
```

`make run WAVES=1` (`axlm_smoke_test`) も PASS し、`wave.fst` (約 92KB) が出る。

## 検証環境の検出力確認

RTL に 1 箇所ずつバグを入れ (29 種)、`axlm_smoke_test` と `axlm_rand_test` (シード 1、`+CMD_NUM=12`) を流した結果。
29 種すべてが、両方のテストで FAIL になった。バグを入れない状態では、同じ手順で両方とも PASS する。
バグは、簡易 TB で使った 60 種 (トップの `README.md`) から、UVM 環境の各チェック
(`axi_if` / `usr_if` の SVA、scoreboard、完了待ちタイムアウト) が働くように選んだ。

```
入れたバグ                                                                     構成  smoke  rand   エラーを出したチェック
書き込みの未完了数の上限を見ない                                               a     検出   検出   axi_if の SVA (未完了数、未完了と AWAKEUP、AxVALID と AWAKEUP)、SCB (止めるまでに出した数)
BREADY を常に 1 にしない                                                       a     検出   検出   axi_if の SVA (BREADY / RREADY、TB 側の保持)、SCB (所要サイクル数、止めるまでに出した数)
RRESP を捨てる (常に OKAY)                                                     a     検出   検出   SCB (スレーブのメモリ、err_flags、done_err)
RDATA を取り込まない                                                           a     検出   検出   SCB (スレーブのメモリ、書き込みトランザクションの内容、内部メモリ)
axi_wakeup が 1 サイクル遅れる                                                 a     検出   検出   axi_if の SVA (AxVALID と AWAKEUP)
読み出しで axi_wakeup を立てない                                               a     検出   検出   axi_if の SVA (AxVALID と AWAKEUP、未完了と AWAKEUP)
AWPROT を常に 0 にする                                                         a     検出   検出   SCB (書き込みトランザクションの内容)
WSTRB を常に全て 1 にする                                                      a     検出   検出   SCB (書き込みトランザクションの内容、スレーブのメモリ)
スライス : 出力が待たされている間の入力を捨てる                                a     検出   検出   完了待ちタイムアウト
スライス : READY を待たずに出力を上書きする                                    a     検出   検出   axi_if の SVA (VALID / ペイロードの保持)、完了待ちタイムアウト、SCB (読み出しトランザクションの内容)
done のサイクルに rd_busy を下げる                                             a     検出   検出   usr_if の SVA (done と busy、ローカルポートの ready、ready と busy)
書き込みコマンド中もローカル読み出しを受ける                                   a     検出   検出   usr_if の SVA (ローカルポートの ready)、SCB (実行中のローカルアクセス、内部メモリ)
ローカル書き込みを止める条件が逆 (書き込みコマンド中に止める)                  a     検出   検出   usr_if の SVA (ローカルポートの ready)、SCB (実行中のローカルアクセス、書き込みトランザクションの内容、内部メモリ)
送信 FIFO の空きを見ずに内部メモリを読む                                       a     検出   検出   SCB (書き込みトランザクションの内容)、完了待ちタイムアウト
書き込み : エラー応答で止めない (STOP_ON_ERROR が効かない)                     a     検出   検出   SCB (止めるまでに出した数)
読み出し : エラー応答で止めない (STOP_ON_ERROR が効かない)                     c     検出   検出   SCB (止めるまでに出した数)
書き込み : エラー応答のサイクルにはまだ要求を出す (止めるのが 1 サイクル遅い)  a     検出   検出   SCB (止めるまでに出した数)
読み出し : エラー応答のサイクルにはまだ要求を出す (止めるのが 1 サイクル遅い)  c     検出   検出   SCB (止めるまでに出した数)
err_index が最後のエラー (書き込み)                                            c     検出   検出   SCB (err_index)
EXOKAY をエラーとして扱わない (止めない / err_index)                           c     検出   検出   SCB (err_index、止めるまでに出した数)
エラー応答の読み出しデータも内部メモリに書く                                   b     検出   検出   SCB (スレーブのメモリ、書き込みトランザクションの内容、内部メモリ)
エラー応答のときに内部メモリの書き込み位置を進めない                           b     検出   検出   SCB (書き込みトランザクションの内容、スレーブのメモリ、内部メモリ)
アドレス空間の一番上にちょうど収まる書き込みを断る                             a     検出   検出   SCB (止めるまでに出した数、err_flags、done_err)
次のコマンドで SLVERR のフラグを消さない                                       b     検出   検出   SCB (err_flags、done_err、err_index)
範囲外のローカル読み出しで 0 を返さない                                        b     検出   検出   SCB (範囲外の読み出し)
待たされたローカル読み出しでも mem_r_rvalid を出す                             a     検出   検出   usr_if の SVA (mem_r_rvalid)
変換 : WLAST を 0 にする                                                       a     検出   検出   axi_if の SVA (WLAST)
変換 : AWCACHE を Bufferable / Modifiable にする                               a     検出   検出   axi_if の SVA (AXI4-Lite 相当の固定値)
変換 : AWAKEUP を出さない                                                      a     検出   検出   axi_if の SVA (未完了と AWAKEUP、AxVALID と AWAKEUP)
```

- 「エラーを出したチェック」は、2 本のログに出た UVM_ERROR / UVM_FATAL を件数の多い順に並べたもの (チェックごとに 3 項目まで)。
  SCB は scoreboard、「完了待ちタイムアウト」は driver が受付 (`*_ready`) や完了 (`*_done`) を `+CMD_TIMEOUT` サイクル
  (この確認では 20000) 待っても来なかったもの (UVM_FATAL)
- 構成 a 以外で流したものは、影響が出る構成を選んだ。b は `STOP_ON_ERROR=0` で、エラー応答の後も同じコマンドの
  トランザクションが続く。またメモリが 10 ワードなので、ローカルポートに範囲外のアドレスがある (a は 16 ワードで無い)。
  c は未完了数が 8 / 3 の `STOP_ON_ERROR=1` で、止める前に出していたトランザクションのエラー応答も受ける
- 「止めるのが 1 サイクル遅い」は、エラー応答を受けたサイクルにもう 1 つ要求を出してしまうバグ。
  出た数は `err_index+1 .. err_index+MAX` の範囲に収まるので、範囲の照合だけでは見つからない。
  scoreboard が、理想的なスレーブのときに「エラー応答を受けたサイクルで止まるときの正確な数」と照合しているので検出できる
- 確認の途中の版の `axlm_rand_test` は、5 種 (EXOKAY をエラーとして扱わない / エラー応答のときに内部メモリの書き込み位置を進めない /
  アドレス空間の一番上にちょうど収まる書き込みを断る / 止めるのが 1 サイクル遅い 2 種) を検出しなかった (`axlm_smoke_test` は検出)。
  そこでランダムテストを次のように強化し、上の結果は強化後の版で全て流し直したもの:
  - 1 つ目のエラー応答の範囲の種類を、ラウンドごとに SLVERR / DECERR / EXOKAY で回す
  - エラー応答のあるラウンドでは長いコマンドを多めにし、内部メモリを書き込み / 読み出しで半分ずつ使う
    (コマンドの途中でエラーになり、その後に OKAY が続く場面を増やす)
  - 理想的なスレーブでエラー応答のあるラウンド (3 / 7) を置き、止めるまでに出す数を正確に照合する
  - 最後に、アドレス空間の一番上でちょうど終わるコマンドを読み書き 4 本ずつ流す
- エラーの多いバグでは、`+UVM_MAX_QUIT_COUNT=200,NO` により 200 件で打ち切られる

## Verilator 5.052 で動かすための注意点

APB 版の環境と同じ注意点 (駆動は `@(vif.xx_cb)` の直後、`get_next_item()` の後に同期、VALID は clocking block で `inout`、
制約式に演算を書かない、enum の coverpoint は bins を明示、長さの違う文字列リテラルを `?:` で選ばない、
`-Wno-fatal` と `-Werror-USERERROR` の併用、ビルドディレクトリが約 0.9GB など) に加えて、この環境で守っていること:

1. **1 つの interface に、駆動する信号の違う clocking block を複数置く**
   書き込みコマンド / 読み出しコマンド / ローカルポートの driver が同じサイクルに独立して駆動できるように、
   `usr_if` に `wdrv_cb` / `rdrv_cb` / `ldrv_cb` を分けている (同じ信号を 2 つの clocking block から駆動しない)。

2. **同じサイクルに受け付けたいものは、同じ時刻に別の sequencer へ流す**
   `fork` で 2 つのシーケンスを同時に start すると、それぞれの driver が同じクロッキングイベントで駆動するので、
   DUT は同じエッジで受け付ける (書き込みと読み出しの同時受付、コマンドとローカルアクセスの同時受付に使っている)。

3. **monitor は、同じサイクルの出来事を決まった順に出す**
   ローカルの書き込み → コマンドの受付 / 完了の順。同じサイクルに受け付けた書き込みコマンドは書いた後の値を送るので、
   scoreboard が期待値を作るときに、その書き込みが反映済みである必要がある。

4. **covergroup の coverpoint に `iff` を書かない**
   条件付きでサンプルしたいものは、別の covergroup にして、条件を満たすときだけ `sample()` を呼んでいる。

## Xcelium で流す場合 (参考・この環境では未実行)

```
xrun -64bit -sv -uvm -uvmhome $UVM_HOME -timescale 1ns/1ps \
     -incdir ../tb \
     ../tb/axlm_params_pkg.sv ../tb/axi_if.sv ../tb/usr_if.sv ../tb/axlm_uvm_pkg.sv \
     -F ../../rtl/filelist.f ../tb/tb_top.sv \
     +define+AXIL_MASTER_SRAM_POISON \
     +UVM_TESTNAME=axlm_rand_test -svseed 1 +CMD_NUM=12
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
- AMBA AXI Protocol Specification (Arm IHI 0022 Issue L):
  https://documentation-service.arm.com/static/68b03beb01ae952d9559f9eb
- AMD AXI Protocol Checker (PG101)、AXI Protocol Checks and Descriptions:
  https://docs.amd.com/r/en-US/pg101-axi-protocol-checker/AXI-Protocol-Checks-and-Descriptions
- Arm CoreLink NI-700 TRM (2.2.2 Clock domain wakeup):
  https://documentation-service.arm.com/static/60acf9c4982fc7708ac1cde2

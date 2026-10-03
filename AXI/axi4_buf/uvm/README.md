# Verilator + UVM テストベンチ (axi4_master_linebuf)

`rtl/axi4_master_linebuf.sv` を Verilator と UVM で検証する環境。
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
 ├─ axi_rd_if              入力側 AXI (AR / R)。clocking block + SVA
 ├─ axi_wr_if              出力側 AXI (AW / W / B)。clocking block + SVA
 ├─ cmd_if                 コマンド / ステータス。clocking block + SVA
 ├─ axi4_master_linebuf    DUT
 └─ uvm_test_top           lb_smoke_test / lb_rand_test
     └─ env (lb_env)
         ├─ cmd_agt   sqr / drv (cmd_valid/ready で渡して done を待つ) / mon (ap_start, ap_done)
         ├─ rd_agt    rsp (AR を受けて R を返す) / mon
         ├─ wr_agt    rsp (AW / W を受けて B を返す) / mon
         ├─ scb       err_flags・バースト列・WSTRB・出力先メモリを照合
         ├─ cov       cg_cmd / cg_result / cg_tail / cg_word / cg_burst
         ├─ vsqr      cmd_sqr + 両側のメモリ / スレーブ設定
         ├─ src_mem / rd_cfg   入力側のメモリモデルとスレーブ設定
         └─ dst_mem / wr_cfg   出力側のメモリモデルとスレーブ設定
```

入力側と出力側でアドレス幅・データ幅が違うので、interface もスレーブ agent も別々にしている。
スレーブの振る舞い (ストール率 / READY が VALID を待つ / SLVERR 範囲) は `axi_slv_cfg` に持たせ、
仮想シーケンスがコマンドの合間に書き換える。

## ファイル

```
uvm/
  tb/
    lb_params_pkg.sv      ... DUT パラメータ (+define+LB_xxx=値 で上書き)
    axi_rd_if.sv          ... 入力側 AXI interface / clocking block / SVA
    axi_wr_if.sv          ... 出力側 AXI interface / clocking block / SVA
    cmd_if.sv             ... コマンド interface / clocking block / SVA
    lb_uvm_pkg.sv         ... UVM パッケージ (型・画像フォーマットの計算・各クラスの include)
    axi_burst_item.svh    ... monitor が出すバースト 1 本分
    axi_mem.svh           ... メモリモデル (axi_mem) とスレーブ設定 (axi_slv_cfg)
    axi_rd_slv_agent.svh  ... 入力側 responder / monitor / agent
    axi_wr_slv_agent.svh  ... 出力側 responder / monitor / agent
    cmd_agent.svh         ... cmd_item (制約) / driver / monitor / agent
    lb_scoreboard.svh     ... scoreboard
    lb_coverage.svh       ... covergroup
    lb_env.svh            ... 仮想 sequencer と env
    lb_seq_lib.svh        ... 仮想シーケンス (smoke / rand)
    lb_test_lib.svh       ... テスト
    tb_top.sv             ... トップ
  sim/
    Makefile
```

## テスト

| テスト | 内容 |
| --- | --- |
| `lb_smoke_test` | 幅 (1 / 中間 / 最大) × 高さ (1 / `NUM_LINES` 以内 / 超過) の 9 通り、4KB 跨ぎ、SLVERR (Read 側 / Write 側)、断るコマンド 3 種 (入力アドレス非アライン / 出力 stride 非アライン / 幅超過) と空コマンド 2 種 (幅 0 / 高さ 0)、その直後の通常フレーム、50% ストール + READY が VALID を待つ、出力が遅い (scratchpad 満杯) |
| `lb_rand_test` | ランダムフレームを、両側スレーブのストール率の組み合わせ 9 通りで各 `+CMD_NUM` 本。続けて SLVERR 注入 4 本、断るコマンド 3 本 + 空コマンド 2 本、最後に通常フレーム 1 本 |

## scoreboard のチェック内容

| タイミング | チェック |
| --- | --- |
| バーストごと | INCR / `AxSIZE` = バス幅 / `AxLEN+1 <= MAX_BURST` / 4KB 境界を跨がない / ID / `AxCACHE`・`AxPROT`・`AxQOS`・`AxREGION`・`AxLOCK` |
| 完了時 | `err_flags` / `done_err` == 期待値 (SLVERR 範囲に掛かるか、コマンドが誤りか) |
| 完了時 | Read・Write のバースト列が、ラインごとに `base + y × stride` から `min(残り, MAX_BURST, 4KB まで)` で分割した列と一致 |
| 完了時 | WSTRB がライン最終ビートだけ端数で、他は全有効 |
| 完了時 | 出力先メモリ == 期待値。ライン外 (ガード領域と stride の隙間) は元のパターンのまま |
| 完了時 | ライン完了パルスの回数 == ライン数 (断ったコマンドでは 0、バーストも 0 本) |

期待値はコマンド受付時に入力側メモリから作る。SLVERR を返すビートはスレーブがメモリに書かないので、
その部分は「元のパターンのまま」を期待値にしている (エラー注入時もメモリを照合できる)。

SVA (interface 内):

| interface | 内容 |
| --- | --- |
| `axi_rd_if` | ARVALID 保持・ペイロード安定、4KB、`ARLEN`、バースト中に `RREADY` を下げない、R の保持 (TB 側) |
| `axi_wr_if` | AWVALID / WVALID 保持・ペイロード安定、4KB、`AWLEN`、AW 握手後に `WVALID` を途切れさせない、B の保持 (TB 側) |
| `cmd_if` | busy 中は `cmd_ready=0`、`done` は 1 サイクル、`done_err == |err_flags`、`sp_level <= NUM_LINES`、コマンドの保持 (TB 側) |

`tb_top` では、scratchpad の動作モデルが数えている異常 (同一ラインへの同時アクセス、
未書き込みワードの読み出し) も UVM のエラーにしている。

## 機能カバレッジ

| covergroup | 内容 |
| --- | --- |
| `cg_cmd` | 幅 (1 / 中間 / 最大) × 高さ (1 / `NUM_LINES` 以内 / 超過) の cross、入力 stride (0 / 最小 / 隙間あり)、出力 stride、入力・出力の 4KB 跨ぎ、両側ストール率 (無し / 1〜49% / 50%〜) の cross、READY が VALID を待つ、scratchpad が満杯まで溜まったか |
| `cg_result` | 正常 / Read エラー / Write エラー / コマンド誤り / 空コマンド |
| `cg_tail` | ライン末尾の端数 (入力ビート / 出力ビート) |
| `cg_word` | SRAM ワードの端数 (幅が `PIX_PER_WORD` の倍数か) |
| `cg_burst` | 方向 × バースト長 (1 / 中間 / 最大) の cross、4KB 境界ちょうどで終わるバースト |

構成によって起こり得ない項目 (`PIX_PER_WORD=1` での「ワードの端数」など) は、その covergroup を
生成しないことで分母から外している。

## 構成の切り替え

DUT のパラメータは `lb_params_pkg.sv` の `` `define `` で決まり、Makefile の `CFG` で切り替える。

| CFG | 内容 |
| --- | --- |
| a | 既定 (64bit → 64bit、8bit 画素、2 画素/ワード、4 ライン) |
| b | 32bit → 128bit、アドレス 40bit / 24bit、10bit 画素を 16bit コンテナの上位詰め、2 ライン、バースト 8 / 4、ID 幅 1 / 8 |
| c | 128bit → 32bit、12bit 画素を隙間なく詰める、4 画素/ワード、3 ライン、Read バースト 8 |

構成を足すときは Makefile に `CFG_x := +define+LB_...` を追加する。
カバレッジを 100% にできるのは、最大幅 3 画素以上、2 ライン以上、最大バースト長 3 以上、
データ幅 16bit 以上の構成。

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
make                                       # ビルド + lb_smoke_test (CFG=a)
make run TEST=lb_rand_test SEED=7 NUM=10   # テスト / シード / 本数を指定
make regress                               # smoke + rand (SEEDS="1 2 3 4 5")
make regress CFG=b                         # 別の構成
make regress_all                           # 全構成で regress + カバレッジ表示
make cov CFG=a                             # その構成の全 run のカバレッジをマージして表示
make run WAVES=1                           # wave.fst を出力 (別ディレクトリに別ビルド)
make clean
```

`UVM_HOME` の既定は `$HOME/tools/uvm-verilator`。別の場所なら `make UVM_HOME=...` で指定する。

実行時の主な plusarg:

```
+UVM_TESTNAME=<test>      テスト選択 (既定 lb_smoke_test)
+verilator+seed+<n>       乱数シード
+CMD_NUM=<n>              lb_rand_test の各フェーズのフレーム数 (既定 6)
+CMD_TIMEOUT=<n>          コマンド受付 / 完了待ちの上限サイクル (既定 400000)
+UVM_VERBOSITY=UVM_HIGH   monitor のバーストログなどを表示
+UVM_MAX_QUIT_COUNT=<n>,NO  UVM_ERROR が n 件で打ち切る (Makefile は QUIT=200 を渡す)
```

所要時間の目安 (この環境、2 コア):

| 項目 | 時間 |
| --- | --- |
| ビルド (1 構成) | 約 1 分 50 秒。ccache が効く 2 回目以降は約 65 秒 |
| `lb_smoke_test` | 2〜3 秒 |
| `lb_rand_test` (`NUM=6`) | 10〜15 秒 |
| `make regress_all` (3 構成のビルド + 18 本 + カバレッジ集計) | 6〜7 分 (ccache あり。2 回測って 6 分 23 秒と 6 分 58 秒) |

## 実行結果 (この環境)

3 構成 × (smoke 1 本 + rand 5 シード) の 18 本が全て PASS (UVM_ERROR / UVM_FATAL / UVM_WARNING とも 0)。
機能カバレッジは 3 構成とも 100% (67 bin 中 67)。

```
$ make regress_all
[a] lb_smoke_test seed=1 : PASS
[a] lb_rand_test  seed=1 : PASS
[a] lb_rand_test  seed=2 : PASS
[a] lb_rand_test  seed=3 : PASS
[a] lb_rand_test  seed=4 : PASS
[a] lb_rand_test  seed=5 : PASS
[a]   covergroup : 100.0% (67/67)
[b] lb_smoke_test seed=1 : PASS
[b] lb_rand_test  seed=1 : PASS
[b] lb_rand_test  seed=2 : PASS
[b] lb_rand_test  seed=3 : PASS
[b] lb_rand_test  seed=4 : PASS
[b] lb_rand_test  seed=5 : PASS
[b]   covergroup : 100.0% (67/67)
[c] lb_smoke_test seed=1 : PASS
[c] lb_rand_test  seed=1 : PASS
[c] lb_rand_test  seed=2 : PASS
[c] lb_rand_test  seed=3 : PASS
[c] lb_rand_test  seed=4 : PASS
[c] lb_rand_test  seed=5 : PASS
[c]   covergroup : 100.0% (67/67)
```

1 本あたりの規模 (scoreboard の集計行から):

```
構成  テスト            コマンド  転送したもの  エラーフラグ付き  画素数   Read バースト  Write バースト
a     lb_smoke_test     20        15            5                 12959    170            155
a     lb_rand_test s=1  64        59            7                 31194    490            472
b     lb_smoke_test     20        15            5                 3229     229            125
b     lb_rand_test s=1  64        59            7                 12750    955            548
c     lb_smoke_test     20        15            5                 6790     113            188
c     lb_rand_test s=1  64        59            7                 22986    420            719
```

- 「転送したもの」に入らない 5 本は、断るコマンド 3 本と空コマンド 2 本
- 「エラーフラグ付き」は、断るコマンド 3 本 + SLVERR を仕込んだフレーム (smoke 2 本 / rand 4 本)

ログの末尾 (CFG=a、`lb_rand_test`、シード 1):

```
UVM_INFO ../tb/lb_coverage.svh(282) @ 228735000: uvm_test_top.env.cov [COV] cg_cmd = 97.7 %  cg_result = 100.0 %  cg_burst = 100.0 %
UVM_INFO ../tb/lb_scoreboard.svh(365) @ 228735000: uvm_test_top.env.scb [SCB] commands=64 (transferred 59, with error flags 7) pixels=31194 bytes=31194 read_bursts=490 write_bursts=472 errors=0
UVM_INFO ../tb/lb_test_lib.svh(42) @ 228735000: uvm_test_top [TEST] ** TEST PASSED **

--- UVM Report Summary ---

Quit count :     0 of   200
** Report counts by severity
UVM_INFO :   82
UVM_WARNING :    0
UVM_ERROR :    0
UVM_FATAL :    0
```

(`[COV]` の行はその 1 本だけの値。100% は `make cov` で全 run をマージした値。)

## 検証環境の検出力確認

RTL に 1 箇所ずつバグを入れ (11 種)、`lb_smoke_test` と `lb_rand_test` (シード 1) を流した結果。
11 種すべてが、両方のテストで FAIL になった。

```
入れたバグ                                  構成  smoke  rand   エラーを出したチェック
最終ビートの WSTRB を全有効にする            a     検出   検出   SCB (WSTRB、出力先メモリ)
入力側 gearbox をライン末尾で clear しない   a     検出   検出   SP_CHK、cmd_if の SVA (sp_level)、SCB、完了待ちタイムアウト
空きラインの確認なしに AR を出す             a     検出   検出   cmd_if の SVA (sp_level <= NUM_LINES)、SP_CHK
Read を 4KB 境界で分割しない                 a     検出   検出   axi_rd_if の SVA (4KB)、SCB (バースト列)
WVALID を WREADY が来てから出す              a     検出   検出   axi_wr_if の SVA (バースト中の WVALID)、完了待ちタイムアウト
SRAM を 1 ワード多く読む                     a     検出   検出   SP_CHK (未書き込みワードの読み出し)
BRESP を無視する                             a     検出   検出   SCB (err_flags / done_err)
出力 stride に入力 stride を使う             a     検出   検出   SCB (バースト列、出力先メモリ)
FIFO の空きを確認せずに AR を出す            a     検出   検出   axi_rd_if の SVA (バースト中の RREADY)
ライン幅を超えた画素位置を 0 にしない        c     検出   検出   SCB (出力先メモリ)
出力で画素の上位詰めを行わない               b     検出   検出   SCB (出力先メモリ)
```

- SP_CHK は `tb_top` が拾っている scratchpad 動作モデルのチェック
- 下の 2 つは、構成 a では影響が出ないバグ (a は 8bit 画素でバイト境界に揃い、上位詰めも無い) なので、
  影響が出る構成で流した
- 「WVALID を WREADY が来てから出す」は、SVA が毎サイクル報告するため 1 本で約 5 万件のエラーになった。
  これを受けて Makefile に `+UVM_MAX_QUIT_COUNT=200,NO` を入れた。入れた後は 200 件で打ち切られ
  (`Quit count :   200 of   200`)、`make run` はエラーで終わる

## Verilator 5.052 で動かすための注意点

前回までに踏んだものを含め、この環境で守っていること。

1. **駆動は `@(vif.xx_cb)` の直後に行う**
   `get_next_item()` はデルタサイクルを消費するので、その後に `@(vif.drv_cb)` で同期してから駆動する。
   VALID / READY は clocking block で `inout` にし、握手は両方のサンプル値で判定する。

2. **`dist` と `randomize() with` の値固定を併用しない** (`UNSATCONSTR` になる)

3. **`randomize() with` と rand 動的配列の `size()` 制約を併用しない**

4. **`with {}` 内のローカル変数名を、item のメンバ名や制約ブロック名と重ねない**

5. **`// Verilator ...` で始まるコメントを書かない** (メタコメント扱いで `BADVLTPRAGMA`)

6. **実行時に z3 が必要** (`VERILATOR_SOLVER` で変更可)。FST 波形には lz4 の開発ヘッダも必要

7. **UVM 基底クラスのメソッド名 (`copy` / `compare` / `print` / `clone` など) と同じ名前のメソッドを作らない**

8. **制約式に乗算や加算を書かない**
   制約式も通常の式と同じビット幅規則で評価されるので、桁あふれした解をソルバが選べてしまう
   (Verilator 固有ではない)。`cmd_item` はランダム化する項目を単純な範囲制約だけにし、
   ライン長に合わせた stride や 4KB 境界に寄せたアドレスは `post_randomize()` で計算している。

9. **enum の coverpoint は bins を明示する**
   基底型が `int` の enum を auto bins に任せると、Verilator 5.052 では値ごとの bin ではなく
   64 個の範囲 bin になった (3 値の enum を全て踏んでも 1/64)。LRM では enum は値ごとに 1 bin。

10. **driver は done を見てから 1 サイクル待って `item_done()` する**
    driver と monitor は同じクロックエッジで done を見る。先にシーケンスへ戻すと、次のフレームの準備
    (メモリの書き換え) が scoreboard の照合より先に走り得る。

11. **エラボレーション時の `$error` は `-Wno-fatal` で警告に下がる**
    UVM ライブラリのために `-Wno-fatal` を付けているので、`-Werror-USERERROR` を併用して
    パラメータチェックがエラーで止まるようにしている。

## Xcelium で流す場合 (参考・この環境では未実行)

```
xrun -64bit -sv -uvm -uvmhome $UVM_HOME -timescale 1ns/1ps \
     -incdir ../tb \
     ../tb/lb_params_pkg.sv ../tb/axi_rd_if.sv ../tb/axi_wr_if.sv ../tb/cmd_if.sv ../tb/lb_uvm_pkg.sv \
     -F ../../rtl/filelist.f ../tb/tb_top.sv \
     +UVM_TESTNAME=lb_rand_test -svseed 1 +CMD_NUM=6
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
- AMBA AXI Protocol Specification (Arm IHI 0022):
  https://developer.arm.com/documentation/ihi0022/latest/

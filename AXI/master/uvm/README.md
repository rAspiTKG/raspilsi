# Verilator + UVM テストベンチ (axi4_full_master_copy)

`rtl/axi4_full_master_copy.sv` (AXI4-Full マスタのコピーエンジン) を、Verilator と UVM で
検証する環境。制約付きランダム / 機能カバレッジ / clocking block / 仮想シーケンス / SVA を
盛り込んでいる。

DUT がマスタになったので、前回 (スレーブ DUT 用) の環境とは役割が逆になっている。

| | 前回 (`axi4_full_slave_mem`) | 今回 (`axi4_full_master_copy`) |
| --- | --- | --- |
| TB 側の AXI | マスタ (driver が AW / W / AR を出す) | スレーブ (responder が READY / B / R を返す) |
| 刺激の入れ方 | AXI トランザクションを sequence で生成 | コピーコマンドを sequence で生成し、AXI はスレーブとして応答 |
| AXI 側で変化させるもの | バースト種別・長さ・WSTRB | ストール率・READY の出し方・SLVERR 注入 (`axi_slv_cfg`) |
| SVA の対象 | スレーブ (DUT) の義務 | マスタ (DUT) の義務 |

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
 ├─ axi_if                 clocking block (wr_cb / rd_cb / mon_cb) + SVA (マスタの義務)
 ├─ cmd_if                 clocking block (drv_cb / mon_cb)
 ├─ axi4_full_master_copy  DUT
 └─ uvm_test_top           copy_smoke_test / copy_rand_test
     └─ env (copy_env)
         ├─ cmd_agt   sqr / drv (cmd_valid/ready で渡して done を待つ) / mon (ap_start, ap_done)
         ├─ axi_agt   rsp (AXI スレーブ応答。Write と Read を並行) / wr_mon / rd_mon
         ├─ scb       バースト分割・データ・done_err・メモリ内容を照合
         ├─ cov       cg_cmd / cg_burst
         ├─ vsqr      cmd_sqr + 共有メモリ (mem) + スレーブ設定 (cfg)
         ├─ mem       axi_mem     : バイト単位のメモリモデル (rsp / scb / vsqr で共有)
         └─ cfg       axi_slv_cfg : ストール率 / ready_wait_valid / SLVERR 範囲
```

```
 cmd_agt.mon.ap_start --+--> scb / cov   (受付時: src の内容と期待エラーをスナップショット)
 cmd_agt.mon.ap_done  --+--> scb / cov   (完了時: 照合)
 axi_agt.wr_mon.ap    --+--> scb / cov   (Write バースト 1 本ごと)
 axi_agt.rd_mon.ap    --+--> scb / cov   (Read バースト 1 本ごと)
```

AXI スレーブ側は sequence で 1 応答ずつ作る方式 (reactive sequence) にはせず、
共有オブジェクト `cfg` の設定に従って responder が自律的に応答する形にしている。
仮想シーケンスがコマンドの合間に `cfg` を書き換えて、スレーブの振る舞いを切り替える。

## ファイル

```
uvm/
  tb/
    axi_params_pkg.sv   ... 幅・DUT パラメータ・テストで使うアドレス窓 (DUT と合わせる)
    axi_if.sv           ... AXI interface / clocking block / SVA
    cmd_if.sv           ... コマンド interface / clocking block
    copy_uvm_pkg.sv     ... UVM パッケージ (型・アドレス計算関数・各クラスの include)
    axi_burst_item.svh  ... monitor が出すバースト 1 本分 (AW+W+B / AR+R)
    axi_mem.svh         ... 共有メモリモデル (axi_mem) とスレーブ設定 (axi_slv_cfg)
    axi_slv_agent.svh   ... AXI スレーブ responder / Write monitor / Read monitor / agent
    cmd_agent.svh       ... cmd_item (制約) / driver / monitor / agent
    copy_scoreboard.svh ... scoreboard
    copy_coverage.svh   ... covergroup
    copy_env.svh        ... 仮想 sequencer と env
    copy_seq_lib.svh    ... 仮想シーケンス (smoke / rand)
    copy_test_lib.svh   ... テスト
    tb_top.sv           ... トップ
  sim/
    Makefile
```

## 盛り込んだ UVM 機能

| 機能 | 場所 | 内容 |
| --- | --- | --- |
| 制約付きランダム | `cmd_agent.svh` | `dist` / `inside` / 含意 `->` / アライン / 64bit に広げた窓の終端制約 / 4KB 跨ぎを出しやすくする制約 |
| 機能カバレッジ | `copy_coverage.svh` | coverpoint / bins / cross、`verilator_coverage` でマージ |
| clocking block | `axi_if.sv`, `cmd_if.sv` | `input #1step` / `output #1`、VALID と READY の両方をサンプルして握手判定 |
| 仮想シーケンス | `copy_env.svh`, `copy_seq_lib.svh` | コマンド sequencer とスレーブ設定 (`cfg`) を 1 本のシナリオで制御 |
| SVA | `axi_if.sv` | VALID 保持・ペイロード安定・4KB 境界・`MAX_BURST`。失敗は `uvm_report_error` で数える |
| 複数 analysis imp | `copy_scoreboard.svh` | `` `uvm_analysis_imp_decl `` で受付 / 完了 / Write / Read を 1 コンポーネントで受ける |
| ウォッチドッグ | `cmd_agent.svh` | 受付・完了待ちが `+CMD_TIMEOUT` サイクルを超えたら `uvm_fatal` |

### scoreboard のチェック内容

| タイミング | チェック |
| --- | --- |
| バーストごと | INCR / `AxSIZE` = バス幅 / `AxLEN+1 <= MAX_BURST` / 4KB 境界を跨がない / ID / WSTRB 全有効 |
| 完了時 | Read・Write それぞれ、src / dst から連続したアドレスで合計 len ビート |
| 完了時 | 分割が `min(残り, MAX_BURST, 4KB まで)` の貪欲分割と一致 |
| 完了時 | R で受けたデータ列 == W で出したデータ列 |
| 完了時 | (エラー注入なしのとき) dst の内容 == 受付時の src の内容 |
| 完了時 | `done_err` == 期待値 (SLVERR 範囲が src か dst に掛かるか) |

### 機能カバレッジ

| covergroup | coverpoint / cross |
| --- | --- |
| `cg_cmd` (コマンドごと) | 長さ (1 / 2〜15 / 16 / 17〜64 / 65〜300) × src の 4KB 跨ぎ × dst の 4KB 跨ぎ (cross) / ストール率 (0 / 1〜49 / 50〜) / `ready_wait_valid` / エラー応答 |
| `cg_burst` (バーストごと) | 方向 × バースト長 (1 / 2〜7 / 8〜15 / 16) の cross / 4KB 境界ちょうどで終わるバースト |

## テスト

| テスト | 内容 |
| --- | --- |
| `copy_smoke_test` | phase1: 1 バースト / src・dst とも 4KB 跨ぎ (分割位置が違う) / 300 ビート / 1 ビート。phase2: dst の 8 ビート目に SLVERR。phase3: 50% ストール + READY が VALID を待つスレーブ |
| `copy_rand_test` | ランダムコマンドを、スレーブを (ストール無し → 50% ストール → 30% ストール + READY が VALID を待つ) と変えながら各 `+CMD_NUM` 本。最後に SLVERR 注入 4 本 |

`ready_wait_valid` (READY を VALID を見てから上げる) はスレーブとして合法な実装で、
「VALID を READY 待ちで出す」マスタ (AXI 違反) はこのモードでデッドロックする。
READY を先に出すスレーブとしか繋がないと、この違反はシミュレーションで露見しない。

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

UVM は Accellera のサイトから 1800.2-2020.3.2 の tarball を取得してもよい。
その場合は `UVM_HOME` を展開先に向ける。

## 実行

```
cd uvm/sim
make                                        # ビルド + copy_smoke_test
make run TEST=copy_rand_test SEED=7 NUM=50  # テスト / シード / 本数を指定
make regress                                # smoke + rand (SEEDS="1 2 3 4 5")
make regress SEEDS="1 2 3 4 5 6 7 8" NUM=20
make cov                                    # 全 run のカバレッジをマージして表示
make run WAVES=1                            # wave.fst を出力 (obj_dir_waves に別ビルド)
make clean
```

`UVM_HOME` の既定は `$HOME/tools/uvm-verilator`。別の場所なら `make UVM_HOME=...` で指定する。

実行時の主な plusarg:

```
+UVM_TESTNAME=<test>      テスト選択 (既定 copy_smoke_test)
+verilator+seed+<n>       乱数シード
+CMD_NUM=<n>              copy_rand_test の各フェーズのコマンド本数 (既定 10)
+CMD_TIMEOUT=<n>          コマンド受付 / 完了待ちの上限サイクル (既定 20000)
+UVM_VERBOSITY=UVM_HIGH   monitor のバーストログなどを表示
```

2 コア / 7GB の環境で、ビルドは約 2 分 (大半が UVM 生成 C++ の g++ コンパイル)、
実行は smoke が約 0.3 秒、rand が `NUM=20` で約 4.6 秒、`NUM=50` で約 12 秒。

## 実行結果 (この環境)

```
$ make regress SEEDS="1 2 3 4 5 6 7 8" NUM=20
copy_smoke_test seed=1 : PASS
copy_rand_test  seed=1 : PASS
copy_rand_test  seed=2 : PASS
copy_rand_test  seed=3 : PASS
copy_rand_test  seed=4 : PASS
copy_rand_test  seed=5 : PASS
copy_rand_test  seed=6 : PASS
copy_rand_test  seed=7 : PASS
copy_rand_test  seed=8 : PASS

$ make cov
  covergroup : 100.0% (36/36)          (smoke 単体では 88.9% (32/36))

$ make run TEST=copy_smoke_test
[VSEQ] copy src=00001000 dst=00100000 len=16 [stall=0% ready_wait_valid=0 err=off] -> done_err=0
[VSEQ] copy src=00002f80 dst=00104fc8 len=100 [stall=0% ready_wait_valid=0 err=off] -> done_err=0
[VSEQ] copy src=00010000 dst=00110000 len=300 [stall=0% ready_wait_valid=0 err=off] -> done_err=0
[VSEQ] copy src=00020000 dst=00120008 len=1 [stall=0% ready_wait_valid=0 err=off] -> done_err=0
[VSEQ] copy src=00030000 dst=00130000 len=32 [stall=0% ready_wait_valid=0 err=[00130040:00130047]] -> done_err=1
[VSEQ] copy src=00040fc0 dst=00140f80 len=64 [stall=50% ready_wait_valid=1 err=off] -> done_err=0
[SCB] commands=6 (error-injected 1) beats=513 read_bursts=35 write_bursts=34 errors=0
[TEST] ** TEST PASSED **

$ make run TEST=copy_rand_test SEED=7 NUM=50
[VSEQ] phase1 : 50 random copies, no stall
[VSEQ] phase2 : 50 random copies, 50% stall
[VSEQ] phase3 : 50 random copies, 30% stall + READY waits for VALID
[VSEQ] phase4 : SLVERR injection
[SCB] commands=154 (error-injected 4) beats=10650 read_bursts=780 write_bursts=765 errors=0
[TEST] ** TEST PASSED **
```

smoke のバースト本数 (Read 35 / Write 34) は、各コマンドの分割
`min(残り, 16, 4KB まで)` を手計算した値と一致している。
`make run WAVES=1` (FST 波形付きビルド) でも PASS と `wave.fst` の出力を確認した。

## 検証環境の検出力確認

DUT (書き込みエンジン) のコピーにバグを 1 箇所ずつ入れ、`copy_smoke_test` と
`copy_rand_test` (seed=1, `+CMD_NUM=20`) を流した結果。全て FAIL (= 検出) になった。

| 入れたバグ | smoke | rand | 検出したもの |
| --- | --- | --- | --- |
| なし | PASS | PASS | |
| 4KB 境界でバーストを分割しない | FAIL (3 件) | FAIL (85 件) | SVA `AW INCR burst crosses 4KB boundary`、scoreboard の 4KB 跨ぎ・分割長の不一致 |
| BRESP を無視 (SLVERR を `done_err` に反映しない) | FAIL (1 件) | FAIL (2 件) | scoreboard の `done_err` 不一致 (rand は SLVERR 注入 4 本のうち dst 側の 2 本) |
| 各バースト 4 ビート目の WDATA bit0 を反転 | FAIL (19 件) | FAIL (238 件) | scoreboard の R / W データ列不一致・dst の内容不一致 |
| WVALID を WREADY が来てから出す (A3.2.1 違反) | FAIL (fatal) | FAIL (fatal) | READY が VALID を待つフェーズでデッドロック → `CMD_TIMEOUT` |

最後の 1 件は、ウォッチドッグ (`+CMD_TIMEOUT`) を入れる前はテスト全体のタイムアウト
(10ms) まで待って `PH_TIMEOUT` で止まり、1 本あたり約 3 分かかっていた。
ウォッチドッグ追加後はシミュレーション時間 約 200us で止まる。

## Verilator 5.052 で動かすための注意点

作成中に実際に踏んだもの。1〜6 は前回 (スレーブ DUT 用の環境) と共通。

1. **駆動は `@(vif.xx_cb)` の直後に行う**
   `get_next_item()` は内部でデルタサイクルを消費するため、その後にそのまま clocking block
   経由で駆動すると、駆動が次のクロッキングイベントまで 1 サイクル遅れた。
   driver は `get_next_item()` の後に `@(vif.drv_cb)` で同期してから駆動している。
   responder も同様に、READY / B / R の駆動は必ず `@(vif.wr_cb)` / `@(vif.rd_cb)` の直後に置き、
   VALID / READY は clocking block で `inout` にして両方のサンプル値で握手を判定している。

2. **`dist` と `randomize() with` の値固定が衝突すると UNSAT になる**
   `dist` が選んだ区分をハード制約として扱うため、別区分へ固定すると `UNSATCONSTR` になる。
   値を固定するときは `constraint_mode(0)` で `dist` の制約ブロックを外す。

3. **`randomize() with` を使うと rand 動的配列の `size()` 制約が反映されない**

4. **`with {}` 内の名前は item 側のスコープが優先される** (IEEE 1800 18.7)
   ローカル変数名が item のメンバ名や制約ブロック名と重なると `Internal Error` になる。

5. **`// Verilator ...` で始まるコメントはメタコメント扱い** (`BADVLTPRAGMA`)

6. **実行時に z3 が必要** (`VERILATOR_SOLVER` で変更可)。FST 波形には lz4 の開発ヘッダも必要。

7. **UVM 基底クラスのメソッド名と同じ名前のメソッドを作らない (今回の新規)**
   仮想シーケンスに `task copy(...)` を作ったところ、`uvm_object::copy()` (非 virtual の function)
   と同名になり、Verilator 5.052 は原因箇所ではなく UVM 内部を指して以下を出した。

   ```
   %Error-UNSUPPORTED: $UVM_HOME/src/base/uvm_globals.svh:119:27: Unsupported: Timing controls inside DPI-exported tasks
   %Error-UNSUPPORTED: $UVM_HOME/src/uvm_pkg.sv:72:6: Unsupported: Timing controls inside DPI-exported tasks
   %Error: Internal Error: axi_burst_item.svh:22:24: ../V3Ast.h:1113: AstNode is not of expected type, but instead has type 'ASSIGN'
   ```

   メソッドを 1 つずつ削って原因を絞り込み、名前を `copy_cmd` に変えて解消した。
   `copy` / `compare` / `print` / `clone` / `create` / `pack` / `record` などは避けるのが無難。

8. **制約式の桁あふれ (Verilator 固有ではない)**
   `(src + (len << 3)) <= SRC_HI + 1` のように 32bit のまま書くと、加算があふれて
   小さな値になる解 (例: `src=FFFFFFB0`) をソルバが選べる。制約式も通常の式と同じ
   ビット幅規則で評価されるためで、LRM どおりの動作。ランダム回帰で src / dst の窓が
   重なり scoreboard が不一致を出したことで見つかった。上限を `inside` で明示し、
   終端の計算は `64'(src) + (64'(len) << ADDR_LSB)` と 64bit に広げている。

## Xcelium で流す場合 (参考・この環境では未実行)

```
xrun -64bit -sv -uvm -uvmhome $UVM_HOME -timescale 1ns/1ps \
     -incdir ../tb \
     ../tb/axi_params_pkg.sv ../tb/axi_if.sv ../tb/cmd_if.sv ../tb/copy_uvm_pkg.sv \
     ../../rtl/axi4_sync_fifo.sv ../../rtl/axi4_mst_wr_engine.sv ../../rtl/axi4_mst_rd_engine.sv \
     ../../rtl/axi4_full_master_copy.sv ../tb/tb_top.sv \
     +UVM_TESTNAME=copy_rand_test -svseed 1 +CMD_NUM=20
```

## 参考

- Verilator Revision History (5.052: "Verilator now supports UVM 2020-3.2"):
  https://verilator.org/guide/latest/changes.html
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
  (節番号の対応はトップの README.md を参照)

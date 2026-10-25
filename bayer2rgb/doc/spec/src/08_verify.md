## 13. 検証

### 13.1 方針

- UVM(IEEE 1800.2-2017-1.0)の環境で、ランダムな設定・画像・メモリの応答タイミングを与え、出力をリファレンスモデルとビット単位で比べます。
- 同じ環境を Verilator と Xcelium で動かせるようにしています(`sim/Makefile`)。
- リファレンスモデルは SystemVerilog(`tb/uvm/b2r_ref_model.svh`、スコアボードで使用)と Python(`tools/b2r_model.py`)の2つで、互いに照合します。
- AXI のプロトコルと本IPの約束(16バイト・INCR・4KB 境界・同時発行数など)はインタフェースの検査で毎クロック確かめます。
- リセットしない FF と SRAM の初期値は乱数にして(Verilator の `--x-assign unique --x-initial unique` と `+verilator+rand+reset+2`)、初期値に依存しないことを確かめます。

### 13.2 検証環境の構成

| 部品 | ファイル | 内容 |
|---|---|---|
| tb_top | `tb/tb_top.sv` | クロック(`+CLK_PS`、`+CTRL_CLK_PS` で周期を変更)、リセット、DUT、インタフェース、波形の出力(`+WAVES`) |
| AXI4-Lite インタフェース | `tb/b2r_axil_if.sv` | BVALID/RVALID と応答の保持、要求していない応答がないことを検査 |
| AXI4 インタフェース | `tb/b2r_axi4_if.sv` | VALID と値の保持、ID=0、SIZE=16バイト、INCR、LEN≦15、16バイト境界、4KB 境界、LOCK=0、同時発行≦4、VALID/READY の不定値を検査 |
| b2r_axil_agent | `tb/uvm/b2r_axil_agent.svh` | AXI4-Lite マスタ。AW と W を別々の乱数の遅れで出す。BREADY/RREADY を乱数で遅らせる |
| b2r_axi_slave | `tb/uvm/b2r_axi_slave.svh` | AXI4 スレーブ(メモリ)。READY の割合、応答の遅れ、ビートの間隔、エラー応答の割合を設定できる。W が AW より先に来る場合も受ける。WLAST の位置と W/AW の対応を検査 |
| b2r_mem | `tb/uvm/b2r_mem.svh` | 4KB ページ単位の疎なメモリ |
| b2r_image | `tb/uvm/b2r_image.svh` | 合成画像 7種類(一様乱数、グラデーション、色付きの矩形、縞・市松、0/最大値の混在、暗部、明部)。上位2bitに乱数を入れる |
| b2r_frame_cfg | `tb/uvm/b2r_frame_cfg.svh` | 1フレームの設定と乱数化 |
| b2r_ref_model | `tb/uvm/b2r_ref_model.svh` | SystemVerilog のリファレンスモデル(6章の式) |
| b2r_scoreboard | `tb/uvm/b2r_scoreboard.svh` | AR/AW の並び(アドレス・長さ・属性)を設定から予測して比較。W はバイトごとに、出力領域の内側か、2回書いていないか、リファレンスモデルと一致するかを検査。`+B2R_DUMP` でフレームの入出力をファイルに出す |
| b2r_coverage | `tb/uvm/b2r_coverage.svh` | 機能カバレッジ(フレームの設定、バースト、制御のイベント) |
| b2r_base_test / b2r_tests | `tb/uvm/b2r_base_test.svh`、`b2r_tests.svh` | テストの共通部分(レジスタアクセス、フレームの設定・開始・完了待ち)とテスト |

RTL の中にもシミュレーション専用の検査があります(`ifndef SYNTHESIS`): CDC の使い方の誤り、IN_CTRL の動作中の開始、SRAM モデルの同じアドレスの同時読み書きと範囲外アドレス。どれも `$error` を出し、回帰試験では失敗になります。

### 13.3 テスト

| テスト | 内容 |
|---|---|
| b2r_reg_test | レジスタのリセット値、読み書き、バイトイネーブル、読み出し専用、未定義アドレス |
| b2r_smoke_test | 既定の設定で1フレーム + 乱数の設定 |
| b2r_phase_test | Bayer の並び4種類 |
| b2r_func_test | BLC / WB / FCS / ガンマの有効・無効とパラメータの乱数 |
| b2r_bypass_test | バイパス(R=G=B=Bayer 値) |
| b2r_tpg_test | テストパターン4種類(入力メモリを読まないこと) |
| b2r_size_test | 幅・高さの境界、クランプ、切り捨て |
| b2r_stress_test | メモリの遅れと READY の詰まりが多い条件 |
| b2r_4kb_test | 4KB 境界をまたぐラインとバーストの分割 |
| b2r_auto_restart_test | 自動再開と REG_UPDATE(設定の保持) |
| b2r_error_test | 読み出し・書き込みのエラー応答と割り込み |
| b2r_sw_reset_test | ソフトリセット(停止中、処理中、START と同時) |
| b2r_ctrl_test | 処理中の START(保留)、BUSY、割り込み出力 |
| b2r_full_frame_test | 3840×2160 の1フレーム |
| b2r_random_test | すべてを乱数で組み合わせる(12フレーム) |
| b2r_wave_test | 仕様書の波形図を作るためのテスト(9章) |

テスト共通のプラスアーグ: `+B2R_FRAMES=n`(フレーム数)、`+B2R_TIMING=0/1/2`(メモリの応答: 速い / 乱数 / 遅い・詰まりが多い)、`+B2R_WMAX`、`+B2R_HMAX`(乱数で決める幅・高さの上限、既定 256 / 48)、`+B2R_DUMP=接頭辞`(フレームの入出力をファイルに出す)。

### 13.4 回帰試験

`sim/tests.list` に、ビルド(PPC=8/4/2/1、同期化セルの乱数遅延あり)、テスト、シードの数、プラスアーグを書いています。クロックの周期の組み合わせ(clk と ctrl_clk のどちらが速い場合も)を含みます。

| ビルド | 内容 | 実行数 |
|---|---|---:|
| ppc8 | PPC=8 | 56 |
| ppc4 | PPC=4 | 7 |
| ppc2 | PPC=2 | 5 |
| ppc1 | PPC=1 | 5 |
| cdc | PPC=8、`BAYER2RGB_CDC_RANDOM_DELAY`(同期化の取り込みを乱数で1クロック遅らせる) | 16 |
| 合計 | | 89 |

結果(2026-10-25、Verilator 5.053、2コアのマシン):

| 回帰試験 | 実行数 | 結果 | 時間(ビルドを含む) | 結果のファイル |
|---|---:|---|---:|---|
| `make regress` | 89 | PASS 89 / FAIL 0 | 13分27秒 | `sim/results/regress.txt` |
| `make cov`(カバレッジ付き) | 89 | PASS 89 / FAIL 0 | 16分23秒 | `sim/results/regress_cov.txt` |

合否は、ログに `TEST PASSED` があり、`%Error`(インタフェースの検査、RTL の検査、SRAM モデルの検査)がないことで判定しています。`make lint`(Verilator `-Wall`)の警告は PPC=8/4/2/1 のいずれも0件です(除外の設定は `rtl/bayer2rgb_lint.vlt`)。3840×2160 の1フレーム(`b2r_full_frame_test`)も一致しました。

### 13.5 Python モデルとの照合

`+B2R_DUMP` で出したフレーム(設定、入力、DUT の出力、SV モデルの出力)を `tools/check_dumps.py` で Python モデルと照合しました。

| 実行したテスト | フレーム数 | 結果 |
|---|---:|---|
| PPC=8: b2r_random_test ×2、b2r_func_test、b2r_phase_test、b2r_bypass_test、b2r_tpg_test、b2r_size_test。PPC=4/2/1: b2r_random_test | 122 | DUT = SV モデル = Python モデル(全フレーム一致) |

### 13.6 カバレッジ

カバレッジ付きの回帰試験(`make cov`、89本、PPC=8/4/2/1 と同期化の乱数遅延の5ビルド)をまとめた結果です。

#### 機能カバレッジ

covergroup 3つ(cg_frame: フレームの設定、cg_burst: AXI のバースト、cg_event: 制御のイベント)のビン 93個は、すべて当たりました。Verilator の covergroup の集計(`verilator_coverage`: covergroup 100.0% (93/93))と、ログからの集計(`tools/merge_cov.py`)の両方で 100% です。

| covergroup.coverpoint | ビン数 | 当たったビン | カバレッジ | 当たっていないビン |
|---|---:|---:|---:|---|
| cg_frame.cp_phase | 4 | 4 | 100.0% | - |
| cg_frame.cp_blc | 2 | 2 | 100.0% | - |
| cg_frame.cp_wb | 2 | 2 | 100.0% | - |
| cg_frame.cp_fcs | 2 | 2 | 100.0% | - |
| cg_frame.cp_gamma | 2 | 2 | 100.0% | - |
| cg_frame.cp_bypass | 2 | 2 | 100.0% | - |
| cg_frame.cp_tpg | 5 | 5 | 100.0% | - |
| cg_frame.cp_w | 7 | 7 | 100.0% | - |
| cg_frame.cp_h | 6 | 6 | 100.0% | - |
| cg_frame.x_phase_func | 16 | 16 | 100.0% | - |
| cg_frame.x_func | 16 | 16 | 100.0% | - |
| cg_burst.cp_dir | 2 | 2 | 100.0% | - |
| cg_burst.cp_len | 3 | 3 | 100.0% | - |
| cg_burst.cp_reason | 3 | 3 | 100.0% | - |
| cg_burst.x_dir_reason | 6 | 6 | 100.0% | - |
| cg_burst.x_dir_len | 6 | 6 | 100.0% | - |
| cg_event.cp_ev | 9 | 9 | 100.0% | - |
| 合計 | 93 | 93 | 100.0% | |

#### コードカバレッジ(RTL)

Verilator の行カバレッジ(`--coverage-line`)を `tools/cov_summary.py` で RTL のファイルごとにまとめたものです。「分岐」は if / case の各枝です。インスタンスと配線だけのファイル(BAYER2RGB、CORE、AXIM_RD_BRIDGE、AXIM_WR_BRIDGE、SRAM と同期化セルのラッパ)とパッケージは、数える行がないので表にありません。

| ファイル | 行 | 実行した行 | 行カバレッジ | 分岐 | 通った分岐 | 分岐カバレッジ |
|---|---:|---:|---:|---:|---:|---:|
| BAYER2RGB_AXIL_BRIDGE.sv | 66 | 66 | 100.0% | 26 | 26 | 100.0% |
| BAYER2RGB_BLC.sv | 22 | 22 | 100.0% | 7 | 7 | 100.0% |
| BAYER2RGB_CDC.sv | 76 | 76 | 100.0% | 20 | 20 | 100.0% |
| BAYER2RGB_DMSC.sv | 98 | 98 | 100.0% | 16 | 16 | 100.0% |
| BAYER2RGB_FCS.sv | 70 | 70 | 100.0% | 22 | 22 | 100.0% |
| BAYER2RGB_GAMMA.sv | 74 | 74 | 100.0% | 24 | 24 | 100.0% |
| BAYER2RGB_IN_CTRL.sv | 53 | 53 | 100.0% | 60 | 60 | 100.0% |
| BAYER2RGB_LBUF.sv | 46 | 46 | 100.0% | 21 | 21 | 100.0% |
| BAYER2RGB_OUT_FIFO.sv | 2 | 2 | 100.0% | 2 | 2 | 100.0% |
| BAYER2RGB_OUT_FMT.sv | 41 | 41 | 100.0% | 11 | 11 | 100.0% |
| BAYER2RGB_RD_DMA.sv | 82 | 82 | 100.0% | 95 | 95 | 100.0% |
| BAYER2RGB_REG.sv | 249 | 249 | 100.0% | 46 | 46 | 100.0% |
| BAYER2RGB_SFIFO.sv | 52 | 49 | 94.2% | 48 | 47 | 97.9% |
| BAYER2RGB_SKID.sv | 18 | 18 | 100.0% | 22 | 22 | 100.0% |
| BAYER2RGB_WB.sv | 32 | 32 | 100.0% | 12 | 12 | 100.0% |
| BAYER2RGB_WR_DMA.sv | 113 | 101 | 89.4% | 129 | 117 | 90.7% |
| 合計 | 1094 | 1079 | 98.6% | 561 | 548 | 97.7% |

実行していない行は、どちらも動作中には到達しないものです。

| ファイル | 行 | 理由 |
|---|---|---|
| BAYER2RGB_SFIFO.sv | 66〜69 | FF 版の `i_clr` の処理。FF 版は WR_DMA のバースト長のキューだけで使い、`i_clr` は0に固定している |
| BAYER2RGB_WR_DMA.sv | 26〜38 | 定数関数 `f_gcd`(パラメータの計算でエラボレーションのときだけ評価する) |

トグルカバレッジは取っていません。

### 13.7 実行方法

必要なもの: Verilator 5.053 以降(`--timing` と UVM が使える版)、UVM 1800.2-2017-1.0(Verilator で使える版。Verilator 向けの修正を入れたものが CHIPS Alliance から出ている [R12][R13])、FST 出力用の zlib と lz4、Python 3(numpy、Pillow)。

```sh
export UVM_HOME=/path/to/uvm-2017-1.0     # src/uvm_pkg.sv があるディレクトリ
cd sim
make lint                                  # RTL の lint(Verilator -Wall)
make build                                 # Verilator でビルド(obj_ppc8/)
make run TEST=b2r_smoke_test SEED=1        # 1テスト(logs/ にログ)
make run TEST=b2r_random_test SEED=5 WAVES=1   # 波形 waves.fst → gtkwave waves.fst
make run TEST=b2r_smoke_test PPC=4         # PPC を変える(obj_ppc4/)
make regress                               # 回帰試験(結果は logs/regress.txt)
make cov                                   # カバレッジ付きの回帰試験(cov/)
```

Xcelium(このリポジトリの環境では実行していません。14章):

```sh
cd sim
make xrun TEST=b2r_smoke_test                    # 付属の UVM(-uvmhome CDNS-1.2)[R16]
make xrun TEST=b2r_smoke_test XWAVES=vcd         # waves.vcd を出す → gtkwave waves.vcd
make xrun TEST=b2r_smoke_test XWAVES=shm         # waves.shm を出す(xrun_waves.tcl)[R15]
make xrun TEST=b2r_smoke_test XUVM=$UVM_HOME     # Verilator と同じ UVM のソースを使う
```

波形: Verilator は FST(`TRACE=vcd` を付けると VCD)、Xcelium は VCD(`XWAVES=vcd`)を出し、どちらも GTKWave で見られます [R17]。

Python のリファレンスモデル:

```sh
python3 tools/gen_image.py --size 640x480 --kind blocks --out in.raw        # 合成画像(16bit LE)
python3 tools/b2r_model.py --in in.raw --raw-size 640x480 --crop 640x480 --out out.rgb --png out.png
python3 tools/b2r_model.py --in in.raw --raw-size 640x480 --cfg cfg.json --out out.rgb   # 設定を JSON で与える
python3 tools/check_dumps.py 'sim/dump/*.cfg.json'                          # +B2R_DUMP の照合
```

### 13.8 ドキュメントの作り直し

```sh
python3 doc/tools/gen_arch.py doc/arch               # ブロック図(draw.io、SVG)
python3 doc/tools/gen_pins.py rtl doc/spec/pins      # 端子表
cd sim && make build TRACE=vcd && ./obj_ppc8_vcd/Vtb_top +UVM_TESTNAME=b2r_wave_test +verilator+seed+1 +WAVES
python3 ../doc/tools/gen_waves.py waves.vcd ../doc/spec/wave      # 波形図(WaveDrom の JSON)
cd ../doc/spec/wave && for j in *.json; do node ../../tools/render_wavedrom.js $j ${j%.json}.svg; done
cd ../../.. && python3 doc/tools/gen_spec.py         # この仕様書
```

SVG にするには node と wavedrom パッケージ(`npm install wavedrom`)が必要です。

#### GitHub での波形図の表示

GitHub の Markdown は WaveDrom を描画しないので、この仕様書では SVG の画像を表示し、WaveDrom の記述(JSON)を `<details>` の中の ```wavedrom ブロックに入れています。記述は [WaveDrom エディタ](https://wavedrom.com/editor.html) に貼ると編集できます。リポジトリを公開している場合は、WaveDrom のサーバで JSON を直接描画することもできます [R14]:

```md
![wr_dma](https://svg.wavedrom.com/github/<ユーザ>/<リポジトリ>/<ブランチ>/doc/spec/wave/wr_dma.json)
```

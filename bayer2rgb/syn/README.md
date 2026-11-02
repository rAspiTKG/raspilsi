# 論理合成

| パス | 内容 |
|---|---|
| `constraints/bayer2rgb.sdc` | タイミング制約(論理合成・配置配線・STA で共通) |
| `yosys/` | Yosys による論理合成と合成後の STA(ASAP7) |
| `rtl/asap7/` | ASAP7 用の SRAM・同期化のラッパ(仮マクロ、FF 2段) |
| `rtl/foundry/` | Foundry のプロセス用の SRAM・同期化のラッパ(雛形。マクロ名・セル名を記入して使う) |
| `results/` | 合成の結果(面積、タイミング)の写し |

Cadence Genus での合成は `pd/commercial/genus/syn.tcl` にあります(雛形)。

## 1. タイミング制約(`constraints/bayer2rgb.sdc`)

ポート名とクロック名だけを使った Tcl の SDC です。セル名・インスタンス名を使わないので、合成ツールや合成の前後によらず同じファイルを読めます。

| 項目 | 値(既定) | 変数 |
|---|---|---|
| clk(映像系) | 2.5 ns(400 MHz) | `B2R_CLK_PERIOD` |
| ctrl_clk(制御系) | 10.0 ns(100 MHz) | `B2R_CTRL_PERIOD` |
| クロックの不確かさ | セットアップ 0.10 ns、ホールド 0.03 ns | `B2R_UNC_SETUP`、`B2R_UNC_HOLD` |
| 入出力の相手のクロック | `clk_io` / `ctrl_clk_io`(clk / ctrl_clk と同じ周期の仮想クロック) | - |
| クロックツリーの遅れの見込み | 0 ns(IP のクロックと入出力の相手のクロックの両方に与える) | `B2R_CLK_LATENCY`、`B2R_CTRL_LATENCY` |
| AXI の入出力遅延 | 周期の 50%(外側が使う割合)。clk_io / ctrl_clk_io から測る | `B2R_IO_PCT` |
| リセットの解除(rst_n、ctrl_rst_n) | 周期の 50%(外側が使う割合)。リカバリ・リムーバルを検査する | `B2R_RST_PCT` |
| 入力の遷移時間 / 出力の負荷 | 0.05 ns / 0.005 pF | `B2R_IN_TRAN`、`B2R_OUT_LOAD` |
| clk 側 ⇔ ctrl_clk 側 | 受け側の1周期(クロックの遅れを含めない)、ホールドは検査しない | - |
| ライブラリの単位 | ns / pF(ASAP7 は ps / fF) | `B2R_TIME_UNIT`、`B2R_CAP_UNIT` |

変数は Tcl のグローバル変数、環境変数、既定値の順に探します。値は ns / pF で書き、`B2R_TIME_UNIT` / `B2R_CAP_UNIT` に合わせて換算します。

clk と ctrl_clk の間の経路は BAYER2RGB_CDC の乗せ換え(同期化セルへのトグルと MCP のデータ)だけです(仕様書 11章)。`set_clock_groups -asynchronous` を使うと遅れの上限の制約まで消えるので、`set_max_delay -ignore_clock_latency`(受け側の1周期)と `set_false_path -hold` を使っています。合成後の STA の `reports/sta_cdc.txt` に、2つの側の間の経路の終点の数を出しています。

入出力の遅延は、IP の外の FF のクロック(仮想クロック)から測ります。クロックツリーを作る前は、`B2R_CLK_LATENCY` / `B2R_CTRL_LATENCY` の値によらず同じ結果になります(IP のクロックと仮想クロックに同じ遅れを与えるため)。クロックツリーの後は、仮想クロックの遅れを実際のクロックツリーの遅れに合わせてください。合わせないと、入力の経路に不要なホールド用バッファが入ります(仕様書 14.2、14.4)。Innovus では CTS の後に `update_io_latency` で合わせられます(`pd/commercial/innovus/cts.tcl`)。OpenROAD では `pd/openroad` の `make io_latency` で測って与えます。

## 2. Yosys での論理合成(`yosys/`)

### 2.1 必要なもの

Yosys 0.48 以降(0.48+5 で確認)、sv2v(v0.0.13 で確認)、OpenSTA(OpenROAD に付いている `sta`。2.6.0 で確認)、Python 3、ASAP7 のライブラリ(OpenROAD-flow-scripts の `flow/platforms/asap7`)。`FRONTEND=slang` には yosys-slang のプラグインが要ります(OSS CAD Suite に入っている)。

### 2.2 使い方

下のコマンドは、全部を続けて実行するものではありません。最初に「準備」を行い、そのあとは目的に合うケースを1つ選んで実行します。ふつうはケース1だけで足ります。

#### 準備(端末を開くたびに)

```sh
cd syn/yosys
export ORFS_FLOW=$HOME/OpenROAD-flow-scripts/flow   # ASAP7 のライブラリがある ORFS の flow ディレクトリ
which sv2v yosys sta                                 # 3つとも見つかることを確かめる
```

ORFS が既定の場所(`$HOME/OpenROAD-flow-scripts/flow`)にあれば、`export` は要りません。

#### ケース1: 論理合成と合成後の STA(ふつうはこれ)

```sh
make
```

SRAM の仮マクロ → ライブラリの準備 → sv2v → 合成 → STA を順に行います(PPC=8、400 MHz、WC コーナー)。結果は `out/asap7_ppc8/` にできます(下の表)。もう一度 `make` すると、終わっている段階は飛ばして STA だけをやり直します。

#### ケース2: 1クロックの画素数(PPC)を変える

```sh
make PPC=4
```

結果は `out/asap7_ppc4/` にできます。出力先が PPC ごとに分かれるので、`make clean` は要りません(PPC=8 の結果も残ります)。

#### ケース3: STA だけやり直す

```sh
make sta                    # SDC を直したとき
make sta CLK_PERIOD=2.0     # 合成し直さずに、別の周期でタイミングを見るとき
```

合成済みのネットリストに対して STA だけを行います(ネットリストがなければ、先に合成します)。2行はどちらか一方を使います。

#### ケース4: 合成だけ行う(STA はしない)

```sh
make synth
```

#### ケース5: sv2v を使わずに読む(yosys-slang)

```sh
make FRONTEND=slang OUT=out/asap7_ppc8_slang
```

sv2v がないとき、または sv2v の結果と比べたいときに使います。Yosys に yosys-slang のプラグインが要ります(`yosys -m slang -p "help read_slang"` で確認できます)。`OUT` で出力先を分けて、ケース1 の結果を上書きしないようにしています。元の階層のまま合成します。

#### ケース6: 周期・コーナーなどを変えて合成し直す

```sh
make clean                  # out/ をすべて消す(PPC=8 だけなら rm -rf out/asap7_ppc8)
make CLK_PERIOD=2.0
```

出力先の名前は PPC だけで決まるので、PPC 以外の変数(`CLK_PERIOD`、`CORNER`、`ABC_AREA`、`SYNTH_FLATTEN`、`FRONTEND`)を変えても、そのままでは合成し直しません。先に `make clean` するか、`make CLK_PERIOD=2.0 OUT=out/asap7_ppc8_2ns` のように出力先を分けてください。

#### 変数

`PPC`(1/2/4/8)、`CLK_PERIOD` / `CTRL_PERIOD` [ns]、`CORNER`(WC / TC / BC)、`FRONTEND`(sv2v / slang)、`SYNTH_FLATTEN`(0: 階層を残す / 1: 平らにする)、`ABC_AREA`(1: 面積優先 / 0: 速度優先)、`OUT`(出力先)、`YOSYS` / `SV2V` / `STA`(コマンドの場所。例 `make SV2V=$HOME/work/sv2v-Linux/sv2v`)。

#### 出力(`out/asap7_ppc<PPC>/`)

| ファイル | 内容 |
|---|---|
| `bayer2rgb_syn.v` | 合成後のネットリスト(階層つき) |
| `macros/` | SRAM の仮マクロ(LEF、Liberty、ブラックボックスの Verilog) |
| `reports/area.txt` | セルの数と面積(モジュールごと。Yosys の `stat`) |
| `reports/area_summary.md` | モジュールごとの面積の表(`scripts/area_summary.py`) |
| `reports/sta_summary.txt`、`sta_setup.txt`、`sta_hold.txt`、`sta_drv.txt` | 合成後の STA(配線の遅れなし) |
| `reports/sta_cdc.txt`、`sta_cdc_paths.txt` | clk 側と ctrl_clk 側の間の経路(終点の数、最も遅い経路) |
| `yosys.log`、`sta.log` | ログ |

### 2.3 流れ

1. `make macros`: 使う大きさの SRAM の仮マクロを `tools/gen_sram_macro.py` で作る(PPC で大きさが変わる)。
2. `make libs`: ASAP7 の Liberty を Yosys / ABC が読める形にそろえ、1つにまとめる(`tools/liberty_prep.py`)。
3. `make sv2v`: RTL を sv2v で Verilog に変換する。SRAM と同期化のラッパは `rtl/asap7/` のものに差し替える。
4. `make synth`: `scripts/synth.tcl`。階層を残して合成し(`SYNTH_FLATTEN=0`。ABC がモジュールごとに動くので必要なメモリが少ない)、加算器を全加算器・半加算器のセルに、FF を ASAP7 の FF に割り当て、組み合わせ回路を ABC で割り当てる。`FRONTEND=slang` では yosys-slang の `--best-effort-hierarchy` で元の階層を残す。
5. `make sta`: `scripts/sta.tcl`。OpenSTA で SDC を読み、セットアップ・ホールド・遷移時間などを調べる。

階層を平らにする(`SYNTH_FLATTEN=1`)と、モジュールをまたいだ最適化ができる代わりに、ABC に一度に大きな回路を渡すので、必要なメモリと時間が増えます。

### 2.4 SRAM の仮マクロ

`tools/gen_sram_macro.py` が作る 1R1W(読み1・書き1)の SRAM のモデルです。配置配線が通ることを確かめるためのもので、実際の SRAM ではありません。

| 項目 | 決め方 |
|---|---|
| 外形 | 1ビット 0.06 um² として面積を決め、端子が並ぶ高さを確保する |
| 端子 | 左辺の M4 に並べる(0.096 um 間隔)。電源 VDD / VSS は M4 の横縞 |
| 遅れ | 読み出し 0.10 + 0.012 × log2(ビット数) ns、セットアップ / ホールド 0.05 ns |

### 2.5 結果

`results/asap7_ppc8/` と仕様書 14章を見てください。

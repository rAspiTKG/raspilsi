# 論理合成

| パス | 内容 |
|---|---|
| `constraints/bayer_ex.sdc` | タイミング制約(論理合成・配置配線・STA で共通)。設定値と意味は [constraints/README.md](constraints/README.md) |
| `yosys/` | Yosys による論理合成と合成後の STA(ASAP7) |
| `results/asap7/` | 合成の結果(面積、タイミング)の写し |

Cadence Genus での合成は `pd/commercial/genus/syn.tcl` にあります(雛形)。BAYER_EX は製品IP(SRAM・同期化セル)を使わないので、プロセスごとに差し替える RTL はありません。

## 1. タイミング制約(`constraints/bayer_ex.sdc`)

ポート名とクロック名だけを使った Tcl の SDC です。設定値と意味の詳しい説明は [constraints/README.md](constraints/README.md) にあります。

| 項目 | 値(既定) | 変数 |
|---|---|---|
| clk | 2.5 ns(400 MHz) | `BEX_CLK_PERIOD` |
| クロックの不確かさ | セットアップ 0.10 ns、ホールド 0.03 ns | `BEX_UNC_SETUP`、`BEX_UNC_HOLD` |
| 入出力の相手のクロック | `clk_io`(clk と同じ周期の仮想クロック) | - |
| クロックツリーの遅れの見込み | 0 ns(clk と clk_io の両方に与える) | `BEX_CLK_LATENCY` |
| 入出力の遅延 | 周期の 50%(外側が使う割合)。clk_io から測る | `BEX_IO_PCT` |
| リセットの解除(rst_n) | 周期の 50%(外側が使う割合)。リカバリ・リムーバルを検査する | `BEX_RST_PCT` |
| 入力の遷移時間 / 出力の負荷 | 0.05 ns / 0.005 pF | `BEX_IN_TRAN`、`BEX_OUT_LOAD` |
| ライブラリの単位 | ns / pF(ASAP7 は ps / fF) | `BEX_TIME_UNIT`、`BEX_CAP_UNIT` |

## 2. Yosys での論理合成(`yosys/`)

### 2.1 必要なもの

Yosys 0.48 以降(0.48+5 で確認)、sv2v(v0.0.13 で確認)、OpenSTA(OpenROAD に付いている `sta`)、Python 3、ASAP7 のライブラリ(OpenROAD-flow-scripts の `flow/platforms/asap7`)。`FRONTEND=slang` には yosys-slang のプラグインが要ります(OSS CAD Suite に入っている)。

トップは `BAYER_EX`(`rtl/BAYER_EX.sv`)です。sv2v は、インタフェースのポートを持つモジュール(`BAYER_EX_CORE`)をトップにできません(「Specified top module … has interface ports. Please instantiate it somewhere and use that as your top module instead.」)。インタフェースのインスタンスは使う側に展開して変換するので、合成後の階層には `BAYER_EX` と `BAYER_EX_PIXCOR` が残り、`BAYER_EX_CORE` は `BAYER_EX` の中に入ります。

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

ライブラリの準備 → sv2v → 合成 → STA を順に行います(400 MHz、WC コーナー。CPU 2個で 30 秒ほど)。結果は `out/asap7/` にできます(下の表)。もう一度 `make` すると、終わっている段階は飛ばして STA だけをやり直します。

#### ケース2: STA だけやり直す

```sh
make sta                    # SDC を直したとき
make sta CLK_PERIOD=2.0     # 合成し直さずに、別の周期でタイミングを見るとき
```

合成済みのネットリストに対して STA だけを行います(ネットリストがなければ、先に合成します)。2行はどちらか一方を使います。

#### ケース3: 合成だけ行う(STA はしない)

```sh
make synth
```

#### ケース4: 周期・コーナーなどを変えて合成し直す

```sh
make clean                  # out/ をすべて消す
make CLK_PERIOD=2.0
```

出力先の名前に周期などは入らないので、変数(`CLK_PERIOD`、`CORNER`、`ABC_AREA`、`SYNTH_FLATTEN`、`FRONTEND`)を変えても、そのままでは合成し直しません。先に `make clean` するか、`make CLK_PERIOD=2.0 OUT=out/asap7_2ns` のように出力先を分けてください。

#### ケース5: sv2v を使わずに読む(yosys-slang)

```sh
make FRONTEND=slang OUT=out/asap7_slang
```

sv2v がないとき、または sv2v の結果と比べたいときに使います。Yosys に yosys-slang のプラグインが要ります(`yosys -m slang -p "help read_slang"` で確認できます)。`OUT` で出力先を分けて、ケース1 の結果を上書きしないようにしています。yosys-slang はインタフェースをそのまま読めるので、`BAYER_EX_CORE` の階層が残ります。結果はケース1 とほぼ同じでした(14,036 セル、1,414.2 um²、セットアップ WNS +735.4 ps)。

#### 変数

`CLK_PERIOD` [ns]、`CORNER`(WC / TC / BC)、`FRONTEND`(sv2v / slang)、`SYNTH_FLATTEN`(0: 階層を残す / 1: 平らにする)、`ABC_AREA`(1: 面積優先 / 0: 速度優先)、`OUT`(出力先)、`YOSYS` / `SV2V` / `STA`(コマンドの場所。例 `make SV2V=$HOME/work/sv2v-Linux/sv2v`)。

#### 出力(`out/asap7/`)

| ファイル | 内容 |
|---|---|
| `bayer_ex_syn.v` | 合成後のネットリスト(階層つき) |
| `bayer_ex_sv2v.v` | sv2v で変換した Verilog |
| `reports/area.txt` | セルの数と面積(モジュールごと。Yosys の `stat`) |
| `reports/area_summary.md` | モジュールごとの面積の表(`scripts/area_summary.py`) |
| `reports/sta_summary.txt`、`sta_setup.txt`、`sta_hold.txt`、`sta_drv.txt` | 合成後の STA(配線の遅れなし) |
| `reports/sta_groups.txt` | 経路の種類ごと(入力 → FF、FF → FF、FF → 出力、rst_n の解除)の最も遅い経路 |
| `reports/sta_check_setup.txt`、`sta_ports.txt` | 制約の漏れの確認(空なら漏れなし)、遅延を与えた入出力の本数 |
| `yosys.log`、`sta.log` | ログ |

### 2.3 流れ

1. `make libs`: ASAP7 の Liberty を Yosys / ABC が読める形にそろえ、1つにまとめる(`tools/liberty_prep.py`)。
2. `make sv2v`: RTL を sv2v で Verilog に変換する(トップ `BAYER_EX`)。
3. `make synth`: `scripts/synth.tcl`。階層を残して合成し(`SYNTH_FLATTEN=0`)、加算器を全加算器・半加算器のセルに、FF を ASAP7 の FF に割り当て、組み合わせ回路を ABC で割り当てる。
4. `make sta`: `scripts/sta.tcl`。OpenSTA で SDC を読み、セットアップ・ホールド・遷移時間などを調べる。

### 2.4 結果

`results/asap7/` に写しを置いています。説明は仕様書 9.1 にあります。

| 項目 | 値 |
|---|---|
| セル数 / 面積 | 14,169 / 1,427.6 um²(PIXCOR 83.7%) |
| FF | 587 個 |
| セットアップ WNS(配線の遅れなし) | +755.3 ps(FF → FF: r_cfg のゲイン → 乗算 → r_data2) |
| 入力 → FF / FF → 出力 / rst_n の解除 | +804.6 / +854.1 / +1170.5 ps |
| ホールド | rst_n のリムーバルと入力の直後の FF で違反(−76.8 ps)。合成直後で配線とバッファがないため。配置配線で直る(仕様書 9.2) |

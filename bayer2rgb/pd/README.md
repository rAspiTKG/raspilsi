# 物理設計(配置配線とサインオフ)

論理合成(`syn/`)の後の工程です。2つの環境があります。

| ディレクトリ | ツール・PDK | 状態 |
|---|---|---|
| `pd/openroad/` | OpenROAD-flow-scripts(ORFS)+ ASAP7(公開の 7nm 相当の予測 PDK) | この環境で概略配線まで実行した(結果は `pd/openroad/results/`)。詳細配線から後はメモリが足りず未実行 |
| `pd/commercial/` | Cadence(Genus / Innovus / Tempus / Conformal / Pegasus)+ Foundry の PDK | 雛形。PDK と商用ツールがないので未実行 |

ASAP7 の結果は、RTL・制約・流れが通ることと、面積・タイミングのおおよその傾向を見るためのものです。ASAP7 は研究用の予測 PDK で、Foundry のプロセスの性能・面積とは一致しません。SRAM も `tools/gen_sram_macro.py` で作った仮のマクロ(外形・端子・タイミングの見積もり)です。

```
RTL(rtl/)
  │  syn/rtl/<PDK>/ で SRAM と同期化のラッパを差し替える
  ▼
論理合成  syn/yosys(Yosys)            または  pd/commercial/genus(Genus)
  │  制約は共通の syn/constraints/bayer2rgb.sdc
  ▼
配置配線  pd/openroad(ORFS)           または  pd/commercial/innovus(Innovus)
  ▼
サインオフ OpenROAD の抽出・STA・IR    または  Quantus / Tempus / Conformal / Pegasus
```

---

## 1. OpenROAD-flow-scripts + ASAP7(`pd/openroad/`)

### 1.1 必要なもの

| もの | 確認した版 | 備考 |
|---|---|---|
| OpenROAD-flow-scripts | commit `8433e67a`(2024-12-11) | `flow/` だけを使う。`ORFS_FLOW` で場所を指定 |
| OpenROAD | v2.0-17598-ga008522d8 | ORFS がその commit で使う版 |
| Yosys | 0.48+5 | 論理合成(`syn/yosys`) |
| sv2v | v0.0.13 | SystemVerilog → Verilog の変換(`syn/yosys` の既定) |
| Python 3 | 3.13(PyYAML、matplotlib、numpy) | ORFS のスクリプト、要約、図 |
| GNU time | - | ORFS が各段階の時間とメモリを測るのに使う |
| KLayout | (この環境にはない) | GDS を作るときだけ要る(`make gds`) |
| メモリ | 概略配線まで: PPC=8 で 4 GB 弱、PPC=2 で 2 GB 弱。詳細配線: PPC=2 で 12 GB 超、PPC=8 で 14 GB 超(どちらもこの環境では足りずに途中で止まった) | 詳細配線(TritonRoute)が最も多く使う。32 GB 以上の計算機を勧める(1.6) |

新しい ORFS では、合成済みのネットリストを渡す変数の名前が `CACHED_NETLIST` から `SYNTH_NETLIST_FILES` に変わっています。`asap7/config.mk` は両方を設定しています。

### 1.2 使い方

下のコマンドも、全部を続けて実行するものではありません。最初に「準備」を行い、そのあとは目的に合うケースを1つ選んで実行します。どのケースも論理合成(`syn/yosys`)を自動で行うので、先に `syn/yosys` で `make` しておく必要はありません。

#### 準備(端末を開くたびに)

```sh
cd pd/openroad
export ORFS_FLOW=$HOME/OpenROAD-flow-scripts/flow
which openroad sta yosys sv2v        # 4つとも見つかることを確かめる
```

ORFS をビルドした場合は、`source <ORFS のディレクトリ>/env.sh` で `openroad`、`sta`、`yosys` が PATH に入ります。

#### ケース1: 最後まで流す(メモリ 32 GB 以上の計算機)

```sh
make
```

論理合成 → フロアプラン → 配置 → CTS → 入出力の遅れの確認 → 配線(概略・詳細)→ 最終の解析 → 要約を順に行います(PPC=8、400 MHz)。詳細配線は多くのメモリを使います(1.6)。

#### ケース2: 概略配線まで流す(メモリが少ないとき。この環境で実行した範囲)

```sh
make synth floorplan place cts io_latency grt summary          # PPC=8(CPU 2個で約 40 分)
make PPC=2 synth floorplan place cts io_latency grt summary    # PPC=2(約 15 分)
```

詳細配線の手前で止めて、要約を作ります。2行はどちらか一方を使います(両方流してもかまいません。結果は PPC ごとに別のディレクトリにできます)。

#### ケース3: 段階を区切って進める

```sh
make cts          # 論理合成から CTS まで
make grt          # 続けて概略配線
make route        # 続けて詳細配線
make final        # 続けて最終の解析(寄生抽出、STA、電力、IR ドロップ)
make summary      # 要約と配置の図(終わっている段階までで作る。いつでも実行できる)
```

途中の結果を見ながら進めたいときに、上から順に実行します。どの段階を指定しても、終わっていない前の段階から順に流れ、終わっている段階は飛ばします。

#### ケース4: 入出力の遅れを測って設定を直す(PPC や設定を変えたとき)

```sh
make cts
make io_latency
```

CTS の後に、入出力につながる FF のクロックの遅れ(中央値)を表示します。`asap7/config.mk` の表(`B2R_IO_LAT_PPC<n>`)と違っていたら表を直して、ケース1 かケース2 を流します(`config.mk` を変えると最初の段階からやり直します)。理由は 1.4 にあります。

#### ケース5: 1クロックの画素数を変える

```sh
make PPC=4
```

作業用のディレクトリは PPC ごとに分かれる(`work/asap7_ppc4/`)ので、`make clean` は要りません。ケース2 のように段階を並べることもできます(`make PPC=4 synth floorplan place cts io_latency grt summary`)。

#### ケース6: 周期やコーナーを変える

```sh
make clean                         # work/ をすべて消す
make -C ../../syn/yosys clean      # 論理合成の結果も消す
make CLK_PERIOD=2.0
```

周期やコーナーは作業用のディレクトリの名前に入らないので、変えても前の結果を使ってしまいます。配置配線(`work/`)と論理合成(`syn/yosys/out/`)の結果を先に消してください。3行目は最後まで流すので、メモリが少ないときはケース2 と同じく段階を並べます(`make CLK_PERIOD=2.0 synth floorplan place cts io_latency grt summary`)。

#### ケース7: GDS を作る

```sh
make gds
```

ケース1 で最後まで流したあとに実行します(KLayout が必要です。SRAM の仮マクロの中身は空です)。

#### 結果の場所

結果は `work/asap7_ppc<PPC>/` の下にできます(ORFS の `results/`、`reports/`、`logs/`)。`make summary` で `results/asap7_ppc<PPC>/summary.md` と配置の図(`layout.png`)を作ります。

段階の要否は、この Makefile が前の段階の結果のファイルを見て決め、ORFS の `do-<段階>`(依存関係を見ない実行)を呼びます。この版の ORFS は、合成済みのネットリスト(`CACHED_NETLIST`)を使うと、呼ぶたびに合成の段階からやり直しになるためです。ネットリスト・SDC・`asap7/config.mk` を変えると最初の段階からやり直します。`ORFS_ARGS` で変数を変えたときは、`make clean` してから流してください。

### 1.3 流れ

| 段階 | ORFS の手順 | 内容 |
|---|---|---|
| synth | (ORFS では合成しない) | `syn/yosys` のネットリストと SDC をそのまま渡す(`CACHED_NETLIST`) |
| floorplan | 2_1〜2_5 | コアの大きさ(使用率 30%)、端子の配置(上辺と下辺)、SRAM マクロの配置(`asap7/macro_place.tcl`)、タップセル、電源配線(M1/M2 のレール、M5/M6 のストライプ、マクロは M4–M5 で接続) |
| place | 3_1〜3_5 | タイミングと配線の混み具合を見た配置、バッファ挿入とサイズ変更、詳細配置 |
| cts | 4_1 | クロックツリー(clk、ctrl_clk)、ホールドの修正 |
| io_latency | (ORFS の `make run`) | 入出力につながる FF のクロックの遅れを測る(`scripts/io_latency.tcl` → `reports/.../io_latency.rpt`) |
| grt / route | 5_1〜5_3 | 概略配線と配線後の修正、詳細配線(TritonRoute)、フィラー |
| final | 6_1、6_report | 寄生抽出(OpenRCX)、配線後の STA、電力、IR ドロップ、最終のネットリスト・DEF・SPEF |

SRAM マクロは、面積の大きい順にコアの左端の列へ下から積み、入らなくなったら右端の列へ積みます。マクロの端子は左辺にあるので、左の列は左右を反転して(MY)端子をコアの内側へ向けます。位置は行の高さと M4 の配線格子の両方にそろえます。この版の OpenROAD の自動マクロ配置(RTL-MP)は、階層つきのネットリストで異常終了したので使っていません(`ORFS_ARGS="MACRO_PLACEMENT_TCL="` で試せます)。

### 1.4 設定(`asap7/config.mk`)

| 変数 | 既定 | 内容 |
|---|---|---|
| `B2R_PPC` | 8 | 1クロックの画素数(Makefile の `PPC`) |
| `B2R_CLK_PERIOD` / `B2R_CTRL_PERIOD` | 2.5 / 10.0 | clk / ctrl_clk の周期 [ns]。SDC に渡す |
| `B2R_CLK_LATENCY` / `B2R_CTRL_LATENCY` | PPC=8: 0.50 / 0.23、PPC=4: 0.45 / 0.22、PPC=2/1: 0.40 / 0.20 | 入出力の相手の仮想クロックの遅れ [ns]。SDC に渡す(下の説明) |
| `CORNER` | WC | ライブラリのコーナー(WC: SS 0.63 V 100°C、TC: TT 0.70 V 0°C、BC: FF 0.77 V 25°C) |
| `CORE_UTILIZATION` | 30 | コアの使用率 [%] |
| `PLACE_DENSITY` | 0.42 | 配置の密度 |
| `ROUTING_LAYER_ADJUSTMENT` | 0.3 | 概略配線で各層の容量から差し引く割合(ORFS の既定は 0.5) |
| `MACRO_PLACE_HALO` / `MACRO_PLACE_CHANNEL` | 4 4 / 8 8 | マクロのまわりの空き [um] |
| `MACRO_PLACEMENT_TCL` | `asap7/macro_place.tcl` | マクロの配置の規則 |
| `PLACE_PINS_ARGS` | `-exclude left:* -exclude right:*` | 端子を上辺と下辺に置く(左右の端はマクロの列) |

SDC は論理合成と同じ `syn/constraints/bayer2rgb.sdc` を、ASAP7 の単位(ps / fF)で読みます(`B2R_TIME_UNIT=ps`、`B2R_CAP_UNIT=fF`)。

SDC は入出力の遅延を、IP の外の FF のクロック(仮想クロック `clk_io`、`ctrl_clk_io`)から測ります。仮想クロックはクロックツリーを通らないので、CTS の後もクロックツリーの遅れの見込み(`B2R_CLK_LATENCY`、`B2R_CTRL_LATENCY`)のままです。見込みが 0 だと、入力ポートから FF への経路のホールドが、IP の中のクロックツリーの遅れ(PPC=8 で約 0.5 ns)だけ厳しくなり、不要なホールド用バッファが入ります。Innovus には仮想クロックの遅れをクロックツリーに合わせる `update_io_latency` がありますが、OpenROAD にはないので、`make io_latency` で測った値(入出力につながる FF のクロックの遅れの中央値)を `asap7/config.mk` の表に書いています。PPC や設定を変えたときは、測り直して表を直してください(見込み → 実測)。

### 1.5 結果

PPC=8 と PPC=2 を概略配線まで流しました(400 MHz、WC コーナー)。各段階の値と配置の図は `pd/openroad/results/asap7_ppc8/summary.md`、`asap7_ppc2/summary.md` にあります。説明は仕様書 14.4 にあります。

| 項目(概略配線の後) | PPC=8 | PPC=2 |
|---|---:|---:|
| ダイの大きさ | 301.7 × 301.7 um | 231.9 × 231.9 um |
| セル数 | 182,326 | 77,087 |
| セットアップ WNS / TNS | +2.0 ps / 0 | +3.9 ps / 0 |
| ホールド違反 | 0 | 0 |
| CTS で入れたホールド用バッファ | 1 | 125 |
| 遷移時間の違反 | 5 | 0 |
| 配線長(概略配線) | 1,857,903 um | 486,830 um |
| 実行時間(フロアプラン〜概略配線、CPU 2個) | 37.9 分 | 12.0 分 |

どちらも、最も余裕が小さいのは rst_n のリカバリの検査です(1.6)。

### 1.6 注意

- OpenROAD の GUI が使えない環境(Qt の部品がないなど)では、ORFS の最後の画像保存(`final_report.tcl` の `save_image`)で止まることがあります。この環境では OpenROAD を起動するスクリプトで `save_image` を無効にしています(最後の段階はこの環境では実行していません)。配置の図は DEF から描いています(`scripts/plot_layout.py`)。
- OpenROAD の中の Python(3.10)のために `PYTHONHOME` を設定する場合は、ORFS が呼ぶ外の `python3` に引き継がないようにしてください(この環境では `python3` を `PYTHONHOME` を消してから起動するスクリプトにした)。
- 仮マクロの電源端子は M4 にあります。ASAP7 の電源配線(`grid_strategy-M1-M2-M5-M6.tcl`)がマクロの M4 と M5 をつなぎます。マクロの位置によっては、M5 のストライプがマクロの M4 の端にかかってビアが入らない場所が出ます(警告 PDN-0110。PPC=2 では右の列の u_out_fifo で 9か所、PPC=8 では 0)。ほかの場所のビアでつながっていることを、フロアプランの後に `check_power_grid` で確かめています(VDD / VSS とも PSM-0040「All shapes ... are connected」)。
- 詳細配線(TritonRoute)は多くのメモリを使います。この環境(作業用のメモリの上限 約 6 GB、スワップ 8 GB、CPU 2個)では、PPC=2 は1回目の繰り返しの 70% を過ぎたところ(メモリとスワップの合計 約 12 GB、開始から約 34 分)で、PPC=8 は 10〜20% のところ(約 14 GB、約 32 分)で、メモリ不足で OS に止められました。glibc の `MALLOC_ARENA_MAX=2` でも変わりませんでした。詳細配線から後(`make route final`)は 32 GB 以上の計算機で実行してください。ORFS の手順の名前(`do-5_2_route`、`do-6_report` など)は、使った版の ORFS と同じであることを確かめています。
- `NUM_CORES` を増やすと、配置・詳細配線が速くなります(この環境では 2)。
- 概略配線の後で最も厳しい検査は、リセットの解除(リカバリ)です。リセットは IP の全体の制御の FF に広がるので、リセットの配線のバッファが 1 ns 程度になります(SDC の `B2R_RST_PCT` で外側の割合を決める。仕様書 14.4.3)。

---

## 2. 商用ツールの雛形(`pd/commercial/`、Cadence + Foundry の PDK)

Foundry の PDK と Cadence のツールで流すためのスクリプトです。PDK の中身(ファイル名、セル名、層の名前、電源の作り方)は公開されていないので、`<...>` の項目を記入して使います。**この環境では実行していません。** コマンドとオプションは Stylus Common UI(Genus / Innovus / Tempus)を想定しています。使う版のマニュアルとリファレンスフローで確認してください。

### 2.1 構成

| ファイル | 内容 |
|---|---|
| `setup/foundry_setup.tcl` | ★ PDK のパス、ライブラリ、RC コーナー、解析ビュー、セル名、配線層(記入する) |
| `setup/design_setup.tcl` | 設計の設定(PPC、周期、RTL の並び、出力先) |
| `setup/mmmc.tcl` | MMMC(ライブラリ・RC・ビュー)。Genus / Innovus / Tempus で共通 |
| `genus/syn.tcl` | 論理合成。ネットリスト、配置配線用の SDC、LEC の dofile を出す |
| `innovus/*.tcl` | 配置配線(init → floorplan → place → cts → route → signoff)。段階ごとに db を保存。CTS の後に `update_io_latency` で入出力の仮想クロックの遅れを合わせる [P5] |
| `tempus/sta.tcl` | サインオフの STA(全ビュー、SI、SDF)。Innovus が書き出した SDC(入出力の遅れを合わせたもの)を読む |
| `lec/gate2gate.do` | 合成後と配置配線後のネットリストの等価性検証 |
| `Makefile` | `make syn / lec_rtl / pnr / sta / lec_g2g / drc / lvs` |
| `syn/rtl/foundry/` | ★ SRAM と同期化のラッパ(マクロ名・セル名・端子名を記入する) |

### 2.2 記入する項目

1. `setup/foundry_setup.tcl` の `<...>`: PDK のパス、LEF、Liberty(コーナーごと)、qrcTechFile、ストリームの層の対応表、GDS / CDL、セル名(TIE、フィラー、デカップ、タップ、クロック用のバッファ・インバータ)、配線層の名前。
2. `syn/rtl/foundry/BAYER2RGB_SRAM_1R1W.sv`: メモリコンパイラで作った 2ポート SRAM のマクロ名と端子名(仕様書 12章の大きさ)。
3. `syn/rtl/foundry/BAYER2RGB_SYNC2.sv`: 同期化セルの名前と端子名。同じ名前を `B2R_SYNC2_CELLS` に書く。
4. 電源配線: 作り方はプロセスによって違うので、PDK のリファレンスフローの電源配線のスクリプトを `B2R_PDN_TCL` に指定する。
5. `Makefile` の `LEC_LIBS`、`PEGASUS_DRC_RULES`、`PEGASUS_LVS_RULES`。

雛形のラッパの書き方は、仮のモデル(`syn/rtl/foundry/B2R_FOUNDRY_STUB.sv`)を使って Verilator の lint で確認しています(PPC=8/4/2/1、警告 0)。

### 2.3 使い方

2.2 の記入を済ませてから実行します。こちらは選ぶものではなく、順に流す流れです。

まとめて流す場合:

```sh
cd pd/commercial
make all          # syn → lec_rtl → pnr → sta → lec_g2g を順に
make drc lvs      # 物理検証(Pegasus)
```

段階ごとに流す場合は、次の順に実行します。後の段階を指定すると、終わっていない前の段階から流れます。

| 順 | コマンド | 内容 | 出力 |
|---|---|---|---|
| 1 | `make syn` | 論理合成(Genus) | `out/foundry_ppc8/genus/` |
| 2 | `make lec_rtl` | RTL と合成後の等価性検証(Conformal)。ほかの段階の前提ではない | |
| 3 | `make pnr` | 配置配線(Innovus。init → floorplan → place → cts → route → signoff) | `out/foundry_ppc8/innovus/`(`db/` に段階ごとの db) |
| 4 | `make sta` | サインオフの STA(Tempus) | `out/foundry_ppc8/tempus/reports/` |
| 5 | `make lec_g2g` | 合成後と配置配線後の等価性検証(Conformal) | |
| 6 | `make drc lvs` | 物理検証(Pegasus) | |

配置配線は段階ごとにも流せます(`make init`、`make floorplan` … `make signoff`)。

### 2.4 ASAP7 の環境との対応

| 項目 | ASAP7(OpenROAD) | Foundry の PDK(Cadence) |
|---|---|---|
| SRAM / 同期化のラッパ | `syn/rtl/asap7/`(仮マクロ、FF 2段) | `syn/rtl/foundry/`(コンパイラのマクロ、同期化セル) |
| 制約 | `syn/constraints/bayer2rgb.sdc`(ps / fF) | 同じファイル(ns / pF)→ Genus が数値の SDC を書き出す |
| 入出力の仮想クロックの遅れ | `make io_latency` で測って `asap7/config.mk` に書く | CTS の後に `update_io_latency`(`innovus/cts.tcl`) |
| 論理合成 | Yosys + ABC | Genus |
| 配置配線 | ORFS(RePlAce、TritonCTS、FastRoute、TritonRoute) | Innovus(GigaPlace、CCOpt、NanoRoute) |
| 抽出・STA | OpenRCX + OpenSTA | Quantus + Tempus |
| 等価性検証 | (なし) | Conformal LEC |
| 物理検証 | KLayout(この環境ではなし) | Pegasus |

---

## 参考

| No | 文献 | 使ったところ |
|---|---|---|
| P1 | [OpenROAD-flow-scripts: Flow Variables](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html) | ORFS の変数(`CORE_UTILIZATION`、`PLACE_DENSITY`、`ADDITIONAL_LEFS` など) |
| P2 | [OpenROAD-flow-scripts(GitHub)](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) | 流れの本体、ASAP7 のプラットフォーム |
| P3 | [OpenROAD(GitHub)](https://github.com/The-OpenROAD-Project/OpenROAD) | 配置配線のツール |
| P4 | [ASAP7 PDK(GitHub)](https://github.com/The-OpenROAD-Project/asap7) | ASAP7 の PDK とセルライブラリ |
| P5 | [Cadence Community: Propagated clock for reg2out](https://community.cadence.com/cadence_technology_forums/f/digital-implementation/27219/propagated-clock-for-reg2out) | 入出力の遅延を仮想クロックから測る方法と、CTS の後の update_io_latency |

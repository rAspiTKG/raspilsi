# タイミング制約(`bayer_ex.sdc`)の設定値と意味

`syn/constraints/bayer_ex.sdc` の設定値と、それぞれの意味をまとめたものです。論理合成の後の STA、配置配線、サインオフの STA で同じファイルを使います。対象のトップは `BAYER_EX`(`BAYER_EX_CORE` のインタフェースのポートを平らにしたラッパ)です。

## 1. 全体の考え方

| 項目 | 内容 |
|---|---|
| 書き方 | ポート名とクロック名だけを使う Tcl の SDC。セル名・インスタンス名を使わないので、合成の前後やツールによらず同じファイルを読める |
| 値の単位 | ファイルの中では ns / pF で書き、ライブラリの単位(`BEX_TIME_UNIT`、`BEX_CAP_UNIT`)に合わせて換算する |
| クロック | 2つ。IP のクロック `clk` と、入出力の相手のクロック(仮想クロック `clk_io`) |
| 入出力 | IP の外の FF(仮想クロック)から測る。外の回路が使う時間を周期の割合で決める(既定 50%) |
| 使うところ | `syn/yosys` の合成後の STA(OpenSTA)、`pd/openroad`(OpenROAD)、`pd/commercial`(Genus → Innovus / Tempus) |

`syn/yosys` の合成そのもの(ABC)はこの SDC を読まず、`CLK_PERIOD` の周期だけを目標にします。SDC を読むのは合成後の STA からです。考え方は BAYER2RGB の SDC と同じです。BAYER_EX はクロックが1本なので、クロックの乗せ換えの制約はありません。

## 2. 変数(調整できる値)

| 変数 | 既定値 | 意味 | 使う制約 |
|---|---|---|---|
| `BEX_TIME_UNIT` | `ns` | ライブラリの時間の単位(`ns` か `ps`) | すべての時間の値の換算 |
| `BEX_CAP_UNIT` | `pF` | ライブラリの容量の単位(`pF` か `fF`) | `set_load` の換算 |
| `BEX_CLK_PERIOD` | 2.5 ns | clk の周期(400 MHz) | clk / clk_io の周期、入出力遅延 |
| `BEX_IO_PCT` | 50 % | 入出力(i_vld、i_busy、i_data、i_cfg、o_vld、o_busy、o_data)で、IP の外の回路が使う時間の割合 | 入出力遅延の最大値 |
| `BEX_RST_PCT` | 50 % | リセットの解除で、IP の外(同期化の FF と配線)が使う時間の割合 | rst_n の入力遅延の最大値 |
| `BEX_UNC_SETUP` | 0.10 ns | セットアップの検査で差し引く余裕(クロックのジッタなど) | `set_clock_uncertainty -setup` |
| `BEX_UNC_HOLD` | 0.03 ns | ホールドの検査で足す余裕 | `set_clock_uncertainty -hold` |
| `BEX_CLK_TRAN` | 0.05 ns | クロックツリーを作る前のクロックの遷移時間 | `set_clock_transition` |
| `BEX_IN_TRAN` | 0.05 ns | 入力ポートを駆動する外の回路の遷移時間 | `set_input_transition` |
| `BEX_OUT_LOAD` | 0.005 pF | 出力ポートにつながる外の負荷容量 | `set_load` |
| `BEX_CLK_LATENCY` | 0 ns | clk のクロックツリーの遅れの見込み | clk と clk_io の `set_clock_latency` |

- 変数は、Tcl のグローバル変数 → 環境変数 → 既定値の順に探します。
- 時間の値は、`BEX_TIME_UNIT=ps` のとき 1000 倍します。容量の値は、`BEX_CAP_UNIT=fF` のとき 1000 倍します。
- 入出力・リセットの割合、不確かさ、遷移時間、負荷容量の既定値は、SoC の値が決まるまでの仮の値です(BAYER2RGB と同じ値)。SoC に組み込むときは、SoC 側の値に合わせて直してください。

## 3. クロック

| クロック | 種類 | 定義する所 | 周期(既定) | 波形 | 遅れ(latency) | 不確かさ(セットアップ / ホールド) | 遷移時間 |
|---|---|---|---|---|---|---|---|
| `clk` | IP のクロック | ポート `clk` | 2.5 ns(400 MHz) | 0 ns で立ち上がり、1.25 ns で立ち下がり | `BEX_CLK_LATENCY` | 0.10 / 0.03 ns | 0.05 ns(CTS の前) |
| `clk_io` | 仮想クロック | (ポートなし) | 2.5 ns | 0 ns / 1.25 ns | `BEX_CLK_LATENCY` | 0.10 / 0.03 ns | - |

各項目の意味:

- **周期**(`create_clock -period`): 目標の動作周波数です。BAYER_EX のすべての FF は clk で動きます。
- **仮想クロック**(ポートを指定しない `create_clock`): IP の外で入出力の相手になる FF のクロックです。clk と同じ周期・同じ位相で、入出力の遅延はこのクロックから測ります。
- **遅れ**(`set_clock_latency`): クロックツリーの遅れの見込みを、clk と clk_io の両方に同じ値で与えます。
  - クロックツリーを作る前: 両方の遅れが同じなので、値によらず同じ結果になります。
  - クロックツリーを作った後: IP の中の FF は実際の遅れで計算され、仮想クロックは与えた値のままです(仮想クロックは伝搬しない)。
  - 値を実際の遅れに合わせないと、入出力のホールドとセットアップがその差だけずれます。0 のままだと、入力ポートから FF への経路に不要なホールド用バッファが入ります(ASAP7 の配置配線で 931 個。合わせた後は 3 個。仕様書 9.3)。
- **不確かさ**(`set_clock_uncertainty`): セットアップの検査では 0.10 ns(周期 2.5 ns の 4%)を差し引き、ホールドの検査では 0.03 ns を足します。2つのクロックに同じ値を与えます(受け側のクロックの値が使われるため)。
- **遷移時間**(`set_clock_transition`): クロックツリーを作る前の、理想クロックの遷移時間です。クロックツリーを作った後は、ツールが実際の値を使います。

## 4. 入出力の遅延

| ポートのグループ | 本数 | 基準のクロック | 最大 | 最小 |
|---|---:|---|---|---|
| 入力: `i_vld`、`i_busy`、`i_data[114:0]`、`i_cfg[122:0]` | 240 | `clk_io` | 1.25 ns(周期の 50%。`BEX_IO_PCT`) | 0 |
| 出力: `o_vld`、`o_busy`、`o_data[114:0]` | 117 | `clk_io` | 1.25 ns | 0 |
| `rst_n` | 1 | `clk_io` | 1.25 ns(周期の 50%。`BEX_RST_PCT`) | 0 |

本数はビットの数です。clk を除くすべての入出力に遅延を与えています。i_cfg は準静的(コアが空のときだけ変える)ですが、ほかの入力と同じ制約にしています。IP の中で最初に FF(r_cfg)で受けるので、厳しくはありません。

各項目の意味:

- **入力遅延の最大**(`set_input_delay -max`): 外の FF のクロックから入力ポートに着くまでの時間です。IP の中で使えるのは、周期からこの値と不確かさを引いた残りです。
- **出力遅延の最大**(`set_output_delay -max`): 出力ポートから外の FF に取り込まれるまでに、外の回路が使う時間です(外の FF のセットアップ時間を含む)。
- **最小 0**(`-min 0`): ホールドの検査で、外の回路の遅れを 0 とみなします(最も厳しい見方)。このため、入力ポートの直後の FF には、配置配線でホールド用バッファが入ります(ASAP7 で 239 個。仕様書 9.3)。SoC で外の FF の clk→Q などの最小の遅れがわかれば、`-min` をその値にすると減ります。
- **リセット**: 非同期アサート・同期解除で、解除は IP の外で clk に同期します。入力遅延を与えるのは、解除のタイミング(FF の非同期リセット端子のリカバリ・リムーバル)を検査するためです。BAYER_EX で非同期リセットを使う FF は4個(有効ビット)だけです。

既定値のときに IP の中で使える時間は、次のとおりです(遅れの見込みが実際と合っている場合)。

| 経路 | セットアップ(IP の中で使える時間) | ホールド(IP の中で必要な遅れ) |
|---|---|---|
| 入力ポート → FF | 2.5 − 1.25 − 0.10 = 1.15 ns から、FF のセットアップ時間を引いた値 | 0.03 ns + FF のホールド時間 |
| FF → 出力ポート | FF の clk→Q を含めて 1.15 ns | FF の clk→Q を含めて 0.03 ns |
| rst_n → FF の非同期リセット端子 | 1.15 ns から、リカバリ時間を引いた値 | 0.03 ns + リムーバル時間 |
| FF → FF | 2.5 − 0.10 = 2.4 ns から、FF のセットアップ時間を引いた値 | 0.03 ns + FF のホールド時間 |

```
入力の例(clk、周期 2.5 ns)

  外の FF ──(外の回路: 最大 1.25 ns)──▶ 入力ポート ──(IP の中: 残り)──▶ IP の FF
  │←────────────────────────── 1周期 2.5 ns ───────────────────────────→│
  IP の中で使える時間 = 2.5 − 1.25 − 0.10(不確かさ)− IP の FF のセットアップ時間
```

BAYER_EX は、入力を FF で受け(i_busy だけは全体停止の判定を通る)、出力を FF から直接出しているので、入出力の経路は短く、余裕があります(合成後の STA で入力 → FF +0.80 ns、FF → 出力 +0.85 ns)。

## 5. 入力の遷移時間と出力の負荷

| 制約 | 対象 | 値 | 意味 |
|---|---|---|---|
| `set_input_transition` | clk を除くすべての入力(i_vld、i_busy、i_data、i_cfg、rst_n) | 0.05 ns | 入力ポートを駆動する外の回路の遷移時間。IP の中の最初のセルの遅れの計算に使う |
| `set_load` | すべての出力(o_vld、o_busy、o_data) | 0.005 pF(5 fF) | 出力ポートにつながる外の配線と入力端子の容量。出力を駆動するセルの遅れの計算に使う |

## 6. ASAP7 の環境での値(ps / fF に換算した値)

ASAP7 のライブラリの単位は ps / fF なので、`syn/yosys` と `pd/openroad` は `BEX_TIME_UNIT=ps`、`BEX_CAP_UNIT=fF` を渡しています。

| 項目 | 値 |
|---|---|
| clk / clk_io の周期 | 2500 ps |
| 入出力・rst_n の入出力遅延の最大 | 1250 ps |
| 不確かさ(セットアップ / ホールド) | 100 ps / 30 ps |
| クロックの遷移時間(CTS の前)、入力の遷移時間 | 50 ps |
| 出力の負荷 | 5 fF |
| クロックツリーの遅れの見込み | `syn/yosys`: 0 ps。`pd/openroad`: 135 ps(`pd/openroad/asap7/config.mk`。`make io_latency` で測った値) |

## 7. 値の変え方

使う流れによって、変数の渡し方が違います。使う流れの1つを選んでください。

### 7.1 `syn/yosys`(合成後の STA)

周期は `make` の変数で、それ以外は環境変数で渡します。

```sh
cd syn/yosys
make sta CLK_PERIOD=2.0                  # 周期を変えて STA だけやり直す
BEX_IO_PCT=40 make sta                   # 入出力の割合を変えて STA だけやり直す
```

どちらも合成し直さずに STA だけをやり直します。2行はどちらか一方を使います。周期を変えて合成し直すときは、`syn/README.md` の 2.2 のケース4 を見てください。

### 7.2 `pd/openroad`(配置配線)

周期・単位・クロックツリーの遅れの見込みは `asap7/config.mk` が渡します。それ以外の変数は環境変数で渡します。

```sh
cd pd/openroad
make clean
BEX_IO_PCT=40 make
```

SDC の値はフロアプランの段階で読み込まれ、後の段階に引き継がれます。値を変えたときは、`make clean` してから最初の段階から流してください。

### 7.3 `pd/commercial`(Genus → Innovus / Tempus)

周期と遅れの見込みは `setup/design_setup.tcl`(環境変数 `BEX_CLK_PERIOD`、`BEX_CLK_LATENCY`)、単位は `setup/foundry_setup.tcl` の `BEX_TIME_UNIT` / `BEX_CAP_UNIT` で決めます。それ以外の変数は環境変数で渡します。

```sh
cd pd/commercial
BEX_IO_PCT=40 make syn
```

Genus が数値に展開した SDC(`out/foundry/genus/bayer_ex_genus.sdc`)を、Innovus と Tempus が読みます。値を変えたときは、Genus から流し直してください。クロックツリーの遅れの見込みは、Innovus の CTS の後に `update_io_latency` で合わせます(`innovus/cts.tcl`)。

## 8. 確かめたこと

- 合成後の STA(OpenSTA)で、クロック 2つと、入出力の本数(入力 240、出力 117、rst_n 1。clk を除くすべての入出力)を確かめました(`syn/yosys` の `reports/sta_ports.txt`)。
- 制約のない終点・入出力はありません(`check_setup -verbose` の結果が空。`reports/sta_check_setup.txt`)。
- 環境変数で渡した値が SDC に届くことを確かめました(`BEX_IO_PCT=40` で i_vld の入力遅延と o_busy の出力遅延が 1000 ps、rst_n は `BEX_RST_PCT` のまま 1250 ps)。
- 遅れの見込み(`BEX_CLK_LATENCY`)は、クロックツリーの前の結果を変えません(`BEX_CLK_LATENCY=0.135` でも、clk と clk_io の両方に 135 ps が入り、i_vld からの経路の余裕は同じ)。

## 参考

| No | 文献 | 使ったところ |
|---|---|---|
| C1 | [Microchip: SDC Command Reference](https://onlinedocs.microchip.com/oxy/GUID-6BACC19D-0959-4B51-87AC-AD97B0E07E35-en-US-1/GUID-B2B14577-0560-4C7E-BF7D-A4337D5BD814.html) | create_clock、set_clock_latency、set_clock_uncertainty、set_input_delay、set_output_delay、set_load の意味 |
| C2 | [Cadence Community: Propagated clock for reg2out](https://community.cadence.com/cadence_technology_forums/f/digital-implementation/27219/propagated-clock-for-reg2out) | 入出力の遅延を仮想クロックから測る方法と、CTS の後の update_io_latency |
| C3 | [OpenSTA(GitHub)](https://github.com/parallaxsw/OpenSTA) | この SDC を読む STA(`set_input_transition` などを含む) |

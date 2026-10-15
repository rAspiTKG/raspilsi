# SDC (Synopsys Design Constraints) 構成要素リファレンス
---

## 0. この資料について

### 0.1 対象範囲と根拠

- **対象**: SDC 標準のコマンド (SDC 1.8 仕様書の全コマンド + SDC 1.9〜2.1 の追加分) と、SDC ファイルを構成する記述要素 (版指定・コメント・オブジェクト指定など)。合成スクリプトで頻出する **SDC 標準外** のツール依存コマンドは第 5 章に分離。
- **文法の根拠**: Synopsys「Using the Synopsys Design Constraints Format Application Note」SDC 1.8 版 (公開 PDF) [R1]。1.9〜2.1 の追加・変更は、AMD UG903 の SDC 1.9 対応表 [R3] と、TAP-in 仕様に基づくオープンソース SDC パーサ sdcx のバージョン判定 [R4] で確認。
- **最新版**: SDC 2.2 (2024 年 6 月) の存在を確認 [R2]。ただし 2.2 の差分は公開資料で確認できなかったため、本資料は 2.1 までを基準とする。2.2 の差分は Synopsys TAP-in 経由の仕様書で確認すること。
- **注意**: SDC は各ツールが持つ引数の「サブセット」と定義されている [R1]。`-filter` などは SDC 標準外の拡張 [R3]。最終確認は各ツールの `man <コマンド名>` で行うこと。
- **SDC に含めないもの**: デザインの読み込み・リンク命令は SDC に含めず、SDC 読み込み前に済ませる前提 [R1]。

### 0.2 表記ルール (文法欄)

| 記号 | 意味 |
|---|---|
| `[ ]` | 省略可能 |
| `a \| b` | いずれか一方 |
| `...` | 繰り返し可能 |
| `xxx_list` | オブジェクトのリスト (`get_*` の戻り値や Tcl リスト) |

- 文法欄は仕様書の記法を元に、2.1 までの追加オプションを含めて記載。
- 「SDC版」欄は導入された版。1.8 版仕様書の注記 [R1] と sdcx の判定 [R4] による。
- 設定例の単位は `set_units -time ns -capacitance pF -resistance kOhm -voltage V -current mA -power mW` を前提とする。
- 設定例のセル名・ライブラリ名 (`BUFX4`, `stdcell_ss` など) は説明用の仮名。

### 0.3 分類

| 分類 | 内容 | 仕様書 [R1] の区分 |
|---|---|---|
| 記述要素 | 版指定・コメント・オブジェクト指定などの書き方 | About the SDC Format |
| A. 汎用 | Tcl 基本コマンド、単位・階層区切り | General-Purpose Commands |
| B. オブジェクトアクセス | ポート・ピン・セル・クロック等の取得 | Object Access Commands |
| C. クロック定義 | クロックの生成 | Timing constraints |
| D. クロック特性 | レイテンシ・アンサーテンティ・遷移・極性 | Timing constraints |
| E. クロック間関係 | 非同期・排他クロックの宣言 | Timing constraints |
| F. 理想ネットワーク | 高ファンアウトネットの理想扱い | Timing constraints |
| G. I/O 遅延 | 入出力ポートの外部タイミング | Timing constraints |
| H. 外部環境 | 入力の駆動・出力の負荷 | System interface |
| I. 動作条件・配線モデル | PVT、ワイヤロード、ディレート、電圧 | Operating conditions / Wire load models / Environment |
| J. 設計ルール (DRC) | 遷移・容量・ファンアウトの上限 | Design rule constraints |
| K. モード・定数 | ケース解析、定数、アーク無効化 | Logic assignments / Timing constraints |
| L. タイミング例外 | フォルスパス・マルチサイクル・最大/最小遅延 | Timing exceptions |
| M. 追加チェック | ゲーティング・データ間・パルス幅・タイムボロー | Timing constraints |
| N. パスグループ | 最適化・レポートのグループ分け | Timing constraints |
| O. 面積・電力 | 面積・電力の目標 | Area constraints / Multivoltage and power |
| P. マルチ電圧 | 電圧エリア・レベルシフタ | Multivoltage and power optimization |

### 0.4 設定順 (推奨記述順)

SDC はファイル内の記述順そのものが制約の優先順位を表すわけではない [R1]。順序が本質的に効くのは次の 2 点だけである。

1. **参照先が先に存在すること**: `-clock CLK` や `get_clocks CLK` で参照するクロックは、参照より前に定義されていなければならない (ジェネレーテッドクロックはマスタークロックの後)。
2. **同じ対象への同種設定は後から書いた方で置き換わる**: `-add` / `-add_delay` などの追加指定をしない限り上書きになる (第 4 章)。

そのうえで、読みやすさと依存関係から次の順を推奨する。

| Step | ブロック | 主なコマンド | この位置に置く理由 |
|---|---|---|---|
| 0 | ヘッダ | `set sdc_version`, `set_units`, `set_hierarchy_separator` | 以降の文法・数値・階層名の解釈を決める |
| 1 | スコープ (必要時のみ) | `current_instance` | 相対名で書くブロックの直前に置く |
| 2 | 動作条件・配線モデル | `set_operating_conditions`, `set_wire_load_*`, `set_timing_derate`, `set_voltage`, `set_resistance` | 解析コーナーの前提。他の制約に依存しない |
| 3 | クロック定義 | `create_clock` → `create_generated_clock` | 以降の多くのコマンドがクロックを参照する |
| 4 | クロック特性・理想ネットワーク | `set_clock_latency`, `set_clock_uncertainty`, `set_clock_transition`, `set_propagated_clock`, `set_sense`, `set_ideal_*` | 定義済みクロックに属性を付ける |
| 5 | クロック間関係 | `set_clock_groups` | 全クロックが揃ってから宣言する |
| 6 | I/O 遅延 | `set_input_delay`, `set_output_delay` | `-clock` でクロック (仮想クロック含む) を参照する |
| 7 | 外部環境 | `set_driving_cell`, `set_drive`, `set_input_transition`, `set_load`, `set_fanout_load`, `set_port_fanout_number` | ポートの電気的条件 |
| 8 | 設計ルール | `set_max_transition`, `set_max_capacitance`, `set_max_fanout`, `set_min_capacitance` | ライブラリ値より厳しい上限を与える |
| 9 | モード・定数 | `set_case_analysis`, `set_logic_*`, `set_disable_timing` | どのパスが有効かを決めてから例外を書く |
| 10 | タイミング例外 | `set_false_path`, `set_multicycle_path`, `set_max_delay`, `set_min_delay` | クロック・ポートを参照する。優先順位は種類と具体性で決まる |
| 11 | 追加チェック | `set_clock_gating_check`, `set_data_check`, `set_min_pulse_width`, `set_max_time_borrow` | 個別の検査条件 |
| 12 | パスグループ・最適化目標 | `group_path`, `set_max_area`, `set_max_dynamic_power`, `set_max_leakage_power` | 合成の最適化方針 |
| 13 | マルチ電圧 | `create_voltage_area`, `set_level_shifter_*` | 物理設計寄り。現在は UPF 側で扱うことが多い |
| 随時 | オブジェクトアクセス・Tcl | `get_*`, `all_*`, `current_design`, `set`, `expr`, `list` | 他コマンドの引数内で使う |

---

## 1. 構成要素一覧 (サマリ表)

| No | 構成要素 | 分類 | 設定順 | 意味 (要約) | SDC版 |
|---:|---|---|---|---|---|
| E1 | `sdc_version` 変数 | 記述要素 | Step 0 | ファイルの SDC 版を宣言 | 全版 |
| E2 | コメント `#` | 記述要素 | 随時 | 行頭 `#`、行末は `;` の後に `#` | 全版 |
| E3 | 行継続 `\` | 記述要素 | 随時 | 1 コマンドを複数行に分割 | 全版 |
| E4 | オブジェクト指定 (暗黙/明示) | 記述要素 | 随時 | 名前のみ、または `get_*` で型を明示 | 全版 |
| E5 | ワイルドカード・複数指定 | 記述要素 | 随時 | `*` と `?`、Tcl リスト | 全版 |
| E6 | バス表記 | 記述要素 | 随時 | `{name[3]}` のように `{}` で囲む | 全版 |
| E7 | 階層区切り文字・`-hsc` | 記述要素 | Step 0 | 既定 `/`。名前に `/` を含む場合の回避 | 1.2〜 |
| 1 | `set` | A 汎用 | 随時 | Tcl 変数への代入 | 1.1〜 |
| 2 | `expr` | A 汎用 | 随時 | 算術式の評価 | 1.1〜 |
| 3 | `list` | A 汎用 | 随時 | Tcl リストの生成 | 1.1〜 |
| 4 | `set_units` | A 汎用 | Step 0 | ファイル内の単位を宣言 | 1.7〜 |
| 5 | `set_hierarchy_separator` | A 汎用 | Step 0 | 階層区切り文字を宣言 | 1.2〜 |
| 6 | `current_instance` | A 汎用 | Step 1 | 検索基準インスタンスを変更 | 1.1〜 |
| 7 | `current_design` | B オブジェクト | 随時 | カレントデザインを返す | 1.1〜 |
| 8 | `get_ports` | B オブジェクト | 随時 | ポートを取得 | 1.1〜 |
| 9 | `get_pins` | B オブジェクト | 随時 | ピンを取得 | 1.1〜 |
| 10 | `get_cells` | B オブジェクト | 随時 | セル (インスタンス) を取得 | 1.1〜 |
| 11 | `get_nets` | B オブジェクト | 随時 | ネットを取得 | 1.1〜 |
| 12 | `get_clocks` | B オブジェクト | 随時 | クロックを取得 | 1.1〜 |
| 13 | `get_libs` | B オブジェクト | 随時 | ライブラリを取得 | 1.1〜 |
| 14 | `get_lib_cells` | B オブジェクト | 随時 | ライブラリセルを取得 | 1.1〜 |
| 15 | `get_lib_pins` | B オブジェクト | 随時 | ライブラリセルのピンを取得 | 1.1〜 |
| 16 | `all_inputs` | B オブジェクト | 随時 | 全入力ポート | 1.1〜 |
| 17 | `all_outputs` | B オブジェクト | 随時 | 全出力ポート | 1.1〜 |
| 18 | `all_clocks` | B オブジェクト | 随時 | 全クロック | 1.1〜 |
| 19 | `all_registers` | B オブジェクト | 随時 | 全レジスタ (およびそのピン) | 1.7〜 |
| 20 | `create_clock` | C クロック定義 | Step 3 | クロック (仮想クロック含む) を定義 | 1.1〜 |
| 21 | `create_generated_clock` | C クロック定義 | Step 3 | 分周・逓倍などの派生クロックを定義 | 1.3〜 |
| 22 | `set_clock_latency` | D クロック特性 | Step 4 | ソース/ネットワークレイテンシ | 1.1〜 |
| 23 | `set_clock_uncertainty` | D クロック特性 | Step 4 | ジッタ・スキュー見積りのマージン | 1.1〜 |
| 24 | `set_clock_transition` | D クロック特性 | Step 4 | 理想クロックの遷移時間 | 1.1〜 |
| 25 | `set_propagated_clock` | D クロック特性 | Step 4 | クロックツリーの実遅延で解析 | 1.1〜 |
| 26 | `set_sense` | D クロック特性 | Step 4 | クロック/データの極性伝搬を指定 | 2.1〜 |
| 27 | `set_clock_sense` | D クロック特性 (旧) | Step 4 | `set_sense` の旧形 | 1.7〜2.0 |
| 28 | `set_clock_groups` | E クロック間関係 | Step 5 | 非同期・排他クロックの宣言 | 1.7〜 |
| 29 | `set_ideal_network` | F 理想ネットワーク | Step 4 | 高ファンアウトネットを理想扱い | 1.7〜 |
| 30 | `set_ideal_latency` | F 理想ネットワーク | Step 4 | 理想ネットワークの到着遅延 | 1.7〜 |
| 31 | `set_ideal_transition` | F 理想ネットワーク | Step 4 | 理想ネットワークの遷移時間 | 1.7〜 |
| 32 | `set_input_delay` | G I/O 遅延 | Step 6 | 入力データの外部遅延 | 1.1〜 |
| 33 | `set_output_delay` | G I/O 遅延 | Step 6 | 出力データへの外部要求 | 1.1〜 |
| 34 | `set_driving_cell` | H 外部環境 | Step 7 | 入力を駆動する外部セル | 1.1〜 |
| 35 | `set_drive` | H 外部環境 | Step 7 | 入力の駆動抵抗 | 1.1〜 |
| 36 | `set_input_transition` | H 外部環境 | Step 7 | 入力の遷移時間 | 1.1〜 |
| 37 | `set_load` | H 外部環境 | Step 7 | 外部負荷容量 | 1.1〜 |
| 38 | `set_fanout_load` | H 外部環境 | Step 7 | 外部ファンアウト負荷 | 1.1〜 |
| 39 | `set_port_fanout_number` | H 外部環境 | Step 7 | 外部ファンアウト数 | 1.1〜 |
| 40 | `set_operating_conditions` | I 動作条件 | Step 2 | PVT 動作条件 | 1.1〜 |
| 41 | `set_wire_load_model` | I 動作条件 | Step 2 | ワイヤロードモデル | 1.1〜 |
| 42 | `set_wire_load_mode` | I 動作条件 | Step 2 | 階層をまたぐネットのモデル選択方式 | 1.1〜 |
| 43 | `set_wire_load_selection_group` | I 動作条件 | Step 2 | 面積によるモデル自動選択 | 1.1〜 |
| 44 | `set_wire_load_min_block_size` | I 動作条件 | Step 2 | 自動選択の最小ブロック面積 | 1.1〜 |
| 45 | `set_resistance` | I 動作条件 | Step 2 | ネット抵抗 | 1.1〜 |
| 46 | `set_timing_derate` | I 動作条件 | Step 2 | OCV ディレート係数 | 1.5〜 |
| 47 | `set_voltage` | I 動作条件 | Step 2 | 電源電圧 | 1.8〜 |
| 48 | `set_max_transition` | J 設計ルール | Step 8 | 遷移時間の上限 | 1.1〜 |
| 49 | `set_max_capacitance` | J 設計ルール | Step 8 | 負荷容量の上限 | 1.1〜 |
| 50 | `set_max_fanout` | J 設計ルール | Step 8 | ファンアウトの上限 | 1.1〜 |
| 51 | `set_min_capacitance` | J 設計ルール | Step 8 | 負荷容量の下限 | 1.1〜 |
| 52 | `set_case_analysis` | K モード・定数 | Step 9 | 解析上の定数 (モード指定) | 1.1〜 |
| 53 | `set_logic_zero` | K モード・定数 | Step 9 | 入力ポートを 0 に固定 | 1.1〜 |
| 54 | `set_logic_one` | K モード・定数 | Step 9 | 入力ポートを 1 に固定 | 1.1〜 |
| 55 | `set_logic_dc` | K モード・定数 | Step 9 | 入力ポートを don't care に | 1.1〜 |
| 56 | `set_disable_timing` | K モード・定数 | Step 9 | タイミングアークの無効化 | 1.1〜 |
| 57 | `set_false_path` | L タイミング例外 | Step 10 | 解析対象外のパス | 1.1〜 |
| 58 | `set_multicycle_path` | L タイミング例外 | Step 10 | 複数サイクルを許すパス | 1.1〜 |
| 59 | `set_max_delay` | L タイミング例外 | Step 10 | 最大遅延の直接指定 | 1.1〜 |
| 60 | `set_min_delay` | L タイミング例外 | Step 10 | 最小遅延の直接指定 | 1.1〜 |
| 61 | `set_clock_gating_check` | M 追加チェック | Step 11 | クロックゲーティングの検査 | 1.2〜 |
| 62 | `set_data_check` | M 追加チェック | Step 11 | データ信号間の検査 | 1.4〜 |
| 63 | `set_min_pulse_width` | M 追加チェック | Step 11 | 最小パルス幅の検査 | 2.0〜 |
| 64 | `set_max_time_borrow` | M 追加チェック | Step 11 | ラッチのタイムボロー上限 | 1.1〜 |
| 65 | `group_path` | N パスグループ | Step 12 | パスのグループ分けと重み | 1.7〜 |
| 66 | `set_max_area` | O 面積・電力 | Step 12 | 面積目標 | 1.1〜 |
| 67 | `set_max_dynamic_power` | O 面積・電力 | Step 12 | 動的電力目標 | 1.4〜 |
| 68 | `set_max_leakage_power` | O 面積・電力 | Step 12 | リーク電力目標 | 1.4〜 |
| 69 | `create_voltage_area` | P マルチ電圧 | Step 13 | 電圧エリアの定義 | 1.6〜 |
| 70 | `set_level_shifter_strategy` | P マルチ電圧 | Step 13 | レベルシフタ挿入方針 | 1.6〜 |
| 71 | `set_level_shifter_threshold` | P マルチ電圧 | Step 13 | レベルシフタ要否のしきい値 | 1.6〜 |

---

## 2. SDC ファイルの記述要素 (コマンド以外)

SDC は Tcl ベースの形式で、全コマンドが Tcl の構文規則に従う [R1]。SDC ファイルの中身は「版 (任意)・単位 (任意)・設計制約・コメント (任意)」で構成される [R1]。

### E1. SDC バージョン指定 (`sdc_version` 変数)

- **分類**: 記述要素 (ヘッダ)
- **設定順**: Step 0 (ファイルの最初のコマンド)
- **SDC版**: 全版
- **意味**: ファイルがどの版の SDC 文法で書かれているかを宣言する。読み込み側は `read_sdc -version` 指定 → `sdc_version` 変数 → ツール既定値 の優先順で版を決める [R1]。未指定時に仮定される版はツール依存なので、互換性のため明記する [R1]。

**文法**

```text
set sdc_version version
```

**設定例**

```tcl
set sdc_version 2.1
```

**設定例の意味**

- このファイルは SDC 2.1 の文法で記述されている。2.1 で追加された `set_sense` や `-ignore_clock_latency` が正しく解釈される。

### E2. コメント

- **分類**: 記述要素
- **設定順**: 随時
- **SDC版**: 全版
- **意味**: `#` で始まる行はコメント。コマンドの後ろにコメントを書く場合は、コマンドを `;` で終えてから `#` を書く [R1] (Tcl ではコマンド先頭位置の `#` だけがコメントになるため)。

**文法**

```text
# comment
command arguments ; # comment
```

**設定例**

```tcl
# core clock: 500 MHz
create_clock -name CLK_CORE -period 2.0 [get_ports clk_core] ; # from PLL0
```

**設定例の意味**

- 1 行目は行コメント、2 行目はコマンドの後ろに付けたコメント。
- 実ファイルのコメントは ASCII (英語) にしておくと、文字コードの扱いが異なるツール間でも安全。

### E3. 行継続

- **分類**: 記述要素
- **設定順**: 随時
- **SDC版**: 全版
- **意味**: 行末の `\` で 1 つのコマンドを複数行に分割できる [R1]。`\` は行の最後の文字にする (後ろに空白を置かない)。

**文法**

```text
command part1 \
  part2 \
  part3
```

**設定例**

```tcl
set_multicycle_path 2 -setup \
  -from [get_clocks CLK_CORE] \
  -to [get_clocks CLK_DIV2]
```

**設定例の意味**

- 3 行で 1 つの `set_multicycle_path` コマンドになる。

### E4. オブジェクト指定 (暗黙指定と明示指定)

- **分類**: 記述要素
- **設定順**: 随時
- **SDC版**: 全版
- **意味**: 名前だけを書く「暗黙指定」では、ツールがコマンドごとに決まった優先順で型 (ポート・ピン・セル・クロック等) を探す。曖昧さを避けるには `get_*` で型を明示する [R1]。

**文法**

```text
object_name
[get_ports | get_pins | get_cells | get_nets | get_clocks ... patterns]
```

**設定例**

```tcl
set_false_path -from U1
set_false_path -from [get_cells U1]
```

**設定例の意味**

- 1 行目: `U1` をどの型として解釈するかはツールの検索順に依存する。
- 2 行目: `U1` をセルとして明示する。可搬性のためこちらを推奨。

### E5. ワイルドカードと複数指定

- **分類**: 記述要素
- **設定順**: 随時
- **SDC版**: 全版
- **意味**: `*` は 0 文字以上、`?` は 1 文字に一致 [R1]。複数オブジェクトは Tcl リストで渡す。SDC 1.5 以降、`get_*` でパターンを省略すると `*` を指定したのと同じ扱い [R1]。

**文法**

```text
get_ports {pattern1 pattern2 ...}
get_ports [list name1 name2 ...]
```

**設定例**

```tcl
set_input_delay -clock CLK_CORE -max 1.2 [get_ports {din* sel?}]
set_load 0.02 [get_ports [list dout0 dout1]]
```

**設定例の意味**

- 1 行目: `din` で始まる全ポートと、`sel` + 1 文字のポートに max 入力遅延 1.2 ns。
- 2 行目: `dout0` と `dout1` に 0.02 pF の負荷。

### E6. バス表記

- **分類**: 記述要素
- **設定順**: 随時
- **SDC版**: 全版
- **意味**: バスは Verilog 形式の `name[index]` で書き、`{}` で囲む [R1]。囲まないと Tcl が `[ ]` をコマンド置換として解釈してエラーになる。

**文法**

```text
{bus_name[index]}
{bus_name[*]}
```

**設定例**

```tcl
set_input_delay -clock CLK_CORE -max 1.2 [get_ports {data_in[0]}]
set_input_delay -clock CLK_CORE -max 1.2 [get_ports {data_in[*]}]
```

**設定例の意味**

- 1 行目: バス `data_in` のビット 0 だけ。
- 2 行目: バス `data_in` の全ビット。
- `[get_ports data_in[0]]` と書くと `0` というコマンドを実行しようとして失敗する。

### E7. 階層区切り文字と `-hsc`

- **分類**: 記述要素
- **設定順**: Step 0
- **SDC版**: 1.2〜 (`set_hierarchy_separator` と `-hsc`)
- **意味**: 階層の区切りは既定で `/`。SDC で使える区切り文字は `/ @ ^ # . |` [R1]。オブジェクト名自体に `/` が含まれる場合に、ファイル全体 (`set_hierarchy_separator`) またはコマンド単位 (`-hsc`) で別の文字を使う。優先順は `-hsc` → `set_hierarchy_separator` → 既定 `/` [R1]。

**文法**

```text
get_pins -hsc separator patterns
set_hierarchy_separator separator
```

**設定例**

```tcl
set_false_path -to [get_pins -hsc @ {U1/U2@A}]
```

**設定例の意味**

- 名前に `/` を含むセル `U1/U2` のピン `A` を指定する。`@` が階層区切り、`/` は名前の一部として扱われる (仕様書の例 [R1] と同じ形)。

---

## 3. SDC 標準コマンド詳細

各コマンドを「分類 / 設定順 / SDC版 / 意味 / 文法 / 設定例 / 設定例の意味」の順に記載する。文法の根拠は [R1] (1.8 版)、1.9 以降の追加は [R3][R4]。

### 3.A 汎用コマンド (General-Purpose)

#### 1. set

- **分類**: A. 汎用 (Tcl 組み込み)
- **設定順**: 随時 (参照より前に定義)
- **SDC版**: 1.1〜
- **意味**: Tcl 変数に値を代入する。`sdc_version` の宣言にも使う。周期やマージンを変数にしておくと、変更時の修正漏れを防げる。

**文法**

```text
set variable_name value
```

**設定例**

```tcl
set CORE_PERIOD 2.0
create_clock -name CLK_CORE -period $CORE_PERIOD [get_ports clk_core]
```

**設定例の意味**

- 変数 `CORE_PERIOD` に 2.0 を代入し、`create_clock` の周期として参照する。
- ツールが書き出す SDC (`write_sdc`) は制約値そのものを展開して出力するため、変数名は残らない。

#### 2. expr

- **分類**: A. 汎用 (Tcl 組み込み)
- **設定順**: 随時
- **SDC版**: 1.1〜
- **意味**: Tcl の算術式を評価する。周期の割合から I/O 遅延を計算する、などに使う。式は `{}` で囲むのが Tcl の作法 (二重評価を防ぐ)。

**文法**

```text
expr arg1 arg2 ... argn
```

**設定例**

```tcl
set_input_delay -clock CLK_CORE -max [expr {$CORE_PERIOD * 0.6}] [get_ports {din[*]}]
```

**設定例の意味**

- 周期 2.0 ns の 60 % = 1.2 ns を、バス `din` の max 入力遅延として設定する。

#### 3. list

- **分類**: A. 汎用 (Tcl 組み込み)
- **設定順**: 随時
- **SDC版**: 1.1〜
- **意味**: Tcl リストを作る。複数のクロック名・ポート名をまとめて渡すときに使う。

**文法**

```text
list arg1 arg2 ... argn
```

**設定例**

```tcl
set_clock_groups -asynchronous -group [list CLK_CORE CLK_DIV2] -group [list CLK_APB]
```

**設定例の意味**

- `CLK_CORE` と `CLK_DIV2` を 1 グループ、`CLK_APB` を別グループとし、グループ間を非同期 (解析対象外) にする。

#### 4. set_units

- **分類**: A. 汎用 (ヘッダ)
- **設定順**: Step 0
- **SDC版**: 1.7〜
- **意味**: SDC ファイル内の数値の単位 (容量・抵抗・時間・電圧・電流・電力) を宣言する [R1]。ツールによっては単位を変更できない (例: Vivado では `-time` で時間単位を変えられない [R3])。Synopsys ツールの `write_sdc` は、メインライブラリの単位を `set_units` として書き出す [R1]。ライブラリ (.lib) の単位と一致させて書くのが安全。

**文法**

```text
set_units [-capacitance cap_unit] [-resistance res_unit] [-time time_unit]
  [-voltage voltage_unit] [-current current_unit] [-power power_unit]
```

**設定例**

```tcl
set_units -time ns -capacitance pF -resistance kOhm -voltage V -current mA -power mW
```

**設定例の意味**

- 以降の数値を ns / pF / kΩ / V / mA / mW として解釈する。

#### 5. set_hierarchy_separator

- **分類**: A. 汎用 (ヘッダ)
- **設定順**: Step 0 (階層名を使うコマンドより前)
- **SDC版**: 1.2〜
- **意味**: このファイルで使う階層区切り文字を宣言する。既定は `/`、使える文字は `/ @ ^ # . |` [R1]。

**文法**

```text
set_hierarchy_separator separator
```

**設定例**

```tcl
set_hierarchy_separator .
set_false_path -to [get_pins {u_core.u_sync.ff1_reg.D}]
```

**設定例の意味**

- このファイルでは `.` を階層区切りとして扱う。2 行目は `u_core/u_sync/ff1_reg/D` を指定したのと同じ。

#### 6. current_instance

- **分類**: A. 汎用 (スコープ)
- **設定順**: Step 1 (相対名で書くブロックの直前)
- **SDC版**: 1.1〜
- **意味**: オブジェクト指定の基準となるインスタンスを変更する。既定の基準はトップレベル [R1]。

**文法**

```text
current_instance [instance]
```

**設定例**

```tcl
current_instance u_core
set_false_path -to [get_pins u_sync/ff1_reg/D]
current_instance
```

**設定例の意味**

- 1 行目: 基準を `u_core` に移す。
- 2 行目: `u_core/u_sync/ff1_reg/D` を相対名で指定する。
- 3 行目: 引数なしでトップに戻す (Synopsys ツールの挙動。他ツールは要確認)。
- ツールが書き出す SDC は常にトップからのフル階層名になる [R1]。

### 3.B オブジェクトアクセス (Object Access)

共通の注意 (7〜19):

- SDC が定めるのは各ツールの構文のサブセット [R1]。`-filter` などは標準外 [R3]。
- 設定順は「随時」。他のコマンドの引数として `[ ]` で埋め込んで使う。
- 設計オブジェクトの種類: design / clock / port / cell / pin / net / library / lib_cell / lib_pin / register [R1]。

#### 7. current_design

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜
- **意味**: カレントデザイン (トップ) のオブジェクトを返す。SDC 標準では引数を取らない [R1][R4]。デザイン全体を対象にする制約で使う。

**文法**

```text
current_design
```

**設定例**

```tcl
set_max_fanout 32 [current_design]
```

**設定例の意味**

- デザイン全体の最大ファンアウトを 32 に制限する。
- `current_design soc_top` のようにデザインを切り替える書き方はツールスクリプト側のコマンドで、SDC 標準の引数ではない (第 5 章)。

#### 8. get_ports

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜 (`-regexp` / `-nocase` は 1.5〜)
- **意味**: パターンに一致するポート (トップの入出力端子) を返す。

**文法**

```text
get_ports [-regexp] [-nocase] [patterns]
```

**設定例**

```tcl
set_input_delay -clock CLK_CORE -max 1.2 [get_ports {din[*] valid_in}]
set_output_delay -clock CLK_CORE -max 0.9 [get_ports -regexp {dout_[0-9]+}]
```

**設定例の意味**

- 1 行目: バス `din` の全ビットと `valid_in` に max 入力遅延 1.2 ns。
- 2 行目: 正規表現で `dout_0`, `dout_15` などに一致するポートに max 出力遅延 0.9 ns。

#### 9. get_pins

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜 (`-hsc` 1.2〜、`-regexp` / `-nocase` 1.5〜)
- **意味**: セルのピン (階層ピン含む) を返す。名前は「セルのパス + 区切り + ピン名」。

**主なオプション**

- `-hierarchical`: 全階層を検索する。
- `-of_objects`: 指定したセルやネットに属するピンを返す。
- `-hsc`: このコマンド内だけの階層区切り文字。

**文法**

```text
get_pins [-hierarchical] [-hsc separator] [-regexp] [-nocase]
  [-of_objects objects] [patterns]
```

**設定例**

```tcl
set_false_path -to [get_pins u_core/u_sync/sync_ff1_reg/D]
set_case_analysis 0 [get_pins -of_objects [get_nets u_crg/clk_sel]]
```

**設定例の意味**

- 1 行目: 同期化 FF 1 段目の D ピンへのパスをフォルスパスにする。
- 2 行目: ネット `u_crg/clk_sel` に接続する全ピンを定数 0 として解析する。

#### 10. get_cells

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜 (`-hsc` 1.2〜、`-regexp` / `-nocase` 1.5〜)
- **意味**: セル (インスタンス) を返す。合成後のレジスタ名は既定で `信号名_reg` 形式になることが多い。

**文法**

```text
get_cells [-hierarchical] [-hsc separator] [-regexp] [-nocase]
  [-of_objects objects] [patterns]
```

**設定例**

```tcl
set_false_path -to [get_cells -hierarchical *sync_ff1_reg]
```

**設定例の意味**

- 全階層から名前が `sync_ff1_reg` で終わるセル (同期化 FF の 1 段目) を探し、そこへのパスをフォルスパスにする。セルを `-to` に指定すると、そのセルのデータ入力が終点として扱われる。

#### 11. get_nets

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜 (`-hsc` 1.2〜、`-regexp` / `-nocase` / `-of_objects` 1.5〜)
- **意味**: ネットを返す。

**文法**

```text
get_nets [-hierarchical] [-hsc separator] [-regexp] [-nocase]
  [-of_objects objects] [patterns]
```

**設定例**

```tcl
set_ideal_network -no_propagate [get_nets u_core/scan_en_int]
```

**設定例の意味**

- ネット `u_core/scan_en_int` を理想ネットワークとして扱う (セルの先へは伝搬させない)。

#### 12. get_clocks

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時 (参照するクロックの定義より後)
- **SDC版**: 1.1〜 (`-regexp` / `-nocase` 1.5〜)
- **意味**: 定義済みのクロック (ジェネレーテッドクロック含む) を返す [R1]。

**文法**

```text
get_clocks [-regexp] [-nocase] [patterns]
```

**設定例**

```tcl
set_clock_uncertainty -setup 0.15 [get_clocks CLK_*]
```

**設定例の意味**

- 名前が `CLK_` で始まる全クロックに、setup 用アンサーテンティ 0.15 ns を設定する。

#### 13. get_libs

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜 (`-regexp` / `-nocase` 1.5〜)
- **意味**: 読み込み済みのライブラリを返す。

**文法**

```text
get_libs [-regexp] [-nocase] [patterns]
```

**設定例**

```tcl
set_wire_load_model -name wl_10k -library [get_libs stdcell_ss]
```

**設定例の意味**

- ライブラリ `stdcell_ss` に定義されたワイヤロードモデル `wl_10k` を使う。

#### 14. get_lib_cells

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜 (`-hsc` 1.2〜、`-regexp` / `-nocase` 1.5〜)
- **意味**: ライブラリセルを「ライブラリ名/セル名」の形で返す。標準 SDC 内での用途は限られ、合成スクリプトでは使用禁止セルの指定 (`set_dont_use`、標準外) によく使う。

**文法**

```text
get_lib_cells [-hsc separator] [-regexp] [-nocase] patterns
```

**設定例**

```tcl
get_lib_cells stdcell_ss/BUFX*
```

**設定例の意味**

- ライブラリ `stdcell_ss` 内の `BUFX` で始まるセル (BUFX1, BUFX4 など) を返す。

#### 15. get_lib_pins

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜 (`-hsc` 1.2〜、`-regexp` / `-nocase` 1.5〜)
- **意味**: ライブラリセルのピンを「ライブラリ名/セル名/ピン名」の形で返す。

**文法**

```text
get_lib_pins [-hsc separator] [-regexp] [-nocase] patterns
```

**設定例**

```tcl
get_lib_pins stdcell_ss/INVX1/A
```

**設定例の意味**

- ライブラリ `stdcell_ss` の `INVX1` セルの入力ピン `A` を返す。DC ではこれを `load_of` (標準外) に渡して負荷容量を求める書き方が多い (第 5 章)。

#### 16. all_inputs

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜
- **意味**: 全入力ポート (双方向含む) を返す。`-clock` を付けると、そのクロック基準の入力遅延が設定されたポートに絞り込む。クロックポートも含まれる点に注意。

**文法**

```text
all_inputs [-level_sensitive] [-edge_triggered] [-clock clock_name]
```

**設定例**

```tcl
set_driving_cell -lib_cell BUFX4 -library stdcell_ss -pin Y [all_inputs]
```

**設定例の意味**

- 全入力ポートが `BUFX4` の出力 `Y` で駆動されているとみなす。

#### 17. all_outputs

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.1〜
- **意味**: 全出力ポート (双方向含む) を返す。

**文法**

```text
all_outputs [-level_sensitive] [-edge_triggered] [-clock clock_name]
```

**設定例**

```tcl
set_load 0.05 [all_outputs]
```

**設定例の意味**

- 全出力ポートに 0.05 pF の外部負荷を設定する。

#### 18. all_clocks

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時 (クロック定義の後)
- **SDC版**: 1.1〜
- **意味**: 定義済みの全クロックを返す。

**文法**

```text
all_clocks
```

**設定例**

```tcl
set_clock_transition 0.08 [all_clocks]
```

**設定例の意味**

- 全クロックの (理想クロックとしての) 遷移時間を 0.08 ns にする。

#### 19. all_registers

- **分類**: B. オブジェクトアクセス
- **設定順**: 随時
- **SDC版**: 1.7〜 (1.8 版仕様書では「`read_sdc` のみ対応」と注記 [R1])
- **意味**: 全レジスタ (順序セル) またはそのピンを返す。クロックや種類で絞り込める。

**主なオプション**

- `-clock` / `-rise_clock` / `-fall_clock`: 指定クロックで動くレジスタ。
- `-cells` / `-data_pins` / `-clock_pins` / `-async_pins` / `-output_pins` / `-slave_clock_pins`: 返すオブジェクトの種類。
- `-level_sensitive` / `-edge_triggered` / `-master_slave`: ラッチ・FF などの種類。

**文法**

```text
all_registers [-no_hierarchy] [-clock clock_name]
  [-rise_clock clock_name] [-fall_clock clock_name]
  [-cells] [-data_pins] [-clock_pins] [-slave_clock_pins]
  [-async_pins] [-output_pins]
  [-level_sensitive] [-edge_triggered] [-master_slave]
```

**設定例**

```tcl
group_path -name REG2REG -from [all_registers] -to [all_registers]
set_max_delay 1.0 -from [all_registers -clock CLK_DIV2] -to [all_outputs]
```

**設定例の意味**

- 1 行目: レジスタ間パスを `REG2REG` グループにまとめる。
- 2 行目: `CLK_DIV2` で動くレジスタから出力ポートまでを 1.0 ns 以内にする。

### 3.C クロック定義

#### 20. create_clock

- **分類**: C. クロック定義 (仕様書区分: Timing constraints)
- **設定順**: Step 3 (クロックを参照する全コマンドより前)
- **SDC版**: 1.1〜 (`-add` 1.4〜、`-comment` 1.9〜)
- **意味**: ポートまたはピンをクロック源として、周期と波形を持つクロックを定義する。ソースを指定しないと、実体のない「仮想クロック」になり、I/O 遅延の基準として使える。

**主なオプション**

- `-period`: 周期 (必須)。
- `-waveform {t_rise t_fall ...}`: 1 周期内のエッジ時刻。省略時は 0 で立ち上がり、周期の半分で立ち下がる (デューティ 50 %)。
- `-name`: クロック名。省略時はソースオブジェクト名になる。仮想クロックでは必須。
- `-add`: 既にクロックがあるソースに、別のクロックを追加で定義する (Vivado の説明でも「既存クロックに追加」[R12])。付けない場合は既存定義の置き換えになるのが一般的な挙動。
- `-comment` (1.9〜): 制約に付けるコメント文字列。

**文法**

```text
create_clock -period period_value [-name clock_name] [-waveform edge_list]
  [-add] [-comment comment_string] [source_objects]
```

**設定例**

```tcl
create_clock -name CLK_CORE -period 2.0 -waveform {0 1.0} [get_ports clk_core]
create_clock -name CLK_APB -period 10.0 [get_ports clk_apb]
create_clock -name VCLK_IO -period 2.0
create_clock -name CLK_TEST -period 20.0 -add [get_ports clk_core]
```

**設定例の意味**

- 1 行目: ポート `clk_core` に 500 MHz (2.0 ns、0 ns で立ち上がり 1.0 ns で立ち下がり) のクロック `CLK_CORE` を定義。
- 2 行目: ポート `clk_apb` に 100 MHz のクロック `CLK_APB` (波形は既定の 50 %)。
- 3 行目: ソースなしの仮想クロック `VCLK_IO`。外部デバイスとの I/O 遅延の基準に使う。
- 4 行目: 同じ `clk_core` ポートにテスト用の 50 MHz クロックを追加。機能用と同時には存在しないため、`set_clock_groups -physically_exclusive` などとセットで使う。

#### 21. create_generated_clock

- **分類**: C. クロック定義 (仕様書区分: Timing constraints)
- **設定順**: Step 3 (マスタークロックの定義の後)
- **SDC版**: 1.3〜 (`-add` / `-master_clock` 1.4〜、`-combinational` 1.7〜、`-comment` 1.9〜)
- **意味**: 既存クロック (マスター) から分周・逓倍・反転などで作られるクロックを定義する。マスターとの位相関係が保たれるため、マスターとの間のパスは同期パスとして解析される。

**主なオプション**

- `-source`: マスタークロックが到達するポート/ピン (必須)。
- `-divide_by` / `-multiply_by`: 分周比・逓倍比。
- `-duty_cycle`: デューティ比 (%)。`-multiply_by` と組み合わせて使う。
- `-edges {e1 e2 e3}`: マスタークロックのエッジ番号 (1 始まり。1 = 最初の立ち上がり、2 = 最初の立ち下がり …) で波形を指定。
- `-edge_shift {s1 s2 s3}`: `-edges` の各エッジをずらす時間。
- `-invert`: 反転したクロック。
- `-master_clock`: `-source` に複数クロックが届く場合に、どれをマスターにするか (`-add` と併用)。
- `-combinational`: マスターから組合せ論理だけを通って到達するクロックとして扱う。

**文法**

```text
create_generated_clock [-name clock_name] -source master_pin
  [-edges edge_list] [-divide_by factor] [-multiply_by factor]
  [-duty_cycle percent] [-invert] [-edge_shift shift_list]
  [-add] [-master_clock clock] [-combinational]
  [-comment comment_string] source_objects
```

**設定例**

```tcl
create_generated_clock -name CLK_DIV2 -source [get_ports clk_core] -divide_by 2 [get_pins u_crg/div2_reg/Q]
create_generated_clock -name CLK_DIV3 -source [get_ports clk_core] -edges {1 3 7} [get_pins u_crg/div3_reg/Q]
```

**設定例の意味**

- 1 行目: `clk_core` を 2 分周した 250 MHz のクロック `CLK_DIV2` を、分周 FF の出力 `Q` に定義。
- 2 行目: マスターのエッジ 1 で立ち上がり、エッジ 3 で立ち下がり、エッジ 7 で次の立ち上がり、つまり周期 = マスター 3 周期、High 幅 = マスター 1 周期の 3 分周クロック `CLK_DIV3`。
- 分周 FF の出力にクロックを定義しないと、ツールはその先をクロックとして扱えず、分周クロックで動く FF が未制約になる。

### 3.D クロック特性

#### 22. set_clock_latency

- **分類**: D. クロック特性 (仕様書区分: Timing constraints)
- **設定順**: Step 4
- **SDC版**: 1.1〜 (`-early` / `-late` 1.2〜、`-clock` 1.5〜、`-dynamic` 2.1〜)
- **意味**: クロックの到着遅延 (レイテンシ) を指定する。
  - **ソースレイテンシ** (`-source`): クロック源 (チップ外の発振器や PLL) からクロック定義点までの遅延。
  - **ネットワークレイテンシ** (`-source` なし): クロック定義点から FF のクロックピンまでの遅延 = CTS で作られるクロックツリー遅延の見積り。

**主なオプション**

- `-source`: ソースレイテンシとして設定。
- `-early` / `-late`: ソースレイテンシの早い値 / 遅い値 (OCV 解析用)。
- `-min` / `-max`: hold 解析用 / setup 解析用の値。
- `-rise` / `-fall`: エッジ別の値。
- `-clock`: ポート/ピンに設定するとき、対象クロックを限定する。
- `-dynamic` (2.1〜): 2.1 で追加されたオプション。意味と使い方はツールのマニュアルで確認すること。

**文法**

```text
set_clock_latency [-rise] [-fall] [-min] [-max] [-source] [-dynamic]
  [-late] [-early] [-clock clock_list] delay object_list
```

**設定例**

```tcl
set_clock_latency -source -early 0.20 [get_clocks CLK_CORE]
set_clock_latency -source -late 0.30 [get_clocks CLK_CORE]
set_clock_latency 0.50 [get_clocks CLK_CORE]
```

**設定例の意味**

- 1〜2 行目: チップ外 (クロック源から `clk_core` ポートまで) の遅延を、早い側 0.20 ns・遅い側 0.30 ns とする。
- 3 行目: CTS 後に想定されるクロックツリー遅延を 0.50 ns とし、理想クロックの到着時刻に加える。
- 同一クロック内のレジスタ間パスでは送り側・受け側に同じ値が加わるため相殺される。I/O 遅延の基準をレイテンシ未設定の仮想クロックにしている場合は相殺されないため、入力パスは捕捉が遅れて余裕が増え、出力パスは送出が遅れて余裕が減る。
- 伝搬クロック (`set_propagated_clock`) にすると、ネットワークレイテンシは実際のクロックツリー遅延で置き換わる。ソースレイテンシは引き続き加算される。

#### 23. set_clock_uncertainty

- **分類**: D. クロック特性 (仕様書区分: Timing constraints)
- **設定順**: Step 4
- **SDC版**: 1.1〜 (`-rise_from` などエッジ別の指定は 1.5〜)
- **意味**: ジッタやスキューを見込んだマージン。setup 解析では要求時刻から差し引き、hold 解析では要求に加える (どちらも厳しくなる)。
  - **単一クロック** (object_list 指定): そのクロックで捕捉するパスに適用。
  - **クロック間** (`-from` / `-to`): 2 つのクロック間のパスにだけ適用。

**文法**

```text
set_clock_uncertainty
  [-from from_clock | -rise_from rise_from_clock | -fall_from fall_from_clock]
  [-to to_clock | -rise_to rise_to_clock | -fall_to fall_to_clock]
  [-rise] [-fall] [-setup] [-hold] uncertainty [object_list]
```

**設定例**

```tcl
set_clock_uncertainty -setup 0.15 [get_clocks CLK_CORE]
set_clock_uncertainty -hold 0.05 [get_clocks CLK_CORE]
set_clock_uncertainty -from [get_clocks CLK_CORE] -to [get_clocks CLK_DIV2] -setup 0.20
```

**設定例の意味**

- 1 行目: setup 解析で 0.15 ns のマージン (ジッタ + CTS 前なのでスキュー見積りも含める)。
- 2 行目: hold 解析で 0.05 ns のマージン。
- 3 行目: `CLK_CORE` から `CLK_DIV2` へのパスの setup にだけ 0.20 ns。
- 合成 (CTS 前) ではスキュー見積りを含めて大きめにし、CTS 後は実スキューが計算されるのでジッタ分中心に減らすのが通例。

#### 24. set_clock_transition

- **分類**: D. クロック特性 (仕様書区分: Timing constraints)
- **設定順**: Step 4
- **SDC版**: 1.1〜
- **意味**: 理想クロックが FF のクロックピンに到着するときの遷移時間 (スルー)。FF の遅延やセットアップ/ホールド値の計算に使われる。伝搬クロックでは実際の遷移時間が使われるため効かない。

**文法**

```text
set_clock_transition [-rise] [-fall] [-min] [-max] transition clock_list
```

**設定例**

```tcl
set_clock_transition 0.08 [get_clocks CLK_CORE]
```

**設定例の意味**

- `CLK_CORE` のクロックピンでの遷移時間を 0.08 ns とみなす (CTS 後の品質を想定した値)。

#### 25. set_propagated_clock

- **分類**: D. クロック特性 (仕様書区分: Timing constraints)
- **設定順**: Step 4
- **SDC版**: 1.1〜
- **意味**: クロックを「伝搬クロック」にし、クロックツリーの実遅延・実遷移で解析する。CTS 前の論理合成では通常使わず (理想クロック)、CTS 後の SDC で使う [R17]。

**文法**

```text
set_propagated_clock object_list
```

**設定例**

```tcl
set_propagated_clock [all_clocks]
```

**設定例の意味**

- 全クロックを伝搬クロックにする (CTS 後のタイミング解析用)。

#### 26. set_sense

- **分類**: D. クロック特性 (SDC 2.1 で追加)
- **設定順**: Step 4
- **SDC版**: 2.1〜 (旧 `set_clock_sense` を置き換え [R4])
- **意味**: ピンでのクロック (またはデータ) の極性伝搬を指定する。XOR などで極性 (ユネイト性) が決まらない点で正/負を決めたり、指定ピンから先へのクロック伝搬を止めたりする。

**主なオプション**

- `-positive` / `-negative`: 正ユネイト (非反転) / 負ユネイト (反転) として伝搬させる。
- `-stop_propagation`: 指定ピンから先へ伝搬させない。
- `-pulse pulse_type`: パルスクロックの種類 (例: `rise_triggered_high_pulse`)。
- `-type clock | data`: クロックとデータのどちらの伝搬に適用するか。
- `-non_unate` / `-clock_leaf`: 非ユネイトとして扱う / クロックの終端として扱う。
- `-clocks`: 対象クロックを限定する。
- `-positive` `-negative` `-pulse` `-stop_propagation` は同時に指定しない。

**文法**

```text
set_sense [-type clock | data] [-non_unate] [-positive] [-negative]
  [-clock_leaf] [-stop_propagation] [-pulse pulse_type]
  [-clocks clock_list] pin_list
```

**設定例**

```tcl
set_sense -type clock -stop_propagation -clocks [get_clocks CLK_CORE] [get_pins u_crg/u_obs_buf/Y]
set_sense -type clock -positive [get_pins u_crg/u_clk_xor/Y]
```

**設定例の意味**

- 1 行目: 観測用バッファ `u_obs_buf` の出力から先へ `CLK_CORE` を伝搬させない。
- 2 行目: XOR 出力で極性が不定になるクロックを、正極性として伝搬させる。

#### 27. set_clock_sense (旧コマンド)

- **分類**: D. クロック特性
- **設定順**: Step 4
- **SDC版**: 1.7〜2.0 (2.1 では `set_sense` を使う [R4])
- **意味**: クロックの極性 (ユネイト性) を指定する旧コマンド。指定した極性は、極性が決まらないピンでだけ意味を持ち、そこから先へ伝搬する [R13]。`-positive` `-negative` `-stop_propagation` は排他 [R13]。

**文法**

```text
set_clock_sense [-positive] [-negative] [-pulse pulse]
  [-stop_propagation] [-clock clock_list] pin_list
```

**設定例**

```tcl
set_clock_sense -positive [get_pins u_crg/u_clk_xor/Y]
```

**設定例の意味**

- XOR 出力のクロックを正ユネイト (非反転) として扱う。2.1 で書くなら `set_sense -type clock -positive` に相当。

### 3.E クロック間関係

#### 28. set_clock_groups

- **分類**: E. クロック間関係 (仕様書区分: Timing constraints)
- **設定順**: Step 5 (関係する全クロックの定義の後)
- **SDC版**: 1.7〜 (`-comment` 1.9〜)
- **意味**: `-group` で分けたクロックのグループ間にあるパスを、タイミング解析しない関係として宣言する。両方向のパスがまとめて対象になる。

**主なオプション**

- `-asynchronous`: グループ間に位相関係がない (非同期)。CDC は同期化回路側で保証する。
- `-logically_exclusive`: 論理的に同時に使われない (MUX で選択されるクロックなど)。
- `-physically_exclusive`: 物理的に同時に存在しない (同じポートに `-add` で定義したモード別クロックなど)。
- `-allow_paths`: `-asynchronous` と組み合わせ、グループ間パスの解析自体は残す指定 (挙動の詳細はツールのマニュアルで確認)。
- `-name`: このグループ定義の名前。
- `-group`: クロックのリスト。複数回指定する。

**文法**

```text
set_clock_groups [-name name]
  [-logically_exclusive | -physically_exclusive | -asynchronous]
  [-allow_paths] -group clock_list [-group clock_list ...]
  [-comment comment_string]
```

**設定例**

```tcl
set_clock_groups -name ASYNC_CORE_APB -asynchronous -group [get_clocks {CLK_CORE CLK_DIV2}] -group [get_clocks CLK_APB]
set_clock_groups -name EXCL_FUNC_TEST -physically_exclusive -group [get_clocks CLK_CORE] -group [get_clocks CLK_TEST]
```

**設定例の意味**

- 1 行目: `CLK_CORE` / `CLK_DIV2` と `CLK_APB` の間の両方向のパスを非同期として解析しない。
- 2 行目: 同じポートに定義した機能用 `CLK_CORE` とテスト用 `CLK_TEST` は同時に存在しないため、互いの間のパスを解析しない。
- フォルスパスと同じく最上位の優先度を持つため、同じパスに書いた `set_max_delay` などは効かなくなる (第 4 章)。

### 3.F 理想ネットワーク

#### 29. set_ideal_network

- **分類**: F. 理想ネットワーク (仕様書区分: Timing constraints)
- **設定順**: Step 4
- **SDC版**: 1.7〜
- **意味**: 指定したポート/ピン/ネットから始まるネットワークを「理想」とみなし、遅延・遷移を理想値で扱って、合成時のバッファ挿入やデザインルール修正の対象から外す。リセットやスキャンイネーブルなど、クロック以外の高ファンアウトネットを合成段階で扱う典型的な方法。
- **`-no_propagate`**: 理想属性を組合せセルの先へ伝搬させず、直接つながるネットだけを理想にする。

**文法**

```text
set_ideal_network [-no_propagate] object_list
```

**設定例**

```tcl
set_ideal_network [get_ports {rst_n scan_en}]
```

**設定例の意味**

- `rst_n` と `scan_en` から広がる高ファンアウトネットを合成時は理想扱いにし、バッファツリーは配置後 (P&R) に作らせる。P&R 用の SDC からは外すのが一般的。

#### 30. set_ideal_latency

- **分類**: F. 理想ネットワーク (仕様書区分: Timing constraints)
- **設定順**: Step 4 (`set_ideal_network` の後)
- **SDC版**: 1.7〜
- **意味**: 理想ネットワーク上のピンへの到着遅延 (理想レイテンシ) を指定する。既定の 0 では楽観的すぎる場合に使う。

**文法**

```text
set_ideal_latency [-rise] [-fall] [-min] [-max] delay object_list
```

**設定例**

```tcl
set_ideal_latency 0.30 [get_pins u_core/*_reg/RN]
```

**設定例の意味**

- `u_core` 直下のレジスタのリセットピン `RN` に、理想ネットワーク経由で 0.30 ns 遅れて信号が届くとみなす (リカバリ/リムーバルのチェックに反映)。

#### 31. set_ideal_transition

- **分類**: F. 理想ネットワーク (仕様書区分: Timing constraints)
- **設定順**: Step 4 (`set_ideal_network` の後)
- **SDC版**: 1.7〜
- **意味**: 理想ネットワーク上のピンの遷移時間を指定する。

**文法**

```text
set_ideal_transition [-rise] [-fall] [-min] [-max] transition_time object_list
```

**設定例**

```tcl
set_ideal_transition 0.15 [get_pins u_core/*_reg/RN]
```

**設定例の意味**

- 同じリセットピンの遷移時間を 0.15 ns とみなす (既定の 0 だと受け側セルの遅延やチェック値が楽観的になる)。

### 3.G I/O 遅延

#### 32. set_input_delay

- **分類**: G. I/O 遅延 (仕様書区分: Timing constraints)
- **設定順**: Step 6 (基準クロックの定義の後)
- **SDC版**: 1.1〜 (`-network_latency_included` / `-source_latency_included` 1.4〜、`-reference_pin` 2.0〜)
- **意味**: 入力ポートのデータが、基準クロックのエッジから何 ns 後に到着するかを指定する。チップ外の遅延 (外部 FF の clock→Q + 基板配線など) を表す。`-max` は setup 解析、`-min` は hold 解析に使われ、どちらも省略すると両方に同じ値が入る。

**主なオプション**

- `-clock`: 基準クロック (実クロックまたは仮想クロック)。
- `-clock_fall`: 基準を立ち下がりエッジにする。
- `-max` / `-min`: setup 用 / hold 用の値。
- `-add_delay`: 同じポートに、別のクロック・別のエッジ基準の遅延を追加する。付けないと同じ条件の既存値を上書きする [R15]。
- `-network_latency_included` / `-source_latency_included`: 値にクロックのネットワーク/ソースレイテンシが含まれていることを示し、二重に加算されないようにする。
- `-reference_pin` (2.0〜): 指定ピンへのクロック到着を基準にする。
- `-level_sensitive`: 外部の送り側がラッチであることを示す。

**文法**

```text
set_input_delay [-clock clock_name] [-reference_pin pin_port_name]
  [-clock_fall] [-level_sensitive] [-rise] [-fall] [-max] [-min]
  [-add_delay] [-network_latency_included] [-source_latency_included]
  delay_value port_pin_list
```

**設定例**

```tcl
set_input_delay -clock VCLK_IO -max 1.20 [get_ports {din[*] valid_in}]
set_input_delay -clock VCLK_IO -min 0.20 [get_ports {din[*] valid_in}]
set_input_delay -clock VCLK_IO -clock_fall -max 0.80 -add_delay [get_ports {ddr_dq[*]}]
```

**設定例の意味**

- 1 行目: 外部で `VCLK_IO` の立ち上がりから最大 1.20 ns 後にデータが届く (setup 解析)。周期 2.0 ns なら、チップ内に残る時間はマージン等を除いて約 0.80 ns。
- 2 行目: 最も早い到着は 0.20 ns 後 (hold 解析)。
- 3 行目: DDR 入力の立ち下がり側の遅延を、立ち上がり側の設定を消さずに `-add_delay` で追加する (実際は `-min` 側も同様に追加する)。

#### 33. set_output_delay

- **分類**: G. I/O 遅延 (仕様書区分: Timing constraints)
- **設定順**: Step 6 (基準クロックの定義の後)
- **SDC版**: 1.1〜 (`-network_latency_included` / `-source_latency_included` 1.4〜、`-reference_pin` 2.0〜)
- **意味**: 出力ポートから出たデータが、外部の受け側で基準クロックのエッジに対してどれだけ前に必要かを指定する。`-max` は外部のセットアップ時間 + 配線遅延 (setup 解析)、`-min` は「配線遅延の最小値 − 外部のホールド時間」(hold 解析、通常は負の値) を表す。
- **オプション**: `set_input_delay` と同じ構成。

**文法**

```text
set_output_delay [-clock clock_name] [-reference_pin pin_port_name]
  [-clock_fall] [-level_sensitive] [-rise] [-fall] [-max] [-min]
  [-add_delay] [-network_latency_included] [-source_latency_included]
  delay_value port_pin_list
```

**設定例**

```tcl
set_output_delay -clock VCLK_IO -max 0.90 [get_ports {dout[*] valid_out}]
set_output_delay -clock VCLK_IO -min -0.10 [get_ports {dout[*] valid_out}]
```

**設定例の意味**

- 1 行目: 外部の受け側でクロックエッジの 0.90 ns 前までにデータが必要。周期 2.0 ns なら、チップ内で使える時間はマージン等を除いて約 1.10 ns。
- 2 行目: 外部のホールド要求 0.10 ns を負の値で表す。データはクロックエッジから 0.10 ns 経つまで変化してはいけない。

### 3.H 外部環境 (System interface)

#### 34. set_driving_cell

- **分類**: H. 外部環境 (仕様書区分: System interface)
- **設定順**: Step 7
- **SDC版**: 1.1〜 (`-min` / `-max` / `-clock` / `-clock_fall` 1.4〜。`-multiply_by` は 2.0 まで [R4])
- **意味**: 入力ポートを外部の特定のライブラリセルが駆動しているとみなし、そのセルの駆動能力から入力の遷移時間と遅延を計算させる。

**主なオプション**

- `-lib_cell` / `-library`: 駆動セルとそのライブラリ。
- `-pin` / `-from_pin`: 駆動セルの出力ピン / 入力ピン (アークの特定)。
- `-input_transition_rise` / `-input_transition_fall`: 駆動セルの入力側の遷移時間。
- `-no_design_rule`: 駆動セルのデザインルール (最大遷移など) をポートに持ち込まない。
- `-dont_scale`: 動作条件によるスケーリングをしない。

**文法**

```text
set_driving_cell [-lib_cell lib_cell_name] [-rise] [-fall] [-min] [-max]
  [-library lib_name] [-pin pin_name] [-from_pin from_pin_name]
  [-dont_scale] [-no_design_rule] [-clock clock_name] [-clock_fall]
  [-input_transition_rise rise_time] [-input_transition_fall fall_time]
  port_list
```

**設定例**

```tcl
set_driving_cell -lib_cell BUFX4 -library stdcell_ss -pin Y [all_inputs]
set_driving_cell -lib_cell CLKBUFX8 -library stdcell_ss -pin Y [get_ports {clk_core clk_apb}]
```

**設定例の意味**

- 1 行目: 全入力ポートを `BUFX4` の出力 `Y` が駆動しているとみなす。
- 2 行目: クロックポートだけは `CLKBUFX8` で駆動されているとみなす (後から設定した方で置き換わる)。

#### 35. set_drive

- **分類**: H. 外部環境 (仕様書区分: System interface)
- **設定順**: Step 7
- **SDC版**: 1.1〜
- **意味**: 入力ポートの駆動抵抗を直接指定する。0 は理想的な駆動 (遷移時間 0) を意味する。

**文法**

```text
set_drive [-rise] [-fall] [-min] [-max] resistance port_list
```

**設定例**

```tcl
set_drive 0 [get_ports {clk_core clk_apb}]
```

**設定例の意味**

- クロックポートを理想駆動 (駆動抵抗 0 kΩ) として扱う。

#### 36. set_input_transition

- **分類**: H. 外部環境 (仕様書区分: System interface)
- **設定順**: Step 7
- **SDC版**: 1.1〜 (`-clock` / `-clock_fall` 1.4〜)
- **意味**: 入力ポートの遷移時間を直接指定する (駆動セルを使わない方法)。

**文法**

```text
set_input_transition [-rise] [-fall] [-min] [-max]
  [-clock clock_name] [-clock_fall] transition port_list
```

**設定例**

```tcl
set_input_transition 0.10 [get_ports {din[*] valid_in}]
```

**設定例の意味**

- これらの入力ポートの遷移時間を 0.10 ns とする。
- 同じポートには `set_driving_cell` / `set_drive` / `set_input_transition` のいずれか 1 つに統一するのが無難 (併用時の扱いはツール依存)。

#### 37. set_load

- **分類**: H. 外部環境 (仕様書区分: System interface)
- **設定順**: Step 7
- **SDC版**: 1.1〜
- **意味**: 出力ポート (またはネット) に外部の負荷容量を設定する。

**主なオプション**

- `-pin_load` / `-wire_load`: ピン容量 / 配線容量として設定する。
- `-subtract_pin_load`: ネットに設定するとき、接続ピンの容量を差し引いた値として扱う。
- `-min` / `-max`: hold 用 / setup 用の値。

**文法**

```text
set_load [-min] [-max] [-subtract_pin_load] [-pin_load] [-wire_load] value objects
```

**設定例**

```tcl
set_load 0.05 [all_outputs]
set_load -max 0.08 [get_ports {dout[*]}]
```

**設定例の意味**

- 1 行目: 全出力ポートに 0.05 pF の外部負荷。
- 2 行目: `dout` だけ、setup 解析用の負荷を 0.08 pF にする。
- DC では `load_of` で既存セルの入力容量の倍数を指定する書き方が多いが、`load_of` は標準 SDC ではなく、RC (Genus の前身) が認識しなかった報告がある [R9]。

#### 38. set_fanout_load

- **分類**: H. 外部環境 (仕様書区分: System interface)
- **設定順**: Step 7
- **SDC版**: 1.1〜
- **意味**: 出力ポートに外部のファンアウト負荷 (ライブラリの fanout_load 単位) を設定し、`max_fanout` のデザインルール判定に含める。

**文法**

```text
set_fanout_load value port_list
```

**設定例**

```tcl
set_fanout_load 4 [get_ports {dout[*]}]
```

**設定例の意味**

- `dout` の外部ファンアウト負荷を 4 として、最大ファンアウトの判定に加える。

#### 39. set_port_fanout_number

- **分類**: H. 外部環境 (仕様書区分: System interface)
- **設定順**: Step 7
- **SDC版**: 1.1〜
- **意味**: ポートの外側に接続されるファンアウト数を指定し、ワイヤロードモデルによる配線容量の見積りに使わせる。

**文法**

```text
set_port_fanout_number value port_list
```

**設定例**

```tcl
set_port_fanout_number 3 [get_ports {dout[*]}]
```

**設定例の意味**

- `dout` は外部で 3 ピンに接続されているとして、ポートにつながるネットの配線負荷を見積もる。

### 3.I 動作条件・配線モデル・ディレート

#### 40. set_operating_conditions

- **分類**: I. 動作条件 (仕様書区分: Operating conditions)
- **設定順**: Step 2
- **SDC版**: 1.1〜 (`-object_list` 1.5〜)
- **意味**: タイミング解析に使う動作条件 (プロセス・電圧・温度。ライブラリ内の operating_conditions 名) を指定する。Genus などの MMMC (マルチモード・マルチコーナー) フローでは、ライブラリと動作条件はコーナー定義側で与えるのが一般的。

**主なオプション**

- `-analysis_type single | bc_wc | on_chip_variation`: 単一条件 / 最良・最悪の同時解析 / OCV 解析 (値はツールのマニュアルで確認)。
- `-max` / `-min`: setup 用 / hold 用の条件名。
- `-max_library` / `-min_library`: それぞれの条件を持つライブラリ。

**文法**

```text
set_operating_conditions [-library lib_name] [-analysis_type type]
  [-max max_condition] [-min min_condition]
  [-max_library max_lib] [-min_library min_lib]
  [-object_list objects] [condition]
```

**設定例**

```tcl
set_operating_conditions -analysis_type bc_wc -max ss0p72v125c -max_library stdcell_ss -min ff0p88vm40c -min_library stdcell_ff
```

**設定例の意味**

- setup (max) は SS・0.72 V・125 ℃、hold (min) は FF・0.88 V・−40 ℃ の条件で同時に解析する。

#### 41. set_wire_load_model

- **分類**: I. 配線モデル (仕様書区分: Wire load models)
- **設定順**: Step 2
- **SDC版**: 1.1〜
- **意味**: 配置情報がない段階で、ファンアウト数から配線の容量・抵抗を統計的に見積もるワイヤロードモデルを指定する。物理情報を使う合成 (DC Topographical や Genus の物理認識合成など) では使わない。

**文法**

```text
set_wire_load_model -name model_name [-library lib_name] [-min] [-max] [object_list]
```

**設定例**

```tcl
set_wire_load_model -name wl_10k -library stdcell_ss
```

**設定例の意味**

- ライブラリ `stdcell_ss` に定義されたワイヤロードモデル `wl_10k` をデザインに適用する。

#### 42. set_wire_load_mode

- **分類**: I. 配線モデル (仕様書区分: Wire load models)
- **設定順**: Step 2
- **SDC版**: 1.1〜
- **意味**: 階層をまたぐネットに、どの階層のワイヤロードモデルを使うかを決める。
  - `top`: 全ネットにトップ階層のモデル。
  - `enclosed`: ネット全体を含む最小の階層のモデル。
  - `segmented`: 階層ごとに区切り、各区間にその階層のモデル。

**文法**

```text
set_wire_load_mode top | enclosed | segmented
```

**設定例**

```tcl
set_wire_load_mode enclosed
```

**設定例の意味**

- 各ネットを完全に含む最小の階層のワイヤロードモデルで見積もる。

#### 43. set_wire_load_selection_group

- **分類**: I. 配線モデル (仕様書区分: Wire load models)
- **設定順**: Step 2
- **SDC版**: 1.1〜
- **意味**: ブロックの面積に応じてワイヤロードモデルを自動選択する選択グループ (ライブラリで定義) を指定する。

**文法**

```text
set_wire_load_selection_group [-library lib_name] [-min] [-max] group_name [object_list]
```

**設定例**

```tcl
set_wire_load_selection_group -library stdcell_ss wlsg_area
```

**設定例の意味**

- ライブラリ `stdcell_ss` の選択グループ `wlsg_area` に従い、面積に応じたモデルを自動で割り当てる。

#### 44. set_wire_load_min_block_size

- **分類**: I. 配線モデル (仕様書区分: Wire load models)
- **設定順**: Step 2
- **SDC版**: 1.1〜
- **意味**: ワイヤロードの自動選択で対象とする最小のブロック面積を指定する。

**文法**

```text
set_wire_load_min_block_size size
```

**設定例**

```tcl
set_wire_load_min_block_size 5000
```

**設定例の意味**

- 面積 5000 (ライブラリの面積単位) 未満のブロックは、自動選択の単位として扱わない。

#### 45. set_resistance

- **分類**: I. 配線モデル (仕様書区分: Timing constraints)
- **設定順**: Step 2
- **SDC版**: 1.1〜
- **意味**: ネットの抵抗値を指定し、ワイヤロードによる見積りを上書きする。

**文法**

```text
set_resistance [-min] [-max] value net_list
```

**設定例**

```tcl
set_resistance 0.20 [get_nets u_core/n_long_route]
```

**設定例の意味**

- ネット `n_long_route` の抵抗を 0.20 kΩ として遅延を計算する。

#### 46. set_timing_derate

- **分類**: I. ディレート (仕様書区分: Timing constraints)
- **設定順**: Step 2
- **SDC版**: 1.5〜 (`-rise` / `-fall` 1.8〜。`-static` / `-dynamic` / `-increment` は 1.8 版より後に追加 [R4])
- **意味**: 遅延に係数を掛けて OCV (チップ内ばらつき) を見込む。`-late` は遅い側 (係数 > 1)、`-early` は速い側 (係数 < 1)。対象は `-cell_delay` (セル遅延) / `-net_delay` (配線遅延) / `-cell_check` (セットアップ等のチェック値)、`-data` / `-clock` でパスの種類を絞れる。`-increment` は既存の係数に加算する指定。`-static` / `-dynamic` の扱いはツールのマニュアルで確認すること。

**文法**

```text
set_timing_derate [-cell_delay] [-cell_check] [-net_delay]
  [-data] [-clock] [-early] [-late] [-rise] [-fall]
  [-static] [-dynamic] [-increment] derate_value [object_list]
```

**設定例**

```tcl
set_timing_derate -cell_delay -late 1.05
set_timing_derate -cell_delay -early 0.95
set_timing_derate -net_delay -late 1.08
```

**設定例の意味**

- セル遅延を遅い側 +5 %、速い側 −5 %、配線遅延を遅い側 +8 % としてディレートする (デザイン全体)。

#### 47. set_voltage

- **分類**: I. 動作条件 (仕様書区分: Environment、付録 A)
- **設定順**: Step 2
- **SDC版**: 1.8〜
- **意味**: 電源ネットの電圧を指定する。`max_case_voltage` は max-delay (遅い条件)、`-min` は min-delay (速い条件) 用 [R1]。電源ドメイン自体の定義は UPF で行う。

**文法**

```text
set_voltage [-min min_case_value] [-object_list list_of_power_nets] max_case_voltage
```

**設定例**

```tcl
set_voltage -min 0.88 -object_list VDD_CORE 0.72
```

**設定例の意味**

- 電源ネット `VDD_CORE` を、max-delay 解析では 0.72 V、min-delay 解析では 0.88 V として扱う。

### 3.J 設計ルール (Design rule constraints)

共通: ライブラリにも同種の上限 (max_transition など) があり、ツールはより厳しい方を守ろうとする。SDC ではライブラリより厳しくしたい場合に指定する。

#### 48. set_max_transition

- **分類**: J. 設計ルール (仕様書区分: Design rule constraints)
- **設定順**: Step 8
- **SDC版**: 1.1〜 (`-clock_path` / `-rise` / `-fall` 1.5〜)
- **意味**: 遷移時間 (スルー) の上限。対象はデザイン・ポート・クロック。クロックに設定するときは `-clock_path` / `-data_path` でクロックパスとデータパスを分けられる。

**文法**

```text
set_max_transition [-clock_path] [-data_path] [-rise] [-fall] value object_list
```

**設定例**

```tcl
set_max_transition 0.30 [current_design]
set_max_transition -clock_path 0.15 [get_clocks CLK_CORE]
```

**設定例の意味**

- 1 行目: デザイン全体で遷移時間を 0.30 ns 以下にする。
- 2 行目: `CLK_CORE` のクロックパスは 0.15 ns 以下にする。

#### 49. set_max_capacitance

- **分類**: J. 設計ルール (仕様書区分: Design rule constraints)
- **設定順**: Step 8
- **SDC版**: 1.1〜
- **意味**: ドライバが駆動する負荷容量の上限。

**文法**

```text
set_max_capacitance value object_list
```

**設定例**

```tcl
set_max_capacitance 0.20 [current_design]
```

**設定例の意味**

- デザイン内の各ドライバの負荷容量を 0.20 pF 以下にする。

#### 50. set_max_fanout

- **分類**: J. 設計ルール (仕様書区分: Design rule constraints)
- **設定順**: Step 8
- **SDC版**: 1.1〜
- **意味**: ファンアウト負荷 (ライブラリの fanout_load の合計) の上限。

**文法**

```text
set_max_fanout value object_list
```

**設定例**

```tcl
set_max_fanout 32 [current_design]
```

**設定例の意味**

- 各ドライバのファンアウト負荷の合計を 32 以下にする。

#### 51. set_min_capacitance

- **分類**: J. 設計ルール (仕様書区分: Design rule constraints)
- **設定順**: Step 8
- **SDC版**: 1.1〜
- **意味**: 負荷容量の下限。ライブラリに最小容量の要件がある場合などに使う。

**文法**

```text
set_min_capacitance value object_list
```

**設定例**

```tcl
set_min_capacitance 0.002 [get_ports {din[*]}]
```

**設定例の意味**

- 入力ポート `din` が最低 0.002 pF の容量を駆動することを要求する。

### 3.K モード・定数 (Logic assignments ほか)

#### 52. set_case_analysis

- **分類**: K. モード・定数 (仕様書区分: Logic assignments)
- **設定順**: Step 9 (タイミング例外より前)
- **SDC版**: 1.1〜
- **意味**: ポート/ピンを定数 (または片側のエッジだけ) とみなしてタイミング解析する。機能モード・テストモードなどの「モード」を表すのに使い、定数は論理を通って伝搬し、無効になった部分の解析が止まる [R14]。値は `0` / `1` / `rising` / `falling` [R1]。

**文法**

```text
set_case_analysis value port_or_pin_list
```

**設定例**

```tcl
set_case_analysis 0 [get_ports scan_mode]
set_case_analysis 0 [get_pins u_crg/u_clk_mux/S]
```

**設定例の意味**

- 1 行目: 機能モード (`scan_mode` = 0) として解析する。
- 2 行目: クロック MUX の選択を 0 側に固定し、片方のクロックだけが伝搬するようにする。
- 合成で論理そのものを定数として削減させたい意図なら、次の `set_logic_zero` / `set_logic_one` を使う。

#### 53〜55. set_logic_zero / set_logic_one / set_logic_dc

- **分類**: K. モード・定数 (仕様書区分: Logic assignments)
- **設定順**: Step 9
- **SDC版**: 1.1〜
- **意味**:
  - `set_logic_zero` / `set_logic_one`: 入力ポートを論理 0 / 1 に固定する。合成ではこの定数を使って論理が最適化 (削除) されうる。
  - `set_logic_dc`: 入力ポートを don't care とし、最適化に有利な値をツールに選ばせる。

**文法**

```text
set_logic_zero port_list
set_logic_one port_list
set_logic_dc port_list
```

**設定例**

```tcl
set_logic_zero [get_ports tie_low_cfg]
set_logic_one [get_ports tie_high_cfg]
set_logic_dc [get_ports {unused_in[*]}]
```

**設定例の意味**

- 1〜2 行目: 基板上で固定される設定ピンを 0 / 1 とみなし、関連論理を簡略化させる。
- 3 行目: 未使用入力を don't care にする。
- テストモードなど実際には変化する信号に使うと、必要な論理まで消える危険がある。モードの指定は `set_case_analysis` を使う。

#### 56. set_disable_timing

- **分類**: K. モード・定数 (仕様書区分: Timing constraints)
- **設定順**: Step 9
- **SDC版**: 1.1〜
- **意味**: セルのタイミングアーク (またはピン) を無効化し、そのアークを通るパスを解析しない。組合せループの切断や、使わないアークの除外に使う。セルを指定すると、Synopsys ツールはそのセルの出力ピンに設定したものとして扱う [R1]。

**文法**

```text
set_disable_timing [-from from_pin_name] [-to to_pin_name] cell_pin_list
```

**設定例**

```tcl
set_disable_timing [get_cells u_core/u_ro/u_inv0]
set_disable_timing -from A -to Y [get_cells u_core/u_dly_mux]
```

**設定例の意味**

- 1 行目: リングオシレータ内のインバータの全アークを無効化し、組合せループを切る。
- 2 行目: `u_dly_mux` の `A`→`Y` のアークだけを無効化する。
- フォルスパスと違いアーク自体を消すため、そのアークを通る全パス (他のクロック・他のモードを含む) が解析されなくなる。必要最小限にとどめる。

### 3.L タイミング例外 (Timing exceptions)

共通の文法要素 (57〜60):

- `-from` / `-to`: 始点 / 終点 (クロック・ポート・セル・ピン)。`-rise_from` / `-fall_from` / `-rise_to` / `-fall_to` はエッジ限定版 (1.7〜)。
- `-through`: 経由点。複数回書くと、その順に通過するパスを表す。`-rise_through` / `-fall_through` はエッジ限定版 (1.7〜)。
- `-comment` (1.9〜): 制約に付けるコメント文字列。
- 優先順位と上書きのルールは第 4 章。

#### 57. set_false_path

- **分類**: L. タイミング例外 (仕様書区分: Timing exceptions)
- **設定順**: Step 10
- **SDC版**: 1.1〜
- **意味**: 指定したパスをタイミング解析・最適化の対象から外す。`-setup` / `-hold` を付けるとその解析だけを外す。

**文法**

```text
set_false_path [-setup] [-hold] [-rise] [-fall]
  [-from from_list | -rise_from rise_from_list | -fall_from fall_from_list]
  [-through through_list | -rise_through rise_through_list | -fall_through fall_through_list] ...
  [-to to_list | -rise_to rise_to_list | -fall_to fall_to_list]
  [-comment comment_string]
```

**設定例**

```tcl
set_false_path -from [get_clocks CLK_APB] -to [get_clocks CLK_CORE]
set_false_path -from [get_cells u_core/cfg_mode_reg*] -comment "static config registers"
```

**設定例の意味**

- 1 行目: `CLK_APB` → `CLK_CORE` 方向のパスだけを外す (逆方向は解析される)。
- 2 行目: 動作中に値が変わらない設定レジスタから出るパスを外す。
- CDC に使う場合は同期化回路 (2 段 FF など) が前提。両方向を外すなら `set_clock_groups -asynchronous` の方が簡潔。

#### 58. set_multicycle_path

- **分類**: L. タイミング例外 (仕様書区分: Timing exceptions)
- **設定順**: Step 10
- **SDC版**: 1.1〜
- **意味**: 指定したパスに複数クロックサイクルを許す。`-setup N` で setup の捕捉エッジを N 周期目に移す。hold の基準も一緒に動くため、通常は `-hold N-1` で hold を元の位置に戻す [R7]。

**主なオプション**

- `-setup` / `-hold`: setup 用 / hold 用の乗数。
- `-start` / `-end`: 乗数を送り側 / 受け側のクロック周期で数える。既定は setup が受け側、hold が送り側を基準にする [R7]。

**文法**

```text
set_multicycle_path [-setup] [-hold] [-rise] [-fall] [-start] [-end]
  [-from from_list | -rise_from rise_from_list | -fall_from fall_from_list]
  [-through through_list | -rise_through rise_through_list | -fall_through fall_through_list] ...
  [-to to_list | -rise_to rise_to_list | -fall_to fall_to_list]
  [-comment comment_string] path_multiplier
```

**設定例**

```tcl
set_multicycle_path 2 -setup -from [get_cells u_core/u_mac/acc_reg*] -to [get_cells u_core/u_mac/res_reg*]
set_multicycle_path 1 -hold -from [get_cells u_core/u_mac/acc_reg*] -to [get_cells u_core/u_mac/res_reg*]
```

**設定例の意味**

- 1 行目: `acc_reg` → `res_reg` のパスは 2 サイクルで届けばよい (setup の捕捉エッジを 2 周期目へ)。
- 2 行目: hold に N−1 = 1 を指定して、hold の検査を元のエッジ関係に戻す。これを書かないと hold の検査も 1 周期後ろにずれ、過度に厳しい要求になる。
- 同じクロック (位相一致) 間の基本形が「setup N / hold N−1」[R7]。

#### 59. set_max_delay

- **分類**: L. タイミング例外 (仕様書区分: Timing exceptions)
- **設定順**: Step 10
- **SDC版**: 1.1〜 (`-ignore_clock_latency` 2.1〜)
- **意味**: 指定したパスの最大遅延を絶対値で指定し、クロックから決まる setup の要求を置き換える。`-ignore_clock_latency` (2.1〜) を付けると、クロックのレイテンシを含めずに評価する。

**文法**

```text
set_max_delay [-rise] [-fall]
  [-from from_list | -rise_from rise_from_list | -fall_from fall_from_list]
  [-through through_list | -rise_through rise_through_list | -fall_through fall_through_list] ...
  [-to to_list | -rise_to rise_to_list | -fall_to fall_to_list]
  [-ignore_clock_latency] [-comment comment_string] delay_value
```

**設定例**

```tcl
set_max_delay 1.5 -from [get_ports {test_si[*]}] -to [get_cells u_core/u_tdr/shift_reg*]
set_max_delay 2.0 -ignore_clock_latency -from [get_cells u_cdc/gray_src_reg*] -to [get_cells u_cdc/gray_sync1_reg*]
```

**設定例の意味**

- 1 行目: テスト入力 `test_si` から TDR のシフトレジスタまでを 1.5 ns 以内にする。
- 2 行目: 非同期クロック間で受け渡すグレイコードのビット間スキューを抑えるため、データパスだけを 2.0 ns 以内にする。
- 同じパスが `set_clock_groups` やフォルスパスで外されていると、優先度が低いため効かない (第 4 章)。

#### 60. set_min_delay

- **分類**: L. タイミング例外 (仕様書区分: Timing exceptions)
- **設定順**: Step 10
- **SDC版**: 1.1〜 (`-ignore_clock_latency` 2.1〜)
- **意味**: 指定したパスの最小遅延を指定し、hold 側の要求を置き換える。

**文法**

```text
set_min_delay [-rise] [-fall]
  [-from from_list | -rise_from rise_from_list | -fall_from fall_from_list]
  [-through through_list | -rise_through rise_through_list | -fall_through fall_through_list] ...
  [-to to_list | -rise_to rise_to_list | -fall_to fall_to_list]
  [-ignore_clock_latency] [-comment comment_string] delay_value
```

**設定例**

```tcl
set_min_delay 0.20 -from [get_ports din_bypass] -to [get_ports dout_bypass]
```

**設定例の意味**

- 入力 `din_bypass` から出力 `dout_bypass` へ素通りする組合せパスの遅延を、最低 0.20 ns 確保する。

### 3.M 追加タイミングチェック

#### 61. set_clock_gating_check

- **分類**: M. 追加チェック (仕様書区分: Timing constraints)
- **設定順**: Step 11
- **SDC版**: 1.2〜
- **意味**: クロックゲーティング (イネーブル信号でクロックを止める論理) の、ゲート信号に対するセットアップ/ホールドのマージンを指定する。`-high` はクロックが High の間ゲート信号が安定している必要がある AND 型、`-low` は OR 型。object_list を省略するとデザイン全体に適用。統合クロックゲートセル (ICG) のチェック値はライブラリ側で定義される。

**文法**

```text
set_clock_gating_check [-setup setup_value] [-hold hold_value]
  [-rise] [-fall] [-high] [-low] [object_list]
```

**設定例**

```tcl
set_clock_gating_check -setup 0.10 -hold 0.05
```

**設定例の意味**

- デザイン内のクロックゲーティング検査に、セットアップ 0.10 ns・ホールド 0.05 ns のマージンを要求する。

#### 62. set_data_check

- **分類**: M. 追加チェック (仕様書区分: Timing constraints)
- **設定順**: Step 11
- **SDC版**: 1.4〜
- **意味**: クロック以外の 2 つのデータ信号の間に、セットアップ/ホールドの関係を検査させる (非順序チェック)。`-from` が基準側 (クロックのように扱われる側)、`-to` が検査される側。Genus では有効化のための属性設定が必要との報告がある [R10]。

**文法**

```text
set_data_check [-from from_object | -rise_from from_object | -fall_from from_object]
  [-to to_object | -rise_to to_object | -fall_to to_object]
  [-setup] [-hold] [-clock clock_object] value
```

**設定例**

```tcl
set_data_check -from [get_pins u_io/u_gate/A] -to [get_pins u_io/u_gate/B] -setup 0.10
```

**設定例の意味**

- ピン `B` の信号が、ピン `A` の変化より 0.10 ns 以上前に安定していることを検査する。

#### 63. set_min_pulse_width

- **分類**: M. 追加チェック (SDC 2.0 で追加)
- **設定順**: Step 11
- **SDC版**: 2.0〜 [R4]
- **意味**: クロック (またはピン) の High / Low パルス幅の最小値を検査させる。`-high` / `-low` を省略すると両方。

**文法**

```text
set_min_pulse_width [-low] [-high] value [object_list]
```

**設定例**

```tcl
set_min_pulse_width -high 0.40 [get_clocks CLK_CORE]
set_min_pulse_width -low 0.40 [get_clocks CLK_CORE]
```

**設定例の意味**

- `CLK_CORE` の High 幅・Low 幅がそれぞれ 0.40 ns を下回らないことを検査する。

#### 64. set_max_time_borrow

- **分類**: M. 追加チェック (仕様書区分: Timing constraints)
- **設定順**: Step 11
- **SDC版**: 1.1〜
- **意味**: ラッチのタイムボロー (ラッチが透過している期間に、前段が次段から借りられる時間) の上限を指定する。

**文法**

```text
set_max_time_borrow delay_value object_list
```

**設定例**

```tcl
set_max_time_borrow 0.30 [get_clocks CLK_CORE]
```

**設定例の意味**

- `CLK_CORE` で動くラッチが借りられる時間を最大 0.30 ns に制限する。

### 3.N パスグループ

#### 65. group_path

- **分類**: N. パスグループ (仕様書区分: Timing constraints)
- **設定順**: Step 12 (クロック・I/O 制約の後)
- **SDC版**: 1.7〜 (`-comment` 1.9〜)
- **意味**: パスをグループに分け、グループごとに最適化・レポートさせる。`-weight` で最適化の重みを付けられる。`-default` は既定グループを指す。Genus では独自のコストグループ機能も使われる (第 5 章)。

**文法**

```text
group_path [-name group_name | -default] [-weight weight_value]
  [-from from_list | -rise_from rise_from_list | -fall_from fall_from_list]
  [-through through_list | -rise_through rise_through_list | -fall_through fall_through_list] ...
  [-to to_list | -rise_to rise_to_list | -fall_to fall_to_list]
  [-comment comment_string]
```

**設定例**

```tcl
group_path -name IN2REG -from [all_inputs] -to [all_registers]
group_path -name REG2OUT -from [all_registers] -to [all_outputs]
group_path -name REG2REG -from [all_registers] -to [all_registers] -weight 2
```

**設定例の意味**

- 入力→レジスタ、レジスタ→出力、レジスタ間の 3 グループに分ける。最悪パスがグループごとに最適化されるので、I/O の違反がレジスタ間の最適化を妨げにくくなる。
- レジスタ間グループの重みを 2 にして、優先的に最適化させる。

### 3.O 面積・電力

#### 66. set_max_area

- **分類**: O. 面積・電力 (仕様書区分: Area constraints)
- **設定順**: Step 12
- **SDC版**: 1.1〜
- **意味**: デザインの面積目標 (ライブラリの面積単位)。DC では `0` を指定して「タイミングを満たしたうえで可能な限り小さく」を指示する書き方が慣用。

**文法**

```text
set_max_area area_value
```

**設定例**

```tcl
set_max_area 0
```

**設定例の意味**

- 面積目標を 0 とし、タイミングを優先しつつ面積を最小化させる。

#### 67. set_max_dynamic_power

- **分類**: O. 面積・電力 (仕様書区分: Multivoltage and power optimization)
- **設定順**: Step 12
- **SDC版**: 1.4〜
- **意味**: 動的電力の目標値。`unit` を省略したときに使われる単位はツール依存なので、明示するのが安全。

**文法**

```text
set_max_dynamic_power power [unit]
```

**設定例**

```tcl
set_max_dynamic_power 50 mW
```

**設定例の意味**

- 動的電力の目標を 50 mW とする (電力最適化を有効にするツール側の設定と組み合わせて使う)。

#### 68. set_max_leakage_power

- **分類**: O. 面積・電力 (仕様書区分: Multivoltage and power optimization)
- **設定順**: Step 12
- **SDC版**: 1.4〜
- **意味**: リーク電力の目標値。

**文法**

```text
set_max_leakage_power power [unit]
```

**設定例**

```tcl
set_max_leakage_power 2 mW
```

**設定例の意味**

- リーク電力の目標を 2 mW とし、低リーク (高 Vt) セルへの置き換えなどを促す。

### 3.P マルチ電圧

現在のマルチ電圧設計では、電源ドメイン・レベルシフタ・アイソレーションの方針は UPF で記述するのが基本。以下は SDC 側に残っている関連コマンド。

#### 69. create_voltage_area

- **分類**: P. マルチ電圧 (仕様書区分: Multivoltage and power optimization)
- **設定順**: Step 13
- **SDC版**: 1.6〜
- **意味**: 特定の電圧で動作するセル群を配置する領域 (電圧エリア) を定義する。物理設計寄りのコマンド。

**文法**

```text
create_voltage_area -name name [-coordinate coordinate_list]
  [-guard_band_x float] [-guard_band_y float] cell_list
```

**設定例**

```tcl
create_voltage_area -name VA_AON -coordinate {0 0 200 150} [get_cells u_aon]
```

**設定例の意味**

- 階層 `u_aon` を、座標 (0, 0)〜(200, 150) の矩形の電圧エリア `VA_AON` に割り当てる。

#### 70. set_level_shifter_strategy

- **分類**: P. マルチ電圧 (仕様書区分: Multivoltage and power optimization)
- **設定順**: Step 13
- **SDC版**: 1.6〜
- **意味**: どの向きの電圧差にレベルシフタを入れるかの方針。`-rule` の値は `all` / `low_to_high` / `high_to_low` (値はツールのマニュアルで確認)。

**文法**

```text
set_level_shifter_strategy [-rule rule_type]
```

**設定例**

```tcl
set_level_shifter_strategy -rule low_to_high
```

**設定例の意味**

- 低電圧ドメインから高電圧ドメインへ向かう信号にだけレベルシフタを入れる。

#### 71. set_level_shifter_threshold

- **分類**: P. マルチ電圧 (仕様書区分: Multivoltage and power optimization)
- **設定順**: Step 13
- **SDC版**: 1.6〜
- **意味**: レベルシフタが必要と判定する電圧差のしきい値を、絶対値 (`-voltage`) または割合 (`-percent`) で指定する。

**文法**

```text
set_level_shifter_threshold [-voltage float] [-percent float]
```

**設定例**

```tcl
set_level_shifter_threshold -voltage 0.1
```

**設定例の意味**

- 電圧差のしきい値を 0.1 V とし、これを超える電圧差の境界にレベルシフタが必要と判定させる。

---

## 4. 優先順位と上書きのルール

### 4.1 記述順と優先順位

- SDC ファイル内のコマンドの順番は、制約の優先順位を表さない (Synopsys 仕様書の記述 [R1])。
- 順番が効くのは「参照前に定義されていること」と「同じ対象への同種設定の上書き」(4.4)。

### 4.2 タイミング例外の種類による優先順位

| 優先度 | 制約 |
|---|---|
| 1 (最優先) | `set_false_path` (`set_clock_groups` も同等) |
| 2 | `set_max_delay` / `set_min_delay` |
| 3 | `set_multicycle_path` |

- Intel Quartus の説明では、フォルスパスが最優先で、クロックグループはフォルスパスと同順位、次に最大/最小遅延、最後にマルチサイクル [R5]。ASIC 向けツールも同じ考え方だが、細部は各ツールのマニュアルで確認すること。
- 例: `set_clock_groups -asynchronous` で外したクロック間に `set_max_delay` を書いても効かない。

### 4.3 同じ種類の例外どうしの優先順位 (指定の具体性)

| 優先度 | 指定 |
|---|---|
| 1 | `-from` にノード (ポート・ピン・セル) |
| 2 | `-to` にノード |
| 3 | `-through` |
| 4 | `-from` にクロック |
| 5 | `-to` にクロック |

- Quartus の説明 [R5]。同じ優先度で重なる場合は、後から作った制約が前の制約を (一部) 上書きする [R6]。

**設定例**

```tcl
set_max_delay 1.0 -from [get_cells u_a_reg] -to [get_cells u_b_reg]
set_max_delay 2.0 -from [get_cells u_a_reg]
set_max_delay 3.0 -to [get_cells u_b_reg]
```

**設定例の意味**

- `u_a_reg` → `u_b_reg` のパスには、`-from` と `-to` を両方指定した 1 行目 (1.0 ns) が適用される。
- 1 行目がなければ、`-from` を指定した 2 行目 (2.0 ns) が 3 行目より優先される [R5]。

### 4.4 同じ対象への再設定 (上書きと追加)

| コマンド | 追加するための指定 | 追加指定がない場合 |
|---|---|---|
| `create_clock` / `create_generated_clock` | `-add` | 同じソースの既存クロックを置き換える (一般的な挙動) |
| `set_input_delay` / `set_output_delay` | `-add_delay` | 同じ基準クロック・エッジ・min/max の既存値を上書き [R15] |
| 属性系 (`set_load`, `set_driving_cell`, `set_clock_uncertainty` など) | なし | 後から設定した値で上書き |

---

## 5. SDC 標準外だが合成でよく使われるもの (ツール依存)

SDC 標準 (第 3 章) に含まれないもの。他ツールへ渡す SDC には入れず、合成スクリプト (DC / Genus の Tcl) 側に書くのが安全。書き方の例は DC の形式で、Genus での可否・書式は各マニュアルで確認すること。

| 名称 | 用途 | 書き方の例 (DC) | 備考 |
|---|---|---|---|
| `current_design` + デザイン名 | 制約対象のデザインを切り替える | `current_design soc_top` | SDC 標準の `current_design` は引数なし [R1][R4]。SDC 読み込み前にツール側で実行 |
| `get_*` の `-filter` | 属性による絞り込み | `get_cells -hierarchical -filter "ref_name =~ DFF*"` | SDC 1.9 にない拡張 [R3]。式の書式はツールごとに異なる |
| `load_of` | ライブラリピンの入力容量を取得 | `set_load [expr {4 * [load_of stdcell_ss/INVX1/A]}] [all_outputs]` | DC の関数。RC (Genus の前身) が認識しなかった事例 [R9] |
| `set_dont_touch` | 指定したセル・ネットを最適化で変更させない | `set_dont_touch [get_cells u_core/u_spare*]` | SDC 1.8 仕様の表にない [R1] |
| `set_dont_touch_network` | クロック・リセット網を変更させない (旧来の手法) | `set_dont_touch_network [get_ports rst_n]` | SDC 標準の代替は `set_ideal_network` |
| `set_dont_use` | ライブラリセルの使用を禁止 | `set_dont_use [get_lib_cells stdcell_ss/DLY*]` | SDC 1.8 仕様の表にない [R1] |
| `remove_from_collection` | コレクションから一部を除外 | `remove_from_collection [all_inputs] [get_ports clk_core]` | DC などのコレクション操作 |
| `set_fix_hold` | 合成時に hold 違反を修正させる | `set_fix_hold [all_clocks]` | DC のコマンド |
| `set_clock_sense` | クロック極性 (旧コマンド) | `set_clock_sense -positive [get_pins u_x/Y]` | SDC 2.1 では `set_sense` [R4] |
| コストグループ (Genus) | パスグループの Genus 独自機能 | `define_cost_group` / `path_group` | Genus (RC) 独自。`group_path` との関係はマニュアルで確認 |

参考: SDC パーサの sdcx は `set_min_porosity` も SDC 1.4〜2.1 のコマンドとして受け付けるが、1.8 版仕様書のコマンド表には記載がないため、本資料では扱わない。

---

## 6. 合成ツールでの読み込みと確認

### 6.1 Design Compiler

- `read_sdc file_name` で読み込む [R1]。版は `read_sdc -version` → ファイル内の `sdc_version` → 既定 (最新) の順で決まる [R1]。
- 文法だけを検査するには `read_sdc -syntax_only`。未対応のコマンドや引数を警告する [R1]。
- `write_sdc file_name` で書き出す。既定は最新の文法で、`-version` で旧版の文法にできる [R1]。書き出される SDC は「展開形式」(ワイルドカード展開・フル階層名・全オプション付き) になる [R1]。

<!-- nonstd -->
```tcl
read_sdc -syntax_only constraints/soc_top.sdc
read_sdc constraints/soc_top.sdc
write_sdc out/soc_top_mapped.sdc
```

- 1 行目: 文法だけを検査する。
- 2 行目: 制約を読み込む。
- 3 行目: 合成後の制約を SDC として書き出す (P&R への受け渡し用)。

### 6.2 Genus

- 典型的な順序は `read_hdl` → `elaborate` → 制約 (SDC) → `syn_generic` → `syn_map` → `syn_opt`。MathWorks の Genus 用スクリプト例では、`elaborate` の後に `create_clock` を直接実行し、続けて `syn_generic` / `syn_map` を実行している [R11]。
- SDC ファイルは `read_sdc` で読み込む。解釈できない行は「Could not interpret SDC command」(SDC-202) として報告される (RC での事例) [R8]。
- 「制約されていないパスがない/クロックパスしか出ない」といった症状では、SDC 読み込み時の警告をログで確認し、`elaborate` 後に対話モードで SDC のコマンドを 1 行ずつ実行して切り分けるよう Cadence のフォーラムで助言されている [R16]。

<!-- nonstd -->
```tcl
read_hdl -sv rtl/soc_top.sv
elaborate soc_top
read_sdc constraints/soc_top.sdc
syn_generic
syn_map
syn_opt
```

- `elaborate` で回路ができてから SDC を読む (オブジェクトが存在しないと `get_*` が空になり、制約が付かない)。

### 6.3 合成用 SDC と CTS 後の SDC の違い

| 項目 | 合成 (CTS 前) | CTS 後 (P&R 後段・STA) |
|---|---|---|
| クロック | 理想クロック (`set_propagated_clock` なし) [R17] | `set_propagated_clock` で実遅延 |
| `set_clock_uncertainty` | ジッタ + スキュー見積り | ジッタ中心 (スキューは実測) |
| `set_clock_latency` (ネットワーク) | 見積り値を設定 | 実遅延に置き換わる |
| `set_clock_transition` | 想定値を設定 | 実遷移が使われる |
| `set_ideal_network` (リセット等) | 使う | 外す |
| ワイヤロード | 物理情報を使わない合成でのみ使う | 不要 |

---

## 7. 合成用 SDC テンプレート (推奨順)

第 0.4 節の Step 順に並べた例。標準 SDC 2.1 のコマンドだけで記述している。コメントは文字コードの問題を避けるため英語にしている。

```tcl
# ==========================================================
# soc_top.sdc : synthesis constraints (pre-CTS, example)
# ==========================================================

# ---- Step 0: header ----
set sdc_version 2.1
set_units -time ns -capacitance pF -resistance kOhm -voltage V -current mA -power mW

# ---- variables ----
set CORE_PERIOD 2.0
set APB_PERIOD 10.0
set IO_IN_MAX [expr {$CORE_PERIOD * 0.6}]
set IO_IN_MIN 0.20
set IO_OUT_MAX [expr {$CORE_PERIOD * 0.45}]
set IO_OUT_MIN -0.10

# ---- Step 2: operating conditions (non-MMMC flow only) ----
set_operating_conditions -analysis_type bc_wc -max ss0p72v125c -max_library stdcell_ss -min ff0p88vm40c -min_library stdcell_ff

# ---- Step 3: clocks ----
create_clock -name CLK_CORE -period $CORE_PERIOD [get_ports clk_core]
create_generated_clock -name CLK_DIV2 -source [get_ports clk_core] -divide_by 2 [get_pins u_crg/div2_reg/Q]
create_clock -name CLK_APB -period $APB_PERIOD [get_ports clk_apb]
create_clock -name VCLK_IO -period $CORE_PERIOD

# ---- Step 4: clock characteristics (ideal clocks) ----
set_clock_uncertainty -setup 0.15 [get_clocks {CLK_CORE CLK_DIV2 VCLK_IO}]
set_clock_uncertainty -hold 0.05 [get_clocks {CLK_CORE CLK_DIV2 VCLK_IO}]
set_clock_uncertainty -setup 0.30 [get_clocks CLK_APB]
set_clock_uncertainty -hold 0.05 [get_clocks CLK_APB]
set_clock_transition 0.08 [all_clocks]
set_clock_latency -source 0.20 [get_clocks CLK_CORE]

# ---- Step 4: ideal networks (synthesis only) ----
set_ideal_network [get_ports scan_en]

# ---- Step 5: clock relationships ----
set_clock_groups -name ASYNC_CORE_APB -asynchronous \
  -group [get_clocks {CLK_CORE CLK_DIV2 VCLK_IO}] \
  -group [get_clocks CLK_APB]

# ---- Step 6: I/O delays (relative to virtual clock) ----
set_input_delay -clock VCLK_IO -max $IO_IN_MAX [get_ports {din[*] valid_in}]
set_input_delay -clock VCLK_IO -min $IO_IN_MIN [get_ports {din[*] valid_in}]
set_output_delay -clock VCLK_IO -max $IO_OUT_MAX [get_ports {dout[*] valid_out}]
set_output_delay -clock VCLK_IO -min $IO_OUT_MIN [get_ports {dout[*] valid_out}]

# ---- Step 7: external environment ----
set_driving_cell -lib_cell BUFX4 -library stdcell_ss -pin Y [get_ports {din[*] valid_in rst_n scan_en scan_mode}]
set_load 0.05 [all_outputs]

# ---- Step 8: design rules ----
set_max_transition 0.30 [current_design]
set_max_fanout 32 [current_design]

# ---- Step 9: mode / constants ----
set_case_analysis 0 [get_ports scan_mode]

# ---- Step 10: timing exceptions ----
# raw asynchronous reset into the reset synchronizer
set_false_path -from [get_ports rst_n]
set_multicycle_path 2 -setup -from [get_cells u_core/u_mac/acc_reg*] -to [get_cells u_core/u_mac/res_reg*]
set_multicycle_path 1 -hold -from [get_cells u_core/u_mac/acc_reg*] -to [get_cells u_core/u_mac/res_reg*]

# ---- Step 11: additional checks ----
set_clock_gating_check -setup 0.10 -hold 0.05

# ---- Step 12: path groups ----
group_path -name IN2REG -from [all_inputs] -to [all_registers]
group_path -name REG2OUT -from [all_registers] -to [all_outputs]
group_path -name REG2REG -from [all_registers] -to [all_registers]
```

**テンプレートの意味 (要点)**

- Step 0: SDC 2.1 文法、単位は ns / pF / kΩ / V / mA / mW。
- 変数: 周期と I/O 遅延を変数にし、入力は周期の 60 %、出力は 45 % を外部で消費する想定。
- Step 2: setup は SS、hold は FF の条件で解析 (MMMC フローではこの行を書かず、コーナー定義側で指定)。
- Step 3: 500 MHz のコアクロック、その 2 分周、100 MHz の APB クロック、I/O 用の仮想クロック。
- Step 4: CTS 前のマージンと遷移時間、チップ外のソースレイテンシ。スキャンイネーブルは理想ネットワーク扱い。
- Step 5: コア系と APB 系は非同期 (CDC は同期化回路で保証)。
- Step 6〜7: I/O は仮想クロック基準。入力は `BUFX4` 駆動、出力は 0.05 pF 負荷。
- Step 8〜9: 遷移時間とファンアウトの上限。機能モード (`scan_mode` = 0) で解析。
- Step 10: リセット同期化回路への生の非同期リセット入力をフォルスパスに。MAC の 2 サイクルパスは setup 2 / hold 1。
- Step 11〜12: クロックゲーティングのマージンと、I/O・レジスタ間のパスグループ分け。

---

## 8. 参考文献 (エビデンス)

| No | 資料 | 本資料での用途 |
|---|---|---|
| R1 | [Synopsys: Using the Synopsys Design Constraints Format Application Note (Version C-2009.06, SDC 1.8)](https://users.ece.utexas.edu/~mcdermot/vlsi1/VLSI2_SP_2017/synopsys/doc/Design_Compiler/sdc.pdf) | コマンド一覧・文法・区分・版指定・コメント・オブジェクト指定・`read_sdc` / `write_sdc` |
| R2 | [Using the Synopsys Design Constraints Format Application Note (SDC 2.2, Scribd 掲載)](https://www.scribd.com/document/893642100/Using-the-Synopsys-Design-Constraints-Format-Application-Note) | SDC 2.2 (2024 年 6 月) の存在 |
| R3 | [AMD UG903: Supported SDC Commands (SDC 1.9 との対応表)](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Supported-SDC-Commands) | SDC 1.9 の文法、`-filter` などが標準外であること、`set_units` の制限 |
| R4 | [sdcx: SDC 1.1〜2.1 対応のパーサ (docs.rs)](https://docs.rs/crate/sdcx/latest) / [GitHub](https://github.com/dalance/sdcx) | 1.9〜2.1 で追加されたコマンド・オプションの版判定 (`set_sense` は 2.1 のみ など) |
| R5 | [Intel Quartus Prime Pro: Timing Exception Precedence](https://www.intel.com/content/www/us/en/docs/programmable/683243/25-3/timing-exception-precedence.html) | 例外の種類・具体性による優先順位 |
| R6 | [Intel Quartus Prime Standard: Timing Constraint Precedence](https://www.intel.com.au/content/www/us/en/docs/programmable/683068/18-1/timing-constraint-precedence.html) | 同順位の例外は後から作ったものが上書き |
| R7 | [AMD UG903: Multicycle Example (Setup=5 / Hold=4)](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Example-Two-Setup-5/Hold-4) | マルチサイクルの setup N / hold N−1 |
| R8 | [Cadence Community: RC の SDC 読み込みエラー (SDC-202)](https://community.cadence.com/cadence_technology_forums/f/logic-design/23924/wanted-to-know-the-behaviour-of-rc-on-different-sdc-command) | `read_sdc` で解釈できない行の報告 |
| R9 | [Cadence Community: RC SDC load_of](https://community.cadence.com/cadence_technology_forums/f/logic-design/19671/rc-sdc-load_of/1286168) | `load_of` が RC で認識されなかった事例 |
| R10 | [Cadence Community: set_data_check in Genus 19](https://community.cadence.com/cadence_technology_forums/f/digital-implementation/46856/problem-in-reporting-set_data_check-in-genus-19) | Genus の `set_data_check` に属性設定が必要との報告 |
| R11 | [MathWorks: Synthesis Using Cadence Genus](https://ww2.mathworks.cn/help/hdlcoder/ug/generate-HDL-code-and-perform-synthesis-using-cadence-genus-on-ASIC-devices.html) | Genus で `elaborate` 後に制約を与えて `syn_generic` / `syn_map` する流れ |
| R12 | [AMD UG835: create_clock](https://docs.amd.com/r/2024.1-English/ug835-vivado-tcl-commands/create_clock) | `-add` の意味 |
| R13 | [AMD UG835: set_clock_sense](https://docs.amd.com/r/2024.1-English/ug835-vivado-tcl-commands/set_clock_sense) | クロック極性指定の意味と排他オプション |
| R14 | [AMD UG949: Case Analysis](https://docs.amd.com/r/en-US/ug949-vivado-design-methodology/Case-Analysis) | `set_case_analysis` による定数伝搬とモード指定 |
| R15 | [ChipVerify: Synthesis Design Constraints](https://chipverify.com/rtl-synthesis/synthesis-design-constraints) | `set_input_delay` の上書き例 |
| R16 | [Cadence Community: Cadence Genus synthesis (未制約パス)](https://community.cadence.com/cadence_technology_forums/f/digital-implementation/57413/cadence-genus-synthesis) | Genus での制約の切り分け方 |
| R17 | [LonghornSilicon wiki: Design Constraints](https://github.com/LonghornSilicon/lambda/wiki/Design-Constraints) | 合成は理想クロック・CTS 前のアンサーテンティで行う流れ |

補足: Cadence (Genus) と Synopsys (DC) の公式マニュアルはログインが必要なため、上表は公開資料に限っている。各コマンドの最終仕様は、ツール上の `man <コマンド名>` または各社サポートサイトで確認すること。

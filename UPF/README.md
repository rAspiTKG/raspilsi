# UPF (IEEE 1801-2024) コマンド索引と記述方法

IEEE Std 1801-2024 (UPF) の規格書 (PDF 614 ページ) を読み、UPF を書く人が書いたり呼んだりするものをすべて拾い出した索引です。Clause 6 の電力意図コマンド 61 個 (うちレガシー 8 個)、Clause 7 のセル定義コマンド 6 個、11.1 の Tcl 問合せコマンド 5 個、11.2.3 の HDL アクセス関数 25 個と、値として書く名前 (定義済み属性、定義済みの名前、電源の状態値とシムステート、付属書 B の定義済み VCM、HDL パッケージの型・列挙・解決関数) 112 個、あわせて 209 項目を収録しています。オプションと引数は 503 個です。

- 説明はすべて、規格を読んで自分の言葉でまとめた要約です。規格の文章や表、例の転載ではありません。規範は規格本体なので、使う前に各行に示した節を確認してください。
- オプションの一覧、プレースホルダ (値の書き方)、必須・任意、複数回指定、排他、入れ子は、各コマンドの Syntax 欄から機械的に取り出したものです。既定値は Arguments 欄と本文の記述から拾いました。
- 各名前の下のリンクは、規格の節番号と印刷ページ番号です。ページ番号は各ページの下端に印刷された番号で、PDF のページ番号はこれに 1 を足したものです (例: p.198 は PDF の 199 ページ目)。コマンドのページは節の見出しがあるページです。リンク先は IEEE Xplore の規格のページで、ページ単位のリンクはできないため共通です。
- ★ よく使う: 付属書 E.4 (例題 SoC の電力意図、p.465 から) の UPF コードの中で、コマンドとして実際に呼ばれているもの (行頭、または `[ ]` の中で呼ばれているもの) に付けました。28 個あり、名前の下に E.4 での呼び出し回数を書いています。
- R: 5.10 の「詳細化できる引数」(Arguments 欄で R の印が付いた引数) です。同じオブジェクトに対して 2 回目以降のコマンドで `-update` と一緒に書き足せます。
- 2024 年版で新しく加わったもの・変わったもの: 規格の序文には、AMS (アナログ/ミックスドシグナル) IP を含むデザインの実装と検証への対応と、より多様な保持レジスタへの対応を加えたことしか書かれておらず、コマンドやオプションごとの変更点は示されていません。そのため、この索引では新規・変更の印を付けていません。
- 機能別のカテゴリ: 規格の 6.2 「Categories」は、現行 (current)・レガシー (legacy)・非推奨 (deprecated) の分類を定義した節で、機能別の分類は規格にありません。この索引では 6.2 の分類を「区分」に使い、機能別のカテゴリは 8.3.3 (電力意図のモデルを組み立てる順番) と Clause 4 の概念の分け方に合わせて設けました。各カテゴリの根拠の節はカテゴリ一覧に書いています。
- 区分: コマンドごとの区分は見出しの "(legacy)" から、オプションごとの区分は付属書 D (D.2.2 非推奨、D.2.3 レガシー) と各コマンドの表の "Legacy arguments" / "Deprecated arguments" の欄から決めました。両者は一致しています。

確認したこと (最後の項目は目視、それ以外は `tools/check.py` で機械的に確認し、結果を `upf_commands.json` に記録しています):

- 目次 (Clause 6 / 7) のコマンドが索引にあり、節番号と印刷ページが一致する: 目次 67 個 (Clause 6: 61、Clause 7: 6) 中 67 個一致
- 各 Syntax 欄のオプションと位置引数が、そのコマンドの行のオプション欄にある: 97 項目 (コマンド・関数) の 503 個中 503 個あり
- layout テキストの表の範囲にある -option (pdfplumber とは別の取り出し) がオプション欄にある: 411 個中 396 個はオプション欄にそのままあり、13 個は Arguments 欄で改行により切れた名前の前半 (オプション欄の名前の先頭と一致)、残り 2 個は説明文の中で別のオプションに触れているもの (-stage_x_enable (define_power_switch_cell)、-lib_cell_type (define_retention_cell))
- カテゴリ別・区分別の件数の合計が総数と一致し、見出しと表の行数とも一致する: カテゴリ 20 個の合計 209 項目、区分の合計 209 項目・オプション 503 個
- README のすべての表で、各行の列数が見出し行と同じ: 表 22 個、221 行すべて一致
- 全角の括弧がない (README、JSON、tools のスクリプトと説明文): 25 ファイルで 0 箇所
- README 内のリンク (#...) の行き先がすべてある: リンク 67 個、行き先 229 個中、解決できないもの 0 個
- PDF のライセンス表示の文言と、そこにある利用者名が out/ と tools/ のどのファイルにもない: 25 ファイルを確認、該当 0 件
- 規格の英文が 6 語以上続けてそのまま入っていない: 英単語 6 語以上の並び 1 個のうち、規格の本文と一致したもの 0 個
- 付属書 D と各コマンドの表 (Legacy / Deprecated arguments) の区分の突き合わせ: 食い違い 0 件
- PDF のページを目視して、索引の行 (オプション、プレースホルダ、必須・任意、複数回指定、R、区分、既定値) と照合したコマンド: `set_isolation`、`set_retention`、`create_power_switch`、`add_power_state`、`create_supply_set`、`set_design_attributes`、`set_equivalent`、`set_design_top`、`set_domain_supply_net`、`define_level_shifter_cell`、`define_power_switch_cell`、`define_retention_cell` の 12 個。すべて一致 (照合で見つけた補足は説明に反映済み)

規格の Syntax 欄や表には、括弧の対応などの誤記がいくつかあります。オプションを取り出すときは、次のように補正して読みました (PDF で目視確認済み)。該当するコマンドの行にも注記しています。

- 6.44 `set_design_attributes`: Syntax 欄の `[-is_refinable_macro [TRUE|FALSE>]]` を `[-is_refinable_macro [<TRUE | FALSE>]]` と読んだ
- 6.47 `set_equivalent`: Syntax 欄の `[-interchangeable [<TRUE | FALSE>] [-nets` を `[-interchangeable [<TRUE | FALSE>]] [-nets` と読んだ
- 7.5 `define_level_shifter_cell`: Arguments 欄の名前の先頭の `-` が抜けているのを `-input_voltage_range` と読んだ
- 7.6 `define_power_switch_cell`: Syntax 欄の `-ground ground_pin]}` を `-ground ground_pin}` と読んだ
- 7.7 `define_retention_cell`: Syntax 欄の `posedge | negedge}}]` を `posedge | negedge>}}]` と読んだ

## 書き方の基本

### 書く順番

UPF のコマンドは書いた順に実行され、名前は使う前に定義しておく必要があります (8.3.2)。ツールは読み込んだあと、8.3.3 の順番で電力意図のモデルを組み立てます。ファイルもこの順に書くと読みやすくなります。

1. 版とトップの宣言: [`upf_version`](#cmd-upf_version)、[`set_design_top`](#cmd-set_design_top)、必要なら [`set_scope`](#cmd-set_scope)。下位ブロックの UPF は [`load_upf`](#cmd-load_upf) `-scope` で読み込む
2. 電源ドメイン: [`create_power_domain`](#cmd-create_power_domain) で範囲 (`-elements`) と電源セットハンドル (`-supply`) を決める
3. 電源供給網: [`create_supply_port`](#cmd-create_supply_port)、[`create_supply_net`](#cmd-create_supply_net)、[`connect_supply_net`](#cmd-connect_supply_net)、電源スイッチ [`create_power_switch`](#cmd-create_power_switch)、電源セット [`create_supply_set`](#cmd-create_supply_set) と [`associate_supply_set`](#cmd-associate_supply_set) (ドメインの `primary` などへの割り当て)
4. 制御信号: 必要なら [`create_logic_port`](#cmd-create_logic_port)、[`create_logic_net`](#cmd-create_logic_net)、[`connect_logic_net`](#cmd-connect_logic_net)
5. ストラテジ: [`set_isolation`](#cmd-set_isolation)、[`set_level_shifter`](#cmd-set_level_shifter)、[`set_retention`](#cmd-set_retention)、[`set_repeater`](#cmd-set_repeater)。クランプ値などのポートの要求は [`set_port_attributes`](#cmd-set_port_attributes) で付ける
6. セルの割り当て (実装向け): [`map_retention_cell`](#cmd-map_retention_cell)、[`use_interface_cell`](#cmd-use_interface_cell)、[`map_power_switch`](#cmd-map_power_switch) など
7. 電源状態: [`add_supply_state`](#cmd-add_supply_state)、[`add_power_state`](#cmd-add_power_state)、[`add_state_transition`](#cmd-add_state_transition)、[`create_power_state_group`](#cmd-create_power_state_group)

IP ブロックの UPF は、段階ごとにファイルを分けて書き足していく使い方が想定されています (4.9.1)。

- 制約 UPF: IP と一緒に渡す最小限の情報。ドメインの最小の範囲 (`-atomic`)、保持が必要な要素、ポートのクランプ値、正当な電源状態と遷移
- 構成 UPF: そのシステムで使うためのストラテジ (分離・レベルシフタ・保持・リピータ) と、その制御
- 実装 UPF: 電源の配線網 (ポート・ネット・スイッチ) と制御ロジック。使えるコマンドと `-update` で足せるオプションは 4.9.1.1 の Table 1 に決められている。[`load_upf`](#cmd-load_upf) `-implementation` を付けると、それ以外のコマンドがエラーになる

### Tcl としての注意 (5.1)

- UPF は Tcl です。ツールは Tcl 8.4 以上の完全なインタプリタで UPF を読みます。コマンドの戻り値は後のコマンドで使えます。
- 変数、リスト、`proc` など Tcl の機能はすべて使えます。ただし、デザインの情報を取るのは [`find_objects`](#cmd-find_objects) だけにし、ツール固有のコマンドを電力意図に混ぜてはいけません。
- 名前のパターンに正規表現が使えるのは [`find_objects`](#cmd-find_objects) と [`query_upf`](#tcl-query_upf) だけです。
- 長いコマンドは行末の `\` で次の行に続けます。リストや論理式は `{ }` で囲みます (例: `-elements {u_a u_b}`、`-supply_expr {power == {FULL_ON 0.8}}`)。
- Tcl の `if` / `for` / `while` は `if {条件} {本体}` の形で、条件を `{ }` で囲んで書きます。Tcl の文法上 `if( 条件 )` の形にはできないため、Tcl を書くときは標準の Tcl の書き方に従ってください。

### スコープと名前 (5.3.3、5.5)

- コマンドはカレントスコープで実行され、作ったオブジェクトはそのスコープに属します (5.5)。カレントスコープは [`set_scope`](#cmd-set_scope) や [`load_upf`](#cmd-load_upf) `-scope` で移ります。
- UPF のオブジェクトの名前は識別子で、英字で始まり、英数字と `_` だけを使います。大文字と小文字は区別されます (5.3.2)。
- 名前の書き方は 3 種類です。
  - 単純名: カレントスコープで定義した名前 (例: `PD_CPU`)
  - ドット付きの名前: ほかのオブジェクトの中のもの (例: ストラテジ `PD_CPU.iso_out`、電源セットハンドル `PD_CPU.primary`、電源ネットハンドル `PD_CPU.primary.power`)。UPF ライブラリの中のものは `ライブラリ名::名前` (5.3.3.3)
  - 階層名: インスタンス名を `/` でつないだもの。先頭に `/` がなければカレントスコープからの相対 (ルート付きの名前、例: `u_cpu/u_core/clk_en`)、`/` で始まればデザインのトップからの名前 (5.3.3.4)
- 電源セットハンドルは電源セット名の代わりに、電源ネットハンドルは電源ネット名の代わりに使えます (5.3.3.5)。

### 単位 (5.13)

- 電圧は単位 V の実数で書きます。`0.8` は 0.8 V です。
- HDL の情報モデルでは、電圧は整数の µV で持ちます。変換には [`upf_convert_real_volts_to_int_uvolts`](#hdl-upf_convert_real_volts_to_int_uvolts) などを使います。

### 段階的な詳細化 (5.10)

- 同じオブジェクトに対して 2 回目以降に書くコマンドには `-update` を付け、オプション一覧で R の付いたオプションを書き足します。オブジェクトを特定する引数 (名前、ストラテジならドメインも) は毎回書きます。
- 最初のコマンドに `-update` を付けるとエラー、2 回目以降に付け忘れてもエラーです。前に指定した値と食い違う値もエラーになります (`-elements` のように積み上がる引数を除く)。
- 例: 構成 UPF で `set_isolation iso_out -domain PD_CPU ...` と書き、実装 UPF で `set_isolation iso_out -domain PD_CPU -update -isolation_supply SS_AON` と書き足す。
- 電源セットの電源状態 `ON` / `OFF` は最初から定義されています (4.7.4)。4.7.4 は、この 2 つの定義を後から更新して論理式・電源式・合法性を足せる (6.5) としており、付属書 E.4 の例でも式を足すときに `add_power_state ... -supply -update` と書いています。

### エラー処理 (5.12)

- 誤ったオプションなどのエラーが起きると `TCL_ERROR` が上がります。Tcl の `catch` で捕まえれば、読み込み中の [`load_upf`](#cmd-load_upf) を止めずに続けられます。
- ただし、エラーになったコマンドが途中まで実行されていることがあり、エラー後の状態は規格で決められていません。

### 例: 電源を切れる 2 つのドメインを持つトップ

次の例は、この索引のために書いたものです (規格の例ではありません)。トップ `soc_top` の中に、常時オンの `PD_TOP` (0.8 V)、電源を切る `PD_CPU` (0.8 V) と `PD_GPU` (0.9 V) があり、電源制御は `PD_TOP` にある `u_pmu` の出力で行う想定です。

```tcl
# soc_top.upf : 常時オンの PD_TOP と、電源を切る PD_CPU / PD_GPU を持つトップ
upf_version 4.0
set_design_top soc_top

# ---- 電源ドメイン (4.4)
create_power_domain PD_TOP -elements {.} -supply {primary}
create_power_domain PD_CPU -elements {u_cpu} -supply {primary} -supply {ret}
create_power_domain PD_GPU -elements {u_gpu} -supply {primary}

# ---- 電源ポートと電源ネット (4.5)
create_supply_port VDD_AON
create_supply_port VDD_HI
create_supply_port VSS
create_supply_net VDD_AON
create_supply_net VDD_HI
create_supply_net VSS
create_supply_net VDD_CPU_SW
create_supply_net VDD_GPU_SW
connect_supply_net VDD_AON -ports {VDD_AON}
connect_supply_net VDD_HI -ports {VDD_HI}
connect_supply_net VSS -ports {VSS}

# ---- 電源スイッチ (u_pmu の出力で入り切りする)
create_power_switch SW_CPU \
  -output_supply_port {vout VDD_CPU_SW} \
  -input_supply_port {vin VDD_AON} \
  -control_port {pwr_en u_pmu/cpu_pwr_en} \
  -on_state {cpu_on vin {pwr_en}} \
  -off_state {cpu_off {!pwr_en}}
create_power_switch SW_GPU \
  -output_supply_port {vout VDD_GPU_SW} \
  -input_supply_port {vin VDD_HI} \
  -control_port {pwr_en u_pmu/gpu_pwr_en} \
  -on_state {gpu_on vin {pwr_en}} \
  -off_state {gpu_off {!pwr_en}}

# ---- 電源セットを作り、ドメインのハンドルに割り当てる
create_supply_set SS_AON -function {power VDD_AON} -function {ground VSS}
create_supply_set SS_CPU -function {power VDD_CPU_SW} -function {ground VSS}
create_supply_set SS_GPU -function {power VDD_GPU_SW} -function {ground VSS}
associate_supply_set SS_AON -handle PD_TOP.primary
associate_supply_set SS_CPU -handle PD_CPU.primary
associate_supply_set SS_AON -handle PD_CPU.ret
associate_supply_set SS_GPU -handle PD_GPU.primary

# ---- 分離: 電源を切るドメインの出力を 0 に固定する。セルは親 (PD_TOP) に置く
set_isolation iso_cpu_out -domain PD_CPU \
  -applies_to outputs \
  -clamp_value 0 \
  -isolation_signal u_pmu/cpu_iso_en \
  -isolation_sense high \
  -isolation_supply SS_AON \
  -location parent
set_isolation iso_gpu_out -domain PD_GPU \
  -applies_to outputs \
  -clamp_value 0 \
  -isolation_signal u_pmu/gpu_iso_en \
  -isolation_sense high \
  -isolation_supply SS_AON \
  -location parent

# ---- レベルシフタ: 0.8 V の PD_TOP から 0.9 V の PD_GPU へ入る信号
set_level_shifter ls_gpu_in -domain PD_GPU \
  -applies_to inputs \
  -rule low_to_high \
  -location self \
  -input_supply SS_AON \
  -output_supply SS_GPU

# ---- 保持: PD_CPU のフリップフロップを、電源断の間 PD_CPU.ret (= SS_AON) で保つ
set_retention ret_cpu -domain PD_CPU \
  -retention_supply PD_CPU.ret \
  -save_signal {u_pmu/cpu_save high} \
  -restore_signal {u_pmu/cpu_restore high}

# ---- 電源状態: 電源セットの ON / OFF は定義済みなので -update で式を足す (4.7.4)
add_power_state SS_AON -supply -update \
  -state {ON -supply_expr {power == {FULL_ON 0.8} && ground == {FULL_ON 0.0}}}
add_power_state SS_CPU -supply -update \
  -state {ON -supply_expr {power == {FULL_ON 0.8} && ground == {FULL_ON 0.0}}} \
  -state {OFF -supply_expr {power == OFF}}
add_power_state SS_GPU -supply -update \
  -state {ON -supply_expr {power == {FULL_ON 0.9} && ground == {FULL_ON 0.0}}} \
  -state {OFF -supply_expr {power == OFF}}

# ---- システムの動作モード: これ以外の組み合わせ (GPU だけ ON など) は不正
add_power_state PD_TOP -domain \
  -state {RUN_ALL -logic_expr {PD_CPU.primary == ON && PD_GPU.primary == ON}} \
  -state {CPU_ONLY -logic_expr {PD_CPU.primary == ON && PD_GPU.primary == OFF}} \
  -state {SLEEP -logic_expr {PD_CPU.primary == OFF && PD_GPU.primary == OFF}} \
  -complete
```

例で使ったコマンド: [`create_power_domain`](#cmd-create_power_domain)、[`create_power_switch`](#cmd-create_power_switch)、[`create_supply_set`](#cmd-create_supply_set)、[`associate_supply_set`](#cmd-associate_supply_set)、[`set_isolation`](#cmd-set_isolation)、[`set_level_shifter`](#cmd-set_level_shifter)、[`set_retention`](#cmd-set_retention)、[`add_power_state`](#cmd-add_power_state)。テストベンチから電源を入り切りするときは、HDL の [`supply_on`](#hdl-supply_on) / [`supply_off`](#hdl-supply_off) で `VDD_AON` などのポートを駆動します。

## 区分の見方

区分は 6.2 の分類 (current / legacy / deprecated) に従います。項目数はコマンド・関数・値の行の数、オプション数はオプションと引数の数です。レガシーのコマンドのオプションは、すべてレガシーとして数えています (オプション欄には書かず、コマンドの区分だけを示しています)。

| 区分 | 項目数 | オプション数 | 意味 |
|---|---:|---:|---|
| 標準 | 187 | 468 | 6.2 の current (現行)。推奨され、最新の概念と整合しているもの |
| 標準 (一部レガシー) | 5 | 0 | コマンドは現行だが、オプションの一部がレガシー (付属書 D.2.3)。該当するオプションに「レガシー」と書いている |
| 標準 (一部非推奨) | 2 | 0 | コマンドは現行だが、オプションの一部 (または値の一部) が非推奨 (付属書 D.2.2) |
| 標準 (一部レガシー・非推奨) | 1 | 0 | コマンドは現行だが、レガシーのオプションと非推奨のオプションの両方を持つ |
| レガシー | 12 | 30 | 6.2 の legacy。後方互換のためだけに残っていて、新しいコードでは使わない。構文と意味は最新の概念に合わせて更新されていない。置き換え先は付属書 D の Table D.1 |
| 非推奨 | 2 | 5 | 6.2 の deprecated。どのコードでも使わない。将来の版で削除されうる |
| (値の一部だけ非推奨) | — | 1 | オプション自体は現行で、取りうる値の一部だけが非推奨のもの。オプション欄に注記している (例: `set_isolation -applies_to_clamp` の `any`) |
| 合計 | 209 | 503 | |

## カテゴリ一覧

- [実行環境・スコープ・ファイル](#cat-env) (7 件): 版の宣言、カレントスコープの移動、UPF ファイルの読み書き、名前の付け方、デザインの検索 (根拠: 5.1、5.5、8.3.2)
- [UPF ライブラリ](#cat-lib) (3 件): どこからでも参照できる UPF ライブラリを作り、読み込み、見えるようにする (根拠: 5.11)
- [電源ドメイン](#cat-domain) (2 件): 電源ドメインと、それを束ねる複合ドメインを定義する (根拠: 4.4、8.3.3 の a・f 項)
- [電源供給網](#cat-supply) (12 件): 電源ポート・電源ネット・電源セットを作ってつなぎ、電源スイッチや抽象的な電源を定義する。電圧の変動範囲もここで指定する (根拠: 4.5、8.3.3 の c・d 項)
- [制御ロジック網](#cat-logic) (3 件): 電源スイッチや分離・保持の制御信号を通すロジックポート・ロジックネットを作ってつなぐ (根拠: 8.3.3 の b 項)
- [電源管理ストラテジ](#cat-strategy) (5 件): 分離・レベルシフタ・リピータ・保持をどのポートや要素に入れるかを決める (根拠: 4.6、8.3.3 の h〜k 項)
- [セルの割り当て](#cat-map) (5 件): ストラテジや電源スイッチを、どのライブラリセル・機能モデルで実装するかを指定する (根拠: 8.3.3 の l 項)
- [電源状態・状態遷移](#cat-state) (7 件): 電源・ドメイン・グループの電源状態と状態遷移を定義する (旧方式の PST を含む) (根拠: 4.7、8.3.3 の m・n 項)
- [属性](#cat-attr) (2 件): モデル・インスタンス・ポートに属性 (5.6 の定義済み属性を含む) を付ける (根拠: 5.6)
- [シミュレーション制御](#cat-sim) (7 件): シムステートの振る舞い、`PARTIAL_ON` の扱い、アサーション・破壊・initial ブロックの再実行、チェッカの挿入を制御する (根拠: 4.8、8.3.4、Clause 9)
- [値の変換](#cat-vcm) (3 件): UPF の電源の値と HDL のポートの値の変換方法 (VCM、旧方式の VCT) を定義する (根拠: 4.10)
- [パワーモデル](#cat-model) (5 件): ハード IP などのパワーモデルを定義してインスタンスに適用する (根拠: 6.31、6.9、付属書 H)
- [セル定義 (Clause 7)](#cat-cell) (6 件): ライブラリセルを電源管理セル (常時オン・ダイオード・分離・レベルシフタ・電源スイッチ・保持) として定義する (根拠: Clause 7)
- [Tcl 問合せコマンド (11.1)](#cat-tcl) (5 件): 情報モデル (Clause 10) のオブジェクトとプロパティを Tcl から調べる。処理の第 5 段階でだけ使える (根拠: 11.1)
- [HDL アクセス関数 (11.2.3)](#cat-hdl) (25 件): テストベンチやチェッカの HDL から情報モデルを読み書きする関数 (電源の投入・遮断を含む) (根拠: 11.2.3)
- [HDL パッケージの型・列挙・解決関数](#cat-hdlpkg) (34 件): 11.2 の UPF パッケージ (SystemVerilog / VHDL) で定義される型・列挙・電源ネットの解決関数 (根拠: 11.2.2、11.2.4、11.2.5)
- [定義済み属性](#cat-vattr) (22 件): `set_port_attributes` / `set_design_attributes` の `-attribute` や HDL の属性で書く、意味の決まった属性名 (根拠: 5.6 の Table 7)
- [定義済みの名前 (関数・ハンドル・電源状態)](#cat-vname) (33 件): 電源セットの関数、ドメインやストラテジのハンドル、総称信号ハンドル、定義済みの電源状態など、予約された名前 (根拠: 5.3.3.2 の Table 3、4.7.4)
- [電源の状態値・シムステート](#cat-vstate) (11 件): 電源の状態値 (`supply_net_type` の state) と、電源状態に付けるシムステート (根拠: 4.7.2、4.8)
- [定義済み VCM (付属書 B)](#cat-vcmtab) (12 件): `connect_supply_net` `-vcm` でそのまま使える定義済みの値変換方式 (根拠: 付属書 B)

<a id="cat-env"></a>

## 実行環境・スコープ・ファイル (7 件)

版の宣言、カレントスコープの移動、UPF ファイルの読み書き、名前の付け方、デザインの検索

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-upf_version"></a>`upf_version`<br>[6.61 p.243](https://ieeexplore.ieee.org/document/10910082) | `string` (任意) | `string`: 以降のコマンドが前提とする UPF の版。この規格に従うなら `4.0` を書く | 引数なしで呼ぶと、ツールが解釈に使っている UPF の版を返す。引数を付けると、以降のコマンドがどの版向けに書かれたかを記録する。IEEE 1801-2024 の版を表す文字列は `4.0`。版の違うコマンドが混在したときの扱いは規格では決めていない | ツールが使っている UPF の版の文字列 (この規格なら `4.0`) | 標準 |
| <a id="cmd-set_design_top"></a>`set_design_top`<br>★ よく使う (E.4 で 4 回)<br>[6.45 p.195](https://ieeexplore.ieee.org/document/10910082) | `design_top_module` (必須) | `design_top_module`: この UPF を書いた対象のトップモジュール名 | この UPF ファイルがどのモジュール向けに書かれたかを宣言する。実際に適用する先が別モジュールのインスタンスでも、構造が同じならエラーにはならない (ツールが警告を出すことはある) | 空文字列 | 標準 |
| <a id="cmd-set_scope"></a>`set_scope`<br>[6.55 p.231](https://ieeexplore.ieee.org/document/10910082) | `instance` (必須) | `instance`: 新しいカレントスコープにするインスタンス | カレントスコープ (以降のコマンドが名前を解決し、オブジェクトを作る階層) を、指定したインスタンスに移す。UPF のコマンドは原則としてカレントスコープで実行される (5.5) | 成功時は、実行前のカレントスコープをデザイン相対の階層名 (/ で始まる名前) で返す。インスタンスがないときなどは `TCL_ERROR` | 標準 |
| <a id="cmd-load_upf"></a>`load_upf`<br>★ よく使う (E.4 で 17 回)<br>[6.35 p.181](https://ieeexplore.ieee.org/document/10910082) | `upf_file_name` (必須)<br>`-scope instance_name_list` (任意)<br>`-hide_globals` (任意)<br>`-parameters {{parameter_name [parameter_value]}*}` (任意)<br>`-implementation` (任意) | `upf_file_name`: 実行する UPF ファイル<br>`-scope`: UPF ファイルを実行するインスタンスのリスト。インスタンスごとにそこをスコープにして実行する<br>`-hide_globals`: 読み込んだファイルからグローバルな Tcl の変数と proc を見えなくし、書き換えられないようにする (`-parameters` で渡したものと、:: で明示的に参照したものを除く)<br>`-parameters`: ファイルに渡す引数のリスト。Tcl の proc の args と同じ書き方で、{名前 値} と書くと値が既定値になる。各引数の値は、その名前の変数に入る<br>`-implementation`: 実装 UPF として許されているコマンドとオプション (4.9.1.1 の Table 1) だけをファイル内で許可する | 別の UPF ファイルを読み込んで実行する。`-scope` を付けると、指定した各インスタンスをカレントスコープ (とデザインのトップ) にして実行し、終わると元に戻す (IP の UPF を階層ごとに読む使い方)。同じインスタンスに `-scope` で 2 回読み込むとエラー。新しい名前空間は作らない | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-save_upf"></a>`save_upf`<br>[6.42 p.191](https://ieeexplore.ieee.org/document/10910082) | `upf_file_name` (必須)<br>`-scope instance_name` (任意) | `upf_file_name`: 書き出す UPF ファイル<br>`-scope`: 書き出すコマンドの基準にするインスタンス | カレントスコープ (または指定したスコープ) を基準に、それまでに解釈した電力意図を UPF ファイルとして書き出す | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-name_format"></a>`name_format`<br>[6.41 p.190](https://ieeexplore.ieee.org/document/10910082) | `-isolation_prefix pattern` (任意、既定: 空文字列)<br>`-isolation_suffix pattern` (任意、既定: `_UPF_ISO`)<br>`-level_shift_prefix pattern` (任意、既定: 空文字列)<br>`-level_shift_suffix pattern` (任意、既定: `_UPF_LS`)<br>`-implicit_supply_suffix string` (任意、既定: `_UPF_IS`)<br>`-implicit_logic_prefix string` (任意、既定: なし (`NULL`))<br>`-implicit_logic_suffix string` (任意、既定: `_UPF_IL`) | `-isolation_prefix`: 分離セル挿入で新しく作る名前の前に付ける文字列の型<br>`-isolation_suffix`: 分離セル挿入で新しく作る名前の後に付ける文字列の型<br>`-level_shift_prefix`: レベルシフタ挿入で新しく作る名前の前に付ける文字列の型<br>`-level_shift_suffix`: レベルシフタ挿入で新しく作る名前の後に付ける文字列の型<br>`-implicit_supply_suffix`: 暗黙に作る電源ネット/ポートの名前の後に付ける文字列<br>`-implicit_logic_prefix`: 暗黙に作るロジックネット/ポートの名前の前に付ける文字列<br>`-implicit_logic_suffix`: 暗黙に作るロジックネット/ポートの名前の後に付ける文字列 | 暗黙に作られるオブジェクト (挿入される分離セル・レベルシフタに伴う名前、暗黙の電源ポート/ネット、暗黙のロジックポート/ネット) の名前の付け方を決める | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-find_objects"></a>`find_objects`<br>★ よく使う (E.4 で 9 回)<br>[6.33 p.174](https://ieeexplore.ieee.org/document/10910082) | `scope` (必須)<br>`-pattern search_pattern` (必須)<br>`-object_type <model \| inst \| port \| supply_port \| net \| process>` (任意)<br>`-direction <in \| out \| inout>` (任意)<br>`-transitive [<TRUE \| FALSE>]` (任意、既定: 未指定なら `FALSE`、値なしで指定すると `TRUE`)<br>`-regexp` (任意、`-exact` と排他)<br>`-exact` (任意、`-regexp` と排他)<br>`-ignore_case` (任意)<br>`-non_leaf` (任意、`-leaf_only` と排他)<br>`-leaf_only` (任意、`-non_leaf` と排他)<br>`-traverse_macros` (任意)<br>`-expand_to_bits` (任意) | `scope`: 探す範囲にするスコープ (インスタンス)<br>`-pattern`: 探す名前のパターン。何も付けなければ Tcl の glob 形式として扱う<br>`-object_type`: 探すオブジェクトの種類 (model / inst / port / `supply_port` / net / process)。省略時はインスタンス・名前付きプロセス・ロジックポート・ネットが対象。port はロジックポートだけを返す<br>`-direction`: `-object_type` が port / `supply_port` のとき、ポートの向き (in / out / inout) で絞る<br>`-transitive`: `TRUE` ならスコープの下の階層もたどって探す<br>`-regexp`: パターンを正規表現として扱う<br>`-exact`: パターンのワイルドカードを展開せず、文字どおりに照合する<br>`-ignore_case`: 大文字と小文字を区別せずに照合する<br>`-non_leaf`: 末端 (リーフ) でないオブジェクトだけを返す<br>`-leaf_only`: 末端 (リーフ) のオブジェクトだけを返す<br>`-traverse_macros`: ハード/ソフト/リファイナブルマクロの中まで探す。省略時はマクロを含むリーフセルで探索が止まる<br>`-expand_to_bits`: 多ビットのポート/ネットを 1 ビットずつの名前に展開して返す (port と net だけに効く) | 指定したスコープの下から、名前のパターンに合う HDL のオブジェクト (インスタンス、ポート、ネット、プロセスなど) を探して名前のリストを返す。UPF からデザインの情報をプログラムで取るときは、このコマンドだけを使う決まり (5.1)。正規表現が使えるのはこのコマンドと `query_upf` だけ<br>**注:** `-regexp` / `-exact` をどちらも付けなければ glob 形式。`-non_leaf` / `-leaf_only` をどちらも付けなければリーフと非リーフの両方を返す | 見つかったオブジェクトの名前 (カレントスコープからの相対名) のリスト。種類の区別は付かない。見つからなければ空文字列 | 標準 |

<a id="cat-lib"></a>

## UPF ライブラリ (3 件)

どこからでも参照できる UPF ライブラリを作り、読み込み、見えるようにする

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-create_upf_library"></a>`create_upf_library`<br>[6.29 p.160](https://ieeexplore.ieee.org/document/10910082) | `upf_library_name` (必須)<br>`-contents {upf commands}` (必須) | `upf_library_name`: 作る UPF ライブラリの名前<br>`-contents`: ライブラリの中身を定義する UPF コマンドの並び ({ } で囲む) | UPF ライブラリ (どのスコープからも参照できる共通の置き場) を作り、その中身を `-contents` の UPF コマンドで定義する。ライブラリに置けるのは VCM など、グローバルに定義する種類のオブジェクト (5.5 の Table 3)。中のオブジェクトは `ライブラリ名::名前` で参照するか、`use_upf_library` で直接見えるようにする | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-load_upf_library"></a>`load_upf_library`<br>[6.36 p.182](https://ieeexplore.ieee.org/document/10910082) | `upf_library_file` (必須) | `upf_library_file`: 読み込む UPF ライブラリのファイル | UPF ライブラリを定義したファイルを読み込んで実行する | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-use_upf_library"></a>`use_upf_library`<br>[6.63 p.246](https://ieeexplore.ieee.org/document/10910082) | `upf_library_name` (必須) | `upf_library_name`: 見えるようにする UPF ライブラリの名前 | 指定した UPF ライブラリの中のオブジェクトを、カレントスコープから `ライブラリ名::` を付けずに参照できるようにする | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |

<a id="cat-domain"></a>

## 電源ドメイン (2 件)

電源ドメインと、それを束ねる複合ドメインを定義する

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-create_power_domain"></a>`create_power_domain`<br>★ よく使う (E.4 で 8 回)<br>[6.21 p.135](https://ieeexplore.ieee.org/document/10910082) | `domain_name` (必須)<br>`-atomic` (任意)<br>`-elements element_list` (任意、R)<br>`-subdomains domain_list` (任意、R)<br>`-exclude_elements exclude_list` (任意、R)<br>`-supply {supply_set_handle [supply_set_ref]}` (任意、複数回可、R)<br>`-available_supplies supply_set_ref_list` (任意、R)<br>`-boundary_supplies supply_set_ref_list` (任意、`-available_supplies` に付随、R)<br>`-define_func_type {supply_function pg_type_list}` (任意、複数回可、R)<br>`-update` (任意、R) | `domain_name`: 作る電源ドメインの名前 (カレントスコープで一意)<br>`-atomic`: このドメインを最小単位にする。範囲に入った要素は、以後もずっとこのドメインに残る (後の詳細化で別ドメインに分けられない)<br>`-elements`: ドメインに入れる要素 (インスタンスなど) のリスト。`.` はカレントスコープ自身とその下全体を表す。最初の定義か `-update` のどちらかで少なくとも 1 回は必要<br>`-subdomains`: 中に入れる (ルート付きの) ドメイン名のリスト。ドメインを束ねる入れ物を作る指定で、`create_composite_domain` と同じ意味。`-elements` とは同時に書けない<br>`-exclude_elements`: 範囲から外す要素のリスト<br>`-supply`: 電源セットハンドルを定義する。{ハンドル名 電源セット} の形で書くと、そのハンドルに既存の電源セットを結び付ける (`associate_supply_set` と同じ)。ハンドルだけ書いて、結び付けは後で行ってもよい<br>`-available_supplies`: ストラテジなしで挿入されるリピータや電源管理セルに使ってよい追加の電源セット。空リストも書ける。指定は和集合として積み上がる<br>`-boundary_supplies`: 境界に入れるセル (分離セル・レベルシフタなど) に使ってよい追加の電源セット。`-available_supplies` と一緒に書く<br>`-define_func_type`: 一次電源セットの電源関数 (power / ground など) を、どの `pg_type` のピンに自動接続するかを決める ({関数 `pg_type` のリスト} の形)<br>`-update`: すでに定義したドメインに情報を追加する | 電源ドメイン (同じ一次電源で動く要素の集まり) をカレントスコープに作る。`-elements` で範囲 (extent) を決め、`-supply` で電源セットハンドルを定義する。どの要素もちょうど 1 つのドメインに属する必要がある。定義済みの一次電源ハンドル primary を持ち、ドメイン内の要素に暗黙に接続される (シミュレーション時)。`-update` で後から要素や電源を足せる<br>**注:** 何も指定しない場合、ドメインのスコープ以上で定義された電源セットはすべて、ドメインに挿入するセルの電源として使ってよい扱いになる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-create_composite_domain"></a>`create_composite_domain`<br>[6.17 p.130](https://ieeexplore.ieee.org/document/10910082) | `composite_domain_name` (必須)<br>`-subdomains subdomain_list` (任意、R)<br>`-supply {supply_set_handle [supply_set_ref]}` (任意、R)<br>`-update` (任意、R) | `composite_domain_name`: 作る複合ドメインの名前 (識別子)<br>`-subdomains`: 束ねるドメインの (ルート付きの) 名前のリスト。作成済みの複合ドメインも入れられる<br>`-supply`: 一次電源ハンドル primary だけを書ける。{primary 電源セット} の形なら、その電源セットに結び付ける (`associate_supply_set` と同じ)<br>`-update`: すでに定義した複合ドメインに情報を追加する | 既存の電源ドメイン (サブドメイン) を束ねた複合ドメインを作る。複合ドメインは入れ物で、シリコン上の領域は持たない。複合ドメインに `set_isolation` / `set_level_shifter` / `set_repeater` / `set_retention` / `connect_supply_net` / `map_power_switch` / `map_retention_cell` / `use_interface_cell` を適用すると、各サブドメインに適用される (どれかのサブドメインでエラーになる場合は適用されない)。一方、複合ドメインに付けた電源状態や一次電源ハンドルはサブドメインには適用されない<br>**注:** サブドメインの一次電源セットは、複合ドメインの一次電源セットと電気的に等価か、機能的に等価で入れ替え可能 (`set_equivalent`) でなければならない | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |

<a id="cat-supply"></a>

## 電源供給網 (12 件)

電源ポート・電源ネット・電源セットを作ってつなぎ、電源スイッチや抽象的な電源を定義する。電圧の変動範囲もここで指定する

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-create_supply_port"></a>`create_supply_port`<br>★ よく使う (E.4 で 12 回)<br>[6.26 p.157](https://ieeexplore.ieee.org/document/10910082) | `port_name_list` (必須)<br>`-direction <in \| out \| inout>` (任意、既定: `in`)<br>`-virtual` (任意)<br>`-domain domain_name` (任意、**レガシー**) | `port_name_list`: 作る電源ポートの名前 (識別子) のリスト<br>`-direction`: ポートの向き (in / out / inout)<br>`-virtual`: 実装上は存在しない仮想の電源ポートにする (検証・解析用のモデル)<br>`-domain`: そのドメインの電源ネットの接続点としてポートを作る | カレントスコープに電源ポートを作る。HDL に同名のポートがあればそれを使い、なければ作る (8.3.4)。電源ネットとの接続は `connect_supply_net` で行う | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 (一部レガシー) |
| <a id="cmd-create_supply_net"></a>`create_supply_net`<br>★ よく使う (E.4 で 4 回)<br>[6.25 p.151](https://ieeexplore.ieee.org/document/10910082) | `net_name_list` (必須)<br>`-resolve <unresolved \| one_hot \| parallel \| parallel_one_hot \| resolution_function_name>` (任意、既定: 指定しなければ unresolved と同じ)<br>`-virtual` (任意)<br>`-tunneling <FORCE \| INHIBIT \| AUTOMATIC>` (任意)<br>`-domain domain_name` (任意、**レガシー**)<br>`-reuse` (任意、**レガシー**) | `net_name_list`: 作る電源ネットの名前 (識別子) のリスト<br>`-resolve`: 複数の駆動元があるときに、状態と電圧をどう決めるか。unresolved (駆動元は 1 つまで)、`one_hot` (同時に `OFF` 以外になる駆動元は 1 つ)、parallel (同じ根の電源から並列の経路で駆動)、`parallel_one_hot` (両者の組み合わせ)、または利用者定義の解決関数名 (6.25.3)<br>`-virtual`: 実装上は存在しない仮想の電源ネットにする<br>`-tunneling`: HDL のポートにつないだときのトンネリングの扱い (FORCE / INHIBIT / AUTOMATIC。4.10.4)<br>`-domain`: どのドメインのスコープにネットを作るかを指定する<br>`-reuse`: 別のドメイン用に定義済みのネットを、このドメインの範囲でも使えるようにする | カレントスコープに電源ネットを作る。複数の電源から駆動される場合の解決方法 (`-resolve`) や、HDL のポートにつないだときのトンネリングの扱いを指定できる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 (一部レガシー) |
| <a id="cmd-create_supply_set"></a>`create_supply_set`<br>★ よく使う (E.4 で 19 回)<br>[6.27 p.158](https://ieeexplore.ieee.org/document/10910082) | `set_name` (必須)<br>`-function {func_name net_name}` (任意、複数回可、R)<br>`-virtual` (任意)<br>`-update` (任意、R) | `set_name`: 作る電源セットの名前 (識別子)。`-update` のときは電源セットハンドルの単純名も書ける<br>`-function`: 電源関数 (power / ground / nwell / pwell / deepnwell / deeppwell) と、それを担う電源ネット (または電源ポート、電源ネットハンドル) の組。ネットはカレントスコープで定義済みであること<br>`-virtual`: 実装上は存在しない仮想の電源セットにする<br>`-update`: 定義済みの電源セット (ハンドル) に情報を追加する | 電源セット (power・ground などの電源関数と、それを担う電源ネットの組) を作る。`-update` で既存の電源セットや電源セットハンドルに、関数とネットの対応を後から追加できる (実装 UPF でネットを割り当てる使い方) | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-connect_supply_net"></a>`connect_supply_net`<br>★ よく使う (E.4 で 6 回)<br>[6.14 p.123](https://ieeexplore.ieee.org/document/10910082) | `net_name` (必須)<br>`-elements element_list` (任意)<br>`-ports port_list` (任意)<br>`-pg_type pg_type_list` (任意、複数回可)<br>`-vcm vcm_name` (任意)<br>`-cells cell_list` (任意)<br>`-domain domain_name` (任意)<br>`-vct vct_name` (任意、**レガシー**) | `net_name`: つなぐ電源ネット (単純名)<br>`-elements`: `-pg_type` で接続するインスタンスのリスト<br>`-ports`: つなぎ先の電源ポート (ルート付きの名前) のリスト<br>`-pg_type`: `pg_type` による間接接続の指定。指定した `pg_type` を持つインスタンスのピンにつなぐ<br>`-vcm`: 電源ネットと HDL のポートの間で値を変換する VCM (6.30) を指定する<br>`-cells`: `-pg_type` で接続する対象をこのセルのインスタンスに限る<br>`-domain`: つなぐインスタンスを、このドメインの範囲に入っているものに限る<br>`-vct`: 値の変換に使う VCT (旧方式)。現在は `-vcm` を使う | 電源ネットを電源ポートにつなぐ。`-ports` で直接つなぐほか、`-pg_type` でインスタンスのピンの `pg_type` を手がかりに間接的につなぐこともできる。必要な階層では暗黙にポートとネットが作られる。明示的な接続は、暗黙・自動の接続より優先される | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 (一部レガシー) |
| <a id="cmd-connect_supply_set"></a>`connect_supply_set`<br>[6.15 p.126](https://ieeexplore.ieee.org/document/10910082) | `supply_set_ref` (必須)<br>`-connect {supply_function pg_type_list}` (必須、複数回可)<br>`-elements element_list` (任意)<br>`-exclude_elements exclude_list` (任意)<br>`-transitive [<TRUE \| FALSE>]` (任意、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`) | `supply_set_ref`: つなぐ電源セット (ルート付きの名前)<br>`-connect`: {電源関数 `pg_type` のリスト} の組。その `pg_type` を持つピンに、電源セットのその関数をつなぐ。少なくとも 1 つ必要<br>`-elements`: 対象にするインスタンスのリスト<br>`-exclude_elements`: 対象から外すインスタンスのリスト<br>`-transitive`: `TRUE` なら指定した要素の下の階層も対象にする | 電源セットの各電源関数を、指定した `pg_type` を持つピンに自動接続するよう指定する。対象の要素を `-elements` で絞れる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-associate_supply_set"></a>`associate_supply_set`<br>★ よく使う (E.4 で 3 回)<br>[6.10 p.117](https://ieeexplore.ieee.org/document/10910082) | `supply_set_name_list` (必須)<br>`-handle supply_set_handle` (任意) | `supply_set_name_list`: 結び付ける電源セット (ルート付きの名前) のリスト<br>`-handle`: 割り当て先の電源セットハンドル (ドメイン・電源スイッチ・ストラテジのもの) | 電源セット同士を結び付け、同じものとして扱う。典型的には、電源ドメインやストラテジ、電源スイッチの電源セットハンドル (例: PD.primary) に、実際の電源セットを割り当てる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-set_equivalent"></a>`set_equivalent`<br>[6.47 p.196](https://ieeexplore.ieee.org/document/10910082) | `-function_only` (任意)<br>`-interchangeable [<TRUE \| FALSE>]` (任意、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`)<br>`-nets supply_net_name_list` (任意)<br>`-sets supply_set_name_list` (任意) | `-function_only`: 電気的ではなく機能的に同じであることを宣言する (別の電源だが常に同じ状態になるなど)<br>`-interchangeable`: 機能的に同じ電源を、互いに入れ替えて使ってよいか<br>`-nets`: 同等とする電源ポート/電源ネットのリスト<br>`-sets`: 同等とする電源セットのリスト | 複数の電源ネット (ポート) や電源セットが、電気的に同じ (同じ電源につながっている) か、機能的に同じであることを宣言する。ストラテジの適用判定 (同じ電源なら分離不要など) に影響する<br>**注:** 規格の Syntax 欄では `-interchangeable` の閉じ括弧 \] が 1 つ欠けている | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-create_power_switch"></a>`create_power_switch`<br>★ よく使う (E.4 で 4 回)<br>[6.23 p.143](https://ieeexplore.ieee.org/document/10910082) | `switch_name` (必須)<br>`-switch_type <fine_grain \| coarse_grain \| both>` (任意、既定: `coarse_grain`)<br>`-output_supply_port {port_name [supply_net_name]}` (任意)<br>`-input_supply_port {port_name [supply_net_name]}` (必須、複数回可)<br>`-control_port {port_name [net_name]}` (必須、複数回可)<br>`-on_state {state_name input_supply_port {boolean_expression}}` (必須、複数回可)<br>`-off_state {state_name {boolean_expression}}` (任意、複数回可)<br>`-supply_set supply_set_ref` (任意)<br>`-on_partial_state {state_name input_supply_port {boolean_expression}}` (任意、複数回可)<br>`-error_state {state_name {boolean_expression}}` (任意、複数回可)<br>`-ack_port {port_name net_name [boolean_expression]}` (任意、複数回可)<br>`-ack_delay {port_name delay}` (任意、複数回可)<br>`-instances instance_list` (任意、R)<br>`-update` (任意、R)<br>`-domain domain_name` (任意、R、**レガシー**) | `switch_name`: 作る電源スイッチの名前 (識別子)<br>`-switch_type`: スイッチの種類 (`fine_grain` / `coarse_grain` / both)。`-instances` で与えたセルを、セルのスイッチ種別 (Liberty の `switch_cell_type` または `UPF_switch_cell_type`) で選び分けるのにも使う<br>`-output_supply_port`: 出力電源ポートの名前と、任意でつなぐ電源ネット。`coarse_grain` と both では必須、`fine_grain` では無視される<br>`-input_supply_port`: 入力電源ポートの名前と、任意でつなぐ電源ネット。少なくとも 1 つ必要で、複数書ける<br>`-control_port`: 制御ポートの名前と、任意でつなぐロジックネット。少なくとも 1 つ必要<br>`-on_state`: `ON` 状態の名前、その状態で出力に通す入力電源ポート、成立条件の論理式<br>`-off_state`: `OFF` 状態の名前と成立条件の論理式<br>`-supply_set`: スイッチの制御部分 (制御ポート・ack) に給電する電源セット<br>`-on_partial_state`: 部分 `ON` (`PARTIAL_ON`) 状態の名前、入力電源ポート、成立条件の論理式<br>`-error_state`: エラー状態の名前と成立条件の論理式<br>`-ack_port`: 肯定応答ポートの名前、つなぐロジックネット、任意で応答値の式<br>`-ack_delay`: 肯定応答ポートの応答遅延<br>`-instances`: このスイッチを実装したセルのインスタンス名 (階層名) のリスト。`fine_grain` では必須<br>`-update`: `-instances` を後から追加する<br>`-domain`: スイッチのインスタンスを作るスコープを、このドメインのスコープにする | 電源スイッチの抽象モデルを作る。入力電源ポート、出力電源ポート、制御ポートを定義し、制御ポートの論理式で `ON` / 部分 `ON` / `OFF` / エラーの各状態を決める。実装では複数のスイッチセルの連鎖などに置き換わってよい。肯定応答 (ack) ポートとその遅延も書ける | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 (一部レガシー) |
| <a id="cmd-create_abstract_power_source"></a>`create_abstract_power_source`<br>★ よく使う (E.4 で 2 回)<br>[6.16 p.127](https://ieeexplore.ieee.org/document/10910082) | `power_source_name` (必須)<br>`-output_supply_set {output_ss_handle [supply_set_ref]}` (任意)<br>`-input_supply_set {input_ss_handle [supply_set_ref]}` (必須、複数回可)<br>`-control_port {port_name [net_name]}` (必須、複数回可)<br>`-on_state {state_name input_supply_set {boolean_expression}}` (必須、複数回可)<br>`-off_state {state_name {boolean_expression}}` (任意)<br>`-supply_set supply_set_ref` (任意)<br>`-ack_port {port_name net_name}` (任意、複数回可)<br>`-ack_delay {port_name delay}` (任意、複数回可)<br>`-ack_polarity {port_name <active_high \| active_low>}` (任意、複数回可、既定: `active_high`)<br>`-power_switch power_switch_list` (任意、R)<br>`-update` (任意、R) | `power_source_name`: 作る電源の名前 (単純名)<br>`-output_supply_set`: 出力の電源セットハンドルの名前と、任意で結び付ける電源セット<br>`-input_supply_set`: 入力の電源セットハンドルの名前と、任意で結び付ける電源セット。少なくとも 1 つ必要<br>`-control_port`: 制御ポートの名前と、任意でつなぐロジックネット。少なくとも 1 つ必要<br>`-on_state`: `ON` にする条件。状態名、出力へ通す入力電源セット、論理式の組。少なくとも 1 つ必要<br>`-off_state`: `OFF` にする条件 (状態名と論理式)。書かなければ、`ON` 条件がどれも成り立たないときに `OFF` とする暗黙の状態が加わる<br>`-supply_set`: 制御ポートと ack に給電する電源セット<br>`-ack_port`: 肯定応答ポートの名前と、つなぐロジックネット<br>`-ack_delay`: 肯定応答ポートの応答遅延<br>`-ack_polarity`: 肯定応答ポートの極性 (`active_high` / `active_low`)<br>`-power_switch`: この電源を実装する電源スイッチ (`create_power_switch` で定義したもの) のリスト。`-update` と一緒に使う想定<br>`-update`: `-power_switch` を後から追加する | 電源セットの単位で電源の切り替えを表す抽象的な電源 (power source) を作る。制御ポートの論理式で、出力電源セットハンドルの定義済み状態 `ON` / `OFF` を切り替える。実装段階で `create_power_switch` の電源スイッチに詳細化する前提のモデル<br>**注:** `ON` 条件と `OFF` 条件のどちらも成り立たない、または両方が成り立つときは、出力は定義済みの `ERROR` 状態になる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-set_domain_supply_net"></a>`set_domain_supply_net`<br>[6.46 p.195](https://ieeexplore.ieee.org/document/10910082) | `domain_name` (必須)<br>`-primary_power_net supply_net_name` (必須)<br>`-primary_ground_net supply_net_name` (必須) | `domain_name`: 対象の電源ドメイン<br>`-primary_power_net`: 一次電源の power に使う電源ネット<br>`-primary_ground_net`: 一次電源の ground に使う電源ネット | 電源ドメインの一次電源 (power と ground) に使う電源ネットを指定する旧方式のコマンド。現在は `create_supply_set` と `associate_supply_set` (ドメインの primary ハンドルへの割り当て) で書く (付属書 D の Table D.1) | 成功時は 1。失敗時は `TCL_ERROR` | レガシー |
| <a id="cmd-set_variation"></a>`set_variation`<br>★ よく使う (E.4 で 2 回)<br>[6.57 p.235](https://ieeexplore.ieee.org/document/10910082) | `-supply supply_name_list` (必須)<br>`-range {low_factor high_factor}` (必須) | `-supply`: 変動範囲を指定する電源ポート/電源ネット/電源セット関数の名前のリスト<br>`-range`: 公称電圧に掛ける下限と上限の係数 ({下限係数 上限係数}) | 電源 (電源ポート・電源ネット・電源セットの関数) の電圧が公称電圧からどれだけ上下しうるかを、公称電圧に掛ける係数の組で指定する (例: 公称 0.9 V に {0.9 1.1} なら 0.81 〜 0.99 V)。公称電圧は電源状態 (`add_power_state`) や電源の状態 (`add_supply_state`) の定義で与える。電気的に等価な電源にも同じ指定が及び、等価な電源に別々の指定をするとエラー。指定のない電源は変動なし ({1.0 1.0} と同じ) | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-set_correlated"></a>`set_correlated`<br>★ よく使う (E.4 で 1 回)<br>[6.43 p.192](https://ieeexplore.ieee.org/document/10910082) | `-nets {supply_net_name_list*}` (任意)<br>`-sets {supply_set_name_list*}` (任意) | `-nets`: 連動させる電源ネットの組を、サブリストのリストで書く<br>`-sets`: 連動させる電源セットの組を、サブリストのリストで書く | 複数の電源ネット (または電源セット) の電圧の変動範囲が連動していることを宣言する。比べるときは、最小は最小同士、最大は最大同士で比べる<br>**注:** 4.9.1.1 の Table 1 には `set_correlation` と書かれているが、このコマンドのこと | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |

<a id="cat-logic"></a>

## 制御ロジック網 (3 件)

電源スイッチや分離・保持の制御信号を通すロジックポート・ロジックネットを作ってつなぐ

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-create_logic_port"></a>`create_logic_port`<br>★ よく使う (E.4 で 25 回)<br>[6.20 p.133](https://ieeexplore.ieee.org/document/10910082) | `port_name_list` (必須)<br>`-direction <in \| out \| inout>` (任意、既定: `in`) | `port_name_list`: 作るロジックポートの名前 (識別子) のリスト<br>`-direction`: ポートの向き (in / out / inout) | カレントスコープにロジックポート (電源制御信号などを通すポート) を作る。HDL に同名のポートがあればそれを使う | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-create_logic_net"></a>`create_logic_net`<br>★ よく使う (E.4 で 18 回)<br>[6.19 p.133](https://ieeexplore.ieee.org/document/10910082) | `net_name_list` (必須) | `net_name_list`: 作るロジックネットの名前 (識別子) のリスト | カレントスコープにロジックネットを作る。電源スイッチの制御や分離・保持の制御信号を、UPF からつなぐために使う | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-connect_logic_net"></a>`connect_logic_net`<br>★ よく使う (E.4 で 30 回)<br>[6.13 p.122](https://ieeexplore.ieee.org/document/10910082) | `net_name` (必須)<br>`-ports port_list` (必須)<br>`-reconnect` (任意) | `net_name`: つなぐロジックネット (単純名)<br>`-ports`: つなぎ先のポートのリスト (カレントスコープのポート、または下のインスタンスのポート)<br>`-reconnect`: 既定値の定数で駆動されているポートを、このネットで駆動し直すことを許す | ロジックネットをロジックポートにつなぐ。つなぎ先は、カレントスコープのインタフェース上のポートか、その下のインスタンスのポート。途中の階層には必要に応じてポートとネットが暗黙に作られる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |

<a id="cat-strategy"></a>

## 電源管理ストラテジ (5 件)

分離・レベルシフタ・リピータ・保持をどのポートや要素に入れるかを決める

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-set_isolation"></a>`set_isolation`<br>★ よく使う (E.4 で 16 回)<br>[6.48 p.198](https://ieeexplore.ieee.org/document/10910082) | `strategy_name` (必須)<br>`-domain domain_name` (必須)<br>`-elements element_list` (任意、R)<br>`-exclude_elements exclude_list` (任意、R)<br>`-source <source_domain_name \| source_supply_ref>` (任意、R)<br>`-sink <sink_domain_name \| sink_supply_ref>` (任意、R)<br>`-diff_supply_only [<TRUE \| FALSE>]` (任意、R、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`)<br>`-use_functional_equivalence [<TRUE \| FALSE>]` (任意、R、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`)<br>`-applies_to <inputs \| outputs \| both>` (任意、R)<br>`-applies_to_boundary <lower \| upper \| both>` (任意、R、既定: `both`)<br>`-applies_to_clamp <0 \| 1 \| Z \| latch \| any \| value>` (任意、R、値 `any` だけが非推奨 (付属書 D.2.2.2))<br>`-no_isolation` (任意、R)<br>`-force_isolation` (任意、R)<br>`-location <self \| other \| parent \| fanout>` (任意、R、既定: `self`)<br>`-clamp_value <0 \| 1 \| Z \| latch \| value \| {<0 \| 1 \| Z \| latch \| value>*}>` (任意、R)<br>`-isolation_signal signal_list` (任意、R)<br>`-isolation_sense <high \| low \| {<high \| low>*}>` (任意、`-isolation_signal` に付随、R、既定: `high`)<br>`-isolation_supply supply_set_list` (任意、R)<br>`-name_prefix pattern` (任意、R)<br>`-name_suffix pattern` (任意、R)<br>`-instance {{instance_name port_name}*}` (任意、R)<br>`-async_set_reset {net_name <high \| low>}` (任意、R)<br>`-async_clamp_value <0 \| 1>` (任意、R)<br>`-update` (任意、R)<br>`-isolation_power_net net_name` (任意、R、**レガシー**)<br>`-isolation_ground_net net_name` (任意、R、**レガシー**)<br>`-applies_to_sink_off_clamp <0 \| 1 \| any \| Z \| latch \| value>` (任意、R、**非推奨**)<br>`-applies_to_source_off_clamp <0 \| 1 \| any \| Z \| latch \| value>` (任意、R、**非推奨**) | `strategy_name`: 分離ストラテジの名前<br>`-domain`: このストラテジを定義する電源ドメイン<br>`-elements`: 適用候補にするインスタンスまたはポートのリスト。インスタンスを書くと、そのインスタンスの全ポートを書いたことになる (優先度は低い)。省略するとドメインのインタフェースの全ポートが候補<br>`-exclude_elements`: 適用しないインスタンスまたはポートのリスト<br>`-source`: 駆動側の電源 (電源セットまたはドメイン名。ドメイン名ならその一次電源) が一致するポートに絞る<br>`-sink`: 受け側の電源 (電源セットまたはドメイン名) が一致するポートに絞る<br>`-diff_supply_only`: `TRUE` なら、駆動側と受け側の電源が異なる経路のポートだけを対象にする<br>`-use_functional_equivalence`: 電源の一致判定で、機能的な等価 (`set_equivalent` `-function_only`) を考慮するか<br>`-applies_to`: ドメインから見たポートの向き (inputs / outputs / both) で絞る<br>`-applies_to_boundary`: 境界の種類 (lower / upper / both) で絞る<br>`-applies_to_clamp`: ポートのクランプ値の要求 (`UPF_clamp_value` 属性) で絞る<br>`-no_isolation`: 対象ポートに分離セルを入れないことを指定する<br>`-force_isolation`: 分離セルに関する最適化を禁じる。冗長な分離や、浮き/定数のポートの分離も残す<br>`-location`: 分離セルを置く場所 (self: 分離するポートのドメイン、parent: 親のドメイン、other: 上側境界なら親・下側境界なら子のドメイン、fanout: 各ファンアウト先のドメイン)<br>`-clamp_value`: 分離中の出力値 (0 / 1 / Z / latch = 分離開始時の値を保持 / ポートの型に合う任意の値)。リストで複数書ける。省略すると `UPF_clamp_value` 属性の値を使う<br>`-isolation_signal`: 分離を有効にする制御信号 (ロジックネットまたはポート) のリスト<br>`-isolation_sense`: 各制御信号の有効レベル (high / low)<br>`-isolation_supply`: 分離セル (と制御信号を受ける論理) に給電する電源セットのリスト。空リスト {} を書くと、クランプ値に必要な側のレールで判定する<br>`-name_prefix`: 挿入する分離セルや関連ネットの名前に付ける接頭辞<br>`-name_suffix`: 挿入する分離セルや関連ネットの名前に付ける接尾辞<br>`-instance`: このストラテジを実装済みのセルのインスタンス名と、それが分離するポート名の組。インスタンス名に空文字列を書くと、最適化で消えたことを表す<br>`-async_set_reset`: 分離セルのセット/リセットとして働く制御信号 (ロジックネットまたはポート) とその有効レベル<br>`-async_clamp_value`: `-async_set_reset` の信号がセット (1) とリセット (0) のどちらとして働くか<br>`-update`: 同じスコープで先に実行した同じ名前・同じドメインのストラテジに情報を追加する<br>`-isolation_power_net`: 分離セルの power に使う電源ネット (旧方式。現在は `-isolation_supply`)<br>`-isolation_ground_net`: 分離セルの ground に使う電源ネット (旧方式。現在は `-isolation_supply`)<br>`-applies_to_sink_off_clamp`: 受け側の電源が落ちたときのクランプ要求で絞るフィルタ<br>`-applies_to_source_off_clamp`: 駆動側の電源が落ちたときのクランプ要求で絞るフィルタ | 分離 (isolation) ストラテジを定義する。電源ドメインの境界ポートのうち条件に合うものに、電源が落ちた側からの不定値を止める分離セルを入れる (検証では分離の動作を挿入したものとして扱う)。`-source` / `-sink` / `-diff_supply_only` / `-applies_to` / `-applies_to_clamp` は、対象ポートを絞るフィルタで、すべてを満たすポートにだけ適用される。分離の値・制御信号・電源はリストで複数組を書ける<br>**注:** `-clamp_value` / `-isolation_signal` / `-isolation_sense` / `-isolation_supply` をリストで書くときは長さをそろえる。同じ位置の要素が 1 組の分離要求になり、制御信号が有効な組のうち最も右の値が出力になる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 (一部レガシー・非推奨) |
| <a id="cmd-set_level_shifter"></a>`set_level_shifter`<br>★ よく使う (E.4 で 6 回)<br>[6.49 p.206](https://ieeexplore.ieee.org/document/10910082) | `strategy_name` (必須)<br>`-domain domain_name` (必須)<br>`-elements element_list` (任意、R)<br>`-exclude_elements exclude_list` (任意、R)<br>`-source <source_domain_name \| source_supply_ref>` (任意、R)<br>`-sink <sink_domain_name \| sink_supply_ref>` (任意、R)<br>`-use_functional_equivalence [<TRUE \| FALSE>]` (任意、R、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`)<br>`-applies_to <inputs \| outputs \| both>` (任意、R)<br>`-applies_to_boundary <lower \| upper \| both>` (任意、R、既定: `both`)<br>`-rule <low_to_high \| high_to_low \| both>` (任意、R、既定: `both`)<br>`-threshold <value>` (任意、R、既定: `0`)<br>`-no_shift` (任意、R)<br>`-force_shift` (任意、R)<br>`-location <self \| other \| parent \| fanout>` (任意、R、既定: `self`)<br>`-input_supply supply_set_ref` (任意、R)<br>`-output_supply supply_set_ref` (任意、R)<br>`-internal_supply supply_set_ref` (任意、R)<br>`-name_prefix pattern` (任意、R)<br>`-name_suffix pattern` (任意、R)<br>`-instance {{instance_name port_name}*}` (任意、R)<br>`-update` (任意、R) | `strategy_name`: レベルシフタストラテジの名前<br>`-domain`: このストラテジを定義する電源ドメイン<br>`-elements`: 適用候補にするインスタンスまたはポートのリスト<br>`-exclude_elements`: 適用しないインスタンスまたはポートのリスト<br>`-source`: 駆動側の電源 (電源セットまたはドメイン名) が一致するポートに絞る<br>`-sink`: 受け側の電源 (電源セットまたはドメイン名) が一致するポートに絞る<br>`-use_functional_equivalence`: 電源の一致判定で、機能的な等価を考慮するか<br>`-applies_to`: ドメインから見たポートの向き (inputs / outputs / both) で絞る<br>`-applies_to_boundary`: 境界の種類 (lower / upper / both) で絞る<br>`-rule`: 必要な変換の向き (`low_to_high` / `high_to_low` / both) で絞る<br>`-threshold`: 電圧差がこの値 (V) を超えるポートだけに絞る<br>`-no_shift`: 対象ポートにレベルシフタを入れないことを指定する<br>`-force_shift`: レベルシフタに関する最適化を禁じる<br>`-location`: レベルシフタを置く場所 (self / other / parent / fanout。意味は `set_isolation` と同じ)<br>`-input_supply`: レベルシフタの入力側に給電する電源セット<br>`-output_supply`: レベルシフタの出力側に給電する電源セット<br>`-internal_supply`: レベルシフタの内部回路に給電する電源セット<br>`-name_prefix`: 挿入するセルや関連ネットの名前に付ける接頭辞<br>`-name_suffix`: 挿入するセルや関連ネットの名前に付ける接尾辞<br>`-instance`: このストラテジを実装済みのセルのインスタンス名と、対象ポート名の組<br>`-update`: 先に実行した同じストラテジに情報を追加する | レベルシフタのストラテジを定義する。電圧の異なるドメインの境界ポートのうち条件に合うものに、レベルシフタを入れる。フィルタの考え方は `set_isolation` と同じで、さらに変換の向き (`-rule`) と電圧差のしきい値 (`-threshold`) で絞れる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-set_repeater"></a>`set_repeater`<br>[6.52 p.219](https://ieeexplore.ieee.org/document/10910082) | `strategy_name` (必須)<br>`-domain domain_name` (必須)<br>`-repeater_supply supply_set_ref` (必須、R)<br>`-elements element_list` (任意、R)<br>`-exclude_elements exclude_list` (任意、R)<br>`-source <source_domain_name \| source_supply_ref>` (任意、R)<br>`-sink <sink_domain_name \| sink_supply_ref>` (任意、R)<br>`-use_functional_equivalence [<TRUE \| FALSE>]` (任意、R、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`)<br>`-applies_to <inputs \| outputs \| both>` (任意、R)<br>`-applies_to_boundary <lower \| upper \| both>` (任意、R、既定: `both`)<br>`-name_prefix string` (任意、R)<br>`-name_suffix string` (任意、R)<br>`-instance {{instance_name port_name}*}` (任意、R)<br>`-update` (任意、R) | `strategy_name`: リピータストラテジの名前<br>`-domain`: このストラテジを定義する電源ドメイン<br>`-repeater_supply`: 挿入するバッファに給電する電源セット<br>`-elements`: 適用候補にするインスタンスまたはポートのリスト<br>`-exclude_elements`: 適用しないインスタンスまたはポートのリスト<br>`-source`: 駆動側の電源 (電源セットまたはドメイン名) が一致するポートに絞る<br>`-sink`: 受け側の電源 (電源セットまたはドメイン名) が一致するポートに絞る<br>`-use_functional_equivalence`: 電源の一致判定で、機能的な等価を考慮するか<br>`-applies_to`: ドメインから見たポートの向き (inputs / outputs / both) で絞る<br>`-applies_to_boundary`: 境界の種類 (lower / upper / both) で絞る<br>`-name_prefix`: 挿入するバッファや関連ネットの名前に付ける接頭辞<br>`-name_suffix`: 挿入するバッファや関連ネットの名前に付ける接尾辞<br>`-instance`: このストラテジを実装済みのセルのインスタンス名と、対象ポート名の組<br>`-update`: 先に実行した同じストラテジに情報を追加する | リピータ (バッファ) のストラテジを定義する。ドメインの境界ポートに、指定した電源セットで動くバッファを入れる (常時オンの電源で信号を中継する場合など) | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-set_retention"></a>`set_retention`<br>★ よく使う (E.4 で 1 回)<br>[6.53 p.222](https://ieeexplore.ieee.org/document/10910082) | `retention_name` (必須)<br>`-domain domain_name` (必須)<br>`-elements element_list` (任意、R)<br>`-exclude_elements exclude_list` (任意、R)<br>`-applies_to <flop \| latch \| any>` (任意、R、既定: `any`)<br>`-retention_supply ret_supply_set` (任意、R)<br>`-no_retention` (任意、R)<br>`-save_signal {logic_net <high \| low \| posedge \| negedge>}` (任意、R)<br>`-restore_signal {logic_net <high \| low \| posedge \| negedge>}` (任意、`-save_signal` と組、R)<br>`-save_event_condition {boolean_expression}` (任意、R、既定: 常に真)<br>`-restore_event_condition {boolean_expression}` (任意、R、既定: 常に真)<br>`-powerdown_period_condition {boolean expression}` (任意、R、既定: 常に真)<br>`-restore_period_condition {boolean expression}` (任意、R、既定: 常に真)<br>`-async_set_reset_effect <ignored \| retained_value \| output_value>` (任意、R、既定: `ignored`)<br>`-use_retention_as_primary` (任意、R)<br>`-parameters {<RET_SUP_COR \| NO_RET_SUP_COR \| SAV_RES_COR \| NO_SAV_RES_COR>*}` (任意、R、既定: `RET_SUP_COR` と `SAV_RES_COR`)<br>`-instance {{instance_name [signal_name]}*}` (任意、R)<br>`-update` (任意、R)<br>`-retention_power_net net_name` (任意、R、**レガシー**)<br>`-retention_ground_net net_name` (任意、R、**レガシー**)<br>`-save_condition {boolean_expression}` (任意、R、既定: `-save_signal` があれば真、なければ無関係、**レガシー**)<br>`-restore_condition {boolean_expression}` (任意、R、既定: `-restore_signal` があれば真、なければ無関係、**レガシー**)<br>`-retention_condition {boolean_expression}` (任意、R、**レガシー**) | `retention_name`: 保持ストラテジの名前<br>`-domain`: このストラテジを適用する電源ドメイン<br>`-elements`: 対象にする要素のリスト。インスタンス、`set_retention_elements` で作った要素リストの名前、名前付きプロセス、記憶素子、信号名を書ける<br>`-exclude_elements`: 対象から外す要素のリスト (書ける種類は `-elements` と同じ)<br>`-applies_to`: 対象にする記憶素子の種類 (flop / latch / any)<br>`-retention_supply`: 保持のために推論する論理に給電する電源セット<br>`-no_retention`: 対象の記憶素子に保持セルを推論しないことを指定する<br>`-save_signal`: 保存の制御信号 (ロジックネットまたはポート) と、有効レベルまたはエッジ (high / low / posedge / negedge)。`-restore_signal` と組で書く<br>`-restore_signal`: 復帰の制御信号と、有効レベルまたはエッジ<br>`-save_event_condition`: 保存を行うための追加条件の論理式<br>`-restore_event_condition`: 復帰を行うための追加条件の論理式<br>`-powerdown_period_condition`: 電源断の期間中に保持が成り立つための条件の論理式<br>`-restore_period_condition`: 復帰の期間中に成り立つべき条件の論理式<br>`-async_set_reset_effect`: 復帰期間中にセット/リセット信号が効いたときの扱い (ignored: 影響しない、`retained_value`: 保持値と出力が恒久的に変わる、`output_value`: 出力だけが一時的に変わる)<br>`-use_retention_as_primary`: 記憶素子とその出力を、保持電源で給電されるものとして扱う<br>`-parameters`: 保持レジスタの破壊の扱い。`RET_SUP_COR` / `NO_RET_SUP_COR` は保持電源が `CORRUPT` のときに通常レジスタを破壊するか、`SAV_RES_COR` / `NO_SAV_RES_COR` は保存と復帰の信号が同時に有効なときに破壊するか<br>`-instance`: このストラテジを実装済みの保持セルのインスタンス名と、任意でそれが保持する信号名の組。空文字列は最適化で消えたことを表す<br>`-update`: 先に実行した同じストラテジに情報を追加する<br>`-retention_power_net`: 保持論理の power に使う電源ネット (旧方式。現在は `-retention_supply`)<br>`-retention_ground_net`: 保持論理の ground に使う電源ネット (旧方式。現在は `-retention_supply`)<br>`-save_condition`: 保存の条件 (旧方式。現在は `-save_event_condition`)<br>`-restore_condition`: 復帰の条件 (旧方式。現在は `-restore_event_condition`)<br>`-retention_condition`: 保持の条件 (旧方式。現在は `-powerdown_period_condition`) | 保持 (retention) ストラテジを定義する。ドメインの電源を落としている間も、対象の記憶素子 (フリップフロップ・ラッチ) の値を保持電源で保つ。保存・復帰の制御信号と条件、保持電源、電源断中の破壊 (corruption) の扱いなどを指定する<br>**注:** 付属書 D の Table D.1 では、旧方式の `-retention_condition` を置き換えるときは `-save_signal` と `-restore_signal` が必須になるとしている | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 (一部レガシー) |
| <a id="cmd-set_retention_elements"></a>`set_retention_elements`<br>★ よく使う (E.4 で 2 回)<br>[6.54 p.230](https://ieeexplore.ieee.org/document/10910082) | `retention_list_name` (必須)<br>`-elements element_list` (必須)<br>`-applies_to <required \| optional \| not_required \| not_optional>` (任意)<br>`-exclude_elements exclude_list` (任意)<br>`-retention_purpose <required \| optional>` (任意、既定: `required`)<br>`-transitive [<TRUE \| FALSE>]` (任意、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`、**非推奨**) | `retention_list_name`: リストの名前 (カレントスコープで一意の識別子)<br>`-elements`: リストに入れる要素のリスト<br>`-applies_to`: `UPF_retention` 属性の値で要素を絞る (required / optional / `not_required` / `not_optional`)<br>`-exclude_elements`: リストから外す要素のリスト<br>`-retention_purpose`: このリストの保持の位置づけ (required / optional)<br>`-transitive`: 指定した要素の下の階層も含めるか (非推奨。現在は `TRUE` が既定で、子インスタンスを外すには `-exclude_elements` を使う) | 名前付きの要素リストを作る。リスト内のどれかに保持を適用するなら、リスト全体の状態をまとめて保持する必要があることを表す。`UPF_retention` 属性 (required / optional) で要素を絞れる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 (一部非推奨) |

<a id="cat-map"></a>

## セルの割り当て (5 件)

ストラテジや電源スイッチを、どのライブラリセル・機能モデルで実装するかを指定する

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-map_power_switch"></a>`map_power_switch`<br>[6.37 p.183](https://ieeexplore.ieee.org/document/10910082) | `switch_name_list` (必須)<br>`-lib_cells lib_cell_list` (必須)<br>`-port_map {{mapped_model_port switch_port_or_supply_net_ref}*}` (任意) | `switch_name_list`: 割り当てる電源スイッチ (`create_power_switch` で定義したもの) のリスト<br>`-lib_cells`: 使ってよいライブラリセルのリスト<br>`-port_map`: {セルのポート スイッチのポートまたは電源ネット} の組のリスト。スイッチ側には入力/出力電源ポート、制御ポート、ack ポート、または電源ネットを書ける | `create_power_switch` で定義した電源スイッチを、どのライブラリセル (またはモデル) で実装するかを指定する。セルのポートとスイッチのポート/電源ネットの対応も書ける | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-map_repeater_cell"></a>`map_repeater_cell`<br>[6.38 p.184](https://ieeexplore.ieee.org/document/10910082) | `repeater_strategy_name` (必須)<br>`-domain domain_name` (必須)<br>`-elements element_list` (任意)<br>`-exclude_elements exclude_list` (任意)<br>`-lib_cells lib_cell_list` (任意) | `repeater_strategy_name`: 対象のリピータストラテジ (`set_repeater` で定義したもの)<br>`-domain`: そのストラテジを定義した電源ドメイン<br>`-elements`: ストラテジの対象ポートのうち、この指定を適用するもの<br>`-exclude_elements`: ストラテジの対象ポートのうち、この指定を適用しないもの<br>`-lib_cells`: 使ってよいライブラリセルのリスト | `set_repeater` のストラテジで挿入するバッファに使ってよいライブラリセルを指定する。ストラテジの対象ポートの一部だけに適用することもできる | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-map_retention_cell"></a>`map_retention_cell`<br>[6.39 p.185](https://ieeexplore.ieee.org/document/10910082) | `retention_name_list` (必須)<br>`-domain domain_name` (必須)<br>`-elements element_list` (任意)<br>`-exclude_elements exclude_list` (任意)<br>`-lib_cells lib_cell_list` (任意)<br>`-lib_cell_type lib_cell_type` (任意)<br>`-lib_model_name name` (任意)<br>`-port_map {{port_name net_ref}*}` (任意、`-lib_model_name` と組) | `retention_name_list`: 対象の保持ストラテジ (`domain_name` で `set_retention` により定義したもの) のリスト<br>`-domain`: ストラテジを定義した電源ドメイン<br>`-elements`: この指定を適用する要素 (インスタンス・名前付きプロセス・記憶素子・信号) のリスト<br>`-exclude_elements`: この指定から外す要素のリスト<br>`-lib_cells`: 使ってよい保持セルのリスト (保持機能以外は元の RTL と同じ動作のもの)<br>`-lib_cell_type`: 保持セルを見分けるためのセルの属性 (`define_retention_cell` `-cell_type` で付けた種別)<br>`-lib_model_name`: 検証に使うライブラリセルまたは振る舞いモデルの名前。`-port_map` と組で書く<br>`-port_map`: モデルのポートと接続先 (`net_ref`) の組のリスト。接続先には論理ネット、電源ネット、`retention_supply`.関数名、`primary_supply`.関数名、`save_signal`、`restore_signal`、`UPF_GENERIC_CLOCK` などの定義済みの名前を書ける (\~ を前に付けると反転) | 保持ストラテジ (`set_retention`) で推論する保持レジスタの実装候補を絞る、または検証用の機能モデルを指定する。`-lib_cells` / `-lib_cell_type` / `-lib_model_name` の組み合わせで、検証に使う動作と実装の制約が決まる (6.39 の表)。モデルの端子は `-port_map` で、論理/電源ネットや `save_signal`・`restore_signal`・`UPF_GENERIC_CLOCK` などの定義済みの名前につなぐ<br>**注:** `-lib_cells`・`-lib_cell_type`・`-lib_model_name` のどれも書かないとエラー | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-map_retention_clamp_cell"></a>`map_retention_clamp_cell`<br>[6.40 p.189](https://ieeexplore.ieee.org/document/10910082) | `list_of_strategies` (必須)<br>`-domain domain_name` (必須)<br>`-clock_clamp_lib_cells list_of_clock_path_library_cells` (必須)<br>`-async_clamp_lib_cells list_of_async_path_library_cells` (必須) | `list_of_strategies`: 対象の保持ストラテジ名のリスト<br>`-domain`: それらのストラテジを定義した電源ドメイン<br>`-clock_clamp_lib_cells`: クロック経路のクランプに使うライブラリセルのリスト (空は不可)<br>`-async_clamp_lib_cells`: 非同期セット/リセット経路のクランプに使うライブラリセルのリスト (空は不可) | 保持ストラテジのために、クロック経路と非同期セット/リセット経路に入れるクランプセルの実装に使うライブラリセルを指定する。使えるのは分離セルか、イネーブル付きレベルシフタのセルだけ | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-use_interface_cell"></a>`use_interface_cell`<br>[6.62 p.244](https://ieeexplore.ieee.org/document/10910082) | `interface_implementation_name` (必須)<br>`-strategy list_of_isolation_level_shifter_strategies` (必須)<br>`-domain domain_name` (必須)<br>`-lib_cells lib_cell_list` (必須)<br>`-port_map {{port net_ref}*}` (任意)<br>`-elements element_list` (任意)<br>`-exclude_elements exclude_list` (任意)<br>`-applies_to_clamp <0 \| 1 \| Z \| latch \| value>` (任意)<br>`-force_function` (任意)<br>`-inverter_supply_set list` (任意) | `interface_implementation_name`: このインタフェースセル指定の名前<br>`-strategy`: 対象の分離ストラテジ、レベルシフタストラテジ、またはその組 (`set_isolation` / `set_level_shifter` で定義したもの)<br>`-domain`: ストラテジを定義した電源ドメイン<br>`-lib_cells`: 使ってよいライブラリセルのリスト<br>`-port_map`: セルのポートと接続先ネットの組のリスト<br>`-elements`: ストラテジの対象ポートのうち、この指定を適用するもの<br>`-exclude_elements`: ストラテジの対象ポートのうち、この指定を適用しないもの<br>`-applies_to_clamp`: 指定したクランプ値のポートだけに適用する<br>`-force_function`: `-lib_cells` の最初のモデルを、分離動作の機能仕様として使う<br>`-inverter_supply_set`: 分離制御信号の極性合わせに必要な反転論理に給電する電源セット | 分離・レベルシフタのストラテジ (または分離とレベルシフタの組) を実装するセルの候補と、検証で使う機能モデルを指定する。分離とレベルシフタを 1 つにした複合セルの指定にも使う | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |

<a id="cat-state"></a>

## 電源状態・状態遷移 (7 件)

電源・ドメイン・グループの電源状態と状態遷移を定義する (旧方式の PST を含む)

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-add_supply_state"></a>`add_supply_state`<br>[6.8 p.113](https://ieeexplore.ieee.org/document/10910082) | `object_name` (必須)<br>`-state {name <nom_voltage \| {net_state nom_voltage} \| off>}` (必須、複数回可) | `object_name`: 状態を定義する電源ポート/電源ネット/電源セット関数 (階層名も可)<br>`-state`: 状態名と値の組。値は公称電圧 (V)、{電源状態 公称電圧} (例: {`PARTIAL_ON` 0.8})、または off。1 つ以上書く | 電源ポート・電源ネット・電源セットの電源関数に、名前付きの電源状態 (公称電圧と状態、または off) を定義する。定義した状態名は `add_power_state` の `-supply_expr` などで参照する | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-add_power_state"></a>`add_power_state`<br>★ よく使う (E.4 で 38 回)<br>[6.5 p.103](https://ieeexplore.ieee.org/document/10910082) | `object_name` (必須)<br>`-supply` (任意、`-domain` / `-group` / `-model` / `-instance` と排他)<br>`-domain` (任意、`-supply` / `-group` / `-model` / `-instance` と排他)<br>`-group` (任意、`-supply` / `-domain` / `-model` / `-instance` と排他)<br>`-model` (任意、`-supply` / `-domain` / `-group` / `-instance` と排他)<br>`-instance` (任意、`-supply` / `-domain` / `-group` / `-model` と排他)<br>`-update` (任意、R)<br>`-state {state_name ...}` (任意、複数回可)<br>`-logic_expr {boolean_expression}` (任意、`-state` に付随、R)<br>`-supply_expr {boolean_expression}` (任意、`-state` に付随、R)<br>`-power_expr {power_expression}` (任意、`-state` に付随)<br>`-simstate simstate` (任意、`-state` に付随、R)<br>`-legal` (任意、`-illegal` と排他、`-state` に付随、R、既定: `-legal` / `-illegal` を書かなければ `-legal`)<br>`-illegal` (任意、`-legal` と排他、`-state` に付随、R)<br>`-complete` (任意、R) | `object_name`: 状態を定義するオブジェクトの単純名またはルート付きの名前<br>`-supply`: `object_name` を電源セット (または電源セットハンドル) として扱う<br>`-domain`: `object_name` を電源ドメインとして扱う<br>`-group`: `object_name` を電源状態グループ (`create_power_state_group`) として扱う<br>`-model`: `object_name` をモデルとして扱う (状態はそのモデルのインスタンスに引き継がれる)<br>`-instance`: `object_name` をインスタンスとして扱う<br>`-update`: 同じオブジェクトについて先に実行したコマンドに情報を追加する<br>`-state`: 定義または詳細化する電源状態。{状態名 オプション...} の形で、複数回書ける<br>`-logic_expr`: 状態の成立条件。ロジックネットや、他の電源セット/ドメインの電源状態を使った論理式<br>`-supply_expr`: 状態の成立条件。電源ポート/電源ネット/電源セット関数の状態や電圧を使った論理式<br>`-power_expr`: この状態での消費電力 (値、または電力を計算する関数)<br>`-simstate`: この状態でのシムステート (`NORMAL` / `CORRUPT_ON_CHANGE` / `CORRUPT_STATE_ON_CHANGE` / `CORRUPT_STATE_ON_ACTIVITY` / `CORRUPT_ON_ACTIVITY` / `CORRUPT` / `NOT_NORMAL`)。電源セットの状態に付ける<br>`-legal`: この状態を正当な状態として定義する<br>`-illegal`: この状態を不正な状態として定義する<br>`-complete`: 定義すべき基本の電源状態をすべて定義し終えたことを示す。以後、どの定義済み状態にも当たらない状態は不正になる | 電源セット・電源ドメイン・複合ドメイン・グループ・モデル・インスタンスの電源状態を定義する。各状態は、論理式 (`-logic_expr`) と電源の式 (`-supply_expr`) で成立条件を表し、電源セットの状態にはシムステート (シミュレーション時の振る舞い) を付ける。`-update` で後から式やシムステートを足せる。状態名を `抽象状態名.名前` と書くと、既存の状態を細分化した状態になる<br>**注:** `-supply` / `-domain` などの種別を書かなければ、どの種類のオブジェクトにも当てはまる (同じ名前のオブジェクトが複数あるとエラー) | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-add_state_transition"></a>`add_state_transition`<br>[6.7 p.111](https://ieeexplore.ieee.org/document/10910082) | `object_name` (必須)<br>`-supply` (任意、`-domain` / `-group` / `-model` / `-instance` と排他)<br>`-domain` (任意、`-supply` / `-group` / `-model` / `-instance` と排他)<br>`-group` (任意、`-supply` / `-domain` / `-model` / `-instance` と排他)<br>`-model` (任意、`-supply` / `-domain` / `-group` / `-instance` と排他)<br>`-instance` (任意、`-supply` / `-domain` / `-group` / `-model` と排他)<br>`-update` (任意、R)<br>`-transition {transition_name ...}` (任意、複数回可)<br>`-from from_list` (任意、`-transition` に付随、R)<br>`-to to_list` (任意、`-from` と組、`-transition` に付随、R)<br>`-paired {{from_state to_state}*}` (任意、`-transition` に付随、R)<br>`-legal` (任意、`-illegal` と排他、`-transition` に付随、R、既定: `-legal` / `-illegal` を書かなければ `-legal`)<br>`-illegal` (任意、`-legal` と排他、`-transition` に付随、R)<br>`-complete` (任意、R) | `object_name`: 遷移を定義するオブジェクト (ルート付きの名前)<br>`-supply`: `object_name` を電源セットとして扱う<br>`-domain`: `object_name` を電源ドメインとして扱う<br>`-group`: `object_name` を電源状態グループとして扱う<br>`-model`: `object_name` をモデルとして扱う<br>`-instance`: `object_name` をインスタンスとして扱う<br>`-update`: 同じオブジェクトについて先に実行したコマンドに情報を追加する<br>`-transition`: 定義する遷移。{遷移名 オプション...} の形で、複数回書ける<br>`-from`: 遷移前に有効な電源状態名のリスト (順不同)。`-to` と組で書く<br>`-to`: 遷移後に有効な電源状態名のリスト (順不同)<br>`-paired`: {遷移前の状態 遷移後の状態} の組のリスト<br>`-legal`: この遷移を正当な遷移として定義する<br>`-illegal`: この遷移を不正な遷移として定義する<br>`-complete`: 遷移をすべて定義し終えたことを示す | オブジェクトの電源状態の間の遷移に名前を付け、正当か不正かを定義する。遷移は `-from` / `-to` の状態リスト、または {遷移前 遷移後} の組のリストで書く | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-create_power_state_group"></a>`create_power_state_group`<br>★ よく使う (E.4 で 3 回)<br>[6.22 p.142](https://ieeexplore.ieee.org/document/10910082) | `group_name` (必須) | `group_name`: 作るグループの名前 (識別子) | 関連する電源状態をまとめるためのグループをカレントスコープに作る。グループの電源状態は `add_power_state` `-group` で定義する (複数ドメインの状態の組み合わせ = システムの動作モードを表す用途など) | 作ったグループの名前。作れなかったときは `TCL_ERROR` | 標準 |
| <a id="cmd-add_port_state"></a>`add_port_state`<br>[6.4 p.101](https://ieeexplore.ieee.org/document/10910082) | `port_name` (必須)<br>`-state {name <nom \| min max \| min nom max \| off>}` (必須、複数回可) | `port_name`: 状態を追加する電源ポート (階層名も可)<br>`-state`: 状態名と値の組。値は公称電圧、最小と最大の 2 値、最小・公称・最大の 3 値、または off。1 つ以上書く | 電源ポートに名前付きの状態 (電圧値または off) を追加する旧方式のコマンド。PST (`create_pst` / `add_pst_state`) と組で使っていた。現在は `add_supply_state` か `add_power_state` で書く (付属書 D の Table D.1) | 作成したポートのカレントスコープからの完全な名前。状態を追加できなかったときは `TCL_ERROR` | レガシー |
| <a id="cmd-add_pst_state"></a>`add_pst_state`<br>[6.6 p.110](https://ieeexplore.ieee.org/document/10910082) | `state_name` (必須)<br>`-pst table_name` (必須)<br>`-state supply_states` (必須) | `state_name`: 定義する状態の名前<br>`-pst`: 状態を追加する PST<br>`-state`: `create_pst` `-supplies` に並べた順の、各電源の状態名のリスト。\* はその電源を問わないことを表す | 電源状態表 (PST) に、設計全体の 1 つの状態 (各電源ネットの状態の組み合わせ) を追加する旧方式のコマンド。現在は `add_power_state` で書く (付属書 D の Table D.1) | 成功時は 1。失敗時は `TCL_ERROR` | レガシー |
| <a id="cmd-create_pst"></a>`create_pst`<br>[6.24 p.150](https://ieeexplore.ieee.org/document/10910082) | `table_name` (必須)<br>`-supplies supply_list` (必須) | `table_name`: PST の名前 (カレントスコープの識別子)<br>`-supplies`: 表に含める電源ネットまたは電源ポート (ルート付きの名前) のリスト | 電源状態表 (PST) を作る旧方式のコマンド。表に含める電源ネット/ポートの並びを決め、状態は `add_pst_state` で追加する。現在は `add_power_state` で書く (付属書 D の Table D.1) | 作成した PST の名前。作れなかったときは `TCL_ERROR` | レガシー |

<a id="cat-attr"></a>

## 属性 (2 件)

モデル・インスタンス・ポートに属性 (5.6 の定義済み属性を含む) を付ける

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-set_design_attributes"></a>`set_design_attributes`<br>★ よく使う (E.4 で 5 回)<br>[6.44 p.193](https://ieeexplore.ieee.org/document/10910082) | `-models model_list` (任意)<br>`-elements element_list` (任意)<br>`-exclude_elements exclude_list` (任意)<br>`-attribute {name value}` (任意、複数回可)<br>`-is_soft_macro [<TRUE \| FALSE>]` (任意、既定: 未指定なら `FALSE`、値なしで指定すると `TRUE`)<br>`-is_hard_macro [<TRUE \| FALSE>]` (任意、既定: 未指定なら `FALSE`、値なしで指定すると `TRUE`)<br>`-is_refinable_macro [<TRUE \| FALSE>]` (任意、既定: 未指定なら `FALSE`、値なしで指定すると `TRUE`)<br>`-is_power_aware_model [<TRUE \| FALSE>]` (任意、既定: 未指定なら `FALSE`、値なしで指定すると `TRUE`)<br>`-switch_cell_type <coarse_grain \| fine_grain>` (任意) | `-models`: 属性を付けるモデルのリスト<br>`-elements`: 属性を付ける要素 (インスタンス・名前付きプロセス・記憶素子・信号) のルート付きの名前のリスト<br>`-exclude_elements`: 対象から外す要素のリスト<br>`-attribute`: {属性名 値} の組。定義済み属性 (`UPF_retention` など) も利用者定義の属性も書ける。複数回書ける<br>`-is_soft_macro`: ソフトマクロとして扱うか (`-attribute` {`UPF_is_soft_macro` 値} と同じ)<br>`-is_hard_macro`: ハードマクロとして扱うか (`-attribute` {`UPF_is_hard_macro` 値} と同じ)<br>`-is_refinable_macro`: リファイナブルマクロとして扱うか (`-attribute` {`UPF_is_refinable_macro` 値} と同じ)<br>`-is_power_aware_model`: 電源の振る舞いをモデル自身が持つ (電力考慮済み) モデルとして扱うか (`-attribute` {`UPF_is_power_aware_model` 値} と同じ)<br>`-switch_cell_type`: モデルのスイッチセルの種類 (`coarse_grain` / `fine_grain`。`-attribute` {`UPF_switch_cell_type` 値} と同じ) | モデルまたはインスタンスに属性を付ける。定義済み属性 (5.6 の Table 7) のうち、マクロの扱い (ソフト/ハード/リファイナブル)、電力考慮済みモデルかどうか、スイッチセルの種類などは専用のオプションでも書ける。モデルは `-models`、インスタンスなどは `-elements` で指定する<br>**注:** 規格の Syntax 欄では `-is_refinable_macro` の値が `[TRUE\|FALSE>]` と書かれ、開き括弧 &lt; が欠けている | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-set_port_attributes"></a>`set_port_attributes`<br>★ よく使う (E.4 で 16 回)<br>[6.51 p.213](https://ieeexplore.ieee.org/document/10910082) | `-model name` (任意)<br>`-elements element_list` (任意)<br>`-exclude_elements element_exclude_list` (任意)<br>`-ports port_list` (任意)<br>`-exclude_ports port_exclude_list` (任意)<br>`-applies_to <inputs \| outputs \| inouts \| {<inputs \| outputs \| inouts>*}>` (任意)<br>`-attribute {name value}` (任意、複数回可)<br>`-clamp_value <0 \| 1 \| any \| Z \| latch \| value>` (任意)<br>`-async_clamp_value <0 \| 1>` (任意)<br>`-driver_supply supply_set_ref` (任意)<br>`-receiver_supply supply_set_ref` (任意)<br>`-literal_supply supply_set_ref` (任意)<br>`-pg_type pg_type_value` (任意)<br>`-related_power_port supply_port_name` (任意)<br>`-related_ground_port supply_port_name` (任意)<br>`-related_bias_ports supply_port_name_list` (任意)<br>`-feedthrough feedthrough_name` (任意)<br>`-unconnected` (任意)<br>`-is_analog` (任意)<br>`-is_isolated` (任意)<br>`-sink_off_clamp <0 \| 1 \| any \| Z \| latch \| value>` (任意、**非推奨**)<br>`-source_off_clamp <0 \| 1 \| any \| Z \| latch \| value>` (任意、**非推奨**) | `-model`: ポートに属性を付けるモジュールまたはライブラリセル。`.` はカレントスコープのモデル<br>`-elements`: ポートに属性を付けるインスタンスのリスト<br>`-exclude_elements`: 対象から外すインスタンスのリスト<br>`-ports`: 属性を付けるポートの単純名またはルート付きの名前のリスト<br>`-exclude_ports`: 対象から外すポートのリスト<br>`-applies_to`: 向きで対象を絞る (inputs / outputs / inouts、またはそのリスト)<br>`-attribute`: {属性名 値} の組。複数回書ける<br>`-clamp_value`: 分離するときに求めるクランプ値 (0 / 1 / any / Z / latch / 値)。`UPF_clamp_value` と同じ<br>`-async_clamp_value`: 非同期のクランプ値の要求 (0 / 1)。`UPF_async_clamp_value` と同じ<br>`-driver_supply`: ポートを駆動する側の電源セット。`UPF_driver_supply` と同じ (インスタンスのポートにだけ書ける)<br>`-receiver_supply`: ポートの信号を受ける側の電源セット。`UPF_receiver_supply` と同じ<br>`-literal_supply`: インスタンスのポートに定数をつないだとき、その定数を作る電源として扱う電源セット。`UPF_literal_supply` と同じ<br>`-pg_type`: ポートの `pg_type` (`primary_power` / `primary_ground` など)。`UPF_pg_type` と同じ<br>`-related_power_port`: このポートに関連する power の電源ポート。`UPF_related_power_port` と同じ<br>`-related_ground_port`: このポートに関連する ground の電源ポート。`UPF_related_ground_port` と同じ<br>`-related_bias_ports`: このポートに関連するバイアスの電源ポートのリスト。`UPF_related_bias_ports` と同じ<br>`-feedthrough`: 指定したポート同士が内部で直結 (フィードスルー) されていることを示す名前。`UPF_feedthrough` と同じ<br>`-unconnected`: 指定したポートが内部でどこにもつながっていないことを示す。`UPF_unconnected` `TRUE` と同じ<br>`-is_analog`: 指定したポートがアナログポートであることを示す。`UPF_is_analog` `TRUE` と同じ<br>`-is_isolated`: 指定したポートが内部で分離済みで、外側での分離が要らないことを示す。`UPF_is_isolated` `TRUE` と同じ<br>`-sink_off_clamp`: 受け側ドメインの一次電源が `NORMAL` でないときのクランプ要求<br>`-source_off_clamp`: 駆動側ドメインの一次電源が `NORMAL` でないときのクランプ要求 | モデルのポート、またはインスタンスのポートに属性を付ける。クランプ値の要求、駆動側/受け側の電源、`pg_type`、関連する電源ポートなど、定義済み属性 (5.6) の多くは専用のオプションでも書ける。モデルのポートは `-model` と `-ports`、インスタンスのポートは `-elements` または `-model` なしの `-ports` で指定する | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 (一部非推奨) |

<a id="cat-sim"></a>

## シミュレーション制御 (7 件)

シムステートの振る舞い、`PARTIAL_ON` の扱い、アサーション・破壊・initial ブロックの再実行、チェッカの挿入を制御する

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-set_simstate_behavior"></a>`set_simstate_behavior`<br>★ よく使う (E.4 で 1 回)<br>[6.56 p.232](https://ieeexplore.ieee.org/document/10910082) | `<ENABLE \| SIMSTATE_ONLY \| PORT_CORR_ONLY \| DISABLE>` (必須)<br>`-lib name` (任意)<br>`-models model_list` (任意)<br>`-elements element_list` (任意)<br>`-exclude_elements exclude_list` (任意) | `<ENABLE \| SIMSTATE_ONLY \| PORT_CORR_ONLY \| DISABLE>`: 振る舞いの種類。`ENABLE` はシムステートの意味づけを有効にし、ハードマクロならポート破壊も有効。`SIMSTATE_ONLY` はシムステートだけ、`PORT_CORR_ONLY` はポート破壊だけ (ハードマクロ専用)、`DISABLE` は両方無効<br>`-lib`: 対象のライブラリ名<br>`-models`: 対象のモデル名のリスト<br>`-elements`: 対象のインスタンスのリスト<br>`-exclude_elements`: 対象から外すインスタンスのリスト | モデルまたはインスタンスのシミュレーション時の振る舞い (シムステートによる破壊と、ハードマクロのポート破壊) を有効/無効にする。`UPF_simstate_behavior` 属性を設定するのと同じ。明示しなければ、電力考慮済みモデルは `DISABLE`、それ以外は `ENABLE` | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-load_simstate_behavior"></a>`load_simstate_behavior`<br>[6.34 p.180](https://ieeexplore.ieee.org/document/10910082) | `lib_name` (必須)<br>`-file file_list` (必須) | `lib_name`: 対象のライブラリ名 (ツール固有の名前)<br>`-file`: `set_simstate_behavior` コマンドを書いたファイルのリスト | ライブラリごとのシムステートの振る舞いの既定値を、`set_simstate_behavior` を書いたファイルから読み込む | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-set_partial_on_translation"></a>`set_partial_on_translation`<br>[6.50 p.212](https://ieeexplore.ieee.org/document/10910082) | `<OFF \| FULL_ON>` (必須) | `<OFF \| FULL_ON>`: `PARTIAL_ON` の代わりに使う値 | 電源の状態 `PARTIAL_ON` を、シミュレーションで `OFF` と `FULL_ON` のどちらとして扱うかを決める | 成功時は設定した変換の値。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-sim_assertion_control"></a>`sim_assertion_control`<br>[6.58 p.236](https://ieeexplore.ieee.org/document/10910082) | `-elements element_list` (任意)<br>`-exclude_elements exclude_list` (任意)<br>`-domain domain_name` (任意)<br>`-model model_name` (任意)<br>`-controlling_domain domain` (任意、`-control_expr` と排他、既定: そのアサーションを含むドメイン)<br>`-control_expr boolean_expression` (任意、`-controlling_domain` と排他、既定: `FALSE`)<br>`-type <reset \| suspend \| kill>` (任意、既定: `reset`)<br>`-transitive [<TRUE \| FALSE>]` (任意、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`) | `-elements`: 対象にするインスタンスまたはアサーションのリスト<br>`-exclude_elements`: 対象から外すインスタンスまたはアサーションのリスト<br>`-domain`: アサーションを探すドメイン<br>`-model`: アサーションを探すモジュール<br>`-controlling_domain`: 一次電源のシムステートで制御の有効/無効を決めるドメイン<br>`-control_expr`: 制御を有効にする論理式<br>`-type`: 制御の種類。suspend は有効な間だけ止める、reset は止めて内部状態も消す、kill は止めたまま再開しない<br>`-transitive`: 下の階層も対象にするか | 低電力検証中のアサーションの扱いを制御する。対象のアサーションを含むドメインの一次電源が `NORMAL` でない間 (または指定した式が真の間)、アサーションをリセット・一時停止・停止する | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-sim_corruption_control"></a>`sim_corruption_control`<br>[6.59 p.238](https://ieeexplore.ieee.org/document/10910082) | `-type <real \| integer \| seq \| comb \| port \| process>` (必須)<br>`-elements element_list` (任意)<br>`-exclude_elements exclude_list` (任意)<br>`-model model_name` (任意)<br>`-domain domain_name` (任意)<br>`-transitive [<TRUE \| FALSE>]` (任意、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`) | `-type`: 破壊を止める要素の種類 (real / integer / seq / comb / port / process)<br>`-elements`: 対象にする要素のリスト<br>`-exclude_elements`: 対象から外す要素のリスト<br>`-model`: 対象にする HDL モデル<br>`-domain`: 対象にするドメイン<br>`-transitive`: 下の階層も対象にするか | 電源断などによる破壊 (corruption) を、特定の要素や種類の要素について行わないようにする | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-sim_replay_control"></a>`sim_replay_control`<br>[6.60 p.241](https://ieeexplore.ieee.org/document/10910082) | `-elements element_list` (任意)<br>`-exclude_elements exclude_list` (任意)<br>`-model model_name` (任意)<br>`-domain domain_name` (任意)<br>`-controlling_domain domain` (任意、既定: その initial ブロックを含むドメイン)<br>`-transitive [<TRUE \| FALSE>]` (任意、既定: 未指定なら `TRUE`、値なしで指定しても `TRUE`) | `-elements`: 対象にする initial ブロックと階層インスタンスのリスト<br>`-exclude_elements`: 対象から外す initial ブロックと階層インスタンスのリスト<br>`-model`: initial ブロックを探すモジュール<br>`-domain`: initial ブロックを探すドメイン<br>`-controlling_domain`: 一次電源のシムステートで再実行のタイミングを決めるドメイン<br>`-transitive`: 下の階層も対象にするか | ドメインの電源が入り直したときに、もう一度実行する initial ブロックを指定する (電源投入時の初期化をシミュレーションで再現する) | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-bind_checker"></a>`bind_checker`<br>[6.12 p.119](https://ieeexplore.ieee.org/document/10910082) | `instance_name` (必須)<br>`-module checker_name` (必須)<br>`-elements element_list` (任意)<br>`-bind_to module` (任意)<br>`-arch name` (任意、`-bind_to` に付随)<br>`-ports {{port_name ref}*}` (任意)<br>`-parameters {{param_name param_value}*}` (任意) | `instance_name`: 各バインド先に作るチェッカのインスタンス名<br>`-module`: チェッカの SystemVerilog モジュール名。バインド先は SystemVerilog でも VHDL でもよい<br>`-elements`: バインド先のインスタンスのリスト<br>`-bind_to`: このモジュール (VHDL ならエンティティ) の全インスタンスをバインド先にする<br>`-arch`: `-bind_to` が VHDL のとき、対象のアーキテクチャ名<br>`-ports`: {チェッカのポート名 接続するオブジェクト} の組のリスト。接続先は、チェッカを置くスコープからの相対名で書く<br>`-parameters`: {パラメータ名 値} の組のリスト。SystemVerilog では parameter、VHDL では generic に設定する。値は定数 | 検証用のチェッカモジュール (SystemVerilog で書いたもの) を、デザインのコードを変えずに挿入する。SystemVerilog の bind の仕組みを使う。`-bind_to` を書けばそのモジュールのすべてのインスタンスに、書かなければカレントスコープにだけチェッカのインスタンスを作る | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |

<a id="cat-vcm"></a>

## 値の変換 (3 件)

UPF の電源の値と HDL のポートの値の変換方法 (VCM、旧方式の VCT) を定義する

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-create_vcm"></a>`create_vcm`<br>[6.30 p.161](https://ieeexplore.ieee.org/document/10910082) | `vcm_name` (必須)<br>`-table {{from_value to_value}*}` (任意)<br>`-hdl_type {<vhdl \| sv> [HDL_typename]}` (任意、`-table` と組、既定: 型名を省略すると、sv なら logic、vhdl なら `std_logic`)<br>`-conversion_direction <hdl2upf \| upf2hdl>` (任意、`-table` と組)<br>`-field field_name` (任意、`-table` に付随)<br>`-function hdl_package::function_name` (任意)<br>`-model model_name` (任意)<br>`-parameters {{param_name param_value}*}` (任意、`-model` に付随)<br>`-vcms ext_vcm_list` (任意) | `vcm_name`: 作る VCM の名前 (単純名)<br>`-table`: 変換表。{変換元の値 変換先の値} の組のリスト<br>`-hdl_type`: 変換表が扱う HDL の言語 (vhdl / sv) と型名。`-table` を書くときは必須、書かないときは書くとエラー<br>`-conversion_direction`: 変換の向き (hdl2upf: HDL から UPF、upf2hdl: UPF から HDL)。`-table` を書くときは必須<br>`-field`: 変換に使うネット型/データ型のフィールド名 (`-table` のときだけ書ける)<br>`-function`: 変換に使う HDL 関数 (`パッケージ名::関数名`。リストも可)<br>`-model`: 変換に使う HDL のモジュール (エンティティ) 名<br>`-parameters`: `-model` に渡すパラメータの {名前 値} の組のリスト<br>`-vcms`: 定義済みの VCM 名のリスト。複数の VCM を 1 つの名前で束ねて参照するために使う | VCM (値変換方式) を定義する。UPF の電源ネットの値 (状態と電圧) と、それにつなぐ HDL のポートの値 (logic など) の間の変換を、変換表 (`-table`)、HDL の関数 (`-function`)、HDL のモジュール (`-model`)、既存の VCM の束 (`-vcms`) のいずれかで表す。定義した VCM は `connect_supply_net` `-vcm` で使う。定義済みの VCM は付属書 B にある | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-create_hdl2upf_vct"></a>`create_hdl2upf_vct`<br>[6.18 p.131](https://ieeexplore.ieee.org/document/10910082) | `vct_name` (必須)<br>`-hdl_type {<vhdl \| sv> [typename]}` (必須)<br>`-table {{from_value to_value}*}` (必須) | `vct_name`: VCT の名前 (識別子)<br>`-hdl_type`: 変換元の HDL の言語 (vhdl / sv) と型名<br>`-table`: {HDL の値 UPF の状態値} の組のリスト | HDL の論理値を UPF の電源状態の値に変換する VCT (値変換表) を定義する旧方式のコマンド。現在は `create_vcm` `-conversion_direction` hdl2upf で書く (付属書 D の Table D.1) | 成功時は空文字列。失敗時は `TCL_ERROR` | レガシー |
| <a id="cmd-create_upf2hdl_vct"></a>`create_upf2hdl_vct`<br>[6.28 p.159](https://ieeexplore.ieee.org/document/10910082) | `vct_name` (必須)<br>`-hdl_type {<vhdl \| sv> [typename]}` (必須)<br>`-table {{from_value to_value}*}` (必須) | `vct_name`: VCT の名前 (識別子)<br>`-hdl_type`: 変換先の HDL の言語 (vhdl / sv) と型名<br>`-table`: {UPF の状態値 HDL の値} の組のリスト | UPF の電源ネットの値 (`supply_net_type`) を HDL の論理値に変換する VCT を定義する旧方式のコマンド。現在は `create_vcm` `-conversion_direction` upf2hdl で書く (付属書 D の Table D.1) | 成功時は空文字列。失敗時は `TCL_ERROR` | レガシー |

<a id="cat-model"></a>

## パワーモデル (5 件)

ハード IP などのパワーモデルを定義してインスタンスに適用する

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-define_power_model"></a>`define_power_model`<br>★ よく使う (E.4 で 2 回)<br>[6.31 p.170](https://ieeexplore.ieee.org/document/10910082) | `power_model_name` (必須)<br>`-for model_list` (任意)<br>`-implementation` (任意、R)<br>`-update` (任意、R)<br>`-complete` (任意、R)<br>`{UPF_commands}` (必須) | `power_model_name`: パワーモデルの名前 (識別子)<br>`-for`: このパワーモデルを当てはめるモデル (モジュール/セル) 名のリスト<br>`-implementation`: 追記する中身に、実装 UPF として許されたコマンドだけを許可する (4.9.1.1 の Table 1)<br>`-update`: 定義済みのパワーモデルに UPF コマンドを追記する<br>`-complete`: パワーモデルを完成扱いにして、以後の追記を禁止する<br>`{UPF_commands}`: パワーモデルの中身の UPF コマンド ({ } で囲む) | パワーモデル (ハード IP などの電力意図を UPF コマンドで書いたもの) を定義する。{ } の中に、そのモデルのスコープで解釈する UPF コマンドを書き、`apply_power_model` でインスタンスに適用する。`-update` で後から追記でき、`-complete` で以後の追記を禁止する | 成功時は 1。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-apply_power_model"></a>`apply_power_model`<br>★ よく使う (E.4 で 3 回)<br>[6.9 p.114](https://ieeexplore.ieee.org/document/10910082) | `power_model_name` (必須)<br>`-elements instance_name_list` (任意、R)<br>`-supply_map {{instance_scope_supply_set current_scope_supply_set}*}` (任意、R)<br>`-port_map {{instance_scope_port current_scope_net}*}` (任意、R)<br>`-parameters {{param_name param_value}*}` (任意)<br>`-update` (任意、R) | `power_model_name`: 適用するパワーモデル (`define_power_model` で定義したもの) の単純名<br>`-elements`: パワーモデルを適用するインスタンスのリスト<br>`-supply_map`: {インスタンス側の電源セット カレントスコープ側の電源セット} の組のリスト<br>`-port_map`: {インスタンス側のポート カレントスコープ側のネット} の組のリスト (ロジックポートと電源ポートの両方)<br>`-parameters`: {パラメータ名 値} の組のリスト。システムレベルのパラメータへの割り当てや、`add_parameter` で定義した Tcl パラメータの既定値の上書きに使う<br>`-update`: すでに適用したインスタンスに、外部との接続情報を追加する | 定義済みのパワーモデルをデザインのインスタンスに結び付け、モデル側のインタフェースの電源セット、ロジックポート、電源ポートを、カレントスコープの電源セットやネットにつなぐ。パラメータの値も渡せる | 成功時は 1。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-add_parameter"></a>`add_parameter`<br>★ よく使う (E.4 で 1 回)<br>[6.3 p.100](https://ieeexplore.ieee.org/document/10910082) | `parameter_name` (必須)<br>`-type <buildtime \| runtime \| rate>` (任意)<br>`-default value` (必須)<br>`-description string` (任意) | `parameter_name`: パラメータの名前 (パワーモデル内で一意)<br>`-type`: パラメータの種類 (buildtime: 実行中に変わらない、runtime: 実行中に変わる、rate: 頻度のように変わる量)<br>`-default`: パラメータの既定値。必ず書く<br>`-description`: パラメータの説明文 | パワーモデルの中で使うパラメータを定義する。`-type` を付けると、システムレベルの IP パワーモデル用の数値パラメータ (ビルド時に固定 / 実行時に変化 / 頻度として変化) になる。付けなければ、`apply_power_model` `-parameters` で上書きできる Tcl 変数になる | 成功時は 1。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-begin_power_model"></a>`begin_power_model`<br>[6.11 p.118](https://ieeexplore.ieee.org/document/10910082) | `power_model_name` (必須)<br>`-for model_list` (任意) | `power_model_name`: パワーモデルの名前 (単純名)<br>`-for`: このパワーモデルを当てはめるモデル名のリスト | パワーモデルの定義を始める旧方式のコマンド。`end_power_model` までの UPF コマンドがモデルの中身になる。現在は `define_power_model` で書く (付属書 D の Table D.1) | 成功時は 1。失敗時は `TCL_ERROR` | レガシー |
| <a id="cmd-end_power_model"></a>`end_power_model`<br>[6.32 p.173](https://ieeexplore.ieee.org/document/10910082) | なし | — | `begin_power_model` で始めたパワーモデルの定義を終える旧方式のコマンド。現在は `define_power_model` で書く (付属書 D の Table D.1) | 成功時は 1。失敗時は `TCL_ERROR` | レガシー |

<a id="cat-cell"></a>

## セル定義 (Clause 7) (6 件)

ライブラリセルを電源管理セル (常時オン・ダイオード・分離・レベルシフタ・電源スイッチ・保持) として定義する

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="cmd-define_always_on_cell"></a>`define_always_on_cell`<br>[7.2 p.248](https://ieeexplore.ieee.org/document/10910082) | `-cells cell_list` (必須)<br>`-power power_pin` (必須)<br>`-ground ground_pin` (必須)<br>`-power_switchable pin` (任意)<br>`-ground_switchable pin` (任意)<br>`-isolated_pins list_of_pin_lists` (任意)<br>`-enable expression_list` (任意、`-isolated_pins` に付随) | `-cells`: 常時オンセルとして扱うセルのリスト<br>`-power`: セルの power ピン。`-power_switchable` と一緒に書くと、スイッチされない側の power ピンを表す<br>`-ground`: セルの ground ピン。`-ground_switchable` と一緒に書くと、スイッチされない側の ground ピンを表す<br>`-power_switchable`: スイッチされる power 電源にレールでつなぐピン<br>`-ground_switchable`: スイッチされる ground 電源にレールでつなぐピン<br>`-isolated_pins`: 内部で分離されている入力ピンのリストのリスト。同じリストのピンは同じ分離制御で分離される<br>`-enable`: `-isolated_pins` の各リストに対応する分離制御の条件式のリスト。制御信号が要らない場合は空文字列 | 常時オン (always-on) セルとして使うライブラリセルを定義する。スイッチされる電源側のピンと、スイッチされない電源のピンを区別して指定する。内部で分離されている入力ピンとその制御条件も書ける | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-define_diode_clamp"></a>`define_diode_clamp`<br>[7.3 p.249](https://ieeexplore.ieee.org/document/10910082) | `-cells cell_list` (必須)<br>`-data_pins pin_list` (必須)<br>`-type <power \| ground \| both>` (任意)<br>`-power pin` (任意)<br>`-ground pin` (任意) | `-cells`: 対象のセルのリスト<br>`-data_pins`: ダイオードクランプが入っている入力ピンのリスト<br>`-type`: クランプダイオードの種類 (power: power 側、ground: ground 側、both: 両方)<br>`-power`: power ネットにつなぐセルのピン<br>`-ground`: ground ネットにつなぐセルのピン | クランプダイオード付きのセル、またはダイオード保護のあるセルの入力ピンを定義する | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-define_isolation_cell"></a>`define_isolation_cell`<br>[7.4 p.250](https://ieeexplore.ieee.org/document/10910082) | `-cells cell_list` (必須)<br>`-power power_pin` (任意)<br>`-ground ground_pin` (任意)<br>`-enable pin` (必須: `-enable` / `-pin_groups` / `-no_enable` のどれか 1 つ)<br>`-clamp_cell <high \| low>` (任意、`-enable` に付随)<br>`-pin_groups {{input_pin output_pin [enable_pin]}*}` (必須: `-pin_groups` / `-enable` / `-no_enable` のどれか 1 つ)<br>`-no_enable <high \| low \| hold>` (必須: `-no_enable` / `-enable` / `-pin_groups` のどれか 1 つ)<br>`-always_on_pins pin_list` (任意)<br>`-aux_enables ordered_pin_list` (任意)<br>`-power_switchable power_pin` (任意)<br>`-ground_switchable ground_pin` (任意)<br>`-valid_location <source \| sink \| on \| off \| any>` (任意、既定: `sink`)<br>`-non_dedicated` (任意) | `-cells`: 分離セルとして扱うセルのリスト<br>`-power`: セルの power ピン (マルチレールで `-power_switchable` と一緒に書くと、スイッチされない側)<br>`-ground`: セルの ground ピン (マルチレールで `-ground_switchable` と一緒に書くと、スイッチされない側)<br>`-enable`: 分離イネーブルピン。極性はライブラリのセル機能で決まる (クランプセルは別)<br>`-clamp_cell`: 論理機能を持たず、トランジスタ 1 個でネットを high / low に固定するクランプセルであることを示す<br>`-pin_groups`: 多ビットの分離セルの {入力ピン 出力ピン \[イネーブルピン\]} の組のリスト<br>`-no_enable`: イネーブルピンのない分離セルであることを示し、スイッチされる電源が落ちたときの出力 (high / low / hold) を指定する<br>`-always_on_pins`: スイッチされない電源に関係するセルのピンのリスト<br>`-aux_enables`: 追加の (補助の) イネーブルピンのリスト (順序付き)<br>`-power_switchable`: マルチレールの分離セルの、スイッチされる power ピン<br>`-ground_switchable`: マルチレールの分離セルの、スイッチされる ground ピン<br>`-valid_location`: 置いてよい場所。source: 駆動側の電源と同じ電源の場所、sink: 受け側の電源と同じ電源の場所、on: 駆動側か受け側と同じで、分離中に電源が落ちない場所、off: 駆動側か受け側と同じで、電源が落ちてもよい場所、any: どこでもよい<br>`-non_dedicated`: 電源管理用ではない通常のセルとしても使ってよいことを示す | 分離セルとして使うライブラリセルを定義する。イネーブルピンの指定 (`-enable`)、多ビットセルの入出力経路の組 (`-pin_groups`)、イネーブルなしのセル (`-no_enable`) のどれか 1 つを書く。マルチレールのセルでは、スイッチされる電源ピンとされない電源ピンを分けて書く。置いてよい場所 (`-valid_location`) も決める | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-define_level_shifter_cell"></a>`define_level_shifter_cell`<br>[7.5 p.252](https://ieeexplore.ieee.org/document/10910082) | `-cells cell_list` (必須)<br>`-input_voltage_range {{lower_bound upper_bound}*}` (任意)<br>`-output_voltage_range {{lower_bound upper_bound}*}` (任意)<br>`-ground_input_voltage_range {{lower_bound upper_bound}*}` (任意)<br>`-ground_output_voltage_range {{lower_bound upper_bound}*}` (任意)<br>`-direction <low_to_high \| high_to_low \| both>` (任意、既定: `low_to_high`)<br>`-input_power_pin power_pin` (任意)<br>`-output_power_pin power_pin` (任意)<br>`-input_ground_pin ground_pin` (任意)<br>`-output_ground_pin ground_pin` (任意)<br>`-ground ground_pin` (任意)<br>`-power power_pin` (任意)<br>`-enable pin` (任意、`-pin_groups` と排他)<br>`-pin_groups {{input_pin output_pin [enable_pin]}*}` (任意、`-enable` と排他)<br>`-valid_location <source \| sink \| either \| any>` (任意、既定: `sink`)<br>`-bypass_enable expression` (任意)<br>`-multi_stage integer` (任意) | `-cells`: レベルシフタとして扱うセルのリスト<br>`-input_voltage_range`: 扱える入力 (駆動側) の power 電圧の範囲 ({下限 上限} のリスト)。power をシフトするセルにだけ書く<br>`-output_voltage_range`: 扱える出力 (受け側) の power 電圧の範囲のリスト。power をシフトするセルにだけ書く<br>`-ground_input_voltage_range`: 扱える入力側の ground 電圧の範囲のリスト。ground をシフトするセルに書く<br>`-ground_output_voltage_range`: 扱える出力側の ground 電圧の範囲のリスト。ground をシフトするセルに書く<br>`-direction`: 変換の向き (`low_to_high` / `high_to_low` / both)<br>`-input_power_pin`: 入力側の power ピン (power シフト用、`-output_power_pin` と組)<br>`-output_power_pin`: 出力側の power ピン (power シフト用、`-input_power_pin` と組)<br>`-input_ground_pin`: 入力側の ground ピン (ground シフト用、`-output_ground_pin` と組)<br>`-output_ground_pin`: 出力側の ground ピン (ground シフト用、`-input_ground_pin` と組)<br>`-ground`: セルの ground ピン。power だけをシフトするセルで使い、`-input_ground_pin` / `-output_ground_pin` とは併用不可<br>`-power`: セルの power ピン。ground だけをシフトするセルで使い、`-input_power_pin` / `-output_power_pin` とは併用不可<br>`-enable`: 駆動側の電源が落ちて出力側だけ電源がある状態で、内部の浮きを防ぐイネーブルピン<br>`-pin_groups`: 多ビットのレベルシフタの {入力ピン 出力ピン \[イネーブルピン\]} の組のリスト<br>`-valid_location`: 置いてよい場所 (source / sink / either / any)<br>`-bypass_enable`: 電圧変換をバイパスしてバッファとして動く条件 (バイパスイネーブル入力ピンの簡単な式)<br>`-multi_stage`: 多段のレベルシフタで、この定義が何段目かを示す番号。N 段なら N 回定義する | レベルシフタとして使うライブラリセルを定義する。扱える入出力の電圧範囲、変換の向き、入力側/出力側の電源ピン、イネーブル (または多ビットの経路の組)、置いてよい場所、バイパスや多段構成を指定する。`-input_voltage_range` と `-ground_input_voltage_range` のどちらかは必ず書き、入力側を書いたら対応する出力側の範囲も同じ個数だけ書く<br>**注:** 規格の Arguments 欄では `-input_voltage_range` の先頭の `-` が抜けている (Syntax 欄では正しい) | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-define_power_switch_cell"></a>`define_power_switch_cell`<br>[7.6 p.258](https://ieeexplore.ieee.org/document/10910082) | `-cells cell_list` (必須)<br>`-type <footer \| header>` (必須)<br>`-stage_1_enable expression` (必須)<br>`-stage_1_output expression` (任意)<br>`-power_switchable power_pin` (必須: `-power_switchable` / `-ground_switchable` のどれか 1 つ)<br>`-power power_pin` (必須、`-power_switchable` と組)<br>`-ground_switchable ground_pin` (必須: `-ground_switchable` / `-power_switchable` のどれか 1 つ)<br>`-ground ground_pin` (必須、`-ground_switchable` と組)<br>`-stage_2_enable expression` (任意)<br>`-stage_2_output expression` (任意、`-stage_2_enable` に付随)<br>`-always_on_pins ordered_pin_list` (任意)<br>`-gate_bias_pin power_pin` (任意) | `-cells`: 電源スイッチとして扱うセルのリスト<br>`-type`: ヘッダ (header) かフッタ (footer) か<br>`-stage_1_enable`: 1 段目のスイッチを `ON` にする条件 (入力ピンの式)。2 段目もある場合は両方の式が真で `ON`、両方が偽で `OFF`<br>`-stage_1_output`: 1 段目のイネーブル入力をバッファまたは反転して出す出力ピンの式 (スイッチの連鎖をつなぐのに使う)<br>`-power_switchable`: ヘッダセルの出力側 (スイッチされる側) の power ピン<br>`-power`: セルの入力側の power ピン<br>`-ground_switchable`: フッタセルの出力側 (スイッチされる側) の ground ピン<br>`-ground`: セルの入力側の ground ピン<br>`-stage_2_enable`: 2 段目のスイッチを `ON` にする条件<br>`-stage_2_output`: 2 段目のイネーブル入力をバッファまたは反転して出す出力ピンの式<br>`-always_on_pins`: 入力側の power / ground に関係するセルのピンのリスト (順序付き)<br>`-gate_bias_pin`: スイッチのゲート駆動に使う電源を受ける power ピン | 電源スイッチ (ヘッダ) またはグランドスイッチ (フッタ) として使うライブラリセルを定義する。1 段目 (と 2 段目) のイネーブル条件で `ON` / `OFF` が決まる。{`-power_switchable` と `-power`} か {`-ground_switchable` と `-ground`} のどちらかの組を書く<br>**注:** 規格の Syntax 欄は {...} の中の閉じ括弧が `]}` となっている | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |
| <a id="cmd-define_retention_cell"></a>`define_retention_cell`<br>[7.7 p.260](https://ieeexplore.ieee.org/document/10910082) | `-cells cell_list` (必須)<br>`-power power_pin` (必須)<br>`-ground ground_pin` (必須)<br>`-cell_type string` (任意)<br>`-always_on_pins pin_list` (任意)<br>`-restore_function {{pin <high \| low \| posedge \| negedge>}}` (任意、既定: 書かなければ、一次電源が戻ったとき (電源投入時) に復帰する)<br>`-save_function {{pin <high \| low \| posedge \| negedge>}}` (任意、既定: 書かなければ、`-restore_function` の否定で保存する。どちらも書かなければ、保持モードに入る前に常に保存する)<br>`-restore_check expression` (任意)<br>`-save_check expression` (任意)<br>`-retention_check expression` (任意)<br>`-hold_check pin_list` (任意)<br>`-always_on_components component_list` (任意)<br>`-power_switchable power_pin` (任意)<br>`-ground_switchable ground_pin` (任意) | `-cells`: 保持セルとして扱うセルのリスト<br>`-power`: セルの power ピン。`-power_switchable` と一緒に書くと、スイッチされない側の power ピンを表す<br>`-ground`: セルの ground ピン。`-ground_switchable` と一緒に書くと、スイッチされない側の ground ピンを表す<br>`-cell_type`: 同じ保持の振る舞いを持つセルの種別名 (利用者が決める名前)。`map_retention_cell` `-lib_cell_type` で選ぶのに使う<br>`-always_on_pins`: スイッチされない電源に関係するセルのピンのリスト<br>`-restore_function`: 復帰ピンとその極性またはエッジ (high / low / posedge / negedge)<br>`-save_function`: 保存ピンとその極性またはエッジ<br>`-restore_check`: 復帰してよい追加条件 (セルの入力ピンの式)<br>`-save_check`: 保存してよい追加条件 (セルの入力ピンの式)<br>`-retention_check`: 電源断中に保持が成功するための追加条件<br>`-hold_check`: 保存から復帰までの間、同じ論理値を保つべきピン (クロックなど) のリスト<br>`-always_on_components`: シミュレーションモデルの中で、スイッチされない電源で動く要素 (インスタンス・プロセス・記憶素子・信号) のリスト<br>`-power_switchable`: スイッチされる power ピン (ヘッダで電源を切るドメインで使うセル)<br>`-ground_switchable`: スイッチされる ground ピン (フッタで電源を切るドメインで使うセル) | 状態保持 (retention) セルとして使うライブラリセルを定義する。保存・復帰のピンの極性やエッジ、保存・復帰・保持の追加条件、保持期間中に値を保つべきピン、スイッチされない電源で動く内部要素などを指定する<br>**注:** 規格の Syntax 欄では `-restore_function` / `-save_function` の値の閉じ括弧 &gt; が抜けている | 成功時は空文字列。失敗時は `TCL_ERROR` | 標準 |

<a id="cat-tcl"></a>

## Tcl 問合せコマンド (11.1) (5 件)

情報モデル (Clause 10) のオブジェクトとプロパティを Tcl から調べる。処理の第 5 段階でだけ使える

| コマンド | オプション | オプションの意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="tcl-upf_query_object_properties"></a>`upf_query_object_properties`<br>[11.1.2.1 p.362](https://ieeexplore.ieee.org/document/10910082) | `object_handle` (必須)<br>`-property property_name` (任意) | `object_handle`: 問い合わせるオブジェクトの UPF ハンドル (例: /top/`dut_i`/pd.`iso_strategy`)<br>`-property`: 問い合わせるプロパティ名 (`upf_name` など)。省略すると全プロパティ | 情報モデル (Clause 10) のオブジェクトのプロパティを Tcl から問い合わせる。11.1 のコマンドは処理の第 5 段階 (8.3.6) でだけ使え、その段階で使える UPF コマンドは `set_scope` / `bind_checker` / `find_objects` / `load_upf` だけになる | `-property` を付けたときはその値 (なければ空文字列)。付けないときは全プロパティの {名前 値} の組のリスト | 標準 |
| <a id="tcl-upf_query_object_type"></a>`upf_query_object_type`<br>[11.1.2.2 p.363](https://ieeexplore.ieee.org/document/10910082) | `object_handle` (必須) | `object_handle`: 調べるオブジェクトの UPF ハンドル | オブジェクトのクラス (種類) を表すキーワードを返す | クラスを表すキーワード。情報モデルにないオブジェクトなら空文字列 | 標準 |
| <a id="tcl-upf_object_in_class"></a>`upf_object_in_class`<br>[11.1.2.3 p.364](https://ieeexplore.ieee.org/document/10910082) | `object_handle` (必須)<br>`-class <CLASS_ID>` (必須) | `object_handle`: 調べるオブジェクトの UPF ハンドル<br>`-class`: クラス ID (オブジェクトのクラス所属として有効なもの) | オブジェクトが指定したクラスに属するかを調べる | 属していれば 1、そうでなければ 0 | 標準 |
| <a id="tcl-upf_query_object_pathname"></a>`upf_query_object_pathname`<br>[11.1.2.4 p.365](https://ieeexplore.ieee.org/document/10910082) | `object_handle` (必須)<br>`-relative_to <object handle>` (任意、既定: `upf_null` (絶対パス)) | `object_handle`: パス名を求めるオブジェクトの UPF ハンドル<br>`-relative_to`: 相対パスの基準にする祖先オブジェクトのハンドル。省略時は `upf_null` で、絶対パスを返す | ハンドルが指すオブジェクトの階層パス名を返す | RTL の階層パス名の文字列。エラー時は空文字列 | 標準 |
| <a id="tcl-query_upf"></a>`query_upf`<br>[11.1.3.2 p.366](https://ieeexplore.ieee.org/document/10910082) | `<domain_name \| scope>` (必須)<br>`-pattern search_pattern` (必須)<br>`-object_type <inst \| port \| supply_port \| net \| supply_net \| supply_set>` (任意)<br>`-inst_type <level_shifter \| isolation_cell \| switch_cell \| retention_cell \| all>` (任意、既定: `all`)<br>`-direction <in \| out \| inout>` (任意)<br>`-transitive [<TRUE \| FALSE>]` (任意、既定: 未指定なら `FALSE`、値なしで指定すると `TRUE`)<br>`-regexp` (任意、`-exact` と排他)<br>`-exact` (任意、`-regexp` と排他)<br>`-ignore_case` (任意)<br>`-non_leaf` (任意、`-leaf_only` と排他)<br>`-leaf_only` (任意、`-non_leaf` と排他) | `<domain_name \| scope>`: 探す範囲にする電源ドメインまたはスコープ<br>`-pattern`: 探す名前のパターン。何も付けなければ Tcl の glob 形式<br>`-object_type`: 返すオブジェクトの種類 (inst / port / `supply_port` / net / `supply_net` / `supply_set`)。省略時はすべて<br>`-inst_type`: inst のとき、インスタンスの種類で絞る (`level_shifter` / `isolation_cell` / `switch_cell` / `retention_cell` / all)<br>`-direction`: port のとき、向き (in / out / inout) で絞る<br>`-transitive`: `TRUE` なら下の階層もたどって探す<br>`-regexp`: パターンを正規表現として扱う<br>`-exact`: パターンのワイルドカードを展開しない<br>`-ignore_case`: 大文字と小文字を区別しない<br>`-non_leaf`: 末端でないインスタンスだけを返す<br>`-leaf_only`: 末端のインスタンスだけを返す | UPF で作られたり推論されたりしたオブジェクト (挿入された分離セルなど) も含めて、論理階層からパターンに合うオブジェクトを探す。電源ドメインを指定すると、その中だけを探す<br>**注:** 規格の Syntax 欄では `-inst_type` と `-direction` の間に余分な `\|` がある | 見つかったオブジェクトの名前 (カレントスコープからの相対名) のリスト。見つからなければ空文字列 | 標準 |

<a id="cat-hdl"></a>

## HDL アクセス関数 (11.2.3) (25 件)

テストベンチやチェッカの HDL から情報モデルを読み書きする関数 (電源の投入・遮断を含む)

| 関数 | 引数 | 引数の意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="hdl-upf_get_handle_by_name"></a>`upf_get_handle_by_name()`<br>[11.2.3.1.1 p.383](https://ieeexplore.ieee.org/document/10910082) | `upfStringT pathname` (必須)<br>`upfHandleT relative_to = upf_null` (任意、省略時 `upf_null`) | `pathname`: オブジェクトのハンドル ID を表す文字列 (例: `/top/dut_i/pd`)<br>`relative_to`: 相対パスの基準にするオブジェクトのハンドル | パス名 (ハンドル ID。10.3.2) から情報モデルのオブジェクトのハンドルを得る。`relative_to` を渡すと、そのオブジェクトからの相対パスとして解釈する | `upfHandleT`: オブジェクトのハンドル。見つからなければ `upf_null` | 標準 |
| <a id="hdl-upf_query_object_properties"></a>`upf_query_object_properties()`<br>[11.2.3.1.2 p.383](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT object_handle` (必須)<br>`upfPropertyIdE attr` (必須) | `object_handle`: 対象オブジェクトのハンドル<br>`attr`: プロパティを表す列挙値 (`UPF_CURRENT_VALUE` など) | オブジェクトのハンドルと、プロパティ ID (`upfPropertyIdE` の列挙値) から、そのプロパティのハンドルを得る。値は `upf_get_value_`\* で読む | `upfHandleT`: プロパティのハンドル。見つからなければ `upf_null` | 標準 |
| <a id="hdl-upf_iter_get_next"></a>`upf_iter_get_next()`<br>[11.2.3.1.3 p.385](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT iter_handle` (必須) | `iter_handle`: 反復子のハンドル | リスト型のプロパティ (反復子) から、次の要素のハンドルを取り出す | `upfHandleT`: 次の要素のハンドル。要素が残っていなければ 0 | 標準 |
| <a id="hdl-upf_get_value_str"></a>`upf_get_value_str()`<br>[11.2.3.2.2 p.386](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT attr` (必須) | `attr`: プロパティのハンドル | プロパティのハンドルから文字列の値を読む | `upfStringT`: 文字列の値。エラー時は空文字列 | 標準 |
| <a id="hdl-upf_get_value_int"></a>`upf_get_value_int()`<br>[11.2.3.2.3 p.387](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT attr` (必須) | `attr`: プロパティのハンドル | プロパティのハンドルから整数の値を読む。列挙型のプロパティは位置の値が返るので、列挙子に変換して使う | `upfIntegerT`: 整数の値 | 標準 |
| <a id="hdl-upf_get_value_real"></a>`upf_get_value_real()`<br>[11.2.3.2.4 p.388](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT attr` (必須) | `attr`: プロパティのハンドル | プロパティのハンドルから実数の値を読む | `upfRealT`: 実数の値 | 標準 |
| <a id="hdl-upf_get_label_upfSupplyTypeT"></a>`upf_get_label_upfSupplyTypeT()`<br>[11.2.3.2.5 p.388](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT attr` (必須) | `attr`: プロパティのハンドル | 電源の値を持つプロパティのハンドルから、`upfSupplyTypeT` (状態と電圧の組) の値を読む | `upfSupplyTypeT`: `upfSupplyTypeT` の値 | 標準 |
| <a id="hdl-get_supply_value"></a>`get_supply_value()`<br>[11.2.3.2.6 p.389](https://ieeexplore.ieee.org/document/10910082) | `string name` (必須) | `name`: 電源ネット (または電源ポート) のパス名 | 電源ポート/電源ネットの現在の値 (状態と電圧の組) を名前で読む | `upfSupplyTypeT`: `upfSupplyTypeT` の値 | 標準 |
| <a id="hdl-get_supply_voltage"></a>`get_supply_voltage()`<br>[11.2.3.2.7 p.390](https://ieeexplore.ieee.org/document/10910082) | `upfSupplyTypeT arg` (必須) | `arg`: `upfSupplyTypeT` の値 | `upfSupplyTypeT` の値から電圧 (V) を取り出す | `upfRealT`: 電圧 (実数、V) | 標準 |
| <a id="hdl-get_supply_on_state"></a>`get_supply_on_state()`<br>[11.2.3.2.8 p.391](https://ieeexplore.ieee.org/document/10910082) | `upfSupplyTypeT arg` (必須) | `arg`: `upfSupplyTypeT` の値 | `upfSupplyTypeT` の値が `ON` かどうかを返す。`FULL_ON` なら 1。`PARTIAL_ON` は `set_partial_on_translation` `FULL_ON` が指定されているときだけ 1 | `upfBooleanT`: `ON` なら 1、それ以外は 0 | 標準 |
| <a id="hdl-get_supply_state"></a>`get_supply_state()`<br>[11.2.3.2.9 p.392](https://ieeexplore.ieee.org/document/10910082) | `upfSupplyTypeT arg` (必須) | `arg`: `upfSupplyTypeT` の値 | `upfSupplyTypeT` の値から電源の状態 (`OFF` / `UNDETERMINED` / `PARTIAL_ON` / `FULL_ON`) を取り出す | `upfSupplyStateE`: `upfSupplyStateE` の値 | 標準 |
| <a id="hdl-upf_set_value_int"></a>`upf_set_value_int()`<br>[11.2.3.3.2 p.393](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT attr` (必須)<br>`upfIntegerT value` (必須) | `attr`: プロパティのハンドル<br>`value`: 書く値 | 動的なプロパティ (シミュレーション中に変わるもの) に整数の値を書く | `upfBooleanT`: 成功時 1、失敗時 0 | 標準 |
| <a id="hdl-upf_set_value_upfSupplyTypeT"></a>`upf_set_value_upfSupplyTypeT()`<br>[11.2.3.3.3 p.394](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT attr` (必須)<br>`upfSupplyTypeT value` (必須) | `attr`: プロパティのハンドル<br>`value`: 書く `upfSupplyTypeT` の値 | 動的なプロパティに `upfSupplyTypeT` (状態と電圧) の値を書く | `upfBooleanT`: 成功時 1、失敗時 0 | 標準 |
| <a id="hdl-supply_on"></a>`supply_on()`<br>[11.2.3.3.4 p.395](https://ieeexplore.ieee.org/document/10910082) | `string supply_name` (必須)<br>`real value = 1.0` (任意、省略時 `1.0`) | `supply_name`: ルートの電源のパス名<br>`value`: 電圧 (V) | ルートの電源 (電源ポートなど) を `FULL_ON` にし、電圧を設定する。テストベンチから電源を投入するときに使う | `upfBooleanT`: 成功時 1、失敗時 0 | 標準 |
| <a id="hdl-supply_off"></a>`supply_off()`<br>[11.2.3.3.5 p.396](https://ieeexplore.ieee.org/document/10910082) | `upfStringT supply_name` (必須) | `supply_name`: ルートの電源の階層パス ID | ルートの電源を `OFF` にする | `upfBooleanT`: 成功時 1、失敗時 0 | 標準 |
| <a id="hdl-supply_partial_on"></a>`supply_partial_on()`<br>[11.2.3.3.6 p.397](https://ieeexplore.ieee.org/document/10910082) | `upfStringT supply_name` (必須)<br>`upfRealT value = 1.0` (任意、省略時 `1.0`) | `supply_name`: ルートの電源のパス名<br>`value`: 電圧 (V) | ルートの電源を `PARTIAL_ON` にし、電圧を設定する | `upfBooleanT`: 成功時 1、失敗時 0 | 標準 |
| <a id="hdl-set_supply_state"></a>`set_supply_state()`<br>[11.2.3.3.7 p.399](https://ieeexplore.ieee.org/document/10910082) | `upfStringT object_name` (必須)<br>`upfSupplyStateE supply_state` (必須) | `object_name`: 電源ポート/電源ネット/電源セット関数の階層パス ID<br>`supply_state`: 設定する状態 (`upfSupplyStateE` の値) | 名前で指定した電源ポート/電源ネット/電源セット関数の状態を設定する | `upfBooleanT`: 成功時 1、失敗時 0 | 標準 |
| <a id="hdl-set_power_state_by_handle"></a>`set_power_state_by_handle()`<br>[11.2.3.3.8 p.400](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT object` (必須)<br>`upfHandleT power_state` (必須) | `object`: UPF オブジェクトのハンドル<br>`power_state`: そのオブジェクトにある電源状態のハンドル | オブジェクトの電源状態を、ハンドルで指定した状態に変える (その状態を有効にする) | `bit`: 成功時 1、失敗時 0 | 標準 |
| <a id="hdl-set_power_state"></a>`set_power_state()`<br>[11.2.3.3.9 p.401](https://ieeexplore.ieee.org/document/10910082) | `string object` (必須)<br>`string power_state` (必須) | `object`: 電源状態を持つオブジェクトの階層パス ID<br>`power_state`: オブジェクトから見た電源状態の相対パス ID (状態名) | パス名で指定したオブジェクトの電源状態を、名前で指定した状態に変える | `upfBooleanT`: 成功時 1、失敗時 0 | 標準 |
| <a id="hdl-upf_create_object_mirror"></a>`upf_create_object_mirror()`<br>[11.2.3.4.2 p.402](https://ieeexplore.ieee.org/document/10910082) | `upfStringT src` (必須)<br>`upfStringT dst` (必須) | `src`: 監視するコピー元オブジェクトの階層パス ID<br>`dst`: 値を写すコピー先オブジェクトの階層パス ID | 動的なプロパティを継続的に監視し、変化をコピー先へ写すミラー関係を作る。UPF のオブジェクトと HDL の変数を結び付けるのに使う | `upfBooleanT`: ミラーを作れたら 1、そうでなければ 0 | 標準 |
| <a id="hdl-upf_query_object_type"></a>`upf_query_object_type()`<br>[11.2.3.5.1 p.404](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT handle` (必須) | `handle`: オブジェクトまたはプロパティのハンドル | オブジェクト (またはプロパティ) のハンドルから、クラス ID を得る | `upfClassIdE`: クラスを表す `upfClassIdE` の値 | 標準 |
| <a id="hdl-upf_object_in_class"></a>`upf_object_in_class()`<br>[11.2.3.5.2 p.405](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT handle` (必須)<br>`upfClassIdE class_id` (必須) | `handle`: オブジェクトまたはプロパティのハンドル<br>`class_id`: クラスを表す `upfClassIdE` の値 | ハンドルが指定したクラスに属するかを調べる | `upfBooleanT`: 属していれば 1、そうでなければ 0 | 標準 |
| <a id="hdl-upf_query_object_pathname"></a>`upf_query_object_pathname()`<br>[11.2.3.5.3 p.405](https://ieeexplore.ieee.org/document/10910082) | `upfHandleT object` (必須)<br>`upfHandleT relative_to = upf_null` (任意、省略時 `upf_null`) | `object`: 対象のオブジェクトのハンドル<br>`relative_to`: 相対パスの基準にするオブジェクトのハンドル。省略すると絶対パス | ハンドルが指すオブジェクトの階層パス名を返す | `upfStringT`: 階層パス名 | 標準 |
| <a id="hdl-upf_convert_real_volts_to_int_uvolts"></a>`upf_convert_real_volts_to_int_uvolts()`<br>[11.2.3.5.4 p.406](https://ieeexplore.ieee.org/document/10910082) | `upfRealT volt` (必須) | `volt`: 電圧 (実数、V) | 実数の電圧 (V) を、整数のマイクロボルトに変換する (情報モデルの電圧は整数の µV で持つ) | `upfIntegerT`: 電圧 (整数、µV) | 標準 |
| <a id="hdl-upf_convert_int_uvolts_to_real_volts"></a>`upf_convert_int_uvolts_to_real_volts()`<br>[11.2.3.5.5 p.407](https://ieeexplore.ieee.org/document/10910082) | `upfIntegerT uvolt` (必須) | `uvolt`: 電圧 (整数、µV) | 整数のマイクロボルトを、実数の電圧 (V) に変換する | `upfRealT`: 電圧 (実数、V) | 標準 |

<a id="cat-hdlpkg"></a>

## HDL パッケージの型・列挙・解決関数 (34 件)

11.2 の UPF パッケージ (SystemVerilog / VHDL) で定義される型・列挙・電源ネットの解決関数

| 名前 | 値・書き方 | 値の意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="val-hdlpkg-UPF_SystemVerilog"></a>`UPF (SystemVerilog)`<br>[11.2.4 p.408](https://ieeexplore.ieee.org/document/10910082) | `import UPF::*;` | パッケージ名 UPF | 電源の型 (`supply_net_type` / `upfSupplyTypeT`)、情報モデルの型と列挙、11.2.3 のアクセス関数、電源ネットの解決関数をまとめた SystemVerilog パッケージ。テストベンチやチェッカで `supply_on` / `supply_off` などを使うときに読み込む。コードは IEEE SA Open UPF リポジトリ (1.6) からも入手できる | — | 標準 |
| <a id="val-hdlpkg-UPF_VHDL"></a>`UPF (VHDL)`<br>[11.2.5 p.426](https://ieeexplore.ieee.org/document/10910082) | use work.UPF.all; など (ライブラリはツールによる) | パッケージ名 UPF | SystemVerilog 版と同じ内容を VHDL で定義したパッケージ。IEEE.`std_logic_1164` と IEEE.`numeric_bit` を使う | — | 標準 |
| <a id="val-hdlpkg-upfStringT"></a>`基本型 (upfStringT など)`<br>[11.2.2.1 p.372](https://ieeexplore.ieee.org/document/10910082) | `upfStringT / upfIntegerT / upfBooleanT / upfRealT / upfLogicT / upfHandleT / upfIteratorT` | SV ではそれぞれ string / int / bit / real / logic / int / int、VHDL では string / integer / bit / real / `std_logic` / integer / integer | 情報モデルのプロパティを HDL で扱うための型。ハンドル (`upfHandleT`) と反復子 (`upfIteratorT`) の値の付け方はツールに任されている | — | 標準 |
| <a id="val-hdlpkg-upfSupplyTypeT"></a>`upfSupplyTypeT`<br>[11.2.2.2 p.373](https://ieeexplore.ieee.org/document/10910082) | `struct { upfSupplyStateE state; upfIntegerT voltage; }` | state: 電源の状態 (`OFF` / `UNDETERMINED` / `PARTIAL_ON` / `FULL_ON`)、voltage: 電圧 (整数の µV) | 電源ポート/電源ネットの現在の値を表す型。HDL 側で宣言した電源ネットはこの型 (または `supply_net_type`) にする | — | 標準 |
| <a id="val-hdlpkg-supply_net_type"></a>`supply_net_type`<br>[11.2.2.2 p.373](https://ieeexplore.ieee.org/document/10910082) | `upfSupplyTypeT` と同じ形 | 以前の版との互換のための型名 | 以前の版から使われている電源ネットの型。HDL でこの型のネットを宣言すると、UPF で `create_supply_net` したのと同じ扱いになる (6.25) | — | 標準 |
| <a id="val-hdlpkg-upfPdSsObjT"></a>`upfPdSsObjT`<br>[11.2.2.3 p.374](https://ieeexplore.ieee.org/document/10910082) | `struct packed { upfHandleT handle; upfPowerStateObjT current_state; upfSimstateE current_simstate; }` | handle: オブジェクトのハンドル、`current_state`: 現在の電源状態、`current_simstate`: 現在のシムステート | 電源ドメインと電源セットのネイティブ表現 (動的プロパティを継続的に見られる構造体) | — | 標準 |
| <a id="val-hdlpkg-upfPowerStateObjT"></a>`upfPowerStateObjT`<br>[11.2.2.3 p.374](https://ieeexplore.ieee.org/document/10910082) | `struct packed { upfHandleT handle; upfBooleanT is_active; }` | handle: 電源状態のハンドル、`is_active`: その状態が有効か | 電源状態 (と PST の状態) のネイティブ表現 | — | 標準 |
| <a id="val-hdlpkg-upfStateHolderObjT"></a>`upfStateHolderObjT`<br>[11.2.2.3 p.374](https://ieeexplore.ieee.org/document/10910082) | `struct packed { upfHandleT handle; upfPowerStateObjT current_state; }` | handle: オブジェクトのハンドル、`current_state`: 現在の電源状態 | 複合ドメインと電源状態グループのネイティブ表現 | — | 標準 |
| <a id="val-hdlpkg-upfBooleanObjT"></a>`upfBooleanObjT`<br>[11.2.2.3 p.374](https://ieeexplore.ieee.org/document/10910082) | `struct packed { upfHandleT handle; upfBooleanT current_value; }` | handle: オブジェクトのハンドル、`current_value`: 現在の値 | 式 (`upfExpressionT`) のネイティブ表現 | — | 標準 |
| <a id="val-hdlpkg-upfLogicObjT"></a>`upfLogicObjT`<br>[11.2.2.3 p.374](https://ieeexplore.ieee.org/document/10910082) | `struct packed { upfHandleT handle; upfLogicT current_value; }` | handle: オブジェクトのハンドル、`current_value`: 現在の論理値 | ロジックネット・ロジックポート・ack ポートのネイティブ表現 | — | 標準 |
| <a id="val-hdlpkg-upfSupplyObjT"></a>`upfSupplyObjT`<br>[11.2.2.3 p.374](https://ieeexplore.ieee.org/document/10910082) | `struct packed { upfHandleT handle; upfSupplyTypeT current_value; }` | handle: オブジェクトのハンドル、`current_value`: 現在の電源の値 | UPF で作った電源ネット・電源ポートのネイティブ表現。HDL で直接宣言した電源は `upfSupplyTypeT` で表す | — | 標準 |
| <a id="val-hdlpkg-upfSupplyStateE"></a>`upfSupplyStateE`<br>[11.2.4 p.409](https://ieeexplore.ieee.org/document/10910082) | 列挙子 4 個 | `OFF` / `FULL_ON` / `PARTIAL_ON` / `UNDETERMINED` | 電源の状態値の列挙。`get_supply_state` の戻り値や `set_supply_state` の引数に使う | — | 標準 |
| <a id="val-hdlpkg-upfSimstateE"></a>`upfSimstateE`<br>[11.2.4 p.416](https://ieeexplore.ieee.org/document/10910082) | 列挙子 6 個 | `CORRUPT` / `CORRUPT_ON_ACTIVITY` / `CORRUPT_ON_CHANGE` / `CORRUPT_STATE_ON_ACTIVITY` / `CORRUPT_STATE_ON_CHANGE` / `NORMAL` | シムステートの列挙 (4.8)。`upfPdSsObjT` の `current_simstate` の型 | — | 標準 |
| <a id="val-hdlpkg-upfClassIdE"></a>`upfClassIdE`<br>[11.2.4 p.409](https://ieeexplore.ieee.org/document/10910082) | 列挙子 58 個 | `UPF_BASE` / `UPF_BASE_HDL` / `UPF_BASE_NAMED` / `UPF_BASE_RELATIONSHIP` / `UPF_BASE_UPF` / `UPF_BOUNDARY_STRATEGY` / `UPF_EXTENT_CLASS` / `UPF_HDL_DECL` ほか (全 58 個) | 情報モデルのクラス ID の列挙 (対応表は 11.2.2.5 の Table 42)。`upf_query_object_type` の戻り値、`upf_object_in_class` の引数に使う | — | 標準 |
| <a id="val-hdlpkg-upfPropertyIdE"></a>`upfPropertyIdE`<br>[11.2.4 p.414](https://ieeexplore.ieee.org/document/10910082) | 列挙子 148 個 | `UPF_ACK_DELAY` / `UPF_ACK_PORTS` / `UPF_APPLIES_TO` / `UPF_ATTR_NAME` / `UPF_ATTR_VALUE` / `UPF_CELL_INFO` / `UPF_CELL_KIND` / `UPF_CELL_ORIGIN` ほか (全 148 個) | 情報モデルのプロパティ ID の列挙 (対応表は 11.2.2.6 の Table 43)。`upf_query_object_properties` の引数に使う | — | 標準 |
| <a id="val-hdlpkg-upfAppliesToFilterE"></a>`upfAppliesToFilterE`<br>[11.2.4 p.414](https://ieeexplore.ieee.org/document/10910082) | 列挙子 4 個 | `UPF_FILTER_UNDEF` / `UPF_FILTER_INPUTS` / `UPF_FILTER_OUTPUTS` / `UPF_FILTER_BOTH` | ストラテジの `-applies_to` (inputs / outputs / both) を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfAppliesToBoundaryE"></a>`upfAppliesToBoundaryE`<br>[11.2.4 p.417](https://ieeexplore.ieee.org/document/10910082) | 列挙子 4 個 | `UPF_BOUNDARY_UNDEF` / `UPF_BOUNDARY_LOWER` / `UPF_BOUNDARY_UPPER` / `UPF_BOUNDARY_BOTH` | ストラテジの `-applies_to_boundary` (lower / upper / both) を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfAppliesToRetFilterE"></a>`upfAppliesToRetFilterE`<br>[11.2.4 p.417](https://ieeexplore.ieee.org/document/10910082) | 列挙子 3 個 | `UPF_RET_FILTER_ANY` / `UPF_RET_FILTER_FLOP` / `UPF_RET_FILTER_LATCH` | `set_retention` `-applies_to` (any / flop / latch) を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfCellKindE"></a>`upfCellKindE`<br>[11.2.4 p.414](https://ieeexplore.ieee.org/document/10910082) | 列挙子 9 個 | `UPF_CELL_NONE` / `UPF_CELL_ISOLATION` / `UPF_CELL_LEVEL_SHIFTER` / `UPF_CELL_ISO_LS_COMBO` / `UPF_CELL_RETENTION` / `UPF_CELL_SWITCH` / `UPF_CELL_REPEATER` / `UPF_CELL_CORRUPT` / `UPF_CELL_MACRO` | 電源管理セルの種類 (分離・レベルシフタ・保持・スイッチ・リピータなど) を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfCellOriginE"></a>`upfCellOriginE`<br>[11.2.4 p.414](https://ieeexplore.ieee.org/document/10910082) | 列挙子 5 個 | `UPF_ORIGIN_UNKNOWN` / `UPF_ORIGIN_DESIGN` / `UPF_ORIGIN_INSERTED` / `UPF_ORIGIN_INSERTED_MAP` / `UPF_ORIGIN_INFERRED` | セルの由来 (デザインにあったもの、挿入されたもの、推論されたものなど) を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfHdlCellKindE"></a>`upfHdlCellKindE`<br>[11.2.4 p.414](https://ieeexplore.ieee.org/document/10910082) | 列挙子 5 個 | `UPF_HDLCELL_NONE` / `UPF_HDLCELL_COMB` / `UPF_HDLCELL_FLOP` / `UPF_HDLCELL_LATCH` / `UPF_HDLCELL_MEM` | HDL の要素の種類 (組み合わせ・フリップフロップ・ラッチ・メモリ) を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfIsolationClampE"></a>`upfIsolationClampE`<br>[11.2.4 p.415](https://ieeexplore.ieee.org/document/10910082) | 列挙子 7 個 | `UPF_CLAMP_UNDEF` / `UPF_CLAMP_ZERO` / `UPF_CLAMP_ONE` / `UPF_CLAMP_ZEE` / `UPF_CLAMP_LATCH` / `UPF_CLAMP_ANY` / `UPF_CLAMP_USER_VALUE` | 分離のクランプ値 (0 / 1 / Z / latch / any / 任意の値) を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfLevelShifterRuleE"></a>`upfLevelShifterRuleE`<br>[11.2.4 p.415](https://ieeexplore.ieee.org/document/10910082) | 列挙子 3 個 | `UPF_LS_LOW_TO_HIGH` / `UPF_LS_HIGH_TO_LOW` / `UPF_LS_BOTH` | `set_level_shifter` `-rule` を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfLocationE"></a>`upfLocationE`<br>[11.2.4 p.415](https://ieeexplore.ieee.org/document/10910082) | 列挙子 5 個 | SELF / OTHER / PARENT / AUTOMATIC / FANOUT | ストラテジの `-location` を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfNamedRefKindE"></a>`upfNamedRefKindE`<br>[11.2.4 p.415](https://ieeexplore.ieee.org/document/10910082) | 列挙子 15 個 | `UPF_REF_POWER` / `UPF_REF_GROUND` / `UPF_REF_PWELL` / `UPF_REF_NWELL` / `UPF_REF_DEEPPWELL` / `UPF_REF_DEEPNWELL` / `UPF_REF_ISO_SIGNAL` / `UPF_REF_SAVE_SIGNAL` ほか (全 15 個) | 名前で参照するもの (電源関数、分離・保存・復帰の信号、総称信号ハンドルなど) の種類を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfPortDirE"></a>`upfPortDirE`<br>[11.2.4 p.415](https://ieeexplore.ieee.org/document/10910082) | 列挙子 4 個 | `UPF_DIR_UNDEF` / `UPF_DIR_IN` / `UPF_DIR_OUT` / `UPF_DIR_INOUT` | ポートの向きを表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfResolveE"></a>`upfResolveE`<br>[11.2.4 p.416](https://ieeexplore.ieee.org/document/10910082) | 列挙子 5 個 | UNRESOLVED / `ONE_HOT` / PARALLEL / `PARALLEL_ONE_HOT` / `USER_RESOLUTION_FUNC` | `create_supply_net` `-resolve` の解決方法を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfRetentionParamE"></a>`upfRetentionParamE`<br>[11.2.4 p.416](https://ieeexplore.ieee.org/document/10910082) | 列挙子 4 個 | `RET_SUP_COR` / `NO_RET_SUP_COR` / `SAV_RES_COR` / `NO_SAV_RES_COR` | `set_retention` `-parameters` の値を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfSignalSenseKindE"></a>`upfSignalSenseKindE`<br>[11.2.4 p.416](https://ieeexplore.ieee.org/document/10910082) | 列挙子 4 個 | `UPF_SENSE_HIGH` / `UPF_SENSE_LOW` / `UPF_SENSE_POSEDGE` / `UPF_SENSE_NEGEDGE` | 信号の有効レベル/エッジ (high / low / posedge / negedge) を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfSwitchTypeE"></a>`upfSwitchTypeE`<br>[11.2.4 p.417](https://ieeexplore.ieee.org/document/10910082) | 列挙子 3 個 | `UPF_SW_COARSE_GRAIN` / `UPF_SW_FINE_GRAIN` / `UPF_SW_BOTH` | `create_power_switch` `-switch_type` を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-upfVoltKindE"></a>`upfVoltKindE`<br>[11.2.4 p.416](https://ieeexplore.ieee.org/document/10910082) | 列挙子 3 個 | NOM / DOUBLET / TRIPLET | 電圧の指定の形 (公称値だけ / 2 値 / 3 値) を表す列挙 | — | 標準 |
| <a id="val-hdlpkg-one_hot"></a>`one_hot`<br>[11.2.4 p.416](https://ieeexplore.ieee.org/document/10910082) | `function upfSupplyTypeT one_hot(...)` | `create_supply_net` `-resolve` `one_hot` に対応する解決関数 | 根の異なる複数の駆動元のうち、同時に `OFF` 以外になるのは 1 つだけという前提で電源ネットの値を決める解決関数。2 つ以上が `OFF` 以外なら `UNDETERMINED` (パッケージ内の定義) | `upfSupplyTypeT` | 標準 |
| <a id="val-hdlpkg-parallel"></a>`parallel`<br>[11.2.4 p.416](https://ieeexplore.ieee.org/document/10910082) | `function upfSupplyTypeT parallel(...)` | `create_supply_net` `-resolve` parallel に対応する解決関数 | 同じ根の電源 (root supply driver) から並列の経路 (スイッチ) で駆動される電源ネットの値を決める解決関数 (パッケージ内の定義) | `upfSupplyTypeT` | 標準 |
| <a id="val-hdlpkg-parallel_one_hot"></a>`parallel_one_hot`<br>[11.2.4 p.416](https://ieeexplore.ieee.org/document/10910082) | `function upfSupplyTypeT parallel_one_hot(...)` | `create_supply_net` `-resolve` `parallel_one_hot` に対応する解決関数 | 根の電源ごとには `one_hot`、同じ根を共有する経路の間では parallel として電源ネットの値を決める解決関数 (パッケージ内の定義) | `upfSupplyTypeT` | 標準 |

<a id="cat-vattr"></a>

## 定義済み属性 (22 件)

`set_port_attributes` / `set_design_attributes` の `-attribute` や HDL の属性で書く、意味の決まった属性名

| 名前 | 値・書き方 | 値の意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="val-vattr-UPF_clamp_value"></a>`UPF_clamp_value`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<0 \| 1 \| Z \| latch \| any \| value>` | 0 / 1 / Z: その値に固定、latch: 分離開始時の値を保持、any: 値を問わない、value: ポートの型に合う任意の値 | ポートを分離するときに求めるクランプ値。`set_port_attributes` `-clamp_value` で付ける。モデルにもインスタンスにも付けられる。`set_isolation` で `-clamp_value` を省略すると、この値が使われる | — | 標準 |
| <a id="val-vattr-UPF_async_clamp_value"></a>`UPF_async_clamp_value`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<0 \| 1>` | 0 / 1: 非同期のセット/リセットで固定する値 | 非同期のクランプ値の要求。`set_port_attributes` `-async_clamp_value` で付ける。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_pg_type"></a>`UPF_pg_type`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `pg_type_value` | `primary_power` / `primary_ground` / `backup_power` / `backup_ground` / pwell / nwell / deeppwell / deepnwell など (4.5.4.6、5.6 の例) | 電源ピンの種類。電源セットの関数を `pg_type` で自動接続するときの手がかりになる (power は `primary_power`、ground は `primary_ground` へ)。`set_port_attributes` `-pg_type` で付ける。Liberty の `pg_type` からも設定される。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_related_power_port"></a>`UPF_related_power_port`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `supply_port_name` | 同じインタフェース上の電源ポートの単純名 | このポートに関係する power の電源ポート。`set_port_attributes` `-related_power_port` で付ける。Liberty の `related_power_pin` からも設定される。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_related_ground_port"></a>`UPF_related_ground_port`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `supply_port_name` | 同じインタフェース上の電源ポートの単純名 | このポートに関係する ground の電源ポート。`set_port_attributes` `-related_ground_port` で付ける。Liberty の `related_ground_pin` からも設定される。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_related_bias_ports"></a>`UPF_related_bias_ports`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `supply_port_name_list` | 同じインタフェース上の電源ポートの単純名を空白で区切ったリスト ({ } で囲まない) | このポートに関係するバイアスの電源ポート。`set_port_attributes` `-related_bias_ports` で付ける。Liberty の `related_bias_pin` からも設定される。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_driver_supply"></a>`UPF_driver_supply`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `supply_set_ref` | 電源セットの名前 | ポートを駆動する側の電源セット。`set_port_attributes` `-driver_supply` で付ける。インスタンスのポートにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_receiver_supply"></a>`UPF_receiver_supply`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `supply_set_ref` | 電源セットの名前 | ポートの信号を受ける側の電源セット。`set_port_attributes` `-receiver_supply` で付ける。インスタンスのポートにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_literal_supply"></a>`UPF_literal_supply`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `supply_set_ref` | 電源セットの名前 | インスタンスのポートにつないだ定数を作る電源として扱う電源セット。`set_port_attributes` `-literal_supply` で付ける。インスタンスのポートにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_feedthrough"></a>`UPF_feedthrough`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `feedthrough_name` | 内部で直結しているポートの組に付ける名前 | 同じ名前を付けたポート同士が内部で直結されていることを示す。`set_port_attributes` `-feedthrough` で付ける。Liberty の short からも設定される。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_unconnected"></a>`UPF_unconnected`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<TRUE \| FALSE>` | `TRUE`: 内部でどこにもつながっていない | ポートが内部で未接続であることを示す。`set_port_attributes` `-unconnected` で付ける。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_is_isolated"></a>`UPF_is_isolated`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<TRUE \| FALSE>` | `TRUE`: 内部で分離済み | ポートが内部で分離されていて、外側での分離が要らないことを示す。`set_port_attributes` `-is_isolated` で付ける。Liberty の `is_isolated` からも設定される。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_is_analog"></a>`UPF_is_analog`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<TRUE \| FALSE>` | `TRUE`: アナログポート | ポートがアナログポートであることを示す。`set_port_attributes` `-is_analog` で付ける。Liberty の `is_analog` からも設定される。モデルにもインスタンスにも付けられる | — | 標準 |
| <a id="val-vattr-UPF_retention"></a>`UPF_retention`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<required \| optional>` | required: 保持が必要、optional: 保持してもしなくてもよい | 要素の保持の要否。`set_design_attributes` `-attribute` {`UPF_retention` 値} で付け、`set_retention_elements` `-applies_to` で絞り込みに使う。モデルにもインスタンスにも付けられる | — | 標準 |
| <a id="val-vattr-UPF_simstate_behavior"></a>`UPF_simstate_behavior`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<ENABLE \| SIMSTATE_ONLY \| PORT_CORR_ONLY \| DISABLE>` | 意味は `set_simstate_behavior` (6.56) を参照 | モデルまたはインスタンスのシミュレーション時の振る舞い。`set_simstate_behavior` で付ける。モデルにもインスタンスにも付けられる | — | 標準 |
| <a id="val-vattr-UPF_is_soft_macro"></a>`UPF_is_soft_macro`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<TRUE \| FALSE>` | `TRUE`: ソフトマクロとして扱う | モデルをソフトマクロとして扱う。ソフトマクロは元の RTL と UPF で表し、ボトムアップで実装するマクロで、その UPF は自己完結していなければならない (4.9.2.4.2)。`set_design_attributes` `-is_soft_macro` で付ける。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_is_hard_macro"></a>`UPF_is_hard_macro`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<TRUE \| FALSE>` | `TRUE`: ハードマクロとして扱う | モデルをハードマクロとして扱う。ハードマクロは実装済みで、親からはインタフェースだけが見えるマクロ (4.9.2.4.1)。`set_design_attributes` `-is_hard_macro` で付ける。Liberty の `is_macro_cell` からも設定される。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_is_refinable_macro"></a>`UPF_is_refinable_macro`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<TRUE \| FALSE>` | `TRUE`: リファイナブルマクロとして扱う | モデルをリファイナブルマクロ (検証済みの電力意図を保ったまま、上位で詳細化してよいマクロ。4.9.2.4.3) として扱う。`set_design_attributes` `-is_refinable_macro` で付ける。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_is_power_aware_model"></a>`UPF_is_power_aware_model`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<TRUE \| FALSE>` | `TRUE`: 電源の振る舞いをモデル自身が持つ | 電力考慮済みのモデルであることを示す。`TRUE` のモデルは、`UPF_simstate_behavior` を明示しなければ `DISABLE` 扱いになる。`set_design_attributes` `-is_power_aware_model` で付ける。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_switch_cell_type"></a>`UPF_switch_cell_type`<br>[5.6 p.86](https://ieeexplore.ieee.org/document/10910082) | `<fine_grain \| coarse_grain>` | `fine_grain` / `coarse_grain`: スイッチセルの粒度 | モデルのスイッチセルの種類。`create_power_switch` `-switch_type` でセルを選ぶのに使う。`set_design_attributes` `-switch_cell_type` で付ける。Liberty の `switch_cell_type` からも設定される。モデルにだけ付けられる | — | 標準 |
| <a id="val-vattr-UPF_sink_off_clamp_value"></a>`UPF_sink_off_clamp_value`<br>[6.51 p.214](https://ieeexplore.ieee.org/document/10910082) | `<0 \| 1 \| any \| Z \| latch \| value>` | `UPF_clamp_value` と同じ値 | 受け側ドメインの一次電源が `NORMAL` でないときのクランプ要求。非推奨の `set_port_attributes` `-sink_off_clamp` と同じ意味の属性名として 6.51 に出てくる (Table 7 にはない) | — | 非推奨 |
| <a id="val-vattr-UPF_source_off_clamp_value"></a>`UPF_source_off_clamp_value`<br>[6.51 p.214](https://ieeexplore.ieee.org/document/10910082) | `<0 \| 1 \| any \| Z \| latch \| value>` | `UPF_clamp_value` と同じ値 | 駆動側ドメインの一次電源が `NORMAL` でないときのクランプ要求。非推奨の `set_port_attributes` `-source_off_clamp` と同じ意味の属性名として 6.51 に出てくる (Table 7 にはない) | — | 非推奨 |

<a id="cat-vname"></a>

## 定義済みの名前 (関数・ハンドル・電源状態) (33 件)

電源セットの関数、ドメインやストラテジのハンドル、総称信号ハンドル、定義済みの電源状態など、予約された名前

| 名前 | 値・書き方 | 値の意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="val-vname-power"></a>`power`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | 電源セット名.power | 電源ネットハンドル | 電源セットの関数の 1 つ。主電源 (VDD 側) を担う電源ネットを表す。自動接続では `pg_type` が `primary_power` のピンにつながる | — | 標準 |
| <a id="val-vname-ground"></a>`ground`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | 電源セット名.ground | 電源ネットハンドル | 電源セットの関数の 1 つ。グランド (VSS 側) を担う電源ネットを表す。自動接続では `pg_type` が `primary_ground` のピンにつながる | — | 標準 |
| <a id="val-vname-pwell"></a>`pwell`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | 電源セット名.pwell | 電源ネットハンドル | 電源セットの関数の 1 つ。P ウェルのバイアスを担う。自動接続では `pg_type` が pwell のピンにつながる | — | 標準 |
| <a id="val-vname-nwell"></a>`nwell`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | 電源セット名.nwell | 電源ネットハンドル | 電源セットの関数の 1 つ。N ウェルのバイアスを担う。自動接続では `pg_type` が nwell のピンにつながる | — | 標準 |
| <a id="val-vname-deeppwell"></a>`deeppwell`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | 電源セット名.deeppwell | 電源ネットハンドル | 電源セットの関数の 1 つ。ディープ P ウェルのバイアスを担う。自動接続では `pg_type` が deeppwell のピンにつながる | — | 標準 |
| <a id="val-vname-deepnwell"></a>`deepnwell`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | 電源セット名.deepnwell | 電源ネットハンドル | 電源セットの関数の 1 つ。ディープ N ウェルのバイアスを担う。自動接続では `pg_type` が deepnwell のピンにつながる | — | 標準 |
| <a id="val-vname-primary"></a>`primary`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | ドメイン名.primary | 電源セットハンドル | 電源ドメインの一次電源セット。ドメイン内の要素に暗黙に接続される。`associate_supply_set` や `create_power_domain` `-supply` で実際の電源セットを割り当てる | — | 標準 |
| <a id="val-vname-switch_supply"></a>`switch_supply`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | スイッチ名.`switch_supply` | 電源セットハンドル | 電源スイッチ (`create_power_switch`) の制御部分に給電する電源セット | — | 標準 |
| <a id="val-vname-isolation_supply"></a>`isolation_supply`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | ドメイン名.ストラテジ名.`isolation_supply` | 電源セットハンドル | 分離ストラテジで挿入する分離セルに給電する電源セット (`set_isolation` `-isolation_supply` で決まる) | — | 標準 |
| <a id="val-vname-isolation_signal"></a>`isolation_signal`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | ドメイン名.ストラテジ名.`isolation_signal` | ネットハンドル | 分離ストラテジの分離制御信号を参照する名前 | — | 標準 |
| <a id="val-vname-input_supply"></a>`input_supply`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | ドメイン名.ストラテジ名.`input_supply` | 電源セットハンドル | レベルシフタストラテジで、レベルシフタの入力側に給電する電源セット | — | 標準 |
| <a id="val-vname-output_supply"></a>`output_supply`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | ドメイン名.ストラテジ名.`output_supply` | 電源セットハンドル | レベルシフタストラテジで、レベルシフタの出力側に給電する電源セット | — | 標準 |
| <a id="val-vname-internal_supply"></a>`internal_supply`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | ドメイン名.ストラテジ名.`internal_supply` | 電源セットハンドル | レベルシフタストラテジで、レベルシフタの内部回路に給電する電源セット | — | 標準 |
| <a id="val-vname-retention_supply"></a>`retention_supply`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | ドメイン名.ストラテジ名.`retention_supply` | 電源セットハンドル | 保持ストラテジで、保持のための論理に給電する電源セット。`map_retention_cell` `-port_map` では `retention_supply`.関数名 で参照する | — | 標準 |
| <a id="val-vname-primary_supply"></a>`primary_supply`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | ドメイン名.ストラテジ名.`primary_supply` | 電源セットハンドル | 保持ストラテジで、ドメインの一次電源を参照する名前。`map_retention_cell` `-port_map` では `primary_supply`.関数名 で参照する | — | 標準 |
| <a id="val-vname-save_signal"></a>`save_signal`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `save_signal` | ネットハンドル | 保持ストラテジの保存信号 (`set_retention` `-save_signal`) を参照する名前。`map_retention_cell` `-port_map` で使い、\~ を付けると反転 | — | 標準 |
| <a id="val-vname-restore_signal"></a>`restore_signal`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `restore_signal` | ネットハンドル | 保持ストラテジの復帰信号 (`set_retention` `-restore_signal`) を参照する名前。`map_retention_cell` `-port_map` で使い、\~ を付けると反転 | — | 標準 |
| <a id="val-vname-powerdown_period_condition"></a>`powerdown_period_condition`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `powerdown_period_condition` | 条件ハンドル | 保持ストラテジの電源断期間の条件 (`set_retention` `-powerdown_period_condition`) を参照する名前 | — | 標準 |
| <a id="val-vname-save_event_condition"></a>`save_event_condition`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `save_event_condition` | 条件ハンドル | 保持ストラテジの保存の追加条件 (`set_retention` `-save_event_condition`) を参照する名前 | — | 標準 |
| <a id="val-vname-restore_event_condition"></a>`restore_event_condition`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `restore_event_condition` | 条件ハンドル | 保持ストラテジの復帰の追加条件 (`set_retention` `-restore_event_condition`) を参照する名前 | — | 標準 |
| <a id="val-vname-UPF_GENERIC_CLOCK"></a>`UPF_GENERIC_CLOCK`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `UPF_GENERIC_CLOCK` | 総称信号ハンドル | 推論した保持レジスタの総称インタフェースのクロック (フリップフロップならデータを取り込むエッジの信号、ラッチなら透過を有効にする信号)。`map_retention_cell` `-port_map` で使う | — | 標準 |
| <a id="val-vname-UPF_GENERIC_DATA"></a>`UPF_GENERIC_DATA`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `UPF_GENERIC_DATA` | 総称信号ハンドル | 推論した保持レジスタの次の状態を表すデータ信号。`map_retention_cell` `-port_map` で使う | — | 標準 |
| <a id="val-vname-UPF_GENERIC_ASYNC_SET_RESET"></a>`UPF_GENERIC_ASYNC_SET_RESET`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `UPF_GENERIC_ASYNC_SET_RESET` | 総称信号ハンドル | 推論した保持レジスタの非同期セットまたはリセットが有効なときに真になる式。`map_retention_cell` `-port_map` で使う | — | 標準 |
| <a id="val-vname-UPF_GENERIC_OUTPUT"></a>`UPF_GENERIC_OUTPUT`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `UPF_GENERIC_OUTPUT` | 総称信号ハンドル | 推論した保持レジスタの出力を受け側へ伝える信号。`map_retention_cell` `-port_map` で使う | — | 標準 |
| <a id="val-vname-repeater_supply"></a>`repeater_supply`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | ドメイン名.ストラテジ名.`repeater_supply` | 電源セットハンドル | リピータストラテジで挿入するバッファに給電する電源セット (`set_repeater` `-repeater_supply` で決まる) | — | 標準 |
| <a id="val-vname-UPF_GENERIC_ASYNC_LOAD"></a>`UPF_GENERIC_ASYNC_LOAD`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `UPF_GENERIC_ASYNC_LOAD` | 総称信号ハンドル | `UPF_GENERIC_ASYNC_SET_RESET` の旧名 | — | レガシー |
| <a id="val-vname-retention_condition"></a>`retention_condition`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `retention_condition` | 条件ハンドル | 旧方式の `set_retention` `-retention_condition` を参照する名前 | — | レガシー |
| <a id="val-vname-save_condition"></a>`save_condition`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `save_condition` | 条件ハンドル | 旧方式の `set_retention` `-save_condition` を参照する名前 | — | レガシー |
| <a id="val-vname-restore_condition"></a>`restore_condition`<br>[5.3.3.2 p.78](https://ieeexplore.ieee.org/document/10910082) | `restore_condition` | 条件ハンドル | 旧方式の `set_retention` `-restore_condition` を参照する名前 | — | レガシー |
| <a id="val-vname-UNDEFINED"></a>`UNDEFINED`<br>[4.7.4 p.53](https://ieeexplore.ieee.org/document/10910082) | `UNDEFINED` | 定義済みの電源状態 | どのオブジェクト (電源セット・ドメイン・複合ドメイン・グループ・モデル・インスタンス) にもある電源状態。状態を細かく定義する前の「すべての状態」を表す。電源セットではシムステートを持たない | — | 標準 |
| <a id="val-vname-ERROR"></a>`ERROR`<br>[4.7.4 p.53](https://ieeexplore.ieee.org/document/10910082) | `ERROR` | 定義済みの電源状態 | どのオブジェクトにもある電源状態。定義した状態の組み合わせがおかしい (例: 排他のはずの状態が同時に有効) ことを表す。電源セットではシムステート `CORRUPT` | — | 標準 |
| <a id="val-vname-ON"></a>`ON`<br>[4.7.4 p.53](https://ieeexplore.ieee.org/document/10910082) | 電源セット名 == `ON` など | 定義済みの電源状態 (電源セットだけ) | 電源セットの電源状態。シムステートは `NORMAL`。式を定義しなければ、必要な電源関数がすべて `FULL_ON` のときに有効。`add_power_state` `-update` で式などを足せる | — | 標準 |
| <a id="val-vname-OFF"></a>`OFF`<br>[4.7.4 p.53](https://ieeexplore.ieee.org/document/10910082) | 電源セット名 == `OFF` など | 定義済みの電源状態 (電源セットだけ) | 電源セットの電源状態。シムステートは `CORRUPT`。式を定義しなければ、他のどの名前付き状態も有効でないときに有効 | — | 標準 |

<a id="cat-vstate"></a>

## 電源の状態値・シムステート (11 件)

電源の状態値 (`supply_net_type` の state) と、電源状態に付けるシムステート

| 名前 | 値・書き方 | 値の意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="val-vstate-OFF"></a>`OFF`<br>[4.7.2 p.51](https://ieeexplore.ieee.org/document/10910082) | `OFF` | 電源の状態値 (`supply_net_type` / `upfSupplyStateE`) | 電源を供給できない状態。電圧の値は意味を持たない | — | 標準 |
| <a id="val-vstate-UNDETERMINED"></a>`UNDETERMINED`<br>[4.7.2 p.51](https://ieeexplore.ieee.org/document/10910082) | `UNDETERMINED` | 電源の状態値 | 電源を供給できるかどうか決まらない状態 (複数の駆動元がぶつかった場合など)。電圧の値は意味を持たない | — | 標準 |
| <a id="val-vstate-PARTIAL_ON"></a>`PARTIAL_ON`<br>[4.7.2 p.51](https://ieeexplore.ieee.org/document/10910082) | `PARTIAL_ON` | 電源の状態値 | 一部だけ供給している状態。電圧の値を持つ。シミュレーションで `OFF` / `FULL_ON` のどちらとして扱うかは `set_partial_on_translation` で決める | — | 標準 |
| <a id="val-vstate-FULL_ON"></a>`FULL_ON`<br>[4.7.2 p.51](https://ieeexplore.ieee.org/document/10910082) | `FULL_ON` | 電源の状態値 | 完全に供給している状態。電圧の値 (整数の µV、HDL 関数では V の実数) を持つ | — | 標準 |
| <a id="val-vstate-NORMAL"></a>`NORMAL`<br>[4.8 p.58](https://ieeexplore.ieee.org/document/10910082) | `NORMAL` | シムステート | 完全に動作する (スイッチングできる) 電源状態。論理は通常どおりシミュレーションされる。電源セットの `ON` 状態のシムステート | — | 標準 |
| <a id="val-vstate-CORRUPT_STATE_ON_CHANGE"></a>`CORRUPT_STATE_ON_CHANGE`<br>[4.8 p.58](https://ieeexplore.ieee.org/document/10910082) | `CORRUPT_STATE_ON_CHANGE` | シムステート | 組み合わせ論理は正常に動き、記憶素子も動作はできるが、記憶素子の値が変わると破壊される | — | 標準 |
| <a id="val-vstate-CORRUPT_STATE_ON_ACTIVITY"></a>`CORRUPT_STATE_ON_ACTIVITY`<br>[4.8 p.58](https://ieeexplore.ieee.org/document/10910082) | `CORRUPT_STATE_ON_ACTIVITY` | シムステート | 組み合わせ論理は正常に動くが、記憶素子の中で動作 (値が変わらなくても) があると破壊される | — | 標準 |
| <a id="val-vstate-CORRUPT_ON_CHANGE"></a>`CORRUPT_ON_CHANGE`<br>[4.8 p.58](https://ieeexplore.ieee.org/document/10910082) | `CORRUPT_ON_CHANGE` | シムステート | 出力が変わらない限り値を保てる。要素の出力が変わると破壊される | — | 標準 |
| <a id="val-vstate-CORRUPT_ON_ACTIVITY"></a>`CORRUPT_ON_ACTIVITY`<br>[4.8 p.58](https://ieeexplore.ieee.org/document/10910082) | `CORRUPT_ON_ACTIVITY` | シムステート | 動作がない限り値を保てる。要素の中で動作があると破壊される | — | 標準 |
| <a id="val-vstate-CORRUPT"></a>`CORRUPT`<br>[4.8 p.57](https://ieeexplore.ieee.org/document/10910082) | `CORRUPT` | シムステート | 電源が切れているか電圧が低すぎて、値を保てない。要素の値は破壊される。電源セットの `OFF` と `ERROR` 状態のシムステート。6 つの中で最も優先度が高い | — | 標準 |
| <a id="val-vstate-NOT_NORMAL"></a>`NOT_NORMAL`<br>[9.5.8 p.275](https://ieeexplore.ieee.org/document/10910082) | `NOT_NORMAL` | シムステート (`add_power_state` `-simstate` に書ける値) | `NORMAL` でないことだけを表す指定。シミュレーションでは、ツール固有の指定で上書きしない限り `CORRUPT` として扱う | — | 標準 |

<a id="cat-vcmtab"></a>

## 定義済み VCM (付属書 B) (12 件)

`connect_supply_net` `-vcm` でそのまま使える定義済みの値変換方式

| 名前 | 値・書き方 | 値の意味 | 意味・機能概要 | 戻り値 | 区分 |
|---|---|---|---|---|---|
| <a id="val-vcmtab-VHDL_SL2UPF"></a>`VHDL_SL2UPF`<br>[B.2 p.443](https://ieeexplore.ieee.org/document/10910082) | VHDL の `std_ulogic`、HDL → UPF (`-conversion_direction hdl2upf`) | `'U'` / `'X'` / `'Z'` / `'W'` / `'-'` → `UNDETERMINED`、`'0'` / `'L'` → `OFF`、`'1'` / `'H'` → `FULL_ON` | VHDL の `std_ulogic` を UPF の電源の状態に変換する定義済み VCM。'1' / 'H' を `FULL_ON`、'0' / 'L' を `OFF` とみなす | — | 標準 |
| <a id="val-vcmtab-UPF2VHDL_SL"></a>`UPF2VHDL_SL`<br>[B.3 p.443](https://ieeexplore.ieee.org/document/10910082) | VHDL の `std_ulogic`、UPF → HDL (`-conversion_direction upf2hdl`) | `UNDETERMINED` / `PARTIAL_ON` → `'X'`、`FULL_ON` → `'1'`、`OFF` → `'0'` | UPF の電源の状態を VHDL の `std_ulogic` に変換する定義済み VCM | — | 標準 |
| <a id="val-vcmtab-VHDL_SL2UPF_GNDZERO"></a>`VHDL_SL2UPF_GNDZERO`<br>[B.4 p.443](https://ieeexplore.ieee.org/document/10910082) | VHDL の `std_ulogic`、HDL → UPF (`-conversion_type hdl2upf`) | `'U'` / `'X'` / `'Z'` / `'W'` / `'-'` → `UNDETERMINED`、`'0'` / `'L'` → `FULL_ON`、`'1'` / `'H'` → `OFF` | VHDL の `std_ulogic` を UPF の電源の状態に変換する定義済み VCM のグランド用。'0' / 'L' を `FULL_ON` とみなす<br>**注:** 規格では向きのオプション名が `-conversion_type` になっている (他の VCM は `-conversion_direction`) | — | 標準 |
| <a id="val-vcmtab-UPF_GNDZERO2VHDL_SL"></a>`UPF_GNDZERO2VHDL_SL`<br>[B.5 p.444](https://ieeexplore.ieee.org/document/10910082) | VHDL の `std_ulogic`、UPF → HDL (`-conversion_direction upf2hdl`) | `UNDETERMINED` / `PARTIAL_ON` → `'X'`、`OFF` → `'1'`、`FULL_ON` → `'0'` | UPF の電源の状態を VHDL の `std_ulogic` に変換する定義済み VCM のグランド用 (`FULL_ON` を '0' にする) | — | 標準 |
| <a id="val-vcmtab-SV_LOGIC2UPF"></a>`SV_LOGIC2UPF`<br>[B.6 p.444](https://ieeexplore.ieee.org/document/10910082) | SystemVerilog の `logic`、HDL → UPF (`-conversion_direction hdl2upf`) | `X` / `Z` → `UNDETERMINED`、`1` → `FULL_ON`、`0` → `OFF` | SystemVerilog の logic を UPF の電源の状態に変換する定義済み VCM | — | 標準 |
| <a id="val-vcmtab-UPF2SV_LOGIC"></a>`UPF2SV_LOGIC`<br>[B.7 p.444](https://ieeexplore.ieee.org/document/10910082) | SystemVerilog の `logic`、UPF → HDL (`-conversion_direction upf2hdl`) | `UNDETERMINED` / `PARTIAL_ON` → `X`、`FULL_ON` → `1`、`OFF` → `0` | UPF の電源の状態を SystemVerilog の logic に変換する定義済み VCM | — | 標準 |
| <a id="val-vcmtab-SV_LOGIC2UPF_GNDZERO"></a>`SV_LOGIC2UPF_GNDZERO`<br>[B.8 p.444](https://ieeexplore.ieee.org/document/10910082) | SystemVerilog の `logic`、HDL → UPF (`-conversion_direction hdl2upf`) | `X` / `Z` → `UNDETERMINED`、`0` → `FULL_ON`、`1` → `OFF` | SystemVerilog の logic を UPF の電源の状態に変換する定義済み VCM のグランド用 (0 を `FULL_ON` とみなす) | — | 標準 |
| <a id="val-vcmtab-UPF_GNDZERO2SV_LOGIC"></a>`UPF_GNDZERO2SV_LOGIC`<br>[B.9 p.444](https://ieeexplore.ieee.org/document/10910082) | SystemVerilog の `logic`、UPF → HDL (`-conversion_direction upf2hdl`) | `UNDETERMINED` / `PARTIAL_ON` → `X`、`OFF` → `1`、`FULL_ON` → `0` | UPF の電源の状態を SystemVerilog の logic に変換する定義済み VCM のグランド用 (`FULL_ON` を 0 にする) | — | 標準 |
| <a id="val-vcmtab-VHDL_TIED_HI"></a>`VHDL_TIED_HI`<br>[B.10 p.444](https://ieeexplore.ieee.org/document/10910082) | VHDL の `std_ulogic`、UPF → HDL (`-conversion_direction upf2hdl`) | `UNDETERMINED` / `PARTIAL_ON` / `OFF` → `'X'`、`FULL_ON` → `'1'` | 電源が `FULL_ON` のときだけ '1' を出す定義済み VCM (VHDL)。タイハイの表現に使う | — | 標準 |
| <a id="val-vcmtab-SV_TIED_HI"></a>`SV_TIED_HI`<br>[B.11 p.445](https://ieeexplore.ieee.org/document/10910082) | SystemVerilog の `logic`、UPF → HDL (`-conversion_direction upf2hdl`) | `UNDETERMINED` / `PARTIAL_ON` / `OFF` → `X`、`FULL_ON` → `1` | 電源が `FULL_ON` のときだけ 1 を出す定義済み VCM (SystemVerilog)。タイハイの表現に使う | — | 標準 |
| <a id="val-vcmtab-VHDL_TIED_LO"></a>`VHDL_TIED_LO`<br>[B.12 p.445](https://ieeexplore.ieee.org/document/10910082) | VHDL の `std_ulogic`、UPF → HDL (`-conversion_direction upf2hdl`) | `UNDETERMINED` / `OFF` → `'X'`、`FULL_ON` / `PARTIAL_ON` → `'0'` | 電源が `FULL_ON` のとき '0' を出す定義済み VCM (VHDL)。タイローの表現に使う<br>**注:** 規格の表では `PARTIAL_ON` も '0' になっている (`SV_TIED_LO` では X) | — | 標準 |
| <a id="val-vcmtab-SV_TIED_LO"></a>`SV_TIED_LO`<br>[B.13 p.445](https://ieeexplore.ieee.org/document/10910082) | SystemVerilog の `logic`、UPF → HDL (`-conversion_direction upf2hdl`) | `UNDETERMINED` / `PARTIAL_ON` / `OFF` → `X`、`FULL_ON` → `0` | 電源が `FULL_ON` のときだけ 0 を出す定義済み VCM (SystemVerilog)。タイローの表現に使う | — | 標準 |

## 対象外にしたもの

次のものは、利用者が UPF に書くコマンドや値ではない、または規格に構文の定義がないため、表には入れていません。

### 構文の定義がない非推奨・置き換え済みのコマンドとオプション

6.2 によると、非推奨のコマンドは名前だけが示され、構文と意味は規格に書かれません。付属書 D の Table D.1 には、次の名前と置き換え先が載っています。

| 名前 | 置き換え先 (Table D.1) | 出典 |
|---|---|---|
| `describe_state_transition` | [`add_state_transition`](#cmd-add_state_transition) の `-transition` | 6.2 c) (非推奨の例として名前が出る)、D.3 |
| `load_upf_protected` | [`load_upf`](#cmd-load_upf) (`-params` は `-parameters` に) | D.3 |
| `set_isolation` / `set_level_shifter` / `set_repeater` の `-use_equivalence` | 各コマンドの `-use_functional_equivalence` (名前の変更) | D.3 |
| `set_retention_elements -transitive FALSE` | [`set_retention_elements`](#cmd-set_retention_elements) の `-exclude_elements` で子インスタンスを外す (`-transitive` 自体が非推奨) | D.2.2.4、D.3 |

### 置き換えられた旧問合せコマンド (付属書 C.4、p.452)

以前の版の `query_*` コマンドは、情報モデル (Clause 10) と 11.1 の問合せコマンドに置き換えられました。付属書 C.4 の Table C.1 に、各コマンドに対応する情報モデルのオブジェクトとプロパティが載っています。38 個:

`query_associate_supply_set`、`query_bind_checker`、`query_cell_instances`、`query_cell_mapped`、`query_composite_domain`、`query_design_attributes`、`query_hdl2upf_vct`、`query_isolation`、`query_isolation_control`、`query_level_shifter`、`query_map_isolation_cell`、`query_map_level_shifter_cell`、`query_map_power_switch`、`query_map_retention_cell`、`query_name_format`、`query_net_ports`、`query_partial_on_translation`、`query_pin_related_supply`、`query_port_attributes`、`query_port_direction`、`query_port_net`、`query_port_state`、`query_power_domain`、`query_power_domain_element`、`query_power_state`、`query_power_switch`、`query_pst`、`query_pst_state`、`query_retention`、`query_retention_control`、`query_retention_elements`、`query_simstate_behavior`、`query_state_transition`、`query_supply_net`、`query_supply_port`、`query_supply_set`、`query_upf2hdl_vct`、`query_use_interface_cell`

### その他、表に入れなかったもの

- 付属書 C.2 / C.3 の Tcl の手続き (proc): 問合せコマンドの使い方を示す例で、規格が定義するコマンドではありません。
- 付属書 J の SAIF (Switching Activity Interchange Format): UPF のコマンドではなく、別のファイル形式の定義です。
- Clause 10 の情報モデルのクラスとプロパティの一覧: HDL から使う ID は「HDL パッケージの型・列挙・解決関数」の `upfClassIdE` / `upfPropertyIdE` の行に、個数と先頭の例だけを載せています。全体は 11.2.2.5 の Table 42 と 11.2.2.6 の Table 43 を参照してください。

## 出典

- [IEEE Std 1801-2024, IEEE Standard for Design and Verification of Low-Power, Energy-Aware Electronic Systems (IEEE Xplore)](https://ieeexplore.ieee.org/document/10910082): この索引の唯一の出典。節番号とページ番号はこの規格のもの
- [IEEE SA Open UPF リポジトリ (opensource.ieee.org/upf)](https://opensource.ieee.org/upf): 規格の 1.6 と 11.2.4 / 11.2.5 が、HDL パッケージのコードの入手先として案内しているリポジトリ

この README は `upf_commands.json` から `tools/render.py` で生成しています。データは、規格の PDF から取り出した構文の骨組み (`tools/extract_tables.py`、`tools/parse_syntax.py`、`tools/extract_values.py`) と、日本語の説明 (`tools/ja/`) を `tools/build_json.py` で合わせて作り、`tools/check.py` で確認しています。

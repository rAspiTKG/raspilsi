## 6. 各ブロックの詳細

| モジュール | ファイル | 内容 |
|---|---|---|
| BAYER_EX_PKG | `rtl/BAYER_EX_PKG.sv` | 構成定数、`bayer4x2_t`、`cfg_t`、色の位置の関数 `f_site` |
| BAYER_EX_DATA_IF | `rtl/BAYER_EX_DATA_IF.sv` | data だけのインタフェース(4.3) |
| BAYER_EX_PIXCOR | `rtl/BAYER_EX_PIXCOR.sv` | 画素ごとの補正(黒レベル・ゲイン)。2段のパイプライン |
| BAYER_EX_CORE | `rtl/BAYER_EX_CORE.sv` | コア。入力段とスキッド、全体停止の判定、設定の FF、PIXCOR |
| BAYER_EX | `rtl/BAYER_EX.sv` | 論理合成・配置配線のトップ(ポートを平らにしたラッパ) |

コーディングの決まり: 有効ビット(制御)の FF はリセットあり、データの FF はリセットなし(有効な転送のときだけ取り込む)。FF は `r_`、組み合わせの信号とインタフェースのインスタンスは `s_`、インスタンスは `u_` で始めます。

### 6.1 BAYER_EX(トップ)

`BAYER_EX_DATA_IF` を2つ(s_i_pix、s_o_pix)作り、i_data / o_data と assign でつないで `BAYER_EX_CORE` に渡します。端子表は 4.2 です。

![BAYER_EX](../arch/bayer_ex_top.svg)

1フレームの入出力の例(16×4画素 = 8転送)です。入力は5転送目の前に2クロックあけ、出力側は2転送目から8クロック busy を出しています。止めている間に入力段とスキッドが埋まり、o_busy=1 の間、送り側は6転送目の vld と data を保持します。

{{WAVE:top_frame}}

### 6.2 BAYER_EX_CORE

![BAYER_EX_CORE](../arch/bayer_ex_core.svg)

{{PINS:BAYER_EX_CORE}}

**入力段とスキッド**

入力の転送は、まず入力段(r_in_vld / r_in_data)で受けます。入力段は「空いている」か「PIXCOR が進む(s_en=1)」ときに更新できます(s_in_free)。更新できないクロックに来た転送は、スキッド(r_skd_vld / r_skd_data)で受けます。o_busy はスキッドの有効ビットそのもの(FF)です。

| スキッド | s_in_free | このクロックの入力の転送(i_vld=1 かつ o_busy=0) | 次のクロック |
|---|---|---|---|
| 空 | 1 | 入力段に入れる | 入力段 = 転送 |
| 空 | 0 | スキッドに入れる | スキッドが埋まる(o_busy=1) |
| 埋まっている(o_busy=1) | 1 | 受け取らない | スキッドの転送を入力段へ移す(o_busy=0) |
| 埋まっている(o_busy=1) | 0 | 受け取らない | そのまま |

**全体停止**

出力が止められている(o_vld=1 かつ i_busy=1)ときは s_en=0 にして、PIXCOR の2段を止めます(有効ビットもデータも保持)。o_vld=0 のときは i_busy=1 でも進めます(空いた段を詰める)。

- コアが持てる転送は最大4つです(PIXCOR の2段、入力段、スキッド)。
- o_busy が i_busy に組み合わせで依存しないように、o_busy は1クロック遅れて上がります。その1クロックに来た転送をスキッドが受けます [R2]。
- 止められた後に動き出すと、スキッドの転送を入力段へ移すクロックだけ、入力の転送を受けません(o_busy=1 が1クロック残る)。

1転送が進む様子(レイテンシ3):

{{WAVE:core_pipe}}

出力を止めたときの様子:

{{WAVE:core_stall}}

**設定の FF**

i_cfg を毎クロック r_cfg で受け直してから PIXCOR に渡します。入力ポートから乗算器への長い経路を FF で切るためです(7.2)。

### 6.3 BAYER_EX_PIXCOR

![BAYER_EX_PIXCOR](../arch/bayer_ex_pixcor.svg)

{{PINS:BAYER_EX_PIXCOR}}

- 色の選択: 8画素のそれぞれについて、`f_site(phase, y, x[0])` で色を決め、黒レベル(s_lvl)とゲイン(s_gain)を選びます。設定は準静的なので、この選択は設定を変えたときだけ変わります。
- 1段目: 5.2 の黒レベル補正。i_en=1 かつ i_vld=1 のとき r_data1 に取り込みます。
- 2段目: 5.3 のゲイン(乗算 30bit、四捨五入、14bit に飽和)。i_en=1 かつ r_vld1=1 のとき r_data2 に取り込みます。
- bypass=1 のときは、どちらの段も入力の値をそのまま渡します。
- sof / eol / eof は計算せず、r_data1 → r_data2 とそのまま運びます。
- 有効ビット r_vld1 / r_vld2 は、i_en=1 のクロックだけ進みます。

{{WAVE:pixcor}}

{{WAVE:pixcor_bypass}}

### 6.4 BAYER_EX_DATA_IF

4.3 を見てください。modport mon は検証環境用です(DUT では使わない)。

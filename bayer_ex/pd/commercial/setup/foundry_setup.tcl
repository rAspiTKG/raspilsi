# ============================================================================
# Foundry の PDK・ライブラリの設定(雛形。未検証)
#
#   Genus / Innovus / Tempus のスクリプトがこのファイルを読む。
#   <...> の項目は Foundry の PDK と Cadence のリファレンスフローに合わせて記入する。
#   ここに書いたファイル名・セル名・コーナー名は記入例で、実在の名前ではない。
#   BAYER_EX は標準セルだけでできている(SRAM・同期化セルなどの製品IPはない)。
#
#   プロセスによって変わる、配置配線に関係すること
#     - 電源配線の作り方はプロセスによって違う。PDK のリファレンスフローの手順に従う
#       (BEX_PDN_TCL に指定する)
#     - しきい値電圧(Vt)の種類が多いときは、使うセルを BEX_DONT_USE で絞る
# ============================================================================

# ----------------------------------------------------------------------------
# PDK の場所
# ----------------------------------------------------------------------------
set BEX_PDK_ROOT   "<PDK_ROOT>"
set BEX_STD_ROOT   "$BEX_PDK_ROOT/<stdcell_library>"

# ----------------------------------------------------------------------------
# 物理情報(LEF)
# ----------------------------------------------------------------------------
set BEX_TECH_LEF   "$BEX_PDK_ROOT/<techlef>/<tech>.tlef"
set BEX_STD_LEF    [list "$BEX_STD_ROOT/lef/<stdcell>.lef"]

# ----------------------------------------------------------------------------
# タイミングライブラリ(コーナーごと)。名前は BEX_VIEWS で使う
# ----------------------------------------------------------------------------
set BEX_LIB(ss) [list "$BEX_STD_ROOT/lib/<stdcell_ss_corner>.lib"]
set BEX_LIB(tt) [list "$BEX_STD_ROOT/lib/<stdcell_tt_corner>.lib"]
set BEX_LIB(ff) [list "$BEX_STD_ROOT/lib/<stdcell_ff_corner>.lib"]

# ライブラリの単位(SDC の BEX_TIME_UNIT / BEX_CAP_UNIT に渡す。ns/pF か ps/fF)
set BEX_TIME_UNIT  "ns"
set BEX_CAP_UNIT   "pF"

# ----------------------------------------------------------------------------
# 配線の抽出(Quantus の qrcTechFile)と温度
# ----------------------------------------------------------------------------
set BEX_QRC(cworst)  "$BEX_PDK_ROOT/<qrc>/<cworst>/qrcTechFile"
set BEX_QRC(cbest)   "$BEX_PDK_ROOT/<qrc>/<cbest>/qrcTechFile"
set BEX_QRC(typical) "$BEX_PDK_ROOT/<qrc>/<typical>/qrcTechFile"
set BEX_RC_TEMP(cworst)  125
set BEX_RC_TEMP(cbest)   -40
set BEX_RC_TEMP(typical) 25

# ----------------------------------------------------------------------------
# 解析ビュー {ビュー名 ライブラリのコーナー RCコーナー 用途}
#   用途: setup / hold / both(両方) / none(レポートだけ)
# ----------------------------------------------------------------------------
set BEX_VIEWS {
  {func_ss_cworst ss cworst setup}
  {func_ff_cbest  ff cbest  hold}
  {func_ss_cbest  ss cbest  hold}
  {func_tt_typ    tt typical none}
}

# ----------------------------------------------------------------------------
# 電源
# ----------------------------------------------------------------------------
set BEX_POWER_NET    "VDD"
set BEX_GROUND_NET   "VSS"
set BEX_POWER_PIN    "VDD"
set BEX_GROUND_PIN   "VSS"
# 電源配線(PDK のリファレンスフローのスクリプトを指定する)
set BEX_PDN_TCL      "$BEX_PDK_ROOT/<reference_flow>/<pdn>.tcl"

# ----------------------------------------------------------------------------
# セル
# ----------------------------------------------------------------------------
set BEX_SITE         "<core_site>"
set BEX_DONT_USE     [list "<cell_pattern_to_avoid>*"]
set BEX_TIE_CELLS    [list "<TIEHI_CELL>" "<TIELO_CELL>"]
set BEX_FILLER_CELLS [list "<FILLER_CELL>"]
set BEX_DECAP_CELLS  [list "<DECAP_CELL>"]
set BEX_TAP_CELL     ""
set BEX_TAP_INTERVAL 0
set BEX_ENDCAP_LEFT  ""
set BEX_ENDCAP_RIGHT ""
set BEX_CTS_BUF_CELLS [list "<CLOCK_BUFFER_CELL>"]
set BEX_CTS_INV_CELLS [list "<CLOCK_INVERTER_CELL>"]
set BEX_CTS_ICG_CELLS [list "<CLOCK_GATING_CELL>"]

# ----------------------------------------------------------------------------
# 配線層
# ----------------------------------------------------------------------------
set BEX_ROUTE_BOTTOM     "<M1>"
set BEX_ROUTE_TOP        "<Mtop_signal>"
set BEX_CLK_LAYER_BOTTOM "<M_clk_bottom>"
set BEX_CLK_LAYER_TOP    "<M_clk_top>"
set BEX_PIN_LAYER_H      "<M_pin_horizontal>"
set BEX_PIN_LAYER_V      "<M_pin_vertical>"

# ----------------------------------------------------------------------------
# サインオフ(GDS、LVS、DRC)
# ----------------------------------------------------------------------------
set BEX_STREAM_MAP   "$BEX_PDK_ROOT/<stream>/<layer>.map"
set BEX_GDS_FILES    [list "$BEX_STD_ROOT/gds/<stdcell>.gds"]
set BEX_CDL_FILES    [list "$BEX_STD_ROOT/cdl/<stdcell>.cdl"]

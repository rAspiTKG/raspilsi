# ============================================================================
# Foundry の PDK・ライブラリの設定(雛形。未検証)
#
#   Genus / Innovus / Tempus のスクリプトがこのファイルを読む。
#   <...> の項目は Foundry の PDK と Cadence のリファレンスフローに合わせて記入する。
#   ここに書いたファイル名・セル名・コーナー名は記入例で、実在の名前ではない。
#
#   プロセスによって変わる、配置配線に関係すること
#     - 電源配線の作り方はプロセスによって違う。PDK のリファレンスフローの手順に従う
#       (B2R_PDN_TCL に指定する)
#     - しきい値電圧(Vt)の種類が多いときは、使うセルを B2R_DONT_USE で絞る
# ============================================================================

# ----------------------------------------------------------------------------
# PDK の場所
# ----------------------------------------------------------------------------
set B2R_PDK_ROOT   "<PDK_ROOT>"
set B2R_STD_ROOT   "$B2R_PDK_ROOT/<stdcell_library>"
# メモリコンパイラの出力(SRAM 1R1W。syn/rtl/foundry/BAYER2RGB_SRAM_1R1W.sv のマクロ)
set B2R_MEM_ROOT   "<MEMORY_COMPILER_OUTPUT>"

# ----------------------------------------------------------------------------
# 物理情報(LEF)
# ----------------------------------------------------------------------------
set B2R_TECH_LEF   "$B2R_PDK_ROOT/<techlef>/<tech>.tlef"
set B2R_STD_LEF    [list "$B2R_STD_ROOT/lef/<stdcell>.lef"]
set B2R_MEM_LEF    [glob -nocomplain "$B2R_MEM_ROOT/*/*.lef"]

# ----------------------------------------------------------------------------
# タイミングライブラリ(コーナーごと)
#   名前は B2R_VIEWS で使う。標準セルとメモリの両方を並べる
# ----------------------------------------------------------------------------
set B2R_LIB(ss) [concat \
  [list "$B2R_STD_ROOT/lib/<stdcell_ss_corner>.lib"] \
  [glob -nocomplain "$B2R_MEM_ROOT/*/*<ss_corner>*.lib"]]
set B2R_LIB(tt) [concat \
  [list "$B2R_STD_ROOT/lib/<stdcell_tt_corner>.lib"] \
  [glob -nocomplain "$B2R_MEM_ROOT/*/*<tt_corner>*.lib"]]
set B2R_LIB(ff) [concat \
  [list "$B2R_STD_ROOT/lib/<stdcell_ff_corner>.lib"] \
  [glob -nocomplain "$B2R_MEM_ROOT/*/*<ff_corner>*.lib"]]

# ライブラリの単位(SDC の B2R_TIME_UNIT / B2R_CAP_UNIT に渡す。ns/pF か ps/fF)
set B2R_TIME_UNIT  "ns"
set B2R_CAP_UNIT   "pF"

# ----------------------------------------------------------------------------
# 配線の抽出(Quantus の qrcTechFile)と温度
# ----------------------------------------------------------------------------
set B2R_QRC(cworst)  "$B2R_PDK_ROOT/<qrc>/<cworst>/qrcTechFile"
set B2R_QRC(cbest)   "$B2R_PDK_ROOT/<qrc>/<cbest>/qrcTechFile"
set B2R_QRC(typical) "$B2R_PDK_ROOT/<qrc>/<typical>/qrcTechFile"
set B2R_RC_TEMP(cworst)  125
set B2R_RC_TEMP(cbest)   -40
set B2R_RC_TEMP(typical) 25

# ----------------------------------------------------------------------------
# 解析ビュー {ビュー名 ライブラリのコーナー RCコーナー 用途}
#   用途: setup / hold / both(両方) / none(レポートだけ)
# ----------------------------------------------------------------------------
set B2R_VIEWS {
  {func_ss_cworst ss cworst setup}
  {func_ff_cbest  ff cbest  hold}
  {func_ss_cbest  ss cbest  hold}
  {func_tt_typ    tt typical none}
}

# ----------------------------------------------------------------------------
# 電源
# ----------------------------------------------------------------------------
set B2R_POWER_NET    "VDD"
set B2R_GROUND_NET   "VSS"
set B2R_POWER_PIN    "VDD"
set B2R_GROUND_PIN   "VSS"
# 電源配線(PDK のリファレンスフローのスクリプトを指定する)
set B2R_PDN_TCL      "$B2R_PDK_ROOT/<reference_flow>/<pdn>.tcl"

# ----------------------------------------------------------------------------
# セル
# ----------------------------------------------------------------------------
set B2R_SITE         "<core_site>"
set B2R_DONT_USE     [list "<cell_pattern_to_avoid>*"]
set B2R_TIE_CELLS    [list "<TIEHI_CELL>" "<TIELO_CELL>"]
set B2R_FILLER_CELLS [list "<FILLER_CELL>"]
set B2R_DECAP_CELLS  [list "<DECAP_CELL>"]
set B2R_TAP_CELL     ""
set B2R_TAP_INTERVAL 0
set B2R_ENDCAP_LEFT  ""
set B2R_ENDCAP_RIGHT ""
set B2R_CTS_BUF_CELLS [list "<CLOCK_BUFFER_CELL>"]
set B2R_CTS_INV_CELLS [list "<CLOCK_INVERTER_CELL>"]
set B2R_CTS_ICG_CELLS [list "<CLOCK_GATING_CELL>"]
# 同期化セル(syn/rtl/foundry/BAYER2RGB_SYNC2.sv で使う。最適化から外す)
#   RTL の雛形のセル名と同じにする(PDK のセル名に書き換えるときは両方を直す)
set B2R_SYNC2_CELLS  [list B2R_SYNC2_RCELL B2R_SYNC2_SCELL]

# ----------------------------------------------------------------------------
# 配線層
# ----------------------------------------------------------------------------
set B2R_ROUTE_BOTTOM   "<M1>"
set B2R_ROUTE_TOP      "<Mtop_signal>"
set B2R_CLK_LAYER_BOTTOM "<M_clk_bottom>"
set B2R_CLK_LAYER_TOP    "<M_clk_top>"
set B2R_PIN_LAYER_H    "<M_pin_horizontal>"
set B2R_PIN_LAYER_V    "<M_pin_vertical>"

# ----------------------------------------------------------------------------
# サインオフ(GDS、LVS、DRC)
# ----------------------------------------------------------------------------
set B2R_STREAM_MAP   "$B2R_PDK_ROOT/<stream>/<layer>.map"
set B2R_GDS_FILES    [concat [list "$B2R_STD_ROOT/gds/<stdcell>.gds"] [glob -nocomplain "$B2R_MEM_ROOT/*/*.gds"]]
set B2R_CDL_FILES    [concat [list "$B2R_STD_ROOT/cdl/<stdcell>.cdl"] [glob -nocomplain "$B2R_MEM_ROOT/*/*.cdl"]]

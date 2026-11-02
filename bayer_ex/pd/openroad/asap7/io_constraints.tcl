# ============================================================================
# 端子の置き場所(ORFS の IO_CONSTRAINTS。端子の配置の前に読まれる)
#   データの流れに合わせて、左から右へ流れるように置く
#     左辺: 入力側(i_vld、i_data、o_busy)
#     右辺: 出力側(o_vld、o_data、i_busy)
#     上辺: 設定(i_cfg)
#     下辺: clk、rst_n
# ============================================================================
proc bex_pins {pats} {
  set names {}
  foreach pat $pats {
    foreach p [get_ports $pat] {
      lappend names [get_full_name $p]
    }
  }
  return $names
}

set_io_pin_constraint -pin_names [bex_pins {i_vld o_busy i_data*}] -region left:*
set_io_pin_constraint -pin_names [bex_pins {o_vld i_busy o_data*}] -region right:*
set_io_pin_constraint -pin_names [bex_pins {i_cfg*}] -region top:*
set_io_pin_constraint -pin_names [bex_pins {clk rst_n}] -region bottom:*

//=============================================================================
// lb_coverage.svh
//-----------------------------------------------------------------------------
//  機能カバレッジ。
//    cg_cmd   : コマンドの形 (幅 / 高さ / stride / 4KB 跨ぎ) と、スレーブの振る舞い、
//               結果 (正常 / Read エラー / Write エラー / コマンド誤り / 空)、
//               scratchpad が満杯まで溜まったか
//    cg_tail  : ライン末尾の端数 (入力ビート / 出力ビート / SRAM ワード)
//    cg_burst : DUT が出したバーストの方向と長さ、4KB 境界で終わるバースト
//
//  構成によって起こり得ない項目 (1 画素/ワードでの「ワードの端数」など) は、
//  その covergroup を生成しないことでカバレッジの分母から外す。
//=============================================================================

`uvm_analysis_imp_decl(_cstart)
`uvm_analysis_imp_decl(_cdone)
`uvm_analysis_imp_decl(_cburst)

class lb_coverage extends uvm_component;

  `uvm_component_utils(lb_coverage)

  typedef enum {
    RES_OK
   ,RES_ERR_RD
   ,RES_ERR_WR
   ,RES_ERR_CFG
   ,RES_EMPTY
  } result_e;

  typedef enum {
    W_ONE
   ,W_MID
   ,W_MAX
  } wclass_e;

  typedef enum {
    H_ONE
   ,H_FIT
   ,H_OVER
  } hclass_e;

  typedef enum {
    STR_ZERO
   ,STR_MIN
   ,STR_GAP
  } strclass_e;

  typedef enum {
    BL_ONE
   ,BL_MID
   ,BL_MAX
  } blclass_e;

  uvm_analysis_imp_cstart #(cmd_item, lb_coverage)       start_imp;
  uvm_analysis_imp_cdone  #(cmd_item, lb_coverage)       done_imp;
  uvm_analysis_imp_cburst #(axi_burst_item, lb_coverage) burst_imp;

  axi_slv_cfg rd_cfg;
  axi_slv_cfg wr_cfg;

  // サンプル値
  protected wclass_e     m_w;
  protected hclass_e     m_h;
  protected strclass_e   m_sstr;
  protected strclass_e   m_dstr;
  protected bit          m_src_x4k;
  protected bit          m_dst_x4k;
  protected int unsigned m_rd_stall;
  protected int unsigned m_wr_stall;
  protected bit          m_rwv;
  protected result_e     m_result;
  protected bit          m_sp_full;
  protected bit          m_exec;
  protected bit          m_in_tail;
  protected bit          m_out_tail;
  protected bit          m_word_tail;
  protected axi_dir_e    m_dir;
  protected blclass_e    m_bl;
  protected bit          m_end4k;

  covergroup cg_cmd;
    option.per_instance = 1;
    cp_w : coverpoint m_w {
      bins one = {W_ONE};
      bins mid = {W_MID};
      bins max = {W_MAX};
    }
    cp_h : coverpoint m_h {
      bins one  = {H_ONE};
      bins fit  = {H_FIT};
      bins over = {H_OVER};
    }
    cp_sstr : coverpoint m_sstr {
      bins zero = {STR_ZERO};
      bins min  = {STR_MIN};
      bins gap  = {STR_GAP};
    }
    cp_dstr : coverpoint m_dstr {
      bins min = {STR_MIN};
      bins gap = {STR_GAP};
    }
    cp_src_x4k : coverpoint m_src_x4k;
    cp_dst_x4k : coverpoint m_dst_x4k;
    cp_rd_stall : coverpoint m_rd_stall {
      bins none  = {0};
      bins some  = {[1:49]};
      bins heavy = {[50:100]};
    }
    cp_wr_stall : coverpoint m_wr_stall {
      bins none  = {0};
      bins some  = {[1:49]};
      bins heavy = {[50:100]};
    }
    cp_rwv : coverpoint m_rwv;
    cp_sp_full : coverpoint m_sp_full;
    x_wh : cross cp_w, cp_h;
    x_stall : cross cp_rd_stall, cp_wr_stall;
  endgroup

  covergroup cg_result;
    option.per_instance = 1;
    cp_result : coverpoint m_result {
      bins ok      = {RES_OK};
      bins err_rd  = {RES_ERR_RD};
      bins err_wr  = {RES_ERR_WR};
      bins err_cfg = {RES_ERR_CFG};
      bins empty   = {RES_EMPTY};
    }
  endgroup

  covergroup cg_tail;
    option.per_instance = 1;
    // 入力側と出力側の端数の組み合わせは、バス幅の比によって起こり得ないものがあるので cross にしない
    cp_in_tail : coverpoint m_in_tail;
    cp_out_tail : coverpoint m_out_tail;
  endgroup

  covergroup cg_word;
    option.per_instance = 1;
    cp_word_tail : coverpoint m_word_tail;
  endgroup

  covergroup cg_burst;
    option.per_instance = 1;
    cp_dir : coverpoint m_dir;
    cp_bl : coverpoint m_bl {
      bins one = {BL_ONE};
      bins mid = {BL_MID};
      bins max = {BL_MAX};
    }
    cp_end4k : coverpoint m_end4k;
    x_dir_bl : cross cp_dir, cp_bl;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    start_imp = new("start_imp", this);
    done_imp  = new("done_imp", this);
    burst_imp = new("burst_imp", this);
    cg_cmd    = new();
    cg_result = new();
    cg_burst  = new();
    // ビート / ワードの端数は、バス幅や 1 ワードの画素数が 1 より大きいときだけ起こる
    if( (IN_STRB_W>1)&&(OUT_STRB_W>1) ) begin
      cg_tail = new();
    end
    if( PIX_PER_WORD>1 ) begin
      cg_word = new();
    end
  endfunction

  // base から nbytes の範囲が 4KB 境界を跨ぐか
  protected function bit crosses_4k(bit [63:0] base, int unsigned nbytes);
    return (32'(base[11:0])+nbytes)>4096;
  endfunction

  protected function strclass_e stride_class(int unsigned stride, int unsigned lb, int unsigned bus_bytes);
    int unsigned min_stride;
    min_stride = lb_align_up(lb, bus_bytes);
    if( stride==0 ) begin
      return STR_ZERO;
    end
    if( stride==min_stride ) begin
      return STR_MIN;
    end
    return STR_GAP;
  endfunction

  // 受付時: コマンドの形とスレーブの設定を記録
  //   (完了時にはスレーブの設定が次の値に変わっている可能性がある)
  function void write_cstart(cmd_item c);
    int unsigned lb;
    bit [63:0]   sa;
    bit [63:0]   da;
    lb     = lb_line_bytes(c.w);
    m_exec = !lb_scoreboard::cmd_is_empty(c)&&!lb_scoreboard::cmd_is_bad(c);
    if( c.w<=1 ) begin
      m_w = W_ONE;
    end else if( c.w>=MAX_LINE_PIXELS ) begin
      m_w = W_MAX;
    end else begin
      m_w = W_MID;
    end
    if( c.h<=1 ) begin
      m_h = H_ONE;
    end else if( c.h<=NUM_LINES ) begin
      m_h = H_FIT;
    end else begin
      m_h = H_OVER;
    end
    m_sstr      = stride_class(c.sstr, lb, IN_STRB_W);
    m_dstr      = stride_class(c.dstr, lb, OUT_STRB_W);
    m_src_x4k   = 1'b0;
    m_dst_x4k   = 1'b0;
    for( int unsigned y=0; y<c.h; y++ ) begin
      sa = c.src + (64'(y) * 64'(c.sstr));
      da = c.dst + (64'(y) * 64'(c.dstr));
      if( crosses_4k(sa,lb) ) begin
        m_src_x4k = 1'b1;
      end
      if( crosses_4k(da,lb) ) begin
        m_dst_x4k = 1'b1;
      end
    end
    m_in_tail   = ((lb%IN_STRB_W)!=0);
    m_out_tail  = ((lb%OUT_STRB_W)!=0);
    m_word_tail = ((c.w%PIX_PER_WORD)!=0);
    m_rd_stall  = rd_cfg.stall_pct;
    m_wr_stall  = wr_cfg.stall_pct;
    m_rwv       = rd_cfg.ready_wait_valid||wr_cfg.ready_wait_valid;
  endfunction

  function void write_cdone(cmd_item c);
    if( lb_scoreboard::cmd_is_empty(c) ) begin
      m_result = RES_EMPTY;
    end else if( c.err_flags[2] ) begin
      m_result = RES_ERR_CFG;
    end else if( c.err_flags[1] ) begin
      m_result = RES_ERR_WR;
    end else if( c.err_flags[0] ) begin
      m_result = RES_ERR_RD;
    end else begin
      m_result = RES_OK;
    end
    m_sp_full = (c.max_sp_level==NUM_LINES);
    cg_result.sample();
    // 形のカバレッジは、実際に転送したコマンドだけ数える
    if( m_exec ) begin
      cg_cmd.sample();
      if( cg_tail!=null ) begin
        cg_tail.sample();
      end
      if( cg_word!=null ) begin
        cg_word.sample();
      end
    end
  endfunction

  function void write_cburst(axi_burst_item t);
    int unsigned bl;
    int unsigned maxb;
    int unsigned bus_bytes;
    bl        = 32'(t.len) + 1;
    maxb      = (t.dir==AXI_WRITE) ? OUT_MAX_BURST : IN_MAX_BURST;
    bus_bytes = (t.dir==AXI_WRITE) ? OUT_STRB_W : IN_STRB_W;
    m_dir     = t.dir;
    if( bl>=maxb ) begin
      m_bl = BL_MAX;
    end else if( bl==1 ) begin
      m_bl = BL_ONE;
    end else begin
      m_bl = BL_MID;
    end
    m_end4k = ((32'(t.addr[11:0])+(bl*bus_bytes))%4096)==0;
    cg_burst.sample();
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV", $sformatf("cg_cmd = %0.1f %%  cg_result = %0.1f %%  cg_burst = %0.1f %%"
                              , cg_cmd.get_inst_coverage(), cg_result.get_inst_coverage(), cg_burst.get_inst_coverage()), UVM_NONE)
  endfunction

endclass

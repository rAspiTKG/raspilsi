//=============================================================================
// axlm_coverage.svh
//-----------------------------------------------------------------------------
//  機能カバレッジ。
//    cg_cmd      : 実行したコマンドの形 (方向 / アドレスの進め方 / PROT / スレーブが理想的か)
//    cg_len      : 転送数 (1 / 中間 / 最大) と内部メモリの位置 (先頭 / 中間 / 末尾) × 方向
//    cg_top      : アドレス空間の最後のワードで終わるコマンド × 方向
//    cg_strb     : 書き込みコマンドの WSTRB (全て 0 / 全て 1 / 一部)
//    cg_result   : 結果 (正常 / SLVERR / DECERR / EXOKAY / メモリ範囲超え / 非アライン / 0 ワード) × 方向
//                  cg_res_range : アドレス範囲超え、cg_res_multi : 2 種類以上のエラー応答
//    cg_err      : 最初のエラー応答の位置 (先頭 / 中間 / 最後) × 方向
//    cg_stop     : STOP_ON_ERROR=1 で途中で止まった / 最後まで出した × 方向
//    cg_conc     : もう一方の方向のコマンドの実行中に受け付けた / 同じサイクルに受け付けた × 方向
//    cg_held     : 実行中に出したまま待たされたコマンド × 方向
//    cg_wr_tr    : 書き込みトランザクション (AW と W の順 / 応答 / 応答の遅延 / 読み出しと同時に未完了)
//    cg_rd_tr    : 読み出しトランザクション (応答 / 応答の遅延 / 書き込みと同時に未完了)
//    cg_depth    : バス上の未完了数が 1 / 上限 に達した × 方向。cg_depth_mid : 中間 (上限 3 以上)
//    cg_local    : ローカルポート (書き込み / 読み出し × 連続 / コマンドの受付と同じサイクル /
//                  反対方向のコマンドの実行中 / 待たされた)
//    cg_local_oor : ローカルポートの範囲外アドレス
//
//  構成によって起こり得ない項目は、その covergroup を生成しないことで分母から外す。
//=============================================================================

`uvm_analysis_imp_decl(_cwstart)
`uvm_analysis_imp_decl(_crstart)
`uvm_analysis_imp_decl(_cwdone)
`uvm_analysis_imp_decl(_crdone)
`uvm_analysis_imp_decl(_caxi)
`uvm_analysis_imp_decl(_cmem)

class axlm_coverage extends uvm_component;

  `uvm_component_utils(axlm_coverage)

  typedef enum {
    L_ONE
   ,L_MID
   ,L_MAX
  } lclass_e;

  typedef enum {
    MP_FIRST
   ,MP_MID
   ,MP_TAIL
  } mclass_e;

  typedef enum {
    RES_OK
   ,RES_SLVERR
   ,RES_DECERR
   ,RES_EXOKAY
   ,RES_MULTI
   ,RES_BAD_MEM
   ,RES_BAD_ALIGN
   ,RES_BAD_RANGE
   ,RES_EMPTY
  } result_e;

  typedef enum {
    EP_FIRST
   ,EP_MID
   ,EP_LAST
  } epos_e;

  typedef enum {
    ST_NONE
   ,ST_ONE
   ,ST_MANY
  } strb_e;

  typedef enum {
    OR_AW_FIRST
   ,OR_W_FIRST
   ,OR_SAME
  } order_e;

  typedef enum {
    LT_ZERO
   ,LT_SHORT
   ,LT_LONG
  } lat_e;

  uvm_analysis_imp_cwstart #(cmd_item, axlm_coverage) wstart_imp;
  uvm_analysis_imp_crstart #(cmd_item, axlm_coverage) rstart_imp;
  uvm_analysis_imp_cwdone  #(cmd_item, axlm_coverage) wdone_imp;
  uvm_analysis_imp_crdone  #(cmd_item, axlm_coverage) rdone_imp;
  uvm_analysis_imp_caxi    #(axi_item, axlm_coverage) axi_imp;
  uvm_analysis_imp_cmem    #(mem_item, axlm_coverage) mem_imp;

  axi_slv_cfg cfg;

  // 受付時の値 (方向ごと)
  protected bit          m_s_ideal[2];
  // サンプル値 (コマンド)
  protected bit          m_wr;
  protected bit          m_incr;
  protected bit [2:0]    m_prot;
  protected bit          m_ideal;
  protected lclass_e     m_len;
  protected mclass_e     m_mpos;
  protected strb_e       m_strb;
  protected result_e     m_result;
  protected epos_e       m_epos;
  protected bit          m_stopped;
  protected bit          m_conc_busy;
  protected bit          m_conc_same;
  // サンプル値 (トランザクション)
  protected order_e      m_order;
  protected bit [1:0]    m_resp;
  protected lat_e        m_lat;
  protected bit          m_other;
  protected bit          m_d_max;
  // サンプル値 (ローカルポート)
  protected bit          m_l_wr;
  protected bit          m_l_consec;
  protected bit          m_l_with_cmd;
  protected bit          m_l_during;
  protected bit          m_l_waited;

  covergroup cg_cmd;
    option.per_instance = 1;
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    cp_incr : coverpoint m_incr {
      bins fixed = {1'b0};
      bins incr  = {1'b1};
    }
    cp_prot : coverpoint m_prot {
      bins p0 = {3'd0};
      bins p1 = {3'd1};
      bins p2 = {3'd2};
      bins p3 = {3'd3};
      bins p4 = {3'd4};
      bins p5 = {3'd5};
      bins p6 = {3'd6};
      bins p7 = {3'd7};
    }
    cp_ideal : coverpoint m_ideal {
      bins stalls = {1'b0};
      bins ideal  = {1'b1};
    }
    x_dir_incr : cross cp_dir, cp_incr;
    x_dir_prot : cross cp_dir, cp_prot;
    x_dir_ideal : cross cp_dir, cp_ideal;
  endgroup

  covergroup cg_len;
    option.per_instance = 1;
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    cp_len : coverpoint m_len {
      bins one = {L_ONE};
      bins mid = {L_MID};
      bins max = {L_MAX};
    }
    cp_mpos : coverpoint m_mpos {
      bins first = {MP_FIRST};
      bins mid   = {MP_MID};
      bins tail  = {MP_TAIL};
    }
    x_dir_len : cross cp_dir, cp_len;
    x_dir_mpos : cross cp_dir, cp_mpos;
  endgroup

  covergroup cg_top;
    option.per_instance = 1;
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
  endgroup

  covergroup cg_strb;
    option.per_instance = 1;
    cp_strb : coverpoint m_strb {
      bins none = {ST_NONE};
      bins all  = {ST_ONE};
      bins part = {ST_MANY};
    }
  endgroup

  covergroup cg_result;
    option.per_instance = 1;
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    cp_result : coverpoint m_result {
      bins ok        = {RES_OK};
      bins slverr    = {RES_SLVERR};
      bins decerr    = {RES_DECERR};
      bins exokay    = {RES_EXOKAY};
      bins bad_mem   = {RES_BAD_MEM};
      bins bad_align = {RES_BAD_ALIGN};
      bins empty     = {RES_EMPTY};
    }
    x_dir_result : cross cp_dir, cp_result;
  endgroup

  covergroup cg_res_range;
    option.per_instance = 1;
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
  endgroup

  covergroup cg_res_multi;
    option.per_instance = 1;
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
  endgroup

  covergroup cg_err;
    option.per_instance = 1;
    cp_pos : coverpoint m_epos {
      bins first = {EP_FIRST};
      bins mid   = {EP_MID};
      bins last  = {EP_LAST};
    }
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    x_pos_dir : cross cp_pos, cp_dir;
  endgroup

  covergroup cg_stop;
    option.per_instance = 1;
    cp_stop : coverpoint m_stopped {
      bins all_issued = {1'b0};
      bins stopped    = {1'b1};
    }
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    x_stop_dir : cross cp_stop, cp_dir;
  endgroup

  covergroup cg_conc;
    option.per_instance = 1;
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    cp_busy : coverpoint m_conc_busy {
      bins during_other = {1'b1};
    }
    cp_same : coverpoint m_conc_same {
      bins alone       = {1'b0};
      bins same_cycle  = {1'b1};
    }
    x_dir_busy : cross cp_dir, cp_busy;
  endgroup

  covergroup cg_held;
    option.per_instance = 1;
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
  endgroup

  covergroup cg_wr_tr;
    option.per_instance = 1;
    cp_order : coverpoint m_order {
      bins aw_first = {OR_AW_FIRST};
      bins w_first  = {OR_W_FIRST};
      bins same     = {OR_SAME};
    }
    cp_resp : coverpoint m_resp {
      bins okay   = {2'b00};
      bins exokay = {2'b01};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
    cp_lat : coverpoint m_lat {
      bins zero  = {LT_ZERO};
      bins short = {LT_SHORT};
      bins long  = {LT_LONG};
    }
    cp_other : coverpoint m_other {
      bins alone     = {1'b0};
      bins with_read = {1'b1};
    }
    x_order_other : cross cp_order, cp_other;
  endgroup

  covergroup cg_rd_tr;
    option.per_instance = 1;
    cp_resp : coverpoint m_resp {
      bins okay   = {2'b00};
      bins exokay = {2'b01};
      bins slverr = {2'b10};
      bins decerr = {2'b11};
    }
    cp_lat : coverpoint m_lat {
      bins zero  = {LT_ZERO};
      bins short = {LT_SHORT};
      bins long  = {LT_LONG};
    }
    cp_other : coverpoint m_other {
      bins alone      = {1'b0};
      bins with_write = {1'b1};
    }
    x_lat_other : cross cp_lat, cp_other;
  endgroup

  covergroup cg_depth;
    option.per_instance = 1;
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    cp_max : coverpoint m_d_max {
      bins reached_max = {1'b1};
    }
    x_dir_max : cross cp_dir, cp_max;
  endgroup

  covergroup cg_local;
    option.per_instance = 1;
    cp_op : coverpoint m_l_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    cp_consec : coverpoint m_l_consec {
      bins single     = {1'b0};
      bins continuous = {1'b1};
    }
    cp_with_cmd : coverpoint m_l_with_cmd {
      bins alone    = {1'b0};
      bins with_cmd = {1'b1};
    }
    cp_during : coverpoint m_l_during {
      bins idle         = {1'b0};
      bins during_other = {1'b1};
    }
    cp_waited : coverpoint m_l_waited {
      bins at_once = {1'b0};
      bins waited  = {1'b1};
    }
    x_op_consec : cross cp_op, cp_consec;
    x_op_with_cmd : cross cp_op, cp_with_cmd;
    x_op_during : cross cp_op, cp_during;
    x_op_waited : cross cp_op, cp_waited;
  endgroup

  covergroup cg_local_oor;
    option.per_instance = 1;
    cp_op : coverpoint m_l_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    wstart_imp = new("wstart_imp", this);
    rstart_imp = new("rstart_imp", this);
    wdone_imp  = new("wdone_imp", this);
    rdone_imp  = new("rdone_imp", this);
    axi_imp    = new("axi_imp", this);
    mem_imp    = new("mem_imp", this);
    cg_cmd     = new();
    cg_top     = new();
    cg_strb    = new();
    cg_result  = new();
    cg_err     = new();
    cg_conc    = new();
    cg_held    = new();
    cg_wr_tr   = new();
    cg_rd_tr   = new();
    cg_depth   = new();
    cg_local   = new();
    // 構成によって起こり得ない項目は生成しない
    if( MEM_DEPTH>=3 ) begin
      cg_len = new();
    end
    if( MEM_DEPTH>=2 ) begin
      cg_res_range = new();
      // 2 種類のエラー応答 : 最後まで続ける構成、または止める前に次のトランザクションが出ている構成
      if( !STOP_ON_ERROR||((MAX_WR>=2)&&(MAX_RD>=2)) ) begin
        cg_res_multi = new();
      end
    end
    if( STOP_ON_ERROR ) begin
      cg_stop = new();
    end
    if( HAS_BAD_MEM ) begin
      cg_local_oor = new();
    end
  endfunction

  protected function void cmd_start(cmd_item c);
    int unsigned d;
    d            = c.wr ? 1 : 0;
    m_s_ideal[d] = cfg.is_ideal();
    m_wr         = c.wr;
    m_conc_busy  = c.other_busy;
    m_conc_same  = c.other_start;
    if( axlm_scoreboard::cmd_is_exec(c) ) begin
      if( c.other_busy||c.other_start ) begin
        cg_conc.sample();
      end
      if( c.held ) begin
        cg_held.sample();
      end
    end
  endfunction

  function void write_cwstart(cmd_item c);
    cmd_start(c);
  endfunction

  function void write_crstart(cmd_item c);
    cmd_start(c);
  endfunction

  protected function void cmd_done(cmd_item c);
    int unsigned d;
    bit [63:0]   last;
    int unsigned nkind;
    d      = c.wr ? 1 : 0;
    m_wr   = c.wr;
    m_incr = c.incr;
    m_prot = c.prot;
    // 結果
    nkind  = 32'(c.err_flags[0]) + 32'(c.err_flags[1]) + 32'(c.err_flags[3]);
    if( axlm_scoreboard::cmd_is_empty(c) ) begin
      m_result = RES_EMPTY;
    end else if( c.err_flags[2] ) begin
      if( axlm_scoreboard::mem_bad(c) ) begin
        m_result = RES_BAD_MEM;
      end else if( axlm_scoreboard::align_bad(c) ) begin
        m_result = RES_BAD_ALIGN;
      end else begin
        m_result = RES_BAD_RANGE;
      end
    end else if( nkind>=2 ) begin
      m_result = RES_MULTI;
    end else if( c.err_flags[0] ) begin
      m_result = RES_SLVERR;
    end else if( c.err_flags[1] ) begin
      m_result = RES_DECERR;
    end else if( c.err_flags[3] ) begin
      m_result = RES_EXOKAY;
    end else begin
      m_result = RES_OK;
    end
    if( (m_result!=RES_BAD_RANGE)&&(m_result!=RES_MULTI) ) begin
      cg_result.sample();
    end
    if( (cg_res_range!=null)&&(m_result==RES_BAD_RANGE) ) begin
      cg_res_range.sample();
    end
    if( (cg_res_multi!=null)&&(m_result==RES_MULTI) ) begin
      cg_res_multi.sample();
    end
    // 形のカバレッジは、実際に転送したコマンドだけ数える
    if( !axlm_scoreboard::cmd_is_exec(c) ) begin
      return;
    end
    m_ideal = m_s_ideal[d];
    cg_cmd.sample();
    if( c.len<=1 ) begin
      m_len = (c.len>=MEM_DEPTH) ? L_MAX : L_ONE;
    end else if( c.len>=MEM_DEPTH ) begin
      m_len = L_MAX;
    end else begin
      m_len = L_MID;
    end
    if( (c.maddr+c.len)>=MEM_DEPTH ) begin
      m_mpos = MP_TAIL;
    end else if( c.maddr==0 ) begin
      m_mpos = MP_FIRST;
    end else begin
      m_mpos = MP_MID;
    end
    if( cg_len!=null ) begin
      cg_len.sample();
    end
    // 最後のトランザクションがアドレス空間の最後のワード
    last = c.incr ? (c.addr + (64'(c.len-1) * 64'(STRB_W))) : c.addr;
    if( (last/64'(STRB_W))==(SPACE_WORDS-64'd1) ) begin
      cg_top.sample();
    end
    if( c.wr ) begin
      if( c.strb=={STRB_W{1'b0}} ) begin
        m_strb = ST_NONE;
      end else if( c.strb=={STRB_W{1'b1}} ) begin
        m_strb = ST_ONE;
      end else begin
        m_strb = ST_MANY;
      end
      cg_strb.sample();
    end
    // 最初のエラー応答の位置 (3 ワード以上のコマンドで見る)
    if( (c.err_flags&4'b1011)!=4'b0000 ) begin
      if( c.len>=3 ) begin
        if( c.err_index==0 ) begin
          m_epos = EP_FIRST;
        end else if( c.err_index==(c.len-1) ) begin
          m_epos = EP_LAST;
        end else begin
          m_epos = EP_MID;
        end
        cg_err.sample();
      end
      if( cg_stop!=null ) begin
        m_stopped = (c.done_count<c.len);
        cg_stop.sample();
      end
    end
  endfunction

  function void write_cwdone(cmd_item c);
    cmd_done(c);
  endfunction

  function void write_crdone(cmd_item c);
    cmd_done(c);
  endfunction

  function void write_caxi(axi_item t);
    int unsigned l;
    m_wr    = t.write;
    m_resp  = t.resp;
    m_other = t.other_out;
    l       = t.latency();
    if( l==0 ) begin
      m_lat = LT_ZERO;
    end else if( l<=3 ) begin
      m_lat = LT_SHORT;
    end else begin
      m_lat = LT_LONG;
    end
    if( t.write ) begin
      if( t.w_cyc>t.a_cyc ) begin
        m_order = OR_AW_FIRST;
      end else if( t.w_cyc<t.a_cyc ) begin
        m_order = OR_W_FIRST;
      end else begin
        m_order = OR_SAME;
      end
      cg_wr_tr.sample();
    end else begin
      cg_rd_tr.sample();
    end
    m_d_max = (t.depth>=(t.write ? MAX_WR : MAX_RD));
    if( m_d_max ) begin
      cg_depth.sample();
    end
  endfunction

  function void write_cmem(mem_item t);
    m_l_wr       = t.write;
    m_l_consec   = t.consec;
    m_l_with_cmd = t.with_wcmd||t.with_rcmd;
    m_l_during   = t.write ? t.during_wcmd : t.during_rcmd;
    m_l_waited   = t.waited;
    if( t.addr>=MEM_DEPTH ) begin
      if( cg_local_oor!=null ) begin
        cg_local_oor.sample();
      end
    end else begin
      cg_local.sample();
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV", $sformatf("cg_cmd = %0.1f %%  cg_result = %0.1f %%  cg_conc = %0.1f %%  cg_wr_tr = %0.1f %%  cg_rd_tr = %0.1f %%  cg_local = %0.1f %%", cg_cmd.get_inst_coverage(), cg_result.get_inst_coverage(), cg_conc.get_inst_coverage(), cg_wr_tr.get_inst_coverage(), cg_rd_tr.get_inst_coverage(), cg_local.get_inst_coverage()), UVM_NONE)
  endfunction

endclass

//=============================================================================
// apbm_coverage.svh
//-----------------------------------------------------------------------------
//  機能カバレッジ。
//    cg_cmd     : 実行したコマンドの形 (方向 / 転送数 / アドレスの進め方 / メモリ位置 /
//                 アドレス空間の末尾 / PPROT / ウェイトの有無)
//    cg_strb    : 書き込みコマンドの PSTRB (全て 0 / 全て 1)。cg_strb_part : 一部だけ 1
//    cg_sel     : 相手のスレーブ (最初 / 最後) × 方向
//    cg_result  : 結果 (正常 / PSLVERR / メモリ範囲超え / アドレス範囲超え / 0 ワード)
//                 cg_res_timeout / cg_res_align / cg_res_sel : タイムアウト / 非アライン /
//                 存在しないスレーブ番号
//    cg_err     : エラーになった転送の位置 (先頭 / 中間 / 最後) × 方向
//    cg_multi_err : 1 コマンドの中でエラーになった転送の数 (1 つ / 2 つ以上)。STOP_ON_ERROR=0 のときだけ
//    cg_xfer    : APB 転送ごと (方向 / ウェイト数 / back-to-back / PSLVERR / 末尾ワード)
//    cg_abort   : 打ち切った転送の方向
//    cg_local   : ローカルポート (書き込み / 読み出し、連続アクセス、コマンドと同じサイクル)
//    cg_local_oor : ローカルポートの範囲外アドレス
//
//  構成によって起こり得ない項目 (スレーブ 1 個での「最後のスレーブ」など) は、
//  その covergroup を生成しないことでカバレッジの分母から外す。
//=============================================================================

`uvm_analysis_imp_decl(_cstart)
`uvm_analysis_imp_decl(_cdone)
`uvm_analysis_imp_decl(_capb)
`uvm_analysis_imp_decl(_cmem)

class apbm_coverage extends uvm_component;

  `uvm_component_utils(apbm_coverage)

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
   ,RES_TIMEOUT
   ,RES_BAD_SEL
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
    WT_ZERO
   ,WT_ONE
   ,WT_MANY
  } wclass_e;

  uvm_analysis_imp_cstart #(usr_item, apbm_coverage) start_imp;
  uvm_analysis_imp_cdone  #(usr_item, apbm_coverage) done_imp;
  uvm_analysis_imp_capb   #(apb_item, apbm_coverage) apb_imp;
  uvm_analysis_imp_cmem   #(mem_item, apbm_coverage) mem_imp;

  apb_slv_cfg cfg[NUM_SLAVES];

  // サンプル値 (コマンド)
  protected bit          m_exec;
  protected bit          m_wr;
  protected lclass_e     m_len;
  protected bit          m_incr;
  protected mclass_e     m_mpos;
  protected bit          m_top;
  protected bit [2:0]    m_prot;
  protected bit          m_has_wait;
  protected bit          m_strb_all;
  protected bit          m_strb_part;
  protected bit          m_sel_last;
  protected bit          m_sel_edge;
  protected result_e     m_result;
  protected epos_e       m_epos;
  protected int unsigned m_n_xerr;     // 実行中のコマンドで、エラー (PSLVERR / 打ち切り) になった転送の数
  protected bit          m_multi_err;  // その数が 2 以上
  // サンプル値 (転送)
  protected bit          m_x_wr;
  protected wclass_e     m_x_wait;
  protected bit          m_x_b2b;
  protected bit          m_x_err;
  protected bit          m_x_top;
  // サンプル値 (ローカルポート)
  protected bit          m_l_wr;
  protected bit          m_l_consec;
  protected bit          m_l_with_cmd;

  covergroup cg_cmd;
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
    cp_incr : coverpoint m_incr {
      bins fixed = {1'b0};
      bins incr  = {1'b1};
    }
    cp_mpos : coverpoint m_mpos {
      bins first = {MP_FIRST};
      bins mid   = {MP_MID};
      bins tail  = {MP_TAIL};
    }
    cp_top : coverpoint m_top {
      bins low = {1'b0};
      bins top = {1'b1};
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
    cp_wait : coverpoint m_has_wait {
      bins none = {1'b0};
      bins some = {1'b1};
    }
    x_dir_len : cross cp_dir, cp_len;
    x_dir_incr : cross cp_dir, cp_incr;
    x_dir_wait : cross cp_dir, cp_wait;
  endgroup

  covergroup cg_strb;
    option.per_instance = 1;
    cp_strb : coverpoint m_strb_all {
      bins none = {1'b0};
      bins all  = {1'b1};
    }
  endgroup

  covergroup cg_strb_part;
    option.per_instance = 1;
    cp_part : coverpoint m_strb_part {
      bins part = {1'b1};
    }
  endgroup

  covergroup cg_sel;
    option.per_instance = 1;
    cp_sel : coverpoint m_sel_last {
      bins first = {1'b0};
      bins last  = {1'b1};
    }
    cp_dir : coverpoint m_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    x_sel_dir : cross cp_sel, cp_dir;
  endgroup

  covergroup cg_result;
    option.per_instance = 1;
    cp_result : coverpoint m_result {
      bins ok        = {RES_OK};
      bins slverr    = {RES_SLVERR};
      bins bad_mem   = {RES_BAD_MEM};
      bins bad_range = {RES_BAD_RANGE};
      bins empty     = {RES_EMPTY};
    }
  endgroup

  covergroup cg_res_timeout;
    option.per_instance = 1;
    cp_result : coverpoint m_result {
      bins timeout = {RES_TIMEOUT};
    }
  endgroup

  covergroup cg_res_align;
    option.per_instance = 1;
    cp_result : coverpoint m_result {
      bins bad_align = {RES_BAD_ALIGN};
    }
  endgroup

  covergroup cg_res_sel;
    option.per_instance = 1;
    cp_result : coverpoint m_result {
      bins bad_sel = {RES_BAD_SEL};
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

  covergroup cg_multi_err;
    option.per_instance = 1;
    cp_num : coverpoint m_multi_err {
      bins one  = {1'b0};
      bins many = {1'b1};
    }
  endgroup

  covergroup cg_xfer;
    option.per_instance = 1;
    cp_dir : coverpoint m_x_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    cp_wait : coverpoint m_x_wait {
      bins zero = {WT_ZERO};
      bins one  = {WT_ONE};
      bins many = {WT_MANY};
    }
    cp_b2b : coverpoint m_x_b2b {
      bins after_idle   = {1'b0};
      bins back_to_back = {1'b1};
    }
    cp_err : coverpoint m_x_err {
      bins okay   = {1'b0};
      bins slverr = {1'b1};
    }
    cp_top : coverpoint m_x_top {
      bins other     = {1'b0};
      bins last_word = {1'b1};
    }
    x_dir_wait : cross cp_dir, cp_wait;
    x_dir_b2b : cross cp_dir, cp_b2b;
    x_dir_err : cross cp_dir, cp_err;
  endgroup

  covergroup cg_abort;
    option.per_instance = 1;
    cp_dir : coverpoint m_x_wr {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
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
    x_op_consec : cross cp_op, cp_consec;
    x_op_with_cmd : cross cp_op, cp_with_cmd;
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
    start_imp = new("start_imp", this);
    done_imp  = new("done_imp", this);
    apb_imp   = new("apb_imp", this);
    mem_imp   = new("mem_imp", this);
    cg_cmd    = new();
    cg_strb   = new();
    cg_result = new();
    cg_err    = new();
    cg_xfer   = new();
    cg_local  = new();
    // 構成によって起こり得ない項目は生成しない
    if( STRB_W>1 ) begin
      cg_strb_part = new();
      cg_res_align = new();
    end
    if( NUM_SLAVES>1 ) begin
      cg_sel = new();
    end
    if( TIMEOUT_CYCLES>0 ) begin
      cg_res_timeout = new();
      cg_abort       = new();
    end
    if( HAS_BAD_SEL ) begin
      cg_res_sel = new();
    end
    if( HAS_BAD_MEM ) begin
      cg_local_oor = new();
    end
    // エラーで中止する構成では、1 コマンドでエラーになる転送は 1 つだけ
    if( !STOP_ON_ERROR&&(LMAX>=2) ) begin
      cg_multi_err = new();
    end
  endfunction

  // 受付時 : コマンドの形とスレーブの設定を記録
  //   (完了時にはスレーブの設定が次の値に変わっている可能性がある)
  function void write_cstart(usr_item c);
    bit [63:0] last;
    m_exec = !apbm_scoreboard::cmd_is_empty(c)&&!apbm_scoreboard::cmd_is_bad(c);
    m_wr   = c.wr;
    m_incr = c.incr;
    m_prot = c.prot;
    if( c.len<=1 ) begin
      m_len = L_ONE;
    end else if( c.len>=LMAX ) begin
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
    // 最後の転送がアドレス空間の最後のワードか
    last        = apbm_xaddr(c.addr, c.incr, (c.len>0) ? (c.len-1) : 0);
    m_top       = ((last+64'(STRB_W))==SPACE_BYTES);
    m_strb_all  = (c.strb=={STRB_W{1'b1}});
    m_strb_part = (c.strb!={STRB_W{1'b1}})&&(c.strb!={STRB_W{1'b0}});
    m_sel_last  = (c.sel==(NUM_SLAVES-1));
    m_sel_edge  = (c.sel==0)||(c.sel==(NUM_SLAVES-1));
    m_has_wait  = 1'b0;
    if( c.sel<NUM_SLAVES ) begin
      m_has_wait = (cfg[c.sel].wait_max>0);
    end
    m_n_xerr = 0;
  endfunction

  function void write_cdone(usr_item c);
    // 結果
    if( apbm_scoreboard::cmd_is_empty(c) ) begin
      m_result = RES_EMPTY;
    end else if( c.err_flags[2] ) begin
      if( apbm_sel_bad(c.sel) ) begin
        m_result = RES_BAD_SEL;
      end else if( apbm_mem_bad(c.maddr,c.len) ) begin
        m_result = RES_BAD_MEM;
      end else if( apbm_align_bad(c.addr) ) begin
        m_result = RES_BAD_ALIGN;
      end else begin
        m_result = RES_BAD_RANGE;
      end
    end else if( c.err_flags[1] ) begin
      m_result = RES_TIMEOUT;
    end else if( c.err_flags[0] ) begin
      m_result = RES_SLVERR;
    end else begin
      m_result = RES_OK;
    end
    cg_result.sample();
    if( cg_res_timeout!=null ) begin
      cg_res_timeout.sample();
    end
    if( cg_res_align!=null ) begin
      cg_res_align.sample();
    end
    if( cg_res_sel!=null ) begin
      cg_res_sel.sample();
    end
    // 形のカバレッジは、実際に転送したコマンドだけ数える
    if( m_exec ) begin
      cg_cmd.sample();
      if( c.wr ) begin
        if( (c.strb=={STRB_W{1'b1}})||(c.strb=={STRB_W{1'b0}}) ) begin
          cg_strb.sample();
        end
        if( (cg_strb_part!=null)&&m_strb_part ) begin
          cg_strb_part.sample();
        end
      end
      if( (cg_sel!=null)&&m_sel_edge ) begin
        cg_sel.sample();
      end
      // エラーになった転送の位置 (3 ワード以上のコマンドで見る)
      if( (c.err_flags[1:0]!=2'b00)&&(c.len>=3) ) begin
        if( c.err_index==0 ) begin
          m_epos = EP_FIRST;
        end else if( c.err_index==(c.len-1) ) begin
          m_epos = EP_LAST;
        end else begin
          m_epos = EP_MID;
        end
        cg_err.sample();
      end
      // エラーになった転送の数 (エラーでも最後まで続ける構成だけ)
      if( (cg_multi_err!=null)&&(m_n_xerr>0) ) begin
        m_multi_err = (m_n_xerr>=2);
        cg_multi_err.sample();
      end
    end
  endfunction

  function void write_capb(apb_item t);
    m_x_wr = t.write;
    if( t.aborted||t.slverr ) begin
      m_n_xerr++;
    end
    if( t.aborted ) begin
      if( cg_abort!=null ) begin
        cg_abort.sample();
      end
      return;
    end
    if( t.n_wait==0 ) begin
      m_x_wait = WT_ZERO;
    end else if( t.n_wait==1 ) begin
      m_x_wait = WT_ONE;
    end else begin
      m_x_wait = WT_MANY;
    end
    m_x_b2b = t.b2b;
    m_x_err = t.slverr;
    m_x_top = ((t.addr+64'(STRB_W))==SPACE_BYTES);
    cg_xfer.sample();
  endfunction

  function void write_cmem(mem_item t);
    m_l_wr       = t.write;
    m_l_consec   = t.consec;
    m_l_with_cmd = t.with_cmd;
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
    `uvm_info("COV", $sformatf("cg_cmd = %0.1f %%  cg_result = %0.1f %%  cg_err = %0.1f %%  cg_xfer = %0.1f %%  cg_local = %0.1f %%", cg_cmd.get_inst_coverage(), cg_result.get_inst_coverage(), cg_err.get_inst_coverage(), cg_xfer.get_inst_coverage(), cg_local.get_inst_coverage()), UVM_NONE)
  endfunction

endclass

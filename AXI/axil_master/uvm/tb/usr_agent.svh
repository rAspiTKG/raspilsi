//=============================================================================
// usr_agent.svh
//-----------------------------------------------------------------------------
//  ユーザ側 agent。書き込みコマンド / 読み出しコマンド / ローカルポートを、
//  それぞれ別の sequencer + driver で同時に動かせる。
//    cmd_driver  : コマンドを 1 本ずつ出す (m_wr で方向を選ぶ)。
//                  wait_done=1 なら done まで待ち、結果を item に入れる
//    loc_driver  : ローカルポートの書き込み / 読み出し (1 つの item に両方あれば同時に)
//    usr_monitor : コマンドの受付 / 完了 (方向ごとに別ポート) と、ローカルポートのアクセスを出す
//=============================================================================

typedef uvm_sequencer #(cmd_item) cmd_sequencer;
typedef uvm_sequencer #(loc_item) loc_sequencer;

//=============================================================================
// コマンドの driver
//=============================================================================
class cmd_driver extends uvm_driver #(cmd_item);

  `uvm_component_utils(cmd_driver)

  virtual usr_if vif;
  bit            m_wr;                 // 1 : 書き込みコマンド / 0 : 読み出しコマンド

  // 受付 / 完了待ちの上限 [cycle] (+CMD_TIMEOUT=<n> で変更)
  //   DUT がハングしたとき、テスト全体のタイムアウトを待たずに止めるためのウォッチドッグ
  int unsigned   m_timeout_cyc = 200000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(usr_vif_t)::get(this,"","usr_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (usr_vif) is not set")
    end
    void'($value$plusargs("CMD_TIMEOUT=%d",m_timeout_cyc));
  endfunction

  task run_phase(uvm_phase phase);
    if( m_wr ) begin
      @(vif.wdrv_cb);
      vif.wdrv_cb.wcmd_valid    <= 1'b0;
      vif.wdrv_cb.wcmd_addr     <= '0;
      vif.wdrv_cb.wcmd_incr     <= 1'b0;
      vif.wdrv_cb.wcmd_mem_addr <= '0;
      vif.wdrv_cb.wcmd_len      <= '0;
      vif.wdrv_cb.wcmd_strb     <= '0;
      vif.wdrv_cb.wcmd_prot     <= '0;
    end else begin
      @(vif.rdrv_cb);
      vif.rdrv_cb.rcmd_valid    <= 1'b0;
      vif.rdrv_cb.rcmd_addr     <= '0;
      vif.rdrv_cb.rcmd_incr     <= 1'b0;
      vif.rdrv_cb.rcmd_mem_addr <= '0;
      vif.rdrv_cb.rcmd_len      <= '0;
      vif.rdrv_cb.rcmd_prot     <= '0;
    end
    wait( vif.aresetn===1'b1 );
    forever begin
      seq_item_port.get_next_item(req);
      // get_next_item() はデルタを消費するので、駆動前にクロッキングイベントで同期する
      if( m_wr ) begin
        @(vif.wdrv_cb);
        repeat( req.idle ) begin
          @(vif.wdrv_cb);
        end
        drive_w();
      end else begin
        @(vif.rdrv_cb);
        repeat( req.idle ) begin
          @(vif.rdrv_cb);
        end
        drive_r();
      end
      seq_item_port.item_done();
    end
  endtask

  protected task drive_w();
    int unsigned n_cyc;
    vif.wdrv_cb.wcmd_addr     <= ADDR_W'(req.addr);
    vif.wdrv_cb.wcmd_incr     <= req.incr;
    vif.wdrv_cb.wcmd_mem_addr <= MEM_AW'(req.maddr);
    vif.wdrv_cb.wcmd_len      <= LEN_W'(req.len);
    vif.wdrv_cb.wcmd_strb     <= req.strb;
    vif.wdrv_cb.wcmd_prot     <= req.prot;
    vif.wdrv_cb.wcmd_valid    <= 1'b1;
    n_cyc = 0;
    do begin
      @(vif.wdrv_cb);
      n_cyc++;
      if( n_cyc>m_timeout_cyc ) begin
        `uvm_fatal("USR_TIMEOUT", $sformatf("wcmd_ready did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
      end
    end while( !((vif.wdrv_cb.wcmd_valid===1'b1)&&(vif.wdrv_cb.wcmd_ready===1'b1)) );
    vif.wdrv_cb.wcmd_valid <= 1'b0;
    if( req.wait_done ) begin
      n_cyc = 0;
      do begin
        @(vif.wdrv_cb);
        n_cyc++;
        if( n_cyc>m_timeout_cyc ) begin
          `uvm_fatal("USR_TIMEOUT", $sformatf("wr_done did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
        end
      end while( vif.wdrv_cb.wr_done!==1'b1 );
      req.done_err   = vif.wdrv_cb.wr_done_err;
      req.err_flags  = vif.wdrv_cb.wr_err_flags;
      req.err_index  = 32'(vif.wdrv_cb.wr_err_index);
      req.done_count = 32'(vif.wdrv_cb.wr_done_count);
      // monitor / scoreboard が完了を処理してからシーケンスへ戻す
      @(vif.wdrv_cb);
    end
  endtask

  protected task drive_r();
    int unsigned n_cyc;
    vif.rdrv_cb.rcmd_addr     <= ADDR_W'(req.addr);
    vif.rdrv_cb.rcmd_incr     <= req.incr;
    vif.rdrv_cb.rcmd_mem_addr <= MEM_AW'(req.maddr);
    vif.rdrv_cb.rcmd_len      <= LEN_W'(req.len);
    vif.rdrv_cb.rcmd_prot     <= req.prot;
    vif.rdrv_cb.rcmd_valid    <= 1'b1;
    n_cyc = 0;
    do begin
      @(vif.rdrv_cb);
      n_cyc++;
      if( n_cyc>m_timeout_cyc ) begin
        `uvm_fatal("USR_TIMEOUT", $sformatf("rcmd_ready did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
      end
    end while( !((vif.rdrv_cb.rcmd_valid===1'b1)&&(vif.rdrv_cb.rcmd_ready===1'b1)) );
    vif.rdrv_cb.rcmd_valid <= 1'b0;
    if( req.wait_done ) begin
      n_cyc = 0;
      do begin
        @(vif.rdrv_cb);
        n_cyc++;
        if( n_cyc>m_timeout_cyc ) begin
          `uvm_fatal("USR_TIMEOUT", $sformatf("rd_done did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
        end
      end while( vif.rdrv_cb.rd_done!==1'b1 );
      req.done_err   = vif.rdrv_cb.rd_done_err;
      req.err_flags  = vif.rdrv_cb.rd_err_flags;
      req.err_index  = 32'(vif.rdrv_cb.rd_err_index);
      req.done_count = 32'(vif.rdrv_cb.rd_done_count);
      @(vif.rdrv_cb);
    end
  endtask

endclass

//=============================================================================
// ローカルポートの driver
//=============================================================================
class loc_driver extends uvm_driver #(loc_item);

  `uvm_component_utils(loc_driver)

  virtual usr_if vif;
  int unsigned   m_timeout_cyc = 200000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(usr_vif_t)::get(this,"","usr_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (usr_vif) is not set")
    end
    void'($value$plusargs("CMD_TIMEOUT=%d",m_timeout_cyc));
  endfunction

  task run_phase(uvm_phase phase);
    @(vif.ldrv_cb);
    vif.ldrv_cb.mem_w_valid <= 1'b0;
    vif.ldrv_cb.mem_w_addr  <= '0;
    vif.ldrv_cb.mem_w_data  <= '0;
    vif.ldrv_cb.mem_r_valid <= 1'b0;
    vif.ldrv_cb.mem_r_addr  <= '0;
    wait( vif.aresetn===1'b1 );
    forever begin
      seq_item_port.get_next_item(req);
      @(vif.ldrv_cb);
      repeat( req.idle ) begin
        @(vif.ldrv_cb);
      end
      req.rd_data.delete();
      fork
        begin
          if( req.wr_data.size()!=0 ) begin
            do_wr();
          end
        end
        begin
          if( req.rd_n!=0 ) begin
            do_rd();
          end
        end
      join
      seq_item_port.item_done();
    end
  endtask

  // 書き込み : アクセスの間に gap_pct の確率で空きサイクルを入れる。入れなければ valid を上げたまま続ける
  protected task do_wr();
    int unsigned i;
    int unsigned n_cyc;
    bit          drive_now;
    i     = 0;
    n_cyc = 0;
    while( i<req.wr_data.size() ) begin
      drive_now = !($urandom_range(99,0)<req.gap_pct);
      if( drive_now ) begin
        vif.ldrv_cb.mem_w_valid <= 1'b1;
        vif.ldrv_cb.mem_w_addr  <= MEM_AW'(req.wr_maddr+i);
        vif.ldrv_cb.mem_w_data  <= req.wr_data[i];
      end else begin
        vif.ldrv_cb.mem_w_valid <= 1'b0;
      end
      // 握手するまで同じ内容を出し続ける
      do begin
        @(vif.ldrv_cb);
        n_cyc++;
        if( n_cyc>m_timeout_cyc ) begin
          `uvm_fatal("USR_TIMEOUT", $sformatf("mem_w_ready did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
        end
      end while( drive_now&&!((vif.ldrv_cb.mem_w_valid===1'b1)&&(vif.ldrv_cb.mem_w_ready===1'b1)) );
      if( drive_now ) begin
        i++;
      end
    end
    vif.ldrv_cb.mem_w_valid <= 1'b0;
  endtask

  // 読み出し : データは受け付けた次のサイクル
  protected task do_rd();
    int unsigned i;
    int unsigned n_cyc;
    bit          pend;
    bit          drive_now;
    i     = 0;
    n_cyc = 0;
    pend  = 1'b0;
    while( (i<req.rd_n)||pend ) begin
      drive_now = (i<req.rd_n)&&!($urandom_range(99,0)<req.gap_pct);
      if( drive_now ) begin
        vif.ldrv_cb.mem_r_valid <= 1'b1;
        vif.ldrv_cb.mem_r_addr  <= MEM_AW'(req.rd_maddr+i);
      end else begin
        vif.ldrv_cb.mem_r_valid <= 1'b0;
      end
      do begin
        @(vif.ldrv_cb);
        n_cyc++;
        if( n_cyc>m_timeout_cyc ) begin
          `uvm_fatal("USR_TIMEOUT", $sformatf("mem_r_ready did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
        end
        if( pend ) begin
          // 直前のサイクルに受け付けられた読み出しのデータ
          req.rd_data.push_back(vif.ldrv_cb.mem_r_rdata);
          pend = 1'b0;
        end
      end while( drive_now&&!((vif.ldrv_cb.mem_r_valid===1'b1)&&(vif.ldrv_cb.mem_r_ready===1'b1)) );
      if( drive_now ) begin
        i++;
        pend = 1'b1;
      end
    end
    vif.ldrv_cb.mem_r_valid <= 1'b0;
  endtask

endclass

//=============================================================================
// Monitor
//=============================================================================
class usr_monitor extends uvm_monitor;

  `uvm_component_utils(usr_monitor)

  virtual usr_if                vif;
  uvm_analysis_port #(cmd_item) ap_wstart;   // 書き込みコマンドの受付
  uvm_analysis_port #(cmd_item) ap_wdone;    // 書き込みコマンドの完了 (結果付き)
  uvm_analysis_port #(cmd_item) ap_rstart;
  uvm_analysis_port #(cmd_item) ap_rdone;
  uvm_analysis_port #(mem_item) ap_mem;      // ローカルポートのアクセス (読み出しはデータが出たとき)

  protected cmd_item     m_wcur;       // 実行中のコマンド
  protected cmd_item     m_rcur;
  protected mem_item     m_rd;         // データ待ちのローカル読み出し
  protected bit          m_lw_last;    // 直前のサイクルにローカル書き込みがあった
  protected bit          m_lr_last;
  protected bit          m_lw_wait;    // 直前のサイクルにローカル書き込みが待たされていた
  protected bit          m_lr_wait;
  protected bit          m_wc_wait;    // 直前のサイクルに書き込みコマンドが待たされていた
  protected bit          m_rc_wait;
  protected int unsigned m_cyc;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_wstart = new("ap_wstart", this);
    ap_wdone  = new("ap_wdone", this);
    ap_rstart = new("ap_rstart", this);
    ap_rdone  = new("ap_rdone", this);
    ap_mem    = new("ap_mem", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(usr_vif_t)::get(this,"","usr_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (usr_vif) is not set")
    end
  endfunction

  task run_phase(uvm_phase phase);
    wait( vif.aresetn===1'b1 );
    forever begin
      @(vif.mon_cb);
      m_cyc++;
      // 同じサイクルのローカル書き込みを先に出す (同じサイクルに受け付けた書き込みコマンドは、書いた後の値を送る)
      sample_mem();
      sample_cmd();
    end
  endtask

  protected function void sample_mem();
    mem_item t;
    bit      w_fire;
    bit      r_fire;
    bit      wc_fire;
    bit      rc_fire;
    // 直前のサイクルに受け付けられた読み出しのデータ
    if( m_rd!=null ) begin
      m_rd.rvalid = (vif.mon_cb.mem_r_rvalid===1'b1);
      m_rd.data   = vif.mon_cb.mem_r_rdata;
      `uvm_info("USR_MON", m_rd.convert2string(), UVM_HIGH)
      ap_mem.write(m_rd);
      m_rd = null;
    end
    w_fire  = (vif.mon_cb.mem_w_valid===1'b1)&&(vif.mon_cb.mem_w_ready===1'b1);
    r_fire  = (vif.mon_cb.mem_r_valid===1'b1)&&(vif.mon_cb.mem_r_ready===1'b1);
    wc_fire = (vif.mon_cb.wcmd_valid===1'b1)&&(vif.mon_cb.wcmd_ready===1'b1);
    rc_fire = (vif.mon_cb.rcmd_valid===1'b1)&&(vif.mon_cb.rcmd_ready===1'b1);
    if( w_fire ) begin
      t             = mem_item::type_id::create("mem_w");
      t.write       = 1'b1;
      t.addr        = 32'(vif.mon_cb.mem_w_addr);
      t.data        = vif.mon_cb.mem_w_data;
      t.with_wcmd   = wc_fire;
      t.with_rcmd   = rc_fire;
      t.during_wcmd = (m_wcur!=null);
      t.during_rcmd = (m_rcur!=null);
      t.consec      = m_lw_last;
      t.waited      = m_lw_wait;
      `uvm_info("USR_MON", t.convert2string(), UVM_HIGH)
      ap_mem.write(t);
    end
    if( r_fire ) begin
      t             = mem_item::type_id::create("mem_r");
      t.write       = 1'b0;
      t.addr        = 32'(vif.mon_cb.mem_r_addr);
      t.with_wcmd   = wc_fire;
      t.with_rcmd   = rc_fire;
      t.during_wcmd = (m_wcur!=null);
      t.during_rcmd = (m_rcur!=null);
      t.consec      = m_lr_last;
      t.waited      = m_lr_wait;
      m_rd          = t;
    end
    m_lw_last = w_fire;
    m_lr_last = r_fire;
    m_lw_wait = (vif.mon_cb.mem_w_valid===1'b1)&&(vif.mon_cb.mem_w_ready!==1'b1);
    m_lr_wait = (vif.mon_cb.mem_r_valid===1'b1)&&(vif.mon_cb.mem_r_ready!==1'b1);
  endfunction

  protected function void sample_cmd();
    bit wc_fire;
    bit rc_fire;
    wc_fire = (vif.mon_cb.wcmd_valid===1'b1)&&(vif.mon_cb.wcmd_ready===1'b1);
    rc_fire = (vif.mon_cb.rcmd_valid===1'b1)&&(vif.mon_cb.rcmd_ready===1'b1);
    //-------------------------------------------------------------------------
    // 書き込み
    //-------------------------------------------------------------------------
    if( wc_fire ) begin
      if( m_wcur!=null ) begin
        `uvm_error("USR_MON", "write command accepted while the previous one is not done")
      end
      m_wcur             = cmd_item::type_id::create("wcmd");
      m_wcur.wr          = 1'b1;
      m_wcur.addr        = 64'(vif.mon_cb.wcmd_addr);
      m_wcur.incr        = vif.mon_cb.wcmd_incr;
      m_wcur.maddr       = 32'(vif.mon_cb.wcmd_mem_addr);
      m_wcur.len         = 32'(vif.mon_cb.wcmd_len);
      m_wcur.strb        = vif.mon_cb.wcmd_strb;
      m_wcur.prot        = vif.mon_cb.wcmd_prot;
      m_wcur.cyc_start   = m_cyc;
      m_wcur.held        = m_wc_wait;
      m_wcur.other_busy  = (vif.mon_cb.rd_busy===1'b1);
      m_wcur.other_start = rc_fire;
      `uvm_info("USR_MON", {"start ", m_wcur.convert2string()}, UVM_HIGH)
      ap_wstart.write(m_wcur);
    end else if( vif.mon_cb.wr_done===1'b1 ) begin
      if( m_wcur==null ) begin
        `uvm_error("USR_MON", "wr_done without an accepted write command")
      end else begin
        m_wcur.done_err   = vif.mon_cb.wr_done_err;
        m_wcur.err_flags  = vif.mon_cb.wr_err_flags;
        m_wcur.err_index  = 32'(vif.mon_cb.wr_err_index);
        m_wcur.done_count = 32'(vif.mon_cb.wr_done_count);
        m_wcur.cyc_done   = m_cyc;
        `uvm_info("USR_MON", $sformatf("done %s err_flags=%b err_index=%0d done_count=%0d", m_wcur.convert2string(), m_wcur.err_flags, m_wcur.err_index, m_wcur.done_count), UVM_HIGH)
        ap_wdone.write(m_wcur);
        m_wcur = null;
      end
    end
    m_wc_wait = (vif.mon_cb.wcmd_valid===1'b1)&&(vif.mon_cb.wcmd_ready!==1'b1);
    //-------------------------------------------------------------------------
    // 読み出し
    //-------------------------------------------------------------------------
    if( rc_fire ) begin
      if( m_rcur!=null ) begin
        `uvm_error("USR_MON", "read command accepted while the previous one is not done")
      end
      m_rcur             = cmd_item::type_id::create("rcmd");
      m_rcur.wr          = 1'b0;
      m_rcur.addr        = 64'(vif.mon_cb.rcmd_addr);
      m_rcur.incr        = vif.mon_cb.rcmd_incr;
      m_rcur.maddr       = 32'(vif.mon_cb.rcmd_mem_addr);
      m_rcur.len         = 32'(vif.mon_cb.rcmd_len);
      m_rcur.strb        = '0;
      m_rcur.prot        = vif.mon_cb.rcmd_prot;
      m_rcur.cyc_start   = m_cyc;
      m_rcur.held        = m_rc_wait;
      m_rcur.other_busy  = (vif.mon_cb.wr_busy===1'b1);
      m_rcur.other_start = wc_fire;
      `uvm_info("USR_MON", {"start ", m_rcur.convert2string()}, UVM_HIGH)
      ap_rstart.write(m_rcur);
    end else if( vif.mon_cb.rd_done===1'b1 ) begin
      if( m_rcur==null ) begin
        `uvm_error("USR_MON", "rd_done without an accepted read command")
      end else begin
        m_rcur.done_err   = vif.mon_cb.rd_done_err;
        m_rcur.err_flags  = vif.mon_cb.rd_err_flags;
        m_rcur.err_index  = 32'(vif.mon_cb.rd_err_index);
        m_rcur.done_count = 32'(vif.mon_cb.rd_done_count);
        m_rcur.cyc_done   = m_cyc;
        `uvm_info("USR_MON", $sformatf("done %s err_flags=%b err_index=%0d done_count=%0d", m_rcur.convert2string(), m_rcur.err_flags, m_rcur.err_index, m_rcur.done_count), UVM_HIGH)
        ap_rdone.write(m_rcur);
        m_rcur = null;
      end
    end
    m_rc_wait = (vif.mon_cb.rcmd_valid===1'b1)&&(vif.mon_cb.rcmd_ready!==1'b1);
  endfunction

endclass

//=============================================================================
// Agent
//=============================================================================
class usr_agent extends uvm_agent;

  `uvm_component_utils(usr_agent)

  cmd_sequencer wsqr;
  cmd_sequencer rsqr;
  loc_sequencer lsqr;
  cmd_driver    wdrv;
  cmd_driver    rdrv;
  loc_driver    ldrv;
  usr_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = usr_monitor::type_id::create("mon", this);
    if( get_is_active()==UVM_ACTIVE ) begin
      wsqr = cmd_sequencer::type_id::create("wsqr", this);
      rsqr = cmd_sequencer::type_id::create("rsqr", this);
      lsqr = loc_sequencer::type_id::create("lsqr", this);
      wdrv = cmd_driver::type_id::create("wdrv", this);
      rdrv = cmd_driver::type_id::create("rdrv", this);
      ldrv = loc_driver::type_id::create("ldrv", this);
      wdrv.m_wr = 1'b1;
      rdrv.m_wr = 1'b0;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if( get_is_active()==UVM_ACTIVE ) begin
      wdrv.seq_item_port.connect(wsqr.seq_item_export);
      rdrv.seq_item_port.connect(rsqr.seq_item_export);
      ldrv.seq_item_port.connect(lsqr.seq_item_export);
    end
  endfunction

endclass

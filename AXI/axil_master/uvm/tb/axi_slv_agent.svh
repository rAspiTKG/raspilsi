//=============================================================================
// axi_slv_agent.svh
//-----------------------------------------------------------------------------
//  AXI スレーブ agent (DUT の AXI マスタに応答する側)。
//    axi_responder : AWREADY / WREADY / ARREADY を cfg の確率で出し、AW と W が揃ったら
//                    メモリに書いて B を、AR を受けたらメモリを読んで R を、cfg の遅延で返す。
//                    応答は受けた順 (AXI4-Lite には ID が無い)。エラー範囲には cfg の応答を返す
//                    (エラーの書き込みはメモリに反映しない)
//    axi_monitor   : トランザクションを観測し、B / R を受けたときに axi_item を出す
//
//  駆動は全て clocking block 経由で、@(vif.slv_cb) の直後 (間にブロッキング呼び出し
//  を挟まない) に行う。出力は「次のサイクルの値」を毎サイクル全ビット書く。
//=============================================================================

//=============================================================================
// Responder
//=============================================================================
class axi_responder extends uvm_component;

  `uvm_component_utils(axi_responder)

  typedef struct packed {
    bit [63:0] addr;
    bit [2:0]  prot;
  } a_t;

  typedef struct packed {
    bit [DATA_W-1:0] data;
    bit [STRB_W-1:0] strb;
  } w_t;

  typedef struct packed {
    bit [1:0]        resp;
    bit [DATA_W-1:0] data;
    bit [63:0]       t;          // このサイクル以降に VALID を出してよい
  } rsp_t;

  virtual axi_if vif;
  axi_slv_mem    mem;
  axi_slv_cfg    cfg;

  protected a_t              m_aw_q[$];
  protected w_t              m_w_q[$];
  protected rsp_t            m_b_q[$];
  protected rsp_t            m_r_q[$];
  protected bit [63:0]       m_cyc;
  protected bit [63:0]       m_b_last;
  protected bit [63:0]       m_r_last;
  // 今のサイクルに出している値
  protected bit              m_awready;
  protected bit              m_wready;
  protected bit              m_arready;
  protected bit              m_bvalid;
  protected bit [1:0]        m_bresp;
  protected bit              m_rvalid;
  protected bit [1:0]        m_rresp;
  protected bit [DATA_W-1:0] m_rdata;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(axi_vif_t)::get(this,"","axi_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (axi_vif) is not set")
    end
  endfunction

  protected function bit [DATA_W-1:0] rand_data();
    bit [DATA_W-1:0] d;
    for( int unsigned b=0; b<DATA_W; b++ ) begin
      d[b] = 1'($urandom());
    end
    return d;
  endfunction

  protected function void clear_state();
    m_aw_q.delete();
    m_w_q.delete();
    m_b_q.delete();
    m_r_q.delete();
    m_cyc     = '0;
    m_b_last  = '0;
    m_r_last  = '0;
    m_awready = 1'b0;
    m_wready  = 1'b0;
    m_arready = 1'b0;
    m_bvalid  = 1'b0;
    m_bresp   = 2'b00;
    m_rvalid  = 1'b0;
    m_rresp   = 2'b00;
    m_rdata   = '0;
  endfunction

  task run_phase(uvm_phase phase);
    clear_state();
    drive();
    forever begin
      @(vif.slv_cb);
      if( vif.aresetn!==1'b1 ) begin
        clear_state();
      end else begin
        step();
      end
      drive();
    end
  endtask

  // 1 サイクル分 : 終わったサイクルの握手を処理し、次のサイクルの出力を決める
  protected function void step();
    bit          aw_hs;
    bit          w_hs;
    bit          ar_hs;
    bit          b_hs;
    bit          r_hs;
    bit          wv;
    bit          av;
    a_t          a;
    w_t          w;
    rsp_t        e;
    int unsigned lat;
    m_cyc = m_cyc + 64'd1;
    wv    = (vif.slv_cb.wvalid===1'b1);
    av    = (vif.slv_cb.awvalid===1'b1);
    aw_hs = m_awready&&av;
    w_hs  = m_wready&&wv;
    ar_hs = m_arready&&(vif.slv_cb.arvalid===1'b1);
    b_hs  = m_bvalid&&(vif.slv_cb.bready===1'b1);
    r_hs  = m_rvalid&&(vif.slv_cb.rready===1'b1);
    // 受け取り
    if( aw_hs ) begin
      a.addr = 64'(vif.slv_cb.awaddr);
      a.prot = vif.slv_cb.awprot;
      m_aw_q.push_back(a);
    end
    if( w_hs ) begin
      w.data = vif.slv_cb.wdata;
      w.strb = vif.slv_cb.wstrb;
      m_w_q.push_back(w);
    end
    if( ar_hs ) begin
      a.addr = 64'(vif.slv_cb.araddr);
      e.resp = cfg.rresp(a.addr);
      if( e.resp==2'b00 ) begin
        e.data = mem.read_word(a.addr);
      end else begin
        e.data = rand_data();
      end
      lat = $urandom_range(cfg.r_lat_max, cfg.r_lat_min);
      e.t = m_cyc + 64'(lat);
      if( e.t<m_r_last ) begin
        e.t = m_r_last;
      end
      m_r_last = e.t;
      m_r_q.push_back(e);
    end
    // AW と W が揃ったら書き込みを実行し、応答を予約する
    while( (m_aw_q.size()!=0)&&(m_w_q.size()!=0) ) begin
      a      = m_aw_q.pop_front();
      w      = m_w_q.pop_front();
      e.resp = cfg.wresp(a.addr);
      e.data = '0;
      if( e.resp==2'b00 ) begin
        mem.write_word(a.addr, w.data, w.strb);
      end
      lat = $urandom_range(cfg.b_lat_max, cfg.b_lat_min);
      e.t = m_cyc + 64'(lat);
      if( e.t<m_b_last ) begin
        e.t = m_b_last;
      end
      m_b_last = e.t;
      m_b_q.push_back(e);
    end
    // 応答
    if( b_hs ) begin
      void'(m_b_q.pop_front());
    end
    if( r_hs ) begin
      void'(m_r_q.pop_front());
    end
    if( !m_bvalid||b_hs ) begin
      if( (m_b_q.size()!=0)&&(m_b_q[0].t<=m_cyc) ) begin
        m_bvalid = 1'b1;
        m_bresp  = m_b_q[0].resp;
      end else begin
        m_bvalid = 1'b0;
        m_bresp  = cfg.noise ? 2'($urandom()) : 2'b00;
      end
    end
    if( !m_rvalid||r_hs ) begin
      if( (m_r_q.size()!=0)&&(m_r_q[0].t<=m_cyc) ) begin
        m_rvalid = 1'b1;
        m_rresp  = m_r_q[0].resp;
        m_rdata  = m_r_q[0].data;
      end else begin
        m_rvalid = 1'b0;
        m_rresp  = cfg.noise ? 2'($urandom()) : 2'b00;
        m_rdata  = cfg.noise ? rand_data() : {DATA_W{1'b0}};
      end
    end
    // 次のサイクルの READY
    m_awready = ($urandom_range(99,0)<cfg.aw_ready_pct)&&!(cfg.aw_wait_w&&(m_w_q.size()==0)&&!wv);
    m_wready  = ($urandom_range(99,0)<cfg.w_ready_pct)&&!(cfg.w_wait_aw&&(m_aw_q.size()==0)&&!av);
    m_arready = ($urandom_range(99,0)<cfg.ar_ready_pct);
  endfunction

  protected task drive();
    vif.slv_cb.awready <= m_awready;
    vif.slv_cb.wready  <= m_wready;
    vif.slv_cb.arready <= m_arready;
    vif.slv_cb.bvalid  <= m_bvalid;
    vif.slv_cb.bresp   <= m_bresp;
    vif.slv_cb.rvalid  <= m_rvalid;
    vif.slv_cb.rresp   <= m_rresp;
    vif.slv_cb.rdata   <= m_rdata;
    // axil_to_axi4 が見ない信号 (ID は 1 つ、ビートは 1 つ)
    if( cfg.noise ) begin
      vif.slv_cb.bid   <= ID_W'($urandom());
      vif.slv_cb.rid   <= ID_W'($urandom());
      vif.slv_cb.rlast <= 1'($urandom());
    end else begin
      vif.slv_cb.bid   <= {ID_W{1'b0}};
      vif.slv_cb.rid   <= {ID_W{1'b0}};
      vif.slv_cb.rlast <= 1'b1;
    end
  endtask

endclass

//=============================================================================
// Monitor
//=============================================================================
class axi_monitor extends uvm_monitor;

  `uvm_component_utils(axi_monitor)

  virtual axi_if                vif;
  uvm_analysis_port #(axi_item) ap;

  protected axi_item         m_aw_q[$];      // AW を受け、W 待ち
  protected bit [DATA_W-1:0] m_wd_q[$];      // W を受け、AW 待ち
  protected bit [STRB_W-1:0] m_ws_q[$];
  protected int unsigned     m_wc_q[$];
  protected axi_item         m_b_q[$];       // AW と W が揃い、B 待ち
  protected axi_item         m_r_q[$];       // AR を受け、R 待ち
  protected int unsigned     m_wr_out;       // AW を受けて B を返していない数
  protected int unsigned     m_rd_out;
  protected int unsigned     m_cyc;

  // 統計 (coverage / レポート用)
  int unsigned n_aw_first;
  int unsigned n_w_first;
  int unsigned n_aw_w_same;
  int unsigned max_wr_out;
  int unsigned max_rd_out;
  int unsigned n_both_cyc;                   // 書き込みと読み出しが両方とも未完了だったサイクル数

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(axi_vif_t)::get(this,"","axi_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (axi_vif) is not set")
    end
  endfunction

  task run_phase(uvm_phase phase);
    wait( vif.aresetn===1'b1 );
    forever begin
      @(vif.mon_cb);
      m_cyc++;
      sample();
    end
  endtask

  protected function void sample();
    bit      aw_hs;
    bit      w_hs;
    bit      b_hs;
    bit      ar_hs;
    bit      r_hs;
    axi_item t;
    aw_hs = (vif.mon_cb.awvalid===1'b1)&&(vif.mon_cb.awready===1'b1);
    w_hs  = (vif.mon_cb.wvalid===1'b1)&&(vif.mon_cb.wready===1'b1);
    b_hs  = (vif.mon_cb.bvalid===1'b1)&&(vif.mon_cb.bready===1'b1);
    ar_hs = (vif.mon_cb.arvalid===1'b1)&&(vif.mon_cb.arready===1'b1);
    r_hs  = (vif.mon_cb.rvalid===1'b1)&&(vif.mon_cb.rready===1'b1);
    //-------------------------------------------------------------------------
    // 書き込み
    //-------------------------------------------------------------------------
    if( aw_hs ) begin
      t           = axi_item::type_id::create("axi_wr");
      t.write     = 1'b1;
      t.addr      = 64'(vif.mon_cb.awaddr);
      t.prot      = vif.mon_cb.awprot;
      t.a_cyc     = m_cyc;
      t.depth     = m_wr_out + 1;
      t.other_out = (m_rd_out!=0);
      if( m_wd_q.size()!=0 ) begin
        n_w_first++;
      end else if( w_hs ) begin
        n_aw_w_same++;
      end else begin
        n_aw_first++;
      end
      m_aw_q.push_back(t);
    end
    if( w_hs ) begin
      m_wd_q.push_back(vif.mon_cb.wdata);
      m_ws_q.push_back(vif.mon_cb.wstrb);
      m_wc_q.push_back(m_cyc);
    end
    while( (m_aw_q.size()!=0)&&(m_wd_q.size()!=0) ) begin
      t       = m_aw_q.pop_front();
      t.data  = m_wd_q.pop_front();
      t.strb  = m_ws_q.pop_front();
      t.w_cyc = m_wc_q.pop_front();
      m_b_q.push_back(t);
    end
    if( b_hs ) begin
      if( m_b_q.size()==0 ) begin
        `uvm_error("AXI_MON", "B handshake without a complete write (AW and W)")
      end else begin
        t          = m_b_q.pop_front();
        t.resp     = vif.mon_cb.bresp;
        t.resp_cyc = m_cyc;
        `uvm_info("AXI_MON", t.convert2string(), UVM_HIGH)
        ap.write(t);
      end
    end
    //-------------------------------------------------------------------------
    // 読み出し
    //-------------------------------------------------------------------------
    if( ar_hs ) begin
      t           = axi_item::type_id::create("axi_rd");
      t.write     = 1'b0;
      t.addr      = 64'(vif.mon_cb.araddr);
      t.prot      = vif.mon_cb.arprot;
      t.strb      = '0;
      t.a_cyc     = m_cyc;
      t.depth     = m_rd_out + 1;
      t.other_out = (m_wr_out!=0);
      m_r_q.push_back(t);
    end
    if( r_hs ) begin
      if( m_r_q.size()==0 ) begin
        `uvm_error("AXI_MON", "R handshake without AR")
      end else begin
        t          = m_r_q.pop_front();
        t.data     = vif.mon_cb.rdata;
        t.resp     = vif.mon_cb.rresp;
        t.resp_cyc = m_cyc;
        `uvm_info("AXI_MON", t.convert2string(), UVM_HIGH)
        ap.write(t);
      end
    end
    //-------------------------------------------------------------------------
    // 未完了数
    //-------------------------------------------------------------------------
    if( (m_wr_out!=0)&&(m_rd_out!=0) ) begin
      n_both_cyc++;
    end
    m_wr_out = m_wr_out + 32'(aw_hs) - 32'(b_hs);
    m_rd_out = m_rd_out + 32'(ar_hs) - 32'(r_hs);
    if( m_wr_out>max_wr_out ) begin
      max_wr_out = m_wr_out;
    end
    if( m_rd_out>max_rd_out ) begin
      max_rd_out = m_rd_out;
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("AXI_MON", $sformatf("AW before W %0d / W before AW %0d / same cycle %0d, max outstanding %0d / %0d, both directions outstanding %0d cycles", n_aw_first, n_w_first, n_aw_w_same, max_wr_out, max_rd_out, n_both_cyc), UVM_NONE)
  endfunction

endclass

//=============================================================================
// Agent
//=============================================================================
class axi_slv_agent extends uvm_agent;

  `uvm_component_utils(axi_slv_agent)

  axi_responder rsp;
  axi_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axi_monitor::type_id::create("mon", this);
    if( get_is_active()==UVM_ACTIVE ) begin
      rsp = axi_responder::type_id::create("rsp", this);
    end
  endfunction

endclass

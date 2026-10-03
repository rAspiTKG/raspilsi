//=============================================================================
// axi_rd_slv_agent.svh
//-----------------------------------------------------------------------------
//  入力側 AXI4 スレーブ agent (DUT の AR / R に応答する側)。
//    axi_rd_responder : AR を受けてメモリから R を返す。
//                       cfg に従ってストール・READY の出し方・SLVERR を変える
//    axi_rd_monitor   : AR / R を観測し、完了した Read バーストを出す
//
//  駆動は全て clocking block 経由で、@(vif.slv_cb) の直後 (間にブロッキング呼び出し
//  を挟まない) に行う。握手は VALID と READY の両方のサンプル値で判定する。
//=============================================================================

//=============================================================================
// Responder
//=============================================================================
class axi_rd_responder extends uvm_component;

  `uvm_component_utils(axi_rd_responder)

  virtual axi_rd_if vif;
  axi_mem           mem;
  axi_slv_cfg       cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(axi_rd_vif_t)::get(this,"","axi_rd_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (axi_rd_vif) is not set")
    end
  endfunction

  //---------------------------------------------------------------------------
  // Read : AR -> R (全ビート)
  //---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    bit [IN_ID_W-1:0] id;
    bit [63:0]        addr;
    bit [7:0]         len;
    bit [2:0]         size;
    bit [1:0]         burst;
    bit [63:0]        a;
    int unsigned      dly;
    bit               hs;
    @(vif.slv_cb);
    vif.slv_cb.arready <= 1'b0;
    vif.slv_cb.rvalid  <= 1'b0;
    vif.slv_cb.rid     <= '0;
    vif.slv_cb.rdata   <= '0;
    vif.slv_cb.rresp   <= AXI_OKAY;
    vif.slv_cb.rlast   <= 1'b0;
    wait( vif.aresetn===1'b1 );
    forever begin
      // --- AR ---
      hs = 1'b0;
      while( !hs ) begin
        @(vif.slv_cb);
        if( (vif.slv_cb.arvalid===1'b1)&&(vif.slv_cb.arready===1'b1) ) begin
          hs    = 1'b1;
          id    = vif.slv_cb.arid;
          addr  = 64'(vif.slv_cb.araddr);
          len   = vif.slv_cb.arlen;
          size  = vif.slv_cb.arsize;
          burst = vif.slv_cb.arburst;
          vif.slv_cb.arready <= 1'b0;
        end else begin
          vif.slv_cb.arready <= cfg.ready_next(vif.slv_cb.arvalid, 1'b0);
        end
      end
      // --- R --- (ビートごとにランダムな待ちを入れる。出したら握手まで保持)
      for( int unsigned beat=0; beat<=32'(len); beat++ ) begin
        dly = cfg.delay();
        if( dly>0 ) begin
          vif.slv_cb.rvalid <= 1'b0;
          repeat( dly ) begin
            @(vif.slv_cb);
          end
        end
        a = axi_beat_addr(addr, len, size, axi_burst_e'(burst), beat);
        vif.slv_cb.rvalid <= 1'b1;
        vif.slv_cb.rid    <= id;
        vif.slv_cb.rdata  <= IN_DATA_W'(mem.read_word(a, IN_STRB_W));
        vif.slv_cb.rresp  <= cfg.in_err(a) ? AXI_SLVERR : AXI_OKAY;
        vif.slv_cb.rlast  <= (beat==32'(len));
        do begin
          @(vif.slv_cb);
        end while( !((vif.slv_cb.rvalid===1'b1)&&(vif.slv_cb.rready===1'b1)) );
      end
      vif.slv_cb.rvalid <= 1'b0;
      vif.slv_cb.rlast  <= 1'b0;
    end
  endtask

endclass

//=============================================================================
// Read monitor
//=============================================================================
class axi_rd_monitor extends uvm_monitor;

  `uvm_component_utils(axi_rd_monitor)

  virtual axi_rd_if                   vif;
  uvm_analysis_port #(axi_burst_item) ap;

  // AR 受領済みで R 受信中のトランザクションと、その受信済みビート数
  protected axi_burst_item m_ar_q[$];
  protected int unsigned   m_beat_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(axi_rd_vif_t)::get(this,"","axi_rd_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (axi_rd_vif) is not set")
    end
  endfunction

  task run_phase(uvm_phase phase);
    wait( vif.aresetn===1'b1 );
    forever begin
      @(vif.mon_cb);
      sample_ar();
      sample_r();
    end
  endtask

  function void sample_ar();
    axi_burst_item t;
    if( (vif.mon_cb.arvalid===1'b1)&&(vif.mon_cb.arready===1'b1) ) begin
      t        = axi_burst_item::type_id::create("rd_tr");
      t.dir    = AXI_READ;
      t.id     = 32'(vif.mon_cb.arid);
      t.addr   = 64'(vif.mon_cb.araddr);
      t.len    = vif.mon_cb.arlen;
      t.size   = vif.mon_cb.arsize;
      t.burst  = axi_burst_e'(vif.mon_cb.arburst);
      t.lock   = vif.mon_cb.arlock;
      t.cache  = vif.mon_cb.arcache;
      t.prot   = vif.mon_cb.arprot;
      t.qos    = vif.mon_cb.arqos;
      t.region = vif.mon_cb.arregion;
      t.data   = new[32'(t.len)+1];
      t.resp   = new[32'(t.len)+1];
      m_ar_q.push_back(t);
      m_beat_q.push_back(0);
    end
  endfunction

  // 同一 ID の Read は発行順に返るので、最も古い同 ID に積む
  function void sample_r();
    axi_burst_item t;
    int            idx[$];
    int unsigned   n;
    int unsigned   rid;
    bit            last_exp;
    if( (vif.mon_cb.rvalid===1'b1)&&(vif.mon_cb.rready===1'b1) ) begin
      rid = 32'(vif.mon_cb.rid);
      idx = m_ar_q.find_first_index(x) with( x.id==rid );
      if( idx.size()==0 ) begin
        `uvm_error("RD_MON", $sformatf("R with unexpected RID=%0d", rid))
        return;
      end
      t         = m_ar_q[idx[0]];
      n         = m_beat_q[idx[0]];
      last_exp  = (n==32'(t.len));
      t.data[n] = MAX_DATA_W'(vif.mon_cb.rdata);
      t.resp[n] = vif.mon_cb.rresp;
      t.resp_id = rid;
      if( vif.mon_cb.rlast!==last_exp ) begin
        `uvm_error("RD_MON", $sformatf("RLAST=%b at beat %0d : %s", vif.mon_cb.rlast, n, t.convert2string()))
      end
      if( last_exp||(vif.mon_cb.rlast===1'b1) ) begin
        m_ar_q.delete(idx[0]);
        m_beat_q.delete(idx[0]);
        if( last_exp ) begin
          `uvm_info("RD_MON", t.convert2string(), UVM_HIGH)
          ap.write(t);
        end
      end else begin
        m_beat_q[idx[0]] = n + 1;
      end
    end
  endfunction

endclass

//=============================================================================
// Agent
//=============================================================================
class axi_rd_slv_agent extends uvm_agent;

  `uvm_component_utils(axi_rd_slv_agent)

  axi_rd_responder rsp;
  axi_rd_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axi_rd_monitor::type_id::create("mon", this);
    if( get_is_active()==UVM_ACTIVE ) begin
      rsp = axi_rd_responder::type_id::create("rsp", this);
    end
  endfunction

endclass

//=============================================================================
// axi_wr_slv_agent.svh
//-----------------------------------------------------------------------------
//  出力側 AXI4 スレーブ agent (DUT の AW / W / B に応答する側)。
//    axi_wr_responder : AW / W を受けてメモリへ書き込み、B を返す。
//                       cfg に従ってストール・READY の出し方・SLVERR を変える
//    axi_wr_monitor   : AW / W / B を観測し、完了した Write バーストを出す
//
//  駆動は全て clocking block 経由で、@(vif.slv_cb) の直後 (間にブロッキング呼び出し
//  を挟まない) に行う。握手は VALID と READY の両方のサンプル値で判定する。
//=============================================================================

//=============================================================================
// Responder
//=============================================================================
class axi_wr_responder extends uvm_component;

  `uvm_component_utils(axi_wr_responder)

  virtual axi_wr_if vif;
  axi_mem           mem;
  axi_slv_cfg       cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(axi_wr_vif_t)::get(this,"","axi_wr_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (axi_wr_vif) is not set")
    end
  endfunction

  //---------------------------------------------------------------------------
  // Write : AW -> W (全ビート) -> B
  //   エラー範囲に入ったビートはメモリに書かず、B で SLVERR を返す
  //---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    bit [OUT_ID_W-1:0] id;
    bit [63:0]         addr;
    bit [7:0]          len;
    bit [2:0]          size;
    bit [1:0]          burst;
    bit [63:0]         a;
    int unsigned       beat;
    int unsigned       dly;
    bit                err;
    bit                hs;
    @(vif.slv_cb);
    vif.slv_cb.awready <= 1'b0;
    vif.slv_cb.wready  <= 1'b0;
    vif.slv_cb.bvalid  <= 1'b0;
    vif.slv_cb.bid     <= '0;
    vif.slv_cb.bresp   <= AXI_OKAY;
    wait( vif.aresetn===1'b1 );
    forever begin
      // --- AW ---
      hs = 1'b0;
      while( !hs ) begin
        @(vif.slv_cb);
        if( (vif.slv_cb.awvalid===1'b1)&&(vif.slv_cb.awready===1'b1) ) begin
          hs    = 1'b1;
          id    = vif.slv_cb.awid;
          addr  = 64'(vif.slv_cb.awaddr);
          len   = vif.slv_cb.awlen;
          size  = vif.slv_cb.awsize;
          burst = vif.slv_cb.awburst;
          vif.slv_cb.awready <= 1'b0;
          vif.slv_cb.wready  <= cfg.ready_next(vif.slv_cb.wvalid, 1'b0);
        end else begin
          vif.slv_cb.awready <= cfg.ready_next(vif.slv_cb.awvalid, 1'b0);
        end
      end
      // --- W ---
      beat = 0;
      err  = 1'b0;
      while( beat<=32'(len) ) begin
        @(vif.slv_cb);
        if( (vif.slv_cb.wvalid===1'b1)&&(vif.slv_cb.wready===1'b1) ) begin
          a = axi_beat_addr(addr, len, size, axi_burst_e'(burst), beat);
          if( cfg.in_err(a) ) begin
            err = 1'b1;
          end else begin
            mem.write_word(a, MAX_DATA_W'(vif.slv_cb.wdata), MAX_STRB_W'(vif.slv_cb.wstrb), OUT_STRB_W);
          end
          if( beat==32'(len) ) begin
            vif.slv_cb.wready <= 1'b0;
          end else begin
            vif.slv_cb.wready <= cfg.ready_next(1'b1, 1'b1);
          end
          beat++;
        end else begin
          vif.slv_cb.wready <= cfg.ready_next(vif.slv_cb.wvalid, 1'b0);
        end
      end
      // --- B ---
      dly = cfg.delay();
      repeat( dly ) begin
        @(vif.slv_cb);
      end
      vif.slv_cb.bvalid <= 1'b1;
      vif.slv_cb.bid    <= id;
      vif.slv_cb.bresp  <= err ? AXI_SLVERR : AXI_OKAY;
      do begin
        @(vif.slv_cb);
      end while( !((vif.slv_cb.bvalid===1'b1)&&(vif.slv_cb.bready===1'b1)) );
      vif.slv_cb.bvalid <= 1'b0;
    end
  endtask

endclass

//=============================================================================
// Write monitor
//=============================================================================
class axi_wr_monitor extends uvm_monitor;

  `uvm_component_utils(axi_wr_monitor)

  virtual axi_wr_if                   vif;
  uvm_analysis_port #(axi_burst_item) ap;

  // AXI4 では W が AW より先に来てもよいので、両方をキューで突き合わせる
  protected axi_burst_item       m_aw_q[$];     // AW 受領済み、W 待ち
  protected axi_burst_item       m_wb_q[$];     // W バースト受領済み、AW 待ち
  protected axi_burst_item       m_b_q[$];      // AW + W 揃い、B 待ち
  protected bit [MAX_DATA_W-1:0] m_wdata_q[$];  // 受信中の W バースト
  protected bit [MAX_STRB_W-1:0] m_wstrb_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(axi_wr_vif_t)::get(this,"","axi_wr_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (axi_wr_vif) is not set")
    end
  endfunction

  task run_phase(uvm_phase phase);
    wait( vif.aresetn===1'b1 );
    forever begin
      @(vif.mon_cb);
      sample_aw();
      sample_w();
      pair_aw_w();
      sample_b();
    end
  endtask

  function void sample_aw();
    axi_burst_item t;
    if( (vif.mon_cb.awvalid===1'b1)&&(vif.mon_cb.awready===1'b1) ) begin
      t        = axi_burst_item::type_id::create("wr_tr");
      t.dir    = AXI_WRITE;
      t.id     = 32'(vif.mon_cb.awid);
      t.addr   = 64'(vif.mon_cb.awaddr);
      t.len    = vif.mon_cb.awlen;
      t.size   = vif.mon_cb.awsize;
      t.burst  = axi_burst_e'(vif.mon_cb.awburst);
      t.lock   = vif.mon_cb.awlock;
      t.cache  = vif.mon_cb.awcache;
      t.prot   = vif.mon_cb.awprot;
      t.qos    = vif.mon_cb.awqos;
      t.region = vif.mon_cb.awregion;
      m_aw_q.push_back(t);
    end
  endfunction

  function void sample_w();
    axi_burst_item t;
    if( (vif.mon_cb.wvalid===1'b1)&&(vif.mon_cb.wready===1'b1) ) begin
      m_wdata_q.push_back(MAX_DATA_W'(vif.mon_cb.wdata));
      m_wstrb_q.push_back(MAX_STRB_W'(vif.mon_cb.wstrb));
      if( vif.mon_cb.wlast===1'b1 ) begin
        t      = axi_burst_item::type_id::create("w_burst");
        t.data = new[m_wdata_q.size()];
        t.strb = new[m_wstrb_q.size()];
        foreach( m_wdata_q[i] ) begin
          t.data[i] = m_wdata_q[i];
          t.strb[i] = m_wstrb_q[i];
        end
        m_wb_q.push_back(t);
        m_wdata_q.delete();
        m_wstrb_q.delete();
      end
    end
  endfunction

  function void pair_aw_w();
    axi_burst_item aw;
    axi_burst_item wb;
    while( (m_aw_q.size()>0)&&(m_wb_q.size()>0) ) begin
      aw = m_aw_q.pop_front();
      wb = m_wb_q.pop_front();
      if( wb.data.size()!=(32'(aw.len)+1) ) begin
        `uvm_error("WR_MON", $sformatf("W beats (%0d) != AWLEN+1 (%0d) : %s"
                                      , wb.data.size(), 32'(aw.len)+1, aw.convert2string()))
      end
      aw.data = wb.data;
      aw.strb = wb.strb;
      m_b_q.push_back(aw);
    end
  endfunction

  function void sample_b();
    axi_burst_item t;
    int            idx[$];
    int unsigned   bid;
    if( (vif.mon_cb.bvalid===1'b1)&&(vif.mon_cb.bready===1'b1) ) begin
      bid = 32'(vif.mon_cb.bid);
      idx = m_b_q.find_first_index(x) with( x.id==bid );
      if( idx.size()==0 ) begin
        `uvm_error("WR_MON", $sformatf("B with unexpected BID=%0d", bid))
      end else begin
        t = m_b_q[idx[0]];
        m_b_q.delete(idx[0]);
        t.resp    = new[1];
        t.resp[0] = vif.mon_cb.bresp;
        t.resp_id = bid;
        `uvm_info("WR_MON", t.convert2string(), UVM_HIGH)
        ap.write(t);
      end
    end
  endfunction

endclass

//=============================================================================
// Agent
//=============================================================================
class axi_wr_slv_agent extends uvm_agent;

  `uvm_component_utils(axi_wr_slv_agent)

  axi_wr_responder rsp;
  axi_wr_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axi_wr_monitor::type_id::create("mon", this);
    if( get_is_active()==UVM_ACTIVE ) begin
      rsp = axi_wr_responder::type_id::create("rsp", this);
    end
  endfunction

endclass

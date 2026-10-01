//=============================================================================
// axi_slv_agent.svh
//-----------------------------------------------------------------------------
//  AXI4 スレーブ agent (DUT のマスタに応答する側)。
//    axi_slv_responder : AW/W を受けてメモリへ書き込み B を返す /
//                        AR を受けてメモリから R を返す (Write と Read は独立に並行)
//                        cfg に従ってストール・READY の出し方・SLVERR を変える
//    axi_wr_monitor    : AW / W / B を観測し、完了した Write バーストを出す
//    axi_rd_monitor    : AR / R を観測し、完了した Read バーストを出す
//
//  駆動は全て clocking block 経由で、@(vif.xx_cb) の直後 (間にブロッキング呼び出し
//  を挟まない) に行う。握手は VALID と READY の両方のサンプル値で判定する。
//=============================================================================

//=============================================================================
// Responder
//=============================================================================
class axi_slv_responder extends uvm_component;

  `uvm_component_utils(axi_slv_responder)

  virtual axi_if vif;
  axi_mem        mem;
  axi_slv_cfg    cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(axi_vif_t)::get(this,"","axi_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (axi_vif) is not set")
    end
  endfunction

  task run_phase(uvm_phase phase);
    fork
      run_write();
      run_read();
    join
  endtask

  //---------------------------------------------------------------------------
  // Write : AW -> W (全ビート) -> B
  //---------------------------------------------------------------------------
  task run_write();
    bit [ID_W-1:0]   id;
    bit [ADDR_W-1:0] addr;
    bit [7:0]        len;
    bit [2:0]        size;
    bit [1:0]        burst;
    bit [ADDR_W-1:0] a;
    int unsigned     beat;
    int unsigned     dly;
    bit              err;
    bit              hs;
    @(vif.wr_cb);
    vif.wr_cb.awready <= 1'b0;
    vif.wr_cb.wready  <= 1'b0;
    vif.wr_cb.bvalid  <= 1'b0;
    vif.wr_cb.bid     <= '0;
    vif.wr_cb.bresp   <= AXI_OKAY;
    wait( vif.aresetn===1'b1 );
    forever begin
      // --- AW ---
      hs = 1'b0;
      while( !hs ) begin
        @(vif.wr_cb);
        if( (vif.wr_cb.awvalid===1'b1)&&(vif.wr_cb.awready===1'b1) ) begin
          hs    = 1'b1;
          id    = vif.wr_cb.awid;
          addr  = vif.wr_cb.awaddr;
          len   = vif.wr_cb.awlen;
          size  = vif.wr_cb.awsize;
          burst = vif.wr_cb.awburst;
          vif.wr_cb.awready <= 1'b0;
          vif.wr_cb.wready  <= cfg.ready_next(vif.wr_cb.wvalid, 1'b0);
        end else begin
          vif.wr_cb.awready <= cfg.ready_next(vif.wr_cb.awvalid, 1'b0);
        end
      end
      // --- W ---
      beat = 0;
      err  = 1'b0;
      while( beat<=32'(len) ) begin
        @(vif.wr_cb);
        if( (vif.wr_cb.wvalid===1'b1)&&(vif.wr_cb.wready===1'b1) ) begin
          a = axi_beat_addr(addr, len, size, axi_burst_e'(burst), beat);
          if( cfg.in_err(a) ) begin
            err = 1'b1;
          end else begin
            mem.write_word(a, vif.wr_cb.wdata, vif.wr_cb.wstrb);
          end
          if( beat==32'(len) ) begin
            vif.wr_cb.wready <= 1'b0;
          end else begin
            vif.wr_cb.wready <= cfg.ready_next(1'b1, 1'b1);
          end
          beat++;
        end else begin
          vif.wr_cb.wready <= cfg.ready_next(vif.wr_cb.wvalid, 1'b0);
        end
      end
      // --- B ---
      dly = cfg.delay();
      repeat( dly ) begin
        @(vif.wr_cb);
      end
      vif.wr_cb.bvalid <= 1'b1;
      vif.wr_cb.bid    <= id;
      vif.wr_cb.bresp  <= err ? AXI_SLVERR : AXI_OKAY;
      do begin
        @(vif.wr_cb);
      end while( !((vif.wr_cb.bvalid===1'b1)&&(vif.wr_cb.bready===1'b1)) );
      vif.wr_cb.bvalid <= 1'b0;
    end
  endtask

  //---------------------------------------------------------------------------
  // Read : AR -> R (全ビート)
  //---------------------------------------------------------------------------
  task run_read();
    bit [ID_W-1:0]   id;
    bit [ADDR_W-1:0] addr;
    bit [7:0]        len;
    bit [2:0]        size;
    bit [1:0]        burst;
    bit [ADDR_W-1:0] a;
    int unsigned     dly;
    bit              hs;
    @(vif.rd_cb);
    vif.rd_cb.arready <= 1'b0;
    vif.rd_cb.rvalid  <= 1'b0;
    vif.rd_cb.rid     <= '0;
    vif.rd_cb.rdata   <= '0;
    vif.rd_cb.rresp   <= AXI_OKAY;
    vif.rd_cb.rlast   <= 1'b0;
    wait( vif.aresetn===1'b1 );
    forever begin
      // --- AR ---
      hs = 1'b0;
      while( !hs ) begin
        @(vif.rd_cb);
        if( (vif.rd_cb.arvalid===1'b1)&&(vif.rd_cb.arready===1'b1) ) begin
          hs    = 1'b1;
          id    = vif.rd_cb.arid;
          addr  = vif.rd_cb.araddr;
          len   = vif.rd_cb.arlen;
          size  = vif.rd_cb.arsize;
          burst = vif.rd_cb.arburst;
          vif.rd_cb.arready <= 1'b0;
        end else begin
          vif.rd_cb.arready <= cfg.ready_next(vif.rd_cb.arvalid, 1'b0);
        end
      end
      // --- R --- (ビートごとにランダムな待ちを入れる。出したら握手まで保持)
      for( int unsigned beat=0; beat<=32'(len); beat++ ) begin
        dly = cfg.delay();
        if( dly>0 ) begin
          vif.rd_cb.rvalid <= 1'b0;
          repeat( dly ) begin
            @(vif.rd_cb);
          end
        end
        a = axi_beat_addr(addr, len, size, axi_burst_e'(burst), beat);
        vif.rd_cb.rvalid <= 1'b1;
        vif.rd_cb.rid    <= id;
        vif.rd_cb.rdata  <= mem.read_word(a);
        vif.rd_cb.rresp  <= cfg.in_err(a) ? AXI_SLVERR : AXI_OKAY;
        vif.rd_cb.rlast  <= (beat==32'(len));
        do begin
          @(vif.rd_cb);
        end while( !((vif.rd_cb.rvalid===1'b1)&&(vif.rd_cb.rready===1'b1)) );
      end
      vif.rd_cb.rvalid <= 1'b0;
      vif.rd_cb.rlast  <= 1'b0;
    end
  endtask

endclass

//=============================================================================
// Write monitor
//=============================================================================
class axi_wr_monitor extends uvm_monitor;

  `uvm_component_utils(axi_wr_monitor)

  virtual axi_if                      vif;
  uvm_analysis_port #(axi_burst_item) ap;

  // AXI4 では W が AW より先に来てもよいので、両方をキューで突き合わせる
  protected axi_burst_item   m_aw_q[$];     // AW 受領済み、W 待ち
  protected axi_burst_item   m_wb_q[$];     // W バースト受領済み、AW 待ち
  protected axi_burst_item   m_b_q[$];      // AW + W 揃い、B 待ち
  protected bit [DATA_W-1:0] m_wdata_q[$];  // 受信中の W バースト
  protected bit [STRB_W-1:0] m_wstrb_q[$];

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
      sample_aw();
      sample_w();
      pair_aw_w();
      sample_b();
    end
  endtask

  function void sample_aw();
    axi_burst_item t;
    if( (vif.mon_cb.awvalid===1'b1)&&(vif.mon_cb.awready===1'b1) ) begin
      t       = axi_burst_item::type_id::create("wr_tr");
      t.dir   = AXI_WRITE;
      t.id    = vif.mon_cb.awid;
      t.addr  = vif.mon_cb.awaddr;
      t.len   = vif.mon_cb.awlen;
      t.size  = vif.mon_cb.awsize;
      t.burst = axi_burst_e'(vif.mon_cb.awburst);
      m_aw_q.push_back(t);
    end
  endfunction

  function void sample_w();
    axi_burst_item t;
    if( (vif.mon_cb.wvalid===1'b1)&&(vif.mon_cb.wready===1'b1) ) begin
      m_wdata_q.push_back(vif.mon_cb.wdata);
      m_wstrb_q.push_back(vif.mon_cb.wstrb);
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
    bit [ID_W-1:0] bid;
    if( (vif.mon_cb.bvalid===1'b1)&&(vif.mon_cb.bready===1'b1) ) begin
      bid = vif.mon_cb.bid;
      idx = m_b_q.find_first_index(x) with( x.id==bid );
      if( idx.size()==0 ) begin
        `uvm_error("WR_MON", $sformatf("B with unexpected BID=%0h", bid))
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
// Read monitor
//=============================================================================
class axi_rd_monitor extends uvm_monitor;

  `uvm_component_utils(axi_rd_monitor)

  virtual axi_if                      vif;
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
    if( !uvm_config_db#(axi_vif_t)::get(this,"","axi_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (axi_vif) is not set")
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
      t       = axi_burst_item::type_id::create("rd_tr");
      t.dir   = AXI_READ;
      t.id    = vif.mon_cb.arid;
      t.addr  = vif.mon_cb.araddr;
      t.len   = vif.mon_cb.arlen;
      t.size  = vif.mon_cb.arsize;
      t.burst = axi_burst_e'(vif.mon_cb.arburst);
      t.data  = new[32'(t.len)+1];
      t.resp  = new[32'(t.len)+1];
      m_ar_q.push_back(t);
      m_beat_q.push_back(0);
    end
  endfunction

  // 同一 ID の Read は発行順に返る (AXI4 spec A6.3) ので、最も古い同 ID に積む
  function void sample_r();
    axi_burst_item t;
    int            idx[$];
    int unsigned   n;
    bit            last_exp;
    bit [ID_W-1:0] rid;
    if( (vif.mon_cb.rvalid===1'b1)&&(vif.mon_cb.rready===1'b1) ) begin
      rid = vif.mon_cb.rid;
      idx = m_ar_q.find_first_index(x) with( x.id==rid );
      if( idx.size()==0 ) begin
        `uvm_error("RD_MON", $sformatf("R with unexpected RID=%0h", rid))
        return;
      end
      t         = m_ar_q[idx[0]];
      n         = m_beat_q[idx[0]];
      last_exp  = (n==32'(t.len));
      t.data[n] = vif.mon_cb.rdata;
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
class axi_slv_agent extends uvm_agent;

  `uvm_component_utils(axi_slv_agent)

  axi_slv_responder rsp;
  axi_wr_monitor    wr_mon;
  axi_rd_monitor    rd_mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    rsp    = axi_slv_responder::type_id::create("rsp", this);
    wr_mon = axi_wr_monitor::type_id::create("wr_mon", this);
    rd_mon = axi_rd_monitor::type_id::create("rd_mon", this);
  endfunction

endclass

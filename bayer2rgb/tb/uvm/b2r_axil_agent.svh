// ============================================================================
// AXI4-Lite マスタエージェント(レジスタアクセス)
//   - AW と W は別々の乱数遅延で出す(順番が入れ替わる場合も試す)
//   - BREADY / RREADY は乱数で遅らせる
// ============================================================================
class b2r_axil_item extends uvm_sequence_item;
  `uvm_object_utils(b2r_axil_item)
  bit        we;
  bit [11:0] addr;
  bit [31:0] data;     // 書き込みデータ / 読み出しデータ
  bit [3:0]  strb;
  bit [1:0]  resp;

  function new( string name="b2r_axil_item" );
    super.new(name);
    strb = 4'hF;
  endfunction

  function string convert2string();
    return $sformatf("%s addr=%03h data=%08h strb=%0h resp=%0d", we ? "WR" : "RD", addr, data, strb, resp);
  endfunction
endclass

typedef uvm_sequencer #(b2r_axil_item) b2r_axil_sequencer;

// 1回の読み書き
class b2r_axil_rw_seq extends uvm_sequence #(b2r_axil_item);
  `uvm_object_utils(b2r_axil_rw_seq)
  bit        we;
  bit [11:0] addr;
  bit [31:0] data;
  bit [3:0]  strb = 4'hF;
  bit [1:0]  resp;

  function new( string name="b2r_axil_rw_seq" );
    super.new(name);
  endfunction

  task body();
    b2r_axil_item it;
    it = b2r_axil_item::type_id::create("it");
    start_item(it);
    it.we   = we;
    it.addr = addr;
    it.data = data;
    it.strb = strb;
    finish_item(it);
    data = it.data;
    resp = it.resp;
  endtask
endclass

class b2r_axil_driver extends uvm_driver #(b2r_axil_item);
  `uvm_component_utils(b2r_axil_driver)
  virtual b2r_axil_if vif;
  int max_dly = 3;     // AW/W/AR を出すまでの最大遅延、READYの最大遅延

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    bit ok;
    super.build_phase(phase);
    ok = uvm_config_db#(virtual b2r_axil_if)::get(this, "", "vif", vif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "b2r_axil_if がない")
    end
  endfunction

  task reset_signals();
    vif.awvalid <= 1'b0;
    vif.awaddr  <= '0;
    vif.awprot  <= '0;
    vif.wvalid  <= 1'b0;
    vif.wdata   <= '0;
    vif.wstrb   <= '0;
    vif.bready  <= 1'b0;
    vif.arvalid <= 1'b0;
    vif.araddr  <= '0;
    vif.arprot  <= '0;
    vif.rready  <= 1'b0;
  endtask

  task wait_cycles( int n );
    for( int i=0; i<n; i++ ) begin
      @(posedge vif.clk);
    end
  endtask

  task drive_aw( b2r_axil_item it );
    wait_cycles($urandom_range(max_dly, 0));
    vif.awaddr  <= it.addr;
    vif.awprot  <= 3'($urandom_range(7, 0));
    vif.awvalid <= 1'b1;
    @(posedge vif.clk);
    while( !vif.awready ) begin
      @(posedge vif.clk);
    end
    vif.awvalid <= 1'b0;
  endtask

  task drive_w( b2r_axil_item it );
    wait_cycles($urandom_range(max_dly, 0));
    vif.wdata  <= it.data;
    vif.wstrb  <= it.strb;
    vif.wvalid <= 1'b1;
    @(posedge vif.clk);
    while( !vif.wready ) begin
      @(posedge vif.clk);
    end
    vif.wvalid <= 1'b0;
  endtask

  task do_write( b2r_axil_item it );
    fork
      drive_aw(it);
      drive_w(it);
    join
    wait_cycles($urandom_range(max_dly, 0));
    vif.bready <= 1'b1;
    @(posedge vif.clk);
    while( !vif.bvalid ) begin
      @(posedge vif.clk);
    end
    it.resp = vif.bresp;
    vif.bready <= 1'b0;
  endtask

  task do_read( b2r_axil_item it );
    wait_cycles($urandom_range(max_dly, 0));
    vif.araddr  <= it.addr;
    vif.arprot  <= 3'($urandom_range(7, 0));
    vif.arvalid <= 1'b1;
    @(posedge vif.clk);
    while( !vif.arready ) begin
      @(posedge vif.clk);
    end
    vif.arvalid <= 1'b0;
    wait_cycles($urandom_range(max_dly, 0));
    vif.rready <= 1'b1;
    @(posedge vif.clk);
    while( !vif.rvalid ) begin
      @(posedge vif.clk);
    end
    it.data = vif.rdata;
    it.resp = vif.rresp;
    vif.rready <= 1'b0;
  endtask

  task run_phase( uvm_phase phase );
    reset_signals();
    @(posedge vif.clk);
    while( !vif.rst_n ) begin
      @(posedge vif.clk);
    end
    forever begin
      seq_item_port.get_next_item(req);
      if( req.we ) begin
        do_write(req);
      end else begin
        do_read(req);
      end
      `uvm_info("AXIL", req.convert2string(), UVM_HIGH)
      seq_item_port.item_done();
    end
  endtask
endclass

class b2r_axil_agent extends uvm_agent;
  `uvm_component_utils(b2r_axil_agent)
  b2r_axil_driver    drv;
  b2r_axil_sequencer sqr;

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    super.build_phase(phase);
    drv = b2r_axil_driver::type_id::create("drv", this);
    sqr = b2r_axil_sequencer::type_id::create("sqr", this);
  endfunction

  function void connect_phase( uvm_phase phase );
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass

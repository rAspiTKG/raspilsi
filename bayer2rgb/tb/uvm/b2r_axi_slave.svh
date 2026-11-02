// ============================================================================
// AXI4 スレーブ(メモリ)モデル
//   - AR/R と AW/W/B を独立に処理する。READYの出し方、応答の遅延、R/Bの間隔、
//     エラー応答の割合を b2r_axi_slave_cfg で変えられる
//   - WはAWより先に来てもよい(AXI4の規則どおり)。AWの順にWを割り当て、
//     WLASTの位置とビート数を検査する
//   - 受け付けた要求と書き込みビートを解析ポートで出す(スコアボード・カバレッジ用)
// ============================================================================
class b2r_axi_slave_cfg extends uvm_object;
  `uvm_object_utils(b2r_axi_slave_cfg)
  int ar_ready_pct = 100;   // ARREADY を出す確率(%)
  int aw_ready_pct = 100;
  int w_ready_pct  = 100;
  int r_lat_min    = 2;     // AR受け付けから最初のRまでのクロック数
  int r_lat_max    = 8;
  int r_gap_pct    = 0;     // Rのビートの間に空きを入れる確率(%)
  int b_lat_min    = 1;     // WLASTからBまでのクロック数
  int b_lat_max    = 8;
  int b_gap_pct    = 0;
  int max_rd_ost   = 8;     // スレーブが受け付ける同時発行数
  int max_wr_ost   = 8;
  int rd_err_pct   = 0;     // エラー応答にするバーストの割合(%)
  int wr_err_pct   = 0;

  function new( string name="b2r_axi_slave_cfg" );
    super.new(name);
  endfunction

  // 応答の遅延・READYを乱数で決める
  function void rand_timing( int level );
    case( level )
      0 : begin
        ar_ready_pct = 100;
        aw_ready_pct = 100;
        w_ready_pct  = 100;
        r_lat_min    = 1;
        r_lat_max    = 2;
        r_gap_pct    = 0;
        b_lat_min    = 1;
        b_lat_max    = 2;
        b_gap_pct    = 0;
      end
      1 : begin
        ar_ready_pct = $urandom_range(100, 50);
        aw_ready_pct = $urandom_range(100, 50);
        w_ready_pct  = $urandom_range(100, 50);
        r_lat_min    = $urandom_range(10, 1);
        r_lat_max    = r_lat_min+$urandom_range(30, 0);
        r_gap_pct    = $urandom_range(30, 0);
        b_lat_min    = $urandom_range(10, 1);
        b_lat_max    = b_lat_min+$urandom_range(30, 0);
        b_gap_pct    = $urandom_range(30, 0);
      end
      default : begin
        ar_ready_pct = $urandom_range(60, 10);
        aw_ready_pct = $urandom_range(60, 10);
        w_ready_pct  = $urandom_range(60, 10);
        r_lat_min    = $urandom_range(50, 10);
        r_lat_max    = r_lat_min+$urandom_range(200, 0);
        r_gap_pct    = $urandom_range(70, 20);
        b_lat_min    = $urandom_range(50, 10);
        b_lat_max    = b_lat_min+$urandom_range(200, 0);
        b_gap_pct    = $urandom_range(70, 20);
      end
    endcase
    max_rd_ost = $urandom_range(8, 1);
    max_wr_ost = $urandom_range(8, 1);
  endfunction
endclass

// 受け付けた要求
class b2r_axi_req extends uvm_sequence_item;
  `uvm_object_utils(b2r_axi_req)
  bit        is_wr;
  bit [39:0] addr;
  bit [7:0]  len;
  bit [3:0]  cache;
  bit [2:0]  prot;
  bit [3:0]  qos;
  bit        err;      // このバーストをエラー応答にする
  longint    due;      // 応答を出してよい時刻(スレーブの内部クロック数)

  function new( string name="b2r_axi_req" );
    super.new(name);
  endfunction
endclass

// 書き込みビート
class b2r_axi_wbeat extends uvm_sequence_item;
  `uvm_object_utils(b2r_axi_wbeat)
  bit [39:0]  addr;
  bit [127:0] data;
  bit [15:0]  strb;
  bit         last;

  function new( string name="b2r_axi_wbeat" );
    super.new(name);
  endfunction
endclass

class b2r_axi_slave extends uvm_component;
  `uvm_component_utils(b2r_axi_slave)
  virtual b2r_axi4_if vif;
  b2r_axi_slave_cfg   cfg;
  b2r_mem             mem;
  uvm_analysis_port #(b2r_axi_req)   ar_ap;
  uvm_analysis_port #(b2r_axi_req)   aw_ap;
  uvm_analysis_port #(b2r_axi_wbeat) w_ap;
  // 統計
  int n_ar;
  int n_aw;
  int n_rbeat;
  int n_wbeat;
  int n_rerr;
  int n_berr;
  longint cyc_rd;
  longint cyc_wr;

  b2r_axi_req   rd_q[$];
  b2r_axi_req   aw_q[$];
  b2r_axi_req   b_q[$];
  b2r_axi_wbeat w_q[$];
  int           wr_ost;    // AWを受け付けてBを返していない数

  function new( string name, uvm_component parent );
    super.new(name, parent);
    ar_ap = new("ar_ap", this);
    aw_ap = new("aw_ap", this);
    w_ap  = new("w_ap", this);
  endfunction

  function void build_phase( uvm_phase phase );
    bit ok;
    super.build_phase(phase);
    ok = uvm_config_db#(virtual b2r_axi4_if)::get(this, "", "vif", vif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "b2r_axi4_if がない")
    end
    ok = uvm_config_db#(b2r_axi_slave_cfg)::get(this, "", "cfg", cfg);
    if( !ok ) begin
      cfg = b2r_axi_slave_cfg::type_id::create("cfg");
    end
    if( mem==null ) begin
      mem = new();
    end
  endfunction

  function bit pct( int p );
    return ($urandom_range(99, 0)<p);
  endfunction

  function bit [1:0] err_resp();
    return ($urandom_range(1, 0)==0) ? 2'b10 : 2'b11;   // SLVERR / DECERR
  endfunction

  task reset_signals();
    vif.arready <= 1'b0;
    vif.rvalid  <= 1'b0;
    vif.rid     <= '0;
    vif.rdata   <= '0;
    vif.rresp   <= '0;
    vif.rlast   <= 1'b0;
    vif.awready <= 1'b0;
    vif.wready  <= 1'b0;
    vif.bvalid  <= 1'b0;
    vif.bid     <= '0;
    vif.bresp   <= '0;
  endtask

  // --------------------------------------------------------------------------
  // AR / R
  // --------------------------------------------------------------------------
  task rd_proc();
    bit         presenting;
    int         beat;
    bit [1:0]   resp;
    b2r_axi_req rq;
    presenting = 1'b0;
    beat       = 0;
    forever begin
      @(posedge vif.clk);
      cyc_rd++;
      if( !vif.rst_n ) begin
        rd_q.delete();
        presenting = 1'b0;
        beat       = 0;
        vif.arready <= 1'b0;
        vif.rvalid  <= 1'b0;
        continue;
      end
      // ---- このクロックのハンドシェイク
      if( vif.arvalid&&vif.arready ) begin
        rq       = b2r_axi_req::type_id::create("rq");
        rq.is_wr = 1'b0;
        rq.addr  = vif.araddr;
        rq.len   = vif.arlen;
        rq.cache = vif.arcache;
        rq.prot  = vif.arprot;
        rq.qos   = vif.arqos;
        rq.err   = pct(cfg.rd_err_pct);
        rq.due   = cyc_rd+longint'($urandom_range(cfg.r_lat_max, cfg.r_lat_min));
        rd_q.push_back(rq);
        n_ar++;
        ar_ap.write(rq);
      end
      if( presenting&&vif.rready ) begin
        presenting = 1'b0;
        n_rbeat++;
        if( beat==int'(rd_q[0].len) ) begin
          void'(rd_q.pop_front());
          beat = 0;
        end else begin
          beat++;
        end
      end
      // ---- 次のクロックの出力
      vif.arready <= (rd_q.size()<cfg.max_rd_ost)&&pct(cfg.ar_ready_pct);
      if( !presenting ) begin
        if( (rd_q.size()>0)&&(rd_q[0].due<=cyc_rd)&&!pct(cfg.r_gap_pct) ) begin
          rq   = rd_q[0];
          resp = rq.err ? err_resp() : 2'b00;
          if( rq.err ) begin
            n_rerr++;
          end
          vif.rvalid <= 1'b1;
          vif.rid    <= '0;
          vif.rdata  <= mem.read_beat(rq.addr+40'(16*beat));
          vif.rresp  <= resp;
          vif.rlast  <= (beat==int'(rq.len));
          presenting = 1'b1;
        end else begin
          vif.rvalid <= 1'b0;
          vif.rdata  <= 128'($urandom());
          vif.rlast  <= 1'($urandom_range(1, 0));
        end
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // AW / W / B
  // --------------------------------------------------------------------------
  task wr_proc();
    bit           b_presenting;
    int           wbeat;
    b2r_axi_req   rq;
    b2r_axi_wbeat wb;
    b_presenting = 1'b0;
    wbeat        = 0;
    forever begin
      @(posedge vif.clk);
      cyc_wr++;
      if( !vif.rst_n ) begin
        aw_q.delete();
        w_q.delete();
        b_q.delete();
        wr_ost       = 0;
        wbeat        = 0;
        b_presenting = 1'b0;
        vif.awready <= 1'b0;
        vif.wready  <= 1'b0;
        vif.bvalid  <= 1'b0;
        continue;
      end
      // ---- このクロックのハンドシェイク
      if( vif.awvalid&&vif.awready ) begin
        rq       = b2r_axi_req::type_id::create("rq");
        rq.is_wr = 1'b1;
        rq.addr  = vif.awaddr;
        rq.len   = vif.awlen;
        rq.cache = vif.awcache;
        rq.prot  = vif.awprot;
        rq.qos   = vif.awqos;
        rq.err   = pct(cfg.wr_err_pct);
        aw_q.push_back(rq);
        wr_ost++;
        n_aw++;
        aw_ap.write(rq);
      end
      if( vif.wvalid&&vif.wready ) begin
        wb      = b2r_axi_wbeat::type_id::create("wb");
        wb.data = vif.wdata;
        wb.strb = vif.wstrb;
        wb.last = vif.wlast;
        w_q.push_back(wb);
      end
      if( b_presenting&&vif.bready ) begin
        b_presenting = 1'b0;
        void'(b_q.pop_front());
        wr_ost--;
      end
      // ---- WをAWに割り当てて書く
      while( (aw_q.size()>0)&&(w_q.size()>0) ) begin
        rq      = aw_q[0];
        wb      = w_q.pop_front();
        wb.addr = rq.addr+40'(16*wbeat);
        if( wb.last!=(wbeat==int'(rq.len)) ) begin
          `uvm_error("AXIS_WLAST", $sformatf("WLAST の位置が違う addr=%0h beat=%0d len=%0d wlast=%0d", rq.addr, wbeat, rq.len, wb.last))
        end
        mem.write_beat(wb.addr, wb.data, wb.strb);
        n_wbeat++;
        w_ap.write(wb);
        if( wbeat==int'(rq.len) ) begin
          void'(aw_q.pop_front());
          rq.due = cyc_wr+longint'($urandom_range(cfg.b_lat_max, cfg.b_lat_min));
          b_q.push_back(rq);
          wbeat = 0;
        end else begin
          wbeat++;
        end
      end
      // ---- 次のクロックの出力
      vif.awready <= (wr_ost<cfg.max_wr_ost)&&pct(cfg.aw_ready_pct);
      vif.wready  <= (w_q.size()<64)&&pct(cfg.w_ready_pct);
      if( !b_presenting ) begin
        if( (b_q.size()>0)&&(b_q[0].due<=cyc_wr)&&!pct(cfg.b_gap_pct) ) begin
          vif.bvalid <= 1'b1;
          vif.bid    <= '0;
          if( b_q[0].err ) begin
            vif.bresp <= err_resp();
            n_berr++;
          end else begin
            vif.bresp <= 2'b00;
          end
          b_presenting = 1'b1;
        end else begin
          vif.bvalid <= 1'b0;
          vif.bresp  <= 2'($urandom_range(3, 0));
        end
      end
    end
  endtask

  task run_phase( uvm_phase phase );
    reset_signals();
    fork
      rd_proc();
      wr_proc();
    join_none
  endtask

  function void check_phase( uvm_phase phase );
    if( w_q.size()!=0 ) begin
      `uvm_error("AXIS_W", $sformatf("AWに対応しないWが残っている (%0d)", w_q.size()))
    end
    if( aw_q.size()!=0 ) begin
      `uvm_error("AXIS_AW", $sformatf("Wがそろっていない書き込み要求が残っている (%0d)", aw_q.size()))
    end
  endfunction

  function void report_phase( uvm_phase phase );
    `uvm_info("AXIS", $sformatf("AR=%0d Rビート=%0d AW=%0d Wビート=%0d Rエラー=%0d Bエラー=%0d",
                                n_ar, n_rbeat, n_aw, n_wbeat, n_rerr, n_berr), UVM_LOW)
  endfunction
endclass

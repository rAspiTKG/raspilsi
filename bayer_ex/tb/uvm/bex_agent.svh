// ============================================================================
// エージェント
//   bex_driver      : 入力側の送り手(vld / data を出す。busy=1 の間は保持する)
//   bex_busy_driver : 出力側の受け手(busy を出す。モードで止め方を変える)
//   bex_monitor     : 転送(rst_n=1、vld=1、busy=0 のクロック)を拾う。入力側・出力側で共通
//   bex_in_agent    : 入力側(シーケンサ + ドライバ + モニタ)
//   bex_out_agent   : 出力側(busy のドライバ + モニタ)
// ============================================================================
typedef uvm_sequencer #(bex_item) bex_sequencer;

// ----------------------------------------------------------------------------
class bex_driver extends uvm_driver #(bex_item);
  `uvm_component_utils(bex_driver)
  virtual bex_vbd_if vif;

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    bit ok;
    super.build_phase(phase);
    ok = uvm_config_db#(virtual bex_vbd_if)::get(this, "", "in_vif", vif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "入力側の bex_vbd_if がない")
    end
  endfunction

  // 1転送: gap クロックだけ vld=0 にしてから、vld=1 と data を出し、転送されるまで保持する
  //   リセット中は busy=0 なので、すぐに終わる(その転送はモニタが数えない)
  task drive_item( bex_item it );
    if( it.gap>0 ) begin
      vif.vld <= 1'b0;
      for( int i=0; i<it.gap; i++ ) begin
        @(posedge vif.clk);
      end
    end
    vif.vld  <= 1'b1;
    vif.data <= it.data;
    @(posedge vif.clk);
    while( vif.busy ) begin
      @(posedge vif.clk);
    end
  endtask

  task run_phase( uvm_phase phase );
    vif.vld  <= 1'b0;
    vif.data <= '0;
    forever begin
      // 次の転送がすぐにあれば vld=1 のまま続ける。なければ vld=0 にして待つ
      seq_item_port.try_next_item(req);
      if( req==null ) begin
        vif.vld <= 1'b0;
        seq_item_port.get_next_item(req);
      end
      drive_item(req);
      `uvm_info("DRV", req.convert2string(), UVM_HIGH)
      seq_item_port.item_done();
    end
  endtask
endclass

// ----------------------------------------------------------------------------
// 出力側の busy
//   BUSY_NONE  : いつも 0
//   BUSY_RAND  : 毎クロック pct [%] の確率で 1
//   BUSY_BURST : 0 が 1〜free_max クロック、1 が 1〜busy_max クロックを繰り返す
//   BUSY_HOLD  : いつも 1(テストがモードを変えるまで)
//   BUSY_SCRIPT: script の値を1クロックずつ使い、なくなったら 0
// ----------------------------------------------------------------------------
class bex_busy_driver extends uvm_component;
  `uvm_component_utils(bex_busy_driver)

  typedef enum int {
    BUSY_NONE   = 0,
    BUSY_RAND   = 1,
    BUSY_BURST  = 2,
    BUSY_HOLD   = 3,
    BUSY_SCRIPT = 4
  } mode_e;

  virtual bex_vbd_if vif;
  int mode     = BUSY_RAND;
  int pct      = 30;
  int free_max = 12;
  int busy_max = 12;
  bit script[$];

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    bit ok;
    super.build_phase(phase);
    ok = uvm_config_db#(virtual bex_vbd_if)::get(this, "", "out_vif", vif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "出力側の bex_vbd_if がない")
    end
  endfunction

  task run_phase( uvm_phase phase );
    bit b;
    int run;
    b   = 1'b0;
    run = 0;
    vif.busy <= 1'b0;
    forever begin
      @(posedge vif.clk);
      case( mode )
        BUSY_NONE : begin
          b = 1'b0;
        end
        BUSY_RAND : begin
          b = ($urandom_range(99, 0)<pct);
        end
        BUSY_BURST : begin
          if( run<=0 ) begin
            b = ~b;
            if( b ) begin
              run = $urandom_range(busy_max, 1);
            end else begin
              run = $urandom_range(free_max, 1);
            end
          end
          run--;
        end
        BUSY_HOLD : begin
          b = 1'b1;
        end
        default : begin
          if( script.size()>0 ) begin
            b = script.pop_front();
          end else begin
            b = 1'b0;
          end
        end
      endcase
      vif.busy <= b;
    end
  endtask
endclass

// ----------------------------------------------------------------------------
// モニタ(入力側・出力側で共通)
//   転送を ap に書く。clk の数(cyc)、入力側は設定(misc.cfg)も付ける。
//   ハンドシェイクのイベントをカバレッジに渡す
// ----------------------------------------------------------------------------
class bex_monitor extends uvm_monitor;
  `uvm_component_utils(bex_monitor)

  uvm_analysis_port #(bex_item) ap;
  virtual bex_vbd_if  vif;
  virtual bex_misc_if mvif;
  bex_coverage        cov;
  bit                 is_in;
  longint             cyc;
  longint             first_cyc;   // clear_stats() の後の最初の転送のクロック
  longint             last_cyc;
  longint             n_xfer;
  longint             n_busy;      // busy=1 のクロック数(リセット中を除く)
  longint             n_gap;       // 転送の間の vld=0 のクロック数(最初の転送より後)
  cfg_t               prev_cfg;

  function new( string name, uvm_component parent );
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase( uvm_phase phase );
    bit    ok;
    string key;
    super.build_phase(phase);
    key = is_in ? "in_vif" : "out_vif";
    ok  = uvm_config_db#(virtual bex_vbd_if)::get(this, "", key, vif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", $sformatf("%s がない", key))
    end
    ok = uvm_config_db#(virtual bex_misc_if)::get(this, "", "misc_vif", mvif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "bex_misc_if がない")
    end
  endfunction

  function void clear_stats();
    n_xfer    = 0;
    n_busy    = 0;
    n_gap     = 0;
    first_cyc = -1;
    last_cyc  = -1;
  endfunction

  task run_phase( uvm_phase phase );
    bex_item it;
    cfg_t    c;
    cyc = 0;
    clear_stats();
    forever begin
      @(posedge vif.clk);
      cyc++;
      c = mvif.cfg;
      if( vif.rst_n!==1'b1 ) begin
        last_cyc = -1;
        prev_cfg = c;
        continue;
      end
      if( vif.busy ) begin
        n_busy++;
      end
      if( vif.vld&&!vif.busy ) begin
        it      = bex_item::type_id::create("it");
        it.data = vif.data;
        it.cyc  = cyc;
        it.cfg  = c;
        n_xfer++;
        if( cov!=null ) begin
          if( last_cyc>=0 ) begin
            if( last_cyc==(cyc-1) ) begin
              cov.sample_ev(is_in ? bex_coverage::EV_IN_B2B : bex_coverage::EV_OUT_B2B);
            end else begin
              cov.sample_ev(is_in ? bex_coverage::EV_IN_GAP : bex_coverage::EV_OUT_GAP);
            end
          end
          if( is_in&&(c!=prev_cfg) ) begin
            cov.sample_ev(bex_coverage::EV_CFG_AT_XFER);
          end
          if( !is_in ) begin
            cov.sample_xfer(it.data);
          end
        end
        if( first_cyc<0 ) begin
          first_cyc = cyc;
        end
        last_cyc = cyc;
        `uvm_info(is_in ? "MON_IN" : "MON_OUT", $sformatf("cyc=%0d %s", cyc, it.convert2string()), UVM_HIGH)
        ap.write(it);
      end else if( !vif.vld&&(last_cyc>=0) ) begin
        n_gap++;
      end
      if( cov!=null ) begin
        if( vif.vld&&vif.busy ) begin
          cov.sample_ev(is_in ? bex_coverage::EV_IN_STALL : bex_coverage::EV_OUT_STALL);
        end
        if( is_in&&vif.busy ) begin
          cov.sample_ev(bex_coverage::EV_SKID_FULL);
        end
        if( !is_in&&vif.busy&&!vif.vld ) begin
          cov.sample_ev(bex_coverage::EV_BUSY_IDLE);
        end
      end
      prev_cfg = c;
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class bex_in_agent extends uvm_agent;
  `uvm_component_utils(bex_in_agent)
  bex_sequencer sqr;
  bex_driver    drv;
  bex_monitor   mon;

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    super.build_phase(phase);
    sqr       = bex_sequencer::type_id::create("sqr", this);
    drv       = bex_driver::type_id::create("drv", this);
    mon       = bex_monitor::type_id::create("mon", this);
    mon.is_in = 1'b1;
  endfunction

  function void connect_phase( uvm_phase phase );
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass

// ----------------------------------------------------------------------------
class bex_out_agent extends uvm_agent;
  `uvm_component_utils(bex_out_agent)
  bex_busy_driver bdrv;
  bex_monitor     mon;

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    super.build_phase(phase);
    bdrv      = bex_busy_driver::type_id::create("bdrv", this);
    mon       = bex_monitor::type_id::create("mon", this);
    mon.is_in = 1'b0;
  endfunction
endclass

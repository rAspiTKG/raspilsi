// ============================================================================
// b2r_base_test : テストの共通部分
//   プラスアーグ
//     +B2R_FRAMES=<n>   フレーム数(テストごとの既定値あり)
//     +B2R_TIMING=<n>   メモリの応答の厳しさ 0:速い 1:乱数 2:遅い・詰まりが多い
//     +B2R_WMAX=<n> +B2R_HMAX=<n>  乱数で決める幅・高さの上限
//     +B2R_DUMP=<接頭辞> フレームの入出力をファイルに出す(スコアボード)
// ============================================================================
class b2r_base_test extends uvm_test;
  `uvm_component_utils(b2r_base_test)
  b2r_env             env;
  b2r_axi_slave_cfg   slv_cfg;
  virtual b2r_misc_if mvif;
  int                 n_frames;
  int                 timing_level;
  int                 wmax;
  int                 hmax;
  int                 frame_id;

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    bit ok;
    super.build_phase(phase);
    env     = b2r_env::type_id::create("env", this);
    slv_cfg = b2r_axi_slave_cfg::type_id::create("slv_cfg");
    uvm_config_db#(b2r_axi_slave_cfg)::set(this, "env.mem_slv", "cfg", slv_cfg);
    ok = uvm_config_db#(virtual b2r_misc_if)::get(this, "", "mvif", mvif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "b2r_misc_if がない")
    end
    if( !$value$plusargs("B2R_FRAMES=%d",n_frames) ) begin
      n_frames = default_frames();
    end
    if( !$value$plusargs("B2R_TIMING=%d",timing_level) ) begin
      timing_level = -1;
    end
    if( !$value$plusargs("B2R_WMAX=%d",wmax) ) begin
      wmax = 256;
    end
    if( !$value$plusargs("B2R_HMAX=%d",hmax) ) begin
      hmax = 48;
    end
    if( timing_level>=0 ) begin
      slv_cfg.rand_timing(timing_level);
    end else begin
      slv_cfg.rand_timing($urandom_range(1, 0));
    end
  endfunction

  virtual function int default_frames();
    return 4;
  endfunction

  // --------------------------------------------------------------------------
  // クロック待ち
  // --------------------------------------------------------------------------
  task wait_ctrl( int n );
    for( int i=0; i<n; i++ ) begin
      @(posedge mvif.ctrl_clk);
    end
  endtask

  task wait_clk( int n );
    for( int i=0; i<n; i++ ) begin
      @(posedge mvif.clk);
    end
  endtask

  // --------------------------------------------------------------------------
  // レジスタアクセス
  // --------------------------------------------------------------------------
  task reg_write( bit [11:0] a, bit [31:0] d, bit [3:0] s=4'hF );
    b2r_axil_rw_seq sq;
    sq      = b2r_axil_rw_seq::type_id::create("sq");
    sq.we   = 1'b1;
    sq.addr = a;
    sq.data = d;
    sq.strb = s;
    sq.start(env.axil.sqr);
    if( sq.resp!=2'b00 ) begin
      `uvm_error("REG", $sformatf("書き込みの応答がOKAYでない addr=%03h resp=%0d", a, sq.resp))
    end
  endtask

  task reg_read( bit [11:0] a, output bit [31:0] d );
    b2r_axil_rw_seq sq;
    sq      = b2r_axil_rw_seq::type_id::create("sq");
    sq.we   = 1'b0;
    sq.addr = a;
    sq.start(env.axil.sqr);
    d = sq.data;
    if( sq.resp!=2'b00 ) begin
      `uvm_error("REG", $sformatf("読み出しの応答がOKAYでない addr=%03h resp=%0d", a, sq.resp))
    end
  endtask

  task reg_expect( bit [11:0] a, bit [31:0] exp, bit [31:0] mask=32'hFFFF_FFFF, string what="" );
    bit [31:0] d;
    reg_read(a, d);
    if( (d&mask)!=(exp&mask) ) begin
      `uvm_error("REG", $sformatf("%s addr=%03h 期待=%08h 実際=%08h (mask=%08h)", what, a, exp&mask, d&mask, mask))
    end
  endtask

  // --------------------------------------------------------------------------
  // 設定
  // --------------------------------------------------------------------------
  // CONTROL の値(STARTなし)
  function bit [31:0] ctrl_word( b2r_frame_cfg c, bit auto_restart, bit reg_update );
    bit [31:0] v;
    v                   = 32'h0;
    v[CTL_REG_UPDATE]   = reg_update;
    v[CTL_BYPASS]       = c.bypass;
    v[CTL_TEST_PATTERN] = c.tpg_en;
    v[CTL_AUTO_RESTART] = auto_restart;
    return v;
  endfunction

  // 設定レジスタを全部書く(CONTROLを除く)
  task program_cfg( b2r_frame_cfg c );
    reg_write(A_ACTIVE_WIDTH, 32'(c.width));
    reg_write(A_ACTIVE_HEIGHT, 32'(c.height));
    reg_write(A_BAYER_PHASE, 32'(c.phase));
    reg_write(A_FUNC_EN, {28'h0, c.gamma_en, c.fcs_en, c.wb_en, c.blc_en});
    reg_write(A_BLC_R_GR, {2'b00, c.blc[1], 2'b00, c.blc[0]});
    reg_write(A_BLC_GB_B, {2'b00, c.blc[3], 2'b00, c.blc[2]});
    reg_write(A_WB_R_GR, {c.wbg[1], c.wbg[0]});
    reg_write(A_WB_GB_B, {c.wbg[3], c.wbg[2]});
    reg_write(A_FCS_PARAM, {8'h00, c.fcs_gain, 2'b00, c.fcs_th});
    reg_write(A_TPG_SEL, 32'(c.tpg_sel));
    reg_write(A_TPG_COLOR, 32'(c.tpg_color));
    reg_write(A_SRC_ADDR_L, c.src_addr[31:0]);
    reg_write(A_SRC_ADDR_H, 32'(c.src_addr[39:32]));
    reg_write(A_SRC_STRIDE, 32'(c.src_stride));
    reg_write(A_DST_ADDR_L, c.dst_addr[31:0]);
    reg_write(A_DST_ADDR_H, 32'(c.dst_addr[39:32]));
    reg_write(A_DST_STRIDE, 32'(c.dst_stride));
    reg_write(A_AXI_ATTR, {8'h00, c.awqos, c.arqos, 1'b0, c.awprot, 1'b0, c.arprot, c.awcache, c.arcache});
    for( int i=0; i<19; i++ ) begin
      if( i==18 ) begin
        reg_write(12'(A_GAMMA_KNOT+(4*i)), {20'h0, c.gm_knot[36]});
      end else begin
        reg_write(12'(A_GAMMA_KNOT+(4*i)), {4'h0, c.gm_knot[(2*i)+1], 4'h0, c.gm_knot[2*i]});
      end
    end
  endtask

  task start_frame( b2r_frame_cfg c, bit auto_restart=1'b0, bit reg_update=1'b1 );
    bit [31:0] v;
    v             = ctrl_word(c, auto_restart, reg_update);
    v[CTL_START]  = 1'b1;
    reg_write(A_CONTROL, v);
  endtask

  // --------------------------------------------------------------------------
  // 完了待ち
  // --------------------------------------------------------------------------
  // FRAME_DONE が立つまで IRQ_STATUS を読む。立ったら書き込み1でクリアする
  task wait_frame_done( int timeout_ctrl=2000000, output bit [31:0] st );
    int t;
    t = 0;
    forever begin
      reg_read(A_IRQ_STATUS, st);
      if( st[IRQ_FRAME_DONE] ) begin
        reg_write(A_IRQ_STATUS, 32'(1<<IRQ_FRAME_DONE));
        break;
      end
      wait_ctrl(16);
      t = t+24;
      if( t>timeout_ctrl ) begin
        `uvm_fatal("TIMEOUT", "FRAME_DONE が立たない")
      end
    end
  endtask

  // STATUS.BUSY が0になるまで待つ
  task wait_idle( int timeout_ctrl=2000000 );
    bit [31:0] st;
    int        t;
    t = 0;
    forever begin
      reg_read(A_STATUS, st);
      if( !st[0] ) begin
        break;
      end
      wait_ctrl(16);
      t = t+24;
      if( t>timeout_ctrl ) begin
        `uvm_fatal("TIMEOUT", "BUSY が0にならない")
      end
    end
  endtask

  // スコアボードが登録したフレームをすべて確認するまで待つ
  task wait_sb_drain( int timeout_ctrl=100000 );
    int t;
    t = 0;
    while( env.sb.pending()!=0 ) begin
      wait_ctrl(8);
      t = t+8;
      if( t>timeout_ctrl ) begin
        `uvm_error("TIMEOUT", "スコアボードのフレームが完了しない")
        break;
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // フレーム
  // --------------------------------------------------------------------------
  // 乱数の設定(幅・高さは上限まで、アドレスは40bit空間のどこか)
  function b2r_frame_cfg new_cfg( int wm, int hm );
    b2r_frame_cfg c;
    bit [39:0]    base;
    c = b2r_frame_cfg::type_id::create("c");
    c.rand_func();
    c.rand_attr();
    c.width  = 12'(8*$urandom_range(wm/8, 2));
    c.height = 12'(2*$urandom_range(hm/2, 8));
    base     = {8'($urandom_range(254, 0)), 32'($urandom())};
    base     = base&~40'hF;
    c.place(base, 8);
    return c;
  endfunction

  // サイズを変えたあとに配置をやり直す
  function void set_size( b2r_frame_cfg c, int w, int h );
    bit [39:0] base;
    c.width  = 12'(w);
    c.height = 12'(h);
    base     = {8'($urandom_range(254, 0)), 32'($urandom())};
    base     = base&~40'hF;
    c.place(base, 8);
  endfunction

  function b2r_image make_image( b2r_frame_cfg c );
    b2r_image img;
    img = new(c.eff_w(), c.eff_h());
    if( !c.tpg_en ) begin
      img.generate_img(c.img_kind, c.phase);
    end
    return img;
  endfunction

  // 入力を置いて期待値を登録する
  function void prepare_frame( b2r_frame_cfg c, output string name );
    b2r_image img;
    name = $sformatf("f%0d", frame_id);
    frame_id++;
    img = make_image(c);
    if( !c.tpg_en ) begin
      env.mem_slv.mem.load_image(c.src_addr, int'(c.src_stride), img);
    end
    env.sb.expect_frame(name, c, img);
  endfunction

  // 1フレームを実行して確認する
  task run_frame( b2r_frame_cfg c );
    string     name;
    bit [31:0] st;
    prepare_frame(c, name);
    program_cfg(c);
    start_frame(c);
    wait_frame_done(2000000+(c.eff_w()*c.eff_h()), st);
    wait_sb_drain();
    `uvm_info("TEST", $sformatf("%s 完了 %s", name, c.convert2string()), UVM_LOW)
  endtask

  // --------------------------------------------------------------------------
  // 実行
  // --------------------------------------------------------------------------
  virtual task body();
  endtask

  task run_phase( uvm_phase phase );
    phase.raise_objection(this);
    @(posedge mvif.ctrl_clk);
    while( !(mvif.ctrl_rst_n&&mvif.rst_n) ) begin
      @(posedge mvif.ctrl_clk);
    end
    wait_ctrl(10);
    body();
    wait_sb_drain();
    wait_ctrl(50);
    phase.drop_objection(this);
  endtask

  function void report_phase( uvm_phase phase );
    uvm_report_server rs;
    rs = uvm_report_server::get_server();
    if( (rs.get_severity_count(UVM_ERROR)+rs.get_severity_count(UVM_FATAL))==0 ) begin
      `uvm_info("RESULT", "*** TEST PASSED ***", UVM_NONE)
    end else begin
      `uvm_info("RESULT", "*** TEST FAILED ***", UVM_NONE)
    end
  endfunction
endclass

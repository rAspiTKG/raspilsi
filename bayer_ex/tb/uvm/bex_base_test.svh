// ============================================================================
// bex_base_test : テストの共通部分
//   プラスアーグ
//     +BEX_FRAMES=<n>   フレーム数(テストごとの既定値あり)
//     +BEX_WMAX=<n>     乱数で決める幅の上限(4の倍数、既定 64)
//     +BEX_HMAX=<n>     乱数で決める高さの上限(2の倍数、既定 16)
//     +BEX_GAP=<n>      入力の間のあけ方をこれに固定する(bex_frame_seq の gap_mode)
//     +BEX_BUSY=<n>     出力側の busy をこれに固定する(bex_busy_driver の mode)
//     +BEX_DUMP=<file>  比べた組をファイルに書く(スコアボード)
// ============================================================================
class bex_base_test extends uvm_test;
  `uvm_component_utils(bex_base_test)
  bex_env             env;
  virtual bex_misc_if mvif;
  virtual bex_vbd_if  in_vif;
  virtual bex_vbd_if  out_vif;
  bex_cfg             cur_cfg;
  int                 n_frames;
  int                 wmax;
  int                 hmax;
  int                 gap_fix;
  int                 busy_fix;

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void build_phase( uvm_phase phase );
    bit ok;
    super.build_phase(phase);
    env     = bex_env::type_id::create("env", this);
    cur_cfg = bex_cfg::type_id::create("cur_cfg");
    ok = uvm_config_db#(virtual bex_misc_if)::get(this, "", "misc_vif", mvif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "bex_misc_if がない")
    end
    ok = uvm_config_db#(virtual bex_vbd_if)::get(this, "", "in_vif", in_vif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "入力側の bex_vbd_if がない")
    end
    ok = uvm_config_db#(virtual bex_vbd_if)::get(this, "", "out_vif", out_vif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "出力側の bex_vbd_if がない")
    end
    if( !$value$plusargs("BEX_FRAMES=%d",n_frames) ) begin
      n_frames = default_frames();
    end
    if( !$value$plusargs("BEX_WMAX=%d",wmax) ) begin
      wmax = 64;
    end
    if( !$value$plusargs("BEX_HMAX=%d",hmax) ) begin
      hmax = 16;
    end
    if( !$value$plusargs("BEX_GAP=%d",gap_fix) ) begin
      gap_fix = -1;
    end
    if( !$value$plusargs("BEX_BUSY=%d",busy_fix) ) begin
      busy_fix = -1;
    end
  endfunction

  virtual function int default_frames();
    return 4;
  endfunction

  // --------------------------------------------------------------------------
  // クロック待ち
  // --------------------------------------------------------------------------
  task wait_clk( int n );
    for( int i=0; i<n; i++ ) begin
      @(posedge mvif.clk);
    end
  endtask

  // --------------------------------------------------------------------------
  // 設定
  //   wait_empty=1: コアが空になるのを待ってから変える(仕様書 5.4)
  //   clk の立ち上がりで変える。この直後に send_frame を呼ぶと、最初の転送は同じクロックになる
  // --------------------------------------------------------------------------
  task apply_cfg( bex_cfg c, bit wait_empty=1'b1 );
    if( wait_empty ) begin
      wait_drain();
    end
    @(posedge mvif.clk);
    mvif.cfg <= c.to_cfg_t();
    cur_cfg.copy_from(c);
    env.cov.sample_cfg(c.to_cfg_t());
    `uvm_info("TEST", $sformatf("設定 %s", c.convert2string()), UVM_MEDIUM)
  endtask

  // --------------------------------------------------------------------------
  // 画像とフレーム
  // --------------------------------------------------------------------------
  function bex_image new_image( int w, int h, int kind=-1, int level=0 );
    bex_image img;
    int       k;
    img = new(w, h);
    k   = kind;
    if( k<0 ) begin
      k = $urandom_range(bex_image::N_KIND-1, 0);
    end
    img.generate_img(k, level);
    return img;
  endfunction

  function int rand_w();
    return 4*$urandom_range(wmax/4, 1);
  endfunction

  function int rand_h();
    return 2*$urandom_range(hmax/2, 1);
  endfunction

  // 1フレームを送る(全部の転送が DUT に受け取られたら戻る。出力は待たない)
  //   gmode: bex_frame_seq の gap_mode(-1: 乱数)
  task send_frame( bex_image img, int gmode=-1, int gpct=20 );
    bex_frame_seq sq;
    sq          = bex_frame_seq::type_id::create("sq");
    sq.img      = img;
    sq.gap_pct  = gpct;
    if( gap_fix>=0 ) begin
      sq.gap_mode = gap_fix;
    end else if( gmode>=0 ) begin
      sq.gap_mode = gmode;
    end else begin
      sq.gap_mode = $urandom_range(2, 0);
    end
    `uvm_info("TEST", $sformatf("フレーム %0d×%0d(%0d 転送、gap_mode=%0d)", img.w, img.h, img.n_xfer(), sq.gap_mode), UVM_MEDIUM)
    sq.start(env.in_agt.sqr);
  endtask

  // --------------------------------------------------------------------------
  // 出力側の busy(+BEX_BUSY があればそれに固定する)
  // --------------------------------------------------------------------------
  function void set_busy( int mode, int pct=30 );
    if( busy_fix>=0 ) begin
      env.out_agt.bdrv.mode = busy_fix;
    end else begin
      env.out_agt.bdrv.mode = mode;
    end
    env.out_agt.bdrv.pct = pct;
  endfunction

  function void rand_busy();
    case( $urandom_range(3, 0) )
      0 : begin
        set_busy(bex_busy_driver::BUSY_NONE);
      end
      1 : begin
        set_busy(bex_busy_driver::BUSY_BURST);
      end
      default : begin
        set_busy(bex_busy_driver::BUSY_RAND, $urandom_range(60, 10));
      end
    endcase
  endfunction

  // --------------------------------------------------------------------------
  // 出力をすべて受け取るまで待つ(コアが空になる)
  //   1クロック待ってから見る(同じ立ち上がりの入力の転送をモニタが数え終わってから)
  // --------------------------------------------------------------------------
  task wait_drain( int timeout=200000 );
    int t;
    t = 0;
    @(posedge mvif.clk);
    while( env.sb.pending()!=0 ) begin
      @(posedge mvif.clk);
      t++;
      if( t>timeout ) begin
        `uvm_error("TIMEOUT", $sformatf("出力が終わらない(残り %0d 転送)", env.sb.pending()))
        break;
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // リセット(tb_top がクロックと関係のない時刻にかけ、5クロック後に解除する)
  //   リセット中に DUT の o_vld と o_busy が 0 になっていることを確かめる
  // --------------------------------------------------------------------------
  task pulse_reset();
    @(posedge mvif.clk);
    mvif.rst_req <= 1'b1;
    wait( mvif.rst_n===1'b0 );
    mvif.rst_req <= 1'b0;
    #0.01;
    if( (out_vif.vld!==1'b0)||(in_vif.busy!==1'b0) ) begin
      `uvm_error("RESET", $sformatf("リセット中に o_vld=%b o_busy=%b", out_vif.vld, in_vif.busy))
    end
    wait( mvif.rst_n===1'b1 );
    @(posedge mvif.clk);
  endtask

  // --------------------------------------------------------------------------
  // 実行
  // --------------------------------------------------------------------------
  virtual task body();
  endtask

  task run_phase( uvm_phase phase );
    bex_cfg c;
    phase.raise_objection(this);
    c = bex_cfg::type_id::create("c");
    mvif.cfg <= c.to_cfg_t();
    @(posedge mvif.clk);
    while( mvif.rst_n!==1'b1 ) begin
      @(posedge mvif.clk);
    end
    wait_clk(5);
    body();
    wait_drain();
    wait_clk(20);
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

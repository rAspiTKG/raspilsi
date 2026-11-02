// ============================================================================
// テスト一覧
//   bex_smoke_test       値が変わらない設定と、ふつうの設定で1フレームずつ
//   bex_bypass_test      bypass=1(黒レベル・ゲインを乱数にしても入力のまま出る)
//   bex_phase_test       Bayer の並び4種類(色ごとに違う黒レベル・ゲイン)
//   bex_edge_test        端の値(黒レベル最大、ゲイン 0 / 最大、丸めの境目、1転送だけのフレーム)
//   bex_random_test      設定・大きさ・画像・入力の間・出力の busy を乱数で組み合わせる
//   bex_stall_test       入力は続けて送り、出力を長く止める(スキッドと o_busy)
//   bex_throughput_test  止めないとき 1転送/クロック、レイテンシ 3、o_busy=0 のまま
//   bex_reset_test       転送の途中でリセット(中のデータを捨て、その後は正しく動く)
//   bex_cfg_change_test  前のフレームの出力が終わったクロックの次に、設定と最初の転送を同時に変える
//   bex_wave_test        仕様書の波形図用(決まった並び)
// ============================================================================

// ----------------------------------------------------------------------------
class bex_smoke_test extends bex_base_test;
  `uvm_component_utils(bex_smoke_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    bex_cfg c;
    c = bex_cfg::type_id::create("c");
    // 黒レベル 0・ゲイン 1.0倍: 出力は入力と同じ
    set_busy(bex_busy_driver::BUSY_NONE);
    apply_cfg(c);
    send_frame(new_image(16, 4, bex_image::IMG_RAMP), 0);
    // ふつうの設定
    c.blc[0]  = 14'd64;
    c.blc[1]  = 14'd64;
    c.blc[2]  = 14'd64;
    c.blc[3]  = 14'd64;
    c.gain[0] = 16'h1800;
    c.gain[1] = 16'h1000;
    c.gain[2] = 16'h1000;
    c.gain[3] = 16'h2000;
    set_busy(bex_busy_driver::BUSY_RAND, 30);
    apply_cfg(c);
    send_frame(new_image(32, 8, bex_image::IMG_RANDOM), 1);
  endtask
endclass

// ----------------------------------------------------------------------------
class bex_bypass_test extends bex_base_test;
  `uvm_component_utils(bex_bypass_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 3;
  endfunction

  task body();
    bex_cfg c;
    c = bex_cfg::type_id::create("c");
    for( int i=0; i<n_frames; i++ ) begin
      c.rand_cfg(0);
      c.bypass = 1'b1;
      rand_busy();
      apply_cfg(c);
      send_frame(new_image(rand_w(), rand_h()));
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class bex_phase_test extends bex_base_test;
  `uvm_component_utils(bex_phase_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    bex_cfg c;
    c = bex_cfg::type_id::create("c");
    // 色ごとに違う値にして、色の位置の選び方を確かめる
    c.blc[0]  = 14'd100;
    c.blc[1]  = 14'd200;
    c.blc[2]  = 14'd300;
    c.blc[3]  = 14'd400;
    c.gain[0] = 16'h1800;
    c.gain[1] = 16'h1100;
    c.gain[2] = 16'h0F00;
    c.gain[3] = 16'h2000;
    for( int p=0; p<4; p++ ) begin
      c.phase = 2'(p);
      rand_busy();
      apply_cfg(c);
      send_frame(new_image(32, 8, bex_image::IMG_RAMP, 50*p));
      send_frame(new_image(rand_w(), rand_h(), bex_image::IMG_RANDOM));
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class bex_edge_test extends bex_base_test;
  `uvm_component_utils(bex_edge_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  // 全チャネルに同じ黒レベル・ゲイン
  function void set_all( bex_cfg c, bit [13:0] b, bit [15:0] g );
    for( int i=0; i<4; i++ ) begin
      c.blc[i]  = b;
      c.gain[i] = g;
    end
  endfunction

  task one( bex_cfg c, int kind, int level=0, int w=16, int h=4 );
    rand_busy();
    apply_cfg(c);
    send_frame(new_image(w, h, kind, level));
  endtask

  task body();
    bex_cfg c;
    c = bex_cfg::type_id::create("c");
    // 黒レベルが最大: すべて 0
    set_all(c, 14'h3FFF, 16'h1000);
    one(c, bex_image::IMG_EXTREM);
    one(c, bex_image::IMG_RANDOM);
    // ゲイン 0: すべて 0
    set_all(c, 14'd0, 16'h0000);
    one(c, bex_image::IMG_HIGH);
    // ゲイン最大(約16倍): 多くが飽和
    set_all(c, 14'd0, 16'hFFFF);
    one(c, bex_image::IMG_RANDOM);
    one(c, bex_image::IMG_LOW, 900);
    // 黒レベル 0・ゲイン 1.0倍: 値が変わらない(0 と 16383 を含む)
    set_all(c, 14'd0, 16'h1000);
    one(c, bex_image::IMG_EXTREM);
    // 黒レベルの近く(黒レベルちょうど、1つ上、1つ下)
    set_all(c, 14'd1000, 16'h1000);
    one(c, bex_image::IMG_FLAT, 999);
    one(c, bex_image::IMG_FLAT, 1000);
    one(c, bex_image::IMG_FLAT, 1001);
    one(c, bex_image::IMG_LOW, 1000);
    // 丸めの境目(0.5倍で奇数は .5 になる → 切り上げ)
    set_all(c, 14'd0, 16'h0800);
    one(c, bex_image::IMG_RAMP);
    set_all(c, 14'd1, 16'h0001);
    one(c, bex_image::IMG_HIGH);
    // 飽和の境目: 16383 × 1.0倍 = 16383(飽和しない)、16383 × (1 + 1/4096) は飽和
    set_all(c, 14'd0, 16'h1001);
    one(c, bex_image::IMG_FLAT, 16383);
    one(c, bex_image::IMG_FLAT, 16380);
    // 大きさの端: 1転送だけ(sof=eol=eof=1)、1列の転送だけ(毎回 eol)、2ラインだけ
    set_all(c, 14'd16, 16'h1400);
    one(c, bex_image::IMG_RANDOM, 0, 4, 2);
    one(c, bex_image::IMG_RANDOM, 0, 4, 8);
    one(c, bex_image::IMG_RANDOM, 0, 64, 2);
  endtask
endclass

// ----------------------------------------------------------------------------
class bex_random_test extends bex_base_test;
  `uvm_component_utils(bex_random_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 8;
  endfunction

  task body();
    bex_cfg c;
    c = bex_cfg::type_id::create("c");
    for( int i=0; i<n_frames; i++ ) begin
      c.rand_cfg(10);
      rand_busy();
      apply_cfg(c);
      send_frame(new_image(rand_w(), rand_h()));
      // 同じ設定で続けて送ることもある(コアが空になるのを待たない)
      if( $urandom_range(2,0)==0 ) begin
        send_frame(new_image(rand_w(), rand_h()));
      end
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class bex_stall_test extends bex_base_test;
  `uvm_component_utils(bex_stall_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    bex_cfg c;
    c = bex_cfg::type_id::create("c");
    env.out_agt.bdrv.busy_max = 30;
    env.out_agt.bdrv.free_max = 4;
    for( int i=0; i<n_frames; i++ ) begin
      c.rand_cfg(10);
      set_busy(bex_busy_driver::BUSY_BURST);
      apply_cfg(c);
      send_frame(new_image(64, 8), 0);
    end
    wait_drain();
    if( env.in_agt.mon.n_busy==0 ) begin
      `uvm_error("STALL", "o_busy が一度も 1 にならなかった(スキッドを使っていない)")
    end
    `uvm_info("STALL", $sformatf("o_busy=1 のクロック %0d", env.in_agt.mon.n_busy), UVM_LOW)
  endtask
endclass

// ----------------------------------------------------------------------------
class bex_throughput_test extends bex_base_test;
  `uvm_component_utils(bex_throughput_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 3;
  endfunction

  task body();
    bex_cfg   c;
    bex_image img;
    longint   span;
    c = bex_cfg::type_id::create("c");
    set_busy(bex_busy_driver::BUSY_NONE);
    for( int i=0; i<n_frames; i++ ) begin
      c.rand_cfg(20);
      apply_cfg(c);
      env.in_agt.mon.clear_stats();
      env.out_agt.mon.clear_stats();
      env.sb.clear_lat();
      img = new_image(64, 16);
      send_frame(img, 0);
      wait_drain();
      // 入力: 間なく送れた(o_busy=0 のまま)
      span = env.in_agt.mon.last_cyc-env.in_agt.mon.first_cyc+1;
      if( (env.in_agt.mon.n_busy!=0)||(span!=img.n_xfer()) ) begin
        `uvm_error("TPUT", $sformatf("入力が止まった o_busy=1 のクロック %0d、%0d 転送に %0d クロック",
                                      env.in_agt.mon.n_busy, img.n_xfer(), span))
      end
      // 出力: 間なく出た
      span = env.out_agt.mon.last_cyc-env.out_agt.mon.first_cyc+1;
      if( (env.out_agt.mon.n_xfer!=img.n_xfer())||(span!=img.n_xfer()) ) begin
        `uvm_error("TPUT", $sformatf("出力に間がある %0d 転送に %0d クロック", env.out_agt.mon.n_xfer, span))
      end
      // レイテンシはすべて 3
      if( (env.sb.min_lat!=3)||(env.sb.max_lat!=3) ) begin
        `uvm_error("TPUT", $sformatf("レイテンシが %0d〜%0d(3 のはず)", env.sb.min_lat, env.sb.max_lat))
      end
      `uvm_info("TPUT", $sformatf("%0d 転送: 入力 %0d クロック、出力 %0d クロック、レイテンシ %0d", img.n_xfer(),
                                  env.in_agt.mon.last_cyc-env.in_agt.mon.first_cyc+1, span, env.sb.max_lat), UVM_LOW)
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class bex_reset_test extends bex_base_test;
  `uvm_component_utils(bex_reset_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 6;
  endfunction

  task body();
    bex_cfg c;
    c = bex_cfg::type_id::create("c");
    c.rand_cfg(10);
    apply_cfg(c);
    fork
      begin
        for( int i=0; i<n_frames; i++ ) begin
          rand_busy();
          send_frame(new_image(rand_w(), rand_h()));
        end
      end
      begin
        for( int k=0; k<3; k++ ) begin
          wait_clk($urandom_range(300, 30));
          pulse_reset();
        end
      end
    join
    // 出力を止めたままデータをためてからリセット(スキッドまで埋まった状態)
    //   コアが空のときに止める(4転送 = 出力段・PIXCOR の1段目・入力段・スキッドで受け取れる数)
    wait_drain();
    set_busy(bex_busy_driver::BUSY_HOLD);
    send_frame(new_image(16, 2), 0);
    wait_clk(4);
    pulse_reset();
    set_busy(bex_busy_driver::BUSY_RAND, 30);
    // リセットの後も正しく動く
    c.rand_cfg(10);
    apply_cfg(c);
    send_frame(new_image(rand_w(), rand_h()));
    wait_drain();
    if( env.sb.n_reset<4 ) begin
      `uvm_error("RESET", $sformatf("リセットが %0d 回(4回のはず)", env.sb.n_reset))
    end
  endtask
endclass

// ----------------------------------------------------------------------------
class bex_cfg_change_test extends bex_base_test;
  `uvm_component_utils(bex_cfg_change_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 6;
  endfunction

  task body();
    bex_cfg c;
    c = bex_cfg::type_id::create("c");
    for( int i=0; i<n_frames; i++ ) begin
      c.rand_cfg(20);
      rand_busy();
      // 前のフレームの出力が終わるまで待ち、次の立ち上がりで設定を変え、同じクロックで最初の転送をする
      wait_drain();
      apply_cfg(c, 1'b0);
      send_frame(new_image(rand_w(), rand_h()), 0);
    end
  endtask
endclass

// ----------------------------------------------------------------------------
// 仕様書の波形図用(doc/tools/gen_waves.py がこの並びを前提にする)
//   1. 16×4画素(8転送)。入力は続けて送り、5転送目の前に2クロックあける。
//      出力は2転送目から8クロック止める(5転送目でスキッドまで埋まり、送り側は6転送目の vld と data を保持する)
//   2. bypass=1 で 16×2画素(4転送)
//   3. 出力を止めたまま4転送を入れ(スキッドまで埋まる)、リセット
// ----------------------------------------------------------------------------
class bex_wave_test extends bex_base_test;
  `uvm_component_utils(bex_wave_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    bex_cfg       c;
    bex_image     img;
    bex_frame_seq sq;
    c = bex_cfg::type_id::create("c");
    c.phase   = 2'd0;
    c.blc[0]  = 14'd100;
    c.blc[1]  = 14'd200;
    c.blc[2]  = 14'd300;
    c.blc[3]  = 14'd400;
    c.gain[0] = 16'h1800;
    c.gain[1] = 16'h1000;
    c.gain[2] = 16'h1000;
    c.gain[3] = 16'h2000;
    set_busy(bex_busy_driver::BUSY_NONE);
    apply_cfg(c);
    wait_clk(3);
    // ---- 1. 16×4画素
    img = new(16, 4);
    for( int y=0; y<4; y++ ) begin
      for( int x=0; x<16; x++ ) begin
        img.px[(y*16)+x] = 1000+(100*x)+(2000*y);
      end
    end
    env.out_agt.bdrv.script.delete();
    for( int i=0; i<3; i++ ) begin
      env.out_agt.bdrv.script.push_back(1'b0);
    end
    for( int i=0; i<8; i++ ) begin
      env.out_agt.bdrv.script.push_back(1'b1);
    end
    set_busy(bex_busy_driver::BUSY_SCRIPT);
    sq          = bex_frame_seq::type_id::create("sq");
    sq.img      = img;
    sq.gap_mode = 3;
    for( int k=0; k<8; k++ ) begin
      if( k==4 ) begin
        sq.gaps.push_back(2);
      end else begin
        sq.gaps.push_back(0);
      end
    end
    sq.start(env.in_agt.sqr);
    wait_drain();
    wait_clk(4);
    // ---- 2. bypass
    c.bypass = 1'b1;
    apply_cfg(c);
    wait_clk(2);
    img = new(16, 2);
    for( int x=0; x<32; x++ ) begin
      img.px[x] = 500+(250*x);
    end
    send_frame(img, 0);
    wait_drain();
    wait_clk(4);
    // ---- 3. 出力を止めたまま入れてリセット
    c.bypass = 1'b0;
    apply_cfg(c);
    set_busy(bex_busy_driver::BUSY_HOLD);
    wait_clk(2);
    img = new(16, 2);
    for( int x=0; x<32; x++ ) begin
      img.px[x] = 3000+(10*x);
    end
    fork
      begin
        send_frame(img, 0);
      end
      begin
        wait_clk(8);
        pulse_reset();
      end
    join
    set_busy(bex_busy_driver::BUSY_NONE);
    wait_clk(4);
  endtask
endclass

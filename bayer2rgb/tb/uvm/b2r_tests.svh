// ============================================================================
// テスト一覧
//   b2r_reg_test          レジスタのリセット値・読み書き・バイトイネーブル・読み出し専用・未定義アドレス
//   b2r_smoke_test        既定の設定で1フレーム + 乱数の設定
//   b2r_phase_test        Bayerの並び4種類
//   b2r_func_test         BLC/WB/FCS/ガンマの有効・無効とパラメータの乱数
//   b2r_bypass_test       バイパス(R=G=B=Bayer値)
//   b2r_tpg_test          テストパターン4種類(入力メモリを読まないこと)
//   b2r_size_test         幅・高さの境界とクランプ・切り捨て
//   b2r_stress_test       メモリの遅延・READYの詰まりが多い条件
//   b2r_4kb_test          4KB境界をまたぐラインとバーストの分割
//   b2r_auto_restart_test 自動再開とREG_UPDATE(設定の保持)
//   b2r_error_test        読み出し・書き込みのエラー応答と割り込み
//   b2r_sw_reset_test     ソフトリセット(停止中・処理中・STARTと同時)
//   b2r_ctrl_test         処理中のSTART(キュー)、BUSY、割り込み出力
//   b2r_full_frame_test   3840×2160 の1フレーム
//   b2r_random_test       すべてを乱数で組み合わせる(回帰試験用)
// ============================================================================

// ---------------------------------------------------------------------------
class b2r_reg_test extends b2r_base_test;
  `uvm_component_utils(b2r_reg_test)

  typedef struct {
    bit [11:0] addr;
    bit [31:0] rst;     // リセット値
    bit [31:0] mask;    // 書けるビット
    string     name;
  } reg_t;

  reg_t rw_regs[$];

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  function void add( bit [11:0] a, bit [31:0] r, bit [31:0] m, string n );
    reg_t t;
    t.addr = a;
    t.rst  = r;
    t.mask = m;
    t.name = n;
    rw_regs.push_back(t);
  endfunction

  task body();
    bit [31:0] d;
    bit [31:0] wv;
    bit [31:0] bm;
    bit [31:0] ro_exp[4];
    bit [11:0] ro_addr[4];
    bit [11:0] undef_addr[6];
    add(A_CONTROL,       32'h0000_0002, 32'h0000_00B2, "CONTROL");
    add(A_IRQ_ENABLE,    32'h0000_0000, 32'h0000_0007, "IRQ_ENABLE");
    add(A_ACTIVE_WIDTH,  32'h0000_0F00, 32'h0000_0FFF, "ACTIVE_WIDTH");
    add(A_ACTIVE_HEIGHT, 32'h0000_0870, 32'h0000_0FFF, "ACTIVE_HEIGHT");
    add(A_BAYER_PHASE,   32'h0000_0000, 32'h0000_0003, "BAYER_PHASE");
    add(A_FUNC_EN,       32'h0000_000F, 32'h0000_000F, "FUNC_EN");
    add(A_BLC_R_GR,      32'h0000_0000, 32'h3FFF_3FFF, "BLC_R_GR");
    add(A_BLC_GB_B,      32'h0000_0000, 32'h3FFF_3FFF, "BLC_GB_B");
    add(A_WB_R_GR,       32'h1000_1000, 32'hFFFF_FFFF, "WB_R_GR");
    add(A_WB_GB_B,       32'h1000_1000, 32'hFFFF_FFFF, "WB_GB_B");
    add(A_FCS_PARAM,     32'h0010_0100, 32'h00FF_3FFF, "FCS_PARAM");
    add(A_TPG_SEL,       32'h0000_0000, 32'h0000_0003, "TPG_SEL");
    add(A_TPG_COLOR,     32'h0000_0000, 32'h00FF_FFFF, "TPG_COLOR");
    add(A_SRC_ADDR_L,    32'h0000_0000, 32'hFFFF_FFF0, "SRC_ADDR_L");
    add(A_SRC_ADDR_H,    32'h0000_0000, 32'h0000_00FF, "SRC_ADDR_H");
    add(A_SRC_STRIDE,    32'h0000_0000, 32'h00FF_FFF0, "SRC_STRIDE");
    add(A_DST_ADDR_L,    32'h0000_0000, 32'hFFFF_FFF0, "DST_ADDR_L");
    add(A_DST_ADDR_H,    32'h0000_0000, 32'h0000_00FF, "DST_ADDR_H");
    add(A_DST_STRIDE,    32'h0000_0000, 32'h00FF_FFF0, "DST_STRIDE");
    add(A_AXI_ATTR,      32'h0000_0033, 32'h00FF_77FF, "AXI_ATTR");
    for( int i=0; i<19; i++ ) begin
      if( i==18 ) begin
        add(12'(A_GAMMA_KNOT+(4*i)), {20'h0, GM_SRGB[36]}, 32'h0000_0FFF, $sformatf("GAMMA_KNOT%0d", i));
      end else begin
        add(12'(A_GAMMA_KNOT+(4*i)), {4'h0, GM_SRGB[(2*i)+1], 4'h0, GM_SRGB[2*i]}, 32'h0FFF_0FFF, $sformatf("GAMMA_KNOT%0d", i));
      end
    end
    ro_addr[0] = A_VERSION;
    ro_exp[0]  = IP_VERSION;
    ro_addr[1] = A_HWCFG0;
    ro_exp[1]  = {16'(MAX_HEIGHT), 16'(MAX_WIDTH)};
    ro_addr[2] = A_HWCFG1;
    ro_exp[2]  = {8'(MEM_AW), 8'(MEM_BYTES), 8'(IN_BITS), 8'(PPC)};
    ro_addr[3] = A_FRAME_COUNT;
    ro_exp[3]  = 32'h0;
    undef_addr[0] = 12'h04C;
    undef_addr[1] = 12'h05C;
    undef_addr[2] = 12'h074;
    undef_addr[3] = 12'h0FC;
    undef_addr[4] = 12'h14C;
    undef_addr[5] = 12'hFFC;

    // ---- リセット値
    foreach( rw_regs[i] ) begin
      reg_expect(rw_regs[i].addr, rw_regs[i].rst, 32'hFFFF_FFFF, {rw_regs[i].name, " リセット値"});
    end
    reg_expect(A_STATUS, 32'h0, 32'hFFFF_FFFF, "STATUS リセット値");
    reg_expect(A_IRQ_STATUS, 32'h0, 32'hFFFF_FFFF, "IRQ_STATUS リセット値");
    for( int i=0; i<4; i++ ) begin
      reg_expect(ro_addr[i], ro_exp[i], 32'hFFFF_FFFF, "読み出し専用 リセット値");
    end
    // ---- 読み書き(書けないビットは0で読める)
    for( int n=0; n<3; n++ ) begin
      foreach( rw_regs[i] ) begin
        wv = $urandom();
        if( rw_regs[i].addr==A_CONTROL ) begin
          wv[CTL_START]    = 1'b0;
          wv[CTL_SW_RESET] = 1'b0;
        end
        reg_write(rw_regs[i].addr, wv);
        reg_expect(rw_regs[i].addr, wv&rw_regs[i].mask, 32'hFFFF_FFFF, {rw_regs[i].name, " 読み書き"});
      end
    end
    // ---- バイトイネーブル: 全ビット1を書いたあと、1バイトずつ0を書く
    foreach( rw_regs[i] ) begin
      if( rw_regs[i].addr==A_CONTROL ) begin
        continue;
      end
      for( int b=0; b<4; b++ ) begin
        reg_write(rw_regs[i].addr, 32'hFFFF_FFFF);
        reg_write(rw_regs[i].addr, 32'h0000_0000, 4'(1<<b));
        bm = 32'hFF<<(8*b);
        reg_expect(rw_regs[i].addr, (~bm)&rw_regs[i].mask, 32'hFFFF_FFFF, {rw_regs[i].name, " バイトイネーブル"});
      end
    end
    // ---- 読み出し専用は書いても変わらない
    for( int i=0; i<4; i++ ) begin
      reg_write(ro_addr[i], ~ro_exp[i]);
      reg_expect(ro_addr[i], ro_exp[i], 32'hFFFF_FFFF, "読み出し専用");
    end
    reg_write(A_STATUS, 32'hFFFF_FFFF);
    reg_expect(A_STATUS, 32'h0, 32'hFFFF_FFFF, "STATUS 書き込み");
    // ---- IRQ_STATUS は書き込みでは立たない
    reg_write(A_IRQ_STATUS, 32'hFFFF_FFFF);
    reg_expect(A_IRQ_STATUS, 32'h0, 32'hFFFF_FFFF, "IRQ_STATUS 書き込み1");
    // ---- 未定義のアドレスは0で読め、書いても何も変わらない
    for( int i=0; i<6; i++ ) begin
      reg_write(undef_addr[i], $urandom());
      reg_expect(undef_addr[i], 32'h0, 32'hFFFF_FFFF, "未定義アドレス");
    end
    // ---- アドレスの下位2ビットは無視する
    reg_write(12'(A_TPG_COLOR+2), 32'h00AB_CDEF);
    reg_expect(A_TPG_COLOR, 32'h00AB_CDEF, 32'hFFFF_FFFF, "下位2ビットの無視");
    // ---- 最後にリセット値へ戻す
    foreach( rw_regs[i] ) begin
      reg_write(rw_regs[i].addr, rw_regs[i].rst);
    end
    reg_read(A_CONTROL, d);
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_smoke_test extends b2r_base_test;
  `uvm_component_utils(b2r_smoke_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 2;
  endfunction

  task body();
    b2r_frame_cfg c;
    // 1枚目: リセット値の設定(全機能有効・sRGBガンマ)、色付きの矩形
    c          = b2r_frame_cfg::type_id::create("c");
    c.img_kind = 2;
    set_size(c, 64, 32);
    run_frame(c);
    for( int i=1; i<n_frames; i++ ) begin
      c = new_cfg(wmax, hmax);
      run_frame(c);
    end
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_phase_test extends b2r_base_test;
  `uvm_component_utils(b2r_phase_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    b2r_frame_cfg c;
    for( int n=0; n<2; n++ ) begin
      for( int ph=0; ph<4; ph++ ) begin
        c          = new_cfg(wmax, hmax);
        c.phase    = 2'(ph);
        c.bypass   = 1'b0;
        c.fcs_en   = 1'(n);
        c.img_kind = 2;
        run_frame(c);
      end
    end
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_func_test extends b2r_base_test;
  `uvm_component_utils(b2r_func_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 16;
  endfunction

  task body();
    b2r_frame_cfg c;
    for( int i=0; i<n_frames; i++ ) begin
      c          = new_cfg(wmax, hmax);
      c.bypass   = 1'b0;
      c.blc_en   = 1'(i);
      c.wb_en    = 1'(i>>1);
      c.fcs_en   = 1'(i>>2);
      c.gamma_en = 1'(i>>3);
      run_frame(c);
    end
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_bypass_test extends b2r_base_test;
  `uvm_component_utils(b2r_bypass_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    b2r_frame_cfg c;
    for( int i=0; i<n_frames; i++ ) begin
      c          = new_cfg(wmax, hmax);
      c.bypass   = 1'b1;
      c.gamma_en = 1'(i);
      c.fcs_en   = 1'b1;
      run_frame(c);
    end
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_tpg_test extends b2r_base_test;
  `uvm_component_utils(b2r_tpg_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    b2r_frame_cfg c;
    int           n_ar;
    int           ws[4];
    ws[0] = 3840;
    ws[1] = 1928;
    ws[2] = 136;
    ws[3] = 16;
    for( int sel=0; sel<4; sel++ ) begin
      for( int k=0; k<4; k++ ) begin
        c = new_cfg(wmax, hmax);
        c.rand_tpg();
        c.tpg_sel = 2'(sel);
        if( k==3 ) begin
          set_size(c, ws[sel], 16);
        end else begin
          set_size(c, 8*$urandom_range(wmax/8, 2), 2*$urandom_range(hmax/2, 8));
        end
        n_ar = env.mem_slv.n_ar;
        run_frame(c);
        if( env.mem_slv.n_ar!=n_ar ) begin
          `uvm_error("TPG", "テストパターンなのに入力メモリを読んだ")
        end
      end
    end
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_size_test extends b2r_base_test;
  `uvm_component_utils(b2r_size_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    b2r_frame_cfg c;
    int           sz[$];
    // {幅, 高さ} の組(範囲外・8の倍数でない・奇数を含む)
    sz = '{16, 16,   24, 16,   40, 18,   8, 16,   0, 0,   17, 17,   23, 31,
          4095, 16, 3840, 18, 3848, 16, 1928, 16, 16, 4095, 16, 2161, 16, 2159,
          200, 99,  264, 34,  120, 20,  8, 40};
    for( int i=0; i<sz.size(); i+=2 ) begin
      c = new_cfg(wmax, hmax);
      set_size(c, sz[i], sz[i+1]);
      run_frame(c);
    end
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_stress_test extends b2r_base_test;
  `uvm_component_utils(b2r_stress_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 6;
  endfunction

  task body();
    b2r_frame_cfg c;
    for( int i=0; i<n_frames; i++ ) begin
      slv_cfg.rand_timing(2);
      c = new_cfg(wmax, hmax);
      run_frame(c);
    end
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_4kb_test extends b2r_base_test;
  `uvm_component_utils(b2r_4kb_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 8;
  endfunction

  task body();
    b2r_frame_cfg c;
    bit [39:0]    page;
    for( int i=0; i<n_frames; i++ ) begin
      c = new_cfg(wmax, hmax);
      set_size(c, 8*$urandom_range(160, 64), 16);
      page         = {8'($urandom_range(254, 0)), 20'($urandom()), 12'h000};
      // ラインの先頭を4KB境界の少し手前に置き、ライン間隔は4KBの倍数にしない
      c.src_addr   = page+40'h1000-40'(16*$urandom_range(4, 1));
      c.src_stride = 24'(c.src_line_bytes()+(16*$urandom_range(40, 1)));
      c.dst_addr   = page+40'h40_0000+40'h1000-40'(16*$urandom_range(4, 1));
      c.dst_stride = 24'(((c.dst_line_bytes()+15)&~15)+(16*$urandom_range(40, 1)));
      if( i==0 ) begin
        // 4KB境界の1ビート手前(1ビートのバースト)
        c.src_addr = page+40'h0FF0;
        c.dst_addr = page+40'h40_0FF0;
      end
      run_frame(c);
    end
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_auto_restart_test extends b2r_base_test;
  `uvm_component_utils(b2r_auto_restart_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 5;
  endfunction

  // 期待値を登録する(入力はすでにメモリに置いてある)
  function void expect_with( b2r_frame_cfg c, b2r_image img );
    string name;
    name = $sformatf("f%0d", frame_id);
    frame_id++;
    env.sb.expect_frame(name, c, img);
  endfunction

  task body();
    b2r_frame_cfg c[$];
    b2r_image     img[$];
    b2r_frame_cfg decoy;
    bit [31:0]    st;
    bit [39:0]    base;
    // フレームごとの設定。入力・出力の領域はフレームごとに分ける
    for( int i=0; i<n_frames; i++ ) begin
      c.push_back(new_cfg(wmax, hmax));
      c[i].tpg_en = 1'b0;
      c[i].width  = 12'(8*$urandom_range(64, 32));
      c[i].height = 12'(2*$urandom_range(24, 16));
      base        = 40'h10_0000_0000+(40'h400_0000*40'(i));
      c[i].place(base, 8);
      img.push_back(make_image(c[i]));
    end
    slv_cfg.rand_timing(1);
    // フレーム0を自動再開ありで開始する
    env.mem_slv.mem.load_image(c[0].src_addr, int'(c[0].src_stride), img[0]);
    expect_with(c[0], img[0]);
    program_cfg(c[0]);
    start_frame(c[0], 1'b1, 1'b1);
    for( int i=1; i<n_frames; i++ ) begin
      // フレーム i-1 の処理中に、次のフレームの設定を書く
      if( i==2 ) begin
        // REG_UPDATE=0: レジスタを書き換えても、次のフレームは前の設定(c[1])のまま
        reg_write(A_CONTROL, ctrl_word(c[1], 1'b1, 1'b0));
        decoy = new_cfg(wmax, hmax);
        program_cfg(decoy);
        expect_with(c[1], img[1]);
        env.cov.sample_event(b2r_coverage::EV_HOLD_CFG);
      end else begin
        env.mem_slv.mem.load_image(c[i].src_addr, int'(c[i].src_stride), img[i]);
        expect_with(c[i], img[i]);
        program_cfg(c[i]);
        reg_write(A_CONTROL, ctrl_word(c[i], 1'b1, 1'b1));
      end
      wait_frame_done(4000000, st);
      env.cov.sample_event(b2r_coverage::EV_AUTO_RESTART);
    end
    // 最後のフレームの処理中に自動再開を止める
    reg_write(A_CONTROL, ctrl_word(c[n_frames-1], 1'b0, 1'b1));
    wait_frame_done(4000000, st);
    wait_idle();
    wait_sb_drain();
    reg_expect(A_FRAME_COUNT, 32'(n_frames), 32'hFFFF_FFFF, "FRAME_COUNT");
    // 止めたあとは次のフレームが始まらない
    wait_ctrl(2000);
    reg_expect(A_STATUS, 32'h0, 32'h1, "停止後のBUSY");
    reg_expect(A_IRQ_STATUS, 32'h0, 32'h1, "停止後のFRAME_DONE");
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_error_test extends b2r_base_test;
  `uvm_component_utils(b2r_error_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 6;
  endfunction

  task body();
    b2r_frame_cfg c;
    bit [31:0]    st;
    int           n_rerr;
    int           n_berr;
    reg_write(A_IRQ_ENABLE, 32'h7);
    for( int i=0; i<n_frames; i++ ) begin
      slv_cfg.rd_err_pct = ((i%3)==1) ? 0 : 20;
      slv_cfg.wr_err_pct = ((i%3)==0) ? 0 : 20;
      n_rerr = env.mem_slv.n_rerr;
      n_berr = env.mem_slv.n_berr;
      c = new_cfg(wmax, hmax);
      c.tpg_en = 1'b0;
      run_frame(c);
      reg_read(A_IRQ_STATUS, st);
      if( st[IRQ_RD_ERR]!=(env.mem_slv.n_rerr!=n_rerr) ) begin
        `uvm_error("ERR", $sformatf("RD_ERR=%0d だが エラー応答は %0d 回", st[IRQ_RD_ERR], env.mem_slv.n_rerr-n_rerr))
      end
      if( st[IRQ_WR_ERR]!=(env.mem_slv.n_berr!=n_berr) ) begin
        `uvm_error("ERR", $sformatf("WR_ERR=%0d だが エラー応答は %0d 回", st[IRQ_WR_ERR], env.mem_slv.n_berr-n_berr))
      end
      if( st[IRQ_RD_ERR] ) begin
        env.cov.sample_event(b2r_coverage::EV_RD_ERR);
      end
      if( st[IRQ_WR_ERR] ) begin
        env.cov.sample_event(b2r_coverage::EV_WR_ERR);
      end
      // 割り込み出力は状態と許可の論理積
      wait_ctrl(4);
      if( mvif.irq!=((st[2:1]!=2'b00)) ) begin
        `uvm_error("ERR", $sformatf("irq=%0d IRQ_STATUS=%0h", mvif.irq, st))
      end
      if( mvif.irq ) begin
        env.cov.sample_event(b2r_coverage::EV_IRQ_PIN);
      end
      reg_write(A_IRQ_STATUS, 32'h6);
      wait_ctrl(4);
      if( mvif.irq ) begin
        `uvm_error("ERR", "IRQ_STATUS をクリアしても irq が下がらない")
      end
    end
    slv_cfg.rd_err_pct = 0;
    slv_cfg.wr_err_pct = 0;
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_sw_reset_test extends b2r_base_test;
  `uvm_component_utils(b2r_sw_reset_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 4;
  endfunction

  // 処理中のフレームをソフトリセットで止める
  task reset_in_frame( int dly );
    b2r_frame_cfg c;
    string        name;
    bit [31:0]    st;
    bit           done;
    c = new_cfg(wmax, hmax);
    set_size(c, 8*$urandom_range(64, 32), 2*$urandom_range(24, 12));
    prepare_frame(c, name);
    program_cfg(c);
    start_frame(c);
    wait_ctrl(dly);
    reg_read(A_STATUS, st);
    if( st[0] ) begin
      env.cov.sample_event(b2r_coverage::EV_SRST_BUSY);
    end
    reg_write(A_CONTROL, ctrl_word(c, 1'b0, 1'b1)|32'(1<<CTL_SW_RESET));
    if( $urandom_range(1,0)==1 ) begin
      // 2回続けて書いても問題ない
      reg_write(A_CONTROL, ctrl_word(c, 1'b0, 1'b1)|32'(1<<CTL_SW_RESET));
    end
    wait_idle();
    // 止めたフレームは取り下げる(完了していればスコアボードには残っていない)
    done = (env.sb.pending()==0);
    env.sb.abort_frame();
    // リセットの直前に完了したフレームの完了通知は、リセットの後に数えられることがある
    reg_read(A_FRAME_COUNT, st);
    if( (st!=0)&&!(done&&(st==1)) ) begin
      `uvm_error("SRST", $sformatf("ソフトリセット後のFRAME_COUNT=%0d", st))
    end
    reg_write(A_IRQ_STATUS, 32'h7);
  endtask

  task body();
    b2r_frame_cfg c;
    int           n_ar;
    int           n_aw;
    bit [31:0]    st;
    string        name;
    slv_cfg.rand_timing(1);
    // ---- 停止中のソフトリセット
    reg_write(A_CONTROL, 32'(1<<CTL_SW_RESET)|32'(1<<CTL_REG_UPDATE));
    env.cov.sample_event(b2r_coverage::EV_SRST_IDLE);
    wait_idle();
    run_frame(new_cfg(wmax, hmax));
    // ---- 処理中のソフトリセット(止めるタイミングを変える)
    for( int i=0; i<n_frames; i++ ) begin
      reset_in_frame($urandom_range(400, 5));
      // 次のフレームは正しく処理できる
      run_frame(new_cfg(wmax, hmax));
    end
    // ---- STARTとSW_RESETを同時に書くとSW_RESETだけが効く
    n_ar = env.mem_slv.n_ar;
    n_aw = env.mem_slv.n_aw;
    c    = new_cfg(wmax, hmax);
    program_cfg(c);
    reg_write(A_CONTROL, ctrl_word(c, 1'b0, 1'b1)|32'(1<<CTL_SW_RESET)|32'(1<<CTL_START));
    env.cov.sample_event(b2r_coverage::EV_START_SRST);
    wait_idle();
    wait_ctrl(500);
    reg_read(A_IRQ_STATUS, st);
    if( st[IRQ_FRAME_DONE]||(env.mem_slv.n_ar!=n_ar)||(env.mem_slv.n_aw!=n_aw) ) begin
      `uvm_error("SRST", "STARTとSW_RESETを同時に書いたのにフレームが動いた")
    end
    // ---- SW_RESETの直後にSTART(リセットの完了後に始まる)
    c = new_cfg(wmax, hmax);
    prepare_frame(c, name);
    program_cfg(c);
    reg_write(A_CONTROL, ctrl_word(c, 1'b0, 1'b1)|32'(1<<CTL_SW_RESET));
    start_frame(c);
    wait_frame_done(2000000, st);
    wait_sb_drain();
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_ctrl_test extends b2r_base_test;
  `uvm_component_utils(b2r_ctrl_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    b2r_frame_cfg c1;
    b2r_frame_cfg c2;
    string        name;
    bit [31:0]    st;
    int           t;
    slv_cfg.rand_timing(1);
    // ---- 処理中に書いたSTARTは、今のフレームの完了後に実行される
    c1 = new_cfg(wmax, hmax);
    set_size(c1, 8*$urandom_range(64, 32), 32);
    c2 = new_cfg(wmax, hmax);
    prepare_frame(c1, name);
    program_cfg(c1);
    start_frame(c1);
    reg_expect(A_STATUS, 32'h1, 32'h1, "処理中のBUSY");
    prepare_frame(c2, name);
    program_cfg(c2);
    start_frame(c2);
    env.cov.sample_event(b2r_coverage::EV_QUEUED_START);
    wait_frame_done(2000000, st);
    wait_frame_done(2000000, st);
    wait_idle();
    wait_sb_drain();
    reg_expect(A_FRAME_COUNT, 32'd2, 32'hFFFF_FFFF, "FRAME_COUNT");
    // ---- 割り込み出力: FRAME_DONE を許可して完了を irq で待つ
    reg_write(A_IRQ_ENABLE, 32'(1<<IRQ_FRAME_DONE));
    c1 = new_cfg(wmax, hmax);
    prepare_frame(c1, name);
    program_cfg(c1);
    start_frame(c1);
    t = 0;
    while( !mvif.irq ) begin
      wait_ctrl(1);
      t++;
      if( t>2000000 ) begin
        `uvm_fatal("TIMEOUT", "irq が立たない")
      end
    end
    env.cov.sample_event(b2r_coverage::EV_IRQ_PIN);
    reg_expect(A_IRQ_STATUS, 32'(1<<IRQ_FRAME_DONE), 32'h7, "irq のときの IRQ_STATUS");
    reg_write(A_IRQ_STATUS, 32'(1<<IRQ_FRAME_DONE));
    wait_ctrl(4);
    if( mvif.irq ) begin
      `uvm_error("IRQ", "クリアしても irq が下がらない")
    end
    wait_sb_drain();
    // ---- 許可していない割り込みは出ない。あとから許可すると出る
    reg_write(A_IRQ_ENABLE, 32'h0);
    c1 = new_cfg(wmax, hmax);
    prepare_frame(c1, name);
    program_cfg(c1);
    start_frame(c1);
    wait_idle();
    wait_ctrl(10);
    if( mvif.irq ) begin
      `uvm_error("IRQ", "許可していないのに irq が立った")
    end
    reg_expect(A_IRQ_STATUS, 32'(1<<IRQ_FRAME_DONE), 32'h7, "許可なしの IRQ_STATUS");
    reg_write(A_IRQ_ENABLE, 32'h7);
    wait_ctrl(4);
    if( !mvif.irq ) begin
      `uvm_error("IRQ", "許可したのに irq が立たない")
    end
    reg_write(A_IRQ_STATUS, 32'h7);
    wait_ctrl(4);
    if( mvif.irq ) begin
      `uvm_error("IRQ", "クリアしても irq が下がらない")
    end
    wait_sb_drain();
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_full_frame_test extends b2r_base_test;
  `uvm_component_utils(b2r_full_frame_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 1;
  endfunction

  task body();
    b2r_frame_cfg c;
    slv_cfg.rand_timing(0);
    for( int i=0; i<n_frames; i++ ) begin
      c          = b2r_frame_cfg::type_id::create("c");
      c.img_kind = 2;
      c.phase    = 2'(i);
      set_size(c, 3840, 2160);
      run_frame(c);
    end
  endtask
endclass

// ---------------------------------------------------------------------------
class b2r_random_test extends b2r_base_test;
  `uvm_component_utils(b2r_random_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  virtual function int default_frames();
    return 12;
  endfunction

  task body();
    b2r_frame_cfg c;
    for( int i=0; i<n_frames; i++ ) begin
      if( timing_level<0 ) begin
        slv_cfg.rand_timing($urandom_range(2, 0));
      end
      slv_cfg.rd_err_pct = ($urandom_range(9, 0)==0) ? 10 : 0;
      slv_cfg.wr_err_pct = ($urandom_range(9, 0)==0) ? 10 : 0;
      c = new_cfg(wmax, hmax);
      if( $urandom_range(7,0)==0 ) begin
        c.rand_tpg();
      end
      if( $urandom_range(7,0)==0 ) begin
        set_size(c, $urandom_range(4095, 0), $urandom_range(40, 0));
      end
      run_frame(c);
      reg_write(A_IRQ_STATUS, 32'h7);
    end
  endtask
endclass

// ---------------------------------------------------------------------------
// b2r_wave_test : 仕様書の波形図(WaveDrom)を作るための短いテスト
//   TRACE=vcd でビルドし +WAVES を付けて実行する。doc/tools/gen_waves.py が waves.vcd を読む
// ---------------------------------------------------------------------------
class b2r_wave_test extends b2r_base_test;
  `uvm_component_utils(b2r_wave_test)

  function new( string name, uvm_component parent );
    super.new(name, parent);
  endfunction

  task body();
    b2r_frame_cfg c;
    bit [31:0]    d;
    string        name;
    slv_cfg.rand_timing(0);
    slv_cfg.r_lat_min  = 3;
    slv_cfg.r_lat_max  = 3;
    slv_cfg.b_lat_min  = 2;
    slv_cfg.b_lat_max  = 2;
    slv_cfg.max_rd_ost = 8;
    slv_cfg.max_wr_ost = 8;
    env.axil.drv.max_dly = 0;
    // ---- レジスタの書き込みと読み出し
    reg_write(A_IRQ_ENABLE, 32'(1<<IRQ_FRAME_DONE));
    reg_read(A_VERSION, d);
    // ---- 40×16 のフレーム(1ラインの書き込みは7.5ビートなので最後は部分書き込み)
    //      画素は一様乱数(波形図でデータの区別がつくように)。BLC と WB は値の変化が見える設定にする
    c          = b2r_frame_cfg::type_id::create("c");
    c.img_kind = 0;
    c.width    = 12'd40;
    c.height   = 12'd16;
    for( int i=0; i<4; i++ ) begin
      c.blc[i] = 14'd800;
    end
    c.wbg[0]   = 16'h1C00;
    c.wbg[3]   = 16'h1800;
    c.fcs_th   = 14'd4000;
    c.fcs_gain = 8'd4;
    c.src_addr   = 40'h00_1000_0000;
    c.src_stride = 24'd80;
    c.dst_addr   = 40'h00_2000_0000;
    c.dst_stride = 24'd128;
    run_frame(c);
    reg_write(A_IRQ_STATUS, 32'h7);
    // ---- 処理中のソフトリセット
    c            = b2r_frame_cfg::type_id::create("c");
    c.img_kind   = 0;
    c.width      = 12'd64;
    c.height     = 12'd16;
    c.src_addr   = 40'h00_3000_0000;
    c.src_stride = 24'd128;
    c.dst_addr   = 40'h00_4000_0000;
    c.dst_stride = 24'd192;
    prepare_frame(c, name);
    program_cfg(c);
    start_frame(c);
    // 読み出し・処理・書き込みがすべて動いている途中でリセットする
    wait_ctrl(30);
    reg_write(A_CONTROL, ctrl_word(c, 1'b0, 1'b1)|32'(1<<CTL_SW_RESET));
    wait_idle();
    env.sb.abort_frame();
    // ---- 書き込み側が詰まる条件(SKID と書き込みバッファの動作を見る)
    slv_cfg.w_ready_pct = 40;
    c            = b2r_frame_cfg::type_id::create("c");
    c.img_kind   = 1;
    c.width      = 12'd32;
    c.height     = 12'd16;
    c.src_addr   = 40'h00_5000_0000;
    c.src_stride = 24'd64;
    c.dst_addr   = 40'h00_6000_0000;
    c.dst_stride = 24'd96;
    run_frame(c);
  endtask
endclass

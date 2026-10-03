//=============================================================================
// lb_seq_lib.svh
//-----------------------------------------------------------------------------
//  cmd_single_seq : コマンド 1 本を cmd sequencer に流す
//  lb_base_vseq   : 仮想シーケンスの共通処理
//                   入力画像の準備 (入力側メモリへバックドア書き込み) ->
//                   出力先をパターンで埋める -> コマンド発行 -> done 待ち
//  lb_smoke_vseq  : 代表パターン (幅 x 高さの端 / 4KB 跨ぎ / SLVERR / コマンド誤り /
//                   ストール + READY の VALID 待ち / scratchpad 満杯)
//  lb_rand_vseq   : ランダムフレームを、両側スレーブの振る舞いを変えながら流す
//
//  仮想シーケンスはコマンド sequencer の制御と、スレーブ設定 (rd_cfg / wr_cfg) の
//  切り替えをまとめて受け持つ。設定はコマンドが完了してから変える
//  (scoreboard / coverage は受付時の設定を記録している)。
//=============================================================================

class cmd_single_seq extends uvm_sequence #(cmd_item);

  `uvm_object_utils(cmd_single_seq)

  cmd_item m_item;

  function new(string name = "cmd_single_seq");
    super.new(name);
  endfunction

  task body();
    start_item(m_item);
    finish_item(m_item);
  endtask

endclass

//=============================================================================
// 共通処理
//=============================================================================
class lb_base_vseq extends uvm_sequence;

  `uvm_object_utils(lb_base_vseq)
  `uvm_declare_p_sequencer(lb_vsequencer)

  function new(string name = "lb_base_vseq");
    super.new(name);
  endfunction

  // 入力画像と出力先を用意してからコマンドを流し、完了を待つ
  protected task run_cmd(cmd_item c);
    cmd_single_seq s;
    int unsigned   lb;
    int unsigned   ib;
    int unsigned   ob;
    bit [63:0]     hi;
    lb = lb_line_bytes(c.w);
    ib = lb_beats(lb, IN_STRB_W);
    ob = lb_beats(lb, OUT_STRB_W);
    // 入力画像 (ビートの端数やコンテナの余りビットも乱数にしておく)
    for( int unsigned y=0; y<c.h; y++ ) begin
      p_sequencer.src_mem.fill_random(c.src + (64'(y) * 64'(c.sstr)), ib*IN_STRB_W);
    end
    // 出力先 (ガード領域を含めてパターンで埋める)
    hi = c.dst + (64'((c.h>0) ? (c.h-1) : 0) * 64'(c.dstr)) + 64'(ob*OUT_STRB_W) + 64'(GUARD);
    p_sequencer.dst_mem.fill_pattern(c.dst - 64'(GUARD), hi);
    s        = cmd_single_seq::type_id::create("s");
    s.m_item = c;
    s.start(p_sequencer.cmd_sqr, this);
    `uvm_info("VSEQ", $sformatf("%s [rd: %s] [wr: %s] -> err_flags=%b"
                               , c.convert2string(), p_sequencer.rd_cfg.convert2string(), p_sequencer.wr_cfg.convert2string(), c.err_flags), UVM_MEDIUM)
  endtask

  // 指定したフレーム (stride を省くとライン長をバス幅に切り上げた値)
  protected task frame_fixed(bit [63:0] src, bit [63:0] dst, int unsigned w, int unsigned h
                            , int unsigned sstr = 0, int unsigned dstr = 0);
    cmd_item c;
    c = cmd_item::type_id::create("c");
    c.set_fixed(src, dst, w, h, sstr, dstr);
    run_cmd(c);
  endtask

  // 制約付きランダムなフレームを n 本
  protected task frame_rand(int unsigned n);
    cmd_item c;
    bit      ok;
    for( int unsigned i=0; i<n; i++ ) begin
      c  = cmd_item::type_id::create($sformatf("c%0d", i));
      ok = c.randomize();
      if( !ok ) begin
        `uvm_error("RAND", "cmd_item randomize failed")
      end
      run_cmd(c);
    end
  endtask

  // ランダムなフレームの 1 ビートに SLVERR を仕込む
  //   side=0 : 入力側 (Read) / side=1 : 出力側 (Write)
  protected task frame_err(bit side);
    cmd_item     c;
    bit          ok;
    int unsigned lb;
    int unsigned y;
    int unsigned k;
    bit [63:0]   a;
    c  = cmd_item::type_id::create("e");
    ok = c.randomize();
    if( !ok ) begin
      `uvm_error("RAND", "cmd_item randomize failed")
    end
    lb = lb_line_bytes(c.w);
    y  = $urandom_range(c.h-1, 0);
    if( !side ) begin
      k = $urandom_range(lb_beats(lb, IN_STRB_W)-1, 0);
      a = c.src + (64'(y) * 64'(c.sstr)) + (64'(k) * 64'(IN_STRB_W));
      p_sequencer.rd_cfg.err_lo = a;
      p_sequencer.rd_cfg.err_hi = a + 64'(IN_STRB_W) - 64'd1;
    end else begin
      k = $urandom_range(lb_beats(lb, OUT_STRB_W)-1, 0);
      a = c.dst + (64'(y) * 64'(c.dstr)) + (64'(k) * 64'(OUT_STRB_W));
      p_sequencer.wr_cfg.err_lo = a;
      p_sequencer.wr_cfg.err_hi = a + 64'(OUT_STRB_W) - 64'd1;
    end
    run_cmd(c);
    p_sequencer.rd_cfg.clear_err();
    p_sequencer.wr_cfg.clear_err();
  endtask

  // DUT が断るべきコマンド / 何もしないコマンド
  //   kind 0: 幅 0 / 1: 高さ 0 / 2: 入力アドレス非アライン / 3: 出力 stride 非アライン /
  //        4: 幅が MAX_LINE_PIXELS 超 (cmd_width のビット幅で表せる構成だけ)
  protected task frame_bad(int unsigned kind);
    cmd_item     c;
    bit          ok;
    c  = cmd_item::type_id::create("b");
    ok = c.randomize();
    if( !ok ) begin
      `uvm_error("RAND", "cmd_item randomize failed")
    end
    case( kind )
      0 : begin
        c.w = 0;
      end
      1 : begin
        c.h = 0;
      end
      2 : begin
        c.src = c.src + 64'd1;
      end
      3 : begin
        c.dstr = c.dstr + 1;
      end
      default : begin
        if( ((1<<XW)-1)>MAX_LINE_PIXELS ) begin
          c.w = MAX_LINE_PIXELS + 1;
        end else begin
          c.dst = c.dst + 64'd1;
        end
      end
    endcase
    run_cmd(c);
  endtask

  protected function void set_slave(int unsigned rd_stall, bit rd_rwv, int unsigned wr_stall, bit wr_rwv);
    p_sequencer.rd_cfg.stall_pct        = rd_stall;
    p_sequencer.rd_cfg.ready_wait_valid = rd_rwv;
    p_sequencer.wr_cfg.stall_pct        = wr_stall;
    p_sequencer.wr_cfg.ready_wait_valid = wr_rwv;
  endfunction

endclass

//=============================================================================
// smoke
//=============================================================================
class lb_smoke_vseq extends lb_base_vseq;

  `uvm_object_utils(lb_smoke_vseq)

  function new(string name = "lb_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    int unsigned w_mid;
    int unsigned lb;
    w_mid = (MAX_LINE_PIXELS>=40) ? 37 : ((MAX_LINE_PIXELS+1)/2);

    `uvm_info("VSEQ", "phase1 : width x height corners", UVM_LOW)
    //          src            dst            w                h
    frame_fixed(64'h0001_0000, 64'h0001_0000, 1,               1);
    frame_fixed(64'h0002_0000, 64'h0002_0000, 1,               NUM_LINES);
    frame_fixed(64'h0003_0000, 64'h0003_0000, 1,               NUM_LINES+1);
    frame_fixed(64'h0004_0000, 64'h0004_0000, w_mid,           1);
    frame_fixed(64'h0005_0000, 64'h0005_0000, w_mid,           NUM_LINES);
    frame_fixed(64'h0006_0000, 64'h0006_0000, w_mid,           MAX_H);
    frame_fixed(64'h0007_0000, 64'h0007_0000, MAX_LINE_PIXELS, 1);
    frame_fixed(64'h0008_0000, 64'h0008_0000, MAX_LINE_PIXELS, NUM_LINES);
    frame_fixed(64'h0009_0000, 64'h0009_0000, MAX_LINE_PIXELS, NUM_LINES+1);

    `uvm_info("VSEQ", "phase2 : 4KB crossing on both sides, stride larger than the line", UVM_LOW)
    lb = lb_line_bytes(MAX_LINE_PIXELS);
    frame_fixed(64'h000A_1000 - 64'(2*IN_STRB_W), 64'h000A_1000 - 64'(3*OUT_STRB_W), MAX_LINE_PIXELS, 3
               , lb_align_up(lb, IN_STRB_W) + IN_STRB_W, lb_align_up(lb, OUT_STRB_W) + (2*OUT_STRB_W));

    `uvm_info("VSEQ", "phase3 : SLVERR on the read side, then on the write side", UVM_LOW)
    frame_err(1'b0);
    frame_err(1'b1);

    `uvm_info("VSEQ", "phase4 : rejected / empty commands", UVM_LOW)
    for( int unsigned k=0; k<5; k++ ) begin
      frame_bad(k);
    end
    frame_fixed(64'h000B_0000, 64'h000B_0000, w_mid, 2);

    `uvm_info("VSEQ", "phase5 : 50% stall + READY waits for VALID on both sides", UVM_LOW)
    set_slave(50, 1'b1, 50, 1'b1);
    frame_fixed(64'h000C_0FC0, 64'h000C_0F80, MAX_LINE_PIXELS, NUM_LINES+2);
    set_slave(0, 1'b0, 0, 1'b0);

    `uvm_info("VSEQ", "phase6 : slow output (scratchpad fills up)", UVM_LOW)
    set_slave(0, 1'b0, 90, 1'b0);
    frame_fixed(64'h000D_0000, 64'h000D_0000, MAX_LINE_PIXELS, MAX_H);
    set_slave(0, 1'b0, 0, 1'b0);
  endtask

endclass

//=============================================================================
// rand
//=============================================================================
class lb_rand_vseq extends lb_base_vseq;

  `uvm_object_utils(lb_rand_vseq)

  int unsigned m_num = 6;

  function new(string name = "lb_rand_vseq");
    super.new(name);
  endfunction

  task body();
    // {入力側ストール率, 出力側ストール率, READY が VALID を待つ}
    int unsigned rd_tbl[9] = '{0, 70, 0, 40, 60, 30, 0, 70, 20};
    int unsigned wr_tbl[9] = '{0, 0, 80, 40, 60, 0, 30, 20, 70};
    bit          rwv_tbl[9] = '{1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0};
    for( int unsigned p=0; p<9; p++ ) begin
      `uvm_info("VSEQ", $sformatf("phase%0d : %0d random frames, stall rd=%0d%% wr=%0d%% ready_wait_valid=%0d"
                                 , p+1, m_num, rd_tbl[p], wr_tbl[p], rwv_tbl[p]), UVM_LOW)
      set_slave(rd_tbl[p], rwv_tbl[p], wr_tbl[p], rwv_tbl[p]);
      frame_rand(m_num);
    end

    `uvm_info("VSEQ", "phase10 : SLVERR injection", UVM_LOW)
    set_slave(20, 1'b0, 20, 1'b0);
    for( int unsigned i=0; i<4; i++ ) begin
      frame_err(i[0]);
    end

    `uvm_info("VSEQ", "phase11 : rejected / empty commands", UVM_LOW)
    for( int unsigned k=0; k<5; k++ ) begin
      frame_bad(k);
    end
    set_slave(0, 1'b0, 0, 1'b0);
    frame_rand(1);
  endtask

endclass

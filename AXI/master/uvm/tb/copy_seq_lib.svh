//=============================================================================
// copy_seq_lib.svh
//-----------------------------------------------------------------------------
//  cmd_single_seq  : コマンド 1 本を cmd sequencer に流す
//  copy_base_vseq  : 仮想シーケンスの共通処理
//                    src へのデータ準備 (共有メモリへバックドア書き込み) ->
//                    コマンド発行 -> done 待ち
//  copy_smoke_vseq : 代表パターン (1 バースト / 4KB 跨ぎ / 長尺 / 1 ビート /
//                    SLVERR / ストール + READY の VALID 待ち)
//  copy_rand_vseq  : ランダムコマンドを、スレーブの振る舞いを変えながら流す
//                    (ストール無し -> 50% -> 30% + VALID 待ち -> SLVERR 注入)
//
//  仮想シーケンスはコマンド sequencer の制御と、スレーブ設定 (cfg) の切り替えを
//  まとめて受け持つ。cfg はコマンドが完了してから変える
//  (scoreboard / coverage は受付時の cfg を記録している)。
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
class copy_base_vseq extends uvm_sequence;

  `uvm_object_utils(copy_base_vseq)
  `uvm_declare_p_sequencer(copy_vsequencer)

  function new(string name = "copy_base_vseq");
    super.new(name);
  endfunction

  // src にランダムデータを置いてからコマンドを流し、完了を待つ
  protected task run_cmd(cmd_item c);
    cmd_single_seq s;
    p_sequencer.mem.fill_random(c.src, c.len);
    s        = cmd_single_seq::type_id::create("s");
    s.m_item = c;
    s.start(p_sequencer.cmd_sqr, this);
    `uvm_info("VSEQ", $sformatf("%s [%s] -> done_err=%0d"
                               , c.convert2string(), p_sequencer.cfg.convert2string(), c.done_err), UVM_MEDIUM)
  endtask

  // 指定コマンド
  protected task copy_cmd(bit [ADDR_W-1:0] src, bit [ADDR_W-1:0] dst, int unsigned len);
    cmd_item c;
    c     = cmd_item::type_id::create("c");
    c.src = src;
    c.dst = dst;
    c.len = len;
    run_cmd(c);
  endtask

  // 制約付きランダムなコマンドを n 本
  protected task copy_rand(int unsigned n);
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

  // src か dst のランダムな 1 ビートに SLVERR を仕込んでコピーする
  protected task copy_with_err(int unsigned n);
    cmd_item         c;
    bit              ok;
    int unsigned     k;
    bit [ADDR_W-1:0] a;
    for( int unsigned i=0; i<n; i++ ) begin
      c  = cmd_item::type_id::create($sformatf("e%0d", i));
      ok = c.randomize();
      if( !ok ) begin
        `uvm_error("RAND", "cmd_item randomize failed")
      end
      k = $urandom_range(c.len-1, 0);
      if( $urandom_range(1,0)==0 ) begin
        a = c.src + ADDR_W'(k*STRB_W);
      end else begin
        a = c.dst + ADDR_W'(k*STRB_W);
      end
      p_sequencer.cfg.err_lo = a;
      p_sequencer.cfg.err_hi = a + ADDR_W'(STRB_W-1);
      run_cmd(c);
      p_sequencer.cfg.clear_err();
    end
  endtask

endclass

//=============================================================================
// smoke
//=============================================================================
class copy_smoke_vseq extends copy_base_vseq;

  `uvm_object_utils(copy_smoke_vseq)

  function new(string name = "copy_smoke_vseq");
    super.new(name);
  endfunction

  task body();
    `uvm_info("VSEQ", "phase1 : directed copies", UVM_LOW)
    //    src           dst           len
    copy_cmd(32'h0000_1000, 32'h0010_0000, 16);    // 1 バースト
    copy_cmd(32'h0000_2F80, 32'h0010_4FC8, 100);   // src / dst とも 4KB 跨ぎ (分割位置が違う)
    copy_cmd(32'h0001_0000, 32'h0011_0000, 300);   // MAX_BURST の連続
    copy_cmd(32'h0002_0000, 32'h0012_0008, 1);     // 1 ビート

    `uvm_info("VSEQ", "phase2 : SLVERR on dst beat 8", UVM_LOW)
    p_sequencer.cfg.err_lo = 32'h0013_0040;
    p_sequencer.cfg.err_hi = 32'h0013_0047;
    copy_cmd(32'h0003_0000, 32'h0013_0000, 32);
    p_sequencer.cfg.clear_err();

    `uvm_info("VSEQ", "phase3 : 50% stall + READY waits for VALID", UVM_LOW)
    p_sequencer.cfg.stall_pct        = 50;
    p_sequencer.cfg.ready_wait_valid = 1'b1;
    copy_cmd(32'h0004_0FC0, 32'h0014_0F80, 64);
    p_sequencer.cfg.stall_pct        = 0;
    p_sequencer.cfg.ready_wait_valid = 1'b0;
  endtask

endclass

//=============================================================================
// rand
//=============================================================================
class copy_rand_vseq extends copy_base_vseq;

  `uvm_object_utils(copy_rand_vseq)

  int unsigned m_num = 10;

  function new(string name = "copy_rand_vseq");
    super.new(name);
  endfunction

  task body();
    `uvm_info("VSEQ", $sformatf("phase1 : %0d random copies, no stall", m_num), UVM_LOW)
    p_sequencer.cfg.stall_pct = 0;
    copy_rand(m_num);

    `uvm_info("VSEQ", $sformatf("phase2 : %0d random copies, 50%% stall", m_num), UVM_LOW)
    p_sequencer.cfg.stall_pct = 50;
    copy_rand(m_num);

    `uvm_info("VSEQ", $sformatf("phase3 : %0d random copies, 30%% stall + READY waits for VALID", m_num), UVM_LOW)
    p_sequencer.cfg.stall_pct        = 30;
    p_sequencer.cfg.ready_wait_valid = 1'b1;
    copy_rand(m_num);
    p_sequencer.cfg.ready_wait_valid = 1'b0;

    `uvm_info("VSEQ", "phase4 : SLVERR injection", UVM_LOW)
    p_sequencer.cfg.stall_pct = 20;
    copy_with_err(4);
    p_sequencer.cfg.stall_pct = 0;
  endtask

endclass

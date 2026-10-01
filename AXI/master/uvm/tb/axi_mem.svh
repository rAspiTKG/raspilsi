//=============================================================================
// axi_mem.svh
//-----------------------------------------------------------------------------
//  axi_mem     : スレーブ応答 agent / scoreboard / 仮想シーケンスで共有する
//                バイト単位のメモリモデル
//  axi_slv_cfg : スレーブ応答の振る舞い (ストール / READY の出し方 / エラー注入)
//                仮想シーケンスから実行中に書き換える
//=============================================================================

class axi_mem extends uvm_object;

  `uvm_object_utils(axi_mem)

  protected bit [7:0] m_mem[bit [ADDR_W-1:0]];

  function new(string name = "axi_mem");
    super.new(name);
  endfunction

  // バス幅 1 ワード読み出し (未書き込みバイトは 0)
  function bit [DATA_W-1:0] read_word(bit [ADDR_W-1:0] a);
    bit [ADDR_W-1:0] base;
    bit [DATA_W-1:0] d;
    base = {a[ADDR_W-1:ADDR_LSB], {ADDR_LSB{1'b0}}};
    d    = '0;
    for( int b=0; b<STRB_W; b++ ) begin
      if( m_mem.exists(base+ADDR_W'(b)) ) begin
        d[8*b+:8] = m_mem[base+ADDR_W'(b)];
      end
    end
    return d;
  endfunction

  // バス幅 1 ワード書き込み (strb が立ったバイトのみ)
  function void write_word(bit [ADDR_W-1:0] a, bit [DATA_W-1:0] d, bit [STRB_W-1:0] strb = STRB_ALL);
    bit [ADDR_W-1:0] base;
    base = {a[ADDR_W-1:ADDR_LSB], {ADDR_LSB{1'b0}}};
    for( int b=0; b<STRB_W; b++ ) begin
      if( strb[b] ) begin
        m_mem[base+ADDR_W'(b)] = d[8*b+:8];
      end
    end
  endfunction

  // a から beats ワードをランダムデータで埋める
  function void fill_random(bit [ADDR_W-1:0] a, int unsigned beats);
    localparam int NW = (DATA_W + 31) / 32;
    bit [NW*32-1:0] wide;
    for( int unsigned i=0; i<beats; i++ ) begin
      for( int w=0; w<NW; w++ ) begin
        wide[32*w+:32] = $urandom();
      end
      write_word(a+ADDR_W'(i*STRB_W), wide[DATA_W-1:0]);
    end
  endfunction

endclass

class axi_slv_cfg extends uvm_object;

  `uvm_object_utils(axi_slv_cfg)

  int unsigned     stall_pct        = 0;      // READY を下げる / VALID を遅らせる確率 [%]
  bit              ready_wait_valid = 1'b0;   // READY を VALID を見てから立てる
  bit [ADDR_W-1:0] err_lo           = '1;     // SLVERR を返す範囲 (err_lo > err_hi で無効)
  bit [ADDR_W-1:0] err_hi           = '0;

  function new(string name = "axi_slv_cfg");
    super.new(name);
  endfunction

  function bit stall();
    return ($urandom_range(99,0)<stall_pct);
  endfunction

  // VALID を出すまでの待ちサイクル数
  function int unsigned delay();
    if( stall() ) begin
      return $urandom_range(4,1);
    end
    return 0;
  endfunction

  // 次サイクルの READY
  //   通常            : VALID と無関係にランダム
  //   ready_wait_valid: VALID が立っていて、このサイクルで握手していなければ立てる
  //   (スレーブが VALID を待つのは AXI で許されている。マスタが READY を待って
  //    VALID を出す実装だとこのモードでデッドロックする)
  function bit ready_next(bit valid_now, bit hs_now);
    if( ready_wait_valid ) begin
      return valid_now&&!hs_now&&!stall();
    end
    return !stall();
  endfunction

  function bit in_err(bit [ADDR_W-1:0] a);
    return (err_lo<=err_hi)&&(a>=err_lo)&&(a<=err_hi);
  endfunction

  // [a, a + beats*STRB_W) がエラー範囲と重なるか
  function bit range_hits_err(bit [ADDR_W-1:0] a, int unsigned beats);
    bit [ADDR_W-1:0] last;
    if( (err_lo>err_hi)||(beats==0) ) begin
      return 1'b0;
    end
    last = a + ADDR_W'(beats*STRB_W) - ADDR_W'(1);
    return (a<=err_hi)&&(last>=err_lo);
  endfunction

  function void clear_err();
    err_lo = '1;
    err_hi = '0;
  endfunction

  function string convert2string();
    if( err_lo<=err_hi ) begin
      return $sformatf("stall=%0d%% ready_wait_valid=%0d err=[%08h:%08h]", stall_pct, ready_wait_valid, err_lo, err_hi);
    end
    return $sformatf("stall=%0d%% ready_wait_valid=%0d err=off", stall_pct, ready_wait_valid);
  endfunction

endclass

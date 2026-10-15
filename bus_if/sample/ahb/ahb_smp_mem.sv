//=============================================================================
// ahb_smp_mem.sv
//-----------------------------------------------------------------------------
//  ahb_if のサンプル : AHB サブオーディネート + メモリ (合成可能)。
//    - HSEL=1、HREADY=1 のエッジで NONSEQ / SEQ のアドレスフェーズを受け付ける
//    - 転送ごとに WAIT サイクル待たせてから完了する (HREADYOUT=0)。IDLE / BUSY は待ち無しの OKAY
//    - 書き込みは HSIZE と HADDR から決まるバイトレーンだけ (HWSTRB は見ない)。応答は常に OKAY
//    - アドレスは下位 (log2(MEM_WORDS) + log2(DATA_WIDTH/8)) ビットだけを使う
//
//  ポートは ahb_if.sub 1 本だけ。
//=============================================================================
`timescale 1ns / 1ps

module ahb_smp_mem #(
  parameter int unsigned DATA_WIDTH = 32
 ,parameter int unsigned MEM_WORDS  = 256    // 2 のべき乗
 ,parameter int unsigned WAIT       = 0
) (
  input logic hclk
 ,input logic hresetn
 ,ahb_if.sub  s_ahb
);

  // つないだ ahb_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( $bits(s_ahb.hwdata)!=DATA_WIDTH ) begin : g_chk_if
    $error("ahb_smp_mem : DATA_WIDTH differs from the ahb_if connected to s_ahb");
  end

  localparam int unsigned SB   = DATA_WIDTH/8;
  localparam int unsigned OFSW = $clog2(SB);
  localparam int unsigned MAW  = $clog2(MEM_WORDS);
  localparam int unsigned WW   = (WAIT<1) ? 1 : $clog2(WAIT+1);

  logic                  dp_v_q;     // データフェーズの転送がある
  logic                  dp_wr_q;
  logic [MAW-1:0]        dp_word_q;  // ワードの番号
  logic [SB-1:0]         dp_be_q;    // バイトレーン
  logic [WW-1:0]         wcnt_q;     // 待ったサイクル数
  logic                  ready;
  logic [DATA_WIDTH-1:0] mem [MEM_WORDS];

  // HSIZE と HADDR から決まるバイトレーン
  function automatic logic [SB-1:0] lanes(input logic [2:0] size, input logic [OFSW-1:0] a);
    logic [SB-1:0] m;
    m = SB'((1<<(1<<size))-1);
    return m<<(a&~OFSW'((1<<size)-1));
  endfunction

  assign ready = !dp_v_q||(wcnt_q==WW'(WAIT));

  always @(posedge hclk or negedge hresetn) begin
    if( !hresetn ) begin
      dp_v_q    <= 1'b0;
      dp_wr_q   <= 1'b0;
      dp_word_q <= '0;
      dp_be_q   <= '0;
      wcnt_q    <= '0;
    end else begin
      if( s_ahb.hready ) begin
        dp_v_q    <= s_ahb.hsel&&s_ahb.htrans[1];
        dp_wr_q   <= s_ahb.hwrite;
        dp_word_q <= s_ahb.haddr[OFSW+:MAW];
        dp_be_q   <= lanes(s_ahb.hsize, s_ahb.haddr[OFSW-1:0]);
        wcnt_q    <= '0;
      end else if( dp_v_q&&!ready ) begin
        wcnt_q <= wcnt_q+1'b1;
      end
    end
  end

  // 書き込み (データフェーズの最後のサイクル)
  always @(posedge hclk) begin
    if( dp_v_q&&dp_wr_q&&ready ) begin
      for( int k=0; k<SB; k++ ) begin
        if( dp_be_q[k] ) begin
          mem[dp_word_q][8*k+:8] <= s_ahb.hwdata[8*k+:8];
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // AHB の出力
  //---------------------------------------------------------------------------
  assign s_ahb.hreadyout = ready;
  assign s_ahb.hresp     = 1'b0;
  assign s_ahb.hrdata    = mem[dp_word_q];
  assign s_ahb.hexokay   = 1'b0;

  // 使わない入力
  wire unused_ctrl = &{1'b0, s_ahb.hburst, s_ahb.hprot, s_ahb.hnonsec, s_ahb.hexcl, s_ahb.hmaster, s_ahb.hmastlock, s_ahb.htrans[0]};
  wire unused_data = &{1'b0, s_ahb.hwstrb, (s_ahb.haddr>>(OFSW+MAW))};

endmodule

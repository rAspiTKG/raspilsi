// ============================================================================
// BAYER2RGB_SRAM_1R1W : 1R1W SRAMのラッパ(論理合成用、ASAP7)
//   rtl/BAYER2RGB_SRAM_1R1W.sv(振る舞いモデルを呼ぶ)の代わりに読む。
//   大きさ(DEPTH × DW)ごとに、tools/gen_sram_macro.py で作った仮マクロ
//   b2r_sram1r1w_<DEPTH>x<DW> を置く。PPC=1/2/4/8 で使う大きさに対応している。
//   読み出しレイテンシ1、同一アドレスの同時読み書きはしない(rtl版と同じ約束)。
// ============================================================================
module BAYER2RGB_SRAM_1R1W #(
  parameter int DEPTH = 480
 ,parameter int DW    = 112
 ,parameter int AW    = $clog2(DEPTH)
) (
  input  logic          clk
 ,input  logic          i_ren
 ,input  logic [AW-1:0] i_raddr
 ,output logic [DW-1:0] o_rdata
 ,input  logic          i_wen
 ,input  logic [AW-1:0] i_waddr
 ,input  logic [DW-1:0] i_wdata
);

  // ラインバッファ(3840/PPC ワード × PPC×14 ビット)
  if( (DEPTH==480)&&(DW==112) ) begin : g_m
    b2r_sram1r1w_480x112 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  end else if( (DEPTH==960)&&(DW==56) ) begin : g_m
    b2r_sram1r1w_960x56 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  end else if( (DEPTH==1920)&&(DW==28) ) begin : g_m
    b2r_sram1r1w_1920x28 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  end else if( (DEPTH==3840)&&(DW==14) ) begin : g_m
    b2r_sram1r1w_3840x14 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  // 読み出しバッファ(64 × 128)と書き込みバッファ(64 × 144)
  end else if( (DEPTH==64)&&(DW==128) ) begin : g_m
    b2r_sram1r1w_64x128 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  end else if( (DEPTH==64)&&(DW==144) ) begin : g_m
    b2r_sram1r1w_64x144 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  // 出力FIFO(32 × (PPC×24+3))
  end else if( (DEPTH==32)&&(DW==195) ) begin : g_m
    b2r_sram1r1w_32x195 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  end else if( (DEPTH==32)&&(DW==99) ) begin : g_m
    b2r_sram1r1w_32x99 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  end else if( (DEPTH==32)&&(DW==51) ) begin : g_m
    b2r_sram1r1w_32x51 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  end else if( (DEPTH==32)&&(DW==27) ) begin : g_m
    b2r_sram1r1w_32x27 u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  end else begin : g_m
    // 対応していない大きさ(このモジュールはないので、エラボレーションでエラーになる)
    b2r_sram1r1w_unsupported_size u_mem (
      .clk   (clk)
     ,.ren   (i_ren)
     ,.raddr (i_raddr)
     ,.rdata (o_rdata)
     ,.wen   (i_wen)
     ,.waddr (i_waddr)
     ,.wdata (i_wdata)
    );
  end

endmodule

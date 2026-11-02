// ============================================================================
// BAYER2RGB_SRAM_1R1W : 1R1W SRAMのラッパ(論理合成用、Foundry のプロセス。雛形)
//   rtl/BAYER2RGB_SRAM_1R1W.sv(振る舞いモデルを呼ぶ)の代わりに読む。
//   大きさ(DEPTH × DW)ごとに、メモリコンパイラで作った 2ポート(読み1・書き1、
//   同じクロック)の SRAM を置く。
//
//   ★ マクロ名 B2R_MEM_<DEPTH>X<DW> と端子名は記入例。メモリコンパイラの出力に合わせて
//     書き換える。ここでは、よくある形として次を仮定している
//       CLK    クロック(読み書きで共通)
//       REB    読み出しの有効(L で有効)   RA  読み出しアドレス   Q  読み出しデータ
//       WEB    書き込みの有効(L で有効)   WA  書き込みアドレス   D  書き込みデータ
//     テスト・電源制御・冗長などの端子は、PDK の推奨どおりにつなぐ(ここでは省略)
//   約束(rtl版と同じ): 読み出しレイテンシ1、i_ren=0 のとき o_rdata は前の値を保持、
//                      同一アドレスの同時読み書きはしない
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

  logic s_reb;   // 読み出しの有効(L で有効)
  logic s_web;   // 書き込みの有効(L で有効)

  assign s_reb = !i_ren;
  assign s_web = !i_wen;

  // ラインバッファ(3840/PPC ワード × PPC×14 ビット)
  if( (DEPTH==480)&&(DW==112) ) begin : g_m
    B2R_MEM_480X112 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  end else if( (DEPTH==960)&&(DW==56) ) begin : g_m
    B2R_MEM_960X56 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  end else if( (DEPTH==1920)&&(DW==28) ) begin : g_m
    B2R_MEM_1920X28 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  end else if( (DEPTH==3840)&&(DW==14) ) begin : g_m
    B2R_MEM_3840X14 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  // 読み出しバッファ(64 × 128)と書き込みバッファ(64 × 144)
  end else if( (DEPTH==64)&&(DW==128) ) begin : g_m
    B2R_MEM_64X128 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  end else if( (DEPTH==64)&&(DW==144) ) begin : g_m
    B2R_MEM_64X144 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  // 出力FIFO(32 × (PPC×24+3))
  end else if( (DEPTH==32)&&(DW==195) ) begin : g_m
    B2R_MEM_32X195 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  end else if( (DEPTH==32)&&(DW==99) ) begin : g_m
    B2R_MEM_32X99 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  end else if( (DEPTH==32)&&(DW==51) ) begin : g_m
    B2R_MEM_32X51 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  end else if( (DEPTH==32)&&(DW==27) ) begin : g_m
    B2R_MEM_32X27 u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  end else begin : g_m
    // 対応していない大きさ(このモジュールはないので、エラボレーションでエラーになる)
    B2R_MEM_UNSUPPORTED_SIZE u_mem (
      .CLK (clk)
     ,.REB (s_reb)
     ,.RA  (i_raddr)
     ,.Q   (o_rdata)
     ,.WEB (s_web)
     ,.WA  (i_waddr)
     ,.D   (i_wdata)
    );
  end

endmodule

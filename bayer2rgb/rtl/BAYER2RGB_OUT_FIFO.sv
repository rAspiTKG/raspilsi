// ============================================================================
// BAYER2RGB_OUT_FIFO : COREの出力FIFO(32段、SRAM + 先読み2段)
//   書き込み側は止められない(IN_CTRLのクレジット制御であふれないことを保証する)
//   o_cnt は先読みバッファと読み出し中の分を含む格納数
// ============================================================================
module BAYER2RGB_OUT_FIFO
  import BAYER2RGB_PKG::*;
(
  input  logic                clk
 ,input  logic                rst_n
 ,input  logic                i_clr
 ,input  logic                i_vld
 ,input  obeat_t              i_data
 ,output logic [OFIFO_CW-1:0] o_cnt
 ,BAYER2RGB_VBD_IF.src        rgb      // COREの出力(obeat_t)
);

  logic s_full;

  BAYER2RGB_SFIFO #(
    .DEPTH    (OFIFO_DEPTH)
   ,.DW       (OUT_DATA_W)
   ,.USE_SRAM (1'b1)
   ,.CW       (OFIFO_CW)
  ) u_fifo (
    .clk     (clk)
   ,.rst_n   (rst_n)
   ,.i_clr   (i_clr)
   ,.i_wvld  (i_vld)
   ,.o_wbusy (s_full)
   ,.i_wdata (i_data)
   ,.o_rvld  (rgb.vld)
   ,.i_rbusy (rgb.busy)
   ,.o_rdata (rgb.data)
   ,.o_cnt   (o_cnt)
  );

`ifndef SYNTHESIS
  always @(posedge clk) begin
    if( rst_n&&i_vld&&s_full&&!i_clr ) begin
      $error("%m: 出力FIFOがあふれた");
    end
  end
`endif

endmodule

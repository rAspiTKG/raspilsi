//=============================================================================
// strm_smp_sink.sv
//-----------------------------------------------------------------------------
//  strm_if のサンプル : 受信側 (合成可能)。
//    - TREADY を LFSR で決めた不規則なパターンで出す (レジスタ出力)
//    - 受け取ったビートが strm_smp_src と同じ順 (TDATA / TSTRB / TID / TADDR) で、TLAST が
//      NWORD ビート目だけに立つことを確かめる。TLAST を受け取ると done (1 サイクル)。err は合わないと 1
//
//  ポートは strm_if.snk 1 本だけ。
//=============================================================================
`timescale 1ns / 1ps

module strm_smp_sink #(
  parameter int unsigned     DATA_WIDTH = 64
 ,parameter int unsigned     ID_WIDTH   = 4
 ,parameter int unsigned     ADDR_WIDTH = 32
 ,parameter int unsigned     NWORD      = 16
 ,parameter int unsigned     TID        = 3
 ,parameter longint unsigned BASE_ADDR  = 64'h0000_1000
 ,parameter logic [7:0]      SEED       = 8'hA5
) (
  input  logic clk
 ,input  logic rst_n
 ,output logic done
 ,output logic err
 ,strm_if.snk  s_strm
);

  // つないだ strm_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(s_strm.tdata)!=DATA_WIDTH)||($bits(s_strm.tid)!=ID_WIDTH)||($bits(s_strm.taddr)!=ADDR_WIDTH) ) begin : g_chk_if
    $error("strm_smp_sink : DATA_WIDTH / ID_WIDTH / ADDR_WIDTH differ from the strm_if connected to s_strm");
  end

  localparam int unsigned SB = DATA_WIDTH/8;

  logic [7:0] lfsr_q;
  logic [7:0] cnt_q;
  logic       done_q;
  logic       err_q;
  logic       take;

  function automatic logic [DATA_WIDTH-1:0] pat(input logic [7:0] i);
    logic [DATA_WIDTH-1:0] d;
    for( int k=0; k<SB; k++ ) begin
      d[8*k+:8] = (i*8'(SB)+8'(k))^8'h69;
    end
    return d;
  endfunction

  assign take = s_strm.tvalid&&s_strm.tready;

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      lfsr_q <= SEED;
      cnt_q  <= '0;
      done_q <= 1'b0;
      err_q  <= 1'b0;
    end else begin
      done_q <= 1'b0;
      lfsr_q <= {lfsr_q[6:0], lfsr_q[7]^lfsr_q[5]^lfsr_q[4]^lfsr_q[3]};
      if( take ) begin
        if( (s_strm.tdata!=pat(cnt_q))||(s_strm.tstrb!={SB{1'b1}})||(s_strm.tlast!=(cnt_q==8'(NWORD-1))) ) begin
          err_q <= 1'b1;
        end
        if( (s_strm.tid!=ID_WIDTH'(TID))||(s_strm.taddr!=ADDR_WIDTH'(BASE_ADDR+64'(cnt_q)*SB)) ) begin
          err_q <= 1'b1;
        end
        if( s_strm.tlast ) begin
          cnt_q  <= '0;
          done_q <= 1'b1;
        end else begin
          cnt_q <= cnt_q+8'd1;
        end
      end
    end
  end

  // 4 サイクルに 1 回くらい TREADY=0 にする
  assign s_strm.tready = (lfsr_q[1:0]!=2'b00);

  assign done = done_q;
  assign err  = err_q;

endmodule

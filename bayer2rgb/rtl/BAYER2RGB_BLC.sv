// ============================================================================
// BAYER2RGB_BLC : 黒レベル補正(レイテンシ1)
//   q = max(p - blc[色位置], 0)     色位置 0:R 1:Gr 2:Gb 3:B
//   blc_en=0 のときは p をそのまま出す
// ============================================================================
module BAYER2RGB_BLC
  import BAYER2RGB_PKG::*;
(
  input  logic clk
 ,input  logic rst_n
 ,input  logic i_clr
 ,input  cfg_t i_cfg
 ,input  stp_t i_stp
 ,output stp_t o_stp
);

  logic                        r_vld;
  stp_t                        r_stp;
  logic [PPC-1:0][1:0]         s_site;
  logic [PPC-1:0][IN_BITS-1:0] s_lvl;
  logic [PPC-1:0][IN_BITS-1:0] s_q;

  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      s_site[i] = f_site(i_cfg.phase, i_stp.line[0], f_xpar(i_stp.col[0], 1'(i)));
      // 色位置で黒レベルを選ぶ(添字が変数の配列読み出しにしない)
      case( s_site[i] )
        2'd0 : begin
          s_lvl[i] = i_cfg.blc[0];
        end
        2'd1 : begin
          s_lvl[i] = i_cfg.blc[1];
        end
        2'd2 : begin
          s_lvl[i] = i_cfg.blc[2];
        end
        default : begin
          s_lvl[i] = i_cfg.blc[3];
        end
      endcase
      if( !i_cfg.blc_en ) begin
        s_q[i] = i_stp.pix[i];
      end else if( i_stp.pix[i]>s_lvl[i] ) begin
        s_q[i] = i_stp.pix[i]-s_lvl[i];
      end else begin
        s_q[i] = '0;
      end
    end
  end

  // 制御(リセットあり)
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_vld <= 1'b0;
    end else begin
      r_vld <= i_stp.vld&&!i_clr;
    end
  end

  // データ(リセットなし)
  always_ff @(posedge clk) begin
    if( i_stp.vld ) begin
      r_stp     <= i_stp;
      r_stp.pix <= s_q;
    end
  end

  always_comb begin
    o_stp     = r_stp;
    o_stp.vld = r_vld;
  end

endmodule

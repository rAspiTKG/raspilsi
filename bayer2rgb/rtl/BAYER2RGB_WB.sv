// ============================================================================
// BAYER2RGB_WB : ホワイトバランス(レイテンシ2)
//   q = min(16383, (p × g[色位置] + 2048) >> 12)     g は U4.12(0x1000 = 1.0倍)
//   wb_en=0 のときは g = 0x1000 として計算する(p をそのまま出すのと同じ)
//   1段目: 乗算  2段目: 丸め・クリップ
// ============================================================================
module BAYER2RGB_WB
  import BAYER2RGB_PKG::*;
(
  input  logic clk
 ,input  logic rst_n
 ,input  logic i_clr
 ,input  cfg_t i_cfg
 ,input  stp_t i_stp
 ,output stp_t o_stp
);

  localparam int MW = IN_BITS+WBG_W;   // 積のビット幅(30)

  logic                    r_vld1;
  stp_t                    r_stp1;
  logic [PPC-1:0][MW-1:0]  r_mul1;
  logic                    r_vld2;
  stp_t                    r_stp2;
  logic [PPC-1:0][1:0]     s_site;
  logic [PPC-1:0][WBG_W-1:0] s_gain;
  logic [PPC-1:0][MW-1:0]  s_mul;
  logic [PPC-1:0][MW-WBG_FRAC:0] s_t;
  logic [PPC-1:0][IN_BITS-1:0] s_q;

  // 1段目: 乗算
  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      s_site[i] = f_site(i_cfg.phase, i_stp.line[0], f_xpar(i_stp.col[0], 1'(i)));
      if( i_cfg.wb_en ) begin
        // 色位置でゲインを選ぶ(添字が変数の配列読み出しにしない)
        case( s_site[i] )
          2'd0 : begin
            s_gain[i] = i_cfg.wbg[0];
          end
          2'd1 : begin
            s_gain[i] = i_cfg.wbg[1];
          end
          2'd2 : begin
            s_gain[i] = i_cfg.wbg[2];
          end
          default : begin
            s_gain[i] = i_cfg.wbg[3];
          end
        endcase
      end else begin
        s_gain[i] = WBG_W'(1<<WBG_FRAC);
      end
      s_mul[i] = MW'(i_stp.pix[i])*MW'(s_gain[i]);
    end
  end

  // 2段目: 丸め・クリップ
  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      s_t[i] = (MW-WBG_FRAC+1)'((r_mul1[i]+MW'(1<<(WBG_FRAC-1)))>>WBG_FRAC);
      if( s_t[i]>(MW-WBG_FRAC+1)'(PIX_MAX) ) begin
        s_q[i] = IN_BITS'(PIX_MAX);
      end else begin
        s_q[i] = IN_BITS'(s_t[i]);
      end
    end
  end

  // 制御(リセットあり)
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_vld1 <= 1'b0;
      r_vld2 <= 1'b0;
    end else begin
      r_vld1 <= i_stp.vld&&!i_clr;
      r_vld2 <= r_vld1&&!i_clr;
    end
  end

  // データ(リセットなし)
  always_ff @(posedge clk) begin
    if( i_stp.vld ) begin
      r_stp1 <= i_stp;
      r_mul1 <= s_mul;
    end
    if( r_vld1 ) begin
      r_stp2     <= r_stp1;
      r_stp2.pix <= s_q;
    end
  end

  always_comb begin
    o_stp     = r_stp2;
    o_stp.vld = r_vld2;
  end

endmodule

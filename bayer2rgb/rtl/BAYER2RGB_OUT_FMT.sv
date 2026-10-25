// ============================================================================
// BAYER2RGB_OUT_FMT : テストパターンの差し替えと出力ビートの整形(レイテンシ1)
//   tpg_en=1 のとき画素値をテストパターンに置き換える(x, y は出力画素の座標)
//     0: カラーバー(幅を8等分。白,黄,シアン,緑,マゼンタ,赤,青,黒)
//     1: ランプ   R=G=B = x[11:4]
//     2: チェッカー(64画素) (x[6]^y[6]) ? 白 : 黒
//     3: 単色     tpg_color {R[23:16], G[15:8], B[7:0]}
//   出力ビート: {eof, eol, sof, rgb}。rgb のバイト 3i/3i+1/3i+2 が画素 i の R/G/B
// ============================================================================
module BAYER2RGB_OUT_FMT
  import BAYER2RGB_PKG::*;
(
  input  logic   clk
 ,input  logic   rst_n
 ,input  logic   i_clr
 ,input  cfg_t   i_cfg
 ,input  gm_t    i_gm
 ,output logic   o_vld
 ,output obeat_t o_data
);

  typedef logic [OUT_BITS-1:0] out_t;

  logic                     r_vld;
  obeat_t                   r_data;
  logic [7:1][WIDTH_W-1:0]  r_bnd;      // カラーバーの境界 j × (幅/8)
  logic [WIDTH_W-1:0]       s_bw;       // カラーバー1本の幅
  logic [PPC-1:0][WIDTH_W-1:0] s_x;
  logic [PPC-1:0][2:0]      s_bar;
  logic [PPC-1:0][2:0][OUT_BITS-1:0] s_tpg;
  logic [PPC-1:0][2:0][OUT_BITS-1:0] s_rgb;

  assign s_bw = f_width(i_cfg.width)>>3;

  always_comb begin
    for( int i=0; i<PPC; i++ ) begin
      s_x[i]   = WIDTH_W'((int'(i_gm.oc)*PPC)+i);
      s_bar[i] = 3'd0;
      for( int j=1; j<8; j++ ) begin
        if( s_x[i]>=r_bnd[j] ) begin
          s_bar[i] = 3'(j);
        end
      end
      case( i_cfg.tpg_sel )
        2'd0 : begin
          s_tpg[i][0] = {OUT_BITS{~s_bar[i][1]}};
          s_tpg[i][1] = {OUT_BITS{~s_bar[i][2]}};
          s_tpg[i][2] = {OUT_BITS{~s_bar[i][0]}};
        end
        2'd1 : begin
          s_tpg[i][0] = out_t'(s_x[i][11:4]);
          s_tpg[i][1] = out_t'(s_x[i][11:4]);
          s_tpg[i][2] = out_t'(s_x[i][11:4]);
        end
        2'd2 : begin
          s_tpg[i][0] = {OUT_BITS{s_x[i][6]^i_gm.y[6]}};
          s_tpg[i][1] = {OUT_BITS{s_x[i][6]^i_gm.y[6]}};
          s_tpg[i][2] = {OUT_BITS{s_x[i][6]^i_gm.y[6]}};
        end
        default : begin
          s_tpg[i][0] = i_cfg.tpg_color[23:16];
          s_tpg[i][1] = i_cfg.tpg_color[15:8];
          s_tpg[i][2] = i_cfg.tpg_color[7:0];
        end
      endcase
      if( i_cfg.tpg_en ) begin
        s_rgb[i] = s_tpg[i];
      end else begin
        s_rgb[i] = i_gm.rgb[i];
      end
    end
  end

  // 制御(リセットあり)
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_vld <= 1'b0;
    end else begin
      r_vld <= i_gm.vld&&!i_clr;
    end
  end

  // データ(リセットなし)
  always_ff @(posedge clk) begin
    // 境界は設定から毎クロック作る(設定はフレーム中に変わらない)
    for( int j=1; j<8; j++ ) begin
      r_bnd[j] <= WIDTH_W'(int'(s_bw)*j);
    end
    if( i_gm.vld ) begin
      r_data.eof <= i_gm.eof;
      r_data.eol <= i_gm.eol;
      r_data.sof <= i_gm.sof;
      r_data.rgb <= s_rgb;
    end
  end

  assign o_vld  = r_vld;
  assign o_data = r_data;

endmodule

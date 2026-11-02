// ============================================================================
// BAYER_EX_PIXCOR : 画素ごとの補正(レイテンシ2)
//   1段目(黒レベル補正): q1 = max(p - blc[色], 0)
//   2段目(ゲイン)      : q2 = min(16383, (q1 × gain[色] + 2048) >> 12)
//                         gain は U4.12(0x1000 = 1.0倍)
//   色は Bayer の並び(phase)と、転送の中の位置(y、x の偶奇)で決まる。
//   bypass=1 のときは q1 = p、q2 = q1(入力の画素をそのまま出す)。
//   sof / eol / eof はそのまま次の段へ渡す。
//   i_en=0 のクロックは、全段の有効ビットとデータを保持する。
// ============================================================================
module BAYER_EX_PIXCOR
  import BAYER_EX_PKG::*;
(
  input  logic      clk
 ,input  logic      rst_n
 ,input  logic      i_en
 ,input  cfg_t      i_cfg
 ,input  logic      i_vld
 ,input  bayer4x2_t i_data
 ,output logic      o_vld
 ,output bayer4x2_t o_data
);

  localparam int MW = PIX_W+GAIN_W;    // 積のビット幅(30)
  localparam int TW = MW-GAIN_FRAC+1;  // 丸めた後のビット幅(19)

  logic                                    r_vld1;
  bayer4x2_t                               r_data1;
  logic                                    r_vld2;
  bayer4x2_t                               r_data2;
  logic [BLK_Y-1:0][BLK_X-1:0][1:0]        s_site;
  logic [BLK_Y-1:0][BLK_X-1:0][PIX_W-1:0]  s_lvl;
  logic [BLK_Y-1:0][BLK_X-1:0][GAIN_W-1:0] s_gain;
  logic [BLK_Y-1:0][BLK_X-1:0][PIX_W-1:0]  s_q1;
  logic [BLK_Y-1:0][BLK_X-1:0][MW-1:0]     s_mul;
  logic [BLK_Y-1:0][BLK_X-1:0][TW-1:0]     s_t;
  logic [BLK_Y-1:0][BLK_X-1:0][PIX_W-1:0]  s_q2;

  // 色の位置で黒レベルとゲインを選ぶ(添字が変数の配列読み出しにしない)
  always_comb begin
    for( int y=0; y<BLK_Y; y++ ) begin
      for( int x=0; x<BLK_X; x++ ) begin
        s_site[y][x] = f_site(i_cfg.phase, 1'(y), 1'(x));
        case( s_site[y][x] )
          2'd0 : begin
            s_lvl[y][x]  = i_cfg.blc[0];
            s_gain[y][x] = i_cfg.gain[0];
          end
          2'd1 : begin
            s_lvl[y][x]  = i_cfg.blc[1];
            s_gain[y][x] = i_cfg.gain[1];
          end
          2'd2 : begin
            s_lvl[y][x]  = i_cfg.blc[2];
            s_gain[y][x] = i_cfg.gain[2];
          end
          default : begin
            s_lvl[y][x]  = i_cfg.blc[3];
            s_gain[y][x] = i_cfg.gain[3];
          end
        endcase
      end
    end
  end

  // 1段目: 黒レベル補正
  always_comb begin
    for( int y=0; y<BLK_Y; y++ ) begin
      for( int x=0; x<BLK_X; x++ ) begin
        if( i_cfg.bypass ) begin
          s_q1[y][x] = i_data.pix[y][x];
        end else if( i_data.pix[y][x]>s_lvl[y][x] ) begin
          s_q1[y][x] = i_data.pix[y][x]-s_lvl[y][x];
        end else begin
          s_q1[y][x] = '0;
        end
      end
    end
  end

  // 2段目: ゲイン(乗算・丸め・クリップ)
  always_comb begin
    for( int y=0; y<BLK_Y; y++ ) begin
      for( int x=0; x<BLK_X; x++ ) begin
        s_mul[y][x] = MW'(r_data1.pix[y][x])*MW'(s_gain[y][x]);
        s_t[y][x]   = TW'((s_mul[y][x]+MW'(1<<(GAIN_FRAC-1)))>>GAIN_FRAC);
        if( i_cfg.bypass ) begin
          s_q2[y][x] = r_data1.pix[y][x];
        end else if( s_t[y][x]>TW'(PIX_MAX) ) begin
          s_q2[y][x] = PIX_W'(PIX_MAX);
        end else begin
          s_q2[y][x] = PIX_W'(s_t[y][x]);
        end
      end
    end
  end

  // 制御(リセットあり)
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_vld1 <= 1'b0;
      r_vld2 <= 1'b0;
    end else if( i_en ) begin
      r_vld1 <= i_vld;
      r_vld2 <= r_vld1;
    end
  end

  // データ(リセットなし。有効な転送のときだけ取り込む)
  always_ff @(posedge clk) begin
    if( i_en&&i_vld ) begin
      r_data1     <= i_data;
      r_data1.pix <= s_q1;
    end
    if( i_en&&r_vld1 ) begin
      r_data2     <= r_data1;
      r_data2.pix <= s_q2;
    end
  end

  assign o_vld  = r_vld2;
  assign o_data = r_data2;

endmodule

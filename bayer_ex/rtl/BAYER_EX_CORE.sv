// ============================================================================
// BAYER_EX_CORE : 演習用のコア(Bayer 4×2画素の、画素ごとの補正)
//   入力: i_vld / o_busy(ポート)と i_pix(BAYER_EX_DATA_IF.dst。data = bayer4x2_t)
//   出力: o_vld / i_busy(ポート)と o_pix(BAYER_EX_DATA_IF.src)
//   vld=1 かつ busy=0 のクロックで1転送。busy=1 の間、送り側は vld と data を保持する。
//
//   構成: 入力段(スキッド付き)→ BAYER_EX_PIXCOR(2段)→ 出力
//     - o_vld / o_pix.data / o_busy はすべて FF から出す
//       (入力ポートから出力ポートへの組み合わせの経路はない)
//     - 出力が止められている(o_vld=1 かつ i_busy=1)ときは、PIXCOR の全段を止める
//     - 止まっている間も、入力段が空いていれば入力段に1転送、さらにスキッドに1転送を
//       受け取る。スキッドが埋まると o_busy=1
//   レイテンシ: 入力の転送のクロックから3クロック後に o_vld=1(止められていないとき)
//   スループット: 1転送/クロック(8画素/クロック)
//   設定 i_cfg は毎クロック FF で受け直す。コアの中にデータがないときだけ変える。
// ============================================================================
module BAYER_EX_CORE
  import BAYER_EX_PKG::*;
(
  input  logic         clk
 ,input  logic         rst_n
 ,input  cfg_t         i_cfg
 // 入力側
 ,input  logic         i_vld
 ,output logic         o_busy
 ,BAYER_EX_DATA_IF.dst i_pix
 // 出力側
 ,output logic         o_vld
 ,input  logic         i_busy
 ,BAYER_EX_DATA_IF.src o_pix
);

  cfg_t      r_cfg;       // 設定(毎クロック受け直す)
  logic      r_in_vld;    // 入力段が有効
  bayer4x2_t r_in_data;
  logic      r_skd_vld;   // スキッドが有効
  bayer4x2_t r_skd_data;
  logic      s_take;      // 入力の転送
  logic      s_en;        // PIXCOR を進める
  logic      s_in_free;   // 入力段を更新できる
  logic      s_pc_vld;
  bayer4x2_t s_pc_data;

  assign s_take    = i_vld&&!r_skd_vld;
  assign s_en      = !(s_pc_vld&&i_busy);
  assign s_in_free = (!r_in_vld)||s_en;
  assign o_busy    = r_skd_vld;

  // 設定(リセットなし。入力ポートからの経路を FF で切る)
  always_ff @(posedge clk) begin
    r_cfg <= i_cfg;
  end

  // 制御(リセットあり)
  always_ff @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      r_in_vld  <= 1'b0;
      r_skd_vld <= 1'b0;
    end else begin
      if( s_in_free ) begin
        r_in_vld  <= r_skd_vld||s_take;
        r_skd_vld <= 1'b0;
      end else if( s_take ) begin
        r_skd_vld <= 1'b1;
      end
    end
  end

  // データ(リセットなし)
  always_ff @(posedge clk) begin
    if( s_in_free ) begin
      if( r_skd_vld ) begin
        r_in_data <= r_skd_data;
      end else if( s_take ) begin
        r_in_data <= i_pix.data;
      end
    end else if( s_take ) begin
      r_skd_data <= i_pix.data;
    end
  end

  // 画素ごとの補正
  BAYER_EX_PIXCOR u_pixcor (
    .clk    (clk)
   ,.rst_n  (rst_n)
   ,.i_en   (s_en)
   ,.i_cfg  (r_cfg)
   ,.i_vld  (r_in_vld)
   ,.i_data (r_in_data)
   ,.o_vld  (s_pc_vld)
   ,.o_data (s_pc_data)
  );

  assign o_vld      = s_pc_vld;
  assign o_pix.data = s_pc_data;

endmodule

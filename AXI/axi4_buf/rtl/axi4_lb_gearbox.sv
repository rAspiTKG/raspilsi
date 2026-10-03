//=============================================================================
// axi4_lb_gearbox.sv
//-----------------------------------------------------------------------------
//  ビット幅変換 (IN_BITS 単位 → OUT_BITS 単位)。IN_BITS と OUT_BITS は任意で、
//  互いに割り切れる必要はない。下位ビットが先 (little-endian) のビット列として
//  つなぎ替える。
//
//      in_data  : [IN_BITS-1:0]  ... 先に入れたものがビット列の下位側
//      out_data : [OUT_BITS-1:0] ... ビット列を下位から OUT_BITS ずつ切り出す
//
//  動作:
//    - 内部にアキュムレータ acc と有効ビット数 cnt を持つ
//    - out_valid = (cnt >= OUT_BITS)  または  (排出中 && cnt != 0)
//    - in_ready  = 排出中でない && (cnt < IN_TH)
//        IN_TH = OUT_BITS + min(IN_BITS, OUT_BITS)
//      → どちらも登録値だけで決まる (相手側の valid / ready に組合せ依存しない)
//    - 入力と出力は同じサイクルに行える。IN_TH は、相手が止まらない限り
//      IN >= OUT なら毎サイクル出力、IN < OUT なら毎サイクル入力が続く最小の値
//    - acc の幅は IN_TH + IN_BITS (受け付け直前の最大 cnt が IN_TH - 1 のため)
//    - in_last 付きの入力を受けると「排出中」になり、残りビットを出し切るまで
//      入力を受けない。端数は上位を 0 で埋めて出す (out_last=1)
//    - clear=1 で acc / cnt / 排出中 を即座に捨てる (ライン末尾の余りビットの破棄用)。
//      clear は他の動作より優先する
//=============================================================================
`timescale 1ns / 1ps

module axi4_lb_gearbox #(
  parameter int unsigned IN_BITS  = 64
 ,parameter int unsigned OUT_BITS = 8
) (
  input  logic                clk
 ,input  logic                rst_n
 ,input  logic                clear
  // 入力側
 ,input  logic [IN_BITS-1:0]  in_data
 ,input  logic                in_last
 ,input  logic                in_valid
 ,output logic                in_ready
  // 出力側
 ,output logic [OUT_BITS-1:0] out_data
 ,output logic                out_last
 ,output logic                out_valid
 ,input  logic                out_ready
);

  localparam int unsigned IN_TH    = OUT_BITS + ((IN_BITS<OUT_BITS) ? IN_BITS : OUT_BITS);
  localparam int unsigned ACC_BITS = IN_TH + IN_BITS;
  localparam int unsigned CNT_W    = $clog2(ACC_BITS+1);

  logic [ACC_BITS-1:0] acc;       // 有効ビットは下位 cnt ビット。それより上は常に 0
  logic [CNT_W-1:0]    cnt;
  logic                drain;     // 排出中 (in_last を受けた後)

  logic                in_fire;
  logic                out_fire;
  logic [ACC_BITS-1:0] acc_o;     // 出力後の acc
  logic [CNT_W-1:0]    cnt_o;     // 出力後の cnt
  logic [ACC_BITS-1:0] in_ext;

  assign out_valid = (cnt>=CNT_W'(OUT_BITS))||(drain&&(cnt!=CNT_W'(0)));
  assign out_data  = acc[OUT_BITS-1:0];
  assign out_last  = drain&&(cnt<=CNT_W'(OUT_BITS));
  assign in_ready  = !drain&&(cnt<CNT_W'(IN_TH));

  assign in_fire   = in_valid&&in_ready;
  assign out_fire  = out_valid&&out_ready;
  assign in_ext    = ACC_BITS'(in_data);

  // 出力で OUT_BITS (端数ならあるだけ) を取り除いた後の状態
  always @(*) begin
    acc_o = acc;
    cnt_o = cnt;
    if( out_fire ) begin
      acc_o = acc >> OUT_BITS;
      if( cnt>CNT_W'(OUT_BITS) ) begin
        cnt_o = cnt - CNT_W'(OUT_BITS);
      end else begin
        cnt_o = CNT_W'(0);
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      acc   <= {ACC_BITS{1'b0}};
      cnt   <= {CNT_W{1'b0}};
      drain <= 1'b0;
    end else if( clear ) begin
      acc   <= {ACC_BITS{1'b0}};
      cnt   <= {CNT_W{1'b0}};
      drain <= 1'b0;
    end else begin
      if( in_fire ) begin
        // 出力後の残りの直上に入力を連結する
        acc <= acc_o | (in_ext << cnt_o);
        cnt <= cnt_o + CNT_W'(IN_BITS);
        if( in_last ) begin
          drain <= 1'b1;
        end
      end else begin
        acc <= acc_o;
        cnt <= cnt_o;
        if( drain&&out_fire&&(cnt<=CNT_W'(OUT_BITS)) ) begin
          drain <= 1'b0;
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時。IEEE 1800 20.11)
  //---------------------------------------------------------------------------
`ifndef AXI4_LB_NO_ELAB_CHECK
  generate
    if( (IN_BITS<1)||(OUT_BITS<1) ) begin : g_chk_bits
      $error("axi4_lb_gearbox : IN_BITS / OUT_BITS must be >= 1 (IN_BITS=%0d OUT_BITS=%0d)", IN_BITS, OUT_BITS);
    end
  endgenerate
`endif

endmodule

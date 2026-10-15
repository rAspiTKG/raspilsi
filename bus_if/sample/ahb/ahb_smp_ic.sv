//=============================================================================
// ahb_smp_ic.sv
//-----------------------------------------------------------------------------
//  ahb_if のサンプル : AHB のインターコネクト (1 マネージャ -> NSUB サブオーディネート。合成可能)。
//    - デコーダ : HADDR の [REGION_BITS +: log2(NSUB)] でサブオーディネートを選ぶ
//      (サブオーディネート i は i * 2^REGION_BITS から 2^REGION_BITS バイト)
//    - マルチプレクサ : データフェーズのサブオーディネートの HREADYOUT / HRESP / HRDATA / HEXOKAY を返す
//    - デフォルトのサブオーディネート : どこにも当たらない NONSEQ / SEQ には ERROR (2 サイクル)、
//      IDLE / BUSY には待ち無しの OKAY
//
//  ポート
//    s_ahb        : マネージャからのリンク (ahb_if.sub。そのリンクは DIRECT=1 にする。
//                   HREADYOUT にマルチプレクサの出力を出し、DIRECT=1 の interface がそれを HREADY にする)
//    m_ahb [NSUB] : サブオーディネートへのリンク (ahb_if.dec の配列。それぞれ DIRECT=0)。
//                   HSEL と HREADY (= マルチプレクサの出力) をここから出す
//=============================================================================
`timescale 1ns / 1ps

module ahb_smp_ic #(
  parameter int unsigned ADDR_WIDTH  = 32
 ,parameter int unsigned DATA_WIDTH  = 32
 ,parameter int unsigned NSUB        = 2      // 2 以上
 ,parameter int unsigned REGION_BITS = 12
) (
  input logic hclk
 ,input logic hresetn
 ,ahb_if.sub  s_ahb
 ,ahb_if.dec  m_ahb [NSUB]
);

  // つないだ ahb_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(s_ahb.haddr)!=ADDR_WIDTH)||($bits(s_ahb.hwdata)!=DATA_WIDTH) ) begin : g_chk_if_s
    $error("ahb_smp_ic : ADDR_WIDTH / DATA_WIDTH differ from the ahb_if connected to s_ahb");
  end
`ifndef SYNTHESIS
  // interface の配列のポート (m_ahb) は、シミュレーションの開始時に確かめる
  // (Verilator 5.052 は配列のポートの幅を、エラボレーションの時点では interface の既定の parameter で計算するため)
  initial begin
    if( ($bits(m_ahb[0].haddr)!=ADDR_WIDTH)||($bits(m_ahb[0].hwdata)!=DATA_WIDTH) ) begin
      $fatal(1, "ahb_smp_ic : ADDR_WIDTH / DATA_WIDTH differ from the ahb_if connected to m_ahb");
    end
  end
`endif

  localparam int unsigned IDXW = $clog2(NSUB);

  typedef enum logic [1:0] {
    DEF_OKAY
   ,DEF_ERR1   // ERROR の 1 サイクル目 (HREADYOUT=0)
   ,DEF_ERR2   // ERROR の 2 サイクル目 (HREADYOUT=1)
  } def_t;

  logic [IDXW-1:0]       a_idx;       // アドレスフェーズのサブオーディネート番号
  logic                  a_hit;       // アドレスフェーズのアドレスがどれかに当たった
  logic                  d_hit_q;     // データフェーズ : どれかに当たった
  logic [IDXW-1:0]       d_idx_q;     // データフェーズ : サブオーディネート番号
  def_t                  def_q;

  logic [NSUB-1:0]       sub_ready;
  logic [NSUB-1:0]       sub_resp;
  logic [NSUB-1:0]       sub_exokay;
  logic [DATA_WIDTH-1:0] sub_rdata [NSUB];

  assign a_idx = s_ahb.haddr[REGION_BITS+:IDXW];
  assign a_hit = ((s_ahb.haddr>>REGION_BITS)<ADDR_WIDTH'(NSUB));

  //---------------------------------------------------------------------------
  // サブオーディネートへのリンク (アドレスフェーズと HWDATA は全てに配る)
  //---------------------------------------------------------------------------
  for( genvar i=0; i<NSUB; i++ ) begin : g_sub
    assign m_ahb[i].hsel      = a_hit&&(a_idx==IDXW'(i));
    assign m_ahb[i].haddr     = s_ahb.haddr;
    assign m_ahb[i].htrans    = s_ahb.htrans;
    assign m_ahb[i].hwrite    = s_ahb.hwrite;
    assign m_ahb[i].hsize     = s_ahb.hsize;
    assign m_ahb[i].hburst    = s_ahb.hburst;
    assign m_ahb[i].hprot     = s_ahb.hprot;
    assign m_ahb[i].hnonsec   = s_ahb.hnonsec;
    assign m_ahb[i].hexcl     = s_ahb.hexcl;
    assign m_ahb[i].hmaster   = s_ahb.hmaster;
    assign m_ahb[i].hmastlock = s_ahb.hmastlock;
    assign m_ahb[i].hwdata    = s_ahb.hwdata;
    assign m_ahb[i].hwstrb    = s_ahb.hwstrb;
    assign m_ahb[i].hready    = s_ahb.hready;
    assign sub_ready[i]       = m_ahb[i].hreadyout;
    assign sub_resp[i]        = m_ahb[i].hresp;
    assign sub_exokay[i]      = m_ahb[i].hexokay;
    assign sub_rdata[i]       = m_ahb[i].hrdata;
  end

  //---------------------------------------------------------------------------
  // データフェーズの選択と、デフォルトのサブオーディネート
  //---------------------------------------------------------------------------
  always @(posedge hclk or negedge hresetn) begin
    if( !hresetn ) begin
      d_hit_q <= 1'b1;
      d_idx_q <= '0;
      def_q   <= DEF_OKAY;
    end else begin
      if( s_ahb.hready ) begin
        d_hit_q <= a_hit;
        d_idx_q <= a_idx;
      end
      case( def_q )
        DEF_ERR1 : begin
          def_q <= DEF_ERR2;
        end
        default : begin
          if( s_ahb.hready&&s_ahb.htrans[1]&&!a_hit ) begin
            def_q <= DEF_ERR1;
          end else begin
            def_q <= DEF_OKAY;
          end
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // マネージャへの応答 (マルチプレクサ)
  //---------------------------------------------------------------------------
  assign s_ahb.hreadyout = d_hit_q ? sub_ready[d_idx_q] : (def_q!=DEF_ERR1);
  assign s_ahb.hresp     = d_hit_q ? sub_resp[d_idx_q] : (def_q!=DEF_OKAY);
  assign s_ahb.hrdata    = d_hit_q ? sub_rdata[d_idx_q] : '0;
  assign s_ahb.hexokay   = d_hit_q ? sub_exokay[d_idx_q] : 1'b0;

  // 使わない入力 (このリンクは DIRECT=1 で HSEL=1)
  wire unused_ok = &{1'b0, s_ahb.hsel};

endmodule

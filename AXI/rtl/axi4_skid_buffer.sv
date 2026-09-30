//=============================================================================
// axi4_skid_buffer.sv
//-----------------------------------------------------------------------------
//  VALID/READY ハンドシェイク用の 2 段スキッドバッファ (レジスタスライス)。
//  AXI4 の 1 チャネル分をタイミング的に切り離しつつ、スループット 1beat/clk を
//  維持する。
//
//  ハンドシェイク上の性質:
//    - m_valid は s_valid から組合せで生成されない (完全レジスタ出力)
//    - s_ready は m_ready から組合せで生成されない
//      → 上流/下流間の組合せパスが無く、AXI4 の「VALID は READY を待たない」
//        という規則 (spec A3.2.1) を守ったままパイプライン段を挿入できる
//    - BYPASS=1 にすると単純結線 (組合せ素通し) になる
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022) A3.2 Basic transaction
//        handshake  https://developer.arm.com/documentation/ihi0022/latest/
//=============================================================================
`timescale 1ns / 1ps

module axi4_skid_buffer #(
  parameter int unsigned WIDTH  = 8
 ,parameter bit          BYPASS = 1'b0
) (
  input  logic             aclk
 ,input  logic             aresetn
  // 上流側 (source)
 ,input  logic [WIDTH-1:0] s_data
 ,input  logic             s_valid
 ,output logic             s_ready
  // 下流側 (destination)
 ,output logic [WIDTH-1:0] m_data
 ,output logic             m_valid
 ,input  logic             m_ready
);

  generate
    if( BYPASS ) begin : g_bypass
      //-----------------------------------------------------------------------
      // 単純素通し
      //-----------------------------------------------------------------------
      assign m_data  = s_data;
      assign m_valid = s_valid;
      assign s_ready = m_ready;

    end else begin : g_skid
      //-----------------------------------------------------------------------
      // 2 段スキッドバッファ
      //-----------------------------------------------------------------------
      logic [WIDTH-1:0] main_data;
      logic             main_valid;
      logic [WIDTH-1:0] skid_data;
      logic             skid_valid;

      assign s_ready = !skid_valid;
      assign m_data  = main_data;
      assign m_valid = main_valid;

      always_ff @(posedge aclk or negedge aresetn) begin
        if( !aresetn ) begin
          main_data  <= {WIDTH{1'b0}};
          main_valid <= 1'b0;
          skid_data  <= {WIDTH{1'b0}};
          skid_valid <= 1'b0;
        end else begin
          // skid 段: 出力段が塞がっている間に 1 拍だけ吸収する
          if( s_valid&&s_ready&&main_valid&&!m_ready ) begin
            skid_data  <= s_data;
            skid_valid <= 1'b1;
          end else if( m_ready ) begin
            skid_valid <= 1'b0;
          end
          // main 段: 空いていれば skid を優先、無ければ上流から直接取り込む
          if( m_ready||!main_valid ) begin
            if( skid_valid ) begin
              main_data  <= skid_data;
              main_valid <= 1'b1;
            end else begin
              main_data  <= s_data;
              main_valid <= s_valid&&s_ready;
            end
          end
        end
      end
    end
  endgenerate

endmodule

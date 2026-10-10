//=============================================================================
// axil_master_rs.sv
//-----------------------------------------------------------------------------
//  レジスタスライス (2 段のスキッドバッファ)。valid/ready のチャネル 1 本ぶん。
//
//    s_* (入力側) --> [main] --> m_* (出力側)
//                      [skid]  出力が待たされている間に来た 1 データを保持
//
//  - 出力 (m_valid / m_data) と入力側の s_ready は、全てレジスタから直接出す
//    (入力から出力への組合せ回路が無い)
//  - 出力側が毎サイクル受け取れば、1 サイクルに 1 データ流れる
//  - m_valid は一度立てたら m_ready まで下げず、その間 m_data も変えない
//    (AXI の VALID / ペイロードの規則をそのまま満たす)
//  - リセット中と解除直後のサイクルは m_valid=0
//=============================================================================
`timescale 1ns / 1ps

module axil_master_rs #(
  parameter int unsigned WIDTH = 32
) (
  input  logic             clk
 ,input  logic             rst_n
 ,input  logic             s_valid
 ,output logic             s_ready
 ,input  logic [WIDTH-1:0] s_data
 ,output logic             m_valid
 ,input  logic             m_ready
 ,output logic [WIDTH-1:0] m_data
);

  logic             main_valid;
  logic [WIDTH-1:0] main_data;
  logic             skid_valid;
  logic [WIDTH-1:0] skid_data;

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      main_valid <= 1'b0;
      main_data  <= {WIDTH{1'b0}};
      skid_valid <= 1'b0;
      skid_data  <= {WIDTH{1'b0}};
    end else begin
      if( !skid_valid ) begin
        // 入力を受けられる (s_ready=1)
        if( !main_valid||m_ready ) begin
          // 出力レジスタが空いている、またはこのサイクルで空くので、入力をそのまま出力へ
          main_valid <= s_valid;
          if( s_valid ) begin
            main_data <= s_data;
          end
        end else if( s_valid ) begin
          // 出力が待たされているので、入力はスキッドへ
          skid_valid <= 1'b1;
          skid_data  <= s_data;
        end
      end else begin
        // スキッドが埋まっている (s_ready=0)。出力が受け取られたら、スキッドを出力へ
        if( m_ready ) begin
          main_data  <= skid_data;
          skid_valid <= 1'b0;
        end
      end
    end
  end

  assign s_ready = !skid_valid;
  assign m_valid = main_valid;
  assign m_data  = main_data;

endmodule

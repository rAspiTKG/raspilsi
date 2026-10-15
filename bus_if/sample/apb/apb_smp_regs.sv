//=============================================================================
// apb_smp_regs.sv
//-----------------------------------------------------------------------------
//  apb_if のサンプル : APB コンプリータ (レジスタファイル。合成可能)。
//    - アドレスの下位 OFS_BITS ビット (コンプリータの中のオフセット) の 0 から 4 バイトおきに NREG 個
//    - ACCESS で WAIT サイクル待たせてから PREADY=1 で完了する
//    - 書き込みは PSTRB のバイトだけ。存在しないレジスタは PSLVERR (書き込みは無視、読み出しデータは 0)
//    - PSLVERR / PRDATA は転送の最後のサイクル以外は 0 にする
//
//  ポートは apb_if.cmp 1 本だけ。
//=============================================================================
`timescale 1ns / 1ps

module apb_smp_regs #(
  parameter int unsigned DATA_WIDTH = 32
 ,parameter int unsigned NREG       = 4
 ,parameter int unsigned OFS_BITS   = 12
 ,parameter int unsigned WAIT       = 0
) (
  input logic pclk
 ,input logic presetn
 ,apb_if.cmp  s_apb
);

  // つないだ apb_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( $bits(s_apb.pwdata)!=DATA_WIDTH ) begin : g_chk_if
    $error("apb_smp_regs : DATA_WIDTH differs from the apb_if connected to s_apb");
  end

  localparam int unsigned SB   = DATA_WIDTH/8;
  localparam int unsigned IDXW = (NREG<2) ? 1 : $clog2(NREG);
  localparam int unsigned WW   = (WAIT<1) ? 1 : $clog2(WAIT+1);

  logic [DATA_WIDTH-1:0] regs_q [NREG];
  logic [WW-1:0]         wcnt_q;
  logic                  access;
  logic                  ready;
  logic                  hit;
  logic [IDXW-1:0]       idx;

  assign access = s_apb.psel&&s_apb.penable;
  assign ready  = (wcnt_q==WW'(WAIT));
  assign hit    = (s_apb.paddr[OFS_BITS-1:2]<(OFS_BITS-2)'(NREG));
  assign idx    = s_apb.paddr[2+:IDXW];

  always @(posedge pclk or negedge presetn) begin
    if( !presetn ) begin
      wcnt_q <= '0;
      for( int i=0; i<NREG; i++ ) begin
        regs_q[i] <= '0;
      end
    end else begin
      if( access&&!ready ) begin
        wcnt_q <= wcnt_q+1'b1;
      end else begin
        wcnt_q <= '0;
      end
      if( access&&ready&&s_apb.pwrite&&hit ) begin
        for( int k=0; k<SB; k++ ) begin
          if( s_apb.pstrb[k] ) begin
            regs_q[idx][8*k+:8] <= s_apb.pwdata[8*k+:8];
          end
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // APB の出力
  //---------------------------------------------------------------------------
  assign s_apb.pready  = ready;
  assign s_apb.pslverr = access&&ready&&!hit;
  assign s_apb.prdata  = (access&&ready&&!s_apb.pwrite&&hit) ? regs_q[idx] : '0;

  // 使わない入力 (PADDR の上位はリクエスタが PSEL のデコードに使う)
  wire unused_ok = &{1'b0, s_apb.pprot, s_apb.paddr[1:0], (s_apb.paddr>>OFS_BITS)};

endmodule

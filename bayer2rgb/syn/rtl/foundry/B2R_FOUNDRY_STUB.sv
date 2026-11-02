// ============================================================================
// Foundry のプロセス用ラッパの確認用の仮モデル(シミュレーション・lint 専用。合成しない)
//   syn/rtl/foundry/ の雛形が仮定したマクロ名・端子名を、振る舞いモデルで作る。
//   本物のメモリ・同期化セルのモデルが届いたら、このファイルは使わない
// ============================================================================
/* verilator lint_off DECLFILENAME */
module B2R_MEM_480X112 (
  input  logic         CLK
 ,input  logic         REB
 ,input  logic [8:0]   RA
 ,output logic [111:0] Q
 ,input  logic         WEB
 ,input  logic [8:0]   WA
 ,input  logic [111:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (480)
   ,.DW    (112)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_MEM_960X56 (
  input  logic        CLK
 ,input  logic        REB
 ,input  logic [9:0]  RA
 ,output logic [55:0] Q
 ,input  logic        WEB
 ,input  logic [9:0]  WA
 ,input  logic [55:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (960)
   ,.DW    (56)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_MEM_1920X28 (
  input  logic        CLK
 ,input  logic        REB
 ,input  logic [10:0] RA
 ,output logic [27:0] Q
 ,input  logic        WEB
 ,input  logic [10:0] WA
 ,input  logic [27:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (1920)
   ,.DW    (28)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_MEM_3840X14 (
  input  logic        CLK
 ,input  logic        REB
 ,input  logic [11:0] RA
 ,output logic [13:0] Q
 ,input  logic        WEB
 ,input  logic [11:0] WA
 ,input  logic [13:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (3840)
   ,.DW    (14)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_MEM_64X128 (
  input  logic         CLK
 ,input  logic         REB
 ,input  logic [5:0]   RA
 ,output logic [127:0] Q
 ,input  logic         WEB
 ,input  logic [5:0]   WA
 ,input  logic [127:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (64)
   ,.DW    (128)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_MEM_64X144 (
  input  logic         CLK
 ,input  logic         REB
 ,input  logic [5:0]   RA
 ,output logic [143:0] Q
 ,input  logic         WEB
 ,input  logic [5:0]   WA
 ,input  logic [143:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (64)
   ,.DW    (144)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_MEM_32X195 (
  input  logic         CLK
 ,input  logic         REB
 ,input  logic [4:0]   RA
 ,output logic [194:0] Q
 ,input  logic         WEB
 ,input  logic [4:0]   WA
 ,input  logic [194:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (32)
   ,.DW    (195)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_MEM_32X99 (
  input  logic        CLK
 ,input  logic        REB
 ,input  logic [4:0]  RA
 ,output logic [98:0] Q
 ,input  logic        WEB
 ,input  logic [4:0]  WA
 ,input  logic [98:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (32)
   ,.DW    (99)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_MEM_32X51 (
  input  logic        CLK
 ,input  logic        REB
 ,input  logic [4:0]  RA
 ,output logic [50:0] Q
 ,input  logic        WEB
 ,input  logic [4:0]  WA
 ,input  logic [50:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (32)
   ,.DW    (51)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_MEM_32X27 (
  input  logic        CLK
 ,input  logic        REB
 ,input  logic [4:0]  RA
 ,output logic [26:0] Q
 ,input  logic        WEB
 ,input  logic [4:0]  WA
 ,input  logic [26:0] D
);

  BAYER2RGB_SRAM_1R1W_BHV #(
    .DEPTH (32)
   ,.DW    (27)
  ) u_bhv (
    .clk     (CLK)
   ,.i_ren   (!REB)
   ,.i_raddr (RA)
   ,.o_rdata (Q)
   ,.i_wen   (!WEB)
   ,.i_waddr (WA)
   ,.i_wdata (D)
  );

endmodule

module B2R_SYNC2_RCELL (
  input  logic CLK
 ,input  logic RN
 ,input  logic D
 ,output logic Q
);

  BAYER2RGB_SYNC2_BHV #(
    .DW   (1)
   ,.INIT (1'b0)
  ) u_bhv (
    .clk   (CLK)
   ,.rst_n (RN)
   ,.i_d   (D)
   ,.o_q   (Q)
  );

endmodule

module B2R_SYNC2_SCELL (
  input  logic CLK
 ,input  logic SN
 ,input  logic D
 ,output logic Q
);

  BAYER2RGB_SYNC2_BHV #(
    .DW   (1)
   ,.INIT (1'b1)
  ) u_bhv (
    .clk   (CLK)
   ,.rst_n (SN)
   ,.i_d   (D)
   ,.o_q   (Q)
  );

endmodule

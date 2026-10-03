//=============================================================================
// axi4_lb_scratchpad.sv
//-----------------------------------------------------------------------------
//  ライン単位の scratchpad SRAM。
//  1 ラインにつき 1 個のシングルポート SRAM (axi4_lb_sram_sp) を持ち、
//  NUM_LINES 個を並べる。
//
//      wr_slot / wr_addr / wr_data --> [SRAM #0] --+
//                                      [SRAM #1] --+--> rd_data (rd_en の次サイクル)
//                                        ...       |
//                                      [SRAM #N-1]-+
//
//  - 書き込みは 1 ワード/サイクル。wr_slot のラインの wr_addr に書く
//  - 読み出しは rd_en の次サイクルに rd_valid / rd_data が出る
//  - 同じラインへの書き込みと読み出しを同じサイクルに出してはならない
//    (上位の制御で、書き込み中のラインと読み出し中のラインは必ず別になる。
//     だからシングルポート SRAM で足りる)
//  - 違うラインであれば、書き込みと読み出しは同時に行える
//
//  SRAM の構成を変えたい場合 (全ラインを 1 個の 2 ポート SRAM にまとめる等) は、
//  このモジュールを同じポートのまま差し替える。
//=============================================================================
`timescale 1ns / 1ps

module axi4_lb_scratchpad #(
  parameter int unsigned NUM_LINES  = 4
 ,parameter int unsigned LINE_WORDS = 1920
 ,parameter int unsigned WORD_BITS  = 8
 ,parameter int unsigned SLOT_W     = (NUM_LINES<2) ? 1 : $clog2(NUM_LINES)
 ,parameter int unsigned ADDR_W     = (LINE_WORDS<2) ? 1 : $clog2(LINE_WORDS)
) (
  input  logic                 clk
 ,input  logic                 rst_n
  // 書き込み
 ,input  logic                 wr_en
 ,input  logic [SLOT_W-1:0]    wr_slot
 ,input  logic [ADDR_W-1:0]    wr_addr
 ,input  logic [WORD_BITS-1:0] wr_data
  // 読み出し (rd_en の次サイクルに rd_valid / rd_data)
 ,input  logic                 rd_en
 ,input  logic [SLOT_W-1:0]    rd_slot
 ,input  logic [ADDR_W-1:0]    rd_addr
 ,output logic                 rd_valid
 ,output logic [WORD_BITS-1:0] rd_data
);

  logic [WORD_BITS-1:0] q [0:NUM_LINES-1];
  logic [SLOT_W-1:0]    rd_slot_q;

  //---------------------------------------------------------------------------
  // ラインごとの SRAM
  //---------------------------------------------------------------------------
  genvar gi;
  generate
    for( gi=0; gi<NUM_LINES; gi=gi+1 ) begin : g_line
      logic              sel_w;
      logic              sel_r;
      logic [ADDR_W-1:0] addr;

      assign sel_w = wr_en&&(wr_slot==SLOT_W'(gi));
      assign sel_r = rd_en&&(rd_slot==SLOT_W'(gi));
      assign addr  = sel_w ? wr_addr : rd_addr;

      axi4_lb_sram_sp #(
        .DEPTH(LINE_WORDS)
       ,.DATA_WIDTH(WORD_BITS)
       ,.ADDR_WIDTH(ADDR_W)
      ) u_sram (
        .clk(clk)
       ,.ce(sel_w||sel_r)
       ,.we(sel_w)
       ,.addr(addr)
       ,.wdata(wr_data)
       ,.rdata(q[gi])
      );
    end
  endgenerate

  //---------------------------------------------------------------------------
  // 読み出しデータの選択 (読み出しを出したラインを 1 サイクル覚えておく)
  //---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      rd_valid  <= 1'b0;
      rd_slot_q <= {SLOT_W{1'b0}};
    end else begin
      rd_valid <= rd_en;
      if( rd_en ) begin
        rd_slot_q <= rd_slot;
      end
    end
  end

  assign rd_data = q[rd_slot_q];

  //---------------------------------------------------------------------------
  // シミュレーション用チェック (合成では `define SYNTHESIS で外れる)
  //   sim_conflict_cnt  : 同じラインへの書き込みと読み出しが同じサイクルに来た回数
  //   sim_uninit_rd_cnt : そのラインにまだ書いていないワードを読んだ回数
  //                       (アドレス 0 への書き込みを「新しいラインの開始」とみなし、
  //                        そこから連続して書かれたワード数を覚えておく)
  //   テストベンチがこの 2 つが 0 のままであることを確認する
  //---------------------------------------------------------------------------
`ifndef SYNTHESIS
  int unsigned sim_conflict_cnt;
  int unsigned sim_uninit_rd_cnt;
  int unsigned sim_wr_words [0:NUM_LINES-1];

  initial begin
    sim_conflict_cnt  = 0;
    sim_uninit_rd_cnt = 0;
    for( int unsigned i=0; i<NUM_LINES; i++ ) begin
      sim_wr_words[i] = 0;
    end
  end

  always @(posedge clk) begin
    int unsigned ws;
    int unsigned wa;
    int unsigned rs;
    int unsigned ra;
    ws = 32'(wr_slot);
    wa = 32'(wr_addr);
    rs = 32'(rd_slot);
    ra = 32'(rd_addr);
    if( wr_en&&rd_en&&(ws==rs) ) begin
      sim_conflict_cnt <= sim_conflict_cnt + 1;
      $display("[%0t] axi4_lb_scratchpad : ERROR : write and read hit the same line slot %0d", $time, ws);
    end
    if( wr_en ) begin
      if( (wa>=LINE_WORDS)||(ws>=NUM_LINES) ) begin
        sim_conflict_cnt <= sim_conflict_cnt + 1;
        $display("[%0t] axi4_lb_scratchpad : ERROR : write out of range (slot %0d, word %0d)", $time, ws, wa);
      end else begin
        sim_wr_words[ws] <= wa + 1;
      end
    end
    if( rd_en ) begin
      if( rs>=NUM_LINES ) begin
        sim_uninit_rd_cnt <= sim_uninit_rd_cnt + 1;
        $display("[%0t] axi4_lb_scratchpad : ERROR : read out of range (slot %0d)", $time, rs);
      end else if( ra>=sim_wr_words[rs] ) begin
        sim_uninit_rd_cnt <= sim_uninit_rd_cnt + 1;
        $display("[%0t] axi4_lb_scratchpad : ERROR : read of a word that is not written (slot %0d, word %0d)", $time, rs, ra);
      end
    end
  end
`endif

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時。IEEE 1800 20.11)
  //---------------------------------------------------------------------------
`ifndef AXI4_LB_NO_ELAB_CHECK
  generate
    if( NUM_LINES<1 ) begin : g_chk_lines
      $error("axi4_lb_scratchpad : NUM_LINES must be >= 1 (NUM_LINES=%0d)", NUM_LINES);
    end
    if( LINE_WORDS<1 ) begin : g_chk_words
      $error("axi4_lb_scratchpad : LINE_WORDS must be >= 1 (LINE_WORDS=%0d)", LINE_WORDS);
    end
  endgenerate
`endif

endmodule

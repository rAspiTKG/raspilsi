// ============================================================================
// BAYER2RGB_SFIFO : 同期FIFO(書き込み・読み出しとも vld/busy/data)
//   USE_SRAM=0 : FFで構成する(浅いFIFO用)。容量 DEPTH
//   USE_SRAM=1 : 1R1W SRAM + 2段の先読みバッファで構成する。容量 DEPTH+2
//                書き込みから読み出し側に出るまで3クロック。連続で1ワード/クロック
//   o_cnt  : 格納数(SRAM版は読み出し中と先読みバッファの分を含む)
//   i_clr  : 同期クリア(中身を捨てる)
// ============================================================================
module BAYER2RGB_SFIFO #(
  parameter int DEPTH    = 32
 ,parameter int DW       = 8
 ,parameter bit USE_SRAM = 1'b0
 ,parameter int CW       = $clog2(DEPTH+3)
) (
  input  logic          clk
 ,input  logic          rst_n
 ,input  logic          i_clr
 // 書き込み側
 ,input  logic          i_wvld
 ,output logic          o_wbusy
 ,input  logic [DW-1:0] i_wdata
 // 読み出し側
 ,output logic          o_rvld
 ,input  logic          i_rbusy
 ,output logic [DW-1:0] o_rdata
 // 格納数
 ,output logic [CW-1:0] o_cnt
);

  localparam int AW = (DEPTH>1) ? $clog2(DEPTH) : 1;

  // ポインタを1つ進める(DEPTHが2のべき乗でなくてもよい)
  function automatic logic [AW-1:0] f_inc( input logic [AW-1:0] p );
    begin
      if( p==AW'(DEPTH-1) ) begin
        f_inc = '0;
      end else begin
        f_inc = p+AW'(1);
      end
    end
  endfunction

  if( !USE_SRAM ) begin : g_ff
    // ------------------------------------------------------------------------
    // FF版
    // ------------------------------------------------------------------------
    logic [DW-1:0] r_mem [DEPTH];
    logic [AW-1:0] r_wp;
    logic [AW-1:0] r_rp;
    logic [CW-1:0] r_cnt;
    logic          s_push;
    logic          s_pop;

    assign o_wbusy = (r_cnt==CW'(DEPTH));
    assign o_rvld  = (r_cnt!=CW'(0));
    assign o_rdata = r_mem[r_rp];
    assign o_cnt   = r_cnt;
    assign s_push  = i_wvld&&!o_wbusy;
    assign s_pop   = o_rvld&&!i_rbusy;

    always_ff @(posedge clk or negedge rst_n) begin
      if( !rst_n ) begin
        r_wp  <= '0;
        r_rp  <= '0;
        r_cnt <= '0;
      end else if( i_clr ) begin
        r_wp  <= '0;
        r_rp  <= '0;
        r_cnt <= '0;
      end else begin
        if( s_push ) begin
          r_wp <= f_inc(r_wp);
        end
        if( s_pop ) begin
          r_rp <= f_inc(r_rp);
        end
        r_cnt <= r_cnt+CW'(s_push)-CW'(s_pop);
      end
    end

    always_ff @(posedge clk) begin
      if( s_push ) begin
        r_mem[r_wp] <= i_wdata;
      end
    end

  end else begin : g_sram
    // ------------------------------------------------------------------------
    // SRAM版
    // ------------------------------------------------------------------------
    logic [AW-1:0] r_wp;
    logic [AW-1:0] r_rp;
    logic [CW-1:0] r_scnt;        // SRAM内の個数
    logic          r_rd;          // 前のクロックでSRAMを読んだ(今クロックにデータが出る)
    logic [1:0]    r_pcnt;        // 先読みバッファの個数(0..2)
    logic          r_phd;         // 先読みバッファの先頭位置
    logic [DW-1:0] r_pf [2];      // 先読みバッファ
    logic [DW-1:0] s_sram_rdata;
    logic          s_push;
    logic          s_pop;
    logic          s_ren;
    logic [1:0]    s_occ;         // 今クロックの終わりの先読みバッファの個数

    assign o_wbusy = (r_scnt==CW'(DEPTH));
    assign s_push  = i_wvld&&!o_wbusy;
    assign o_rvld  = (r_pcnt!=2'd0);
    assign o_rdata = r_pf[r_phd];
    assign s_pop   = o_rvld&&!i_rbusy;
    assign s_occ   = r_pcnt+{1'b0, r_rd}-{1'b0, s_pop};
    assign s_ren   = (r_scnt!=CW'(0))&&(s_occ<=2'd1);
    assign o_cnt   = r_scnt+CW'(r_pcnt)+CW'(r_rd);

    BAYER2RGB_SRAM_1R1W #(
      .DEPTH (DEPTH)
     ,.DW    (DW)
     ,.AW    (AW)
    ) u_sram (
      .clk     (clk)
     ,.i_ren   (s_ren)
     ,.i_raddr (r_rp)
     ,.o_rdata (s_sram_rdata)
     ,.i_wen   (s_push)
     ,.i_waddr (r_wp)
     ,.i_wdata (i_wdata)
    );

    always_ff @(posedge clk or negedge rst_n) begin
      if( !rst_n ) begin
        r_wp   <= '0;
        r_rp   <= '0;
        r_scnt <= '0;
        r_rd   <= 1'b0;
        r_pcnt <= 2'd0;
        r_phd  <= 1'b0;
      end else if( i_clr ) begin
        r_wp   <= '0;
        r_rp   <= '0;
        r_scnt <= '0;
        r_rd   <= 1'b0;
        r_pcnt <= 2'd0;
        r_phd  <= 1'b0;
      end else begin
        if( s_push ) begin
          r_wp <= f_inc(r_wp);
        end
        if( s_ren ) begin
          r_rp <= f_inc(r_rp);
        end
        r_scnt <= r_scnt+CW'(s_push)-CW'(s_ren);
        r_rd   <= s_ren;
        r_pcnt <= s_occ;
        if( s_pop ) begin
          r_phd <= ~r_phd;
        end
      end
    end

    // SRAMから出たデータを先読みバッファの末尾に入れる(r_rd=1 のとき r_pcnt<=1)
    always_ff @(posedge clk) begin
      if( r_rd ) begin
        r_pf[r_phd^r_pcnt[0]] <= s_sram_rdata;
      end
    end

  end

endmodule

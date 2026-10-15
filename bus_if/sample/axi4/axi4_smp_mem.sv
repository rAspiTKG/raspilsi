//=============================================================================
// axi4_smp_mem.sv
//-----------------------------------------------------------------------------
//  axi4_if のサンプル : AXI4 サブオーディネート + メモリ (合成可能)。
//    - トランザクションを 1 つずつ処理する (AW と AR が同時なら交互)
//    - FIXED / INCR / WRAP、狭い転送 (WSTRB をバイトイネーブルに使う) に対応。RDATA はワード全体
//    - AWREADY / ARREADY は VALID が来てから READY_DLY サイクル後に出す (待ちの例)
//    - W は AW を受け付けてから受け取る。応答は常に OKAY (AxLOCK は見ない)
//    - アドレスは下位 (log2(MEM_WORDS) + log2(DATA_WIDTH/8)) ビットだけを使う
//
//  ポートは axi4_if.sub 1 本だけ (個別の s_axi_* は書かない)。
//=============================================================================
`timescale 1ns / 1ps

module axi4_smp_mem #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned MEM_WORDS  = 64     // 2 のべき乗
 ,parameter int unsigned READY_DLY  = 1
) (
  input logic aclk
 ,input logic aresetn
 ,axi4_if.sub s_axi
);

  // つないだ axi4_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(s_axi.awaddr)!=ADDR_WIDTH)||($bits(s_axi.wdata)!=DATA_WIDTH)||($bits(s_axi.awid)!=ID_WIDTH) ) begin : g_chk_if
    $error("axi4_smp_mem : ADDR_WIDTH / DATA_WIDTH / ID_WIDTH differ from the axi4_if connected to s_axi");
  end

  localparam int unsigned STRB_WIDTH = DATA_WIDTH/8;
  localparam int unsigned OFSW       = $clog2(STRB_WIDTH);
  localparam int unsigned MAW        = $clog2(MEM_WORDS);
  localparam int unsigned DLYW       = (READY_DLY<1) ? 1 : $clog2(READY_DLY+1);

  typedef enum logic [1:0] {
    M_IDLE
   ,M_WDATA
   ,M_BRESP
   ,M_RDATA
  } st_t;

  st_t                   st_q;
  logic                  last_wr_q;  // 直前に受け付けたのが書き込み (交互にするため)
  logic [DLYW-1:0]       dly_q;
  logic [ID_WIDTH-1:0]   id_q;
  logic [ADDR_WIDTH-1:0] addr_q;
  logic [7:0]            len_q;
  logic [2:0]            size_q;
  logic [1:0]            burst_q;
  logic [7:0]            beat_q;
  logic [DATA_WIDTH-1:0] mem [MEM_WORDS];

  logic                  pick_w;     // IDLE でどちらを受け付けるか
  logic                  pick_r;
  logic                  dly_ok;

  // 次のビートのアドレス (FIXED / INCR / WRAP)
  function automatic logic [ADDR_WIDTH-1:0] next_addr(input logic [ADDR_WIDTH-1:0] a, input logic [7:0] len, input logic [2:0] size, input logic [1:0] burst);
    logic [ADDR_WIDTH-1:0] nb;
    logic [ADDR_WIDTH-1:0] inc;
    logic [ADDR_WIDTH-1:0] wm;
    nb  = ADDR_WIDTH'(1)<<size;
    inc = (a&~(nb-1'b1))+nb;
    wm  = ((ADDR_WIDTH'(len)+1'b1)<<size)-1'b1;
    case( burst )
      2'b00 : begin
        next_addr = a;
      end
      2'b10 : begin
        next_addr = (a&~wm)|(inc&wm);
      end
      default : begin
        next_addr = inc;
      end
    endcase
  endfunction

  assign pick_w = s_axi.awvalid&&(!s_axi.arvalid||!last_wr_q);
  assign pick_r = s_axi.arvalid&&!pick_w;
  assign dly_ok = (dly_q==DLYW'(READY_DLY));

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      st_q      <= M_IDLE;
      last_wr_q <= 1'b0;
      dly_q     <= '0;
      id_q      <= '0;
      addr_q    <= '0;
      len_q     <= '0;
      size_q    <= '0;
      burst_q   <= '0;
      beat_q    <= '0;
    end else begin
      case( st_q )
        M_IDLE : begin
          if( pick_w||pick_r ) begin
            if( dly_ok ) begin
              dly_q     <= '0;
              last_wr_q <= pick_w;
              beat_q    <= '0;
              if( pick_w ) begin
                id_q    <= s_axi.awid;
                addr_q  <= s_axi.awaddr;
                len_q   <= s_axi.awlen;
                size_q  <= s_axi.awsize;
                burst_q <= s_axi.awburst;
                st_q    <= M_WDATA;
              end else begin
                id_q    <= s_axi.arid;
                addr_q  <= s_axi.araddr;
                len_q   <= s_axi.arlen;
                size_q  <= s_axi.arsize;
                burst_q <= s_axi.arburst;
                st_q    <= M_RDATA;
              end
            end else begin
              dly_q <= dly_q+1'b1;
            end
          end
        end
        M_WDATA : begin
          if( s_axi.wvalid ) begin
            addr_q <= next_addr(addr_q, len_q, size_q, burst_q);
            beat_q <= beat_q+8'd1;
            if( beat_q==len_q ) begin
              st_q <= M_BRESP;
            end
          end
        end
        M_BRESP : begin
          if( s_axi.bready ) begin
            st_q <= M_IDLE;
          end
        end
        M_RDATA : begin
          if( s_axi.rready ) begin
            addr_q <= next_addr(addr_q, len_q, size_q, burst_q);
            beat_q <= beat_q+8'd1;
            if( beat_q==len_q ) begin
              st_q <= M_IDLE;
            end
          end
        end
        default : begin
          st_q <= M_IDLE;
        end
      endcase
    end
  end

  // メモリ (書き込みは WSTRB のバイトだけ)
  always @(posedge aclk) begin
    if( (st_q==M_WDATA)&&s_axi.wvalid ) begin
      for( int k=0; k<STRB_WIDTH; k++ ) begin
        if( s_axi.wstrb[k] ) begin
          mem[addr_q[OFSW+:MAW]][8*k+:8] <= s_axi.wdata[8*k+:8];
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // AXI の出力
  //---------------------------------------------------------------------------
  assign s_axi.awready = (st_q==M_IDLE)&&pick_w&&dly_ok;
  assign s_axi.arready = (st_q==M_IDLE)&&pick_r&&dly_ok;
  assign s_axi.wready  = (st_q==M_WDATA);
  assign s_axi.bid     = id_q;
  assign s_axi.bresp   = 2'b00;
  assign s_axi.bvalid  = (st_q==M_BRESP);
  assign s_axi.rid     = id_q;
  assign s_axi.rdata   = mem[addr_q[OFSW+:MAW]];
  assign s_axi.rresp   = 2'b00;
  assign s_axi.rlast   = (beat_q==len_q);
  assign s_axi.rvalid  = (st_q==M_RDATA);

  // 使わない入力 (WLAST はビート数で代用する)
  wire unused_aw = &{1'b0, s_axi.awlock, s_axi.awcache, s_axi.awprot, s_axi.awqos, s_axi.awregion, s_axi.wlast};
  wire unused_ar = &{1'b0, s_axi.arlock, s_axi.arcache, s_axi.arprot, s_axi.arqos, s_axi.arregion};

endmodule

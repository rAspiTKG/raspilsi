//=============================================================================
// axi4_full_slave_mem.sv
//-----------------------------------------------------------------------------
//  AXI4-Full スレーブ単体。
//  Write で受け取ったデータを内部メモリに格納し、同一アドレスの Read で
//  そのまま返す (ループバック) 単純なモジュール。
//
//  実装している AXI4 の要件:
//    - AW / W / B / AR / R の 5 チャネル全てで VALID/READY ハンドシェイク
//        * VALID は READY を待たずにアサートしてよい (スレーブ側は READY のみ制御)
//        * VALID は握手が成立するまでデアサートしない (マスタ側の責務)
//    - バーストタイプ FIXED / INCR / WRAP のアドレス生成
//    - AWLEN/ARLEN = 0..255 (INCR)、WRAP は 2/4/8/16 ビート
//    - WSTRB によるバイトイネーブル
//    - WLAST / RLAST、BRESP / RRESP (常に OKAY)
//    - AxID をレスポンスにそのまま返す (BID / RID)
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//        https://developer.arm.com/documentation/ihi0022/latest/
//        - A3.2  Basic transaction handshake  (VALID/READY 規則)
//        - A3.4.1 Address structure           (バーストアドレス生成の疑似コード)
//        - A3.4.4 Read and write response structure (RESP エンコード)
//
//  注意 (簡易実装):
//    - 未処理トランザクションは Write/Read 各 1 本 (アウトスタンディング非対応)
//    - W チャネルは AW 受領後に WREADY をアサートする (W 先行は受け付けない)
//      → AXI 的には合法 (スレーブは WREADY を任意に下げてよい)
//    - 同一アドレスへの Read/Write 同時アクセス時は Read が旧データを返す
//=============================================================================
`timescale 1ns / 1ps

module axi4_full_slave_mem #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned MEM_DEPTH  = 1024
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                      aclk
 ,input  logic                      aresetn
  //---------------------------------------------------------------------------
  // Write address channel (AW)
  //---------------------------------------------------------------------------
 ,input  logic [ID_WIDTH-1:0]       s_axi_awid
 ,input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr
 ,input  logic [7:0]                s_axi_awlen
 ,input  logic [2:0]                s_axi_awsize
 ,input  logic [1:0]                s_axi_awburst
 ,input  logic                      s_axi_awlock
 ,input  logic [3:0]                s_axi_awcache
 ,input  logic [2:0]                s_axi_awprot
 ,input  logic [3:0]                s_axi_awqos
 ,input  logic [3:0]                s_axi_awregion
 ,input  logic                      s_axi_awvalid
 ,output logic                      s_axi_awready
  //---------------------------------------------------------------------------
  // Write data channel (W)
  //---------------------------------------------------------------------------
 ,input  logic [DATA_WIDTH-1:0]     s_axi_wdata
 ,input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb
 ,input  logic                      s_axi_wlast
 ,input  logic                      s_axi_wvalid
 ,output logic                      s_axi_wready
  //---------------------------------------------------------------------------
  // Write response channel (B)
  //---------------------------------------------------------------------------
 ,output logic [ID_WIDTH-1:0]       s_axi_bid
 ,output logic [1:0]                s_axi_bresp
 ,output logic                      s_axi_bvalid
 ,input  logic                      s_axi_bready
  //---------------------------------------------------------------------------
  // Read address channel (AR)
  //---------------------------------------------------------------------------
 ,input  logic [ID_WIDTH-1:0]       s_axi_arid
 ,input  logic [ADDR_WIDTH-1:0]     s_axi_araddr
 ,input  logic [7:0]                s_axi_arlen
 ,input  logic [2:0]                s_axi_arsize
 ,input  logic [1:0]                s_axi_arburst
 ,input  logic                      s_axi_arlock
 ,input  logic [3:0]                s_axi_arcache
 ,input  logic [2:0]                s_axi_arprot
 ,input  logic [3:0]                s_axi_arqos
 ,input  logic [3:0]                s_axi_arregion
 ,input  logic                      s_axi_arvalid
 ,output logic                      s_axi_arready
  //---------------------------------------------------------------------------
  // Read data channel (R)
  //---------------------------------------------------------------------------
 ,output logic [ID_WIDTH-1:0]       s_axi_rid
 ,output logic [DATA_WIDTH-1:0]     s_axi_rdata
 ,output logic [1:0]                s_axi_rresp
 ,output logic                      s_axi_rlast
 ,output logic                      s_axi_rvalid
 ,input  logic                      s_axi_rready
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned ADDR_LSB   = $clog2(STRB_WIDTH);
  localparam int unsigned MEM_AW     = $clog2(MEM_DEPTH);

  localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
  localparam logic [1:0] AXI_BURST_INCR  = 2'b01;
  localparam logic [1:0] AXI_BURST_WRAP  = 2'b10;

  localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;

  //---------------------------------------------------------------------------
  // Burst address generator
  //   AXI4 spec A3.4.1 Address structure の疑似コード相当
  //---------------------------------------------------------------------------
  function automatic logic [ADDR_WIDTH-1:0] f_next_addr
  (
    input logic [ADDR_WIDTH-1:0] cur_addr
   ,input logic [ADDR_WIDTH-1:0] start_addr
   ,input logic [7:0]            len
   ,input logic [2:0]            size
   ,input logic [1:0]            burst
  );
    logic [ADDR_WIDTH-1:0] num_bytes;
    logic [ADDR_WIDTH-1:0] total_bytes;
    logic [ADDR_WIDTH-1:0] wrap_lo;
    logic [ADDR_WIDTH-1:0] wrap_hi;
    logic [ADDR_WIDTH-1:0] aligned_next;
    begin
      num_bytes    = ADDR_WIDTH'(1) << size;
      total_bytes  = num_bytes * (ADDR_WIDTH'(len) + ADDR_WIDTH'(1));
      wrap_lo      = start_addr & ~(total_bytes - ADDR_WIDTH'(1));
      wrap_hi      = wrap_lo + total_bytes;
      aligned_next = (cur_addr & ~(num_bytes - ADDR_WIDTH'(1))) + num_bytes;
      case( burst )
        AXI_BURST_FIXED : begin
          f_next_addr = cur_addr;
        end
        AXI_BURST_WRAP : begin
          if( aligned_next>=wrap_hi ) begin
            f_next_addr = wrap_lo;
          end else begin
            f_next_addr = aligned_next;
          end
        end
        default : begin
          // AXI_BURST_INCR
          f_next_addr = aligned_next;
        end
      endcase
    end
  endfunction

  // アドレス → メモリワードインデックス (下位はバイトオフセットなので捨てる)
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [MEM_AW-1:0] f_word_idx( input logic [ADDR_WIDTH-1:0] addr );
    begin
      f_word_idx = addr[ADDR_LSB+:MEM_AW];
    end
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  //---------------------------------------------------------------------------
  // Storage
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

  //---------------------------------------------------------------------------
  // Write channel FSM
  //---------------------------------------------------------------------------
  typedef enum logic [1:0] {
     WR_IDLE = 2'd0
    ,WR_DATA = 2'd1
    ,WR_RESP = 2'd2
  } wr_state_e;

  wr_state_e             wr_state;
  logic [ID_WIDTH-1:0]   wr_id;
  logic [ADDR_WIDTH-1:0] wr_addr;
  logic [ADDR_WIDTH-1:0] wr_start;
  logic [7:0]            wr_len;
  logic [2:0]            wr_size;
  logic [1:0]            wr_burst;

  assign s_axi_awready = (wr_state==WR_IDLE);
  assign s_axi_wready  = (wr_state==WR_DATA);
  assign s_axi_bvalid  = (wr_state==WR_RESP);
  assign s_axi_bid     = wr_id;
  assign s_axi_bresp   = AXI_RESP_OKAY;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      wr_state <= WR_IDLE;
      wr_id    <= {ID_WIDTH{1'b0}};
      wr_addr  <= {ADDR_WIDTH{1'b0}};
      wr_start <= {ADDR_WIDTH{1'b0}};
      wr_len   <= 8'd0;
      wr_size  <= 3'd0;
      wr_burst <= AXI_BURST_INCR;
    end else begin
      case( wr_state )
        WR_IDLE : begin
          if( s_axi_awvalid ) begin
            wr_id    <= s_axi_awid;
            wr_addr  <= s_axi_awaddr;
            wr_start <= s_axi_awaddr;
            wr_len   <= s_axi_awlen;
            wr_size  <= s_axi_awsize;
            wr_burst <= s_axi_awburst;
            wr_state <= WR_DATA;
          end
        end
        WR_DATA : begin
          if( s_axi_wvalid ) begin
            wr_addr <= f_next_addr(wr_addr, wr_start, wr_len, wr_size, wr_burst);
            if( s_axi_wlast ) begin
              wr_state <= WR_RESP;
            end
          end
        end
        WR_RESP : begin
          if( s_axi_bready ) begin
            wr_state <= WR_IDLE;
          end
        end
        default : begin
          wr_state <= WR_IDLE;
        end
      endcase
    end
  end

  // メモリ書き込み (WSTRB でバイト単位マスク)
  always_ff @(posedge aclk) begin
    if( s_axi_wvalid&&s_axi_wready ) begin
      for( int unsigned b=0; b<STRB_WIDTH; b++ ) begin
        if( s_axi_wstrb[b] ) begin
          mem[f_word_idx(wr_addr)][b*8+:8] <= s_axi_wdata[b*8+:8];
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // Read channel FSM
  //---------------------------------------------------------------------------
  typedef enum logic [0:0] {
     RD_IDLE = 1'b0
    ,RD_DATA = 1'b1
  } rd_state_e;

  rd_state_e             rd_state;
  logic [ID_WIDTH-1:0]   rd_id;
  logic [ADDR_WIDTH-1:0] rd_addr;
  logic [ADDR_WIDTH-1:0] rd_start;
  logic [7:0]            rd_len;
  logic [2:0]            rd_size;
  logic [1:0]            rd_burst;
  logic [7:0]            rd_cnt;
  logic [ADDR_WIDTH-1:0] rd_addr_nxt;
  logic [DATA_WIDTH-1:0] rd_data_reg;
  logic                  mem_re;
  logic [MEM_AW-1:0]     mem_raddr;

  assign rd_addr_nxt = f_next_addr(rd_addr, rd_start, rd_len, rd_size, rd_burst);

  assign s_axi_arready = (rd_state==RD_IDLE);
  assign s_axi_rvalid  = (rd_state==RD_DATA);
  assign s_axi_rid     = rd_id;
  assign s_axi_rdata   = rd_data_reg;
  assign s_axi_rresp   = AXI_RESP_OKAY;
  assign s_axi_rlast   = (rd_state==RD_DATA)&&(rd_cnt==rd_len);

  // 同期読み出し RAM のアドレス生成 (次ビートを 1 拍先読みする)
  always_comb begin
    mem_re    = 1'b0;
    mem_raddr = f_word_idx(rd_addr);
    if( rd_state==RD_IDLE ) begin
      if( s_axi_arvalid ) begin
        mem_re    = 1'b1;
        mem_raddr = f_word_idx(s_axi_araddr);
      end
    end else begin
      if( s_axi_rready&&(rd_cnt!=rd_len) ) begin
        mem_re    = 1'b1;
        mem_raddr = f_word_idx(rd_addr_nxt);
      end
    end
  end

  always_ff @(posedge aclk) begin
    if( mem_re ) begin
      rd_data_reg <= mem[mem_raddr];
    end
  end

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      rd_state <= RD_IDLE;
      rd_id    <= {ID_WIDTH{1'b0}};
      rd_addr  <= {ADDR_WIDTH{1'b0}};
      rd_start <= {ADDR_WIDTH{1'b0}};
      rd_len   <= 8'd0;
      rd_size  <= 3'd0;
      rd_burst <= AXI_BURST_INCR;
      rd_cnt   <= 8'd0;
    end else begin
      case( rd_state )
        RD_IDLE : begin
          if( s_axi_arvalid ) begin
            rd_id    <= s_axi_arid;
            rd_addr  <= s_axi_araddr;
            rd_start <= s_axi_araddr;
            rd_len   <= s_axi_arlen;
            rd_size  <= s_axi_arsize;
            rd_burst <= s_axi_arburst;
            rd_cnt   <= 8'd0;
            rd_state <= RD_DATA;
          end
        end
        RD_DATA : begin
          if( s_axi_rready ) begin
            if( rd_cnt==rd_len ) begin
              rd_state <= RD_IDLE;
            end else begin
              rd_cnt  <= rd_cnt + 8'd1;
              rd_addr <= rd_addr_nxt;
            end
          end
        end
        default : begin
          rd_state <= RD_IDLE;
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // 未使用入力 (本モジュールでは無視する属性信号)
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{ 1'b0
                      , s_axi_awlock, s_axi_awcache, s_axi_awprot
                      , s_axi_awqos , s_axi_awregion
                      , s_axi_arlock, s_axi_arcache, s_axi_arprot
                      , s_axi_arqos , s_axi_arregion };

endmodule

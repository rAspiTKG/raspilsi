//=============================================================================
// axi4_full_to_p2p_bridge.sv
//-----------------------------------------------------------------------------
//  AXI4-Full スレーブ ⇄ valid/busy 方式の p2p (point-to-point) インタフェース
//  の双方向 bridge。
//
//    AXI4-Full Write バースト  --[送信 FIFO]--> p2p 出力チャネル (vld/busy/dat)
//    p2p 入力チャネル (vld/busy/dat) --[受信 FIFO]--> AXI4-Full Read バースト
//
//  p2p プロトコル (busy = ready の反転):
//    - 送信側が dat と vld を駆動し、受信側が busy を駆動する
//    - vld=1 かつ busy=0 のクロック立ち上がりで 1 ビート転送成立
//    - vld は busy を待たずにアサートしてよく、転送成立まで下げてはならない
//    - vld は busy に組合せ依存しない (本モジュールでは FIFO の登録値から生成)
//    - busy は vld に組合せ依存しない (FIFO の格納数から生成)
//
//  AXI4 側は AW/W/B/AR/R の 5 チャネル全てで VALID/READY ハンドシェイクを実装。
//  本モジュールは FIFO ポートとして振る舞うため、AWADDR / ARADDR / AxSIZE /
//  AxBURST 等のアドレス属性は無視する (どのアドレスへのアクセスも同じ FIFO)。
//  転送ビート数は AWLEN / ARLEN が決める。
//
//  参考:
//    - AMBA AXI Protocol Specification (Arm IHI 0022)
//      https://developer.arm.com/documentation/ihi0022/latest/
//      A3.2 Basic transaction handshake / A3.4.4 Read and write response structure
//    - Cadence Stratus HLS (cynw_p2p 相当の vld/busy チャネル)
//      https://www.cadence.com/en_US/home/tools/digital-design-and-signoff/synthesis/stratus-high-level-synthesis.html
//=============================================================================
`timescale 1ns / 1ps

module axi4_full_to_p2p_bridge #(
  parameter int unsigned ADDR_WIDTH    = 32
 ,parameter int unsigned DATA_WIDTH    = 64
 ,parameter int unsigned ID_WIDTH      = 4
  // 送信 (Write → p2p out) / 受信 (p2p in → Read) FIFO の深さ。2 以上
 ,parameter int unsigned WR_FIFO_DEPTH = 16
 ,parameter int unsigned RD_FIFO_DEPTH = 16
  // 0 : 全ビートを送信 FIFO に積んだ時点で B 応答 (レイテンシ小)
  // 1 : 送信 FIFO が空になる (p2p へ出し切る) まで B 応答を待つ
 ,parameter bit          B_WAIT_DRAIN  = 1'b0
  // 0 : 無効 (データが来るまで RVALID を待たせる。AXI 的に合法)
  // >0: 指定サイクル数 p2p 入力が来なければ残りビートを SLVERR で返し切る
 ,parameter int unsigned RD_TIMEOUT    = 0
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                      aclk
 ,input  logic                      aresetn
  //---------------------------------------------------------------------------
  // AXI4-Full slave : Write address channel (AW)
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
  // AXI4-Full slave : Write data channel (W)
  //---------------------------------------------------------------------------
 ,input  logic [DATA_WIDTH-1:0]     s_axi_wdata
 ,input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb
 ,input  logic                      s_axi_wlast
 ,input  logic                      s_axi_wvalid
 ,output logic                      s_axi_wready
  //---------------------------------------------------------------------------
  // AXI4-Full slave : Write response channel (B)
  //---------------------------------------------------------------------------
 ,output logic [ID_WIDTH-1:0]       s_axi_bid
 ,output logic [1:0]                s_axi_bresp
 ,output logic                      s_axi_bvalid
 ,input  logic                      s_axi_bready
  //---------------------------------------------------------------------------
  // AXI4-Full slave : Read address channel (AR)
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
  // AXI4-Full slave : Read data channel (R)
  //---------------------------------------------------------------------------
 ,output logic [ID_WIDTH-1:0]       s_axi_rid
 ,output logic [DATA_WIDTH-1:0]     s_axi_rdata
 ,output logic [1:0]                s_axi_rresp
 ,output logic                      s_axi_rlast
 ,output logic                      s_axi_rvalid
 ,input  logic                      s_axi_rready
  //---------------------------------------------------------------------------
  // p2p 出力チャネル (AXI Write データの吐き出し先)
  //   strb / last は dat と同時に有効なサイドバンド。不要なら未接続でよい
  //---------------------------------------------------------------------------
 ,output logic [DATA_WIDTH-1:0]     p2p_out_dat
 ,output logic [(DATA_WIDTH/8)-1:0] p2p_out_strb
 ,output logic                      p2p_out_last
 ,output logic                      p2p_out_vld
 ,input  logic                      p2p_out_busy
  //---------------------------------------------------------------------------
  // p2p 入力チャネル (AXI Read データの供給元)
  //---------------------------------------------------------------------------
 ,input  logic [DATA_WIDTH-1:0]     p2p_in_dat
 ,input  logic                      p2p_in_vld
 ,output logic                      p2p_in_busy
  //---------------------------------------------------------------------------
  // ステータス
  //---------------------------------------------------------------------------
 ,output logic [$clog2(WR_FIFO_DEPTH+1)-1:0] wr_fifo_level
 ,output logic [$clog2(RD_FIFO_DEPTH+1)-1:0] rd_fifo_level
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
  localparam int unsigned WR_PL_W    = 1 + STRB_WIDTH + DATA_WIDTH; // {last,strb,data}
  localparam int unsigned WR_LVL_W   = $clog2(WR_FIFO_DEPTH+1);

  localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

  // Read タイムアウト
  localparam bit          RD_TO_EN  = (RD_TIMEOUT!=0);
  localparam int unsigned RD_TO_LIM = (RD_TIMEOUT<2) ? 1 : (RD_TIMEOUT - 1);
  localparam int unsigned TO_W      = (RD_TO_LIM<2) ? 1 : $clog2(RD_TO_LIM+1);

  //---------------------------------------------------------------------------
  // 送信 FIFO (AXI Write → p2p out)
  //---------------------------------------------------------------------------
  logic [WR_PL_W-1:0] wrf_wr_data;
  logic               wrf_wr_valid;
  logic               wrf_wr_ready;
  logic [WR_PL_W-1:0] wrf_rd_data;
  logic               wrf_rd_valid;
  logic               wrf_rd_ready;

  axi4_sync_fifo #(
    .WIDTH(WR_PL_W)
   ,.DEPTH(WR_FIFO_DEPTH)
  ) u_wr_fifo (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_data(wrf_wr_data)
   ,.wr_valid(wrf_wr_valid)
   ,.wr_ready(wrf_wr_ready)
   ,.rd_data(wrf_rd_data)
   ,.rd_valid(wrf_rd_valid)
   ,.rd_ready(wrf_rd_ready)
   ,.level(wr_fifo_level)
  );

  //---------------------------------------------------------------------------
  // 受信 FIFO (p2p in → AXI Read)
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] rdf_wr_data;
  logic                  rdf_wr_valid;
  logic                  rdf_wr_ready;
  logic [DATA_WIDTH-1:0] rdf_rd_data;
  logic                  rdf_rd_valid;
  logic                  rdf_rd_ready;

  axi4_sync_fifo #(
    .WIDTH(DATA_WIDTH)
   ,.DEPTH(RD_FIFO_DEPTH)
  ) u_rd_fifo (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_data(rdf_wr_data)
   ,.wr_valid(rdf_wr_valid)
   ,.wr_ready(rdf_wr_ready)
   ,.rd_data(rdf_rd_data)
   ,.rd_valid(rdf_rd_valid)
   ,.rd_ready(rdf_rd_ready)
   ,.level(rd_fifo_level)
  );

  //---------------------------------------------------------------------------
  // Write チャネル FSM (AXI → 送信 FIFO)
  //---------------------------------------------------------------------------
  typedef enum logic [1:0] {
     WR_IDLE = 2'd0
    ,WR_DATA = 2'd1
    ,WR_RESP = 2'd2
  } wr_state_e;

  wr_state_e           wr_state;
  logic [ID_WIDTH-1:0] wr_id;
  logic                wr_drained;

  assign wr_drained = (wr_fifo_level==WR_LVL_W'(0));

  assign s_axi_awready = (wr_state==WR_IDLE);
  assign s_axi_wready  = (wr_state==WR_DATA)&&wrf_wr_ready;
  assign wrf_wr_valid  = (wr_state==WR_DATA)&&s_axi_wvalid;
  assign wrf_wr_data   = {s_axi_wlast, s_axi_wstrb, s_axi_wdata};

  assign s_axi_bvalid  = (wr_state==WR_RESP)&&(!B_WAIT_DRAIN||wr_drained);
  assign s_axi_bid     = wr_id;
  assign s_axi_bresp   = AXI_RESP_OKAY;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      wr_state <= WR_IDLE;
      wr_id    <= {ID_WIDTH{1'b0}};
    end else begin
      case( wr_state )
        WR_IDLE : begin
          if( s_axi_awvalid ) begin
            wr_id    <= s_axi_awid;
            wr_state <= WR_DATA;
          end
        end
        WR_DATA : begin
          if( s_axi_wvalid&&s_axi_wready&&s_axi_wlast ) begin
            wr_state <= WR_RESP;
          end
        end
        WR_RESP : begin
          if( s_axi_bvalid&&s_axi_bready ) begin
            wr_state <= WR_IDLE;
          end
        end
        default : begin
          wr_state <= WR_IDLE;
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // p2p 出力チャネル (送信 FIFO → p2p)
  //   vld  : FIFO の登録値から生成。busy には組合せ依存しない
  //   転送 : vld=1 かつ busy=0 のクロックエッジで FIFO をポップする
  //---------------------------------------------------------------------------
  assign p2p_out_dat  = wrf_rd_data[DATA_WIDTH-1:0];
  assign p2p_out_strb = wrf_rd_data[DATA_WIDTH+:STRB_WIDTH];
  assign p2p_out_last = wrf_rd_data[DATA_WIDTH+STRB_WIDTH];
  assign p2p_out_vld  = wrf_rd_valid;
  assign wrf_rd_ready = !p2p_out_busy;

  //---------------------------------------------------------------------------
  // p2p 入力チャネル (p2p → 受信 FIFO)
  //   busy : FIFO 満杯で 1。vld には組合せ依存しない
  //---------------------------------------------------------------------------
  assign rdf_wr_data  = p2p_in_dat;
  assign rdf_wr_valid = p2p_in_vld;
  assign p2p_in_busy  = !rdf_wr_ready;

  //---------------------------------------------------------------------------
  // Read チャネル FSM (受信 FIFO → AXI)
  //---------------------------------------------------------------------------
  typedef enum logic [0:0] {
     RD_IDLE = 1'b0
    ,RD_DATA = 1'b1
  } rd_state_e;

  rd_state_e           rd_state;
  logic [ID_WIDTH-1:0] rd_id;
  logic [7:0]          rd_len;
  logic [7:0]          rd_cnt;
  logic [TO_W-1:0]     rd_to_cnt;
  logic                rd_to_err;

  assign s_axi_arready = (rd_state==RD_IDLE);
  assign s_axi_rvalid  = (rd_state==RD_DATA)&&(rdf_rd_valid||rd_to_err);
  assign s_axi_rdata   = rd_to_err ? {DATA_WIDTH{1'b0}} : rdf_rd_data;
  assign s_axi_rresp   = rd_to_err ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
  assign s_axi_rlast   = (rd_state==RD_DATA)&&(rd_cnt==rd_len);
  assign s_axi_rid     = rd_id;
  assign rdf_rd_ready  = (rd_state==RD_DATA)&&s_axi_rready&&!rd_to_err;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      rd_state  <= RD_IDLE;
      rd_id     <= {ID_WIDTH{1'b0}};
      rd_len    <= 8'd0;
      rd_cnt    <= 8'd0;
      rd_to_cnt <= {TO_W{1'b0}};
      rd_to_err <= 1'b0;
    end else begin
      case( rd_state )
        RD_IDLE : begin
          rd_to_cnt <= {TO_W{1'b0}};
          rd_to_err <= 1'b0;
          if( s_axi_arvalid ) begin
            rd_id    <= s_axi_arid;
            rd_len   <= s_axi_arlen;
            rd_cnt   <= 8'd0;
            rd_state <= RD_DATA;
          end
        end
        RD_DATA : begin
          // データ待ちの経過サイクルを数える
          if( rdf_rd_valid ) begin
            rd_to_cnt <= {TO_W{1'b0}};
          end else if( RD_TO_EN&&!rd_to_err ) begin
            if( rd_to_cnt==TO_W'(RD_TO_LIM) ) begin
              rd_to_err <= 1'b1;
            end else begin
              rd_to_cnt <= rd_to_cnt + TO_W'(1);
            end
          end
          // ビート進行
          if( s_axi_rvalid&&s_axi_rready ) begin
            if( rd_cnt==rd_len ) begin
              rd_state <= RD_IDLE;
            end else begin
              rd_cnt <= rd_cnt + 8'd1;
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
  // 未使用入力
  //   本モジュールは FIFO ポートとして振る舞うため、アドレス属性は使用しない
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{ 1'b0
                      , s_axi_awaddr, s_axi_awlen  , s_axi_awsize
                      , s_axi_awburst, s_axi_awlock, s_axi_awcache
                      , s_axi_awprot , s_axi_awqos , s_axi_awregion
                      , s_axi_araddr , s_axi_arsize, s_axi_arburst
                      , s_axi_arlock , s_axi_arcache, s_axi_arprot
                      , s_axi_arqos  , s_axi_arregion };

endmodule

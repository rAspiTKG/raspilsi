//=============================================================================
// axi4_mst_wr_engine.sv
//-----------------------------------------------------------------------------
//  AXI4-Full マスタ書き込みエンジン。
//  コマンド (先頭アドレス + ビート数) を受け、valid/ready で受け取ったデータを
//  AW / W / B チャネルで書き込む。
//
//  動作:
//    - コマンドは cmd_valid / cmd_ready で受ける (アイドル時のみ cmd_ready=1)
//    - 転送を INCR バーストに分割する。1 バーストの長さは
//        min(残りビート数, MAX_BURST, 4KB 境界までのビート数)
//      (AXI4 spec A3.4.1: バーストは 4KB 境界を跨いではならない)
//    - 1 バースト分のデータが揃ってから AW を出す (s_count >= バースト長)
//      → AW を出したのに W が出せず、スレーブの書き込みチャネルを塞ぐのを防ぐ
//    - AW と W は同時に出す。B を受けてから次のバーストへ進む
//      (アウトスタンディングは 1)
//    - 完了時に done を 1 サイクル出す。BRESP != OKAY または BID 不一致が
//      1 回でもあれば done_err=1
//
//  ハンドシェイク (AXI4 spec A3.2.1):
//    - AWVALID は登録値。READY に組合せ依存しない
//    - WVALID は s_valid から生成 (VALID -> VALID)、s_ready は WREADY から生成
//      (READY -> READY)。データ源が valid を保持する限り WVALID も保持される
//
//  制約:
//    - アドレスはバス幅 (DATA_WIDTH/8 バイト) にアラインしていること
//      (下位ビットは切り捨てる)。cmd_len はビート数 (0 なら即完了)
//    - WSTRB は常に全バイト有効
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//        https://developer.arm.com/documentation/ihi0022/latest/
//=============================================================================
`timescale 1ns / 1ps

module axi4_mst_wr_engine #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned AXI_ID     = 0
 ,parameter int unsigned LEN_WIDTH  = 16
 ,parameter int unsigned CNT_WIDTH  = 16
 ,parameter int unsigned MAX_BURST  = 16
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                      aclk
 ,input  logic                      aresetn
  //---------------------------------------------------------------------------
  // コマンド / ステータス
  //---------------------------------------------------------------------------
 ,input  logic                      cmd_valid
 ,output logic                      cmd_ready
 ,input  logic [ADDR_WIDTH-1:0]     cmd_addr
 ,input  logic [LEN_WIDTH-1:0]      cmd_len
 ,output logic                      busy
 ,output logic                      done
 ,output logic                      done_err
  //---------------------------------------------------------------------------
  // 書き込みデータ入力 (valid/ready)
  //   s_count : 現在受け取れるビート数 (FIFO の格納数など)
  //---------------------------------------------------------------------------
 ,input  logic [DATA_WIDTH-1:0]     s_data
 ,input  logic                      s_valid
 ,output logic                      s_ready
 ,input  logic [CNT_WIDTH-1:0]      s_count
  //---------------------------------------------------------------------------
  // AXI4 master : Write address channel
  //---------------------------------------------------------------------------
 ,output logic [ID_WIDTH-1:0]       m_axi_awid
 ,output logic [ADDR_WIDTH-1:0]     m_axi_awaddr
 ,output logic [7:0]                m_axi_awlen
 ,output logic [2:0]                m_axi_awsize
 ,output logic [1:0]                m_axi_awburst
 ,output logic                      m_axi_awlock
 ,output logic [3:0]                m_axi_awcache
 ,output logic [2:0]                m_axi_awprot
 ,output logic [3:0]                m_axi_awqos
 ,output logic [3:0]                m_axi_awregion
 ,output logic                      m_axi_awvalid
 ,input  logic                      m_axi_awready
  //---------------------------------------------------------------------------
  // AXI4 master : Write data channel
  //---------------------------------------------------------------------------
 ,output logic [DATA_WIDTH-1:0]     m_axi_wdata
 ,output logic [(DATA_WIDTH/8)-1:0] m_axi_wstrb
 ,output logic                      m_axi_wlast
 ,output logic                      m_axi_wvalid
 ,input  logic                      m_axi_wready
  //---------------------------------------------------------------------------
  // AXI4 master : Write response channel
  //---------------------------------------------------------------------------
 ,input  logic [ID_WIDTH-1:0]       m_axi_bid
 ,input  logic [1:0]                m_axi_bresp
 ,input  logic                      m_axi_bvalid
 ,output logic                      m_axi_bready
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_W   = DATA_WIDTH / 8;
  localparam int unsigned ADDR_LSB = $clog2(STRB_W);

  localparam logic [1:0] AXI_BURST_INCR = 2'b01;
  localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;

  typedef enum logic [2:0] {
     S_IDLE  = 3'd0
    ,S_CALC  = 3'd1
    ,S_WAIT  = 3'd2
    ,S_BURST = 3'd3
    ,S_RESP  = 3'd4
    ,S_DONE  = 3'd5
  } state_e;

  //---------------------------------------------------------------------------
  // Registers
  //---------------------------------------------------------------------------
  state_e                state;
  logic [ADDR_WIDTH-1:0] cur_addr;    // 次のバーストの先頭アドレス
  logic [LEN_WIDTH-1:0]  rem;         // 残りビート数
  logic [8:0]            burst_len;   // 現在のバースト長 (1..256)
  logic [8:0]            w_cnt;       // 現在のバーストで送った W ビート数
  logic                  aw_pend;     // AW 握手待ち
  logic                  w_act;       // W 送出中
  logic                  err;

  //---------------------------------------------------------------------------
  // バースト長の計算: min(残り, MAX_BURST, 4KB 境界まで)
  //---------------------------------------------------------------------------
  logic [31:0] rem32;
  logic [31:0] b4k32;
  logic [31:0] bl32;

  assign rem32 = 32'(rem);
  assign b4k32 = (32'd4096 - 32'(cur_addr[11:0])) >> ADDR_LSB;

  always_comb begin
    bl32 = 32'(MAX_BURST);
    if( rem32<bl32 ) begin
      bl32 = rem32;
    end
    if( b4k32<bl32 ) begin
      bl32 = b4k32;
    end
  end

  //---------------------------------------------------------------------------
  // AXI 出力
  //---------------------------------------------------------------------------
  logic w_hs;
  logic w_last_beat;

  assign m_axi_awid     = ID_WIDTH'(AXI_ID);
  assign m_axi_awaddr   = cur_addr;
  assign m_axi_awlen    = 8'(burst_len - 9'd1);
  assign m_axi_awsize   = 3'(ADDR_LSB);
  assign m_axi_awburst  = AXI_BURST_INCR;
  assign m_axi_awlock   = 1'b0;
  assign m_axi_awcache  = 4'b0011;
  assign m_axi_awprot   = 3'b000;
  assign m_axi_awqos    = 4'd0;
  assign m_axi_awregion = 4'd0;
  assign m_axi_awvalid  = aw_pend;

  assign w_hs           = m_axi_wvalid&&m_axi_wready;
  assign w_last_beat    = (w_cnt==(burst_len-9'd1));
  assign m_axi_wvalid   = (state==S_BURST)&&w_act&&s_valid;
  assign m_axi_wdata    = s_data;
  assign m_axi_wstrb    = {STRB_W{1'b1}};
  assign m_axi_wlast    = w_last_beat;
  assign s_ready        = (state==S_BURST)&&w_act&&m_axi_wready;

  assign m_axi_bready   = (state==S_RESP);

  //---------------------------------------------------------------------------
  // ステータス
  //---------------------------------------------------------------------------
  assign cmd_ready = (state==S_IDLE);
  assign busy      = (state!=S_IDLE);
  assign done      = (state==S_DONE);
  assign done_err  = err;

  //---------------------------------------------------------------------------
  // FSM
  //---------------------------------------------------------------------------
  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      state     <= S_IDLE;
      cur_addr  <= {ADDR_WIDTH{1'b0}};
      rem       <= {LEN_WIDTH{1'b0}};
      burst_len <= 9'd0;
      w_cnt     <= 9'd0;
      aw_pend   <= 1'b0;
      w_act     <= 1'b0;
      err       <= 1'b0;
    end else begin
      case( state )
        S_IDLE : begin
          if( cmd_valid ) begin
            cur_addr <= {cmd_addr[ADDR_WIDTH-1:ADDR_LSB], {ADDR_LSB{1'b0}}};
            rem      <= cmd_len;
            err      <= 1'b0;
            if( cmd_len=={LEN_WIDTH{1'b0}} ) begin
              state <= S_DONE;
            end else begin
              state <= S_CALC;
            end
          end
        end
        S_CALC : begin
          burst_len <= bl32[8:0];
          state     <= S_WAIT;
        end
        S_WAIT : begin
          // 1 バースト分のデータが揃ってから AW を出す
          if( 32'(s_count)>=32'(burst_len) ) begin
            aw_pend <= 1'b1;
            w_act   <= 1'b1;
            w_cnt   <= 9'd0;
            state   <= S_BURST;
          end
        end
        S_BURST : begin
          if( m_axi_awvalid&&m_axi_awready ) begin
            aw_pend <= 1'b0;
          end
          if( w_hs ) begin
            w_cnt <= w_cnt + 9'd1;
            if( w_last_beat ) begin
              w_act <= 1'b0;
            end
          end
          // AW と最終 W の両方が終わったら B 待ちへ
          if( (!aw_pend||m_axi_awready)&&(!w_act||(w_hs&&w_last_beat)) ) begin
            state <= S_RESP;
          end
        end
        S_RESP : begin
          if( m_axi_bvalid ) begin
            if( (m_axi_bresp!=AXI_RESP_OKAY)||(m_axi_bid!=ID_WIDTH'(AXI_ID)) ) begin
              err <= 1'b1;
            end
            cur_addr <= cur_addr + (ADDR_WIDTH'(burst_len) << ADDR_LSB);
            rem      <= rem - LEN_WIDTH'(burst_len);
            if( rem==LEN_WIDTH'(burst_len) ) begin
              state <= S_DONE;
            end else begin
              state <= S_CALC;
            end
          end
        end
        S_DONE : begin
          state <= S_IDLE;
        end
        default : begin
          state <= S_IDLE;
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // 未使用入力 (アライン外の下位アドレスビットは捨てる)
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{1'b0, cmd_addr[ADDR_LSB-1:0]};

  //---------------------------------------------------------------------------
  // エラボレーション時チェック
  //---------------------------------------------------------------------------
  initial begin
    if( (MAX_BURST<1)||(MAX_BURST>256) ) begin
      $error("axi4_mst_wr_engine : MAX_BURST must be 1..256 (MAX_BURST=%0d)", MAX_BURST);
    end
  end

endmodule

//=============================================================================
// axi4_lb_rd_engine.sv
//-----------------------------------------------------------------------------
//  AXI4 マスタ読み出しエンジン (AR / R)。
//  コマンド (先頭アドレス + ビート数) を受け、読み出したデータを valid/ready で出す。
//
//  動作:
//    - コマンドは cmd_valid / cmd_ready で受ける (アイドル時のみ cmd_ready=1)
//    - 転送を INCR バーストに分割する。1 バーストの長さは
//        min(残りビート数, MAX_BURST, 4KB 境界までのビート数)
//      (AXI 仕様: バーストは 4KB 境界を跨いではならない)
//    - 出力先に 1 バースト分の空きがあるときだけ AR を出す (m_space >= バースト長)
//      → R を受け取れずに読み出しチャネルを塞ぐことがない
//    - 1 バースト受け終わってから次の AR を出す (アウトスタンディングは 1)
//    - m_last はコマンド全体の最終ビートで 1
//    - 完了時に done を 1 サイクル出す。RRESP != OKAY、RID 不一致、
//      RLAST の位置ずれが 1 回でもあれば done_err=1
//
//  ハンドシェイク:
//    - ARVALID はステート (登録値) から生成。ARREADY に組合せ依存しない
//    - m_valid は RVALID から (VALID -> VALID)、RREADY は m_ready から (READY -> READY)
//
//  制約:
//    - cmd_addr はバス幅 (DATA_WIDTH/8 バイト) にアラインしていること
//      (下位ビットは 0 として扱う)。cmd_len はビート数 (0 なら即完了)
//=============================================================================
`timescale 1ns / 1ps

module axi4_lb_rd_engine #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned AXI_ID     = 0
 ,parameter int unsigned LEN_WIDTH  = 16
 ,parameter int unsigned CNT_WIDTH  = 16
 ,parameter int unsigned MAX_BURST  = 16
 ,parameter logic [3:0]  AXCACHE    = 4'b0011
 ,parameter logic [2:0]  AXPROT     = 3'b000
 ,parameter logic [3:0]  AXQOS      = 4'd0
 ,parameter logic [3:0]  AXREGION   = 4'd0
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                  aclk
 ,input  logic                  aresetn
  //---------------------------------------------------------------------------
  // コマンド / ステータス
  //---------------------------------------------------------------------------
 ,input  logic                  cmd_valid
 ,output logic                  cmd_ready
 ,input  logic [ADDR_WIDTH-1:0] cmd_addr
 ,input  logic [LEN_WIDTH-1:0]  cmd_len
 ,output logic                  busy
 ,output logic                  done
 ,output logic                  done_err
  //---------------------------------------------------------------------------
  // 読み出しデータ出力 (valid/ready)
  //   m_space : 出力先がいま受け取れるビート数 (FIFO の空き数)
  //---------------------------------------------------------------------------
 ,output logic [DATA_WIDTH-1:0] m_data
 ,output logic                  m_last
 ,output logic                  m_valid
 ,input  logic                  m_ready
 ,input  logic [CNT_WIDTH-1:0]  m_space
  //---------------------------------------------------------------------------
  // AXI4 master : Read address channel
  //---------------------------------------------------------------------------
 ,output logic [ID_WIDTH-1:0]   m_axi_arid
 ,output logic [ADDR_WIDTH-1:0] m_axi_araddr
 ,output logic [7:0]            m_axi_arlen
 ,output logic [2:0]            m_axi_arsize
 ,output logic [1:0]            m_axi_arburst
 ,output logic                  m_axi_arlock
 ,output logic [3:0]            m_axi_arcache
 ,output logic [2:0]            m_axi_arprot
 ,output logic [3:0]            m_axi_arqos
 ,output logic [3:0]            m_axi_arregion
 ,output logic                  m_axi_arvalid
 ,input  logic                  m_axi_arready
  //---------------------------------------------------------------------------
  // AXI4 master : Read data channel
  //---------------------------------------------------------------------------
 ,input  logic [ID_WIDTH-1:0]   m_axi_rid
 ,input  logic [DATA_WIDTH-1:0] m_axi_rdata
 ,input  logic [1:0]            m_axi_rresp
 ,input  logic                  m_axi_rlast
 ,input  logic                  m_axi_rvalid
 ,output logic                  m_axi_rready
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_W   = DATA_WIDTH / 8;
  localparam int unsigned ADDR_LSB = $clog2(STRB_W);

  localparam logic [1:0] AXI_BURST_INCR = 2'b01;
  localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;

  // アライン用マスク (下位 ADDR_LSB ビットが 0)
  localparam logic [ADDR_WIDTH-1:0] ALIGN_MASK = ~ADDR_WIDTH'(STRB_W-1);

  typedef enum logic [2:0] {
    S_IDLE = 3'd0
   ,S_CALC = 3'd1
   ,S_WAIT = 3'd2
   ,S_ADDR = 3'd3
   ,S_DATA = 3'd4
   ,S_DONE = 3'd5
  } state_e;

  //---------------------------------------------------------------------------
  // Registers
  //---------------------------------------------------------------------------
  state_e                state;
  logic [ADDR_WIDTH-1:0] cur_addr;    // 次のバーストの先頭アドレス
  logic [LEN_WIDTH-1:0]  rem;         // 残りビート数
  logic [8:0]            burst_len;   // 現在のバースト長 (1..256)
  logic [8:0]            r_cnt;       // 現在のバーストで受けた R ビート数
  logic                  err;

  //---------------------------------------------------------------------------
  // バースト長の計算: min(残り, MAX_BURST, 4KB 境界まで)
  //---------------------------------------------------------------------------
  logic [31:0] rem32;
  logic [31:0] b4k32;
  logic [31:0] bl32;

  assign rem32 = 32'(rem);
  assign b4k32 = (32'd4096 - 32'(cur_addr[11:0])) >> ADDR_LSB;

  always @(*) begin
    bl32 = 32'(MAX_BURST);
    if( rem32<bl32 ) begin
      bl32 = rem32;
    end
    if( b4k32<bl32 ) begin
      bl32 = b4k32;
    end
  end

  //---------------------------------------------------------------------------
  // AXI 出力 / データ出力
  //---------------------------------------------------------------------------
  logic r_hs;
  logic r_last_beat;

  assign m_axi_arid     = ID_WIDTH'(AXI_ID);
  assign m_axi_araddr   = cur_addr;
  assign m_axi_arlen    = 8'(burst_len - 9'd1);
  assign m_axi_arsize   = 3'(ADDR_LSB);
  assign m_axi_arburst  = AXI_BURST_INCR;
  assign m_axi_arlock   = 1'b0;
  assign m_axi_arcache  = AXCACHE;
  assign m_axi_arprot   = AXPROT;
  assign m_axi_arqos    = AXQOS;
  assign m_axi_arregion = AXREGION;
  assign m_axi_arvalid  = (state==S_ADDR);

  assign r_hs           = m_axi_rvalid&&m_axi_rready;
  assign r_last_beat    = (r_cnt==(burst_len-9'd1));
  assign m_axi_rready   = (state==S_DATA)&&m_ready;
  assign m_valid        = (state==S_DATA)&&m_axi_rvalid;
  assign m_data         = m_axi_rdata;
  assign m_last         = r_last_beat&&(rem==LEN_WIDTH'(burst_len));

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
  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      state     <= S_IDLE;
      cur_addr  <= {ADDR_WIDTH{1'b0}};
      rem       <= {LEN_WIDTH{1'b0}};
      burst_len <= 9'd0;
      r_cnt     <= 9'd0;
      err       <= 1'b0;
    end else begin
      case( state )
        S_IDLE : begin
          if( cmd_valid ) begin
            cur_addr <= cmd_addr & ALIGN_MASK;
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
          // 出力先に 1 バースト分の空きができてから AR を出す
          if( 32'(m_space)>=32'(burst_len) ) begin
            state <= S_ADDR;
          end
        end
        S_ADDR : begin
          if( m_axi_arready ) begin
            r_cnt <= 9'd0;
            state <= S_DATA;
          end
        end
        S_DATA : begin
          if( r_hs ) begin
            if( (m_axi_rresp!=AXI_RESP_OKAY)||(m_axi_rid!=ID_WIDTH'(AXI_ID))||(m_axi_rlast!=r_last_beat) ) begin
              err <= 1'b1;
            end
            r_cnt <= r_cnt + 9'd1;
            if( r_last_beat ) begin
              cur_addr <= cur_addr + (ADDR_WIDTH'(burst_len) << ADDR_LSB);
              rem      <= rem - LEN_WIDTH'(burst_len);
              if( rem==LEN_WIDTH'(burst_len) ) begin
                state <= S_DONE;
              end else begin
                state <= S_CALC;
              end
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
  // 未使用ビット (bl32 は下位 9 ビットだけ使う)
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{1'b0, bl32[31:9]};

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時。IEEE 1800 20.11)
  //---------------------------------------------------------------------------
`ifndef AXI4_LB_NO_ELAB_CHECK
  generate
    if( (MAX_BURST<1)||(MAX_BURST>256) ) begin : g_chk_burst
      $error("axi4_lb_rd_engine : MAX_BURST must be 1..256 (MAX_BURST=%0d)", MAX_BURST);
    end
    if( ADDR_WIDTH<12 ) begin : g_chk_addr
      $error("axi4_lb_rd_engine : ADDR_WIDTH must be >= 12 (ADDR_WIDTH=%0d)", ADDR_WIDTH);
    end
  endgenerate
`endif

endmodule

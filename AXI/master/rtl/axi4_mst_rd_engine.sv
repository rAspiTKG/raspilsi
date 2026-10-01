//=============================================================================
// axi4_mst_rd_engine.sv
//-----------------------------------------------------------------------------
//  AXI4-Full マスタ読み出しエンジン。
//  コマンド (先頭アドレス + ビート数) を受け、AR / R チャネルで読み出した
//  データを valid/ready で出力する。
//
//  動作:
//    - コマンドは cmd_valid / cmd_ready で受ける (アイドル時のみ cmd_ready=1)
//    - 転送を INCR バーストに分割する。1 バーストの長さは
//        min(残りビート数, MAX_BURST, 4KB 境界までのビート数)
//    - 出力先に 1 バースト分の空きがあるときだけ AR を出す
//      (m_space >= バースト長) → R を受け取れずにスレーブの読み出しチャネルを
//      塞ぐのを防ぐ
//    - 1 バースト受け終わってから次の AR を出す (アウトスタンディングは 1)
//    - m_last はコマンド全体の最終ビートで 1
//    - 完了時に done を 1 サイクル出す。RRESP != OKAY、RID 不一致、
//      RLAST の位置ずれが 1 回でもあれば done_err=1
//
//  ハンドシェイク (AXI4 spec A3.2.1):
//    - ARVALID は登録値 (ステート) から生成
//    - m_valid は RVALID から生成 (VALID -> VALID)、RREADY は m_ready から生成
//      (READY -> READY)
//
//  制約:
//    - アドレスはバス幅 (DATA_WIDTH/8 バイト) にアラインしていること
//      (下位ビットは切り捨てる)。cmd_len はビート数 (0 なら即完了)
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//        https://developer.arm.com/documentation/ihi0022/latest/
//=============================================================================
`timescale 1ns / 1ps

module axi4_mst_rd_engine #(
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
  // 読み出しデータ出力 (valid/ready)
  //   m_space : 出力先がいま受け取れるビート数 (FIFO の空き数など)
  //---------------------------------------------------------------------------
 ,output logic [DATA_WIDTH-1:0]     m_data
 ,output logic                      m_last
 ,output logic                      m_valid
 ,input  logic                      m_ready
 ,input  logic [CNT_WIDTH-1:0]      m_space
  //---------------------------------------------------------------------------
  // AXI4 master : Read address channel
  //---------------------------------------------------------------------------
 ,output logic [ID_WIDTH-1:0]       m_axi_arid
 ,output logic [ADDR_WIDTH-1:0]     m_axi_araddr
 ,output logic [7:0]                m_axi_arlen
 ,output logic [2:0]                m_axi_arsize
 ,output logic [1:0]                m_axi_arburst
 ,output logic                      m_axi_arlock
 ,output logic [3:0]                m_axi_arcache
 ,output logic [2:0]                m_axi_arprot
 ,output logic [3:0]                m_axi_arqos
 ,output logic [3:0]                m_axi_arregion
 ,output logic                      m_axi_arvalid
 ,input  logic                      m_axi_arready
  //---------------------------------------------------------------------------
  // AXI4 master : Read data channel
  //---------------------------------------------------------------------------
 ,input  logic [ID_WIDTH-1:0]       m_axi_rid
 ,input  logic [DATA_WIDTH-1:0]     m_axi_rdata
 ,input  logic [1:0]                m_axi_rresp
 ,input  logic                      m_axi_rlast
 ,input  logic                      m_axi_rvalid
 ,output logic                      m_axi_rready
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_W   = DATA_WIDTH / 8;
  localparam int unsigned ADDR_LSB = $clog2(STRB_W);

  localparam logic [1:0] AXI_BURST_INCR = 2'b01;
  localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;

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
  logic [ADDR_WIDTH-1:0] cur_addr;
  logic [LEN_WIDTH-1:0]  rem;
  logic [8:0]            burst_len;
  logic [8:0]            r_cnt;
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
  assign m_axi_arcache  = 4'b0011;
  assign m_axi_arprot   = 3'b000;
  assign m_axi_arqos    = 4'd0;
  assign m_axi_arregion = 4'd0;
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
  always_ff @(posedge aclk or negedge aresetn) begin
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
  // 未使用入力 (アライン外の下位アドレスビットは捨てる)
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{1'b0, cmd_addr[ADDR_LSB-1:0]};

  //---------------------------------------------------------------------------
  // エラボレーション時チェック
  //---------------------------------------------------------------------------
  initial begin
    if( (MAX_BURST<1)||(MAX_BURST>256) ) begin
      $error("axi4_mst_rd_engine : MAX_BURST must be 1..256 (MAX_BURST=%0d)", MAX_BURST);
    end
  end

endmodule

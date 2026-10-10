//=============================================================================
// axil_master_engine.sv
//-----------------------------------------------------------------------------
//  AXI4-Lite マスタ (Manager) の転送エンジン。
//  書き込みと読み出しは独立していて、同時に動く。
//
//      wreq_* (valid/ready) --> [AW スライス] --> AW
//                           \-> [W スライス]  --> W
//      wrsp_* (パルス)      <-------------------- B
//      rreq_* (valid/ready) --> [AR スライス] --> AR
//      rrsp_* (パルス)      <-------------------- R
//
//  要求 / 応答:
//    - 1 要求 = 1 トランザクション (AXI4-Lite は常に 1 ビート、データバス幅いっぱい)
//    - 応答を待たずに、書き込みは MAX_WR_OUTSTANDING 個、読み出しは MAX_RD_OUTSTANDING 個まで
//      要求を受け付ける (受け付けてから応答を受けるまでを 1 個と数える)
//    - 応答は要求を受けた順に、B / R を受けた次のサイクルに 1 サイクルだけ出す
//      (AXI4-Lite には ID が無いので、スレーブは同じ方向の応答を要求の順に返す)
//    - BREADY / RREADY は常に 1。応答に待ったはかけられないので、wrsp_* / rrsp_* は毎サイクル受け取ること
//    - wreq_ready / rreq_ready はレジスタだけで決まる (AXI の READY には組合せで依存しない)
//
//  AXI 側:
//    - AWVALID / WVALID / ARVALID と、そのアドレス / データはレジスタスライスから直接出す
//      (VALID を出したら READY まで下げず、その間ペイロードも変えない)
//    - AW と W は同じ要求から同時に出すが、それぞれ独立に READY を待つ
//      (AWREADY を待ってから WVALID を出す、ということはしない)
//    - AWREADY / WREADY / ARREADY が毎サイクル 1 なら、1 サイクルに 1 トランザクション出せる
//      (応答の待ちを隠すには、MAX_*_OUTSTANDING を「L + 3」以上にする。L はスレーブが AW と W
//       (AR) を受けたサイクルの次から BVALID (RVALID) を出すまでの待ち。次のサイクルに出すなら 0。
//       要求を受け付けてから応答を受けるまで L + 2 サイクルかかり、その間に出したものが未完了になるため)
//
//  axi_wakeup:
//    要求を受けてから全ての応答を受けるまで 1 になるレジスタ出力。AWVALID / ARVALID より
//    遅れずに立つ。AXI5 の AWAKEUP が必要な相手 (NI-700 など) につなぐときに使う
//    (axil_to_axi4.sv を参照)。AXI4-Lite だけで使うなら未接続でよい
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//=============================================================================
`timescale 1ns / 1ps

module axil_master_engine #(
  parameter int unsigned ADDR_WIDTH         = 32
 ,parameter int unsigned DATA_WIDTH         = 32
 ,parameter int unsigned MAX_WR_OUTSTANDING = 4
 ,parameter int unsigned MAX_RD_OUTSTANDING = 4
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                      aclk
 ,input  logic                      aresetn
  //---------------------------------------------------------------------------
  // 書き込み要求 (valid/ready)
  //---------------------------------------------------------------------------
 ,input  logic                      wreq_valid
 ,output logic                      wreq_ready
 ,input  logic [ADDR_WIDTH-1:0]     wreq_addr
 ,input  logic [DATA_WIDTH-1:0]     wreq_data
 ,input  logic [(DATA_WIDTH/8)-1:0] wreq_strb
 ,input  logic [2:0]                wreq_prot
  //---------------------------------------------------------------------------
  // 書き込み応答 (wrsp_valid は 1 サイクル)
  //---------------------------------------------------------------------------
 ,output logic                      wrsp_valid
 ,output logic [1:0]                wrsp_resp
  //---------------------------------------------------------------------------
  // 読み出し要求 (valid/ready)
  //---------------------------------------------------------------------------
 ,input  logic                      rreq_valid
 ,output logic                      rreq_ready
 ,input  logic [ADDR_WIDTH-1:0]     rreq_addr
 ,input  logic [2:0]                rreq_prot
  //---------------------------------------------------------------------------
  // 読み出し応答 (rrsp_valid は 1 サイクル)
  //---------------------------------------------------------------------------
 ,output logic                      rrsp_valid
 ,output logic [DATA_WIDTH-1:0]     rrsp_data
 ,output logic [1:0]                rrsp_resp
  //---------------------------------------------------------------------------
  // ステータス
  //---------------------------------------------------------------------------
 ,output logic                      wr_busy
 ,output logic                      rd_busy
 ,output logic                      axi_wakeup
  //---------------------------------------------------------------------------
  // AXI4-Lite master
  //---------------------------------------------------------------------------
 ,output logic [ADDR_WIDTH-1:0]     m_axi_awaddr
 ,output logic [2:0]                m_axi_awprot
 ,output logic                      m_axi_awvalid
 ,input  logic                      m_axi_awready
 ,output logic [DATA_WIDTH-1:0]     m_axi_wdata
 ,output logic [(DATA_WIDTH/8)-1:0] m_axi_wstrb
 ,output logic                      m_axi_wvalid
 ,input  logic                      m_axi_wready
 ,input  logic [1:0]                m_axi_bresp
 ,input  logic                      m_axi_bvalid
 ,output logic                      m_axi_bready
 ,output logic [ADDR_WIDTH-1:0]     m_axi_araddr
 ,output logic [2:0]                m_axi_arprot
 ,output logic                      m_axi_arvalid
 ,input  logic                      m_axi_arready
 ,input  logic [DATA_WIDTH-1:0]     m_axi_rdata
 ,input  logic [1:0]                m_axi_rresp
 ,input  logic                      m_axi_rvalid
 ,output logic                      m_axi_rready
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_W = DATA_WIDTH / 8;
  // (MAX_*_OUTSTANDING が 0 のときもビット幅を 1 にして、下のパラメータチェックでエラーにする)
  localparam int unsigned WCNT_W = (MAX_WR_OUTSTANDING<1) ? 1 : $clog2(MAX_WR_OUTSTANDING+1);
  localparam int unsigned RCNT_W = (MAX_RD_OUTSTANDING<1) ? 1 : $clog2(MAX_RD_OUTSTANDING+1);

  //---------------------------------------------------------------------------
  // 書き込み
  //---------------------------------------------------------------------------
  logic              aw_s_ready;
  logic              w_s_ready;
  logic              wreq_fire;
  logic              b_fire;
  logic [WCNT_W-1:0] wr_cnt;        // 受け付けて、まだ B を受けていない要求の数
  logic [WCNT_W-1:0] wr_cnt_nxt;

  assign wreq_ready = aw_s_ready&&w_s_ready&&(wr_cnt<WCNT_W'(MAX_WR_OUTSTANDING));
  assign wreq_fire  = wreq_valid&&wreq_ready;
  assign b_fire     = m_axi_bvalid&&m_axi_bready;

  always @(*) begin
    wr_cnt_nxt = wr_cnt;
    if( wreq_fire&&!b_fire ) begin
      wr_cnt_nxt = wr_cnt + WCNT_W'(1);
    end else if( !wreq_fire&&b_fire ) begin
      wr_cnt_nxt = wr_cnt - WCNT_W'(1);
    end
  end

  // AW と W は同じ要求から同時に入れ、出口では独立に READY を待つ
  axil_master_rs #(
    .WIDTH(ADDR_WIDTH+3)
  ) u_aw_rs (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.s_valid(wreq_fire)
   ,.s_ready(aw_s_ready)
   ,.s_data({wreq_prot, wreq_addr})
   ,.m_valid(m_axi_awvalid)
   ,.m_ready(m_axi_awready)
   ,.m_data({m_axi_awprot, m_axi_awaddr})
  );

  axil_master_rs #(
    .WIDTH(DATA_WIDTH+STRB_W)
  ) u_w_rs (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.s_valid(wreq_fire)
   ,.s_ready(w_s_ready)
   ,.s_data({wreq_strb, wreq_data})
   ,.m_valid(m_axi_wvalid)
   ,.m_ready(m_axi_wready)
   ,.m_data({m_axi_wstrb, m_axi_wdata})
  );

  assign m_axi_bready = 1'b1;

  //---------------------------------------------------------------------------
  // 読み出し
  //---------------------------------------------------------------------------
  logic              ar_s_ready;
  logic              rreq_fire;
  logic              r_fire;
  logic [RCNT_W-1:0] rd_cnt;        // 受け付けて、まだ R を受けていない要求の数
  logic [RCNT_W-1:0] rd_cnt_nxt;

  assign rreq_ready = ar_s_ready&&(rd_cnt<RCNT_W'(MAX_RD_OUTSTANDING));
  assign rreq_fire  = rreq_valid&&rreq_ready;
  assign r_fire     = m_axi_rvalid&&m_axi_rready;

  always @(*) begin
    rd_cnt_nxt = rd_cnt;
    if( rreq_fire&&!r_fire ) begin
      rd_cnt_nxt = rd_cnt + RCNT_W'(1);
    end else if( !rreq_fire&&r_fire ) begin
      rd_cnt_nxt = rd_cnt - RCNT_W'(1);
    end
  end

  axil_master_rs #(
    .WIDTH(ADDR_WIDTH+3)
  ) u_ar_rs (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.s_valid(rreq_fire)
   ,.s_ready(ar_s_ready)
   ,.s_data({rreq_prot, rreq_addr})
   ,.m_valid(m_axi_arvalid)
   ,.m_ready(m_axi_arready)
   ,.m_data({m_axi_arprot, m_axi_araddr})
  );

  assign m_axi_rready = 1'b1;

  //---------------------------------------------------------------------------
  // カウンタ / 応答 / wakeup
  //---------------------------------------------------------------------------
  logic wakeup_q;

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      wr_cnt     <= {WCNT_W{1'b0}};
      rd_cnt     <= {RCNT_W{1'b0}};
      wrsp_valid <= 1'b0;
      wrsp_resp  <= 2'b00;
      rrsp_valid <= 1'b0;
      rrsp_data  <= {DATA_WIDTH{1'b0}};
      rrsp_resp  <= 2'b00;
      wakeup_q   <= 1'b0;
    end else begin
      wr_cnt     <= wr_cnt_nxt;
      rd_cnt     <= rd_cnt_nxt;
      wrsp_valid <= b_fire;
      if( b_fire ) begin
        wrsp_resp <= m_axi_bresp;
      end
      rrsp_valid <= r_fire;
      if( r_fire ) begin
        rrsp_data <= m_axi_rdata;
        rrsp_resp <= m_axi_rresp;
      end
      // 要求を受けたエッジで立つので、AWVALID / ARVALID (スライスの出力) と同じエッジになる
      wakeup_q <= (wr_cnt_nxt!={WCNT_W{1'b0}})||(rd_cnt_nxt!={RCNT_W{1'b0}});
    end
  end

  assign wr_busy    = (wr_cnt!={WCNT_W{1'b0}});
  assign rd_busy    = (rd_cnt!={RCNT_W{1'b0}});
  assign axi_wakeup = wakeup_q;

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時。IEEE 1800 20.11)
  //   対応していない合成ツールでは +define+AXIL_MASTER_NO_ELAB_CHECK で外す
  //---------------------------------------------------------------------------
`ifndef AXIL_MASTER_NO_ELAB_CHECK
  generate
    if( (DATA_WIDTH!=32)&&(DATA_WIDTH!=64) ) begin : g_chk_data
      $error("axil_master_engine : DATA_WIDTH must be 32 or 64 for AXI4-Lite (DATA_WIDTH=%0d)", DATA_WIDTH);
    end
    if( (ADDR_WIDTH<$clog2(DATA_WIDTH/8))||(ADDR_WIDTH>64) ) begin : g_chk_addr
      $error("axil_master_engine : ADDR_WIDTH must be %0d..64 (ADDR_WIDTH=%0d)", $clog2(DATA_WIDTH/8), ADDR_WIDTH);
    end
    if( (MAX_WR_OUTSTANDING<1)||(MAX_RD_OUTSTANDING<1) ) begin : g_chk_out
      $error("axil_master_engine : MAX_WR_OUTSTANDING / MAX_RD_OUTSTANDING must be >= 1 (%0d / %0d)", MAX_WR_OUTSTANDING, MAX_RD_OUTSTANDING);
    end
  endgenerate
`endif

endmodule

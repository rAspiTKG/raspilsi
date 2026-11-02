// ============================================================================
// BAYER2RGB_AXIL_BRIDGE : AXI4-Liteスレーブ ⇔ レジスタアクセス要求(vld/busy/data)
//   - AW と W は別々に受け取り、両方そろったら書き込み要求を出す
//   - 読み出しと書き込みが両方待っているときは交互に出す
//   - 要求は1つずつ処理する(応答のハンドシェイクが終わるまで次を出さない)
// ============================================================================
module BAYER2RGB_AXIL_BRIDGE
  import BAYER2RGB_PKG::*;
(
  input  logic                ctrl_clk
 ,input  logic                ctrl_rst_n
 // AXI4-Liteスレーブ
 ,input  logic [REG_AW-1:0]   BAYER2RGB_REG_AWADDR
 ,input  logic [2:0]          BAYER2RGB_REG_AWPROT
 ,input  logic                BAYER2RGB_REG_AWVALID
 ,output logic                BAYER2RGB_REG_AWREADY
 ,input  logic [REG_DW-1:0]   BAYER2RGB_REG_WDATA
 ,input  logic [REG_DW/8-1:0] BAYER2RGB_REG_WSTRB
 ,input  logic                BAYER2RGB_REG_WVALID
 ,output logic                BAYER2RGB_REG_WREADY
 ,output logic [1:0]          BAYER2RGB_REG_BRESP
 ,output logic                BAYER2RGB_REG_BVALID
 ,input  logic                BAYER2RGB_REG_BREADY
 ,input  logic [REG_AW-1:0]   BAYER2RGB_REG_ARADDR
 ,input  logic [2:0]          BAYER2RGB_REG_ARPROT
 ,input  logic                BAYER2RGB_REG_ARVALID
 ,output logic                BAYER2RGB_REG_ARREADY
 ,output logic [REG_DW-1:0]   BAYER2RGB_REG_RDATA
 ,output logic [1:0]          BAYER2RGB_REG_RRESP
 ,output logic                BAYER2RGB_REG_RVALID
 ,input  logic                BAYER2RGB_REG_RREADY
 // レジスタアクセス要求(REGへ)と応答(REGから)
 ,BAYER2RGB_VBD_IF.src        req
 ,BAYER2RGB_VBD_IF.dst        rsp
);

  // --------------------------------------------------------------------------
  // AXI4-Liteのポートを内部信号に受ける
  // --------------------------------------------------------------------------
  logic [REG_AW-1:0]   s_reg_awaddr;
  logic                s_reg_awvalid;
  logic                s_reg_awready;
  logic [REG_DW-1:0]   s_reg_wdata;
  logic [REG_DW/8-1:0] s_reg_wstrb;
  logic                s_reg_wvalid;
  logic                s_reg_wready;
  logic [1:0]          s_reg_bresp;
  logic                s_reg_bvalid;
  logic                s_reg_bready;
  logic [REG_AW-1:0]   s_reg_araddr;
  logic                s_reg_arvalid;
  logic                s_reg_arready;
  logic [REG_DW-1:0]   s_reg_rdata;
  logic [1:0]          s_reg_rresp;
  logic                s_reg_rvalid;
  logic                s_reg_rready;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [2:0]          s_reg_awprot;  // 保護属性は使わない
  logic [2:0]          s_reg_arprot;
  /* verilator lint_on UNUSEDSIGNAL */

  assign s_reg_awaddr          = BAYER2RGB_REG_AWADDR;
  assign s_reg_awprot          = BAYER2RGB_REG_AWPROT;
  assign s_reg_awvalid         = BAYER2RGB_REG_AWVALID;
  assign BAYER2RGB_REG_AWREADY = s_reg_awready;
  assign s_reg_wdata           = BAYER2RGB_REG_WDATA;
  assign s_reg_wstrb           = BAYER2RGB_REG_WSTRB;
  assign s_reg_wvalid          = BAYER2RGB_REG_WVALID;
  assign BAYER2RGB_REG_WREADY  = s_reg_wready;
  assign BAYER2RGB_REG_BRESP   = s_reg_bresp;
  assign BAYER2RGB_REG_BVALID  = s_reg_bvalid;
  assign s_reg_bready          = BAYER2RGB_REG_BREADY;
  assign s_reg_araddr          = BAYER2RGB_REG_ARADDR;
  assign s_reg_arprot          = BAYER2RGB_REG_ARPROT;
  assign s_reg_arvalid         = BAYER2RGB_REG_ARVALID;
  assign BAYER2RGB_REG_ARREADY = s_reg_arready;
  assign BAYER2RGB_REG_RDATA   = s_reg_rdata;
  assign BAYER2RGB_REG_RRESP   = s_reg_rresp;
  assign BAYER2RGB_REG_RVALID  = s_reg_rvalid;
  assign s_reg_rready          = BAYER2RGB_REG_RREADY;

  // --------------------------------------------------------------------------
  // 内部レジスタ
  // --------------------------------------------------------------------------
  logic                r_aw_ok;     // AWを受け取り済み
  logic [REG_AW-1:0]   r_aw_addr;
  logic                r_w_ok;      // Wを受け取り済み
  logic [REG_DW-1:0]   r_w_data;
  logic [REG_DW/8-1:0] r_w_strb;
  logic                r_ar_ok;     // ARを受け取り済み
  logic [REG_AW-1:0]   r_ar_addr;
  logic                r_req_vld;   // REGへの要求を出している
  regreq_t             r_req;
  logic                r_wait;      // REGの応答待ち
  logic                r_wr;        // 処理中の要求は書き込み
  logic                r_prio_rd;   // 1: 次は読み出しを優先する
  logic                r_bvalid;
  logic [1:0]          r_bresp;
  logic                r_rvalid;
  logic [1:0]          r_rresp;
  logic [REG_DW-1:0]   r_rdata;

  logic                s_aw_take;
  logic                s_w_take;
  logic                s_ar_take;
  logic                s_free;      // 次の要求を出せる
  logic                s_wr_rdy;
  logic                s_rd_rdy;
  logic                s_sel_wr;
  logic                s_sel_rd;
  logic                s_req_done;
  logic                s_rsp_take;
  regrsp_t             s_rsp;

  assign s_reg_awready = !r_aw_ok;
  assign s_reg_wready  = !r_w_ok;
  assign s_reg_arready = !r_ar_ok;
  assign s_aw_take     = s_reg_awvalid&&s_reg_awready;
  assign s_w_take      = s_reg_wvalid&&s_reg_wready;
  assign s_ar_take     = s_reg_arvalid&&s_reg_arready;

  assign s_free        = (!r_req_vld)&&(!r_wait)&&(!r_bvalid)&&(!r_rvalid);
  assign s_wr_rdy      = r_aw_ok&&r_w_ok;
  assign s_rd_rdy      = r_ar_ok;
  assign s_sel_wr      = s_free&&s_wr_rdy&&((!s_rd_rdy)||(!r_prio_rd));
  assign s_sel_rd      = s_free&&s_rd_rdy&&((!s_wr_rdy)||r_prio_rd);

  assign req.vld       = r_req_vld;
  assign req.data      = r_req;
  assign s_req_done    = r_req_vld&&!req.busy;

  assign s_rsp         = regrsp_t'(rsp.data);
  assign rsp.busy      = r_bvalid||r_rvalid;
  assign s_rsp_take    = rsp.vld&&!rsp.busy;

  assign s_reg_bvalid  = r_bvalid;
  assign s_reg_bresp   = r_bresp;
  assign s_reg_rvalid  = r_rvalid;
  assign s_reg_rresp   = r_rresp;
  assign s_reg_rdata   = r_rdata;

  // 制御(リセットあり)
  always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if( !ctrl_rst_n ) begin
      r_aw_ok   <= 1'b0;
      r_w_ok    <= 1'b0;
      r_ar_ok   <= 1'b0;
      r_req_vld <= 1'b0;
      r_wait    <= 1'b0;
      r_wr      <= 1'b0;
      r_prio_rd <= 1'b0;
      r_bvalid  <= 1'b0;
      r_bresp   <= AXI_RESP_OKAY;
      r_rvalid  <= 1'b0;
      r_rresp   <= AXI_RESP_OKAY;
    end else begin
      // AW / W / AR の受け取り
      if( s_aw_take ) begin
        r_aw_ok <= 1'b1;
      end else if( s_sel_wr ) begin
        r_aw_ok <= 1'b0;
      end
      if( s_w_take ) begin
        r_w_ok <= 1'b1;
      end else if( s_sel_wr ) begin
        r_w_ok <= 1'b0;
      end
      if( s_ar_take ) begin
        r_ar_ok <= 1'b1;
      end else if( s_sel_rd ) begin
        r_ar_ok <= 1'b0;
      end
      // REGへの要求
      if( s_sel_wr||s_sel_rd ) begin
        r_req_vld <= 1'b1;
        r_wr      <= s_sel_wr;
        r_prio_rd <= s_sel_wr;
      end else if( s_req_done ) begin
        r_req_vld <= 1'b0;
      end
      if( s_req_done ) begin
        r_wait <= 1'b1;
      end else if( s_rsp_take ) begin
        r_wait <= 1'b0;
      end
      // 応答
      if( s_rsp_take&&r_wr ) begin
        r_bvalid <= 1'b1;
        r_bresp  <= s_rsp.resp;
      end else if( s_reg_bready ) begin
        r_bvalid <= 1'b0;
      end
      if( s_rsp_take&&!r_wr ) begin
        r_rvalid <= 1'b1;
        r_rresp  <= s_rsp.resp;
      end else if( s_reg_rready ) begin
        r_rvalid <= 1'b0;
      end
    end
  end

  // データ(リセットなし)
  always_ff @(posedge ctrl_clk) begin
    if( s_aw_take ) begin
      r_aw_addr <= s_reg_awaddr;
    end
    if( s_w_take ) begin
      r_w_data <= s_reg_wdata;
      r_w_strb <= s_reg_wstrb;
    end
    if( s_ar_take ) begin
      r_ar_addr <= s_reg_araddr;
    end
    if( s_sel_wr ) begin
      r_req.we    <= 1'b1;
      r_req.strb  <= r_w_strb;
      r_req.addr  <= r_aw_addr;
      r_req.wdata <= r_w_data;
    end else if( s_sel_rd ) begin
      r_req.we    <= 1'b0;
      r_req.strb  <= '0;
      r_req.addr  <= r_ar_addr;
      r_req.wdata <= '0;
    end
    if( s_rsp_take&&!r_wr ) begin
      r_rdata <= s_rsp.rdata;
    end
  end

endmodule

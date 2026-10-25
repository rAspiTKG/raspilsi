// ============================================================================
// BAYER2RGB_REG : レジスタ(ctrl_clk ドメイン)
//   - レジスタアクセス要求(vld/busy/data)を受けて読み書きし、応答を返す
//   - STARTとSW_RESETをCDCへ1つずつ送る(SW_RESETを優先)
//   - 映像系からのイベントで割り込み状態とフレーム数を更新する
//   - 割り込み出力は IRQ_STATUS と IRQ_ENABLE の論理積のOR(レベル, High)
// ============================================================================
module BAYER2RGB_REG
  import BAYER2RGB_PKG::*;
(
  input  logic         ctrl_clk
 ,input  logic         ctrl_rst_n
 // レジスタアクセス要求と応答
 ,BAYER2RGB_VBD_IF.dst req
 ,BAYER2RGB_VBD_IF.src rsp
 // CDCへ
 ,output cfg_t         o_cfg       // 現在のレジスタ値(STARTのときにCDCが取り込む)
 ,output logic         o_start     // フレーム開始の要求(パルス)
 ,output logic         o_sw_rst    // ソフトリセットの要求(パルス)
 ,input  logic         i_cdc_busy  // CDCが要求を処理中
 ,input  evt_t         i_evt       // 映像系からのイベント(パルス)
 // 割り込み
 ,output logic         o_irq
);

  // --------------------------------------------------------------------------
  // 内部レジスタ
  // --------------------------------------------------------------------------
  logic                           r_reg_update;
  logic                           r_bypass;
  logic                           r_tpg_en;
  logic                           r_auto_restart;
  logic [2:0]                     r_irq_status;
  logic [2:0]                     r_irq_enable;
  logic [31:0]                    r_frame_count;
  logic [WIDTH_W-1:0]             r_width;
  logic [HEIGHT_W-1:0]            r_height;
  logic [1:0]                     r_phase;
  logic [3:0]                     r_func_en;      // [0]BLC [1]WB [2]FCS [3]GAMMA
  logic [3:0][IN_BITS-1:0]        r_blc;
  logic [3:0][WBG_W-1:0]          r_wbg;
  logic [IN_BITS-1:0]             r_fcs_th;
  logic [FCS_GAIN_W-1:0]          r_fcs_gain;
  logic [1:0]                     r_tpg_sel;
  logic [23:0]                    r_tpg_color;
  logic [MEM_AW-1:4]              r_src_addr;     // 下位4ビットは0
  logic [23:4]                    r_src_stride;
  logic [MEM_AW-1:4]              r_dst_addr;
  logic [23:4]                    r_dst_stride;
  logic [3:0]                     r_arcache;
  logic [3:0]                     r_awcache;
  logic [2:0]                     r_arprot;
  logic [2:0]                     r_awprot;
  logic [3:0]                     r_arqos;
  logic [3:0]                     r_awqos;
  logic [GM_KNOTS-1:0][GM_KW-1:0] r_gm_knot;

  logic                           r_start_pend;   // STARTの送信待ち
  logic                           r_srst_pend;    // SW_RESETの送信待ち
  logic                           r_srst_wait;    // ソフトリセットの完了待ち(送信からsrst_doneまで)
  logic                           r_frm_busy;     // フレーム処理中(START送信からframe_doneまで)
  logic                           r_start_o;
  logic                           r_srst_o;
  logic                           r_irq;
  logic                           r_rsp_vld;
  regrsp_t                        r_rsp;

  // --------------------------------------------------------------------------
  // アクセスのデコード
  // --------------------------------------------------------------------------
  regreq_t                        s_req;
  logic                           s_req_take;
  logic                           s_wr;
  logic [REG_AW-1:0]              s_addr;          // ワード境界のアドレス
  logic [31:0]                    s_wmask;         // バイトイネーブルを展開したマスク
  logic [31:0]                    s_rd;            // アドレスのレジスタの現在値
  logic [31:0]                    s_wval;          // 書き込み後の値
  logic [31:0]                    s_wset;          // 1を書いたビット
  logic                           s_gm_hit;        // ガンマの折れ点の範囲
  logic [4:0]                     s_gm_idx;        // ガンマのワード番号
  logic                           s_busy;
  logic                           s_cdc_free;
  logic                           s_srst_go;
  logic                           s_start_go;

  assign s_req      = regreq_t'(req.data);
  assign req.busy   = r_rsp_vld;
  assign s_req_take = req.vld&&!r_rsp_vld;
  assign s_wr       = s_req_take&&s_req.we;
  assign s_addr     = {s_req.addr[REG_AW-1:2], 2'b00};
  assign s_wmask    = {{8{s_req.strb[3]}}, {8{s_req.strb[2]}}, {8{s_req.strb[1]}}, {8{s_req.strb[0]}}};
  assign s_wval     = (s_rd&~s_wmask)|(s_req.wdata&s_wmask);
  assign s_wset     = s_req.wdata&s_wmask;
  assign s_gm_hit   = (s_addr>=A_GAMMA_KNOT)&&(s_addr<(A_GAMMA_KNOT+REG_AW'(GM_WORDS*4)));
  assign s_gm_idx   = 5'((s_addr-A_GAMMA_KNOT)>>2);

  assign s_busy     = r_start_pend||r_frm_busy||r_srst_pend||r_srst_wait||i_cdc_busy||r_start_o||r_srst_o;
  assign s_cdc_free = (!i_cdc_busy)&&(!r_start_o)&&(!r_srst_o);
  assign s_srst_go  = r_srst_pend&&(!r_srst_wait)&&s_cdc_free;
  assign s_start_go = r_start_pend&&(!r_srst_pend)&&(!r_srst_wait)&&(!r_frm_busy)&&s_cdc_free;

  // 読み出し値
  always_comb begin
    s_rd = 32'h0000_0000;
    case( s_addr )
      A_CONTROL : begin
        s_rd[CTL_REG_UPDATE]   = r_reg_update;
        s_rd[CTL_BYPASS]       = r_bypass;
        s_rd[CTL_TEST_PATTERN] = r_tpg_en;
        s_rd[CTL_AUTO_RESTART] = r_auto_restart;
      end
      A_STATUS : begin
        s_rd[0] = s_busy;
      end
      A_IRQ_STATUS : begin
        s_rd[2:0] = r_irq_status;
      end
      A_IRQ_ENABLE : begin
        s_rd[2:0] = r_irq_enable;
      end
      A_VERSION : begin
        s_rd = IP_VERSION;
      end
      A_HWCFG0 : begin
        s_rd = {16'(MAX_HEIGHT), 16'(MAX_WIDTH)};
      end
      A_HWCFG1 : begin
        s_rd = {8'(MEM_AW), 8'(MEM_BYTES), 8'(IN_BITS), 8'(PPC)};
      end
      A_FRAME_COUNT : begin
        s_rd = r_frame_count;
      end
      A_ACTIVE_WIDTH : begin
        s_rd[WIDTH_W-1:0] = r_width;
      end
      A_ACTIVE_HEIGHT : begin
        s_rd[HEIGHT_W-1:0] = r_height;
      end
      A_BAYER_PHASE : begin
        s_rd[1:0] = r_phase;
      end
      A_FUNC_EN : begin
        s_rd[3:0] = r_func_en;
      end
      A_BLC_R_GR : begin
        s_rd[13:0]  = r_blc[0];
        s_rd[29:16] = r_blc[1];
      end
      A_BLC_GB_B : begin
        s_rd[13:0]  = r_blc[2];
        s_rd[29:16] = r_blc[3];
      end
      A_WB_R_GR : begin
        s_rd = {r_wbg[1], r_wbg[0]};
      end
      A_WB_GB_B : begin
        s_rd = {r_wbg[3], r_wbg[2]};
      end
      A_FCS_PARAM : begin
        s_rd[13:0]  = r_fcs_th;
        s_rd[23:16] = r_fcs_gain;
      end
      A_TPG_SEL : begin
        s_rd[1:0] = r_tpg_sel;
      end
      A_TPG_COLOR : begin
        s_rd[23:0] = r_tpg_color;
      end
      A_SRC_ADDR_L : begin
        s_rd[31:4] = r_src_addr[31:4];
      end
      A_SRC_ADDR_H : begin
        s_rd[MEM_AW-33:0] = r_src_addr[MEM_AW-1:32];
      end
      A_SRC_STRIDE : begin
        s_rd[23:4] = r_src_stride;
      end
      A_DST_ADDR_L : begin
        s_rd[31:4] = r_dst_addr[31:4];
      end
      A_DST_ADDR_H : begin
        s_rd[MEM_AW-33:0] = r_dst_addr[MEM_AW-1:32];
      end
      A_DST_STRIDE : begin
        s_rd[23:4] = r_dst_stride;
      end
      A_AXI_ATTR : begin
        s_rd[3:0]   = r_arcache;
        s_rd[7:4]   = r_awcache;
        s_rd[10:8]  = r_arprot;
        s_rd[14:12] = r_awprot;
        s_rd[19:16] = r_arqos;
        s_rd[23:20] = r_awqos;
      end
      default : begin
        if( s_gm_hit ) begin
          s_rd[11:0] = r_gm_knot[{s_gm_idx, 1'b0}];
          if( s_gm_idx!=5'(GM_WORDS-1) ) begin
            s_rd[27:16] = r_gm_knot[{s_gm_idx, 1'b1}];
          end
        end
      end
    endcase
  end

  // --------------------------------------------------------------------------
  // 設定レジスタ(リセット値は f_cfg_default() と同じ)
  // --------------------------------------------------------------------------
  always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if( !ctrl_rst_n ) begin
      r_reg_update   <= 1'b1;
      r_bypass       <= 1'b0;
      r_tpg_en       <= 1'b0;
      r_auto_restart <= 1'b0;
      r_irq_enable   <= 3'b000;
      r_width        <= WIDTH_W'(MAX_WIDTH);
      r_height       <= HEIGHT_W'(MAX_HEIGHT);
      r_phase        <= 2'd0;
      r_func_en      <= 4'hF;
      r_blc          <= '0;
      for( int i=0; i<4; i++ ) begin
        r_wbg[i] <= WBG_W'(1<<WBG_FRAC);
      end
      r_fcs_th       <= IN_BITS'(256);
      r_fcs_gain     <= FCS_GAIN_W'(16);
      r_tpg_sel      <= 2'd0;
      r_tpg_color    <= 24'h00_0000;
      r_src_addr     <= '0;
      r_src_stride   <= '0;
      r_dst_addr     <= '0;
      r_dst_stride   <= '0;
      r_arcache      <= 4'b0011;
      r_awcache      <= 4'b0011;
      r_arprot       <= 3'b000;
      r_awprot       <= 3'b000;
      r_arqos        <= 4'h0;
      r_awqos        <= 4'h0;
      r_gm_knot      <= GM_SRGB;
    end else if( s_wr ) begin
      case( s_addr )
        A_CONTROL : begin
          r_reg_update   <= s_wval[CTL_REG_UPDATE];
          r_bypass       <= s_wval[CTL_BYPASS];
          r_tpg_en       <= s_wval[CTL_TEST_PATTERN];
          r_auto_restart <= s_wval[CTL_AUTO_RESTART];
        end
        A_IRQ_ENABLE : begin
          r_irq_enable <= s_wval[2:0];
        end
        A_ACTIVE_WIDTH : begin
          r_width <= s_wval[WIDTH_W-1:0];
        end
        A_ACTIVE_HEIGHT : begin
          r_height <= s_wval[HEIGHT_W-1:0];
        end
        A_BAYER_PHASE : begin
          r_phase <= s_wval[1:0];
        end
        A_FUNC_EN : begin
          r_func_en <= s_wval[3:0];
        end
        A_BLC_R_GR : begin
          r_blc[0] <= s_wval[13:0];
          r_blc[1] <= s_wval[29:16];
        end
        A_BLC_GB_B : begin
          r_blc[2] <= s_wval[13:0];
          r_blc[3] <= s_wval[29:16];
        end
        A_WB_R_GR : begin
          r_wbg[0] <= s_wval[15:0];
          r_wbg[1] <= s_wval[31:16];
        end
        A_WB_GB_B : begin
          r_wbg[2] <= s_wval[15:0];
          r_wbg[3] <= s_wval[31:16];
        end
        A_FCS_PARAM : begin
          r_fcs_th   <= s_wval[13:0];
          r_fcs_gain <= s_wval[23:16];
        end
        A_TPG_SEL : begin
          r_tpg_sel <= s_wval[1:0];
        end
        A_TPG_COLOR : begin
          r_tpg_color <= s_wval[23:0];
        end
        A_SRC_ADDR_L : begin
          r_src_addr[31:4] <= s_wval[31:4];
        end
        A_SRC_ADDR_H : begin
          r_src_addr[MEM_AW-1:32] <= s_wval[MEM_AW-33:0];
        end
        A_SRC_STRIDE : begin
          r_src_stride <= s_wval[23:4];
        end
        A_DST_ADDR_L : begin
          r_dst_addr[31:4] <= s_wval[31:4];
        end
        A_DST_ADDR_H : begin
          r_dst_addr[MEM_AW-1:32] <= s_wval[MEM_AW-33:0];
        end
        A_DST_STRIDE : begin
          r_dst_stride <= s_wval[23:4];
        end
        A_AXI_ATTR : begin
          r_arcache <= s_wval[3:0];
          r_awcache <= s_wval[7:4];
          r_arprot  <= s_wval[10:8];
          r_awprot  <= s_wval[14:12];
          r_arqos   <= s_wval[19:16];
          r_awqos   <= s_wval[23:20];
        end
        default : begin
          if( s_gm_hit ) begin
            r_gm_knot[{s_gm_idx, 1'b0}] <= s_wval[11:0];
            if( s_gm_idx!=5'(GM_WORDS-1) ) begin
              r_gm_knot[{s_gm_idx, 1'b1}] <= s_wval[27:16];
            end
          end
        end
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // 状態・要求・割り込み
  // --------------------------------------------------------------------------
  always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if( !ctrl_rst_n ) begin
      r_start_pend  <= 1'b0;
      r_srst_pend   <= 1'b0;
      r_srst_wait   <= 1'b0;
      r_frm_busy    <= 1'b0;
      r_start_o     <= 1'b0;
      r_srst_o      <= 1'b0;
      r_irq_status  <= 3'b000;
      r_frame_count <= 32'd0;
      r_irq         <= 1'b0;
    end else begin
      // フレーム完了(ソフトリセット後に届いた前フレームの完了では再開しない)
      if( i_evt.frame_done ) begin
        r_frm_busy    <= 1'b0;
        r_frame_count <= r_frame_count+32'd1;
        if( r_frm_busy&&r_auto_restart ) begin
          r_start_pend <= 1'b1;
        end
      end
      // ソフトリセットの完了
      if( i_evt.srst_done ) begin
        r_srst_wait <= 1'b0;
      end
      // CDCへの要求(1つずつ。SW_RESETを優先)
      r_srst_o  <= s_srst_go;
      r_start_o <= s_start_go;
      if( s_srst_go ) begin
        r_srst_pend <= 1'b0;
        r_srst_wait <= 1'b1;
      end
      if( s_start_go ) begin
        r_start_pend <= 1'b0;
        r_frm_busy   <= 1'b1;
      end
      // ソフトウェアからの書き込み
      if( s_wr&&(s_addr==A_CONTROL) ) begin
        if( s_wset[CTL_SW_RESET] ) begin
          r_srst_pend   <= 1'b1;
          r_start_pend  <= 1'b0;
          r_frm_busy    <= 1'b0;
          r_frame_count <= 32'd0;
        end else if( s_wset[CTL_START] ) begin
          r_start_pend <= 1'b1;
        end
      end
      // 割り込み状態(書き込み1でクリア。同時に起きたイベントを優先)
      for( int i=0; i<3; i++ ) begin
        if( s_wr&&(s_addr==A_IRQ_STATUS)&&s_wset[i] ) begin
          r_irq_status[i] <= 1'b0;
        end
      end
      if( i_evt.frame_done ) begin
        r_irq_status[IRQ_FRAME_DONE] <= 1'b1;
      end
      if( i_evt.rd_err ) begin
        r_irq_status[IRQ_RD_ERR] <= 1'b1;
      end
      if( i_evt.wr_err ) begin
        r_irq_status[IRQ_WR_ERR] <= 1'b1;
      end
      r_irq <= |(r_irq_status&r_irq_enable);
    end
  end

  // --------------------------------------------------------------------------
  // 応答
  // --------------------------------------------------------------------------
  always_ff @(posedge ctrl_clk or negedge ctrl_rst_n) begin
    if( !ctrl_rst_n ) begin
      r_rsp_vld <= 1'b0;
    end else begin
      if( s_req_take ) begin
        r_rsp_vld <= 1'b1;
      end else if( !rsp.busy ) begin
        r_rsp_vld <= 1'b0;
      end
    end
  end

  always_ff @(posedge ctrl_clk) begin
    if( s_req_take ) begin
      r_rsp.resp <= AXI_RESP_OKAY;
      if( s_req.we ) begin
        r_rsp.rdata <= 32'h0000_0000;
      end else begin
        r_rsp.rdata <= s_rd;
      end
    end
  end

  assign rsp.vld  = r_rsp_vld;
  assign rsp.data = r_rsp;

  // --------------------------------------------------------------------------
  // 出力
  // --------------------------------------------------------------------------
  always_comb begin
    o_cfg            = '0;
    o_cfg.reg_update = r_reg_update;
    o_cfg.bypass     = r_bypass;
    o_cfg.tpg_en     = r_tpg_en;
    o_cfg.tpg_sel    = r_tpg_sel;
    o_cfg.tpg_color  = r_tpg_color;
    o_cfg.width      = r_width;
    o_cfg.height     = r_height;
    o_cfg.phase      = r_phase;
    o_cfg.blc_en     = r_func_en[0];
    o_cfg.wb_en      = r_func_en[1];
    o_cfg.fcs_en     = r_func_en[2];
    o_cfg.gamma_en   = r_func_en[3];
    o_cfg.blc        = r_blc;
    o_cfg.wbg        = r_wbg;
    o_cfg.fcs_th     = r_fcs_th;
    o_cfg.fcs_gain   = r_fcs_gain;
    o_cfg.gm_knot    = r_gm_knot;
    o_cfg.src_addr   = {r_src_addr, 4'h0};
    o_cfg.src_stride = {r_src_stride, 4'h0};
    o_cfg.dst_addr   = {r_dst_addr, 4'h0};
    o_cfg.dst_stride = {r_dst_stride, 4'h0};
    o_cfg.arcache    = r_arcache;
    o_cfg.awcache    = r_awcache;
    o_cfg.arprot     = r_arprot;
    o_cfg.awprot     = r_awprot;
    o_cfg.arqos      = r_arqos;
    o_cfg.awqos      = r_awqos;
  end

  assign o_start  = r_start_o;
  assign o_sw_rst = r_srst_o;
  assign o_irq    = r_irq;

endmodule

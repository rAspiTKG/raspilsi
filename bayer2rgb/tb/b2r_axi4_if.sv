// ============================================================================
// b2r_axi4_if : AXI4 インタフェース(検証環境用)
//   DUT(マスタ)側の出力について、プロトコルと本IPの約束を検査する
//     - AxVALID / WVALID は READY まで下げない。要求・データの値も保持する
//     - AxSIZE=16バイト、AxBURST=INCR、AxLEN<=15、16バイト境界、4KB境界をまたがない
//     - AxID=0、AxLOCK=0
//     - 同時発行(応答を受け終えていないバースト)は読み・書きとも4以下
//   WとAWの対応(ビート数・WLAST)はスレーブモデルで検査する
// ============================================================================
interface b2r_axi4_if (
  input logic clk
 ,input logic rst_n
);
  // AW
  logic [3:0]   awid;
  logic [39:0]  awaddr;
  logic [7:0]   awlen;
  logic [2:0]   awsize;
  logic [1:0]   awburst;
  logic         awlock;
  logic [3:0]   awcache;
  logic [2:0]   awprot;
  logic [3:0]   awqos;
  logic         awvalid;
  logic         awready;
  // W
  logic [127:0] wdata;
  logic [15:0]  wstrb;
  logic         wlast;
  logic         wvalid;
  logic         wready;
  // B
  logic [3:0]   bid;
  logic [1:0]   bresp;
  logic         bvalid;
  logic         bready;
  // AR
  logic [3:0]   arid;
  logic [39:0]  araddr;
  logic [7:0]   arlen;
  logic [2:0]   arsize;
  logic [1:0]   arburst;
  logic         arlock;
  logic [3:0]   arcache;
  logic [2:0]   arprot;
  logic [3:0]   arqos;
  logic         arvalid;
  logic         arready;
  // R
  logic [3:0]   rid;
  logic [127:0] rdata;
  logic [1:0]   rresp;
  logic         rlast;
  logic         rvalid;
  logic         rready;

  // --------------------------------------------------------------------------
  // プロトコル検査
  // --------------------------------------------------------------------------
  logic         p_arvalid;
  logic         p_arready;
  logic [66:0]  p_ar;
  logic         p_awvalid;
  logic         p_awready;
  logic [66:0]  p_aw;
  logic         p_wvalid;
  logic         p_wready;
  logic [144:0] p_w;
  int           n_rd_ost;
  int           n_wr_ost;
  logic [66:0]  s_ar;
  logic [66:0]  s_aw;
  logic [144:0] s_w;
  bit           chk_ost_en = 1'b1;   // 同時発行数の検査

  assign s_ar = {arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos};
  assign s_aw = {awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos};
  assign s_w  = {wdata, wstrb, wlast};

  // 要求1つ分の検査
  function automatic void f_check_req( string ch, logic [3:0] id, logic [39:0] addr, logic [7:0] len,
                                      logic [2:0] size, logic [1:0] burst, logic lock );
    longint unsigned last_byte;
    begin
      last_byte = longint'(addr[11:0])+((longint'(len)+1)*16)-1;
      if( id!==4'd0 ) begin
        $error("b2r_axi4_if: %sID が0でない (%0h)", ch, id);
      end
      if( size!==3'd4 ) begin
        $error("b2r_axi4_if: %sSIZE が16バイトでない (%0d)", ch, size);
      end
      if( burst!==2'b01 ) begin
        $error("b2r_axi4_if: %sBURST が INCR でない (%0d)", ch, burst);
      end
      if( lock!==1'b0 ) begin
        $error("b2r_axi4_if: %sLOCK が0でない", ch);
      end
      if( len>8'd15 ) begin
        $error("b2r_axi4_if: %sLEN が15を超えた (%0d)", ch, len);
      end
      if( addr[3:0]!==4'h0 ) begin
        $error("b2r_axi4_if: %sADDR が16バイト境界でない (%0h)", ch, addr);
      end
      if( last_byte>64'd4095 ) begin
        $error("b2r_axi4_if: %s のバーストが4KB境界をまたぐ (addr=%0h len=%0d)", ch, addr, len);
      end
    end
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      p_arvalid <= 1'b0;
      p_arready <= 1'b0;
      p_awvalid <= 1'b0;
      p_awready <= 1'b0;
      p_wvalid  <= 1'b0;
      p_wready  <= 1'b0;
      n_rd_ost  <= 0;
      n_wr_ost  <= 0;
    end else begin
      // 不定値
      if( $isunknown({arvalid,awvalid,wvalid,rready,bready}) ) begin
        $error("b2r_axi4_if: VALID/READY に不定値がある");
      end
      // 保持
      if( p_arvalid&&!p_arready ) begin
        if( !arvalid||(s_ar!==p_ar) ) begin
          $error("b2r_axi4_if: ARVALID/AR* が ARREADY の前に変化した");
        end
      end
      if( p_awvalid&&!p_awready ) begin
        if( !awvalid||(s_aw!==p_aw) ) begin
          $error("b2r_axi4_if: AWVALID/AW* が AWREADY の前に変化した");
        end
      end
      if( p_wvalid&&!p_wready ) begin
        if( !wvalid||(s_w!==p_w) ) begin
          $error("b2r_axi4_if: WVALID/W* が WREADY の前に変化した");
        end
      end
      // 要求の内容
      if( arvalid&&arready ) begin
        f_check_req("AR", arid, araddr, arlen, arsize, arburst, arlock);
      end
      if( awvalid&&awready ) begin
        f_check_req("AW", awid, awaddr, awlen, awsize, awburst, awlock);
      end
      // 同時発行数
      n_rd_ost <= n_rd_ost+int'(arvalid&&arready)-int'(rvalid&&rready&&rlast);
      n_wr_ost <= n_wr_ost+int'(awvalid&&awready)-int'(bvalid&&bready);
      if( chk_ost_en&&(n_rd_ost>4) ) begin
        $error("b2r_axi4_if: 読み出しの同時発行が4を超えた (%0d)", n_rd_ost);
      end
      if( chk_ost_en&&(n_wr_ost>4) ) begin
        $error("b2r_axi4_if: 書き込みの同時発行が4を超えた (%0d)", n_wr_ost);
      end
      p_arvalid <= arvalid;
      p_arready <= arready;
      p_ar      <= s_ar;
      p_awvalid <= awvalid;
      p_awready <= awready;
      p_aw      <= s_aw;
      p_wvalid  <= wvalid;
      p_wready  <= wready;
      p_w       <= s_w;
    end
  end

endinterface

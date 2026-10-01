//=============================================================================
// axi4_full_master_copy.sv
//-----------------------------------------------------------------------------
//  AXI4-Full マスタのコピーエンジン。
//  AXI Read で受け取ったデータを内部バッファ (FIFO) に溜め、そのまま
//  AXI Write で出力する (src -> dst のメモリコピー)。
//
//      cmd (src, dst, len)
//           |
//    +------+-------------------------------------------------+
//    |  axi4_mst_rd_engine --> [ FIFO BUF_DEPTH ] --> axi4_mst_wr_engine
//    |   AR / R                                         AW / W / B
//    +---------------------------------------------------------+
//
//  - コマンドは cmd_valid / cmd_ready で受ける。両エンジンがアイドルのときだけ
//    受け付け、同じサイクルで両方へ渡す
//  - cmd_len はビート数 (DATA_WIDTH 単位)。src / dst はバス幅アライン
//  - Read 側は FIFO の空きが 1 バースト分あるときだけ AR を出し、
//    Write 側は FIFO に 1 バースト分のデータが揃ってから AW を出す
//  - Read と Write は並行に進む (Read が先行して FIFO を満たす)
//  - done は Write 完了時に 1 サイクル。done_err は Read / Write どちらかで
//    エラー応答 (SLVERR / DECERR) や ID 不一致があれば 1
//
//  BUF_DEPTH >= 2 * MAX_BURST が必要。
//  (src と dst で 4KB 境界の位置が違うと Read / Write のバースト境界がずれる。
//   FIFO が小さいと「Write はデータ不足、Read は空き不足」で両方が止まり得る)
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//        https://developer.arm.com/documentation/ihi0022/latest/
//=============================================================================
`timescale 1ns / 1ps

module axi4_full_master_copy #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned RD_ID      = 0
 ,parameter int unsigned WR_ID      = 1
 ,parameter int unsigned LEN_WIDTH  = 16
 ,parameter int unsigned MAX_BURST  = 16
 ,parameter int unsigned BUF_DEPTH  = 32
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
 ,input  logic [ADDR_WIDTH-1:0]     cmd_src
 ,input  logic [ADDR_WIDTH-1:0]     cmd_dst
 ,input  logic [LEN_WIDTH-1:0]      cmd_len
 ,output logic                      busy
 ,output logic                      done
 ,output logic                      done_err
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
  localparam int unsigned LVL_W = $clog2(BUF_DEPTH+1);
  localparam int unsigned CNT_W = 16;

  //---------------------------------------------------------------------------
  // コマンド分配 (両エンジンがアイドルのときだけ受け付ける)
  //---------------------------------------------------------------------------
  logic rd_cmd_ready;
  logic wr_cmd_ready;
  logic eng_cmd_valid;

  assign cmd_ready     = rd_cmd_ready&&wr_cmd_ready;
  assign eng_cmd_valid = cmd_valid&&cmd_ready;

  //---------------------------------------------------------------------------
  // 内部バッファ
  //---------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] rd_data;
  logic                  rd_valid;
  logic                  rd_ready;
  logic [DATA_WIDTH-1:0] buf_data;
  logic                  buf_valid;
  logic                  buf_ready;
  logic [LVL_W-1:0]      buf_level;
  logic [CNT_W-1:0]      buf_space;
  logic [CNT_W-1:0]      buf_count;

  assign buf_count = CNT_W'(buf_level);
  assign buf_space = CNT_W'(BUF_DEPTH) - CNT_W'(buf_level);

  axi4_sync_fifo #(
    .WIDTH(DATA_WIDTH)
   ,.DEPTH(BUF_DEPTH)
  ) u_buf (
    .clk(aclk)
   ,.rst_n(aresetn)
   ,.wr_data(rd_data)
   ,.wr_valid(rd_valid)
   ,.wr_ready(rd_ready)
   ,.rd_data(buf_data)
   ,.rd_valid(buf_valid)
   ,.rd_ready(buf_ready)
   ,.level(buf_level)
  );

  //---------------------------------------------------------------------------
  // Read エンジン (src -> バッファ)
  //---------------------------------------------------------------------------
  logic rd_busy;
  logic rd_done;
  logic rd_done_err;
  logic rd_last;

  axi4_mst_rd_engine #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.AXI_ID(RD_ID)
   ,.LEN_WIDTH(LEN_WIDTH)
   ,.CNT_WIDTH(CNT_W)
   ,.MAX_BURST(MAX_BURST)
  ) u_rd (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(eng_cmd_valid)
   ,.cmd_ready(rd_cmd_ready)
   ,.cmd_addr(cmd_src)
   ,.cmd_len(cmd_len)
   ,.busy(rd_busy)
   ,.done(rd_done)
   ,.done_err(rd_done_err)
   ,.m_data(rd_data)
   ,.m_last(rd_last)
   ,.m_valid(rd_valid)
   ,.m_ready(rd_ready)
   ,.m_space(buf_space)
   ,.m_axi_arid(m_axi_arid)
   ,.m_axi_araddr(m_axi_araddr)
   ,.m_axi_arlen(m_axi_arlen)
   ,.m_axi_arsize(m_axi_arsize)
   ,.m_axi_arburst(m_axi_arburst)
   ,.m_axi_arlock(m_axi_arlock)
   ,.m_axi_arcache(m_axi_arcache)
   ,.m_axi_arprot(m_axi_arprot)
   ,.m_axi_arqos(m_axi_arqos)
   ,.m_axi_arregion(m_axi_arregion)
   ,.m_axi_arvalid(m_axi_arvalid)
   ,.m_axi_arready(m_axi_arready)
   ,.m_axi_rid(m_axi_rid)
   ,.m_axi_rdata(m_axi_rdata)
   ,.m_axi_rresp(m_axi_rresp)
   ,.m_axi_rlast(m_axi_rlast)
   ,.m_axi_rvalid(m_axi_rvalid)
   ,.m_axi_rready(m_axi_rready)
  );

  //---------------------------------------------------------------------------
  // Write エンジン (バッファ -> dst)
  //---------------------------------------------------------------------------
  logic wr_busy;
  logic wr_done;
  logic wr_done_err;

  axi4_mst_wr_engine #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ID_WIDTH(ID_WIDTH)
   ,.AXI_ID(WR_ID)
   ,.LEN_WIDTH(LEN_WIDTH)
   ,.CNT_WIDTH(CNT_W)
   ,.MAX_BURST(MAX_BURST)
  ) u_wr (
    .aclk(aclk)
   ,.aresetn(aresetn)
   ,.cmd_valid(eng_cmd_valid)
   ,.cmd_ready(wr_cmd_ready)
   ,.cmd_addr(cmd_dst)
   ,.cmd_len(cmd_len)
   ,.busy(wr_busy)
   ,.done(wr_done)
   ,.done_err(wr_done_err)
   ,.s_data(buf_data)
   ,.s_valid(buf_valid)
   ,.s_ready(buf_ready)
   ,.s_count(buf_count)
   ,.m_axi_awid(m_axi_awid)
   ,.m_axi_awaddr(m_axi_awaddr)
   ,.m_axi_awlen(m_axi_awlen)
   ,.m_axi_awsize(m_axi_awsize)
   ,.m_axi_awburst(m_axi_awburst)
   ,.m_axi_awlock(m_axi_awlock)
   ,.m_axi_awcache(m_axi_awcache)
   ,.m_axi_awprot(m_axi_awprot)
   ,.m_axi_awqos(m_axi_awqos)
   ,.m_axi_awregion(m_axi_awregion)
   ,.m_axi_awvalid(m_axi_awvalid)
   ,.m_axi_awready(m_axi_awready)
   ,.m_axi_wdata(m_axi_wdata)
   ,.m_axi_wstrb(m_axi_wstrb)
   ,.m_axi_wlast(m_axi_wlast)
   ,.m_axi_wvalid(m_axi_wvalid)
   ,.m_axi_wready(m_axi_wready)
   ,.m_axi_bid(m_axi_bid)
   ,.m_axi_bresp(m_axi_bresp)
   ,.m_axi_bvalid(m_axi_bvalid)
   ,.m_axi_bready(m_axi_bready)
  );

  //---------------------------------------------------------------------------
  // ステータス
  //   Read は必ず Write より先に終わるので、Read のエラーを保持して
  //   Write 完了時にまとめて返す
  //---------------------------------------------------------------------------
  logic rd_err_q;

  always_ff @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      rd_err_q <= 1'b0;
    end else begin
      if( eng_cmd_valid ) begin
        rd_err_q <= 1'b0;
      end else if( rd_done&&rd_done_err ) begin
        rd_err_q <= 1'b1;
      end
    end
  end

  assign busy     = rd_busy||wr_busy;
  assign done     = wr_done;
  assign done_err = wr_done_err||rd_err_q;

  //---------------------------------------------------------------------------
  // 未使用 (コピーでは Read 側のコマンド境界は使わない)
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{1'b0, rd_last};

  //---------------------------------------------------------------------------
  // エラボレーション時チェック
  //---------------------------------------------------------------------------
  initial begin
    if( BUF_DEPTH<(2*MAX_BURST) ) begin
      $error("axi4_full_master_copy : BUF_DEPTH (%0d) must be >= 2*MAX_BURST (%0d)", BUF_DEPTH, 2*MAX_BURST);
    end
  end

endmodule

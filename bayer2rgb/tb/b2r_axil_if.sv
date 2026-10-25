// ============================================================================
// b2r_axil_if : AXI4-Lite インタフェース(検証環境用)
//   DUT(スレーブ)側の出力について、プロトコルの基本規則を検査する
//     - BVALID / RVALID は READY まで下げない。応答の値も保持する
//     - 要求していない応答を返さない
// ============================================================================
interface b2r_axil_if (
  input logic clk
 ,input logic rst_n
);
  logic [11:0] awaddr;
  logic [2:0]  awprot;
  logic        awvalid;
  logic        awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wvalid;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;
  logic [11:0] araddr;
  logic [2:0]  arprot;
  logic        arvalid;
  logic        arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready;

  // --------------------------------------------------------------------------
  // プロトコル検査
  // --------------------------------------------------------------------------
  logic        p_bvalid;
  logic        p_bready;
  logic [1:0]  p_bresp;
  logic        p_rvalid;
  logic        p_rready;
  logic [31:0] p_rdata;
  logic [1:0]  p_rresp;
  int          n_aw;
  int          n_w;
  int          n_b;
  int          n_ar;
  int          n_r;

  always @(posedge clk or negedge rst_n) begin
    if( !rst_n ) begin
      p_bvalid <= 1'b0;
      p_rvalid <= 1'b0;
      p_bready <= 1'b0;
      p_rready <= 1'b0;
      n_aw     <= 0;
      n_w      <= 0;
      n_b      <= 0;
      n_ar     <= 0;
      n_r      <= 0;
    end else begin
      if( p_bvalid&&!p_bready ) begin
        if( !bvalid||(bresp!==p_bresp) ) begin
          $error("b2r_axil_if: BVALID/BRESP が BREADY の前に変化した");
        end
      end
      if( p_rvalid&&!p_rready ) begin
        if( !rvalid||(rdata!==p_rdata)||(rresp!==p_rresp) ) begin
          $error("b2r_axil_if: RVALID/RDATA/RRESP が RREADY の前に変化した");
        end
      end
      if( awvalid&&awready ) begin
        n_aw <= n_aw+1;
      end
      if( wvalid&&wready ) begin
        n_w <= n_w+1;
      end
      if( arvalid&&arready ) begin
        n_ar <= n_ar+1;
      end
      if( bvalid&&bready ) begin
        n_b <= n_b+1;
        if( (n_b>=n_aw)||(n_b>=n_w) ) begin
          $error("b2r_axil_if: 書き込み要求より先に B を返した");
        end
      end
      if( rvalid&&rready ) begin
        n_r <= n_r+1;
        if( n_r>=n_ar ) begin
          $error("b2r_axil_if: 読み出し要求より先に R を返した");
        end
      end
      p_bvalid <= bvalid;
      p_bready <= bready;
      p_bresp  <= bresp;
      p_rvalid <= rvalid;
      p_rready <= rready;
      p_rdata  <= rdata;
      p_rresp  <= rresp;
    end
  end

endinterface

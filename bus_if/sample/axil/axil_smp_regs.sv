//=============================================================================
// axil_smp_regs.sv
//-----------------------------------------------------------------------------
//  axil_if のサンプル : AXI4-Lite サブオーディネート (レジスタファイル。合成可能)。
//    - アドレス 0 から 4 バイトおきに NREG 個の DATA_WIDTH ビットのレジスタ
//    - 書き込みは WSTRB のバイトだけ。存在しない番号への書き込み / 読み出しは SLVERR
//      (書き込みは無視、読み出しデータは 0)
//    - AW と W は別々に受け付けて、両方そろったら書いて B を返す
//    - AWREADY / WREADY / ARREADY は VALID が来てから READY_DLY サイクル後に出す (待ちの例)
//
//  ポートは axil_if.sub 1 本だけ。
//=============================================================================
`timescale 1ns / 1ps

module axil_smp_regs #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 32
 ,parameter int unsigned NREG       = 4
 ,parameter int unsigned READY_DLY  = 0
) (
  input logic  aclk
 ,input logic  aresetn
 ,axil_if.sub  s_axi
);

  // つないだ axil_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(s_axi.awaddr)!=ADDR_WIDTH)||($bits(s_axi.wdata)!=DATA_WIDTH) ) begin : g_chk_if
    $error("axil_smp_regs : ADDR_WIDTH / DATA_WIDTH differ from the axil_if connected to s_axi");
  end

  localparam int unsigned STRB_WIDTH = DATA_WIDTH/8;
  localparam int unsigned IDXW       = (NREG<2) ? 1 : $clog2(NREG);
  localparam int unsigned DLYW       = (READY_DLY<1) ? 1 : $clog2(READY_DLY+1);

  logic [DATA_WIDTH-1:0] regs_q [NREG];
  logic                  aw_v_q;     // AW を受け取った
  logic [ADDR_WIDTH-3:0] aw_wa_q;    // AWADDR のワードアドレス (下位 2 ビットを除く)
  logic                  w_v_q;      // W を受け取った
  logic [DATA_WIDTH-1:0] w_data_q;
  logic [STRB_WIDTH-1:0] w_strb_q;
  logic                  bvalid_q;
  logic [1:0]            bresp_q;
  logic                  rvalid_q;
  logic [1:0]            rresp_q;
  logic [DATA_WIDTH-1:0] rdata_q;
  logic [DLYW-1:0]       aw_dly_q;
  logic [DLYW-1:0]       w_dly_q;
  logic [DLYW-1:0]       ar_dly_q;

  logic                  awready;
  logic                  wready;
  logic                  arready;
  logic                  do_wr;

  // ワードアドレスのレジスタが存在するか
  function automatic logic hit(input logic [ADDR_WIDTH-3:0] wa);
    return (wa<(ADDR_WIDTH-2)'(NREG));
  endfunction

  assign awready = !aw_v_q&&(aw_dly_q==DLYW'(READY_DLY));
  assign wready  = !w_v_q&&(w_dly_q==DLYW'(READY_DLY));
  assign arready = !rvalid_q&&(ar_dly_q==DLYW'(READY_DLY));
  assign do_wr   = aw_v_q&&w_v_q&&!bvalid_q;

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      aw_v_q    <= 1'b0;
      aw_wa_q   <= '0;
      w_v_q     <= 1'b0;
      w_data_q  <= '0;
      w_strb_q  <= '0;
      bvalid_q  <= 1'b0;
      bresp_q   <= 2'b00;
      rvalid_q  <= 1'b0;
      rresp_q   <= 2'b00;
      rdata_q   <= '0;
      aw_dly_q  <= '0;
      w_dly_q   <= '0;
      ar_dly_q  <= '0;
      for( int i=0; i<NREG; i++ ) begin
        regs_q[i] <= '0;
      end
    end else begin
      // READY を出すまでの待ち
      if( s_axi.awvalid&&!awready&&!aw_v_q ) begin
        aw_dly_q <= aw_dly_q+1'b1;
      end
      if( s_axi.wvalid&&!wready&&!w_v_q ) begin
        w_dly_q <= w_dly_q+1'b1;
      end
      if( s_axi.arvalid&&!arready&&!rvalid_q ) begin
        ar_dly_q <= ar_dly_q+1'b1;
      end
      // AW / W を受け取る
      if( s_axi.awvalid&&awready ) begin
        aw_v_q    <= 1'b1;
        aw_wa_q   <= s_axi.awaddr[ADDR_WIDTH-1:2];
        aw_dly_q  <= '0;
      end
      if( s_axi.wvalid&&wready ) begin
        w_v_q    <= 1'b1;
        w_data_q <= s_axi.wdata;
        w_strb_q <= s_axi.wstrb;
        w_dly_q  <= '0;
      end
      // 両方そろったら書いて B を返す
      if( do_wr ) begin
        if( hit(aw_wa_q) ) begin
          for( int k=0; k<STRB_WIDTH; k++ ) begin
            if( w_strb_q[k] ) begin
              regs_q[aw_wa_q[IDXW-1:0]][8*k+:8] <= w_data_q[8*k+:8];
            end
          end
          bresp_q <= 2'b00;
        end else begin
          bresp_q <= 2'b10;
        end
        bvalid_q <= 1'b1;
      end
      if( bvalid_q&&s_axi.bready ) begin
        bvalid_q <= 1'b0;
        aw_v_q   <= 1'b0;
        w_v_q    <= 1'b0;
      end
      // 読み出し
      if( s_axi.arvalid&&arready ) begin
        rvalid_q <= 1'b1;
        ar_dly_q <= '0;
        if( hit(s_axi.araddr[ADDR_WIDTH-1:2]) ) begin
          rdata_q <= regs_q[s_axi.araddr[2+:IDXW]];
          rresp_q <= 2'b00;
        end else begin
          rdata_q <= '0;
          rresp_q <= 2'b10;
        end
      end else if( rvalid_q&&s_axi.rready ) begin
        rvalid_q <= 1'b0;
      end
    end
  end

  //---------------------------------------------------------------------------
  // AXI4-Lite の出力
  //---------------------------------------------------------------------------
  assign s_axi.awready = awready;
  assign s_axi.wready  = wready;
  assign s_axi.bresp   = bresp_q;
  assign s_axi.bvalid  = bvalid_q;
  assign s_axi.arready = arready;
  assign s_axi.rdata   = rdata_q;
  assign s_axi.rresp   = rresp_q;
  assign s_axi.rvalid  = rvalid_q;

  // 使わない入力
  wire unused_ok = &{1'b0, s_axi.awprot, s_axi.arprot, s_axi.awaddr[1:0], s_axi.araddr[1:0]};

endmodule

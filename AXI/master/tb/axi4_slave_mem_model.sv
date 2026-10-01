//=============================================================================
// axi4_slave_mem_model.sv
//-----------------------------------------------------------------------------
//  AXI4-Full マスタ検証用のスレーブメモリモデル (テストベンチ専用)。
//
//  機能:
//    - バイト単位の連想配列メモリ (poke_word / peek_word でバックドアアクセス)
//    - ランダムストール (stall_pct [%])
//        AWREADY / WREADY / ARREADY をランダムに下げる
//        BVALID / 各ビートの RVALID をランダムに遅らせる (出したら握手まで保持)
//    - ready_wait_valid=1 : READY を VALID を見てから立てる (握手ごとに一旦下げる)
//        スレーブが VALID を待つのは AXI で許されている。マスタが逆に READY を
//        待ってから VALID を出す実装だとこのモードでデッドロックするので検出できる
//    - SLVERR 注入 : [err_lo, err_hi] のアドレスへのアクセスは SLVERR を返す
//      (書き込みはメモリに反映しない)
//    - マスタ側のプロトコルチェック (違反は n_viol に数える)
//        * AWVALID / WVALID / ARVALID を握手前に下げていないか
//        * 握手待ちの間にペイロードを変えていないか
//        * WLAST が AWLEN の位置で立つか
//        * INCR バーストが 4KB 境界を跨いでいないか
//        * バースト長が MAX_BURST 以下か、予約バースト種別でないか
//
//  設定変数 (stall_pct / err_lo / err_hi) はテストベンチから階層参照で変更する。
//
//  参考: AMBA AXI Protocol Specification (Arm IHI 0022)
//        https://developer.arm.com/documentation/ihi0022/latest/
//=============================================================================
`timescale 1ns / 1ps

module axi4_slave_mem_model #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 64
 ,parameter int unsigned ID_WIDTH   = 4
 ,parameter int unsigned MAX_BURST  = 256
) (
  input  logic                      aclk
 ,input  logic                      aresetn
  // Write address channel
 ,input  logic [ID_WIDTH-1:0]       s_axi_awid
 ,input  logic [ADDR_WIDTH-1:0]     s_axi_awaddr
 ,input  logic [7:0]                s_axi_awlen
 ,input  logic [2:0]                s_axi_awsize
 ,input  logic [1:0]                s_axi_awburst
 ,input  logic                      s_axi_awvalid
 ,output logic                      s_axi_awready
  // Write data channel
 ,input  logic [DATA_WIDTH-1:0]     s_axi_wdata
 ,input  logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb
 ,input  logic                      s_axi_wlast
 ,input  logic                      s_axi_wvalid
 ,output logic                      s_axi_wready
  // Write response channel
 ,output logic [ID_WIDTH-1:0]       s_axi_bid
 ,output logic [1:0]                s_axi_bresp
 ,output logic                      s_axi_bvalid
 ,input  logic                      s_axi_bready
  // Read address channel
 ,input  logic [ID_WIDTH-1:0]       s_axi_arid
 ,input  logic [ADDR_WIDTH-1:0]     s_axi_araddr
 ,input  logic [7:0]                s_axi_arlen
 ,input  logic [2:0]                s_axi_arsize
 ,input  logic [1:0]                s_axi_arburst
 ,input  logic                      s_axi_arvalid
 ,output logic                      s_axi_arready
  // Read data channel
 ,output logic [ID_WIDTH-1:0]       s_axi_rid
 ,output logic [DATA_WIDTH-1:0]     s_axi_rdata
 ,output logic [1:0]                s_axi_rresp
 ,output logic                      s_axi_rlast
 ,output logic                      s_axi_rvalid
 ,input  logic                      s_axi_rready
);

  localparam int unsigned STRB_W   = DATA_WIDTH / 8;
  localparam int unsigned ADDR_LSB = $clog2(STRB_W);

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  //---------------------------------------------------------------------------
  // 設定 / メモリ / 統計
  //---------------------------------------------------------------------------
  int unsigned           stall_pct;
  bit                    ready_wait_valid;
  logic [ADDR_WIDTH-1:0] err_lo;
  logic [ADDR_WIDTH-1:0] err_hi;

  bit [7:0]              mem [bit [ADDR_WIDTH-1:0]];

  int unsigned           n_viol;
  int unsigned           n_aw;
  int unsigned           n_ar;
  int unsigned           n_wbeat;
  int unsigned           n_rbeat;
  int unsigned           max_awlen;
  int unsigned           max_arlen;

  initial begin
    stall_pct        = 0;
    ready_wait_valid = 1'b0;
    err_lo    = {ADDR_WIDTH{1'b1}};
    err_hi    = {ADDR_WIDTH{1'b0}};
    n_viol    = 0;
    n_aw      = 0;
    n_ar      = 0;
    n_wbeat   = 0;
    n_rbeat   = 0;
    max_awlen = 0;
    max_arlen = 0;
  end

  //---------------------------------------------------------------------------
  // ヘルパ
  //---------------------------------------------------------------------------
  function automatic bit f_stall();
    return ($urandom_range(99,0)<stall_pct);
  endfunction

  function automatic int unsigned f_delay();
    if( f_stall() ) begin
      return $urandom_range(4,1);
    end
    return 0;
  endfunction

  // 次サイクルの READY
  //   通常モード      : VALID と無関係にランダム
  //   VALID 待ちモード : VALID が立っていて、このサイクルで握手していなければ立てる
  function automatic bit f_ready_next( input bit valid_now, input bit hs_now );
    if( ready_wait_valid ) begin
      return valid_now&&!hs_now&&!f_stall();
    end
    return !f_stall();
  endfunction

  function automatic bit f_in_err( input logic [ADDR_WIDTH-1:0] a );
    return (err_lo<=err_hi)&&(a>=err_lo)&&(a<=err_hi);
  endfunction

  // バースト内 beat 番目のアドレス (AXI4 spec A3.4.1)
  function automatic logic [ADDR_WIDTH-1:0] f_beat_addr
  (
    input logic [ADDR_WIDTH-1:0] start
   ,input logic [7:0]            len
   ,input logic [2:0]            size
   ,input logic [1:0]            burst
   ,input int unsigned           beat
  );
    logic [ADDR_WIDTH-1:0] nbytes;
    logic [ADDR_WIDTH-1:0] total;
    logic [ADDR_WIDTH-1:0] lo;
    nbytes = ADDR_WIDTH'(1) << size;
    if( burst==2'b00 ) begin
      return start;
    end else if( burst==2'b10 ) begin
      total = nbytes * (ADDR_WIDTH'(len) + ADDR_WIDTH'(1));
      lo    = start & ~(total - ADDR_WIDTH'(1));
      return lo + ((start - lo + (nbytes * ADDR_WIDTH'(beat))) % total);
    end else begin
      if( beat==0 ) begin
        return start;
      end
      return (start & ~(nbytes - ADDR_WIDTH'(1))) + (nbytes * ADDR_WIDTH'(beat));
    end
  endfunction

  function automatic logic [DATA_WIDTH-1:0] peek_word( input logic [ADDR_WIDTH-1:0] a );
    logic [ADDR_WIDTH-1:0] base;
    logic [DATA_WIDTH-1:0] d;
    base = {a[ADDR_WIDTH-1:ADDR_LSB], {ADDR_LSB{1'b0}}};
    d    = '0;
    for( int b=0; b<STRB_W; b++ ) begin
      if( mem.exists(base+ADDR_WIDTH'(b)) ) begin
        d[8*b+:8] = mem[base+ADDR_WIDTH'(b)];
      end
    end
    return d;
  endfunction

  function automatic void poke_word( input logic [ADDR_WIDTH-1:0] a, input logic [DATA_WIDTH-1:0] d );
    logic [ADDR_WIDTH-1:0] base;
    base = {a[ADDR_WIDTH-1:ADDR_LSB], {ADDR_LSB{1'b0}}};
    for( int b=0; b<STRB_W; b++ ) begin
      mem[base+ADDR_WIDTH'(b)] = d[8*b+:8];
    end
  endfunction

  function automatic void violation( input string msg );
    n_viol++;
    $display("[%0t] AXI_SLAVE_MODEL : PROTOCOL VIOLATION : %s", $time, msg);
  endfunction

  // AW / AR 受領時のバースト規則チェック
  function automatic void check_burst
  (
    input string                 ch
   ,input logic [ADDR_WIDTH-1:0] addr
   ,input logic [7:0]            len
   ,input logic [2:0]            size
   ,input logic [1:0]            burst
  );
    int unsigned nbytes;
    nbytes = 1 << size;
    if( burst==2'b11 ) begin
      violation($sformatf("%s reserved burst type", ch));
    end
    if( nbytes>STRB_W ) begin
      violation($sformatf("%s size %0d is wider than the bus", ch, size));
    end
    if( (32'(len)+1)>MAX_BURST ) begin
      violation($sformatf("%s len+1=%0d exceeds MAX_BURST=%0d", ch, 32'(len)+1, MAX_BURST));
    end
    if( (burst==2'b01)&&((32'(addr[11:0])+((32'(len)+1)*nbytes))>4096) ) begin
      violation($sformatf("%s INCR burst crosses 4KB boundary : addr=%h len=%0d", ch, addr, len));
    end
  endfunction

  //---------------------------------------------------------------------------
  // Write 側
  //---------------------------------------------------------------------------
  typedef enum logic [1:0] {
     W_IDLE = 2'd0
    ,W_DATA = 2'd1
    ,W_RESP = 2'd2
  } wst_e;

  wst_e                  wst;
  logic [ID_WIDTH-1:0]   aw_id_q;
  logic [ADDR_WIDTH-1:0] aw_addr_q;
  logic [7:0]            aw_len_q;
  logic [2:0]            aw_size_q;
  logic [1:0]            aw_burst_q;
  int unsigned           w_beat;
  bit                    w_err;
  int unsigned           b_dly;

  always @(posedge aclk or negedge aresetn) begin
    logic [ADDR_WIDTH-1:0] a;
    logic [ADDR_WIDTH-1:0] base;
    if( !aresetn ) begin
      wst           <= W_IDLE;
      s_axi_awready <= 1'b0;
      s_axi_wready  <= 1'b0;
      s_axi_bvalid  <= 1'b0;
      s_axi_bid     <= '0;
      s_axi_bresp   <= RESP_OKAY;
      w_beat        <= 0;
      w_err         <= 1'b0;
      b_dly         <= 0;
    end else begin
      case( wst )
        W_IDLE : begin
          if( s_axi_awvalid&&s_axi_awready ) begin
            check_burst("AW", s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst);
            aw_id_q       <= s_axi_awid;
            aw_addr_q     <= s_axi_awaddr;
            aw_len_q      <= s_axi_awlen;
            aw_size_q     <= s_axi_awsize;
            aw_burst_q    <= s_axi_awburst;
            w_beat        <= 0;
            w_err         <= 1'b0;
            n_aw          <= n_aw + 1;
            if( 32'(s_axi_awlen)>max_awlen ) begin
              max_awlen <= 32'(s_axi_awlen);
            end
            s_axi_awready <= 1'b0;
            s_axi_wready  <= f_ready_next(s_axi_wvalid, 1'b0);
            wst           <= W_DATA;
          end else begin
            s_axi_awready <= f_ready_next(s_axi_awvalid, 1'b0);
          end
        end
        W_DATA : begin
          if( s_axi_wvalid&&s_axi_wready ) begin
            a    = f_beat_addr(aw_addr_q, aw_len_q, aw_size_q, aw_burst_q, w_beat);
            base = {a[ADDR_WIDTH-1:ADDR_LSB], {ADDR_LSB{1'b0}}};
            if( f_in_err(a) ) begin
              w_err <= 1'b1;
            end else begin
              for( int b=0; b<STRB_W; b++ ) begin
                if( s_axi_wstrb[b] ) begin
                  mem[base+ADDR_WIDTH'(b)] = s_axi_wdata[8*b+:8];
                end
              end
            end
            n_wbeat <= n_wbeat + 1;
            if( s_axi_wlast!==(w_beat==32'(aw_len_q)) ) begin
              violation($sformatf("WLAST=%b at beat %0d (AWLEN=%0d)", s_axi_wlast, w_beat, aw_len_q));
            end
            if( w_beat==32'(aw_len_q) ) begin
              s_axi_wready <= 1'b0;
              b_dly        <= f_delay();
              wst          <= W_RESP;
            end else begin
              w_beat       <= w_beat + 1;
              s_axi_wready <= f_ready_next(1'b1, 1'b1);
            end
          end else begin
            s_axi_wready <= f_ready_next(s_axi_wvalid, 1'b0);
          end
        end
        W_RESP : begin
          if( s_axi_bvalid ) begin
            if( s_axi_bready ) begin
              s_axi_bvalid  <= 1'b0;
              s_axi_awready <= f_ready_next(s_axi_awvalid, 1'b0);
              wst           <= W_IDLE;
            end
          end else if( b_dly==0 ) begin
            s_axi_bvalid <= 1'b1;
            s_axi_bid    <= aw_id_q;
            s_axi_bresp  <= w_err ? RESP_SLVERR : RESP_OKAY;
          end else begin
            b_dly <= b_dly - 1;
          end
        end
        default : begin
          wst <= W_IDLE;
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // Read 側
  //---------------------------------------------------------------------------
  typedef enum logic [0:0] {
     R_IDLE = 1'b0
    ,R_DATA = 1'b1
  } rst_e;

  rst_e                  rst;
  logic [ID_WIDTH-1:0]   ar_id_q;
  logic [ADDR_WIDTH-1:0] ar_addr_q;
  logic [7:0]            ar_len_q;
  logic [2:0]            ar_size_q;
  logic [1:0]            ar_burst_q;
  int unsigned           r_beat;
  int unsigned           r_dly;

  // beat 番目のデータを R に出す
  task automatic present_beat( input int unsigned beat );
    logic [ADDR_WIDTH-1:0] a;
    a             = f_beat_addr(ar_addr_q, ar_len_q, ar_size_q, ar_burst_q, beat);
    s_axi_rvalid <= 1'b1;
    s_axi_rid    <= ar_id_q;
    s_axi_rdata  <= peek_word(a);
    s_axi_rresp  <= f_in_err(a) ? RESP_SLVERR : RESP_OKAY;
    s_axi_rlast  <= (beat==32'(ar_len_q));
  endtask

  always @(posedge aclk or negedge aresetn) begin
    int unsigned d;
    if( !aresetn ) begin
      rst           <= R_IDLE;
      s_axi_arready <= 1'b0;
      s_axi_rvalid  <= 1'b0;
      s_axi_rid     <= '0;
      s_axi_rdata   <= '0;
      s_axi_rresp   <= RESP_OKAY;
      s_axi_rlast   <= 1'b0;
      r_beat        <= 0;
      r_dly         <= 0;
    end else begin
      case( rst )
        R_IDLE : begin
          if( s_axi_arvalid&&s_axi_arready ) begin
            check_burst("AR", s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst);
            ar_id_q       <= s_axi_arid;
            ar_addr_q     <= s_axi_araddr;
            ar_len_q      <= s_axi_arlen;
            ar_size_q     <= s_axi_arsize;
            ar_burst_q    <= s_axi_arburst;
            n_ar          <= n_ar + 1;
            if( 32'(s_axi_arlen)>max_arlen ) begin
              max_arlen <= 32'(s_axi_arlen);
            end
            s_axi_arready <= 1'b0;
            r_beat        <= 0;
            r_dly         <= f_delay();
            rst           <= R_DATA;
          end else begin
            s_axi_arready <= f_ready_next(s_axi_arvalid, 1'b0);
          end
        end
        R_DATA : begin
          if( s_axi_rvalid ) begin
            if( s_axi_rready ) begin
              n_rbeat <= n_rbeat + 1;
              if( r_beat==32'(ar_len_q) ) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_rlast   <= 1'b0;
                s_axi_arready <= f_ready_next(s_axi_arvalid, 1'b0);
                rst           <= R_IDLE;
              end else begin
                r_beat <= r_beat + 1;
                d      = f_delay();
                if( d==0 ) begin
                  present_beat(r_beat + 1);
                end else begin
                  s_axi_rvalid <= 1'b0;
                  r_dly        <= d - 1;
                end
              end
            end
          end else if( r_dly==0 ) begin
            present_beat(r_beat);
          end else begin
            r_dly <= r_dly - 1;
          end
        end
        default : begin
          rst <= R_IDLE;
        end
      endcase
    end
  end

  //---------------------------------------------------------------------------
  // マスタ側の VALID 保持 / ペイロード安定のチェック
  //---------------------------------------------------------------------------
  localparam int unsigned AX_PL_W = ID_WIDTH + ADDR_WIDTH + 8 + 3 + 2;
  localparam int unsigned W_PL_W  = DATA_WIDTH + STRB_W + 1;

  logic               aw_wait_q;
  logic               w_wait_q;
  logic               ar_wait_q;
  logic [AX_PL_W-1:0] aw_pl_q;
  logic [W_PL_W-1:0]  w_pl_q;
  logic [AX_PL_W-1:0] ar_pl_q;
  logic [AX_PL_W-1:0] aw_pl;
  logic [W_PL_W-1:0]  w_pl;
  logic [AX_PL_W-1:0] ar_pl;

  assign aw_pl = {s_axi_awid, s_axi_awaddr, s_axi_awlen, s_axi_awsize, s_axi_awburst};
  assign w_pl  = {s_axi_wlast, s_axi_wstrb, s_axi_wdata};
  assign ar_pl = {s_axi_arid, s_axi_araddr, s_axi_arlen, s_axi_arsize, s_axi_arburst};

  always @(posedge aclk or negedge aresetn) begin
    if( !aresetn ) begin
      aw_wait_q <= 1'b0;
      w_wait_q  <= 1'b0;
      ar_wait_q <= 1'b0;
      aw_pl_q   <= '0;
      w_pl_q    <= '0;
      ar_pl_q   <= '0;
    end else begin
      if( aw_wait_q ) begin
        if( s_axi_awvalid!==1'b1 ) begin
          violation("AWVALID dropped before AWREADY");
        end else if( aw_pl!==aw_pl_q ) begin
          violation("AW payload changed before handshake");
        end
      end
      if( w_wait_q ) begin
        if( s_axi_wvalid!==1'b1 ) begin
          violation("WVALID dropped before WREADY");
        end else if( w_pl!==w_pl_q ) begin
          violation("W payload changed before handshake");
        end
      end
      if( ar_wait_q ) begin
        if( s_axi_arvalid!==1'b1 ) begin
          violation("ARVALID dropped before ARREADY");
        end else if( ar_pl!==ar_pl_q ) begin
          violation("AR payload changed before handshake");
        end
      end
      aw_wait_q <= s_axi_awvalid&&!s_axi_awready;
      w_wait_q  <= s_axi_wvalid&&!s_axi_wready;
      ar_wait_q <= s_axi_arvalid&&!s_axi_arready;
      aw_pl_q   <= aw_pl;
      w_pl_q    <= w_pl;
      ar_pl_q   <= ar_pl;
    end
  end

endmodule

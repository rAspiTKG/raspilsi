//=============================================================================
// axil_slave_mem_model.sv
//-----------------------------------------------------------------------------
//  検証用 AXI4-Lite スレーブ (Subordinate) + メモリ。プロトコルチェック付き。
//
//  振る舞い (テストベンチが変数で切り替える):
//    - AWREADY / WREADY / ARREADY : 毎サイクル乱数で決める (*_ready_pct [%]。100 なら常に 1)
//        aw_wait_w = 1 : W のデータが来ているまで AWREADY を出さない
//        w_wait_aw = 1 : AW のアドレスが来ているまで WREADY を出さない
//        (マスタが「READY を待ってから相手のチャネルの VALID を出す」作りだと、ここでデッドロックする)
//    - B / R の遅延 : AW と W (または AR) を受け取った次のサイクルから、b_lat / r_lat サイクル後に VALID
//                     (範囲内の乱数)。応答は受け取った順に返す (AXI4-Lite には ID が無い)
//    - エラー応答 : 書き込み / 読み出しそれぞれ、アドレス範囲 2 つまでに SLVERR / DECERR / EXOKAY を返す
//                   (範囲ごとに応答を決める。エラーの書き込みはメモリに反映しない)
//    - noise = 1 : VALID=0 のときの BRESP / RDATA / RRESP を乱数にする (見てはいけない値)
//
//  チェック (違反は n_viol に数える):
//    - リセット中は AWVALID / WVALID / ARVALID が 0
//    - VALID を出したら READY まで下げない。その間アドレス / PROT / データ / WSTRB を変えない
//    - VALID / READY が X にならない。VALID のときのペイロードが X にならない
//    - バス上の未完了数 (AW / W / AR を受け取って、まだ応答を返し終えていない数) が
//      MAX_WR_OUTSTANDING / MAX_RD_OUTSTANDING を超えない
//  非アラインのアドレスは n_unaligned に数える。
//
//  ログ (テストベンチが照合する): 応答を返し終えた順に、書き込み / 読み出しそれぞれ
//    wlog_* : アドレス / PROT / データ / WSTRB / 応答
//    rlog_* : アドレス / PROT / データ / 応答
//=============================================================================
`timescale 1ns / 1ps

module axil_slave_mem_model #(
  parameter int unsigned ADDR_WIDTH         = 32
 ,parameter int unsigned DATA_WIDTH         = 32
 ,parameter int unsigned MAX_WR_OUTSTANDING = 4
 ,parameter int unsigned MAX_RD_OUTSTANDING = 4
) (
  input  logic                      aclk
 ,input  logic                      aresetn
 ,input  logic [ADDR_WIDTH-1:0]     awaddr
 ,input  logic [2:0]                awprot
 ,input  logic                      awvalid
 ,output logic                      awready
 ,input  logic [DATA_WIDTH-1:0]     wdata
 ,input  logic [(DATA_WIDTH/8)-1:0] wstrb
 ,input  logic                      wvalid
 ,output logic                      wready
 ,output logic [1:0]                bresp
 ,output logic                      bvalid
 ,input  logic                      bready
 ,input  logic [ADDR_WIDTH-1:0]     araddr
 ,input  logic [2:0]                arprot
 ,input  logic                      arvalid
 ,output logic                      arready
 ,output logic [DATA_WIDTH-1:0]     rdata
 ,output logic [1:0]                rresp
 ,output logic                      rvalid
 ,input  logic                      rready
);

  localparam int unsigned STRB_W = DATA_WIDTH / 8;

  //---------------------------------------------------------------------------
  // 設定 (テストベンチが書き換える)
  //---------------------------------------------------------------------------
  int unsigned     aw_ready_pct;
  int unsigned     w_ready_pct;
  int unsigned     ar_ready_pct;
  bit              aw_wait_w;
  bit              w_wait_aw;
  int unsigned     b_lat_min;
  int unsigned     b_lat_max;
  int unsigned     r_lat_min;
  int unsigned     r_lat_max;
  bit              noise;
  // エラー応答 (アドレス範囲 [lo, hi] を 2 つまで。resp が 2'b00 なら無効。両方に入るときは [0] が優先)
  bit [1:0]        werr_resp [2];
  bit [63:0]       werr_lo   [2];
  bit [63:0]       werr_hi   [2];
  bit [1:0]        rerr_resp [2];
  bit [63:0]       rerr_lo   [2];
  bit [63:0]       rerr_hi   [2];

  //---------------------------------------------------------------------------
  // メモリ (ワード単位、キーはワード先頭のアドレス)
  //---------------------------------------------------------------------------
  bit [DATA_WIDTH-1:0] mem [bit [63:0]];

  function automatic bit [63:0] f_base( input bit [63:0] a );
    return a & ~64'(STRB_W-1);
  endfunction

  function automatic bit [DATA_WIDTH-1:0] peek_word( input bit [63:0] a );
    if( mem.exists(f_base(a)) ) begin
      return mem[f_base(a)];
    end
    return {DATA_WIDTH{1'b0}};
  endfunction

  function automatic void poke_word( input bit [63:0] a, input bit [DATA_WIDTH-1:0] d );
    mem[f_base(a)] = d;
  endfunction

  function automatic bit [1:0] f_wresp( input bit [63:0] a );
    for( int unsigned i=0; i<2; i++ ) begin
      if( (werr_resp[i]!=2'b00)&&(a>=werr_lo[i])&&(a<=werr_hi[i]) ) begin
        return werr_resp[i];
      end
    end
    return 2'b00;
  endfunction

  function automatic bit [1:0] f_rresp( input bit [63:0] a );
    for( int unsigned i=0; i<2; i++ ) begin
      if( (rerr_resp[i]!=2'b00)&&(a>=rerr_lo[i])&&(a<=rerr_hi[i]) ) begin
        return rerr_resp[i];
      end
    end
    return 2'b00;
  endfunction

  //---------------------------------------------------------------------------
  // ログと統計
  //---------------------------------------------------------------------------
  bit [63:0]           wlog_addr [$];
  bit [2:0]            wlog_prot [$];
  bit [DATA_WIDTH-1:0] wlog_data [$];
  bit [STRB_W-1:0]     wlog_strb [$];
  bit [1:0]            wlog_resp [$];
  bit [63:0]           rlog_addr [$];
  bit [2:0]            rlog_prot [$];
  bit [DATA_WIDTH-1:0] rlog_data [$];
  bit [1:0]            rlog_resp [$];

  int unsigned n_viol;
  int unsigned n_unaligned;
  int unsigned n_wr;
  int unsigned n_rd;
  int unsigned n_wr_err;
  int unsigned n_rd_err;
  int unsigned max_wr_out;
  int unsigned max_rd_out;
  int unsigned n_both;          // 書き込みと読み出しの両方がバス上で未完了だったサイクル数
  int unsigned n_aw_first;      // W より先に AW を受け取った書き込みの数
  int unsigned n_w_first;       // AW より先に W を受け取った書き込みの数

  task automatic clear_wlog();
    wlog_addr.delete();
    wlog_prot.delete();
    wlog_data.delete();
    wlog_strb.delete();
    wlog_resp.delete();
  endtask

  task automatic clear_rlog();
    rlog_addr.delete();
    rlog_prot.delete();
    rlog_data.delete();
    rlog_resp.delete();
  endtask

  task automatic clear_log();
    clear_wlog();
    clear_rlog();
  endtask

  task automatic set_ready( input int unsigned aw, input int unsigned w, input int unsigned ar );
    aw_ready_pct = aw;
    w_ready_pct  = w;
    ar_ready_pct = ar;
  endtask

  task automatic set_lat( input int unsigned bmin, input int unsigned bmax, input int unsigned rmin, input int unsigned rmax );
    b_lat_min = bmin;
    b_lat_max = bmax;
    r_lat_min = rmin;
    r_lat_max = rmax;
  endtask

  task automatic clear_err();
    for( int unsigned i=0; i<2; i++ ) begin
      werr_resp[i] = 2'b00;
      rerr_resp[i] = 2'b00;
    end
  endtask

  task automatic set_werr( input int unsigned i, input bit [1:0] resp, input bit [63:0] lo, input bit [63:0] hi );
    werr_resp[i] = resp;
    werr_lo[i]   = lo;
    werr_hi[i]   = hi;
  endtask

  task automatic set_rerr( input int unsigned i, input bit [1:0] resp, input bit [63:0] lo, input bit [63:0] hi );
    rerr_resp[i] = resp;
    rerr_lo[i]   = lo;
    rerr_hi[i]   = hi;
  endtask

  initial begin
    aw_ready_pct = 100;
    w_ready_pct  = 100;
    ar_ready_pct = 100;
    aw_wait_w    = 1'b0;
    w_wait_aw    = 1'b0;
    b_lat_min    = 0;
    b_lat_max    = 0;
    r_lat_min    = 0;
    r_lat_max    = 0;
    noise        = 1'b1;
    for( int unsigned i=0; i<2; i++ ) begin
      werr_resp[i] = 2'b00;
      werr_lo[i]   = 64'd0;
      werr_hi[i]   = 64'd0;
      rerr_resp[i] = 2'b00;
      rerr_lo[i]   = 64'd0;
      rerr_hi[i]   = 64'd0;
    end
    n_viol       = 0;
    n_unaligned  = 0;
    n_wr         = 0;
    n_rd         = 0;
    n_wr_err     = 0;
    n_rd_err     = 0;
    max_wr_out   = 0;
    max_rd_out   = 0;
    n_both       = 0;
    n_aw_first   = 0;
    n_w_first    = 0;
  end

  function automatic void violation( input string msg );
    n_viol++;
    $display("[%0t] AXIL_SLAVE_MODEL : PROTOCOL VIOLATION : %s", $time, msg);
  endfunction

  function automatic logic [DATA_WIDTH-1:0] f_rand_data();
    logic [DATA_WIDTH-1:0] d;
    for( int unsigned i=0; i<DATA_WIDTH; i++ ) begin
      d[i] = 1'($urandom());
    end
    return d;
  endfunction

  //---------------------------------------------------------------------------
  // 内部のキュー
  //---------------------------------------------------------------------------
  typedef struct packed {
    bit [63:0] addr;
    bit [2:0]  prot;
  } a_t;

  typedef struct packed {
    bit [DATA_WIDTH-1:0] data;
    bit [STRB_W-1:0]     strb;
  } w_t;

  typedef struct packed {
    bit [63:0]           addr;
    bit [2:0]            prot;
    bit [DATA_WIDTH-1:0] data;
    bit [STRB_W-1:0]     strb;
    bit [1:0]            resp;
    bit [63:0]           t;        // このサイクル以降に VALID を出してよい
  } rsp_t;

  a_t              aw_q [$];
  w_t              w_q  [$];
  rsp_t            b_q  [$];
  rsp_t            r_q  [$];
  longint unsigned cyc;            // これから始まるサイクルの番号
  longint unsigned b_last_t;
  longint unsigned r_last_t;
  int unsigned     wr_out;         // バス上の未完了数 (AW を受け取ってから B を返し終えるまで)
  int unsigned     w_out;          // W を受け取ってから B を返し終えるまで
  int unsigned     rd_out;
  // 安定性の確認用 (前のサイクルの値)
  logic                  p_awvalid;
  logic                  p_awready;
  logic [ADDR_WIDTH-1:0] p_awaddr;
  logic [2:0]            p_awprot;
  logic                  p_wvalid;
  logic                  p_wready;
  logic [DATA_WIDTH-1:0] p_wdata;
  logic [STRB_W-1:0]     p_wstrb;
  logic                  p_arvalid;
  logic                  p_arready;
  logic [ADDR_WIDTH-1:0] p_araddr;
  logic [2:0]            p_arprot;

  //---------------------------------------------------------------------------
  // リセット中の VALID (リセットを入れたクロックエッジ以降で見る。
  // リセットの立ち下がりと同時刻には、マスタ側のリセットがまだ反映されていないため)
  //---------------------------------------------------------------------------
  always @(posedge aclk) begin
    if( !aresetn&&((awvalid!==1'b0)||(wvalid!==1'b0)||(arvalid!==1'b0)) ) begin
      violation($sformatf("VALID during reset : AWVALID=%b WVALID=%b ARVALID=%b", awvalid, wvalid, arvalid));
    end
  end

  //---------------------------------------------------------------------------
  // 本体
  //---------------------------------------------------------------------------
  always @(posedge aclk or negedge aresetn) begin
    bit              aw_hs;
    bit              w_hs;
    bit              ar_hs;
    bit              b_hs;
    bit              r_hs;
    a_t              a;
    w_t              w;
    rsp_t            e;
    bit [DATA_WIDTH-1:0] m;
    int unsigned     lat;
    if( !aresetn ) begin
      awready   <= 1'b0;
      wready    <= 1'b0;
      arready   <= 1'b0;
      bvalid    <= 1'b0;
      bresp     <= 2'b00;
      rvalid    <= 1'b0;
      rresp     <= 2'b00;
      rdata     <= {DATA_WIDTH{1'b0}};
      aw_q.delete();
      w_q.delete();
      b_q.delete();
      r_q.delete();
      cyc       = 0;
      b_last_t  = 0;
      r_last_t  = 0;
      wr_out    = 0;
      w_out     = 0;
      rd_out    = 0;
      p_awvalid <= 1'b0;
      p_awready <= 1'b0;
      p_wvalid  <= 1'b0;
      p_wready  <= 1'b0;
      p_arvalid <= 1'b0;
      p_arready <= 1'b0;
    end else begin
      cyc = cyc + 1;
      //-----------------------------------------------------------------------
      // X / 安定性のチェック (このエッジでサンプルした値 = 終わったサイクルの値)
      //-----------------------------------------------------------------------
      if( $isunknown({awvalid,wvalid,arvalid,bready,rready}) ) begin
        violation("AWVALID / WVALID / ARVALID / BREADY / RREADY is X");
      end
      if( (awvalid===1'b1)&&$isunknown({awaddr,awprot}) ) begin
        violation("AWADDR / AWPROT is X while AWVALID=1");
      end
      if( (wvalid===1'b1)&&$isunknown({wdata,wstrb}) ) begin
        violation("WDATA / WSTRB is X while WVALID=1");
      end
      if( (arvalid===1'b1)&&$isunknown({araddr,arprot}) ) begin
        violation("ARADDR / ARPROT is X while ARVALID=1");
      end
      if( p_awvalid&&!p_awready ) begin
        if( awvalid!==1'b1 ) begin
          violation("AWVALID was deasserted before AWREADY");
        end else if( (awaddr!==p_awaddr)||(awprot!==p_awprot) ) begin
          violation("AWADDR / AWPROT changed while AWVALID=1 and AWREADY=0");
        end
      end
      if( p_wvalid&&!p_wready ) begin
        if( wvalid!==1'b1 ) begin
          violation("WVALID was deasserted before WREADY");
        end else if( (wdata!==p_wdata)||(wstrb!==p_wstrb) ) begin
          violation("WDATA / WSTRB changed while WVALID=1 and WREADY=0");
        end
      end
      if( p_arvalid&&!p_arready ) begin
        if( arvalid!==1'b1 ) begin
          violation("ARVALID was deasserted before ARREADY");
        end else if( (araddr!==p_araddr)||(arprot!==p_arprot) ) begin
          violation("ARADDR / ARPROT changed while ARVALID=1 and ARREADY=0");
        end
      end
      p_awvalid <= awvalid;
      p_awready <= awready;
      p_awaddr  <= awaddr;
      p_awprot  <= awprot;
      p_wvalid  <= wvalid;
      p_wready  <= wready;
      p_wdata   <= wdata;
      p_wstrb   <= wstrb;
      p_arvalid <= arvalid;
      p_arready <= arready;
      p_araddr  <= araddr;
      p_arprot  <= arprot;

      aw_hs = (awvalid===1'b1)&&(awready===1'b1);
      w_hs  = (wvalid===1'b1)&&(wready===1'b1);
      ar_hs = (arvalid===1'b1)&&(arready===1'b1);
      b_hs  = (bvalid===1'b1)&&(bready===1'b1);
      r_hs  = (rvalid===1'b1)&&(rready===1'b1);

      //-----------------------------------------------------------------------
      // 受け取り
      //-----------------------------------------------------------------------
      // AW と W のどちらが先に来たか (同じサイクルならどちらにも数えない)
      if( aw_hs&&!w_hs&&(w_q.size()==0) ) begin
        n_aw_first++;
      end
      if( w_hs&&!aw_hs&&(aw_q.size()==0) ) begin
        n_w_first++;
      end
      if( aw_hs ) begin
        a.addr = 64'(awaddr);
        a.prot = awprot;
        aw_q.push_back(a);
        wr_out++;
        if( f_base(64'(awaddr))!=64'(awaddr) ) begin
          n_unaligned++;
        end
      end
      if( w_hs ) begin
        w.data = wdata;
        w.strb = wstrb;
        w_q.push_back(w);
        w_out++;
      end
      if( ar_hs ) begin
        a.addr = 64'(araddr);
        a.prot = arprot;
        rd_out++;
        if( f_base(64'(araddr))!=64'(araddr) ) begin
          n_unaligned++;
        end
        // 応答を予約 (データは受け取った時点のメモリ)
        e.addr = a.addr;
        e.prot = a.prot;
        e.resp = f_rresp(a.addr);
        e.strb = {STRB_W{1'b0}};
        if( e.resp==2'b00 ) begin
          e.data = peek_word(a.addr);
        end else begin
          e.data = f_rand_data();
        end
        lat = $urandom_range(r_lat_max, r_lat_min);
        e.t = cyc + 64'(lat);
        if( e.t<r_last_t ) begin
          e.t = r_last_t;
        end
        r_last_t = e.t;
        r_q.push_back(e);
      end
      // AW と W がそろったら書き込みを実行し、応答を予約する
      while( (aw_q.size()!=0)&&(w_q.size()!=0) ) begin
        a = aw_q.pop_front();
        w = w_q.pop_front();
        e.addr = a.addr;
        e.prot = a.prot;
        e.data = w.data;
        e.strb = w.strb;
        e.resp = f_wresp(a.addr);
        if( e.resp==2'b00 ) begin
          m = peek_word(a.addr);
          for( int unsigned b=0; b<STRB_W; b++ ) begin
            if( w.strb[b] ) begin
              m[8*b +: 8] = w.data[8*b +: 8];
            end
          end
          poke_word(a.addr, m);
        end
        lat = $urandom_range(b_lat_max, b_lat_min);
        e.t = cyc + 64'(lat);
        if( e.t<b_last_t ) begin
          e.t = b_last_t;
        end
        b_last_t = e.t;
        b_q.push_back(e);
      end

      //-----------------------------------------------------------------------
      // 応答 (B)
      //-----------------------------------------------------------------------
      if( b_hs ) begin
        e = b_q.pop_front();
        wlog_addr.push_back(e.addr);
        wlog_prot.push_back(e.prot);
        wlog_data.push_back(e.data);
        wlog_strb.push_back(e.strb);
        wlog_resp.push_back(e.resp);
        n_wr++;
        if( e.resp!=2'b00 ) begin
          n_wr_err++;
        end
        wr_out--;
        w_out--;
      end
      if( (bvalid!==1'b1)||b_hs ) begin
        if( (b_q.size()!=0)&&(b_q[0].t<=cyc) ) begin
          bvalid <= 1'b1;
          bresp  <= b_q[0].resp;
        end else begin
          bvalid <= 1'b0;
          if( noise ) begin
            bresp <= 2'($urandom());
          end else begin
            bresp <= 2'b00;
          end
        end
      end

      //-----------------------------------------------------------------------
      // 応答 (R)
      //-----------------------------------------------------------------------
      if( r_hs ) begin
        e = r_q.pop_front();
        rlog_addr.push_back(e.addr);
        rlog_prot.push_back(e.prot);
        rlog_data.push_back(e.data);
        rlog_resp.push_back(e.resp);
        n_rd++;
        if( e.resp!=2'b00 ) begin
          n_rd_err++;
        end
        rd_out--;
      end
      if( (rvalid!==1'b1)||r_hs ) begin
        if( (r_q.size()!=0)&&(r_q[0].t<=cyc) ) begin
          rvalid <= 1'b1;
          rresp  <= r_q[0].resp;
          rdata  <= r_q[0].data;
        end else begin
          rvalid <= 1'b0;
          if( noise ) begin
            rresp <= 2'($urandom());
            rdata <= f_rand_data();
          end else begin
            rresp <= 2'b00;
            rdata <= {DATA_WIDTH{1'b0}};
          end
        end
      end

      //-----------------------------------------------------------------------
      // 未完了数のチェック
      //-----------------------------------------------------------------------
      if( (wr_out>MAX_WR_OUTSTANDING)||(w_out>MAX_WR_OUTSTANDING) ) begin
        violation($sformatf("too many outstanding writes on the bus : AW %0d / W %0d (max %0d)", wr_out, w_out, MAX_WR_OUTSTANDING));
      end
      if( rd_out>MAX_RD_OUTSTANDING ) begin
        violation($sformatf("too many outstanding reads on the bus : %0d (max %0d)", rd_out, MAX_RD_OUTSTANDING));
      end
      if( wr_out>max_wr_out ) begin
        max_wr_out = wr_out;
      end
      if( rd_out>max_rd_out ) begin
        max_rd_out = rd_out;
      end
      if( (wr_out!=0)&&(rd_out!=0) ) begin
        n_both++;
      end

      //-----------------------------------------------------------------------
      // 次のサイクルの READY
      //-----------------------------------------------------------------------
      awready <= ($urandom_range(99, 0)<aw_ready_pct)&&!(aw_wait_w&&(w_q.size()==0)&&(wvalid!==1'b1));
      wready  <= ($urandom_range(99, 0)<w_ready_pct)&&!(w_wait_aw&&(aw_q.size()==0)&&(awvalid!==1'b1));
      arready <= ($urandom_range(99, 0)<ar_ready_pct);
    end
  end

endmodule

//=============================================================================
// apb_slave_mem_model.sv
//-----------------------------------------------------------------------------
//  APB マスタ検証用のスレーブ (Completer) メモリモデル (テストベンチ専用)。
//  NUM_SLAVES 個のスレーブをまとめて 1 モジュールにしてある
//  (スレーブ s は psel[s] / pready[s] / prdata[s*DATA_WIDTH +: DATA_WIDTH] / pslverr[s])。
//  各スレーブは独立に動く。
//
//  機能:
//    - スレーブごとのワード単位メモリ (poke_word / peek_word でバックドアアクセス)。
//      書き込みは PSTRB が 1 のバイトだけ反映する
//    - ウェイト : 転送ごとに wait_min[s]..wait_max[s] サイクルの間で乱数 (PREADY を遅らせる)
//    - PSLVERR 注入 : [err_lo[s], err_hi[s]] のアドレスへのアクセスは PSLVERR=1 で完了する
//      (書き込みはメモリに反映しない。読み出しデータは乱数)
//    - ハング : [hang_lo[s], hang_hi[s]] のアドレスへのアクセスは PREADY を返さない
//      (マスタのタイムアウト確認用)
//    - noise=1 : 仕様上「見てはいけない」タイミングの出力を乱数にする
//        * PENABLE=0 のとき / 選択されていないときの PREADY
//          (IHI 0024E: PREADY can take any value when PENABLE is LOW)
//        * PREADY=1 の完了サイクル以外の PSLVERR
//        * 読み出しの完了サイクル以外の PRDATA、エラー応答の PRDATA
//    - 完了した転送の記録 (log_* の待ち行列。全スレーブ共通でバス上の順) と統計
//    - マスタ側のプロトコルチェック (違反は n_viol に数える)
//        * SETUP (PSEL=1, PENABLE=0) は 1 サイクルで、次は必ず ACCESS (PENABLE=1)
//        * SETUP を経ずに ACCESS に入っていないか
//        * SETUP から完了まで PADDR / PPROT / PWRITE / PWDATA / PSTRB が変わらないか
//        * 完了の次のサイクルに PENABLE を下げているか
//        * 読み出しで PSTRB が 0 か
//        * PSEL が同時に 2 本以上立っていないか、制御信号に X が無いか
//    - PREADY を待たずに PSEL / PENABLE を下げた回数は n_abort に数える
//      (タイムアウトの確認で使う。それ以外では 0 のはず)
//
//  設定変数はテストベンチから階層参照で変更する。
//
//  参考: AMBA APB Protocol Specification (Arm IHI 0024E)
//        https://documentation-service.arm.com/static/63fe2c1356ea36189d4e79f3
//=============================================================================
`timescale 1ns / 1ps

module apb_slave_mem_model #(
  parameter int unsigned ADDR_WIDTH = 32
 ,parameter int unsigned DATA_WIDTH = 32
 ,parameter int unsigned NUM_SLAVES = 1
) (
  input  logic                               pclk
 ,input  logic                               presetn
 ,input  logic [ADDR_WIDTH-1:0]              paddr
 ,input  logic [2:0]                         pprot
 ,input  logic [NUM_SLAVES-1:0]              psel
 ,input  logic                               penable
 ,input  logic                               pwrite
 ,input  logic [DATA_WIDTH-1:0]              pwdata
 ,input  logic [(DATA_WIDTH/8)-1:0]          pstrb
 ,output logic [NUM_SLAVES-1:0]              pready
 ,output logic [(NUM_SLAVES*DATA_WIDTH)-1:0] prdata
 ,output logic [NUM_SLAVES-1:0]              pslverr
);

  localparam int unsigned STRB_W = DATA_WIDTH / 8;

  typedef enum logic [1:0] {
    M_IDLE = 2'd0
   ,M_WAIT = 2'd1
   ,M_RESP = 2'd2
  } mst_e;

  //---------------------------------------------------------------------------
  // 設定 (スレーブごと)
  //---------------------------------------------------------------------------
  int unsigned           wait_min [NUM_SLAVES];
  int unsigned           wait_max [NUM_SLAVES];
  logic [ADDR_WIDTH-1:0] err_lo   [NUM_SLAVES];
  logic [ADDR_WIDTH-1:0] err_hi   [NUM_SLAVES];
  logic [ADDR_WIDTH-1:0] hang_lo  [NUM_SLAVES];
  logic [ADDR_WIDTH-1:0] hang_hi  [NUM_SLAVES];
  bit                    noise;

  //---------------------------------------------------------------------------
  // メモリ (キーは {スレーブ番号, ワード先頭アドレス})
  //---------------------------------------------------------------------------
  bit [DATA_WIDTH-1:0]   mem [bit [63:0]];

  //---------------------------------------------------------------------------
  // 統計
  //---------------------------------------------------------------------------
  int unsigned           n_viol;
  int unsigned           n_abort;
  int unsigned           n_xfer;
  int unsigned           n_write;
  int unsigned           n_read;
  int unsigned           n_err;
  int unsigned           n_b2b;         // 直前の転送に続けて (IDLE を挟まずに) 始まった転送の数
  int unsigned           n_unaligned;
  int unsigned           max_wait;

  // 完了した転送の記録 (バス上の順。テストベンチが取り出して照合する)
  int unsigned           log_slv   [$];
  logic [ADDR_WIDTH-1:0] log_addr  [$];
  logic                  log_write [$];
  logic [DATA_WIDTH-1:0] log_wdata [$];
  logic [STRB_W-1:0]     log_strb  [$];
  logic [2:0]            log_prot  [$];
  logic [DATA_WIDTH-1:0] log_rdata [$];
  logic                  log_err   [$];
  int unsigned           log_wait  [$];

  initial begin
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      wait_min[s] = 0;
      wait_max[s] = 0;
      err_lo[s]   = {ADDR_WIDTH{1'b1}};
      err_hi[s]   = {ADDR_WIDTH{1'b0}};
      hang_lo[s]  = {ADDR_WIDTH{1'b1}};
      hang_hi[s]  = {ADDR_WIDTH{1'b0}};
    end
    noise       = 1'b1;
    n_viol      = 0;
    n_abort     = 0;
    n_xfer      = 0;
    n_write     = 0;
    n_read      = 0;
    n_err       = 0;
    n_b2b       = 0;
    n_unaligned = 0;
    max_wait    = 0;
  end

  //---------------------------------------------------------------------------
  // ヘルパ
  //---------------------------------------------------------------------------
  function automatic bit f_in_err( input int unsigned s, input logic [ADDR_WIDTH-1:0] a );
    return (err_lo[s]<=err_hi[s])&&(a>=err_lo[s])&&(a<=err_hi[s]);
  endfunction

  function automatic bit f_in_hang( input int unsigned s, input logic [ADDR_WIDTH-1:0] a );
    return (hang_lo[s]<=hang_hi[s])&&(a>=hang_lo[s])&&(a<=hang_hi[s]);
  endfunction

  function automatic logic [ADDR_WIDTH-1:0] f_base( input logic [ADDR_WIDTH-1:0] a );
    return a & ~ADDR_WIDTH'(STRB_W-1);
  endfunction

  function automatic bit [63:0] f_key( input int unsigned s, input logic [ADDR_WIDTH-1:0] a );
    return {32'(s), 32'(f_base(a))};
  endfunction

  function automatic logic [DATA_WIDTH-1:0] peek_word( input int unsigned s, input logic [ADDR_WIDTH-1:0] a );
    if( mem.exists(f_key(s,a)) ) begin
      return mem[f_key(s, a)];
    end
    return {DATA_WIDTH{1'b0}};
  endfunction

  function automatic void poke_word( input int unsigned s, input logic [ADDR_WIDTH-1:0] a, input logic [DATA_WIDTH-1:0] d );
    mem[f_key(s, a)] = d;
  endfunction

  function automatic void clear_err();
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      err_lo[s]  = {ADDR_WIDTH{1'b1}};
      err_hi[s]  = {ADDR_WIDTH{1'b0}};
      hang_lo[s] = {ADDR_WIDTH{1'b1}};
      hang_hi[s] = {ADDR_WIDTH{1'b0}};
    end
  endfunction

  function automatic void set_wait( input int unsigned lo, input int unsigned hi );
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      wait_min[s] = lo;
      wait_max[s] = hi;
    end
  endfunction

  function automatic void clear_log();
    log_slv.delete();
    log_addr.delete();
    log_write.delete();
    log_wdata.delete();
    log_strb.delete();
    log_prot.delete();
    log_rdata.delete();
    log_err.delete();
    log_wait.delete();
  endfunction

  function automatic void violation( input int unsigned s, input string msg );
    n_viol++;
    $display("[%0t] APB_SLAVE_MODEL[%0d] : PROTOCOL VIOLATION : %s", $time, s, msg);
  endfunction

  function automatic logic [DATA_WIDTH-1:0] f_rand_data();
    logic [DATA_WIDTH-1:0] d;
    for( int unsigned i=0; i<DATA_WIDTH; i++ ) begin
      d[i] = 1'($urandom());
    end
    return d;
  endfunction

  //---------------------------------------------------------------------------
  // 応答の生成 (スレーブごとに独立)
  //   出力は登録値。SETUP を見たエッジで、次のサイクル (最初の ACCESS) の値を決める
  //---------------------------------------------------------------------------
  mst_e                  mst         [NUM_SLAVES];
  int unsigned           wleft       [NUM_SLAVES];   // 残りウェイト数
  int unsigned           wcount      [NUM_SLAVES];   // この転送で入れたウェイト数
  bit                    hang_q      [NUM_SLAVES];
  bit                    last_done_q [NUM_SLAVES];   // 直前のサイクルで転送が完了した
  logic                  setup_q     [NUM_SLAVES];
  logic                  done_q      [NUM_SLAVES];
  // SETUP で取り込んだ値 (安定性の確認用)
  logic [ADDR_WIDTH-1:0] s_addr      [NUM_SLAVES];
  logic [2:0]            s_prot      [NUM_SLAVES];
  logic                  s_write     [NUM_SLAVES];
  logic [DATA_WIDTH-1:0] s_wdata     [NUM_SLAVES];
  logic [STRB_W-1:0]     s_strb      [NUM_SLAVES];

  // 見てはいけないタイミングの出力
  task automatic drive_idle( input int unsigned s );
    if( noise ) begin
      pready[s]                          <= 1'($urandom());
      pslverr[s]                         <= 1'($urandom());
      prdata[s*DATA_WIDTH +: DATA_WIDTH] <= f_rand_data();
    end else begin
      pready[s]                          <= 1'b0;
      pslverr[s]                         <= 1'b0;
      prdata[s*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
    end
  endtask

  // ウェイト中の出力 (PREADY=0)
  task automatic drive_wait( input int unsigned s );
    pready[s] <= 1'b0;
    if( noise ) begin
      pslverr[s]                         <= 1'($urandom());
      prdata[s*DATA_WIDTH +: DATA_WIDTH] <= f_rand_data();
    end else begin
      pslverr[s]                         <= 1'b0;
      prdata[s*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
    end
  endtask

  // 完了サイクルの出力 (PREADY=1)
  task automatic drive_resp( input int unsigned s, input logic [ADDR_WIDTH-1:0] a, input logic wr );
    pready[s]  <= 1'b1;
    pslverr[s] <= f_in_err(s, a);
    if( !wr&&!f_in_err(s,a) ) begin
      prdata[s*DATA_WIDTH +: DATA_WIDTH] <= peek_word(s, a);
    end else if( noise ) begin
      prdata[s*DATA_WIDTH +: DATA_WIDTH] <= f_rand_data();
    end else begin
      prdata[s*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
    end
  endtask

  always @(posedge pclk or negedge presetn) begin
    logic [DATA_WIDTH-1:0] w;
    int unsigned           n;
    if( !presetn ) begin
      pready  <= {NUM_SLAVES{1'b0}};
      pslverr <= {NUM_SLAVES{1'b0}};
      prdata  <= {(NUM_SLAVES*DATA_WIDTH){1'b0}};
      for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
        mst[s]         <= M_IDLE;
        wleft[s]       <= 0;
        wcount[s]      <= 0;
        hang_q[s]      <= 1'b0;
        last_done_q[s] <= 1'b0;
        setup_q[s]     <= 1'b0;
        done_q[s]      <= 1'b0;
      end
    end else begin
      if( $isunknown(psel)||(penable===1'bx) ) begin
        violation(0, "PSEL / PENABLE is X");
      end
      if( !$isunknown(psel)&&!$onehot0(psel) ) begin
        violation(0, $sformatf("more than one PSEL is asserted : %b", psel));
      end
      for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
        last_done_q[s] <= 1'b0;
        // SETUP の次のサイクルは必ず ACCESS、完了の次のサイクルは PENABLE=0
        if( setup_q[s]&&!((psel[s]===1'b1)&&(penable===1'b1)) ) begin
          violation(s, "SETUP was not followed by ACCESS in the next cycle");
        end
        if( done_q[s]&&(psel[s]===1'b1)&&(penable===1'b1) ) begin
          violation(s, "PENABLE was not deasserted after the transfer completed");
        end
        setup_q[s] <= (psel[s]===1'b1)&&(penable===1'b0);
        done_q[s]  <= (psel[s]===1'b1)&&(penable===1'b1)&&(pready[s]===1'b1);

        if( (psel[s]===1'b1)&&(penable===1'b0) ) begin
          //-------------------------------------------------------------------
          // SETUP
          //-------------------------------------------------------------------
          if( mst[s]!=M_IDLE ) begin
            // 前の転送が PREADY を待たずに打ち切られ、続けて次の転送が始まった
            n_abort <= n_abort + 1;
          end
          // 直前のサイクルが ACCESS だった (完了、または打ち切りの直前) なら back-to-back
          if( last_done_q[s]||(mst[s]!=M_IDLE) ) begin
            n_b2b <= n_b2b + 1;
          end
          if( $isunknown({paddr,pprot,pwrite,pstrb}) ) begin
            violation(s, "PADDR / PPROT / PWRITE / PSTRB is X in SETUP");
          end
          if( (pwrite===1'b1)&&$isunknown(pwdata) ) begin
            violation(s, "PWDATA is X in SETUP of a write");
          end
          if( (pwrite===1'b0)&&(pstrb!=={STRB_W{1'b0}}) ) begin
            violation(s, $sformatf("PSTRB=%b on a read transfer (must be 0)", pstrb));
          end
          if( f_base(paddr)!=paddr ) begin
            n_unaligned <= n_unaligned + 1;
          end
          s_addr[s]  <= paddr;
          s_prot[s]  <= pprot;
          s_write[s] <= pwrite;
          s_wdata[s] <= pwdata;
          s_strb[s]  <= pstrb;
          hang_q[s]  <= f_in_hang(s, paddr);
          n           = $urandom_range(wait_max[s], wait_min[s]);
          wcount[s]  <= n;
          if( f_in_hang(s,paddr) ) begin
            drive_wait(s);
            wleft[s] <= 0;
            mst[s]   <= M_WAIT;
          end else if( n==0 ) begin
            drive_resp(s, paddr, pwrite);
            mst[s] <= M_RESP;
          end else begin
            drive_wait(s);
            wleft[s] <= n;
            mst[s]   <= M_WAIT;
          end
        end else if( (psel[s]===1'b1)&&(penable===1'b1) ) begin
          //-------------------------------------------------------------------
          // ACCESS
          //-------------------------------------------------------------------
          if( mst[s]==M_IDLE ) begin
            violation(s, "ACCESS (PENABLE=1) without a SETUP cycle");
            drive_idle(s);
          end else begin
            if( (paddr!==s_addr[s])||(pprot!==s_prot[s])||(pwrite!==s_write[s])||(pstrb!==s_strb[s]) ) begin
              violation(s, "PADDR / PPROT / PWRITE / PSTRB changed during the transfer");
            end
            if( s_write[s]&&(pwdata!==s_wdata[s]) ) begin
              violation(s, "PWDATA changed during a write transfer");
            end
            if( mst[s]==M_RESP ) begin
              // このエッジで転送が完了する (PREADY=1 を出している)
              if( s_write[s]&&!f_in_err(s,s_addr[s]) ) begin
                w = peek_word(s, s_addr[s]);
                for( int unsigned b=0; b<STRB_W; b++ ) begin
                  if( s_strb[s][b] ) begin
                    w[8*b +: 8] = s_wdata[s][8*b +: 8];
                  end
                end
                mem[f_key(s, s_addr[s])] = w;
              end
              log_slv.push_back(s);
              log_addr.push_back(s_addr[s]);
              log_write.push_back(s_write[s]);
              log_wdata.push_back(s_wdata[s]);
              log_strb.push_back(s_strb[s]);
              log_prot.push_back(s_prot[s]);
              log_rdata.push_back(prdata[s*DATA_WIDTH +: DATA_WIDTH]);
              log_err.push_back(pslverr[s]);
              log_wait.push_back(wcount[s]);
              n_xfer <= n_xfer + 1;
              if( s_write[s] ) begin
                n_write <= n_write + 1;
              end else begin
                n_read <= n_read + 1;
              end
              if( pslverr[s] ) begin
                n_err <= n_err + 1;
              end
              if( wcount[s]>max_wait ) begin
                max_wait <= wcount[s];
              end
              last_done_q[s] <= 1'b1;
              drive_idle(s);
              mst[s] <= M_IDLE;
            end else begin
              // ウェイト中
              if( hang_q[s] ) begin
                drive_wait(s);
              end else if( wleft[s]<=1 ) begin
                drive_resp(s, s_addr[s], s_write[s]);
                mst[s] <= M_RESP;
              end else begin
                drive_wait(s);
                wleft[s] <= wleft[s] - 1;
              end
            end
          end
        end else begin
          //-------------------------------------------------------------------
          // このスレーブは選択されていない
          //-------------------------------------------------------------------
          if( mst[s]!=M_IDLE ) begin
            // PREADY を待たずに PSEL が下がった (転送の打ち切り)
            n_abort <= n_abort + 1;
          end
          drive_idle(s);
          mst[s] <= M_IDLE;
        end
      end
    end
  end

endmodule

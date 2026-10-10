//=============================================================================
// apb_master_mem.sv
//-----------------------------------------------------------------------------
//  APB マスタ (Requester) + 内部メモリ (汎用レジスタ)。
//  内部メモリと APB の間で、コマンド 1 つにつき連続したワードをまとめて転送する。
//
//      mem_* (ローカルポート) <--> [内部メモリ MEM_DEPTH ワード]
//                                        |  ^
//                      cmd_write=1 (書く) v  | cmd_write=0 (読む)
//      cmd_* / done  --> [シーケンサ] --> [apb_master_engine] --> APB
//
//    cmd_write = 1 : 内部メモリ [cmd_mem_addr から cmd_len ワード] を APB へ書き込む
//    cmd_write = 0 : APB から cmd_len ワード読み出し、内部メモリ [cmd_mem_addr から] に格納する
//
//  parameter で調整できるもの:
//    ADDR_WIDTH     : PADDR のビット幅 (1..32)
//    DATA_WIDTH     : PWDATA / PRDATA のビット幅 (8 / 16 / 32)
//    NUM_SLAVES     : PSEL の本数 (つなぐスレーブ数)
//    MEM_DEPTH      : 内部メモリのワード数 (1 ワード = DATA_WIDTH ビット)
//    TIMEOUT_CYCLES : PREADY 待ちの上限 (0 = 無効)
//    STOP_ON_ERROR  : 1 = 最初のエラーで残りの転送を中止 / 0 = 最後まで続ける
//
//  コマンド (cmd_valid / cmd_ready。アイドル時のみ cmd_ready=1):
//    cmd_write    : 1 = 書き込み (メモリ → APB) / 0 = 読み出し (APB → メモリ)
//    cmd_sel      : 相手のスレーブ番号 (0..NUM_SLAVES-1)。その番号の PSEL だけ立てる
//    cmd_addr     : APB の先頭アドレス (DATA_WIDTH/8 バイトの倍数)
//    cmd_incr     : 1 = 1 転送ごとにアドレスを DATA_WIDTH/8 進める / 0 = 同じアドレスに繰り返す
//    cmd_mem_addr : 内部メモリの先頭ワード番号
//    cmd_len      : 転送ワード数 (0 なら何もせず完了)
//    cmd_strb     : 書き込み時の PSTRB (全転送で共通)。読み出しでは無視し、PSTRB は 0 を出す
//    cmd_prot     : PPROT (全転送で共通)
//
//  ステータス:
//    done         : 完了で 1 サイクル。以下は done と同じサイクルで見る (次のコマンド受付まで保持)
//    done_err     : err_flags のどれかが 1
//    err_flags[0] : PSLVERR を受けた
//    err_flags[1] : タイムアウトで転送を打ち切った
//    err_flags[2] : コマンドの誤り (転送は行わない)
//                     cmd_sel が NUM_SLAVES 以上 / メモリ範囲が MEM_DEPTH を超える /
//                     cmd_addr が非アライン / アドレスが ADDR_WIDTH の範囲を超える
//    err_index    : 最初にエラーになった転送の番号 (0 始まり)。err_flags[1:0] != 0 のとき有効
//    done_count   : バスで実行した転送数 (エラーで終わった転送も含む)
//
//  エラー時の動作:
//    - STOP_ON_ERROR=1 : 最初のエラーで中止。それより後の転送はバスに出ない
//                        (done_count = err_index + 1)
//    - STOP_ON_ERROR=0 : 最後まで転送し、done のときに err_flags で通知する
//    - エラーになった読み出しのデータはメモリに書かない (元の値のまま)
//
//  内部メモリのローカルポート (mem_valid / mem_ready):
//    - コマンド実行中 (busy=1) は mem_ready=0。アイドル時だけ読み書きできる
//    - コマンドを受け付けるサイクルはまだアイドルなので、同じサイクルのアクセスも受け付ける
//      (書き込みはそのコマンドが送るデータに反映される。読み出しはコマンド開始前の値が返る)
//    - 読み出しは、受け付けた次のサイクルに mem_rvalid=1 と mem_rdata
//      (mem_rdata は mem_rvalid=1 のサイクルだけ有効)
//    - MEM_DEPTH 以上のアドレスは、書き込みを無視し、読み出しは 0 を返す
//
//  転送速度: PREADY が常に 1 なら 2 サイクルに 1 転送 (APB の最短)。
//    - 1 コマンドの中の転送は IDLE を挟まずに続ける (ウェイトやエラーがあっても同じ)
//    - 受付から done までのサイクル数は、書き込みが 4 + 各転送のサイクル数の合計、
//      読み出しが 3 + 同、転送しないコマンド (0 ワード / 誤り) が 1
//      (1 転送は SETUP 1 + ACCESS (1 + ウェイト数)。打ち切った転送は SETUP 1 + ACCESS TIMEOUT_CYCLES)
//
//  参考: AMBA APB Protocol Specification (Arm IHI 0024E)
//        https://documentation-service.arm.com/static/63fe2c1356ea36189d4e79f3
//=============================================================================
`timescale 1ns / 1ps

module apb_master_mem #(
  parameter int unsigned ADDR_WIDTH     = 32
 ,parameter int unsigned DATA_WIDTH     = 32
 ,parameter int unsigned NUM_SLAVES     = 1
 ,parameter int unsigned MEM_DEPTH      = 16
 ,parameter int unsigned TIMEOUT_CYCLES = 0
 ,parameter bit          STOP_ON_ERROR  = 1'b1
) (
  //---------------------------------------------------------------------------
  // Global
  //---------------------------------------------------------------------------
  input  logic                                                 pclk
 ,input  logic                                                 presetn
  //---------------------------------------------------------------------------
  // コマンド
  //---------------------------------------------------------------------------
 ,input  logic                                                 cmd_valid
 ,output logic                                                 cmd_ready
 ,input  logic                                                 cmd_write
 ,input  logic [((NUM_SLAVES<2) ? 1 : $clog2(NUM_SLAVES))-1:0] cmd_sel
 ,input  logic [ADDR_WIDTH-1:0]                                cmd_addr
 ,input  logic                                                 cmd_incr
 ,input  logic [((MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH))-1:0]   cmd_mem_addr
 ,input  logic [$clog2(MEM_DEPTH+1)-1:0]                       cmd_len
 ,input  logic [(DATA_WIDTH/8)-1:0]                            cmd_strb
 ,input  logic [2:0]                                           cmd_prot
  //---------------------------------------------------------------------------
  // ステータス
  //---------------------------------------------------------------------------
 ,output logic                                                 busy
 ,output logic                                                 done
 ,output logic                                                 done_err
 ,output logic [2:0]                                           err_flags
 ,output logic [$clog2(MEM_DEPTH+1)-1:0]                       err_index
 ,output logic [$clog2(MEM_DEPTH+1)-1:0]                       done_count
  //---------------------------------------------------------------------------
  // 内部メモリのローカルポート
  //---------------------------------------------------------------------------
 ,input  logic                                                 mem_valid
 ,output logic                                                 mem_ready
 ,input  logic                                                 mem_write
 ,input  logic [((MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH))-1:0]   mem_addr
 ,input  logic [DATA_WIDTH-1:0]                                mem_wdata
 ,output logic                                                 mem_rvalid
 ,output logic [DATA_WIDTH-1:0]                                mem_rdata
  //---------------------------------------------------------------------------
  // APB master
  //   prdata はスレーブ i の分が [i*DATA_WIDTH +: DATA_WIDTH]
  //---------------------------------------------------------------------------
 ,output logic [ADDR_WIDTH-1:0]                                paddr
 ,output logic [2:0]                                           pprot
 ,output logic [NUM_SLAVES-1:0]                                psel
 ,output logic                                                 penable
 ,output logic                                                 pwrite
 ,output logic [DATA_WIDTH-1:0]                                pwdata
 ,output logic [(DATA_WIDTH/8)-1:0]                            pstrb
 ,input  logic [NUM_SLAVES-1:0]                                pready
 ,input  logic [(NUM_SLAVES*DATA_WIDTH)-1:0]                   prdata
 ,input  logic [NUM_SLAVES-1:0]                                pslverr
);

  //---------------------------------------------------------------------------
  // Local parameters
  //---------------------------------------------------------------------------
  localparam int unsigned STRB_W   = DATA_WIDTH / 8;
  localparam int unsigned STRB_LSB = $clog2(STRB_W);
  localparam int unsigned SEL_W    = (NUM_SLAVES<2) ? 1 : $clog2(NUM_SLAVES);
  localparam int unsigned MEM_AW   = (MEM_DEPTH<2) ? 1 : $clog2(MEM_DEPTH);
  localparam int unsigned LEN_W    = $clog2(MEM_DEPTH+1);

  typedef enum logic [2:0] {
    F_IDLE   = 3'd0
   ,F_WR_MEM = 3'd1
   ,F_WR_REQ = 3'd2
   ,F_RD_REQ = 3'd3
   ,F_WAIT   = 3'd4
   ,F_DONE   = 3'd5
  } fstate_e;

  //---------------------------------------------------------------------------
  // Registers
  //---------------------------------------------------------------------------
  fstate_e               fstate;
  logic                  wr_q;          // 1 = 書き込み (メモリ → APB)
  logic [SEL_W-1:0]      sel_q;
  logic [ADDR_WIDTH-1:0] addr_q;        // 次に発行する転送の APB アドレス
  logic                  incr_q;
  logic [STRB_W-1:0]     strb_q;
  logic [2:0]            prot_q;
  logic [MEM_AW-1:0]     iss_ptr;       // 次に発行する転送のメモリ位置
  logic [MEM_AW-1:0]     rsp_ptr;       // 次に受ける応答のメモリ位置
  logic [LEN_W-1:0]      iss_left;      // 未発行の転送数
  logic [LEN_W-1:0]      rsp_left;      // 応答をまだ受けていない転送数
  logic [LEN_W-1:0]      rsp_cnt;       // 受けた応答数
  logic                  wfirst;        // F_WR_REQ の最初のサイクル (メモリの読み出しデータが有効)
  logic [DATA_WIDTH-1:0] wdata_q;       // メモリから読んだ書き込みデータの保持
  logic                  err_slv;
  logic                  err_to;
  logic                  err_cfg;
  logic [LEN_W-1:0]      err_index_q;

  //---------------------------------------------------------------------------
  // コマンドの検査
  //---------------------------------------------------------------------------
  logic cmd_empty;
  logic cmd_bad;
  logic cmd_sel_bad;      // スレーブ番号が NUM_SLAVES 以上
  logic cmd_mem_bad;      // メモリ範囲が MEM_DEPTH を超える
  logic cmd_align_bad;    // アドレスが DATA_WIDTH/8 バイトの倍数でない
  logic cmd_range_bad;    // アドレスが ADDR_WIDTH の範囲を超える

  // cmd_sel のビット幅で NUM_SLAVES 以上の値を表せるときだけ比較する
  generate
    if( (1<<SEL_W)>NUM_SLAVES ) begin : g_sel_chk
      assign cmd_sel_bad = (32'(cmd_sel)>=32'(NUM_SLAVES));
    end else begin : g_sel_nochk
      assign cmd_sel_bad = 1'b0;
    end
  endgenerate

  assign cmd_empty     = (cmd_len=={LEN_W{1'b0}});
  assign cmd_mem_bad   = ((32'(cmd_mem_addr) + 32'(cmd_len))>32'(MEM_DEPTH));
  assign cmd_align_bad = ((cmd_addr&ADDR_WIDTH'(STRB_W-1))!={ADDR_WIDTH{1'b0}});
  assign cmd_range_bad = cmd_incr&&((64'(cmd_addr) + (64'(cmd_len) << STRB_LSB))>(64'd1 << ADDR_WIDTH));
  assign cmd_bad       = cmd_sel_bad||cmd_mem_bad||cmd_align_bad||cmd_range_bad;

  //---------------------------------------------------------------------------
  // エンジンとの接続信号
  //---------------------------------------------------------------------------
  logic                  req_valid;
  logic                  req_ready;
  logic                  req_fire;
  logic [DATA_WIDTH-1:0] req_wdata;
  logic                  rsp_valid;
  logic [DATA_WIDTH-1:0] rsp_rdata;
  logic                  rsp_slverr;
  logic                  rsp_timeout;
  logic                  eng_busy;

  logic                  run;           // コマンド実行中 (応答を受け付ける状態)
  logic                  rsp_take;
  logic                  rsp_err;
  logic                  rsp_last;      // これが最後の応答
  logic                  rsp_abort;     // エラーで中止する

  //---------------------------------------------------------------------------
  // 内部メモリとの接続信号
  //---------------------------------------------------------------------------
  logic                  seq_rd;        // 書き込みコマンド : メモリから 1 ワード読む
  logic                  seq_wr;        // 読み出しコマンド : 応答のデータをメモリへ書く
  logic                  loc_fire;      // ローカルポートのアクセス
  logic                  loc_ok;        // ローカルポートのアドレスが範囲内
  logic                  sram_ce;
  logic                  sram_we;
  logic [MEM_AW-1:0]     sram_addr;
  logic [DATA_WIDTH-1:0] sram_wdata;
  logic [DATA_WIDTH-1:0] sram_rdata;

  assign run       = (fstate==F_WR_MEM)||(fstate==F_WR_REQ)||(fstate==F_RD_REQ)||(fstate==F_WAIT);
  assign req_valid = (fstate==F_WR_REQ)||(fstate==F_RD_REQ);
  assign req_fire  = req_valid&&req_ready;
  assign req_wdata = wfirst ? sram_rdata : wdata_q;

  assign rsp_take  = run&&rsp_valid;
  assign rsp_err   = rsp_slverr||rsp_timeout;
  assign rsp_last  = (rsp_left==LEN_W'(1));
  assign rsp_abort = STOP_ON_ERROR&&rsp_err;

  //---------------------------------------------------------------------------
  // ステータス出力
  //---------------------------------------------------------------------------
  assign cmd_ready  = (fstate==F_IDLE);
  assign busy       = (fstate!=F_IDLE);
  assign done       = (fstate==F_DONE);
  assign err_flags  = {err_cfg, err_to, err_slv};
  assign done_err   = err_cfg||err_to||err_slv;
  assign err_index  = err_index_q;
  assign done_count = rsp_cnt;

  //---------------------------------------------------------------------------
  // シーケンサ
  //   書き込み : F_WR_MEM (メモリ読み出し) -> F_WR_REQ (要求) を転送数ぶん繰り返す
  //   読み出し : F_RD_REQ で要求を出し続け、応答が来るたびにメモリへ書く
  //   要求を全て出したら F_WAIT で残りの応答を待つ
  //---------------------------------------------------------------------------
  always @(posedge pclk or negedge presetn) begin
    if( !presetn ) begin
      fstate      <= F_IDLE;
      wr_q        <= 1'b0;
      sel_q       <= {SEL_W{1'b0}};
      addr_q      <= {ADDR_WIDTH{1'b0}};
      incr_q      <= 1'b0;
      strb_q      <= {STRB_W{1'b0}};
      prot_q      <= 3'b000;
      iss_ptr     <= {MEM_AW{1'b0}};
      rsp_ptr     <= {MEM_AW{1'b0}};
      iss_left    <= {LEN_W{1'b0}};
      rsp_left    <= {LEN_W{1'b0}};
      rsp_cnt     <= {LEN_W{1'b0}};
      wfirst      <= 1'b0;
      wdata_q     <= {DATA_WIDTH{1'b0}};
      err_slv     <= 1'b0;
      err_to      <= 1'b0;
      err_cfg     <= 1'b0;
      err_index_q <= {LEN_W{1'b0}};
    end else begin
      case( fstate )
        F_IDLE : begin
          if( cmd_valid ) begin
            wr_q        <= cmd_write;
            sel_q       <= cmd_sel;
            addr_q      <= cmd_addr;
            incr_q      <= cmd_incr;
            strb_q      <= cmd_strb;
            prot_q      <= cmd_prot;
            iss_ptr     <= cmd_mem_addr;
            rsp_ptr     <= cmd_mem_addr;
            iss_left    <= cmd_len;
            rsp_left    <= cmd_len;
            rsp_cnt     <= {LEN_W{1'b0}};
            err_slv     <= 1'b0;
            err_to      <= 1'b0;
            err_index_q <= {LEN_W{1'b0}};
            if( cmd_empty ) begin
              // 0 ワードは何もせず完了
              err_cfg <= 1'b0;
              fstate  <= F_DONE;
            end else if( cmd_bad ) begin
              err_cfg <= 1'b1;
              fstate  <= F_DONE;
            end else begin
              err_cfg <= 1'b0;
              if( cmd_write ) begin
                fstate <= F_WR_MEM;
              end else begin
                fstate <= F_RD_REQ;
              end
            end
          end
        end
        F_WR_MEM : begin
          wfirst <= 1'b1;
          fstate <= F_WR_REQ;
        end
        F_WR_REQ : begin
          wfirst <= 1'b0;
          if( wfirst ) begin
            wdata_q <= sram_rdata;
          end
          if( req_fire ) begin
            if( iss_left==LEN_W'(1) ) begin
              fstate <= F_WAIT;
            end else begin
              fstate <= F_WR_MEM;
            end
          end
        end
        F_RD_REQ : begin
          if( req_fire&&(iss_left==LEN_W'(1)) ) begin
            fstate <= F_WAIT;
          end
        end
        F_WAIT : begin
          fstate <= F_WAIT;
        end
        F_DONE : begin
          fstate <= F_IDLE;
        end
        default : begin
          fstate <= F_IDLE;
        end
      endcase
      // 要求を 1 つ出すごとに、次の転送の位置へ進める
      if( req_fire ) begin
        iss_left <= iss_left - LEN_W'(1);
        iss_ptr  <= iss_ptr + MEM_AW'(1);
        if( incr_q ) begin
          addr_q <= addr_q + ADDR_WIDTH'(STRB_W);
        end
      end
      // 応答
      if( rsp_take ) begin
        rsp_left <= rsp_left - LEN_W'(1);
        rsp_cnt  <= rsp_cnt + LEN_W'(1);
        rsp_ptr  <= rsp_ptr + MEM_AW'(1);
        if( rsp_err&&!err_slv&&!err_to ) begin
          err_index_q <= rsp_cnt;
        end
        if( rsp_slverr ) begin
          err_slv <= 1'b1;
        end
        if( rsp_timeout ) begin
          err_to <= 1'b1;
        end
        // 最後の応答、またはエラーで中止 (上の case の遷移より優先する)
        if( rsp_last||rsp_abort ) begin
          fstate <= F_DONE;
        end
      end
    end
  end

  //---------------------------------------------------------------------------
  // 内部メモリのアクセス
  //   シーケンサとローカルポートは同時には使わない (ローカルポートはアイドル時だけ)。
  //   シーケンサも 1 コマンドの中では読むだけか書くだけなので、シングルポートで足りる
  //---------------------------------------------------------------------------
  assign seq_rd     = (fstate==F_WR_MEM);
  assign seq_wr     = rsp_take&&!wr_q&&!rsp_err;
  assign mem_ready  = (fstate==F_IDLE);
  assign loc_fire   = mem_valid&&mem_ready;

  assign sram_ce    = seq_rd||seq_wr||(loc_fire&&loc_ok);
  assign sram_we    = seq_wr||(loc_fire&&mem_write);
  assign sram_wdata = seq_wr ? rsp_rdata : mem_wdata;

  always @(*) begin
    if( seq_rd ) begin
      sram_addr = iss_ptr;
    end else if( seq_wr ) begin
      sram_addr = rsp_ptr;
    end else begin
      sram_addr = mem_addr;
    end
  end

  always @(posedge pclk or negedge presetn) begin
    if( !presetn ) begin
      mem_rvalid <= 1'b0;
    end else begin
      mem_rvalid <= loc_fire&&!mem_write;
    end
  end

  // mem_addr のビット幅で MEM_DEPTH 以上の値を表せるときだけ、範囲を確認する
  generate
    if( (1<<MEM_AW)>MEM_DEPTH ) begin : g_loc_chk
      logic loc_rd_ok_q;

      assign loc_ok    = (32'(mem_addr)<32'(MEM_DEPTH));
      assign mem_rdata = loc_rd_ok_q ? sram_rdata : {DATA_WIDTH{1'b0}};

      always @(posedge pclk or negedge presetn) begin
        if( !presetn ) begin
          loc_rd_ok_q <= 1'b0;
        end else begin
          loc_rd_ok_q <= loc_ok;
        end
      end
    end else begin : g_loc_nochk
      assign loc_ok    = 1'b1;
      assign mem_rdata = sram_rdata;
    end
  endgenerate

  apb_master_sram_sp #(
    .DEPTH(MEM_DEPTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.ADDR_WIDTH(MEM_AW)
  ) u_mem (
    .clk(pclk)
   ,.ce(sram_ce)
   ,.we(sram_we)
   ,.addr(sram_addr)
   ,.wdata(sram_wdata)
   ,.rdata(sram_rdata)
  );

  //---------------------------------------------------------------------------
  // APB 転送エンジン
  //   STOP_ON_ERROR=1 のときは、エラーの後に受け付けていた要求をエンジンが捨てる
  //---------------------------------------------------------------------------
  apb_master_engine #(
    .ADDR_WIDTH(ADDR_WIDTH)
   ,.DATA_WIDTH(DATA_WIDTH)
   ,.NUM_SLAVES(NUM_SLAVES)
   ,.TIMEOUT_CYCLES(TIMEOUT_CYCLES)
   ,.FLUSH_ON_ERROR(STOP_ON_ERROR)
  ) u_engine (
    .pclk(pclk)
   ,.presetn(presetn)
   ,.req_valid(req_valid)
   ,.req_ready(req_ready)
   ,.req_write(wr_q)
   ,.req_sel(sel_q)
   ,.req_addr(addr_q)
   ,.req_wdata(req_wdata)
   ,.req_strb(strb_q)
   ,.req_prot(prot_q)
   ,.rsp_valid(rsp_valid)
   ,.rsp_rdata(rsp_rdata)
   ,.rsp_slverr(rsp_slverr)
   ,.rsp_timeout(rsp_timeout)
   ,.busy(eng_busy)
   ,.paddr(paddr)
   ,.pprot(pprot)
   ,.psel(psel)
   ,.penable(penable)
   ,.pwrite(pwrite)
   ,.pwdata(pwdata)
   ,.pstrb(pstrb)
   ,.pready(pready)
   ,.prdata(prdata)
   ,.pslverr(pslverr)
  );

  //---------------------------------------------------------------------------
  // 未使用信号
  //---------------------------------------------------------------------------
  logic unused_ok;
  assign unused_ok = &{1'b0, eng_busy};

  //---------------------------------------------------------------------------
  // パラメータチェック (エラボレーション時。IEEE 1800 20.11)
  //   対応していない合成ツールでは +define+APB_MASTER_NO_ELAB_CHECK で外す
  //---------------------------------------------------------------------------
`ifndef APB_MASTER_NO_ELAB_CHECK
  generate
    if( (DATA_WIDTH!=8)&&(DATA_WIDTH!=16)&&(DATA_WIDTH!=32) ) begin : g_chk_data
      $error("apb_master_mem : DATA_WIDTH must be 8, 16 or 32 (DATA_WIDTH=%0d)", DATA_WIDTH);
    end
    if( (ADDR_WIDTH<1)||(ADDR_WIDTH>32) ) begin : g_chk_addr
      $error("apb_master_mem : ADDR_WIDTH must be 1..32 (ADDR_WIDTH=%0d)", ADDR_WIDTH);
    end
    if( NUM_SLAVES<1 ) begin : g_chk_slaves
      $error("apb_master_mem : NUM_SLAVES must be >= 1 (NUM_SLAVES=%0d)", NUM_SLAVES);
    end
    if( MEM_DEPTH<1 ) begin : g_chk_depth
      $error("apb_master_mem : MEM_DEPTH must be >= 1 (MEM_DEPTH=%0d)", MEM_DEPTH);
    end
  endgenerate
`endif

endmodule

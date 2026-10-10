//=============================================================================
// apbm_scoreboard.svh
//-----------------------------------------------------------------------------
//  scoreboard。
//
//  持っている期待値:
//    m_mem      : DUT の内部メモリ (ローカルポートの書き込みと、読み出しコマンドの結果で更新)
//    m_exp_smem : スレーブのメモリ (最初のコマンドの時点の内容を写し、書き込みコマンドで更新)
//
//  チェック:
//    コマンド受付時 : そのコマンドで起こるはずの転送の列を作る
//                     (アドレス / エラーになる転送 / 打ち切る転送 / どこで止まるか)
//    APB 転送ごと   : 順番どおりで、スレーブ番号 / アドレス / 方向 / PWDATA / PSTRB / PPROT が
//                     期待どおり。PSLVERR / 打ち切りが期待どおり。読み出しデータが
//                     スレーブのメモリの内容と一致。
//                     1 コマンドの中の転送が IDLE を挟まずに続いている (back-to-back)
//    コマンド完了時 : 期待した転送が全て出ていて余分が無い。
//                     done_err / err_flags / err_index / done_count が期待どおり。
//                     受付から done までのサイクル数が期待どおり (転送しないコマンドは 1。
//                     転送するコマンドは 書き込み 4 / 読み出し 3 + 各転送の長さ)。
//                     書き込んだワードがスレーブのメモリに反映されている
//    ローカル読み出し : 読めたデータが m_mem と一致 (範囲外のアドレスは 0)
//    終了時         : スレーブのメモリ全体が m_exp_smem と一致 (触っていない場所を含む)
//=============================================================================

`uvm_analysis_imp_decl(_start)
`uvm_analysis_imp_decl(_done)
`uvm_analysis_imp_decl(_mem)
`uvm_analysis_imp_decl(_apb)

class apbm_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(apbm_scoreboard)

  uvm_analysis_imp_start #(usr_item, apbm_scoreboard) start_imp;
  uvm_analysis_imp_done  #(usr_item, apbm_scoreboard) done_imp;
  uvm_analysis_imp_mem   #(mem_item, apbm_scoreboard) mem_imp;
  uvm_analysis_imp_apb   #(apb_item, apbm_scoreboard) apb_imp;

  apb_slv_mem smem;                 // スレーブのメモリ (responder と共有)
  apb_slv_cfg cfg[NUM_SLAVES];      // スレーブの設定 (responder と共有)

  // 期待値
  protected bit [DATA_W-1:0] m_mem[MEM_DEPTH];
  protected bit              m_mem_vld[MEM_DEPTH];
  protected bit [DATA_W-1:0] m_exp_smem[bit [63:0]];
  protected bit              m_snap_done;

  // 実行中のコマンドと、その期待値
  protected usr_item         m_cmd;
  protected bit              m_empty;
  protected bit              m_bad;
  protected bit [63:0]       m_x_addr[$];    // 実行されるはずの転送のアドレス
  protected bit              m_x_to[$];      // その転送はタイムアウトで打ち切られる
  protected bit              m_x_er[$];      // その転送は PSLVERR になる
  protected int unsigned     m_xi;           // 次に来るはずの転送の番号
  protected int unsigned     m_dur;          // このコマンドの転送が使ったサイクル数の合計
  protected bit              m_got_err;
  protected bit              m_e_slv;
  protected bit              m_e_to;
  protected int unsigned     m_e_idx;

  // 統計
  protected int unsigned     m_n_cmd;
  protected int unsigned     m_n_exec;
  protected int unsigned     m_n_err_cmd;
  protected int unsigned     m_n_xfer;
  protected int unsigned     m_n_abort;
  protected int unsigned     m_n_mem_wr;
  protected int unsigned     m_n_mem_rd;
  protected int unsigned     m_n_err;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    start_imp = new("start_imp", this);
    done_imp  = new("done_imp", this);
    mem_imp   = new("mem_imp", this);
    apb_imp   = new("apb_imp", this);
  endfunction

  protected function void error(string msg);
    m_n_err++;
    `uvm_error("SCB", msg)
  endfunction

  //---------------------------------------------------------------------------
  // コマンドの分類 (coverage からも使う)
  //---------------------------------------------------------------------------
  static function bit cmd_is_empty(usr_item c);
    return (c.len==0);
  endfunction

  // DUT が err_flags[2] で断るべきコマンドか
  static function bit cmd_is_bad(usr_item c);
    bit b_sel;
    bit b_mem;
    bit b_align;
    bit b_range;
    b_sel   = apbm_sel_bad(c.sel);
    b_mem   = apbm_mem_bad(c.maddr, c.len);
    b_align = apbm_align_bad(c.addr);
    b_range = apbm_range_bad(c.addr, c.incr, c.len);
    return b_sel||b_mem||b_align||b_range;
  endfunction

  protected function bit [DATA_W-1:0] exp_smem_read(int unsigned s, bit [63:0] a);
    bit [63:0] k;
    k = apb_slv_mem::key(s, a);
    if( m_exp_smem.exists(k) ) begin
      return m_exp_smem[k];
    end
    return {DATA_W{1'b0}};
  endfunction

  // スレーブのメモリの現在の内容を期待値に写す (最初のコマンドのときに 1 回)
  protected function void snapshot_smem();
    apb_slv_mem::key_q_t keys;
    keys = smem.get_keys();
    m_exp_smem.delete();
    for( int unsigned i=0; i<keys.size(); i++ ) begin
      m_exp_smem[keys[i]] = smem.get(keys[i]);
    end
    m_snap_done = 1'b1;
  endfunction

  //---------------------------------------------------------------------------
  // コマンド受付 : 期待される転送の列を作る
  //   スレーブの設定は受付時の値を使う (仮想シーケンスはコマンドの完了後にだけ変える)
  //---------------------------------------------------------------------------
  function void write_start(usr_item c);
    bit [63:0] a;
    bit        to;
    bit        er;
    if( !m_snap_done ) begin
      snapshot_smem();
    end
    if( m_cmd!=null ) begin
      error({"command accepted while the previous one is not done : ", c.convert2string()});
    end
    m_cmd     = c;
    m_empty   = cmd_is_empty(c);
    m_bad     = cmd_is_bad(c);
    m_xi      = 0;
    m_dur     = 0;
    m_got_err = 1'b0;
    m_e_slv   = 1'b0;
    m_e_to    = 1'b0;
    m_e_idx   = 0;
    m_x_addr.delete();
    m_x_to.delete();
    m_x_er.delete();
    if( !m_empty&&!m_bad ) begin
      if( (TIMEOUT_CYCLES>0)&&(cfg[c.sel].wait_max>=TIMEOUT_CYCLES)&&(cfg[c.sel].wait_min!=cfg[c.sel].wait_max) ) begin
        error("testbench : wait range crosses the timeout limit, the expected result is not defined");
      end
      for( int unsigned i=0; i<c.len; i++ ) begin
        a  = apbm_xaddr(c.addr, c.incr, i);
        to = (TIMEOUT_CYCLES>0)&&(cfg[c.sel].in_hang(a)||cfg[c.sel].wait_times_out());
        er = !to&&cfg[c.sel].in_err(a);
        m_x_addr.push_back(a);
        m_x_to.push_back(to);
        m_x_er.push_back(er);
        if( to||er ) begin
          if( !m_got_err ) begin
            m_got_err = 1'b1;
            m_e_idx   = i;
          end
          if( to ) begin
            m_e_to = 1'b1;
          end else begin
            m_e_slv = 1'b1;
          end
          if( STOP_ON_ERROR ) begin
            break;
          end
        end
      end
    end
  endfunction

  //---------------------------------------------------------------------------
  // APB 転送 1 回 (完了または打ち切り)
  //---------------------------------------------------------------------------
  function void write_apb(apb_item t);
    int unsigned     i;
    bit [63:0]       a;
    bit [DATA_W-1:0] wd;
    bit [DATA_W-1:0] m;
    bit [STRB_W-1:0] strb_exp;
    if( m_cmd==null ) begin
      error({"transfer on the bus without a command : ", t.convert2string()});
      return;
    end
    if( m_xi>=m_x_addr.size() ) begin
      error($sformatf("extra transfer on the bus (the command needs %0d) : %s", m_x_addr.size(), t.convert2string()));
      return;
    end
    i    = m_xi;
    a    = m_x_addr[i];
    m_xi = m_xi + 1;
    // 転送の長さ : SETUP 1 + ACCESS (完了した転送は 1 + ウェイト数、打ち切った転送は PREADY=0 だったサイクル数)
    m_dur = m_dur + 1 + t.n_wait + (t.aborted ? 0 : 1);
    // 要求の内容
    strb_exp = m_cmd.wr ? m_cmd.strb : {STRB_W{1'b0}};
    if( (t.slv!=m_cmd.sel)||(t.addr!=a)||(t.write!=m_cmd.wr)||(t.prot!=m_cmd.prot)||(t.strb!=strb_exp) ) begin
      error($sformatf("transfer %0d : %s (exp slave=%0d addr=%0h write=%b prot=%b strb=%b)", i, t.convert2string(), m_cmd.sel, a, m_cmd.wr, m_cmd.prot, strb_exp));
    end
    // 設計意図 : 1 コマンドの中の転送は、IDLE を挟まずに続ける (back-to-back)
    if( (i>0)&&!t.b2b ) begin
      error($sformatf("transfer %0d : did not start right after the previous transfer (IDLE cycle in between) : %s", i, t.convert2string()));
    end
    if( (i==0)&&t.b2b ) begin
      error($sformatf("transfer 0 : started right after a transfer of the previous command : %s", t.convert2string()));
    end
    wd = m_mem[(m_cmd.maddr+i) % MEM_DEPTH];
    if( m_cmd.wr ) begin
      if( !m_mem_vld[(m_cmd.maddr+i)%MEM_DEPTH] ) begin
        error($sformatf("testbench : internal memory word %0d is sent before it is written", m_cmd.maddr+i));
      end else if( t.wdata!=wd ) begin
        error($sformatf("transfer %0d : PWDATA=%0h (exp %0h = internal memory word %0d)", i, t.wdata, wd, m_cmd.maddr+i));
      end
    end
    // 結果
    if( m_x_to[i] ) begin
      m_n_abort++;
      if( !t.aborted ) begin
        error($sformatf("transfer %0d : expected to be aborted by the timeout : %s", i, t.convert2string()));
      end else if( t.n_wait!=TIMEOUT_CYCLES ) begin
        error($sformatf("transfer %0d : aborted after %0d ACCESS cycles (exp %0d)", i, t.n_wait, TIMEOUT_CYCLES));
      end
      return;
    end
    m_n_xfer++;
    if( t.aborted ) begin
      error($sformatf("transfer %0d : aborted without PREADY : %s", i, t.convert2string()));
      return;
    end
    if( t.slverr!=m_x_er[i] ) begin
      error($sformatf("transfer %0d : PSLVERR=%b (exp %b) : %s", i, t.slverr, m_x_er[i], t.convert2string()));
    end
    if( m_x_er[i] ) begin
      return;
    end
    // 期待値の更新
    if( m_cmd.wr ) begin
      m = exp_smem_read(m_cmd.sel, a);
      for( int unsigned b=0; b<STRB_W; b++ ) begin
        if( m_cmd.strb[b] ) begin
          m[8*b +: 8] = wd[8*b +: 8];
        end
      end
      m_exp_smem[apb_slv_mem::key(m_cmd.sel, a)] = m;
    end else begin
      if( t.rdata!=exp_smem_read(m_cmd.sel,a) ) begin
        error($sformatf("transfer %0d : PRDATA=%0h but the slave memory holds %0h (slave model)", i, t.rdata, exp_smem_read(m_cmd.sel, a)));
      end
      m_mem[m_cmd.maddr+i]     = exp_smem_read(m_cmd.sel, a);
      m_mem_vld[m_cmd.maddr+i] = 1'b1;
    end
  endfunction

  //---------------------------------------------------------------------------
  // コマンド完了
  //---------------------------------------------------------------------------
  function void write_done(usr_item c);
    bit [2:0]    exp_flags;
    bit [63:0]   a;
    int unsigned n_exp;
    int unsigned exp_cyc;
    string       id;
    if( m_cmd==null ) begin
      error("done without an accepted command");
      return;
    end
    id        = c.convert2string();
    n_exp     = m_x_addr.size();
    exp_flags = {(m_bad&&!m_empty), m_e_to, m_e_slv};
    m_n_cmd++;
    if( !m_empty&&!m_bad ) begin
      m_n_exec++;
    end
    if( exp_flags!=3'b000 ) begin
      m_n_err_cmd++;
    end
    if( m_xi!=n_exp ) begin
      error($sformatf("%0d transfer(s) on the bus, expected %0d : %s", m_xi, n_exp, id));
    end
    if( c.err_flags!=exp_flags ) begin
      error($sformatf("err_flags=%b (exp %b) : %s", c.err_flags, exp_flags, id));
    end
    if( c.done_err!=(|exp_flags) ) begin
      error($sformatf("done_err=%b (exp %b) : %s", c.done_err, |exp_flags, id));
    end
    if( c.done_count!=n_exp ) begin
      error($sformatf("done_count=%0d (exp %0d) : %s", c.done_count, n_exp, id));
    end
    if( m_got_err&&(c.err_index!=m_e_idx) ) begin
      error($sformatf("err_index=%0d (exp %0d) : %s", c.err_index, m_e_idx, id));
    end
    // 受付から done までのサイクル数 (転送の前後や間に、余分なサイクルが入っていないこと)
    if( n_exp==0 ) begin
      exp_cyc = 1;
    end else begin
      exp_cyc = (m_cmd.wr ? 4 : 3) + m_dur;
    end
    if( (c.cyc_done-c.cyc_start)!=exp_cyc ) begin
      error($sformatf("done came %0d cycles after the command was accepted (exp %0d) : %s", c.cyc_done-c.cyc_start, exp_cyc, id));
    end
    // 書き込み : 触ったワードがスレーブのメモリに反映されていること
    if( m_cmd.wr ) begin
      for( int unsigned i=0; i<n_exp; i++ ) begin
        a = m_x_addr[i];
        if( smem.read_word(m_cmd.sel,a)!=exp_smem_read(m_cmd.sel,a) ) begin
          error($sformatf("slave %0d addr=%0h = %0h (exp %0h) : %s", m_cmd.sel, a, smem.read_word(m_cmd.sel, a), exp_smem_read(m_cmd.sel, a), id));
        end
      end
    end
    m_cmd = null;
  endfunction

  //---------------------------------------------------------------------------
  // ローカルポートのアクセス
  //---------------------------------------------------------------------------
  function void write_mem(mem_item t);
    if( t.during_cmd ) begin
      error({"local access accepted while a command is running : ", t.convert2string()});
    end
    if( t.write ) begin
      m_n_mem_wr++;
      if( t.addr<MEM_DEPTH ) begin
        m_mem[t.addr]     = t.data;
        m_mem_vld[t.addr] = 1'b1;
      end
    end else begin
      m_n_mem_rd++;
      if( !t.rvalid ) begin
        error({"mem_rvalid was low in the cycle after : ", t.convert2string()});
      end
      if( t.addr>=MEM_DEPTH ) begin
        if( t.data!={DATA_W{1'b0}} ) begin
          error($sformatf("out-of-range local read of word %0d returned %0h (exp 0)", t.addr, t.data));
        end
      end else if( !m_mem_vld[t.addr] ) begin
        error($sformatf("testbench : internal memory word %0d is read before it is written", t.addr));
      end else if( t.data!=m_mem[t.addr] ) begin
        error($sformatf("internal memory word %0d = %0h (exp %0h)", t.addr, t.data, m_mem[t.addr]));
      end
    end
  endfunction

  //---------------------------------------------------------------------------
  // 終了時
  //---------------------------------------------------------------------------
  function void check_phase(uvm_phase phase);
    apb_slv_mem::key_q_t keys;
    bit [63:0]           k;
    int unsigned         nbad;
    super.check_phase(phase);
    if( m_cmd!=null ) begin
      error({"a command is still running at the end of the test : ", m_cmd.convert2string()});
    end
    // スレーブのメモリ全体を照合 (書いていないはずの場所が変わっていないことも見る)
    if( m_snap_done ) begin
      nbad = 0;
      keys = smem.get_keys();
      if( keys.size()!=m_exp_smem.num() ) begin
        error($sformatf("slave memory has %0d words, expected %0d", keys.size(), m_exp_smem.num()));
      end
      for( int unsigned i=0; i<keys.size(); i++ ) begin
        k = keys[i];
        if( !m_exp_smem.exists(k) ) begin
          nbad++;
          error($sformatf("slave %0d addr=%0h was written unexpectedly", k[63:32], k[31:0]));
        end else if( smem.get(k)!=m_exp_smem[k] ) begin
          nbad++;
          if( nbad<=8 ) begin
            error($sformatf("slave %0d addr=%0h = %0h (exp %0h)", k[63:32], k[31:0], smem.get(k), m_exp_smem[k]));
          end
        end
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf("commands=%0d (transferred %0d, with error flags %0d) bus transfers=%0d aborted=%0d local writes=%0d local reads=%0d errors=%0d", m_n_cmd, m_n_exec, m_n_err_cmd, m_n_xfer, m_n_abort, m_n_mem_wr, m_n_mem_rd, m_n_err), UVM_NONE)
  endfunction

endclass

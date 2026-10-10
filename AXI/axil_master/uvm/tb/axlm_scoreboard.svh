//=============================================================================
// axlm_scoreboard.svh
//-----------------------------------------------------------------------------
//  scoreboard。書き込みと読み出しを別々に追う (同時に実行されるため)。
//
//  持っている期待値:
//    m_mem      : DUT の内部メモリ (ローカル書き込みと、読み出しコマンドの結果で更新)
//    m_exp_smem : スレーブのメモリ (最初のコマンドの時点の内容を写し、書き込みトランザクションで更新)
//
//  チェック:
//    コマンド受付時 : そのコマンドで出るはずのトランザクションの列を作る
//                     (アドレス / 応答 / 書き込みデータ = 受付時の内部メモリ)
//    トランザクションごと : 順番どおりで、アドレス / PROT / WDATA / WSTRB / 応答が期待どおり。
//                     読み出しデータはスレーブのメモリの内容 (OKAY のときだけ内部メモリへ)
//    コマンド完了時 : done_count = バスで完了した数。STOP_ON_ERROR=1 でエラーがあれば
//                     err_index+1 .. err_index+MAX (理想的なスレーブでは正確な数)、なければ全数。
//                     err_flags / done_err / err_index が、実際に受けた応答と一致。
//                     理想的なスレーブでは、受付から done までのサイクル数が
//                     書き込み 7 + f(n-1) / 読み出し 5 + f(n-1) / 転送しないコマンド 1
//                     (f(i) = i (MAX>=3)、3*(i/MAX) + i%MAX (MAX<3))
//    ローカルポート : 読めたデータが m_mem と一致 (範囲外のアドレスは 0)。
//                     書き込みは読み出しコマンドの実行中、読み出しは書き込みコマンドの実行中に
//                     受け付けられていないこと
//    終了時         : スレーブのメモリ全体が m_exp_smem と一致 (触っていない場所を含む)
//
//  テストベンチ自身の誤り (結果が仕様上決まらない使い方) も報告する:
//    同時に実行中の書き込み / 読み出しコマンドの内部メモリ範囲やスレーブのアドレスが重なる、
//    実行中のコマンドの範囲をローカルポートで触る
//=============================================================================

`uvm_analysis_imp_decl(_wstart)
`uvm_analysis_imp_decl(_wdone)
`uvm_analysis_imp_decl(_rstart)
`uvm_analysis_imp_decl(_rdone)
`uvm_analysis_imp_decl(_mem)
`uvm_analysis_imp_decl(_axi)

class axlm_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(axlm_scoreboard)

  uvm_analysis_imp_wstart #(cmd_item, axlm_scoreboard) wstart_imp;
  uvm_analysis_imp_wdone  #(cmd_item, axlm_scoreboard) wdone_imp;
  uvm_analysis_imp_rstart #(cmd_item, axlm_scoreboard) rstart_imp;
  uvm_analysis_imp_rdone  #(cmd_item, axlm_scoreboard) rdone_imp;
  uvm_analysis_imp_mem    #(mem_item, axlm_scoreboard) mem_imp;
  uvm_analysis_imp_axi    #(axi_item, axlm_scoreboard) axi_imp;

  axi_slv_mem smem;                 // スレーブのメモリ (responder と共有)
  axi_slv_cfg cfg;                  // スレーブの設定 (responder と共有)

  // 期待値
  protected bit [DATA_W-1:0] m_mem[MEM_DEPTH];
  protected bit              m_mem_vld[MEM_DEPTH];
  protected bit [DATA_W-1:0] m_exp_smem[bit [63:0]];
  protected bit              m_snap_done;

  // 実行中のコマンドと期待値 (方向ごと。[0] = 読み出し / [1] = 書き込み)
  protected cmd_item         m_cmd[2];
  protected bit              m_empty[2];
  protected bit              m_bad[2];
  protected bit              m_ideal[2];
  protected bit [63:0]       m_x_addr0[$];   // 読み出しのトランザクションのアドレス
  protected bit [1:0]        m_x_resp0[$];
  protected bit [63:0]       m_x_addr1[$];   // 書き込み
  protected bit [1:0]        m_x_resp1[$];
  protected bit [DATA_W-1:0] m_x_data1[$];   // 書き込みデータ (受付時の内部メモリ)
  protected int unsigned     m_n_x[2];       // 出るはずのトランザクション数 (止めなければ)
  protected int unsigned     m_xi[2];        // バスで完了した数
  protected int unsigned     m_k[2];         // 最初のエラー応答の番号 (無ければ m_n_x)
  protected int unsigned     m_nmin[2];
  protected int unsigned     m_nmax[2];
  protected bit [3:0]        m_got_flags[2]; // 実際に受けた応答の種類

  // 統計
  protected int unsigned     m_n_cmd[2];
  protected int unsigned     m_n_exec[2];
  protected int unsigned     m_n_rsperr[2];
  protected int unsigned     m_n_stop[2];
  protected int unsigned     m_n_exact[2];
  protected int unsigned     m_n_tr[2];
  protected int unsigned     m_n_conc;
  protected int unsigned     m_n_mem_wr;
  protected int unsigned     m_n_mem_rd;
  protected int unsigned     m_n_err;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    wstart_imp = new("wstart_imp", this);
    wdone_imp  = new("wdone_imp", this);
    rstart_imp = new("rstart_imp", this);
    rdone_imp  = new("rdone_imp", this);
    mem_imp    = new("mem_imp", this);
    axi_imp    = new("axi_imp", this);
  endfunction

  protected function void error(string msg);
    m_n_err++;
    `uvm_error("SCB", msg)
  endfunction

  //---------------------------------------------------------------------------
  // コマンドの分類 (coverage からも使う)
  //---------------------------------------------------------------------------
  static function bit cmd_is_empty(cmd_item c);
    return (c.len==0);
  endfunction

  static function bit mem_bad(cmd_item c);
    return ((c.maddr+c.len)>MEM_DEPTH);
  endfunction

  static function bit align_bad(cmd_item c);
    return ((c.addr % 64'(STRB_W))!=64'd0);
  endfunction

  static function bit range_bad(cmd_item c);
    return c.incr&&(64'(c.len)>(SPACE_WORDS - (c.addr/64'(STRB_W))));
  endfunction

  // DUT が err_flags[2] で断るべきコマンドか
  static function bit cmd_is_bad(cmd_item c);
    return !cmd_is_empty(c)&&(mem_bad(c)||align_bad(c)||range_bad(c));
  endfunction

  static function bit cmd_is_exec(cmd_item c);
    return !cmd_is_empty(c)&&!cmd_is_bad(c);
  endfunction

  // 理想的なスレーブで、i 番目のトランザクションをエンジンが受け付けるサイクル
  static function int unsigned f_acc(int unsigned i, int unsigned max_out);
    if( max_out>=3 ) begin
      return i;
    end
    return (3 * (i / max_out)) + (i % max_out);
  endfunction

  // 理想的なスレーブで k 番目がエラー応答のときに出る数 (エラー応答を受けたサイクルから止める)
  static function int unsigned f_stop_cnt(int unsigned k, int unsigned n, int unsigned max_out);
    int unsigned c;
    c = 0;
    for( int unsigned j=0; j<n; j++ ) begin
      if( f_acc(j,max_out)<=(f_acc(k,max_out)+2) ) begin
        c++;
      end
    end
    return c;
  endfunction

  static function bit [3:0] resp_flag(bit [1:0] r);
    case( r )
      2'b10 : begin
        return 4'b0001;
      end
      2'b11 : begin
        return 4'b0010;
      end
      2'b01 : begin
        return 4'b1000;
      end
      default : begin
        return 4'b0000;
      end
    endcase
  endfunction

  protected function bit [DATA_W-1:0] exp_smem_read(bit [63:0] a);
    bit [63:0] k;
    k = axi_slv_mem::key(a);
    if( m_exp_smem.exists(k) ) begin
      return m_exp_smem[k];
    end
    return {DATA_W{1'b0}};
  endfunction

  // スレーブのメモリの現在の内容を期待値に写す (最初のコマンドのときに 1 回)
  protected function void snapshot_smem();
    axi_slv_mem::key_q_t keys;
    keys = smem.get_keys();
    m_exp_smem.delete();
    for( int unsigned i=0; i<keys.size(); i++ ) begin
      m_exp_smem[keys[i]] = smem.get(keys[i]);
    end
    m_snap_done = 1'b1;
  endfunction

  //---------------------------------------------------------------------------
  // コマンド受付 : 期待されるトランザクションの列を作る
  //   スレーブの設定は受付時の値を使う (仮想シーケンスは、コマンドの実行中に変えない)
  //---------------------------------------------------------------------------
  protected function void cmd_start(cmd_item c);
    int unsigned d;
    int unsigned o;
    bit [63:0]   a;
    bit [1:0]    r;
    d = c.wr ? 1 : 0;
    o = 1 - d;
    if( !m_snap_done ) begin
      snapshot_smem();
    end
    if( m_cmd[d]!=null ) begin
      error({"command accepted while the previous one is not done : ", c.convert2string()});
    end
    m_cmd[d]       = c;
    m_empty[d]     = cmd_is_empty(c);
    m_bad[d]       = cmd_is_bad(c);
    m_ideal[d]     = cfg.is_ideal();
    m_xi[d]        = 0;
    m_got_flags[d] = 4'b0000;
    if( d==1 ) begin
      m_x_addr1.delete();
      m_x_resp1.delete();
      m_x_data1.delete();
    end else begin
      m_x_addr0.delete();
      m_x_resp0.delete();
    end
    m_n_x[d] = 0;
    m_k[d]   = 0;
    if( !m_empty[d]&&!m_bad[d] ) begin
      m_n_x[d] = c.len;
      m_k[d]   = c.len;
      for( int unsigned i=0; i<c.len; i++ ) begin
        a = c.incr ? (c.addr + (64'(i) * 64'(STRB_W))) : c.addr;
        if( d==1 ) begin
          r = cfg.wresp(a);
          m_x_addr1.push_back(a);
          m_x_resp1.push_back(r);
          if( !m_mem_vld[c.maddr+i] ) begin
            error($sformatf("testbench : internal memory word %0d is sent before it is written", c.maddr+i));
          end
          m_x_data1.push_back(m_mem[c.maddr+i]);
        end else begin
          r = cfg.rresp(a);
          m_x_addr0.push_back(a);
          m_x_resp0.push_back(r);
        end
        if( (r!=2'b00)&&(m_k[d]==c.len) ) begin
          m_k[d] = i;
        end
      end
    end
    // done_count の範囲
    if( STOP_ON_ERROR&&(m_k[d]<m_n_x[d]) ) begin
      if( m_ideal[d] ) begin
        m_nmin[d] = f_stop_cnt(m_k[d], m_n_x[d], c.wr ? MAX_WR : MAX_RD);
        m_nmax[d] = m_nmin[d];
      end else begin
        m_nmin[d] = m_k[d] + 1;
        m_nmax[d] = m_k[d] + (c.wr ? MAX_WR : MAX_RD);
        if( m_nmax[d]>m_n_x[d] ) begin
          m_nmax[d] = m_n_x[d];
        end
      end
    end else begin
      m_nmin[d] = m_n_x[d];
      m_nmax[d] = m_n_x[d];
    end
    // テストベンチの誤り : 同時に実行中のコマンドと内部メモリやスレーブのアドレスが重なる
    if( (m_cmd[o]!=null)&&cmd_is_exec(c)&&cmd_is_exec(m_cmd[o]) ) begin
      m_n_conc++;
      if( c.mem_overlap(m_cmd[o].maddr,m_cmd[o].len) ) begin
        error($sformatf("testbench : internal memory ranges of the running commands overlap : %s / %s", c.convert2string(), m_cmd[o].convert2string()));
      end
      if( (c.bus_lo()<=m_cmd[o].bus_hi())&&(m_cmd[o].bus_lo()<=c.bus_hi()) ) begin
        error($sformatf("testbench : bus address ranges of the running commands overlap : %s / %s", c.convert2string(), m_cmd[o].convert2string()));
      end
    end
  endfunction

  function void write_wstart(cmd_item c);
    cmd_start(c);
  endfunction

  function void write_rstart(cmd_item c);
    cmd_start(c);
  endfunction

  //---------------------------------------------------------------------------
  // AXI トランザクション 1 つ (応答まで完了)
  //---------------------------------------------------------------------------
  function void write_axi(axi_item t);
    int unsigned     d;
    int unsigned     i;
    bit [63:0]       a;
    bit [1:0]        r;
    bit [DATA_W-1:0] wd;
    bit [DATA_W-1:0] m;
    d = t.write ? 1 : 0;
    if( m_cmd[d]==null ) begin
      error({"transaction on the bus without a command : ", t.convert2string()});
      return;
    end
    if( m_xi[d]>=m_n_x[d] ) begin
      error($sformatf("extra transaction on the bus (the command needs %0d) : %s", m_n_x[d], t.convert2string()));
      return;
    end
    i       = m_xi[d];
    m_xi[d] = m_xi[d] + 1;
    m_n_tr[d]++;
    m_got_flags[d] = m_got_flags[d] | resp_flag(t.resp);
    if( d==1 ) begin
      a  = m_x_addr1[i];
      r  = m_x_resp1[i];
      wd = m_x_data1[i];
      if( (t.addr!=a)||(t.prot!=m_cmd[1].prot)||(t.data!=wd)||(t.strb!=m_cmd[1].strb)||(t.resp!=r) ) begin
        error($sformatf("write transaction %0d : %s (exp addr=%0h prot=%b data=%0h strb=%b resp=%b)", i, t.convert2string(), a, m_cmd[1].prot, wd, m_cmd[1].strb, r));
      end
      // 期待値の更新 (OKAY のときだけスレーブのメモリが変わる)
      if( t.resp==2'b00 ) begin
        m = exp_smem_read(a);
        for( int unsigned b=0; b<STRB_W; b++ ) begin
          if( m_cmd[1].strb[b] ) begin
            m[8*b +: 8] = wd[8*b +: 8];
          end
        end
        m_exp_smem[axi_slv_mem::key(a)] = m;
      end
    end else begin
      a = m_x_addr0[i];
      r = m_x_resp0[i];
      if( (t.addr!=a)||(t.prot!=m_cmd[0].prot)||(t.resp!=r) ) begin
        error($sformatf("read transaction %0d : %s (exp addr=%0h prot=%b resp=%b)", i, t.convert2string(), a, m_cmd[0].prot, r));
      end
      // OKAY のデータだけ内部メモリへ入る
      if( t.resp==2'b00 ) begin
        if( t.data!=exp_smem_read(a) ) begin
          error($sformatf("read transaction %0d : RDATA=%0h but the slave memory holds %0h (slave model)", i, t.data, exp_smem_read(a)));
        end
        m_mem[m_cmd[0].maddr+i]     = t.data;
        m_mem_vld[m_cmd[0].maddr+i] = 1'b1;
      end
    end
  endfunction

  //---------------------------------------------------------------------------
  // コマンド完了
  //---------------------------------------------------------------------------
  protected function void cmd_done(cmd_item c);
    int unsigned d;
    int unsigned n;
    int unsigned exp_cyc;
    bit [3:0]    exp_flags;
    bit [63:0]   a;
    string       id;
    d = c.wr ? 1 : 0;
    if( m_cmd[d]==null ) begin
      error("done without an accepted command");
      return;
    end
    id = c.convert2string();
    n  = m_xi[d];
    m_n_cmd[d]++;
    if( !m_empty[d]&&!m_bad[d] ) begin
      m_n_exec[d]++;
    end
    // 完了した数
    if( c.done_count!=n ) begin
      error($sformatf("done_count=%0d but %0d transaction(s) completed on the bus : %s", c.done_count, n, id));
    end
    if( (n<m_nmin[d])||(n>m_nmax[d]) ) begin
      error($sformatf("%0d transaction(s) completed (exp %0d..%0d, first error at %0d) : %s", n, m_nmin[d], m_nmax[d], m_k[d], id));
    end
    // フラグ (実際に受けた応答 + コマンドの誤り)
    exp_flags = m_got_flags[d] | {1'b0, (m_bad[d]&&!m_empty[d]), 2'b00};
    if( c.err_flags!=exp_flags ) begin
      error($sformatf("err_flags=%b (exp %b) : %s", c.err_flags, exp_flags, id));
    end
    if( c.done_err!=(|exp_flags) ) begin
      error($sformatf("done_err=%b (exp %b) : %s", c.done_err, |exp_flags, id));
    end
    if( (m_k[d]<n)&&(c.err_index!=m_k[d]) ) begin
      error($sformatf("err_index=%0d (exp %0d) : %s", c.err_index, m_k[d], id));
    end
    if( (m_got_flags[d]&4'b1011)!=4'b0000 ) begin
      m_n_rsperr[d]++;
    end
    if( n<m_n_x[d] ) begin
      m_n_stop[d]++;
    end
    // 受付から done までのサイクル数 (理想的なスレーブのとき)
    if( m_ideal[d] ) begin
      if( n==0 ) begin
        exp_cyc = 1;
      end else if( c.wr ) begin
        exp_cyc = 7 + f_acc(n-1, MAX_WR);
      end else begin
        exp_cyc = 5 + f_acc(n-1, MAX_RD);
      end
      if( (c.cyc_done-c.cyc_start)!=exp_cyc ) begin
        error($sformatf("done came %0d cycles after the command was accepted (exp %0d) : %s", c.cyc_done-c.cyc_start, exp_cyc, id));
      end
      m_n_exact[d]++;
    end
    // 書き込み : 触ったワードがスレーブのメモリに反映されていること
    if( c.wr ) begin
      for( int unsigned i=0; i<n; i++ ) begin
        a = m_x_addr1[i];
        if( smem.read_word(a)!=exp_smem_read(a) ) begin
          error($sformatf("slave addr=%0h = %0h (exp %0h) : %s", a, smem.read_word(a), exp_smem_read(a), id));
        end
      end
    end
    m_cmd[d] = null;
  endfunction

  function void write_wdone(cmd_item c);
    cmd_done(c);
  endfunction

  function void write_rdone(cmd_item c);
    cmd_done(c);
  endfunction

  //---------------------------------------------------------------------------
  // ローカルポートのアクセス
  //---------------------------------------------------------------------------
  function void write_mem(mem_item t);
    if( t.write ) begin
      m_n_mem_wr++;
      if( t.during_rcmd ) begin
        error({"local write accepted while a read command is running : ", t.convert2string()});
      end
      if( (m_cmd[1]!=null)&&!m_empty[1]&&!m_bad[1]&&m_cmd[1].mem_overlap(t.addr,1) ) begin
        error({"testbench : local write to the range of the running write command : ", t.convert2string()});
      end
      if( t.addr<MEM_DEPTH ) begin
        m_mem[t.addr]     = t.data;
        m_mem_vld[t.addr] = 1'b1;
      end
    end else begin
      m_n_mem_rd++;
      if( t.during_wcmd ) begin
        error({"local read accepted while a write command is running : ", t.convert2string()});
      end
      if( !t.rvalid ) begin
        error({"mem_r_rvalid was low in the cycle after : ", t.convert2string()});
      end
      if( t.addr>=MEM_DEPTH ) begin
        if( t.data!={DATA_W{1'b0}} ) begin
          error($sformatf("out-of-range local read of word %0d returned %0h (exp 0)", t.addr, t.data));
        end
      end else if( (m_cmd[0]!=null)&&!m_empty[0]&&!m_bad[0]&&!t.with_rcmd&&m_cmd[0].mem_overlap(t.addr,1) ) begin
        error({"testbench : local read from the range of the running read command : ", t.convert2string()});
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
    axi_slv_mem::key_q_t keys;
    bit [63:0]           k;
    int unsigned         nbad;
    super.check_phase(phase);
    for( int unsigned d=0; d<2; d++ ) begin
      if( m_cmd[d]!=null ) begin
        error({"a command is still running at the end of the test : ", m_cmd[d].convert2string()});
      end
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
          error($sformatf("slave addr=%0h was written unexpectedly", k));
        end else if( smem.get(k)!=m_exp_smem[k] ) begin
          nbad++;
          if( nbad<=8 ) begin
            error($sformatf("slave addr=%0h = %0h (exp %0h)", k, smem.get(k), m_exp_smem[k]));
          end
        end
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf("write commands=%0d (transferred %0d, error responses %0d, stopped early %0d, cycle-exact %0d) transactions=%0d", m_n_cmd[1], m_n_exec[1], m_n_rsperr[1], m_n_stop[1], m_n_exact[1], m_n_tr[1]), UVM_NONE)
    `uvm_info("SCB", $sformatf("read commands=%0d (transferred %0d, error responses %0d, stopped early %0d, cycle-exact %0d) transactions=%0d", m_n_cmd[0], m_n_exec[0], m_n_rsperr[0], m_n_stop[0], m_n_exact[0], m_n_tr[0]), UVM_NONE)
    `uvm_info("SCB", $sformatf("commands started while the other direction was running=%0d local writes=%0d local reads=%0d errors=%0d", m_n_conc, m_n_mem_wr, m_n_mem_rd, m_n_err), UVM_NONE)
  endfunction

endclass

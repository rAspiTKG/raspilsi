//=============================================================================
// copy_scoreboard.svh
//-----------------------------------------------------------------------------
//  コピーエンジンの scoreboard。
//    受付時 (write_start) : src の内容と期待エラー (cfg のエラー範囲と重なるか) を
//                           スナップショットする
//    バースト (write_wr/rd): マスタの義務をバースト単位でチェック
//                           INCR / size = バス幅 / len+1 <= MAX_BURST /
//                           4KB 境界を跨がない / ID / WSTRB 全有効
//    完了時 (write_done)  : 1) done_err == 期待エラー
//                           2) Read / Write それぞれ、src / dst から連続したアドレスで
//                              合計 len ビート。分割は min(残り, MAX_BURST, 4KB まで)
//                           3) R で受けたデータ列 == W で出したデータ列
//                           4) エラーが無ければ dst の内容 == 受付時の src の内容
//=============================================================================

`uvm_analysis_imp_decl(_start)
`uvm_analysis_imp_decl(_done)
`uvm_analysis_imp_decl(_wr)
`uvm_analysis_imp_decl(_rd)

class copy_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(copy_scoreboard)

  uvm_analysis_imp_start #(cmd_item, copy_scoreboard)       start_imp;
  uvm_analysis_imp_done  #(cmd_item, copy_scoreboard)       done_imp;
  uvm_analysis_imp_wr    #(axi_burst_item, copy_scoreboard) wr_imp;
  uvm_analysis_imp_rd    #(axi_burst_item, copy_scoreboard) rd_imp;

  axi_mem     mem;
  axi_slv_cfg cfg;

  // 実行中コマンドの期待値
  protected bit              m_active;
  protected bit [ADDR_W-1:0] m_src;
  protected bit [ADDR_W-1:0] m_dst;
  protected int unsigned     m_len;
  protected bit              m_exp_err;
  protected bit [DATA_W-1:0] m_src_data[$];

  protected axi_burst_item   m_wr_q[$];
  protected axi_burst_item   m_rd_q[$];

  // 集計
  protected int unsigned     m_n_cmd;
  protected int unsigned     m_n_cmd_err;
  protected int unsigned     m_n_beat;
  protected int unsigned     m_n_rd_burst;
  protected int unsigned     m_n_wr_burst;
  protected int unsigned     m_n_err;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    start_imp = new("start_imp", this);
    done_imp  = new("done_imp", this);
    wr_imp    = new("wr_imp", this);
    rd_imp    = new("rd_imp", this);
  endfunction

  protected function void error(string msg);
    m_n_err++;
    `uvm_error("SCB", msg)
  endfunction

  //---------------------------------------------------------------------------
  // コマンド受付
  //---------------------------------------------------------------------------
  function void write_start(cmd_item c);
    if( m_active ) begin
      error("command started before the previous one completed");
    end
    if( (m_wr_q.size()!=0)||(m_rd_q.size()!=0) ) begin
      error($sformatf("%0d write / %0d read bursts observed outside of a command", m_wr_q.size(), m_rd_q.size()));
      m_wr_q.delete();
      m_rd_q.delete();
    end
    m_active  = 1'b1;
    m_src     = c.src;
    m_dst     = c.dst;
    m_len     = c.len;
    m_exp_err = cfg.range_hits_err(c.src, c.len)||cfg.range_hits_err(c.dst, c.len);
    m_src_data.delete();
    for( int unsigned i=0; i<c.len; i++ ) begin
      m_src_data.push_back(mem.read_word(c.src+ADDR_W'(i*STRB_W)));
    end
  endfunction

  //---------------------------------------------------------------------------
  // バースト単位のチェック (マスタの義務)
  //---------------------------------------------------------------------------
  protected function void check_burst(axi_burst_item t, int unsigned exp_id);
    if( t.burst!=AXI_INCR ) begin
      error({"burst type is not INCR : ", t.convert2string()});
    end
    if( 32'(t.size)!=ADDR_LSB ) begin
      error({"size is not the bus width : ", t.convert2string()});
    end
    if( (32'(t.len)+1)>MAX_BURST ) begin
      error({"burst longer than MAX_BURST : ", t.convert2string()});
    end
    if( (32'(t.addr[11:0])+((32'(t.len)+1)*STRB_W))>4096 ) begin
      error({"burst crosses 4KB boundary : ", t.convert2string()});
    end
    if( 32'(t.id)!=exp_id ) begin
      error($sformatf("ID %0d (exp %0d) : %s", t.id, exp_id, t.convert2string()));
    end
  endfunction

  function void write_wr(axi_burst_item t);
    check_burst(t, WR_ID);
    foreach( t.strb[i] ) begin
      if( t.strb[i]!==STRB_ALL ) begin
        error($sformatf("WSTRB=%0h at beat %0d : %s", t.strb[i], i, t.convert2string()));
      end
    end
    m_wr_q.push_back(t);
  endfunction

  function void write_rd(axi_burst_item t);
    check_burst(t, RD_ID);
    m_rd_q.push_back(t);
  endfunction

  //---------------------------------------------------------------------------
  // バースト列: start から連続、合計 len ビート、分割は貪欲 (最大長) であること
  //---------------------------------------------------------------------------
  protected function void check_seq(string name, axi_burst_item q[$], bit [ADDR_W-1:0] start, int unsigned len);
    bit [ADDR_W-1:0] a;
    int unsigned     rem;
    int unsigned     exp_bl;
    int unsigned     b4k;
    a   = start;
    rem = len;
    foreach( q[i] ) begin
      b4k    = (4096 - 32'(a[11:0])) / STRB_W;
      exp_bl = MAX_BURST;
      if( rem<exp_bl ) begin
        exp_bl = rem;
      end
      if( b4k<exp_bl ) begin
        exp_bl = b4k;
      end
      if( q[i].addr!==a ) begin
        error($sformatf("%s burst #%0d addr=%08h (exp %08h)", name, i, q[i].addr, a));
      end
      if( (32'(q[i].len)+1)!=exp_bl ) begin
        error($sformatf("%s burst #%0d len+1=%0d (exp %0d)", name, i, 32'(q[i].len)+1, exp_bl));
      end
      a   = q[i].addr + ADDR_W'((32'(q[i].len)+1)*STRB_W);
      rem = (rem>(32'(q[i].len)+1)) ? (rem - (32'(q[i].len)+1)) : 0;
    end
    if( rem!=0 ) begin
      error($sformatf("%s : %0d beats missing (cmd len=%0d)", name, rem, len));
    end
  endfunction

  //---------------------------------------------------------------------------
  // 完了
  //---------------------------------------------------------------------------
  function void write_done(cmd_item c);
    bit [DATA_W-1:0] rd_data[$];
    bit [DATA_W-1:0] wr_data[$];
    bit [DATA_W-1:0] act;
    int unsigned     n_mis;
    if( !m_active ) begin
      error("done without a started command");
      return;
    end
    // 1) done_err
    if( c.done_err!==m_exp_err ) begin
      error($sformatf("done_err=%0d (exp %0d) : %s", c.done_err, m_exp_err, c.convert2string()));
    end
    // 2) バースト列
    check_seq("READ", m_rd_q, m_src, m_len);
    check_seq("WRITE", m_wr_q, m_dst, m_len);
    // 3) R で受けたデータ列 == W で出したデータ列
    foreach( m_rd_q[i] ) begin
      foreach( m_rd_q[i].data[j] ) begin
        rd_data.push_back(m_rd_q[i].data[j]);
      end
    end
    foreach( m_wr_q[i] ) begin
      foreach( m_wr_q[i].data[j] ) begin
        wr_data.push_back(m_wr_q[i].data[j]);
      end
    end
    if( rd_data.size()!=wr_data.size() ) begin
      error($sformatf("R beats (%0d) != W beats (%0d)", rd_data.size(), wr_data.size()));
    end else begin
      n_mis = 0;
      foreach( rd_data[i] ) begin
        if( rd_data[i]!==wr_data[i] ) begin
          n_mis++;
        end
      end
      if( n_mis!=0 ) begin
        error($sformatf("W data differs from R data in %0d / %0d beats : %s", n_mis, rd_data.size(), c.convert2string()));
      end
    end
    // 4) メモリ (エラー注入時は不定なので比較しない)
    if( !m_exp_err ) begin
      n_mis = 0;
      for( int unsigned i=0; i<m_len; i++ ) begin
        act = mem.read_word(m_dst+ADDR_W'(i*STRB_W));
        if( act!==m_src_data[i] ) begin
          if( n_mis<3 ) begin
            `uvm_error("SCB", $sformatf("dst[%0d] @%08h exp=%016h act=%016h", i, m_dst+ADDR_W'(i*STRB_W), m_src_data[i], act))
          end
          n_mis++;
        end
      end
      if( n_mis!=0 ) begin
        error($sformatf("dst differs from src in %0d / %0d beats : %s", n_mis, m_len, c.convert2string()));
      end
    end
    // 集計
    m_n_cmd++;
    if( m_exp_err ) begin
      m_n_cmd_err++;
    end
    m_n_beat     += m_len;
    m_n_rd_burst += m_rd_q.size();
    m_n_wr_burst += m_wr_q.size();
    m_rd_q.delete();
    m_wr_q.delete();
    m_active = 1'b0;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf("commands=%0d (error-injected %0d) beats=%0d read_bursts=%0d write_bursts=%0d errors=%0d"
                              , m_n_cmd, m_n_cmd_err, m_n_beat, m_n_rd_burst, m_n_wr_burst, m_n_err), UVM_NONE)
    if( m_n_cmd==0 ) begin
      `uvm_error("SCB", "no command was checked")
    end
    if( m_active ) begin
      `uvm_error("SCB", "a command was still running at the end of the test")
    end
  endfunction

endclass

//=============================================================================
// lb_scoreboard.svh
//-----------------------------------------------------------------------------
//  axi4_master_linebuf の scoreboard。
//    受付時 (write_start) : 期待する err_flags と、出力先メモリの期待値
//                           (ガード領域を含む全バイト) を作る
//    バースト (write_wr/rd): マスタの義務と DUT の仕様をバースト単位でチェック
//                           INCR / size = バス幅 / len+1 <= MAX_BURST /
//                           4KB 境界を跨がない / ID / AxCACHE 等の属性
//    完了時 (write_done)  : 1) err_flags / done_err == 期待値
//                           2) Read / Write のバースト列が、ラインごとに
//                              base + y*stride から min(残り, MAX_BURST, 4KB まで)
//                              で分割した列と一致する
//                           3) WSTRB がライン最終ビートだけ端数で、他は全有効
//                           4) 出力先メモリ == 期待値 (ライン外は元のパターンのまま)
//                           5) ライン完了パルスの回数
//=============================================================================

`uvm_analysis_imp_decl(_start)
`uvm_analysis_imp_decl(_done)
`uvm_analysis_imp_decl(_wr)
`uvm_analysis_imp_decl(_rd)

class lb_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(lb_scoreboard)

  uvm_analysis_imp_start #(cmd_item, lb_scoreboard)       start_imp;
  uvm_analysis_imp_done  #(cmd_item, lb_scoreboard)       done_imp;
  uvm_analysis_imp_wr    #(axi_burst_item, lb_scoreboard) wr_imp;
  uvm_analysis_imp_rd    #(axi_burst_item, lb_scoreboard) rd_imp;

  axi_mem     src_mem;
  axi_mem     dst_mem;
  axi_slv_cfg rd_cfg;
  axi_slv_cfg wr_cfg;

  // 実行中コマンドの期待値
  protected bit            m_active;
  protected bit            m_exec;          // 実際に転送するコマンド (空 / 誤りでない)
  protected bit [2:0]      m_exp_flags;
  protected bit [7:0]      m_exp_mem[bit [63:0]];

  protected axi_burst_item m_wr_q[$];
  protected axi_burst_item m_rd_q[$];

  // 集計
  protected int unsigned   m_n_cmd;
  protected int unsigned   m_n_exec;
  protected int unsigned   m_n_err_cmd;
  protected longint unsigned m_n_pix;
  protected int unsigned   m_n_rd_burst;
  protected int unsigned   m_n_wr_burst;
  protected longint unsigned m_n_bytes;
  protected int unsigned   m_n_err;

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
  // コマンドの分類
  //---------------------------------------------------------------------------
  // DUT が err_flags[2] で断るべきコマンドか
  static function bit cmd_is_bad(cmd_item c);
    bit width_over;
    bit src_bad;
    bit dst_bad;
    width_over = (c.w>MAX_LINE_PIXELS);
    src_bad    = ((c.src%64'(IN_STRB_W))!=64'd0)||((c.sstr%IN_STRB_W)!=0);
    dst_bad    = ((c.dst%64'(OUT_STRB_W))!=64'd0)||((c.dstr%OUT_STRB_W)!=0);
    return width_over||src_bad||dst_bad;
  endfunction

  static function bit cmd_is_empty(cmd_item c);
    return (c.w==0)||(c.h==0);
  endfunction

  // [base から beats ビート] のどれかのビート先頭アドレスが cfg のエラー範囲に入るか
  protected function bit beats_hit_err(axi_slv_cfg cfg, bit [63:0] base, int unsigned beats, int unsigned bus_bytes);
    bit [63:0] a;
    if( !cfg.err_enabled() ) begin
      return 1'b0;
    end
    for( int unsigned i=0; i<beats; i++ ) begin
      a = base + (64'(i) * 64'(bus_bytes));
      if( cfg.in_err(a) ) begin
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  //---------------------------------------------------------------------------
  // コマンド受付
  //---------------------------------------------------------------------------
  function void write_start(cmd_item c);
    int unsigned lb;
    int unsigned ib;
    int unsigned ob;
    bit [63:0]   a;
    bit [63:0]   lo;
    bit [63:0]   hi;
    bit [63:0]   line;
    bit [63:0]   sline;
    bit [63:0]   beat_a;
    bit [7:0]    s;
    bit          rd_hit;
    bit          wr_hit;
    if( m_active ) begin
      error("command started before the previous one completed");
    end
    if( (m_wr_q.size()!=0)||(m_rd_q.size()!=0) ) begin
      error($sformatf("%0d write / %0d read bursts observed outside of a command", m_wr_q.size(), m_rd_q.size()));
      m_wr_q.delete();
      m_rd_q.delete();
    end
    lb          = lb_line_bytes(c.w);
    ib          = lb_beats(lb, IN_STRB_W);
    ob          = lb_beats(lb, OUT_STRB_W);
    m_active    = 1'b1;
    m_exec      = !cmd_is_empty(c)&&!cmd_is_bad(c);
    m_exp_flags = 3'b000;
    if( !cmd_is_empty(c)&&cmd_is_bad(c) ) begin
      m_exp_flags[2] = 1'b1;
    end
    // 出力先メモリの期待値: まず全体を元のパターンにする
    m_exp_mem.delete();
    lo = c.dst - 64'(GUARD);
    hi = c.dst + (64'((c.h>0) ? (c.h-1) : 0) * 64'(c.dstr)) + 64'(ob*OUT_STRB_W) + 64'(GUARD);
    for( a=lo; a<hi; a=a+64'd1 ) begin
      m_exp_mem[a] = lb_pattern(a);
    end
    if( m_exec ) begin
      for( int unsigned y=0; y<c.h; y++ ) begin
        // エラー応答の期待値
        sline  = c.src + (64'(y) * 64'(c.sstr));
        line   = c.dst + (64'(y) * 64'(c.dstr));
        rd_hit = beats_hit_err(rd_cfg, sline, ib, IN_STRB_W);
        wr_hit = beats_hit_err(wr_cfg, line, ob, OUT_STRB_W);
        if( rd_hit ) begin
          m_exp_flags[0] = 1'b1;
        end
        if( wr_hit ) begin
          m_exp_flags[1] = 1'b1;
        end
        // ライン内のバイト。スレーブがエラーにするビートは書かれないので元のパターンのまま
        for( int unsigned i=0; i<lb; i++ ) begin
          beat_a = (line + 64'(i)) & ~(64'(OUT_STRB_W) - 64'd1);
          if( !wr_cfg.in_err(beat_a) ) begin
            s = src_mem.read_byte(sline + 64'(i));
            m_exp_mem[line + 64'(i)] = lb_exp_byte(s, i, c.w);
          end
        end
      end
    end
  endfunction

  //---------------------------------------------------------------------------
  // バースト単位のチェック
  //---------------------------------------------------------------------------
  protected function void check_burst(axi_burst_item t);
    int unsigned bus_bytes;
    int unsigned maxb;
    int unsigned exp_id;
    bit [3:0]    exp_cache;
    bit [2:0]    exp_prot;
    bit [3:0]    exp_qos;
    bit [3:0]    exp_region;
    if( t.dir==AXI_WRITE ) begin
      bus_bytes  = OUT_STRB_W;
      maxb       = OUT_MAX_BURST;
      exp_id     = OUT_AXI_ID;
      exp_cache  = AWCACHE_V;
      exp_prot   = AWPROT_V;
      exp_qos    = AWQOS_V;
      exp_region = AWREGION_V;
    end else begin
      bus_bytes  = IN_STRB_W;
      maxb       = IN_MAX_BURST;
      exp_id     = IN_AXI_ID;
      exp_cache  = ARCACHE_V;
      exp_prot   = ARPROT_V;
      exp_qos    = ARQOS_V;
      exp_region = ARREGION_V;
    end
    if( t.burst!=AXI_INCR ) begin
      error({"burst type is not INCR : ", t.convert2string()});
    end
    if( (32'd1<<t.size)!=bus_bytes ) begin
      error({"size is not the bus width : ", t.convert2string()});
    end
    if( (32'(t.len)+1)>maxb ) begin
      error({"burst longer than MAX_BURST : ", t.convert2string()});
    end
    if( (32'(t.addr[11:0])+((32'(t.len)+1)*bus_bytes))>4096 ) begin
      error({"burst crosses 4KB boundary : ", t.convert2string()});
    end
    if( t.id!=exp_id ) begin
      error($sformatf("ID %0d (exp %0d) : %s", t.id, exp_id, t.convert2string()));
    end
    if( (t.cache!==exp_cache)||(t.prot!==exp_prot)||(t.qos!==exp_qos)||(t.region!==exp_region)||(t.lock!==1'b0) ) begin
      error($sformatf("attribute cache=%b prot=%b qos=%0d region=%0d lock=%b : %s", t.cache, t.prot, t.qos, t.region, t.lock, t.convert2string()));
    end
  endfunction

  function void write_wr(axi_burst_item t);
    check_burst(t);
    m_wr_q.push_back(t);
  endfunction

  function void write_rd(axi_burst_item t);
    check_burst(t);
    m_rd_q.push_back(t);
  endfunction

  //---------------------------------------------------------------------------
  // バースト列: ラインごとに base + y*stride から貪欲 (最大長) に分割されていること
  //   Write 側は WSTRB も確認する (ライン最終ビートだけ端数)
  //---------------------------------------------------------------------------
  protected function void check_seq(string name, axi_burst_item q[$], bit [63:0] base, int unsigned stride
                                   , int unsigned h, int unsigned beats, int unsigned bus_bytes, int unsigned maxb
                                   , bit chk_strb, int unsigned last_bytes);
    bit [63:0]           a;
    int unsigned         rem;
    int unsigned         exp_bl;
    int unsigned         b4k;
    int unsigned         qi;
    int unsigned         line_beat;
    bit [MAX_STRB_W-1:0] exp_strb;
    qi = 0;
    for( int unsigned y=0; y<h; y++ ) begin
      a         = base + (64'(y) * 64'(stride));
      rem       = beats;
      line_beat = 0;
      while( rem!=0 ) begin
        if( qi>=q.size() ) begin
          error($sformatf("%s : bursts ended at line %0d (%0d beats missing)", name, y, rem));
          return;
        end
        b4k    = (4096 - 32'(a[11:0])) / bus_bytes;
        exp_bl = maxb;
        if( rem<exp_bl ) begin
          exp_bl = rem;
        end
        if( b4k<exp_bl ) begin
          exp_bl = b4k;
        end
        if( q[qi].addr!==a ) begin
          error($sformatf("%s line %0d burst #%0d addr=%0h (exp %0h)", name, y, qi, q[qi].addr, a));
          return;
        end
        if( (32'(q[qi].len)+1)!=exp_bl ) begin
          error($sformatf("%s line %0d burst #%0d len+1=%0d (exp %0d)", name, y, qi, 32'(q[qi].len)+1, exp_bl));
          return;
        end
        if( chk_strb ) begin
          foreach( q[qi].strb[i] ) begin
            exp_strb = '0;
            for( int unsigned b=0; b<bus_bytes; b++ ) begin
              exp_strb[b] = ((line_beat+i)!=(beats-1))||(b<last_bytes);
            end
            if( q[qi].strb[i]!==exp_strb ) begin
              error($sformatf("%s line %0d beat %0d WSTRB=%0h (exp %0h)", name, y, line_beat+i, q[qi].strb[i], exp_strb));
            end
          end
        end
        a         = a + (64'(exp_bl) * 64'(bus_bytes));
        rem       = rem - exp_bl;
        line_beat = line_beat + exp_bl;
        qi++;
      end
    end
    if( qi!=q.size() ) begin
      error($sformatf("%s : %0d extra bursts", name, q.size()-qi));
    end
  endfunction

  //---------------------------------------------------------------------------
  // 完了
  //---------------------------------------------------------------------------
  function void write_done(cmd_item c);
    int unsigned lb;
    int unsigned ib;
    int unsigned ob;
    int unsigned n_mis;
    bit [7:0]    act;
    if( !m_active ) begin
      error("done without a started command");
      return;
    end
    lb = lb_line_bytes(c.w);
    ib = lb_beats(lb, IN_STRB_W);
    ob = lb_beats(lb, OUT_STRB_W);
    // 1) err_flags / done_err
    if( c.err_flags!==m_exp_flags ) begin
      error($sformatf("err_flags=%b (exp %b) : %s", c.err_flags, m_exp_flags, c.convert2string()));
    end
    if( c.done_err!==(|m_exp_flags) ) begin
      error($sformatf("done_err=%b (exp %b) : %s", c.done_err, |m_exp_flags, c.convert2string()));
    end
    // 2) 3) バースト列と WSTRB
    if( m_exec ) begin
      check_seq("READ", m_rd_q, c.src, c.sstr, c.h, ib, IN_STRB_W, IN_MAX_BURST, 1'b0, 0);
      check_seq("WRITE", m_wr_q, c.dst, c.dstr, c.h, ob, OUT_STRB_W, OUT_MAX_BURST, 1'b1, lb - ((ob-1)*OUT_STRB_W));
    end else begin
      if( (m_rd_q.size()!=0)||(m_wr_q.size()!=0) ) begin
        error($sformatf("%0d read / %0d write bursts for a rejected or empty command", m_rd_q.size(), m_wr_q.size()));
      end
    end
    // 4) 出力先メモリ (ガード領域を含む)
    n_mis = 0;
    foreach( m_exp_mem[a] ) begin
      act = dst_mem.read_byte(a);
      if( act!==m_exp_mem[a] ) begin
        if( n_mis<3 ) begin
          `uvm_error("SCB", $sformatf("dst[%0h] = %02h (exp %02h)", a, act, m_exp_mem[a]))
        end
        n_mis++;
      end
    end
    if( n_mis!=0 ) begin
      error($sformatf("%0d bytes mismatch in the destination : %s", n_mis, c.convert2string()));
    end
    // 5) ライン完了パルス
    if( m_exec ) begin
      if( (c.n_line_in!=c.h)||(c.n_line_out!=c.h) ) begin
        error($sformatf("line_in_done=%0d line_out_done=%0d (exp %0d)", c.n_line_in, c.n_line_out, c.h));
      end
    end else begin
      if( (c.n_line_in!=0)||(c.n_line_out!=0) ) begin
        error("line pulses for a rejected or empty command");
      end
    end
    // 集計
    m_n_cmd++;
    if( m_exec ) begin
      m_n_exec++;
      m_n_pix   += longint'(c.w) * longint'(c.h);
      m_n_bytes += longint'(lb) * longint'(c.h);
    end
    if( m_exp_flags!=3'b000 ) begin
      m_n_err_cmd++;
    end
    m_n_rd_burst += m_rd_q.size();
    m_n_wr_burst += m_wr_q.size();
    m_rd_q.delete();
    m_wr_q.delete();
    m_exp_mem.delete();
    m_active = 1'b0;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf("commands=%0d (transferred %0d, with error flags %0d) pixels=%0d bytes=%0d read_bursts=%0d write_bursts=%0d errors=%0d"
                              , m_n_cmd, m_n_exec, m_n_err_cmd, m_n_pix, m_n_bytes, m_n_rd_burst, m_n_wr_burst, m_n_err), UVM_NONE)
    if( m_n_exec==0 ) begin
      `uvm_error("SCB", "no transferred command was checked")
    end
    if( m_active ) begin
      `uvm_error("SCB", "a command was still running at the end of the test")
    end
  endfunction

endclass

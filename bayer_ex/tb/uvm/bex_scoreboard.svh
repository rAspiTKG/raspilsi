// ============================================================================
// bex_scoreboard : 転送の順に比べる
//   入力側のモニタの転送(そのときの設定つき)から、リファレンスモデルで期待値を作り、
//   出力側のモニタの転送と1つずつ比べる(sof / eol / eof と8画素)。
//   - レイテンシ(出力のクロック − 入力のクロック)が3より小さければエラー
//   - リセットがかかったら、出力されていない期待値を捨てる(DUT も捨てる)
//   - 終わりに出力されていない期待値が残っていればエラー
//   +BEX_DUMP=<ファイル> を付けると、比べた組(設定・入力・出力)を1行ずつ書く
//   (tools/bex_model.py で Python のモデルと照合する)
// ============================================================================
`uvm_analysis_imp_decl(_in)
`uvm_analysis_imp_decl(_out)

class bex_scoreboard extends uvm_component;
  `uvm_component_utils(bex_scoreboard)

  localparam int MIN_LAT = 3;   // 止められていないときのレイテンシ

  uvm_analysis_imp_in  #(bex_item, bex_scoreboard) in_imp;
  uvm_analysis_imp_out #(bex_item, bex_scoreboard) out_imp;
  virtual bex_misc_if mvif;
  bex_coverage        cov;
  bex_item            q[$];
  longint             n_in;
  longint             n_out;
  longint             n_match;
  longint             n_mismatch;
  longint             n_flushed;
  longint             n_reset;
  longint             min_lat;
  longint             max_lat;
  int                 max_msg = 10;
  string              dump_name;
  int                 dump_fd;

  function new( string name, uvm_component parent );
    super.new(name, parent);
    in_imp  = new("in_imp", this);
    out_imp = new("out_imp", this);
  endfunction

  function void build_phase( uvm_phase phase );
    bit ok;
    super.build_phase(phase);
    ok = uvm_config_db#(virtual bex_misc_if)::get(this, "", "misc_vif", mvif);
    if( !ok ) begin
      `uvm_fatal("NOVIF", "bex_misc_if がない")
    end
    dump_fd = 0;
    if( $value$plusargs("BEX_DUMP=%s",dump_name) ) begin
      dump_fd = $fopen(dump_name, "w");
      if( dump_fd==0 ) begin
        `uvm_error("SB_DUMP", $sformatf("%s を開けない", dump_name))
      end
    end
    clear_lat();
  endfunction

  function void clear_lat();
    min_lat = -1;
    max_lat = -1;
  endfunction

  function int pending();
    return q.size();
  endfunction

  // --------------------------------------------------------------------------
  function void write_in( bex_item it );
    q.push_back(it);
    n_in++;
  endfunction

  function void write_out( bex_item it );
    bex_item   e;
    bayer4x2_t x;
    longint    lat;
    int        r;
    int        v;
    bit        bad;
    n_out++;
    if( q.size()==0 ) begin
      `uvm_error("SB", $sformatf("入力していない転送が出力された cyc=%0d %s", it.cyc, it.convert2string()))
      n_mismatch++;
      return;
    end
    e   = q.pop_front();
    x   = bex_ref_model::xfer(e.cfg, e.data);
    bad = 1'b0;
    if( (it.data.sof!=x.sof)||(it.data.eol!=x.eol)||(it.data.eof!=x.eof) ) begin
      bad = 1'b1;
      if( n_mismatch<max_msg ) begin
        `uvm_error("SB", $sformatf("フラグが違う 期待 sof=%0d eol=%0d eof=%0d / 実際 sof=%0d eol=%0d eof=%0d (入力 cyc=%0d)",
                                    x.sof, x.eol, x.eof, it.data.sof, it.data.eol, it.data.eof, e.cyc))
      end
    end
    for( int y=0; y<2; y++ ) begin
      for( int xx=0; xx<4; xx++ ) begin
        v = bex_ref_model::pix(e.cfg, y, xx, int'(e.data.pix[y][xx]), r);
        if( cov!=null ) begin
          cov.sample_pix(bex_ref_model::site(e.cfg.phase, y, xx), r);
        end
        if( it.data.pix[y][xx]!=x.pix[y][xx] ) begin
          bad = 1'b1;
          if( n_mismatch<max_msg ) begin
            `uvm_error("SB", $sformatf("画素が違う pix[%0d][%0d] 入力=%0d 期待=%0d 実際=%0d (入力 cyc=%0d、%s)", y, xx,
                                        e.data.pix[y][xx], x.pix[y][xx], it.data.pix[y][xx], e.cyc, cfg_str(e.cfg)))
          end
        end
      end
    end
    lat = it.cyc-e.cyc;
    if( lat<MIN_LAT ) begin
      bad = 1'b1;
      `uvm_error("SB", $sformatf("レイテンシが %0d クロック(%0d より小さい)", lat, MIN_LAT))
    end
    if( (min_lat<0)||(lat<min_lat) ) begin
      min_lat = lat;
    end
    if( lat>max_lat ) begin
      max_lat = lat;
    end
    if( bad ) begin
      n_mismatch++;
    end else begin
      n_match++;
    end
    if( dump_fd!=0 ) begin
      dump_pair(e, it);
    end
  endfunction

  function string cfg_str( cfg_t c );
    return $sformatf("bypass=%0d phase=%0d blc=%0d/%0d/%0d/%0d gain=%04h/%04h/%04h/%04h", c.bypass, c.phase,
                      c.blc[0], c.blc[1], c.blc[2], c.blc[3], c.gain[0], c.gain[1], c.gain[2], c.gain[3]);
  endfunction

  // 1行: cfg <bypass> <phase> <blc×4> <gain×4> in <sof> <eol> <eof> <画素×8> out <sof> <eol> <eof> <画素×8>
  //   画素の順は pix[0][0..3]、pix[1][0..3]。値はすべて10進
  function void dump_pair( bex_item e, bex_item o );
    string s;
    s = $sformatf("cfg %0d %0d", e.cfg.bypass, e.cfg.phase);
    for( int i=0; i<4; i++ ) begin
      s = {s, $sformatf(" %0d", e.cfg.blc[i])};
    end
    for( int i=0; i<4; i++ ) begin
      s = {s, $sformatf(" %0d", e.cfg.gain[i])};
    end
    s = {s, $sformatf(" in %0d %0d %0d", e.data.sof, e.data.eol, e.data.eof)};
    for( int y=0; y<2; y++ ) begin
      for( int x=0; x<4; x++ ) begin
        s = {s, $sformatf(" %0d", e.data.pix[y][x])};
      end
    end
    s = {s, $sformatf(" out %0d %0d %0d", o.data.sof, o.data.eol, o.data.eof)};
    for( int y=0; y<2; y++ ) begin
      for( int x=0; x<4; x++ ) begin
        s = {s, $sformatf(" %0d", o.data.pix[y][x])};
      end
    end
    $fdisplay(dump_fd, "%s", s);
  endfunction

  // --------------------------------------------------------------------------
  // リセット: 出力されていない期待値を捨てる(最初のリセットは数えない)
  // --------------------------------------------------------------------------
  task run_phase( uvm_phase phase );
    bit first;
    first = 1'b1;
    forever begin
      @(negedge mvif.rst_n);
      if( first ) begin
        first = 1'b0;
        continue;
      end
      n_reset++;
      if( cov!=null ) begin
        if( q.size()>0 ) begin
          cov.sample_ev(bex_coverage::EV_RESET_INFLIGHT);
        end else begin
          cov.sample_ev(bex_coverage::EV_RESET_IDLE);
        end
      end
      `uvm_info("SB", $sformatf("リセット: 出力されていない %0d 転送を捨てる", q.size()), UVM_LOW)
      n_flushed += q.size();
      q.delete();
    end
  endtask

  function void check_phase( uvm_phase phase );
    if( q.size()!=0 ) begin
      `uvm_error("SB", $sformatf("出力されていない転送が %0d 個ある(最初 cyc=%0d %s)", q.size(), q[0].cyc, q[0].convert2string()))
    end
  endfunction

  function void report_phase( uvm_phase phase );
    if( dump_fd!=0 ) begin
      $fclose(dump_fd);
    end
    `uvm_info("SB", $sformatf("入力 %0d / 出力 %0d / 一致 %0d / 不一致 %0d / リセットで捨てた %0d(リセット %0d 回)/ レイテンシ %0d〜%0d",
                              n_in, n_out, n_match, n_mismatch, n_flushed, n_reset, min_lat, max_lat), UVM_NONE)
  endfunction
endclass

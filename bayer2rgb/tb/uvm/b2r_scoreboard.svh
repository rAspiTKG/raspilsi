// ============================================================================
// b2r_scoreboard : フレーム単位の比較
//   テストが expect_frame() で期待するフレームを順に登録する。
//   - AR/AW: 設定から作ったバーストの並び(アドレス・長さ・属性)と1つずつ比べる
//   - W    : 書き込みビートのバイトごとに、出力領域の内側か、重複していないか、
//            リファレンスモデルの値と一致するかを調べる
//   - 1フレーム分(幅×3×高さ バイト)書かれたらそのフレームは完了
//   ソフトリセットで中断したフレームは abort_frame() で取り下げる
//   +B2R_DUMP=<接頭辞> を付けると、完了したフレームの設定・入力・出力をファイルに出す
//   (tools/check_dumps.py でPythonモデルと照合する。バイト列は16進テキスト)
// ============================================================================
`uvm_analysis_imp_decl(_ar)
`uvm_analysis_imp_decl(_aw)
`uvm_analysis_imp_decl(_w)

class b2r_burst;
  bit [39:0] addr;
  bit [7:0]  len;
  int        reason;   // バーストの切れ目 0:16ビート 1:ラインの終わり 2:4KB境界
endclass

class b2r_sb_frame;
  string        name;
  b2r_frame_cfg cfg;
  b2r_image     img;
  int           w;
  int           h;
  byte unsigned exp[];
  byte unsigned got[];
  bit           seen[];
  int           n_bytes;
  int           n_err;
  b2r_burst     ar_plan[$];
  b2r_burst     aw_plan[$];
  int           ar_idx;
  int           aw_idx;
endclass

class b2r_scoreboard extends uvm_component;
  `uvm_component_utils(b2r_scoreboard)
  uvm_analysis_imp_ar #(b2r_axi_req, b2r_scoreboard)   ar_imp;
  uvm_analysis_imp_aw #(b2r_axi_req, b2r_scoreboard)   aw_imp;
  uvm_analysis_imp_w  #(b2r_axi_wbeat, b2r_scoreboard) w_imp;
  b2r_coverage  cov;
  b2r_sb_frame  q[$];
  int           n_pass;
  int           n_fail;
  int           n_abort;
  int           max_msg = 10;   // 1フレームで表示する不一致の数
  string        dump_prefix;
  int           dump_max_pix = 1<<20;

  function new( string name, uvm_component parent );
    super.new(name, parent);
    ar_imp = new("ar_imp", this);
    aw_imp = new("aw_imp", this);
    w_imp  = new("w_imp", this);
  endfunction

  function void build_phase( uvm_phase phase );
    super.build_phase(phase);
    if( !$value$plusargs("B2R_DUMP=%s",dump_prefix) ) begin
      dump_prefix = "";
    end
  endfunction

  // --------------------------------------------------------------------------
  // バーストの並び(RTLと同じ規則: min(16, ラインの残り, 4KB境界まで))
  // --------------------------------------------------------------------------
  function void make_plan( b2r_sb_frame f, bit is_wr, bit [39:0] base, int stride, int h, int bpl );
    bit [39:0] a;
    int        rem;
    int        n;
    int        b4k;
    b2r_burst  bt;
    for( int y=0; y<h; y++ ) begin
      a   = base+(40'(stride)*40'(y));
      rem = bpl;
      while( rem>0 ) begin
        bt        = new();
        b4k       = 256-int'(a[11:4]);
        n         = 16;
        bt.reason = 0;
        if( rem<=n ) begin
          n         = rem;
          bt.reason = 1;
        end
        if( b4k<n ) begin
          n         = b4k;
          bt.reason = 2;
        end
        bt.addr = a;
        bt.len  = 8'(n-1);
        if( is_wr ) begin
          f.aw_plan.push_back(bt);
        end else begin
          f.ar_plan.push_back(bt);
        end
        a   = a+40'(16*n);
        rem = rem-n;
      end
    end
  endfunction

  // --------------------------------------------------------------------------
  // 期待するフレームを登録する(リファレンスモデルを実行する)
  // --------------------------------------------------------------------------
  function void expect_frame( string name, b2r_frame_cfg c, b2r_image img );
    b2r_sb_frame  f;
    b2r_ref_model m;
    b2r_frame_cfg cc;
    cc = b2r_frame_cfg::type_id::create("cc");
    cc.copy_from(c);
    f      = new();
    f.name = name;
    f.cfg  = cc;
    f.img  = img;
    f.w    = cc.eff_w();
    f.h    = cc.eff_h();
    m      = new(cc);
    m.compute(img);
    f.exp  = m.out;
    f.got  = new[f.w*f.h*3];
    f.seen = new[f.w*f.h*3];
    if( !cc.tpg_en ) begin
      make_plan(f, 1'b0, cc.src_addr, int'(cc.src_stride), f.h, (f.w*2)/16);
    end
    make_plan(f, 1'b1, cc.dst_addr, int'(cc.dst_stride), f.h, ((f.w*3)+15)/16);
    q.push_back(f);
    if( cov!=null ) begin
      cov.sample_frame(cc);
    end
    `uvm_info("SB", $sformatf("%s: 期待フレームを登録 %s AR=%0d AW=%0d", name, cc.convert2string(), f.ar_plan.size(), f.aw_plan.size()), UVM_MEDIUM)
  endfunction

  // 中断したフレームを取り下げる(それまでに書かれたデータは比較済み)
  function void abort_frame();
    if( q.size()==0 ) begin
      return;
    end
    `uvm_info("SB", $sformatf("%s: 中断 (%0d/%0d バイト書き込み済み)", q[0].name, q[0].n_bytes, q[0].w*q[0].h*3), UVM_LOW)
    if( q[0].n_err!=0 ) begin
      n_fail++;
    end
    n_abort++;
    void'(q.pop_front());
  endfunction

  function int pending();
    return q.size();
  endfunction

  // --------------------------------------------------------------------------
  // AR / AW
  // --------------------------------------------------------------------------
  function void check_req( b2r_axi_req r, b2r_sb_frame f );
    b2r_burst  bt;
    string     ch;
    int        idx;
    int        nplan;
    bit [3:0]  cache;
    bit [2:0]  prot;
    bit [3:0]  qos;
    if( r.is_wr ) begin
      ch    = "AW";
      idx   = f.aw_idx;
      nplan = f.aw_plan.size();
      cache = f.cfg.awcache;
      prot  = f.cfg.awprot;
      qos   = f.cfg.awqos;
    end else begin
      ch    = "AR";
      idx   = f.ar_idx;
      nplan = f.ar_plan.size();
      cache = f.cfg.arcache;
      prot  = f.cfg.arprot;
      qos   = f.cfg.arqos;
    end
    if( idx>=nplan ) begin
      `uvm_error({"SB_", ch}, $sformatf("%s: 予定にない %s addr=%0h len=%0d", f.name, ch, r.addr, r.len))
      f.n_err++;
      return;
    end
    if( r.is_wr ) begin
      bt = f.aw_plan[idx];
      f.aw_idx++;
    end else begin
      bt = f.ar_plan[idx];
      f.ar_idx++;
    end
    if( (r.addr!=bt.addr)||(r.len!=bt.len) ) begin
      `uvm_error({"SB_", ch}, $sformatf("%s: %s[%0d] が違う 期待 addr=%0h len=%0d / 実際 addr=%0h len=%0d", f.name, ch, idx,
                                        bt.addr, bt.len, r.addr, r.len))
      f.n_err++;
    end
    if( (r.cache!=cache)||(r.prot!=prot)||(r.qos!=qos) ) begin
      `uvm_error({"SB_", ch}, $sformatf("%s: %s の属性が違う cache=%0h/%0h prot=%0h/%0h qos=%0h/%0h", f.name, ch,
                                        r.cache, cache, r.prot, prot, r.qos, qos))
      f.n_err++;
    end
    if( cov!=null ) begin
      cov.sample_burst(r.is_wr, int'(bt.len)+1, bt.reason);
    end
  endfunction

  function void write_ar( b2r_axi_req r );
    if( q.size()==0 ) begin
      `uvm_error("SB_AR", $sformatf("期待するフレームがないのに AR が出た addr=%0h", r.addr))
      return;
    end
    if( q[0].cfg.tpg_en ) begin
      `uvm_error("SB_AR", $sformatf("%s: テストパターンなのに AR が出た addr=%0h", q[0].name, r.addr))
      q[0].n_err++;
      return;
    end
    check_req(r, q[0]);
  endfunction

  function void write_aw( b2r_axi_req r );
    if( q.size()==0 ) begin
      `uvm_error("SB_AW", $sformatf("期待するフレームがないのに AW が出た addr=%0h", r.addr))
      return;
    end
    check_req(r, q[0]);
  endfunction

  // --------------------------------------------------------------------------
  // W
  // --------------------------------------------------------------------------
  function void write_w( b2r_axi_wbeat b );
    b2r_sb_frame f;
    longint      off;
    longint      stride;
    longint      y;
    longint      xb;
    int          idx;
    int          lb;
    string       chn;
    if( q.size()==0 ) begin
      `uvm_error("SB_W", $sformatf("期待するフレームがないのに書き込みがあった addr=%0h", b.addr))
      return;
    end
    f      = q[0];
    lb     = f.w*3;
    stride = longint'(f.cfg.dst_stride);
    if( stride==0 ) begin
      `uvm_fatal("SB_W", "DST_STRIDE が0")
    end
    // WSTRBは下位から連続していること(ラインの最後の端数ビートだけが部分書き込み)
    if( (b.strb&(b.strb+16'd1))!=16'h0000 ) begin
      `uvm_error("SB_W", $sformatf("%s: WSTRB が下位から連続していない addr=%0h strb=%04h", f.name, b.addr, b.strb))
      f.n_err++;
    end
    for( int i=0; i<16; i++ ) begin
      if( !b.strb[i] ) begin
        continue;
      end
      off = longint'(b.addr+40'(i))-longint'(f.cfg.dst_addr);
      if( off<0 ) begin
        y  = -1;
        xb = -1;
      end else begin
        y  = off/stride;
        xb = off%stride;
      end
      if( (off<0)||(y>=f.h)||(xb>=lb) ) begin
        if( f.n_err<max_msg ) begin
          `uvm_error("SB_W", $sformatf("%s: 出力領域の外に書いた addr=%0h", f.name, b.addr+40'(i)))
        end
        f.n_err++;
        continue;
      end
      idx = int'((y*lb)+xb);
      if( f.seen[idx] ) begin
        if( f.n_err<max_msg ) begin
          `uvm_error("SB_W", $sformatf("%s: 同じバイトに2回書いた y=%0d byte=%0d", f.name, y, xb))
        end
        f.n_err++;
      end
      f.seen[idx] = 1'b1;
      f.got[idx]  = b.data[(8*i)+:8];
      f.n_bytes++;
      if( f.got[idx]!=f.exp[idx] ) begin
        if( f.n_err<max_msg ) begin
          case( xb%3 )
            0 : begin
              chn = "R";
            end
            1 : begin
              chn = "G";
            end
            default : begin
              chn = "B";
            end
          endcase
          `uvm_error("SB_W", $sformatf("%s: 不一致 y=%0d x=%0d %s 期待=%0d 実際=%0d", f.name, y, xb/3, chn, f.exp[idx], f.got[idx]))
        end
        f.n_err++;
      end
    end
    if( f.n_bytes==(lb*f.h) ) begin
      finish_frame(f);
    end
  endfunction

  function void finish_frame( b2r_sb_frame f );
    if( f.ar_idx!=f.ar_plan.size() ) begin
      `uvm_error("SB_AR", $sformatf("%s: AR の数が足りない %0d/%0d", f.name, f.ar_idx, f.ar_plan.size()))
      f.n_err++;
    end
    if( f.aw_idx!=f.aw_plan.size() ) begin
      `uvm_error("SB_AW", $sformatf("%s: AW の数が足りない %0d/%0d", f.name, f.aw_idx, f.aw_plan.size()))
      f.n_err++;
    end
    if( f.n_err==0 ) begin
      n_pass++;
      `uvm_info("SB", $sformatf("%s: 一致 (%0dx%0d)", f.name, f.w, f.h), UVM_LOW)
    end else begin
      n_fail++;
      `uvm_error("SB", $sformatf("%s: 不一致 %0d 件", f.name, f.n_err))
    end
    if( dump_prefix!="" ) begin
      dump_frame(f);
    end
    void'(q.pop_front());
  endfunction

  // --------------------------------------------------------------------------
  // ファイル出力(Pythonモデルとの照合用)。バイト列は16進テキスト(1行32バイト)
  // --------------------------------------------------------------------------
  function void dump_hex( string fn, byte unsigned d[] );
    int fd;
    fd = $fopen(fn, "w");
    if( fd==0 ) begin
      `uvm_error("SB_DUMP", $sformatf("%s を開けない", fn))
      return;
    end
    for( int i=0; i<d.size(); i++ ) begin
      $fwrite(fd, "%02x", d[i]);
      if( (i%32)==31 ) begin
        $fwrite(fd, "\n");
      end
    end
    $fwrite(fd, "\n");
    $fclose(fd);
  endfunction

  function void dump_frame( b2r_sb_frame f );
    int           fd;
    string        base;
    byte unsigned raw[];
    if( (f.w*f.h)>dump_max_pix ) begin
      return;
    end
    base = $sformatf("%s_%s", dump_prefix, f.name);
    fd = $fopen({base, ".cfg.json"}, "w");
    if( fd==0 ) begin
      `uvm_error("SB_DUMP", $sformatf("%s.cfg.json を開けない", base))
      return;
    end
    $fwrite(fd, "{\n");
    $fwrite(fd, "  \"width\": %0d, \"height\": %0d, \"phase\": %0d,\n", f.cfg.width, f.cfg.height, f.cfg.phase);
    $fwrite(fd, "  \"blc_en\": %0d, \"wb_en\": %0d, \"fcs_en\": %0d, \"gamma_en\": %0d,\n", f.cfg.blc_en, f.cfg.wb_en, f.cfg.fcs_en, f.cfg.gamma_en);
    $fwrite(fd, "  \"bypass\": %0d, \"tpg_en\": %0d, \"tpg_sel\": %0d, \"tpg_color\": %0d,\n", f.cfg.bypass, f.cfg.tpg_en, f.cfg.tpg_sel, f.cfg.tpg_color);
    $fwrite(fd, "  \"blc\": [%0d, %0d, %0d, %0d],\n", f.cfg.blc[0], f.cfg.blc[1], f.cfg.blc[2], f.cfg.blc[3]);
    $fwrite(fd, "  \"wbg\": [%0d, %0d, %0d, %0d],\n", f.cfg.wbg[0], f.cfg.wbg[1], f.cfg.wbg[2], f.cfg.wbg[3]);
    $fwrite(fd, "  \"fcs_th\": %0d, \"fcs_gain\": %0d,\n", f.cfg.fcs_th, f.cfg.fcs_gain);
    $fwrite(fd, "  \"gm_knot\": [");
    for( int i=0; i<37; i++ ) begin
      if( i==36 ) begin
        $fwrite(fd, "%0d", f.cfg.gm_knot[i]);
      end else begin
        $fwrite(fd, "%0d, ", f.cfg.gm_knot[i]);
      end
    end
    $fwrite(fd, "]\n}\n");
    $fclose(fd);
    if( !f.cfg.tpg_en ) begin
      raw = new[f.w*f.h*2];
      for( int i=0; i<(f.w*f.h); i++ ) begin
        raw[2*i]     = f.img.px[i][7:0];
        raw[(2*i)+1] = f.img.px[i][15:8];
      end
      dump_hex({base, ".in.hex"}, raw);
    end
    dump_hex({base, ".dut.hex"}, f.got);
    dump_hex({base, ".ref.hex"}, f.exp);
  endfunction

  // --------------------------------------------------------------------------
  function void check_phase( uvm_phase phase );
    foreach( q[i] ) begin
      `uvm_error("SB", $sformatf("%s: 完了していない (%0d/%0d バイト)", q[i].name, q[i].n_bytes, q[i].w*q[i].h*3))
    end
  endfunction

  function void report_phase( uvm_phase phase );
    `uvm_info("SB", $sformatf("フレーム 一致=%0d 不一致=%0d 中断=%0d", n_pass, n_fail, n_abort), UVM_NONE)
  endfunction
endclass

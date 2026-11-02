// ============================================================================
// bex_coverage : 機能カバレッジ
//   cg_cfg  : 設定(Bayer の並び × bypass、黒レベル・ゲインの分類。チャネルごとに数える)
//   cg_pix  : 画素の結果(色の位置 × 結果の分類: bypass / 黒レベル以下 / 飽和 / ふつう)
//   cg_xfer : 転送のフラグ(sof / eol / eof、1転送だけのフレーム)
//   cg_hs   : ハンドシェイクとリセットのイベント
//
//   covergroup とは別に、同じビンを名前つきの表でも数える。テストの終わりに
//   "[COVBIN] <ビン名> <回数>" を全ビンについて出し、tools/merge_cov.py で
//   回帰試験全体の結果にまとめる(シミュレータによらずにまとめるため)。
// ============================================================================
class bex_coverage extends uvm_component;
  `uvm_component_utils(bex_coverage)

  // ハンドシェイクとリセットのイベント
  typedef enum int {
    EV_IN_B2B         = 0,    // 入力: 続けて転送した
    EV_IN_GAP         = 1,    // 入力: 間をあけて転送した
    EV_IN_STALL       = 2,    // 入力: vld=1 のとき o_busy=1(DUT が止めた)
    EV_SKID_FULL      = 3,    // o_busy=1(スキッドが埋まった)
    EV_OUT_B2B        = 4,    // 出力: 続けて転送した
    EV_OUT_GAP        = 5,    // 出力: 間をあけて転送した
    EV_OUT_STALL      = 6,    // 出力: o_vld=1 のとき i_busy=1
    EV_BUSY_IDLE      = 7,    // 出力: o_vld=0 のとき i_busy=1
    EV_CFG_AT_XFER    = 8,    // 設定を変えたクロックに入力の転送があった
    EV_RESET_INFLIGHT = 9,    // コアの中にデータがあるときにリセットした
    EV_RESET_IDLE     = 10    // コアが空のときにリセットした
  } ev_e;

  localparam int N_EV = 11;

  // 標本
  int phase;
  int bypass;
  int blc_cls;
  int gain_cls;
  int site;
  int res;
  int flag;
  int ev;

  // 名前つきのビンの表
  int    hits[string];
  string bin_names[$];

  covergroup cg_cfg;
    cp_phase  : coverpoint phase {
      bins rggb = {0};
      bins grbg = {1};
      bins gbrg = {2};
      bins bggr = {3};
    }
    cp_bypass : coverpoint bypass {
      bins off = {0};
      bins on  = {1};
    }
    x_phase_bypass : cross cp_phase, cp_bypass;
  endgroup

  covergroup cg_ch;
    cp_blc  : coverpoint blc_cls {
      bins zero = {0};
      bins mid  = {1};
      bins max  = {2};
    }
    cp_gain : coverpoint gain_cls {
      bins zero = {0};
      bins lt1  = {1};
      bins one  = {2};
      bins gt1  = {3};
      bins max  = {4};
    }
  endgroup

  covergroup cg_pix;
    cp_site : coverpoint site {
      bins r  = {0};
      bins gr = {1};
      bins gb = {2};
      bins b  = {3};
    }
    cp_res  : coverpoint res {
      bins bypass = {0};
      bins clamp  = {1};
      bins sat    = {2};
      bins normal = {3};
    }
    x_site_res : cross cp_site, cp_res;
  endgroup

  covergroup cg_xfer;
    cp_flag : coverpoint flag {
      bins sof    = {0};
      bins eol    = {1};
      bins eof    = {2};
      bins single = {3};
    }
  endgroup

  covergroup cg_hs;
    cp_ev : coverpoint ev {
      bins in_b2b         = {0};
      bins in_gap         = {1};
      bins in_stall       = {2};
      bins skid_full      = {3};
      bins out_b2b        = {4};
      bins out_gap        = {5};
      bins out_stall      = {6};
      bins busy_idle      = {7};
      bins cfg_at_xfer    = {8};
      bins reset_inflight = {9};
      bins reset_idle     = {10};
    }
  endgroup

  // --------------------------------------------------------------------------
  // ビンの名前(covergroup のビンと同じ名前にする)
  // --------------------------------------------------------------------------
  function string f_ph( int v );
    case( v )
      0 : begin
        return "rggb";
      end
      1 : begin
        return "grbg";
      end
      2 : begin
        return "gbrg";
      end
      default : begin
        return "bggr";
      end
    endcase
  endfunction

  function string f_oo( int v );
    if( v!=0 ) begin
      return "on";
    end else begin
      return "off";
    end
  endfunction

  function string f_blc( int v );
    case( v )
      0 : begin
        return "zero";
      end
      1 : begin
        return "mid";
      end
      default : begin
        return "max";
      end
    endcase
  endfunction

  function string f_gain( int v );
    case( v )
      0 : begin
        return "zero";
      end
      1 : begin
        return "lt1";
      end
      2 : begin
        return "one";
      end
      3 : begin
        return "gt1";
      end
      default : begin
        return "max";
      end
    endcase
  endfunction

  function string f_site( int v );
    case( v )
      0 : begin
        return "r";
      end
      1 : begin
        return "gr";
      end
      2 : begin
        return "gb";
      end
      default : begin
        return "b";
      end
    endcase
  endfunction

  function string f_res( int v );
    case( v )
      0 : begin
        return "bypass";
      end
      1 : begin
        return "clamp";
      end
      2 : begin
        return "sat";
      end
      default : begin
        return "normal";
      end
    endcase
  endfunction

  function string f_flag( int v );
    case( v )
      0 : begin
        return "sof";
      end
      1 : begin
        return "eol";
      end
      2 : begin
        return "eof";
      end
      default : begin
        return "single";
      end
    endcase
  endfunction

  function string f_ev( int v );
    case( v )
      EV_IN_B2B : begin
        return "in_b2b";
      end
      EV_IN_GAP : begin
        return "in_gap";
      end
      EV_IN_STALL : begin
        return "in_stall";
      end
      EV_SKID_FULL : begin
        return "skid_full";
      end
      EV_OUT_B2B : begin
        return "out_b2b";
      end
      EV_OUT_GAP : begin
        return "out_gap";
      end
      EV_OUT_STALL : begin
        return "out_stall";
      end
      EV_BUSY_IDLE : begin
        return "busy_idle";
      end
      EV_CFG_AT_XFER : begin
        return "cfg_at_xfer";
      end
      EV_RESET_INFLIGHT : begin
        return "reset_inflight";
      end
      default : begin
        return "reset_idle";
      end
    endcase
  endfunction

  function void add_bin( string n );
    hits[n] = 0;
    bin_names.push_back(n);
  endfunction

  function void hit( string n );
    if( !hits.exists(n) ) begin
      `uvm_error("COV", $sformatf("登録していないビン %s", n))
      return;
    end
    hits[n] = hits[n]+1;
  endfunction

  // --------------------------------------------------------------------------
  function new( string name, uvm_component parent );
    super.new(name, parent);
    cg_cfg  = new();
    cg_ch   = new();
    cg_pix  = new();
    cg_xfer = new();
    cg_hs   = new();
    for( int p=0; p<4; p++ ) begin
      add_bin({"cg_cfg.cp_phase.", f_ph(p)});
    end
    for( int b=0; b<2; b++ ) begin
      add_bin({"cg_cfg.cp_bypass.", f_oo(b)});
    end
    for( int p=0; p<4; p++ ) begin
      for( int b=0; b<2; b++ ) begin
        add_bin({"cg_cfg.x_phase_bypass.", f_ph(p), "_", f_oo(b)});
      end
    end
    for( int v=0; v<3; v++ ) begin
      add_bin({"cg_ch.cp_blc.", f_blc(v)});
    end
    for( int v=0; v<5; v++ ) begin
      add_bin({"cg_ch.cp_gain.", f_gain(v)});
    end
    for( int s=0; s<4; s++ ) begin
      for( int r=0; r<4; r++ ) begin
        add_bin({"cg_pix.x_site_res.", f_site(s), "_", f_res(r)});
      end
    end
    for( int v=0; v<4; v++ ) begin
      add_bin({"cg_xfer.cp_flag.", f_flag(v)});
    end
    for( int e=0; e<N_EV; e++ ) begin
      add_bin({"cg_hs.cp_ev.", f_ev(e)});
    end
  endfunction

  // --------------------------------------------------------------------------
  // 標本を取る
  // --------------------------------------------------------------------------
  // 設定(設定を変えたとき)
  function void sample_cfg( cfg_t c );
    phase  = int'(c.phase);
    bypass = int'(c.bypass);
    cg_cfg.sample();
    hit({"cg_cfg.cp_phase.", f_ph(phase)});
    hit({"cg_cfg.cp_bypass.", f_oo(bypass)});
    hit({"cg_cfg.x_phase_bypass.", f_ph(phase), "_", f_oo(bypass)});
    for( int i=0; i<4; i++ ) begin
      if( c.blc[i]==14'd0 ) begin
        blc_cls = 0;
      end else if( c.blc[i]==14'h3FFF ) begin
        blc_cls = 2;
      end else begin
        blc_cls = 1;
      end
      if( c.gain[i]==16'h0000 ) begin
        gain_cls = 0;
      end else if( c.gain[i]<16'h1000 ) begin
        gain_cls = 1;
      end else if( c.gain[i]==16'h1000 ) begin
        gain_cls = 2;
      end else if( c.gain[i]==16'hFFFF ) begin
        gain_cls = 4;
      end else begin
        gain_cls = 3;
      end
      cg_ch.sample();
      hit({"cg_ch.cp_blc.", f_blc(blc_cls)});
      hit({"cg_ch.cp_gain.", f_gain(gain_cls)});
    end
  endfunction

  // 画素の結果(スコアボードが比べたとき)
  function void sample_pix( int s, int r );
    site = s;
    res  = r;
    cg_pix.sample();
    hit({"cg_pix.x_site_res.", f_site(s), "_", f_res(r)});
  endfunction

  // 転送のフラグ(出力側)
  function void sample_xfer( bayer4x2_t d );
    if( d.sof ) begin
      flag = 0;
      cg_xfer.sample();
      hit("cg_xfer.cp_flag.sof");
    end
    if( d.eol ) begin
      flag = 1;
      cg_xfer.sample();
      hit("cg_xfer.cp_flag.eol");
    end
    if( d.eof ) begin
      flag = 2;
      cg_xfer.sample();
      hit("cg_xfer.cp_flag.eof");
    end
    if( d.sof&&d.eol&&d.eof ) begin
      flag = 3;
      cg_xfer.sample();
      hit("cg_xfer.cp_flag.single");
    end
  endfunction

  function void sample_ev( ev_e e );
    ev = int'(e);
    cg_hs.sample();
    hit({"cg_hs.cp_ev.", f_ev(ev)});
  endfunction

  function void report_phase( uvm_phase phase );
    int n_hit;
    n_hit = 0;
    foreach( bin_names[i] ) begin
      if( hits[bin_names[i]]>0 ) begin
        n_hit++;
      end
    end
    `uvm_info("COV", $sformatf("機能カバレッジ cfg=%0.1f%% ch=%0.1f%% pix=%0.1f%% xfer=%0.1f%% hs=%0.1f%% (このテストで当たったビン %0d/%0d)",
                              cg_cfg.get_coverage(), cg_ch.get_coverage(), cg_pix.get_coverage(), cg_xfer.get_coverage(),
                              cg_hs.get_coverage(), n_hit, bin_names.size()), UVM_NONE)
    foreach( bin_names[i] ) begin
      `uvm_info("COVBIN", $sformatf("%s %0d", bin_names[i], hits[bin_names[i]]), UVM_NONE)
    end
  endfunction
endclass

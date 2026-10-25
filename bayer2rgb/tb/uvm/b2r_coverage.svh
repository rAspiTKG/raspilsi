// ============================================================================
// b2r_coverage : 機能カバレッジ
//   cg_frame : フレームの設定(色の並び・機能の組み合わせ・テストパターン・サイズの分類)
//   cg_burst : AXIのバースト(読み/書き × 長さ × 切れ目の理由)
//   cg_event : 制御のイベント(エラー応答、ソフトリセット、自動再開、設定の保持など)
//
//   covergroup とは別に、同じビンを名前つきの表でも数える。テストの終わりに
//   "[COVBIN] <ビン名> <回数>" を全ビンについて出し、tools/merge_cov.py で
//   回帰試験全体の結果にまとめる(シミュレータによらずにまとめるため)。
// ============================================================================
class b2r_coverage extends uvm_component;
  `uvm_component_utils(b2r_coverage)

  // イベントの番号
  typedef enum int {
    EV_RD_ERR       = 0,   // 読み出しエラー応答
    EV_WR_ERR       = 1,   // 書き込みエラー応答
    EV_SRST_IDLE    = 2,   // 停止中のソフトリセット
    EV_SRST_BUSY    = 3,   // フレーム処理中のソフトリセット
    EV_AUTO_RESTART = 4,   // 自動再開で次のフレームが始まった
    EV_HOLD_CFG     = 5,   // REG_UPDATE=0 で前の設定のまま始まった
    EV_IRQ_PIN      = 6,   // 割り込み出力が立った
    EV_QUEUED_START = 7,   // 処理中に書いたSTARTが完了後に実行された
    EV_START_SRST   = 8    // STARTとSW_RESETを同時に書いた
  } ev_e;

  localparam int N_EV = 9;

  // 標本
  int phase;
  int blc_en;
  int wb_en;
  int fcs_en;
  int gamma_en;
  int bypass;
  int tpg_mode;
  int w_class;
  int h_class;
  int is_wr;
  int blen;
  int reason;
  int ev;

  // 名前つきのビンの表
  int    hits[string];
  string bin_names[$];

  covergroup cg_frame;
    cp_phase  : coverpoint phase {
      bins rggb = {0};
      bins grbg = {1};
      bins gbrg = {2};
      bins bggr = {3};
    }
    cp_blc    : coverpoint blc_en {
      bins off = {0};
      bins on  = {1};
    }
    cp_wb     : coverpoint wb_en {
      bins off = {0};
      bins on  = {1};
    }
    cp_fcs    : coverpoint fcs_en {
      bins off = {0};
      bins on  = {1};
    }
    cp_gamma  : coverpoint gamma_en {
      bins off = {0};
      bins on  = {1};
    }
    cp_bypass : coverpoint bypass {
      bins off = {0};
      bins on  = {1};
    }
    cp_tpg    : coverpoint tpg_mode {
      bins off     = {0};
      bins bars    = {1};
      bins ramp    = {2};
      bins chk     = {3};
      bins solid   = {4};
    }
    cp_w      : coverpoint w_class {
      bins below_min = {0};   // 16未満(16にする)
      bins min       = {1};   // 16
      bins mod16_8   = {2};   // 16で割って8余る
      bins mod16_0   = {3};   // 16の倍数
      bins max       = {4};   // 3840
      bins above_max = {5};   // 3840より大きい(3840にする)
      bins unaligned = {6};   // 8の倍数でない(切り捨てる)
    }
    cp_h      : coverpoint h_class {
      bins below_min = {0};
      bins min       = {1};
      bins even      = {2};
      bins odd       = {3};   // 奇数(切り捨てる)
      bins max       = {4};
      bins above_max = {5};
    }
    x_phase_func : cross cp_phase, cp_fcs, cp_bypass;
    x_func       : cross cp_blc, cp_wb, cp_fcs, cp_gamma;
  endgroup

  covergroup cg_burst;
    cp_dir    : coverpoint is_wr {
      bins rd = {0};
      bins wr = {1};
    }
    cp_len    : coverpoint blen {
      bins one  = {1};
      bins mid  = {[2:15]};
      bins full = {16};
    }
    cp_reason : coverpoint reason {
      bins max16    = {0};
      bins line_end = {1};
      bins b4k      = {2};
    }
    x_dir_reason : cross cp_dir, cp_reason;
    x_dir_len    : cross cp_dir, cp_len;
  endgroup

  covergroup cg_event;
    cp_ev : coverpoint ev {
      bins rd_err       = {EV_RD_ERR};
      bins wr_err       = {EV_WR_ERR};
      bins srst_idle    = {EV_SRST_IDLE};
      bins srst_busy    = {EV_SRST_BUSY};
      bins auto_restart = {EV_AUTO_RESTART};
      bins hold_cfg     = {EV_HOLD_CFG};
      bins irq_pin      = {EV_IRQ_PIN};
      bins queued_start = {EV_QUEUED_START};
      bins start_srst   = {EV_START_SRST};
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

  function string f_tpg( int v );
    case( v )
      0 : begin
        return "off";
      end
      1 : begin
        return "bars";
      end
      2 : begin
        return "ramp";
      end
      3 : begin
        return "chk";
      end
      default : begin
        return "solid";
      end
    endcase
  endfunction

  function string f_w( int v );
    case( v )
      0 : begin
        return "below_min";
      end
      1 : begin
        return "min";
      end
      2 : begin
        return "mod16_8";
      end
      3 : begin
        return "mod16_0";
      end
      4 : begin
        return "max";
      end
      5 : begin
        return "above_max";
      end
      default : begin
        return "unaligned";
      end
    endcase
  endfunction

  function string f_h( int v );
    case( v )
      0 : begin
        return "below_min";
      end
      1 : begin
        return "min";
      end
      2 : begin
        return "even";
      end
      3 : begin
        return "odd";
      end
      4 : begin
        return "max";
      end
      default : begin
        return "above_max";
      end
    endcase
  endfunction

  function string f_dir( int v );
    if( v!=0 ) begin
      return "wr";
    end else begin
      return "rd";
    end
  endfunction

  // バースト長の分類: 0:1ビート 1:2〜15 2:16
  function int f_lcls( int len );
    if( len==1 ) begin
      return 0;
    end else if( len==16 ) begin
      return 2;
    end else begin
      return 1;
    end
  endfunction

  function string f_len( int c );
    case( c )
      0 : begin
        return "one";
      end
      1 : begin
        return "mid";
      end
      default : begin
        return "full";
      end
    endcase
  endfunction

  function string f_rsn( int v );
    case( v )
      0 : begin
        return "max16";
      end
      1 : begin
        return "line_end";
      end
      default : begin
        return "b4k";
      end
    endcase
  endfunction

  function string f_ev( int v );
    case( v )
      EV_RD_ERR : begin
        return "rd_err";
      end
      EV_WR_ERR : begin
        return "wr_err";
      end
      EV_SRST_IDLE : begin
        return "srst_idle";
      end
      EV_SRST_BUSY : begin
        return "srst_busy";
      end
      EV_AUTO_RESTART : begin
        return "auto_restart";
      end
      EV_HOLD_CFG : begin
        return "hold_cfg";
      end
      EV_IRQ_PIN : begin
        return "irq_pin";
      end
      EV_QUEUED_START : begin
        return "queued_start";
      end
      default : begin
        return "start_srst";
      end
    endcase
  endfunction

  function string f_xpf( int ph, int fcs, int byp );
    return $sformatf("cg_frame.x_phase_func.%s_fcs_%s_byp_%s", f_ph(ph), f_oo(fcs), f_oo(byp));
  endfunction

  function string f_xfn( int b, int w, int f, int g );
    return $sformatf("cg_frame.x_func.blc_%s_wb_%s_fcs_%s_gm_%s", f_oo(b), f_oo(w), f_oo(f), f_oo(g));
  endfunction

  function void add_bin( string name );
    bin_names.push_back(name);
    hits[name] = 0;
  endfunction

  function void hit( string name );
    if( !hits.exists(name) ) begin
      `uvm_error("COV", $sformatf("登録していないビン %s", name))
    end else begin
      hits[name] = hits[name]+1;
    end
  endfunction

  // --------------------------------------------------------------------------
  function new( string name, uvm_component parent );
    super.new(name, parent);
    cg_frame = new();
    cg_burst = new();
    cg_event = new();
    for( int i=0; i<4; i++ ) begin
      add_bin({"cg_frame.cp_phase.", f_ph(i)});
    end
    for( int i=0; i<2; i++ ) begin
      add_bin({"cg_frame.cp_blc.", f_oo(i)});
      add_bin({"cg_frame.cp_wb.", f_oo(i)});
      add_bin({"cg_frame.cp_fcs.", f_oo(i)});
      add_bin({"cg_frame.cp_gamma.", f_oo(i)});
      add_bin({"cg_frame.cp_bypass.", f_oo(i)});
    end
    for( int i=0; i<5; i++ ) begin
      add_bin({"cg_frame.cp_tpg.", f_tpg(i)});
    end
    for( int i=0; i<7; i++ ) begin
      add_bin({"cg_frame.cp_w.", f_w(i)});
    end
    for( int i=0; i<6; i++ ) begin
      add_bin({"cg_frame.cp_h.", f_h(i)});
    end
    for( int p=0; p<4; p++ ) begin
      for( int f=0; f<2; f++ ) begin
        for( int b=0; b<2; b++ ) begin
          add_bin(f_xpf(p, f, b));
        end
      end
    end
    for( int k=0; k<16; k++ ) begin
      add_bin(f_xfn((k>>3)&1, (k>>2)&1, (k>>1)&1, k&1));
    end
    for( int d=0; d<2; d++ ) begin
      add_bin({"cg_burst.cp_dir.", f_dir(d)});
    end
    for( int c=0; c<3; c++ ) begin
      add_bin({"cg_burst.cp_len.", f_len(c)});
      add_bin({"cg_burst.cp_reason.", f_rsn(c)});
    end
    for( int d=0; d<2; d++ ) begin
      for( int c=0; c<3; c++ ) begin
        add_bin({"cg_burst.x_dir_reason.", f_dir(d), "_", f_rsn(c)});
        add_bin({"cg_burst.x_dir_len.", f_dir(d), "_", f_len(c)});
      end
    end
    for( int e=0; e<N_EV; e++ ) begin
      add_bin({"cg_event.cp_ev.", f_ev(e)});
    end
  endfunction

  function void sample_frame( b2r_frame_cfg c );
    phase    = c.phase;
    blc_en   = c.blc_en;
    wb_en    = c.wb_en;
    fcs_en   = c.fcs_en;
    gamma_en = c.gamma_en;
    bypass   = c.bypass;
    tpg_mode = c.tpg_en ? (int'(c.tpg_sel)+1) : 0;
    if( c.width<16 ) begin
      w_class = 0;
    end else if( c.width==16 ) begin
      w_class = 1;
    end else if( c.width>3840 ) begin
      w_class = 5;
    end else if( c.width==3840 ) begin
      w_class = 4;
    end else if( (c.width%8)!=0 ) begin
      w_class = 6;
    end else if( (c.width%16)==8 ) begin
      w_class = 2;
    end else begin
      w_class = 3;
    end
    if( c.height<16 ) begin
      h_class = 0;
    end else if( c.height==16 ) begin
      h_class = 1;
    end else if( c.height>2160 ) begin
      h_class = 5;
    end else if( c.height==2160 ) begin
      h_class = 4;
    end else if( (c.height%2)!=0 ) begin
      h_class = 3;
    end else begin
      h_class = 2;
    end
    cg_frame.sample();
    hit({"cg_frame.cp_phase.", f_ph(phase)});
    hit({"cg_frame.cp_blc.", f_oo(blc_en)});
    hit({"cg_frame.cp_wb.", f_oo(wb_en)});
    hit({"cg_frame.cp_fcs.", f_oo(fcs_en)});
    hit({"cg_frame.cp_gamma.", f_oo(gamma_en)});
    hit({"cg_frame.cp_bypass.", f_oo(bypass)});
    hit({"cg_frame.cp_tpg.", f_tpg(tpg_mode)});
    hit({"cg_frame.cp_w.", f_w(w_class)});
    hit({"cg_frame.cp_h.", f_h(h_class)});
    hit(f_xpf(phase, fcs_en, bypass));
    hit(f_xfn(blc_en, wb_en, fcs_en, gamma_en));
  endfunction

  function void sample_burst( bit wr, int len, int rsn );
    is_wr  = wr;
    blen   = len;
    reason = rsn;
    cg_burst.sample();
    hit({"cg_burst.cp_dir.", f_dir(is_wr)});
    hit({"cg_burst.cp_len.", f_len(f_lcls(blen))});
    hit({"cg_burst.cp_reason.", f_rsn(reason)});
    hit({"cg_burst.x_dir_reason.", f_dir(is_wr), "_", f_rsn(reason)});
    hit({"cg_burst.x_dir_len.", f_dir(is_wr), "_", f_len(f_lcls(blen))});
  endfunction

  function void sample_event( ev_e e );
    ev = int'(e);
    cg_event.sample();
    hit({"cg_event.cp_ev.", f_ev(ev)});
  endfunction

  function void report_phase( uvm_phase phase );
    int n_hit;
    n_hit = 0;
    foreach( bin_names[i] ) begin
      if( hits[bin_names[i]]>0 ) begin
        n_hit++;
      end
    end
    `uvm_info("COV", $sformatf("機能カバレッジ frame=%0.1f%% burst=%0.1f%% event=%0.1f%% (このテストで当たったビン %0d/%0d)",
                              cg_frame.get_coverage(), cg_burst.get_coverage(), cg_event.get_coverage(),
                              n_hit, bin_names.size()), UVM_NONE)
    foreach( bin_names[i] ) begin
      `uvm_info("COVBIN", $sformatf("%s %0d", bin_names[i], hits[bin_names[i]]), UVM_NONE)
    end
  endfunction
endclass

//=============================================================================
// usr_items.svh
//-----------------------------------------------------------------------------
//  ユーザ側の sequence item。
//    cmd_item : 書き込み / 読み出しコマンド 1 本 (driver への操作、monitor の出力を兼ねる)
//    loc_item : ローカルポートの操作 (連続したワードの書き込み / 読み出し。両方あれば同時に)
//    mem_item : monitor が出す、ローカルポートのアクセス 1 回分
//
//  cmd_item のランダム化は「単純な範囲制約」だけにして、そこから決まる値
//  (内部メモリの範囲やスレーブの窓に収まる位置) は post_randomize() で計算している。
//  範囲は randomize() の前に set_region() で与える。
//=============================================================================

//=============================================================================
// コマンド
//=============================================================================
class cmd_item extends uvm_sequence_item;

  //---------------------------------------------------------------------------
  // ランダム化する項目
  //---------------------------------------------------------------------------
  rand int unsigned     r_len_sel;      // 0: 1 ワード / 1: 最大 / 2: 2 ワード / 他: r_len
  rand int unsigned     r_len;
  rand int unsigned     r_incr_sel;     // 0,1: 固定アドレス / 他: インクリメント
  rand int unsigned     r_mpos_sel;     // 0: 範囲の先頭 / 1: 範囲の末尾ちょうど / 他: r_mpos
  rand int unsigned     r_mpos;
  rand int unsigned     r_apos_sel;     // 0: 窓の先頭 / 1: 窓の末尾ちょうど / 他: r_apos
  rand int unsigned     r_apos;
  rand int unsigned     r_strb_sel;     // 0: 全て 0 / 1,2,3: 全て 1 / 他: r_strb
  rand bit [STRB_W-1:0] r_strb;
  rand bit [2:0]        r_prot;

  constraint c_cmd {
    r_len_sel  inside {[0:9]};
    r_len      inside {[1:4096]};
    r_incr_sel inside {[0:9]};
    r_mpos_sel inside {[0:9]};
    r_mpos     inside {[0:4095]};
    r_apos_sel inside {[0:9]};
    r_apos     inside {[0:4095]};
    r_strb_sel inside {[0:9]};
  }

  //---------------------------------------------------------------------------
  // ランダムなコマンドを収める範囲 (set_region で設定)
  //---------------------------------------------------------------------------
  int unsigned     m_lo = 0;            // 内部メモリ [m_lo, m_lo+m_n)
  int unsigned     m_n  = MEM_DEPTH;
  longint unsigned w_lo = WB;           // スレーブの窓 [w_lo, w_lo+w_n) (ワード位置)
  int unsigned     w_n  = LWIN;

  //---------------------------------------------------------------------------
  // コマンド
  //---------------------------------------------------------------------------
  bit              wr;
  bit [63:0]       addr;
  bit              incr;
  int unsigned     maddr;
  int unsigned     len;
  bit [STRB_W-1:0] strb;
  bit [2:0]        prot;
  // 駆動の仕方
  int unsigned     idle;                // 出す前に空けるサイクル数
  bit              wait_done = 1'b1;    // 1 : done まで待って次へ / 0 : 受け付けられたら次へ (次を実行中に出せる)

  //---------------------------------------------------------------------------
  // 結果 (driver / monitor が埋める)
  //---------------------------------------------------------------------------
  bit              done_err;
  bit [3:0]        err_flags;
  int unsigned     err_index;
  int unsigned     done_count;
  int unsigned     cyc_start;           // 受付 / done を見たサイクルの番号 (monitor が埋める)
  int unsigned     cyc_done;
  bit              held;                // 実行中に出され、待たされてから受け付けられた
  bit              other_busy;          // 受付時に反対方向のコマンドが実行中だった
  bit              other_start;         // 反対方向のコマンドと同じサイクルに受け付けられた

  `uvm_object_utils(cmd_item)

  function new(string name = "cmd_item");
    super.new(name);
  endfunction

  function void set_region(bit wr_i, int unsigned m_lo_i, int unsigned m_n_i, longint unsigned w_lo_i, int unsigned w_n_i);
    wr   = wr_i;
    m_lo = m_lo_i;
    m_n  = m_n_i;
    w_lo = w_lo_i;
    w_n  = w_n_i;
  endfunction

  // ランダム化した値から、範囲に収まる有効なコマンドを作る
  function void post_randomize();
    int unsigned     lmax;
    longint unsigned off;
    incr = (r_incr_sel>=2);
    prot = r_prot;
    lmax = incr ? ((m_n<w_n) ? m_n : w_n) : m_n;
    case( r_len_sel )
      0 : begin
        len = 1;
      end
      1 : begin
        len = lmax;
      end
      2 : begin
        len = (lmax>=2) ? 2 : 1;
      end
      default : begin
        len = 1 + ((r_len-1) % lmax);
      end
    endcase
    case( r_mpos_sel )
      0 : begin
        maddr = m_lo;
      end
      1 : begin
        maddr = m_lo + m_n - len;
      end
      default : begin
        maddr = m_lo + (r_mpos % (m_n - len + 1));
      end
    endcase
    if( incr ) begin
      case( r_apos_sel )
        0 : begin
          off = 64'd0;
        end
        1 : begin
          off = 64'(w_n - len);
        end
        default : begin
          off = 64'(r_apos % (w_n - len + 1));
        end
      endcase
    end else begin
      if( r_apos_sel==1 ) begin
        off = 64'(w_n - 1);
      end else begin
        off = 64'(r_apos % w_n);
      end
    end
    addr = axlm_waddr(w_lo + off);
    if( !wr ) begin
      strb = '0;
    end else if( r_strb_sel==0 ) begin
      strb = {STRB_W{1'b0}};
    end else if( r_strb_sel<=3 ) begin
      strb = {STRB_W{1'b1}};
    end else begin
      strb = r_strb;
    end
  endfunction

  // 指定値のコマンドにする
  function void set_cmd
  (
    bit              wr_i
   ,bit [63:0]       addr_i
   ,bit              incr_i
   ,int unsigned     maddr_i
   ,int unsigned     len_i
   ,bit [STRB_W-1:0] strb_i
   ,bit [2:0]        prot_i
  );
    wr    = wr_i;
    addr  = addr_i;
    incr  = incr_i;
    maddr = maddr_i;
    len   = len_i;
    strb  = wr_i ? strb_i : {STRB_W{1'b0}};
    prot  = prot_i;
  endfunction

  // 内部メモリの範囲 / スレーブのバイト範囲 (重なりの確認用)
  function bit mem_overlap(int unsigned lo, int unsigned n);
    return (len!=0)&&(n!=0)&&(maddr<(lo+n))&&(lo<(maddr+len));
  endfunction

  function bit [63:0] bus_lo();
    return addr;
  endfunction

  function bit [63:0] bus_hi();
    if( incr ) begin
      return addr + (64'(len) * 64'(STRB_W)) - 64'd1;
    end
    return addr + 64'(STRB_W) - 64'd1;
  endfunction

  function string convert2string();
    string s_dir;
    string s_incr;
    // 長さの違う文字列リテラルを ?: で選ぶと短いほうに詰め物が付くので、if で分ける
    if( wr ) begin
      s_dir = "WRITE";
    end else begin
      s_dir = "READ";
    end
    if( incr ) begin
      s_incr = "incr";
    end else begin
      s_incr = "fixed";
    end
    if( wr ) begin
      return $sformatf("%s addr=%0h %s mem=%0d len=%0d strb=%b prot=%b", s_dir, addr, s_incr, maddr, len, strb, prot);
    end
    return $sformatf("%s addr=%0h %s mem=%0d len=%0d prot=%b", s_dir, addr, s_incr, maddr, len, prot);
  endfunction

endclass

//=============================================================================
// ローカルポートの操作
//=============================================================================
class loc_item extends uvm_sequence_item;

  int unsigned     wr_maddr;            // 書き込み : wr_maddr から wr_data のワード数
  bit [DATA_W-1:0] wr_data[$];
  int unsigned     rd_maddr;            // 読み出し : rd_maddr から rd_n ワード
  int unsigned     rd_n;
  bit [DATA_W-1:0] rd_data[$];          // 読めたデータ (driver が入れる)
  int unsigned     gap_pct;             // アクセスの間に空きサイクルを入れる確率 [%]
  int unsigned     idle;                // 始める前に空けるサイクル数

  `uvm_object_utils(loc_item)

  function new(string name = "loc_item");
    super.new(name);
  endfunction

  function string convert2string();
    string s;
    s = "local";
    if( wr_data.size()!=0 ) begin
      s = {s, $sformatf(" write mem[%0d..%0d]", wr_maddr, wr_maddr+wr_data.size()-1)};
    end
    if( rd_n!=0 ) begin
      s = {s, $sformatf(" read mem[%0d..%0d]", rd_maddr, rd_maddr+rd_n-1)};
    end
    return s;
  endfunction

endclass

//=============================================================================
// ローカルポートのアクセス 1 回分 (monitor が出す)
//=============================================================================
class mem_item extends uvm_sequence_item;

  bit              write;
  int unsigned     addr;
  bit [DATA_W-1:0] data;          // 書き込みデータ / 読み出しデータ
  bit              rvalid;        // 読み出し : 次のサイクルに mem_r_rvalid が立っていた
  bit              with_wcmd;     // 書き込みコマンドの受付と同じサイクル
  bit              with_rcmd;     // 読み出しコマンドの受付と同じサイクル
  bit              during_wcmd;   // 書き込みコマンドの実行中に受け付けられた
  bit              during_rcmd;   // 読み出しコマンドの実行中に受け付けられた
  bit              consec;        // 直前のサイクルにも同じポートのアクセスがあった
  bit              waited;        // valid を出してから待たされた

  `uvm_object_utils(mem_item)

  function new(string name = "mem_item");
    super.new(name);
  endfunction

  function string convert2string();
    if( write ) begin
      return $sformatf("local write mem[%0d] = %0h", addr, data);
    end
    return $sformatf("local read mem[%0d] = %0h", addr, data);
  endfunction

endclass

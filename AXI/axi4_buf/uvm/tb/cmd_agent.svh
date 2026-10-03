//=============================================================================
// cmd_agent.svh
//-----------------------------------------------------------------------------
//  フレームコマンド用 agent。
//    cmd_item    : src / dst / stride / 幅 / 高さ と結果 (done_err / err_flags)
//    cmd_driver  : コマンドを valid/ready で渡し、done まで待つ
//    cmd_monitor : 受付 (ap_start) と完了 (ap_done) を別ポートで出す
//    cmd_agent   : 上記と sequencer をまとめる
//
//  cmd_item のランダム化は「単純な範囲制約」だけにして、そこから決まる値
//  (ライン長に合わせた stride、4KB 境界に寄せたアドレス) は post_randomize() で
//  計算している。制約式に乗算や加算を書くと、式のビット幅で桁あふれした解を
//  ソルバが選べてしまうため。
//=============================================================================

//=============================================================================
// Sequence item
//=============================================================================
class cmd_item extends uvm_sequence_item;

  // テストで使うアドレス範囲 (4KB ページ単位)。フレーム全体が収まるように上を空ける
  localparam int unsigned MAX_LB     = ((MAX_LINE_PIXELS*PIX_MEM_BITS)+7)/8;
  localparam int unsigned SPAN_PAGES = ((MAX_H*(MAX_LB+(4*MAX_STRB_W)))/4096) + 4;
  localparam bit [51:0]   SRC_PAGES  = (IN_ADDR_W>=64) ? 52'hF_FFFF_FFFF_FFFF : 52'((64'd1 << (IN_ADDR_W-12)) - 64'd1);
  localparam bit [51:0]   DST_PAGES  = (OUT_ADDR_W>=64) ? 52'hF_FFFF_FFFF_FFFF : 52'((64'd1 << (OUT_ADDR_W-12)) - 64'd1);
  localparam bit [51:0]   SRC_PAGE_MAX = SRC_PAGES - 52'(SPAN_PAGES);
  localparam bit [51:0]   DST_PAGE_MAX = DST_PAGES - 52'(SPAN_PAGES);

  //---------------------------------------------------------------------------
  // ランダム化する項目
  //---------------------------------------------------------------------------
  rand int unsigned w_sel;        // 0: 1 画素 / 1: 最大幅 / 2,3,4: 1 ワードの前後 / 他: w_rand
  rand int unsigned w_rand;
  rand int unsigned h_sel;        // 0: 1 ライン / 1: NUM_LINES / 2: NUM_LINES+1 / 他: h_rand
  rand int unsigned h_rand;
  rand int unsigned sstr_extra;   // stride をライン長より何ビート分大きくするか
  rand int unsigned dstr_extra;
  rand bit          sstr_zero;    // 入力 stride = 0 (同じラインを繰り返し読む)
  rand bit [51:0]   src_page;     // 先頭アドレスのページ番号
  rand bit [51:0]   dst_page;
  rand int unsigned src_pos;      // 0: ページ先頭 / 1: ページ内 / 2,3: ページ末尾の手前
  rand int unsigned dst_pos;
  rand int unsigned src_back;     // ページ末尾から何ビート手前か
  rand int unsigned dst_back;
  rand int unsigned src_ofs;      // ページ内オフセット [8 バイト単位]
  rand int unsigned dst_ofs;

  //---------------------------------------------------------------------------
  // コマンド (DUT に渡す値)
  //---------------------------------------------------------------------------
  bit [63:0]        src;
  bit [63:0]        dst;
  int unsigned      sstr;
  int unsigned      dstr;
  int unsigned      w;
  int unsigned      h;

  //---------------------------------------------------------------------------
  // 結果 / 実行中の観測値 (monitor が埋める)
  //---------------------------------------------------------------------------
  bit               done_err;
  bit [2:0]         err_flags;
  int unsigned      n_line_in;
  int unsigned      n_line_out;
  int unsigned      max_sp_level;

  constraint c_size {
    w_sel  inside {[0:11]};
    w_rand inside {[1:MAX_LINE_PIXELS]};
    h_sel  inside {[0:7]};
    h_rand inside {[1:MAX_H]};
  }

  constraint c_stride {
    sstr_extra inside {[0:3]};
    dstr_extra inside {[0:3]};
    sstr_zero dist { 1'b0 := 9, 1'b1 := 1 };
  }

  constraint c_addr {
    src_page inside {[52'd1:SRC_PAGE_MAX]};
    dst_page inside {[52'd1:DST_PAGE_MAX]};
    src_pos  inside {[0:3]};
    dst_pos  inside {[0:3]};
    src_back inside {[1:8]};
    dst_back inside {[1:8]};
    src_ofs  inside {[0:511]};
    dst_ofs  inside {[0:511]};
  }

  `uvm_object_utils(cmd_item)

  function new(string name = "cmd_item");
    super.new(name);
  endfunction

  // ページ内のオフセット (bus_bytes アライン)
  protected function bit [63:0] page_ofs(int unsigned pos, int unsigned back, int unsigned ofs8, int unsigned bus_bytes);
    bit [63:0] o;
    case( pos )
      0 : begin
        o = 64'd0;
      end
      1 : begin
        o = 64'(ofs8) * 64'd8;
      end
      default : begin
        // ページ末尾の back ビート手前 → 最初のバーストが 4KB 境界で切れる
        o = 64'd4096 - (64'(back) * 64'(bus_bytes));
      end
    endcase
    return (o / 64'(bus_bytes)) * 64'(bus_bytes);
  endfunction

  function void post_randomize();
    int unsigned lb;
    case( w_sel )
      0 : begin
        w = 1;
      end
      1 : begin
        w = MAX_LINE_PIXELS;
      end
      2 : begin
        w = (PIX_PER_WORD>1) ? (PIX_PER_WORD-1) : 1;
      end
      3 : begin
        w = PIX_PER_WORD;
      end
      4 : begin
        w = PIX_PER_WORD + 1;
      end
      default : begin
        w = w_rand;
      end
    endcase
    if( w>MAX_LINE_PIXELS ) begin
      w = MAX_LINE_PIXELS;
    end
    case( h_sel )
      0 : begin
        h = 1;
      end
      1 : begin
        h = NUM_LINES;
      end
      2 : begin
        h = NUM_LINES + 1;
      end
      default : begin
        h = h_rand;
      end
    endcase
    lb   = lb_line_bytes(w);
    sstr = lb_align_up(lb, IN_STRB_W) + (sstr_extra*IN_STRB_W);
    dstr = lb_align_up(lb, OUT_STRB_W) + (dstr_extra*OUT_STRB_W);
    if( sstr_zero ) begin
      sstr = 0;
    end
    src  = {src_page, 12'd0} + page_ofs(src_pos, src_back, src_ofs, IN_STRB_W);
    dst  = {dst_page, 12'd0} + page_ofs(dst_pos, dst_back, dst_ofs, OUT_STRB_W);
  endfunction

  // 指定値のコマンドにする (stride を 0 にすると、ライン長をバス幅に切り上げた値を使う)
  function void set_fixed(bit [63:0] src_a, bit [63:0] dst_a, int unsigned width, int unsigned height
                         , int unsigned src_stride = 0, int unsigned dst_stride = 0);
    int unsigned lb;
    src  = src_a;
    dst  = dst_a;
    w    = width;
    h    = height;
    lb   = lb_line_bytes(width);
    sstr = (src_stride!=0) ? src_stride : lb_align_up(lb, IN_STRB_W);
    dstr = (dst_stride!=0) ? dst_stride : lb_align_up(lb, OUT_STRB_W);
  endfunction

  function string convert2string();
    return $sformatf("frame %0dx%0d src=%0h(+%0d) dst=%0h(+%0d)", w, h, src, sstr, dst, dstr);
  endfunction

endclass

typedef uvm_sequencer #(cmd_item) cmd_sequencer;

//=============================================================================
// Driver
//=============================================================================
class cmd_driver extends uvm_driver #(cmd_item);

  `uvm_component_utils(cmd_driver)

  virtual cmd_if vif;

  // 受付 / 完了待ちの上限 [cycle] (+CMD_TIMEOUT=<n> で変更)
  //   DUT がハングしたとき、テスト全体のタイムアウトを待たずに止めるためのウォッチドッグ
  int unsigned   m_timeout_cyc = 400000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(cmd_vif_t)::get(this,"","cmd_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (cmd_vif) is not set")
    end
    if( $value$plusargs("CMD_TIMEOUT=%d",m_timeout_cyc) ) begin
      `uvm_info("CMD_DRV", $sformatf("command timeout = %0d cycles", m_timeout_cyc), UVM_LOW)
    end
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned n_cyc;
    @(vif.drv_cb);
    vif.drv_cb.cmd_valid      <= 1'b0;
    vif.drv_cb.cmd_src_addr   <= '0;
    vif.drv_cb.cmd_dst_addr   <= '0;
    vif.drv_cb.cmd_src_stride <= '0;
    vif.drv_cb.cmd_dst_stride <= '0;
    vif.drv_cb.cmd_width      <= '0;
    vif.drv_cb.cmd_height     <= '0;
    wait( vif.aresetn===1'b1 );
    @(vif.drv_cb);
    forever begin
      seq_item_port.get_next_item(req);
      // get_next_item() はデルタを消費するので、駆動前にクロッキングイベントで同期する
      @(vif.drv_cb);
      vif.drv_cb.cmd_src_addr   <= IN_ADDR_W'(req.src);
      vif.drv_cb.cmd_dst_addr   <= OUT_ADDR_W'(req.dst);
      vif.drv_cb.cmd_src_stride <= STRIDE_W'(req.sstr);
      vif.drv_cb.cmd_dst_stride <= STRIDE_W'(req.dstr);
      vif.drv_cb.cmd_width      <= XW'(req.w);
      vif.drv_cb.cmd_height     <= HEIGHT_W'(req.h);
      vif.drv_cb.cmd_valid      <= 1'b1;
      n_cyc = 0;
      do begin
        @(vif.drv_cb);
        n_cyc++;
        if( n_cyc>m_timeout_cyc ) begin
          `uvm_fatal("CMD_TIMEOUT", $sformatf("cmd_ready did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
        end
      end while( !((vif.drv_cb.cmd_valid===1'b1)&&(vif.drv_cb.cmd_ready===1'b1)) );
      vif.drv_cb.cmd_valid <= 1'b0;
      n_cyc = 0;
      do begin
        @(vif.drv_cb);
        n_cyc++;
        if( n_cyc>m_timeout_cyc ) begin
          `uvm_fatal("CMD_TIMEOUT", $sformatf("done did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
        end
      end while( vif.drv_cb.done!==1'b1 );
      req.done_err  = vif.drv_cb.done_err;
      req.err_flags = vif.drv_cb.err_flags;
      // monitor / scoreboard が完了を処理してからシーケンスへ戻す
      @(vif.drv_cb);
      seq_item_port.item_done();
    end
  endtask

endclass

//=============================================================================
// Monitor
//=============================================================================
class cmd_monitor extends uvm_monitor;

  `uvm_component_utils(cmd_monitor)

  virtual cmd_if                vif;
  uvm_analysis_port #(cmd_item) ap_start;   // コマンド受付時
  uvm_analysis_port #(cmd_item) ap_done;    // 完了時 (結果と観測値付き)

  protected cmd_item m_cur;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_start = new("ap_start", this);
    ap_done  = new("ap_done", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(cmd_vif_t)::get(this,"","cmd_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (cmd_vif) is not set")
    end
  endfunction

  task run_phase(uvm_phase phase);
    wait( vif.aresetn===1'b1 );
    forever begin
      @(vif.mon_cb);
      if( m_cur!=null ) begin
        if( vif.mon_cb.line_in_done===1'b1 ) begin
          m_cur.n_line_in++;
        end
        if( vif.mon_cb.line_out_done===1'b1 ) begin
          m_cur.n_line_out++;
        end
        if( 32'(vif.mon_cb.sp_level)>m_cur.max_sp_level ) begin
          m_cur.max_sp_level = 32'(vif.mon_cb.sp_level);
        end
      end
      if( (vif.mon_cb.cmd_valid===1'b1)&&(vif.mon_cb.cmd_ready===1'b1) ) begin
        if( m_cur!=null ) begin
          `uvm_error("CMD_MON", "command accepted while the previous one is not done")
        end
        m_cur      = cmd_item::type_id::create("cmd");
        m_cur.src  = 64'(vif.mon_cb.cmd_src_addr);
        m_cur.dst  = 64'(vif.mon_cb.cmd_dst_addr);
        m_cur.sstr = 32'(vif.mon_cb.cmd_src_stride);
        m_cur.dstr = 32'(vif.mon_cb.cmd_dst_stride);
        m_cur.w    = 32'(vif.mon_cb.cmd_width);
        m_cur.h    = 32'(vif.mon_cb.cmd_height);
        `uvm_info("CMD_MON", {"start ", m_cur.convert2string()}, UVM_HIGH)
        ap_start.write(m_cur);
      end else if( vif.mon_cb.done===1'b1 ) begin
        if( m_cur==null ) begin
          `uvm_error("CMD_MON", "done without an accepted command")
        end else begin
          m_cur.done_err  = vif.mon_cb.done_err;
          m_cur.err_flags = vif.mon_cb.err_flags;
          `uvm_info("CMD_MON", $sformatf("done %s err_flags=%b", m_cur.convert2string(), m_cur.err_flags), UVM_HIGH)
          ap_done.write(m_cur);
          m_cur = null;
        end
      end
    end
  endtask

endclass

//=============================================================================
// Agent
//=============================================================================
class cmd_agent extends uvm_agent;

  `uvm_component_utils(cmd_agent)

  cmd_sequencer sqr;
  cmd_driver    drv;
  cmd_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = cmd_monitor::type_id::create("mon", this);
    if( get_is_active()==UVM_ACTIVE ) begin
      sqr = cmd_sequencer::type_id::create("sqr", this);
      drv = cmd_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if( get_is_active()==UVM_ACTIVE ) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass

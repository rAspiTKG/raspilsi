//=============================================================================
// usr_agent.svh
//-----------------------------------------------------------------------------
//  ユーザ側 agent (コマンド / ステータス / 内部メモリのローカルポート)。
//    usr_item    : driver への操作 1 つ (ローカルポートの書き込み / 読み出し / コマンド)
//    mem_item    : monitor が出す、ローカルポートのアクセス 1 回分
//    usr_driver  : 操作を実行する。コマンドは done まで待つ
//    usr_monitor : コマンドの受付 (ap_start) / 完了 (ap_done) と、ローカルポートの
//                  アクセス (ap_mem) を別ポートで出す
//    usr_agent   : 上記と sequencer をまとめる
//
//  usr_item のランダム化は「単純な範囲制約」だけにして、そこから決まる値
//  (メモリ範囲やアドレス空間に収まる位置) は post_randomize() で計算している。
//=============================================================================

//=============================================================================
// Sequence item
//=============================================================================
class usr_item extends uvm_sequence_item;

  //---------------------------------------------------------------------------
  // ランダム化する項目 (コマンド用)
  //---------------------------------------------------------------------------
  rand bit              r_wr;
  rand int unsigned     r_len_sel;      // 0: 1 ワード / 1: 最大 / 2: 2 ワード / 他: r_len
  rand int unsigned     r_len;
  rand int unsigned     r_maddr_sel;    // 0: 先頭 / 1: 末尾ちょうど / 他: r_maddr
  rand int unsigned     r_maddr;
  rand int unsigned     r_sel;
  rand int unsigned     r_incr_sel;     // 0,1: 固定アドレス / 他: インクリメント
  rand int unsigned     r_addr_sel;     // 0,1: アドレス空間の末尾ちょうど / 2: 末尾の少し手前 / 他: 下位の領域
  rand int unsigned     r_addr_w;       // 下位の領域でのワード位置
  rand int unsigned     r_back;         // 末尾から何ワード手前か
  rand int unsigned     r_strb_sel;     // 0: 全て 0 / 1,2,3: 全て 1 / 他: r_strb
  rand bit [STRB_W-1:0] r_strb;
  rand bit [2:0]        r_prot;

  //---------------------------------------------------------------------------
  // 操作
  //---------------------------------------------------------------------------
  usr_op_e         op;
  // ローカルポート (OP_MEM_WR / OP_MEM_RD) : maddr から連続したワード
  //   OP_MEM_WR : data を書く / OP_MEM_RD : n ワード読み、結果を data に入れる
  int unsigned     n;
  bit [DATA_W-1:0] data[$];
  int unsigned     gap_pct;      // アクセスの間に空きサイクルを入れる確率 [%]
  // コマンド (OP_CMD)。maddr は cmd_mem_addr
  bit              wr;
  int unsigned     sel;
  bit [63:0]       addr;
  bit              incr;
  int unsigned     maddr;
  int unsigned     len;
  bit [STRB_W-1:0] strb;
  bit [2:0]        prot;
  // コマンドと同じサイクルにローカルポートへ 1 ワード書く / 読む (OP_CMD)
  bit              with_mem;
  bit              with_mem_wr;
  int unsigned     with_mem_addr;
  bit [DATA_W-1:0] with_mem_data;

  //---------------------------------------------------------------------------
  // コマンドの結果 (driver / monitor が埋める)
  //---------------------------------------------------------------------------
  bit              done_err;
  bit [2:0]        err_flags;
  int unsigned     err_index;
  int unsigned     done_count;
  // 受付 / done を見たサイクルの番号 (monitor が埋める。差が所要サイクル数)
  int unsigned     cyc_start;
  int unsigned     cyc_done;

  constraint c_cmd {
    r_len_sel   inside {[0:9]};
    r_len       inside {[1:MEM_DEPTH]};
    r_maddr_sel inside {[0:9]};
    r_maddr     inside {[0:MEM_DEPTH-1]};
    r_sel       inside {[0:NUM_SLAVES-1]};
    r_incr_sel  inside {[0:9]};
    r_addr_sel  inside {[0:9]};
    r_addr_w    inside {[0:47]};
    r_back      inside {[1:2]};
    r_strb_sel  inside {[0:9]};
  }

  `uvm_object_utils(usr_item)

  function new(string name = "usr_item");
    super.new(name);
  endfunction

  // ランダム化した値から、有効なコマンドを作る
  function void post_randomize();
    longint unsigned w;
    op   = OP_CMD;
    wr   = r_wr;
    sel  = r_sel;
    prot = r_prot;
    incr = (r_incr_sel>=2);
    // 転送数
    case( r_len_sel )
      0 : begin
        len = 1;
      end
      1 : begin
        len = MEM_DEPTH;
      end
      2 : begin
        len = (MEM_DEPTH>=2) ? 2 : 1;
      end
      default : begin
        len = r_len;
      end
    endcase
    // インクリメントのときは、アドレス空間に収まる数まで
    if( incr&&(64'(len)>SPACE_WORDS) ) begin
      len = int'(SPACE_WORDS);
    end
    // 内部メモリの位置 (範囲に収める)
    case( r_maddr_sel )
      0 : begin
        maddr = 0;
      end
      1 : begin
        maddr = MEM_DEPTH - len;
      end
      default : begin
        maddr = r_maddr;
      end
    endcase
    if( (maddr+len)>MEM_DEPTH ) begin
      maddr = MEM_DEPTH - len;
    end
    // アドレス (アドレス空間に収める)
    if( incr ) begin
      if( r_addr_sel<=1 ) begin
        w = SPACE_WORDS - 64'(len);
      end else if( (r_addr_sel==2)&&(SPACE_WORDS>=(64'(len)+64'(r_back))) ) begin
        w = SPACE_WORDS - 64'(len) - 64'(r_back);
      end else begin
        w = 64'(r_addr_w);
        if( (w+64'(len))>SPACE_WORDS ) begin
          w = SPACE_WORDS - 64'(len);
        end
      end
    end else begin
      if( r_addr_sel<=1 ) begin
        w = SPACE_WORDS - 64'd1;
      end else begin
        w = 64'(r_addr_w);
        if( w>=SPACE_WORDS ) begin
          w = SPACE_WORDS - 64'd1;
        end
      end
    end
    addr = apbm_waddr(w);
    // PSTRB
    if( r_strb_sel==0 ) begin
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
   ,int unsigned     sel_i
   ,bit [63:0]       addr_i
   ,bit              incr_i
   ,int unsigned     maddr_i
   ,int unsigned     len_i
   ,bit [STRB_W-1:0] strb_i
   ,bit [2:0]        prot_i
  );
    op    = OP_CMD;
    wr    = wr_i;
    sel   = sel_i;
    addr  = addr_i;
    incr  = incr_i;
    maddr = maddr_i;
    len   = len_i;
    strb  = strb_i;
    prot  = prot_i;
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
    case( op )
      OP_MEM_WR : begin
        return $sformatf("local write mem[%0d..%0d]", maddr, maddr+data.size()-1);
      end
      OP_MEM_RD : begin
        return $sformatf("local read mem[%0d..%0d]", maddr, maddr+n-1);
      end
      default : begin
        return $sformatf("%s slave=%0d addr=%0h %s mem=%0d len=%0d strb=%b prot=%b", s_dir, sel, addr, s_incr, maddr, len, strb, prot);
      end
    endcase
  endfunction

endclass

// ローカルポートのアクセス 1 回分 (monitor が出す)
class mem_item extends uvm_sequence_item;

  bit              write;
  int unsigned     addr;
  bit [DATA_W-1:0] data;        // 書き込みデータ / 読み出しデータ
  bit              rvalid;      // 読み出し : 次のサイクルに mem_rvalid が立っていた
  bit              with_cmd;    // コマンドの受付と同じサイクルだった
  bit              during_cmd;  // コマンドの実行中に受け付けられた (あってはならない)
  bit              consec;      // 直前のサイクルにもアクセスがあった

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

typedef uvm_sequencer #(usr_item) usr_sequencer;

//=============================================================================
// Driver
//=============================================================================
class usr_driver extends uvm_driver #(usr_item);

  `uvm_component_utils(usr_driver)

  virtual usr_if vif;

  // 受付 / 完了待ちの上限 [cycle] (+CMD_TIMEOUT=<n> で変更)
  //   DUT がハングしたとき、テスト全体のタイムアウトを待たずに止めるためのウォッチドッグ
  int unsigned   m_timeout_cyc = 200000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(usr_vif_t)::get(this,"","usr_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (usr_vif) is not set")
    end
    if( $value$plusargs("CMD_TIMEOUT=%d",m_timeout_cyc) ) begin
      `uvm_info("USR_DRV", $sformatf("command timeout = %0d cycles", m_timeout_cyc), UVM_LOW)
    end
  endfunction

  task run_phase(uvm_phase phase);
    @(vif.drv_cb);
    vif.drv_cb.cmd_valid    <= 1'b0;
    vif.drv_cb.cmd_write    <= 1'b0;
    vif.drv_cb.cmd_sel      <= '0;
    vif.drv_cb.cmd_addr     <= '0;
    vif.drv_cb.cmd_incr     <= 1'b0;
    vif.drv_cb.cmd_mem_addr <= '0;
    vif.drv_cb.cmd_len      <= '0;
    vif.drv_cb.cmd_strb     <= '0;
    vif.drv_cb.cmd_prot     <= '0;
    vif.drv_cb.mem_valid    <= 1'b0;
    vif.drv_cb.mem_write    <= 1'b0;
    vif.drv_cb.mem_addr     <= '0;
    vif.drv_cb.mem_wdata    <= '0;
    wait( vif.presetn===1'b1 );
    @(vif.drv_cb);
    forever begin
      seq_item_port.get_next_item(req);
      // get_next_item() はデルタを消費するので、駆動前にクロッキングイベントで同期する
      @(vif.drv_cb);
      case( req.op )
        OP_MEM_WR : begin
          do_mem(1'b1);
        end
        OP_MEM_RD : begin
          do_mem(1'b0);
        end
        default : begin
          do_cmd();
        end
      endcase
      seq_item_port.item_done();
    end
  endtask

  // ローカルポート : maddr から連続したワードを書く / 読む
  //   アクセスの間に gap_pct の確率で空きサイクルを入れる。入れなければ mem_valid を上げたまま続ける
  protected task do_mem(bit write);
    int unsigned total;
    int unsigned i;
    int unsigned n_cyc;
    bit          pend_rd;
    bit          drive_now;
    total   = write ? req.data.size() : req.n;
    i       = 0;
    n_cyc   = 0;
    pend_rd = 1'b0;
    if( !write ) begin
      req.data.delete();
    end
    while( (i<total)||pend_rd ) begin
      drive_now = (i<total)&&!($urandom_range(99,0)<req.gap_pct);
      if( drive_now ) begin
        vif.drv_cb.mem_valid <= 1'b1;
        vif.drv_cb.mem_write <= write;
        vif.drv_cb.mem_addr  <= MEM_AW'(req.maddr+i);
        if( write ) begin
          vif.drv_cb.mem_wdata <= req.data[i];
        end
      end else begin
        vif.drv_cb.mem_valid <= 1'b0;
      end
      // 握手するまで同じ内容を出し続ける
      do begin
        @(vif.drv_cb);
        n_cyc++;
        if( n_cyc>m_timeout_cyc ) begin
          `uvm_fatal("USR_TIMEOUT", $sformatf("mem_ready did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
        end
        if( pend_rd ) begin
          // 直前のサイクルに受け付けられた読み出しのデータ
          req.data.push_back(vif.drv_cb.mem_rdata);
          pend_rd = 1'b0;
        end
      end while( drive_now&&!((vif.drv_cb.mem_valid===1'b1)&&(vif.drv_cb.mem_ready===1'b1)) );
      if( drive_now ) begin
        i++;
        pend_rd = !write;
      end
    end
    vif.drv_cb.mem_valid <= 1'b0;
  endtask

  // コマンド : valid/ready で渡し、done を待って結果を取り込む
  //   with_mem=1 のときは、同じサイクルにローカルポートのアクセスも出す
  protected task do_cmd();
    int unsigned n_cyc;
    bit          mem_pend;
    mem_pend = req.with_mem;
    if( mem_pend ) begin
      vif.drv_cb.mem_valid <= 1'b1;
      vif.drv_cb.mem_write <= req.with_mem_wr;
      vif.drv_cb.mem_addr  <= MEM_AW'(req.with_mem_addr);
      vif.drv_cb.mem_wdata <= req.with_mem_data;
    end
    vif.drv_cb.cmd_write    <= req.wr;
    vif.drv_cb.cmd_sel      <= SEL_W'(req.sel);
    vif.drv_cb.cmd_addr     <= ADDR_W'(req.addr);
    vif.drv_cb.cmd_incr     <= req.incr;
    vif.drv_cb.cmd_mem_addr <= MEM_AW'(req.maddr);
    vif.drv_cb.cmd_len      <= LEN_W'(req.len);
    vif.drv_cb.cmd_strb     <= req.strb;
    vif.drv_cb.cmd_prot     <= req.prot;
    vif.drv_cb.cmd_valid    <= 1'b1;
    n_cyc = 0;
    do begin
      @(vif.drv_cb);
      n_cyc++;
      if( n_cyc>m_timeout_cyc ) begin
        `uvm_fatal("USR_TIMEOUT", $sformatf("cmd_ready did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
      end
      // ローカルポートのアクセスは、受け付けられたら下げる
      if( mem_pend&&(vif.drv_cb.mem_valid===1'b1)&&(vif.drv_cb.mem_ready===1'b1) ) begin
        vif.drv_cb.mem_valid <= 1'b0;
        mem_pend = 1'b0;
      end
    end while( !((vif.drv_cb.cmd_valid===1'b1)&&(vif.drv_cb.cmd_ready===1'b1)) );
    vif.drv_cb.cmd_valid <= 1'b0;
    n_cyc = 0;
    do begin
      @(vif.drv_cb);
      n_cyc++;
      if( n_cyc>m_timeout_cyc ) begin
        `uvm_fatal("USR_TIMEOUT", $sformatf("done did not arrive within %0d cycles : %s", m_timeout_cyc, req.convert2string()))
      end
    end while( vif.drv_cb.done!==1'b1 );
    req.done_err   = vif.drv_cb.done_err;
    req.err_flags  = vif.drv_cb.err_flags;
    req.err_index  = 32'(vif.drv_cb.err_index);
    req.done_count = 32'(vif.drv_cb.done_count);
    // monitor / scoreboard が完了を処理してからシーケンスへ戻す
    @(vif.drv_cb);
  endtask

endclass

//=============================================================================
// Monitor
//=============================================================================
class usr_monitor extends uvm_monitor;

  `uvm_component_utils(usr_monitor)

  virtual usr_if                vif;
  uvm_analysis_port #(usr_item) ap_start;   // コマンド受付時
  uvm_analysis_port #(usr_item) ap_done;    // 完了時 (結果付き)
  uvm_analysis_port #(mem_item) ap_mem;     // ローカルポートのアクセス (読み出しはデータが出たとき)

  protected usr_item     m_cur;        // 実行中のコマンド
  protected mem_item     m_rd;         // データ待ちの読み出し
  protected bit          m_last_acc;   // 直前のサイクルにローカルポートのアクセスがあった
  protected int unsigned m_cyc;        // サイクル番号

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_start = new("ap_start", this);
    ap_done  = new("ap_done", this);
    ap_mem   = new("ap_mem", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(usr_vif_t)::get(this,"","usr_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (usr_vif) is not set")
    end
  endfunction

  task run_phase(uvm_phase phase);
    wait( vif.presetn===1'b1 );
    forever begin
      @(vif.mon_cb);
      m_cyc++;
      sample_mem();
      sample_cmd();
    end
  endtask

  protected function void sample_mem();
    mem_item t;
    bit      acc;
    bit      cmd_fire;
    // 直前のサイクルに受け付けられた読み出しのデータ
    if( m_rd!=null ) begin
      m_rd.rvalid = (vif.mon_cb.mem_rvalid===1'b1);
      m_rd.data   = vif.mon_cb.mem_rdata;
      `uvm_info("USR_MON", m_rd.convert2string(), UVM_HIGH)
      ap_mem.write(m_rd);
      m_rd = null;
    end
    acc      = (vif.mon_cb.mem_valid===1'b1)&&(vif.mon_cb.mem_ready===1'b1);
    cmd_fire = (vif.mon_cb.cmd_valid===1'b1)&&(vif.mon_cb.cmd_ready===1'b1);
    if( acc ) begin
      t            = mem_item::type_id::create("mem_acc");
      t.write      = vif.mon_cb.mem_write;
      t.addr       = 32'(vif.mon_cb.mem_addr);
      t.with_cmd   = cmd_fire;
      t.during_cmd = (m_cur!=null);
      t.consec     = m_last_acc;
      if( t.write ) begin
        t.data = vif.mon_cb.mem_wdata;
        `uvm_info("USR_MON", t.convert2string(), UVM_HIGH)
        ap_mem.write(t);
      end else begin
        m_rd = t;
      end
    end
    m_last_acc = acc;
  endfunction

  protected function void sample_cmd();
    if( (vif.mon_cb.cmd_valid===1'b1)&&(vif.mon_cb.cmd_ready===1'b1) ) begin
      if( m_cur!=null ) begin
        `uvm_error("USR_MON", "command accepted while the previous one is not done")
      end
      m_cur       = usr_item::type_id::create("cmd");
      m_cur.op    = OP_CMD;
      m_cur.wr    = vif.mon_cb.cmd_write;
      m_cur.sel   = 32'(vif.mon_cb.cmd_sel);
      m_cur.addr  = 64'(vif.mon_cb.cmd_addr);
      m_cur.incr  = vif.mon_cb.cmd_incr;
      m_cur.maddr = 32'(vif.mon_cb.cmd_mem_addr);
      m_cur.len   = 32'(vif.mon_cb.cmd_len);
      m_cur.strb  = vif.mon_cb.cmd_strb;
      m_cur.prot  = vif.mon_cb.cmd_prot;
      // 所要サイクル数の起点
      m_cur.cyc_start = m_cyc;
      `uvm_info("USR_MON", {"start ", m_cur.convert2string()}, UVM_HIGH)
      ap_start.write(m_cur);
    end else if( vif.mon_cb.done===1'b1 ) begin
      if( m_cur==null ) begin
        `uvm_error("USR_MON", "done without an accepted command")
      end else begin
        m_cur.done_err   = vif.mon_cb.done_err;
        m_cur.err_flags  = vif.mon_cb.err_flags;
        m_cur.err_index  = 32'(vif.mon_cb.err_index);
        m_cur.done_count = 32'(vif.mon_cb.done_count);
        m_cur.cyc_done   = m_cyc;
        `uvm_info("USR_MON", $sformatf("done %s err_flags=%b err_index=%0d done_count=%0d", m_cur.convert2string(), m_cur.err_flags, m_cur.err_index, m_cur.done_count), UVM_HIGH)
        ap_done.write(m_cur);
        m_cur = null;
      end
    end
  endfunction

endclass

//=============================================================================
// Agent
//=============================================================================
class usr_agent extends uvm_agent;

  `uvm_component_utils(usr_agent)

  usr_sequencer sqr;
  usr_driver    drv;
  usr_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = usr_monitor::type_id::create("mon", this);
    if( get_is_active()==UVM_ACTIVE ) begin
      sqr = usr_sequencer::type_id::create("sqr", this);
      drv = usr_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if( get_is_active()==UVM_ACTIVE ) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction

endclass

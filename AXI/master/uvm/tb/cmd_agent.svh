//=============================================================================
// cmd_agent.svh
//-----------------------------------------------------------------------------
//  コピーコマンド用 agent。
//    cmd_item    : src / dst / len (ビート数) と結果 (done_err)
//    cmd_driver  : コマンドを valid/ready で渡し、done まで待つ
//    cmd_monitor : 受付 (ap_start) と完了 (ap_done) を別ポートで出す
//    cmd_agent   : 上記と sequencer をまとめる
//=============================================================================

//=============================================================================
// Sequence item
//=============================================================================
class cmd_item extends uvm_sequence_item;

  rand bit [ADDR_W-1:0] src;
  rand bit [ADDR_W-1:0] dst;
  rand int unsigned     len;            // ビート数 (DATA_W 単位)
  rand bit              src_near_4k;    // src を 4KB 境界直前の 128B に寄せる
  rand bit              dst_near_4k;    // dst を 4KB 境界直前の 128B に寄せる

  bit                   done_err;       // DUT が返した done_err

  // バス幅アライン
  constraint c_align {
    src[ADDR_LSB-1:0] == 0;
    dst[ADDR_LSB-1:0] == 0;
  }

  // 1 バースト未満 / ちょうど MAX_BURST / 数バースト / 長め
  constraint c_len {
    len inside {[1:300]};
    len dist { [1:15] :/ 3, 16 := 1, [17:64] :/ 3, [65:300] :/ 3 };
  }

  // src と dst は別の窓に置く (重ならない)
  //   注意: 制約式も通常の式と同じビット幅規則で評価される。
  //         32bit のまま (src + len*8) <= HI+1 と書くと、src=FFFFFFB0 のように
  //         加算が桁あふれして小さな値になる解をソルバが選べてしまう。
  //         そこで src / dst の上限を明示し、終端の計算は 64bit に広げる。
  constraint c_win {
    src inside {[SRC_LO:SRC_HI]};
    dst inside {[DST_LO:DST_HI]};
    (64'(src) + (64'(len) << ADDR_LSB)) <= (64'(SRC_HI) + 64'd1);
    (64'(dst) + (64'(len) << ADDR_LSB)) <= (64'(DST_HI) + 64'd1);
  }

  // 4KB 境界を跨ぐ転送を出しやすくする
  constraint c_near_4k {
    src_near_4k -> (src[11:7] == 5'h1F);
    dst_near_4k -> (dst[11:7] == 5'h1F);
  }

  `uvm_object_utils(cmd_item)

  function new(string name = "cmd_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("copy src=%08h dst=%08h len=%0d", src, dst, len);
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
  int unsigned   m_timeout_cyc = 20000;

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
    vif.drv_cb.cmd_valid <= 1'b0;
    vif.drv_cb.cmd_src   <= '0;
    vif.drv_cb.cmd_dst   <= '0;
    vif.drv_cb.cmd_len   <= '0;
    wait( vif.aresetn===1'b1 );
    @(vif.drv_cb);
    forever begin
      seq_item_port.get_next_item(req);
      // get_next_item() はデルタを消費するので、駆動前にクロッキングイベントで同期する
      @(vif.drv_cb);
      vif.drv_cb.cmd_src   <= req.src;
      vif.drv_cb.cmd_dst   <= req.dst;
      vif.drv_cb.cmd_len   <= LEN_W'(req.len);
      vif.drv_cb.cmd_valid <= 1'b1;
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
      req.done_err = vif.drv_cb.done_err;
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
  uvm_analysis_port #(cmd_item) ap_done;    // 完了時 (done_err 付き)

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
      if( (vif.mon_cb.cmd_valid===1'b1)&&(vif.mon_cb.cmd_ready===1'b1) ) begin
        if( m_cur!=null ) begin
          `uvm_error("CMD_MON", "command accepted while the previous one is not done")
        end
        m_cur     = cmd_item::type_id::create("cmd");
        m_cur.src = vif.mon_cb.cmd_src;
        m_cur.dst = vif.mon_cb.cmd_dst;
        m_cur.len = 32'(vif.mon_cb.cmd_len);
        `uvm_info("CMD_MON", {"start ", m_cur.convert2string()}, UVM_HIGH)
        ap_start.write(m_cur);
      end
      if( vif.mon_cb.done===1'b1 ) begin
        if( m_cur==null ) begin
          `uvm_error("CMD_MON", "done without an accepted command")
        end else begin
          m_cur.done_err = vif.mon_cb.done_err;
          `uvm_info("CMD_MON", $sformatf("done %s done_err=%0d", m_cur.convert2string(), m_cur.done_err), UVM_HIGH)
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

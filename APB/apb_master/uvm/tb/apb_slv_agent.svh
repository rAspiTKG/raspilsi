//=============================================================================
// apb_slv_agent.svh
//-----------------------------------------------------------------------------
//  APB スレーブ agent (DUT の APB マスタに応答する側)。
//    apb_responder : 全スレーブぶんの応答を 1 つのコンポーネントで行う。
//                    スレーブごとの cfg に従ってウェイト・PSLVERR・ハングを入れる
//    apb_monitor   : 転送を観測し、完了 (または打ち切り) ごとに apb_item を出す
//
//  駆動は全て clocking block 経由で、@(vif.slv_cb) の直後 (間にブロッキング呼び出し
//  を挟まない) に行う。出力は「次のサイクルの値」を毎サイクル全ビット書く。
//=============================================================================

//=============================================================================
// Responder
//=============================================================================
class apb_responder extends uvm_component;

  `uvm_component_utils(apb_responder)

  typedef enum {
    M_IDLE
   ,M_WAIT
   ,M_RESP
  } mst_e;

  virtual apb_if vif;
  apb_slv_mem    mem;
  apb_slv_cfg    cfg[NUM_SLAVES];

  // スレーブごとの状態
  protected mst_e            m_st[NUM_SLAVES];
  protected int unsigned     m_wleft[NUM_SLAVES];
  protected bit              m_hang[NUM_SLAVES];
  protected bit [63:0]       m_addr[NUM_SLAVES];
  protected bit              m_write[NUM_SLAVES];
  protected bit [DATA_W-1:0] m_wdata[NUM_SLAVES];
  protected bit [STRB_W-1:0] m_strb[NUM_SLAVES];
  // 次のサイクルに出す値
  protected bit [NUM_SLAVES-1:0]          m_pready;
  protected bit [(NUM_SLAVES*DATA_W)-1:0] m_prdata;
  protected bit [NUM_SLAVES-1:0]          m_pslverr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(apb_vif_t)::get(this,"","apb_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (apb_vif) is not set")
    end
  endfunction

  protected function bit [DATA_W-1:0] rand_data();
    bit [DATA_W-1:0] d;
    for( int unsigned b=0; b<DATA_W; b++ ) begin
      d[b] = 1'($urandom());
    end
    return d;
  endfunction

  // 見てはいけないタイミングの出力
  protected function void set_idle(int unsigned s);
    if( cfg[s].noise ) begin
      m_pready[s]                  = 1'($urandom());
      m_pslverr[s]                 = 1'($urandom());
      m_prdata[s*DATA_W +: DATA_W] = rand_data();
    end else begin
      m_pready[s]                  = 1'b0;
      m_pslverr[s]                 = 1'b0;
      m_prdata[s*DATA_W +: DATA_W] = {DATA_W{1'b0}};
    end
  endfunction

  // ウェイト中の出力 (PREADY=0)
  protected function void set_wait(int unsigned s);
    m_pready[s] = 1'b0;
    if( cfg[s].noise ) begin
      m_pslverr[s]                 = 1'($urandom());
      m_prdata[s*DATA_W +: DATA_W] = rand_data();
    end else begin
      m_pslverr[s]                 = 1'b0;
      m_prdata[s*DATA_W +: DATA_W] = {DATA_W{1'b0}};
    end
  endfunction

  // 完了サイクルの出力 (PREADY=1)
  protected function void set_resp(int unsigned s);
    bit err;
    err          = cfg[s].in_err(m_addr[s]);
    m_pready[s]  = 1'b1;
    m_pslverr[s] = err;
    if( !m_write[s]&&!err ) begin
      m_prdata[s*DATA_W +: DATA_W] = mem.read_word(s, m_addr[s]);
    end else if( cfg[s].noise ) begin
      m_prdata[s*DATA_W +: DATA_W] = rand_data();
    end else begin
      m_prdata[s*DATA_W +: DATA_W] = {DATA_W{1'b0}};
    end
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned           n;
    bit                    sel;
    bit                    en;
    bit [NUM_SLAVES-1:0]   psel_v;
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      m_st[s] = M_IDLE;
    end
    m_pready  = '0;
    m_prdata  = '0;
    m_pslverr = '0;
    @(vif.slv_cb);
    vif.slv_cb.pready  <= m_pready;
    vif.slv_cb.prdata  <= m_prdata;
    vif.slv_cb.pslverr <= m_pslverr;
    wait( vif.presetn===1'b1 );
    forever begin
      @(vif.slv_cb);
      en     = (vif.slv_cb.penable===1'b1);
      psel_v = vif.slv_cb.psel;
      for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
        sel = psel_v[s];
        if( sel&&!en ) begin
          // SETUP : 次のサイクル (最初の ACCESS) の応答を決める
          m_addr[s]  = 64'(vif.slv_cb.paddr);
          m_write[s] = vif.slv_cb.pwrite;
          m_wdata[s] = vif.slv_cb.pwdata;
          m_strb[s]  = vif.slv_cb.pstrb;
          m_hang[s]  = cfg[s].in_hang(m_addr[s]);
          n          = cfg[s].pick_wait();
          if( m_hang[s] ) begin
            set_wait(s);
            m_st[s] = M_WAIT;
          end else if( n==0 ) begin
            set_resp(s);
            m_st[s] = M_RESP;
          end else begin
            set_wait(s);
            m_wleft[s] = n;
            m_st[s]    = M_WAIT;
          end
        end else if( sel&&en ) begin
          // ACCESS
          if( m_st[s]==M_RESP ) begin
            // このエッジで転送が完了する (PREADY=1 を出していた)
            if( m_write[s]&&!cfg[s].in_err(m_addr[s]) ) begin
              mem.write_word(s, m_addr[s], m_wdata[s], m_strb[s]);
            end
            set_idle(s);
            m_st[s] = M_IDLE;
          end else if( m_st[s]==M_WAIT ) begin
            if( m_hang[s] ) begin
              set_wait(s);
            end else if( m_wleft[s]<=1 ) begin
              set_resp(s);
              m_st[s] = M_RESP;
            end else begin
              set_wait(s);
              m_wleft[s] = m_wleft[s] - 1;
            end
          end else begin
            // SETUP を経ていない ACCESS (interface の SVA が報告する)
            set_idle(s);
          end
        end else begin
          // 選択されていない (ウェイト中に下がった場合は打ち切り)
          set_idle(s);
          m_st[s] = M_IDLE;
        end
      end
      vif.slv_cb.pready  <= m_pready;
      vif.slv_cb.prdata  <= m_prdata;
      vif.slv_cb.pslverr <= m_pslverr;
    end
  endtask

endclass

//=============================================================================
// Monitor
//=============================================================================
class apb_monitor extends uvm_monitor;

  `uvm_component_utils(apb_monitor)

  virtual apb_if                vif;
  uvm_analysis_port #(apb_item) ap;

  protected apb_item m_cur;        // 転送中 (SETUP を見てから完了まで)
  protected bit      m_last_acc;   // 直前のサイクルが ACCESS だった (転送の完了、または打ち切りの直前)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if( !uvm_config_db#(apb_vif_t)::get(this,"","apb_vif",vif) ) begin
      `uvm_fatal("NOVIF", "virtual interface (apb_vif) is not set")
    end
  endfunction

  task run_phase(uvm_phase phase);
    wait( vif.presetn===1'b1 );
    forever begin
      @(vif.mon_cb);
      sample();
    end
  endtask

  protected function void sample();
    bit                             en;
    bit                             any_sel;
    int unsigned                    idx;
    bit [NUM_SLAVES-1:0]            psel_v;
    bit [NUM_SLAVES-1:0]            pready_v;
    bit [NUM_SLAVES-1:0]            pslverr_v;
    bit [(NUM_SLAVES*DATA_W)-1:0]   prdata_v;
    // クロッキングブロックの値は、いったんローカル変数に取ってから添字で選ぶ
    en        = (vif.mon_cb.penable===1'b1);
    psel_v    = vif.mon_cb.psel;
    pready_v  = vif.mon_cb.pready;
    pslverr_v = vif.mon_cb.pslverr;
    prdata_v  = vif.mon_cb.prdata;
    // 転送中 : このサイクルが ACCESS でなければ打ち切り
    if( m_cur!=null ) begin
      if( psel_v[m_cur.slv]&&en ) begin
        if( pready_v[m_cur.slv] ) begin
          m_cur.rdata  = prdata_v[m_cur.slv*DATA_W +: DATA_W];
          m_cur.slverr = pslverr_v[m_cur.slv];
          `uvm_info("APB_MON", m_cur.convert2string(), UVM_HIGH)
          ap.write(m_cur);
          m_cur = null;
        end else begin
          m_cur.n_wait++;
        end
      end else begin
        m_cur.aborted = 1'b1;
        `uvm_info("APB_MON", m_cur.convert2string(), UVM_HIGH)
        ap.write(m_cur);
        m_cur = null;
      end
    end
    // SETUP : 新しい転送
    any_sel = 1'b0;
    idx     = 0;
    for( int unsigned s=0; s<NUM_SLAVES; s++ ) begin
      if( psel_v[s]&&!any_sel ) begin
        any_sel = 1'b1;
        idx     = s;
      end
    end
    if( (m_cur==null)&&any_sel&&!en ) begin
      m_cur       = apb_item::type_id::create("apb_tr");
      m_cur.slv   = idx;
      m_cur.addr  = 64'(vif.mon_cb.paddr);
      m_cur.write = vif.mon_cb.pwrite;
      m_cur.wdata = vif.mon_cb.pwdata;
      m_cur.strb  = vif.mon_cb.pstrb;
      m_cur.prot  = vif.mon_cb.pprot;
      m_cur.b2b   = m_last_acc;
    end
    m_last_acc = any_sel&&en;
  endfunction

endclass

//=============================================================================
// Agent
//=============================================================================
class apb_slv_agent extends uvm_agent;

  `uvm_component_utils(apb_slv_agent)

  apb_responder rsp;
  apb_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = apb_monitor::type_id::create("mon", this);
    if( get_is_active()==UVM_ACTIVE ) begin
      rsp = apb_responder::type_id::create("rsp", this);
    end
  endfunction

endclass

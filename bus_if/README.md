# bus_if : バスプロトコルの SystemVerilog interface と簡易サンプル

これまでに作ったモジュールのバス (AXI4 / AXI4-Lite / AHB5・AHB-Lite / APB4 / p2p / 簡易ストリーム) を、
SystemVerilog の interface にまとめたものです。モジュールのポート宣言とインスタンスの接続が、バス 1 本につき 1 行になります。

各 interface の中身は次のとおりです。

| 中身 | 合成 | シミュレーション |
|---|---|---|
| 信号 + 合成用の modport (mgr / sub など) | 入る | 入る |
| clocking block + TB 用の modport (mgr_tb など) | 入らない (`SYNTHESIS` で外れる) | 入る |
| プロトコルチェック (SVA と振る舞いのチェック。違反は `$error`) | 入らない | 入る (CHECK=1 のとき) |
| TB_ROLE の確認 (つながない側の clocking block に書くと `$warning`) | 入らない | 入る |

既存のモジュールは変更していません (interface と、それを使う新しいサンプルだけです)。
既存のモジュールを interface につなぐ書き方は 4.5 にあります。

---------------------------------------------------------------------------------------------------

## 1. interface の一覧

| ファイル | プロトコル | 信号 | 合成用 modport | TB 用 clocking block | これまでのモジュールの信号 |
|---|---|---|---|---|---|
| if/axi4_if.sv | AXI4 (QOS / REGION あり、USER なし) | 39 | mgr / sub / mon | mgr_cb / sub_cb / mon_cb | m_axi_* / s_axi_* |
| if/axil_if.sv | AXI4-Lite | 19 | mgr / sub / mon | mgr_cb / sub_cb / mon_cb | axil_master_mem などの m_axi_* / s_axi_* |
| if/ahb_if.sv | AHB5 / AHB-Lite (1 リンク分) | 18 | mgr / sub / dec / mon | mgr_cb / sub_cb / mon_cb | ahb_master_mem の h*、shared_sram の SCP 側 |
| if/apb_if.sv | APB4 (APB3 互換。1 コンプリータ分) | 10 | req / cmp / mon | req_cb / cmp_cb / mon_cb | apb_master_mem の P* (PSEL[n] などは interface の配列) |
| if/p2p_if.sv | p2p (vld / busy) | 5 | src / snk / mon | src_cb / snk_cb / mon_cb | p2p_out_* / p2p_in_* |
| if/strm_if.sv | 簡易ストリーム (valid / ready) | 7 | src / snk / mon | src_cb / snk_cb / mon_cb | m_t* / s_t* |

信号名はプロトコルの信号名の小文字です (awaddr、haddr、psel など)。p2p は dat / strb / last / vld / busy、
簡易ストリームは tdata / tstrb / tlast / tid / taddr / tvalid / tready です。

modport の名前

| modport | 意味 |
|---|---|
| mgr / req / src | マネージャ (マスタ) / リクエスタ / 送信側。要求を出す側 |
| sub / cmp / snk | サブオーディネート (スレーブ) / コンプリータ / 受信側 |
| dec | AHB だけ。インターコネクトのサブオーディネート向きのポート (HSEL と HREADY も出す) |
| mon | 全て入力 (観測用) |
| `<名前>_tb` | TB 用。clocking block `<名前>_cb` とリセットだけを持つ (シミュレーションだけ) |

parameter

| parameter | interface | 意味 |
|---|---|---|
| ADDR_WIDTH / DATA_WIDTH / ID_WIDTH | 各 interface | 幅 (既定値はファイルの先頭を参照) |
| HPROT_WIDTH / MASTER_WIDTH | ahb_if | HPROT の幅 (4 : AHB-Lite / 7 : AHB5 の Extended_Memory_Types)、HMASTER の幅 |
| DIRECT | ahb_if | 1 : マネージャとサブオーディネートを直結 (HSEL=1、HREADY=HREADYOUT を interface の中で作る) / 0 : 間にインターコネクトを置く |
| CHECK | 全て | 1 : プロトコルチェックを有効にする (シミュレーションだけ) |
| TB_ROLE | 全て | TB が clocking block で駆動する側。0 : なし (RTL 同士) / 1 : mgr・req・src 側 / 2 : sub・cmp・snk 側 / 3 : 両方 |

---------------------------------------------------------------------------------------------------

## 2. ファイル構成

```text
bus_if/
├── README.md
├── if/                 interface (6 個)
├── sample/             interface ごとの簡易サンプル (合成できる RTL と、自己チェック TB)
│   ├── axi4/           axi4_smp_mgr -> axi4_smp_mem (INCR / WRAP の書き込みと読み出し)
│   ├── axil/           axil_smp_mgr -> axil_smp_regs (レジスタの書き込み / 読み出し、SLVERR)
│   ├── ahb/            ahb_smp_mgr -> ahb_smp_ic (デコーダ + マルチプレクサ) -> ahb_smp_mem x 2
│   ├── apb/            apb_smp_req -> apb_smp_regs x 2 (interface の配列)
│   ├── p2p/            p2p_smp_src -> p2p_smp_slice -> p2p_smp_sink
│   ├── strm/           strm_smp_src -> strm_smp_rs (レジスタスライス) -> strm_smp_sink
│   └── uvm/            tb_axil_uvm (UVM で使う例。uvm_config_db で virtual interface を渡す)
├── check/              tb_<p>_chk : プロトコルチェックの自己テスト / tb_role_chk : TB_ROLE の確認の自己テスト
└── sim/Makefile        Verilator で lint、シミュレーション、自己テストを行う
```

サンプルの TB (`sample/<p>/tb_<p>_smp.sv`) は 2 部構成です。

1. 合成できるサンプル (`<p>_smp_top`) を動かし、interface を mon_cb で観測して転送の数などを確かめる
2. TB が clocking block (TB_ROLE=1) で要求側になり、サンプルの応答側を直接動かす。
   `+BAD` を付けるとプロトコル違反を 1 つ入れ、interface のチェックが止めることを確かめる

---------------------------------------------------------------------------------------------------

## 3. どれだけ減るか

AXI4 のマネージャとサブオーディネートを 1 本でつなぐ場合 (sample/axi4/axi4_smp_top.sv)

| 記述 | 個別の信号 | interface |
|---|---|---|
| モジュールのポート宣言 | 39 行 / モジュール | 1 行 (`axi4_if.mgr m_axi`) |
| 上位の wire 宣言 | 39 行 | interface のインスタンス 8 行 |
| インスタンスの接続 | 39 行 x 2 | 1 行 x 2 |
| 上位の合計 | 117 行 | 10 行 |

他の interface も、上位の記述は「信号の数 x 3 行」が「インスタンス (parameter の数 + 5 行) + 接続 1 行 x 2」になります
(AXI4-Lite 19 本、AHB 18 本、APB 10 本、p2p 5 本、簡易ストリーム 7 本)。

---------------------------------------------------------------------------------------------------

## 4. 使い方

### 4.1 合成するモジュールのポート

ポートは「interface 名.modport 名」で 1 行に書きます。信号は「ポート名.信号名」で参照します
(sample/axi4/axi4_smp_mgr.sv からの抜粋)。

```systemverilog
module axi4_smp_mgr #(
  parameter int unsigned     ADDR_WIDTH = 32
 ,parameter int unsigned     DATA_WIDTH = 64
 ,parameter int unsigned     ID_WIDTH   = 4
 ,parameter int unsigned     AXI_ID     = 0
 ,parameter longint unsigned BASE_ADDR  = 64'h0000_0100  // 4 ワード (4 * DATA_WIDTH/8 バイト) にアライン
 ,parameter int unsigned     NBEAT      = 8              // 4〜256 (4KB 境界をまたがないこと)
) (
  input  logic aclk
 ,input  logic aresetn
 ,input  logic start
 ,output logic busy
 ,output logic done
 ,output logic err
 ,axi4_if.mgr  m_axi
);

  // つないだ axi4_if の幅がこのモジュールの parameter と同じか (違えばエラボレーションで止める)
  if( ($bits(m_axi.awaddr)!=ADDR_WIDTH)||($bits(m_axi.wdata)!=DATA_WIDTH)||($bits(m_axi.awid)!=ID_WIDTH) ) begin : g_chk_if
    $error("axi4_smp_mgr : ADDR_WIDTH / DATA_WIDTH / ID_WIDTH differ from the axi4_if connected to m_axi");
  end
  ...
  assign m_axi.awid     = ID_WIDTH'(AXI_ID);
  assign m_axi.awaddr   = ADDR_WIDTH'(BASE_ADDR);
  ...
  assign m_axi.awvalid  = awvalid_q;
```

- interface の parameter とモジュールの parameter は同じ値にします。サンプルのモジュールは全て、上の
  `g_chk_if` のように幅を比べ、違えばエラボレーション時に `$error` で止めます
- interface の配列のポート (`apb_if.req m_apb [NSEL]` など) だけは、シミュレーションの開始時に `initial` で比べます
  (7 章の Verilator の制限のため)
- modport の向きに反する代入 (mgr のポートから awready に代入するなど) は、ツールがエラーにします

### 4.2 上位でつなぐ

sample/axi4/axi4_smp_top.sv の本体です。

```systemverilog
  axi4_if #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
  ) u_axi (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
  );

  axi4_smp_mgr #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
   ,.NBEAT      ( NBEAT      )
  ) u_mgr (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
   ,.start   ( start   )
   ,.busy    ( busy    )
   ,.done    ( done    )
   ,.err     ( err     )
   ,.m_axi   ( u_axi   )
  );

  axi4_smp_mem #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.ID_WIDTH   ( ID_WIDTH   )
   ,.READY_DLY  ( READY_DLY  )
  ) u_mem (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
   ,.s_axi   ( u_axi   )
  );
```

interface のクロックとリセットは、プロトコルチェックと clocking block だけが使います (合成では使いません)。
RTL のモジュールには、これまでどおりクロックとリセットを別のポートで渡します。

### 4.3 AHB : 直結とインターコネクト

ahb_if は 1 リンク分です。HSEL と HREADY を誰が作るかを DIRECT で選びます。

```text
  ahb_smp_mgr (m_ahb : mgr)
        |   ahb_if u_m     DIRECT=1 : HSEL=1、HREADY=HREADYOUT を interface の中で作る
  ahb_smp_ic  (s_ahb : sub)          インターコネクトのマネージャ向きは sub (HREADYOUT にマルチプレクサの出力を出す)
  ahb_smp_ic  (m_ahb[i] : dec)       インターコネクトのサブオーディネート向きは dec (HSEL[i] と HREADY を出す)
        |   ahb_if u_s[2]  DIRECT=0
  ahb_smp_mem (s_ahb : sub) x 2      WAIT=0 と WAIT=2
```

- マネージャとサブオーディネートを直結するなら DIRECT=1 (既定) にして、mgr と sub をつなぐだけです
- AHB-Lite で使わない信号 (HNONSEC / HEXCL / HMASTER / HWSTRB / HEXOKAY) も interface にあるので、
  出す側のモジュールが固定値を出します (使わない側は読まないだけ)

### 4.4 APB : コンプリータごとの interface の配列

apb_if は 1 コンプリータ分です。これまでの PSEL[n] / PREADY[n] / PSLVERR[n] は、interface の配列の n 番目になります
(sample/apb/apb_smp_top.sv からの抜粋)。

```systemverilog
  apb_if #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
  ) u_apb [2] (
    .pclk    ( pclk    )
   ,.presetn ( presetn )
  );

  apb_smp_req #(
    .ADDR_WIDTH ( ADDR_WIDTH )
   ,.DATA_WIDTH ( DATA_WIDTH )
   ,.NSEL       ( 2          )
   ,.SEL_BITS   ( 12         )
  ) u_req (
    .pclk    ( pclk    )
   ,.presetn ( presetn )
   ,.start   ( start   )
   ,.busy    ( busy    )
   ,.done    ( done    )
   ,.err     ( err     )
   ,.m_apb   ( u_apb   )      // apb_if.req m_apb [NSEL]
  );

  apb_smp_regs #(
    .DATA_WIDTH ( DATA_WIDTH )
   ,.OFS_BITS   ( 12         )
   ,.WAIT       ( 0          )
  ) u_regs0 (
    .pclk    ( pclk     )
   ,.presetn ( presetn  )
   ,.s_apb   ( u_apb[0] )      // apb_if.cmp s_apb
  );
```

PENABLE / PADDR / PWDATA などは、リクエスタが全ての配列の要素に同じ値を出してかまいません
(チェックは PSEL=0 の要素の PENABLE を見ません)。

### 4.5 既存の (個別の信号の) モジュールをつなぐ

既存のモジュールを変えずに interface につなぐときは、ポートに interface の信号を 1 本ずつつなぎます。
新しいモジュール側は 1 行のままで、interface のプロトコルチェックも効きます。
次は ahb_master_mem (AHB5 マネージャ) と ahb_smp_mem をつなぐ例です (Verilator の lint で確認)。

```systemverilog
  ahb_if #(
    .ADDR_WIDTH   ( 32 )
   ,.DATA_WIDTH   ( 32 )
   ,.HPROT_WIDTH  ( 7  )   // ahb_master_mem の EXT_MEM_TYPES=1 (HPROT 7 ビット)
   ,.MASTER_WIDTH ( 4  )
  ) u_ahb (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
  );

  // ahb_master_mem に無い出力は固定値にする
  assign u_ahb.hexcl = 1'b0;

  ahb_master_mem #(
    .ADDR_WIDTH ( 32 )
   ,.DATA_WIDTH ( 32 )
  ) u_mst (
    .hclk          ( hclk            )
   ,.hresetn       ( hresetn         )
    ...
   ,.haddr         ( u_ahb.haddr     )
   ,.htrans        ( u_ahb.htrans    )
   ,.hwrite        ( u_ahb.hwrite    )
   ,.hsize         ( u_ahb.hsize     )
   ,.hburst        ( u_ahb.hburst    )
   ,.hprot         ( u_ahb.hprot     )
   ,.hnonsec       ( u_ahb.hnonsec   )
   ,.hmastlock     ( u_ahb.hmastlock )
   ,.hmaster       ( u_ahb.hmaster   )
   ,.hwdata        ( u_ahb.hwdata    )
   ,.hwstrb        ( u_ahb.hwstrb    )
   ,.hready        ( u_ahb.hready    )
   ,.hresp         ( u_ahb.hresp     )
   ,.hrdata        ( u_ahb.hrdata    )
  );

  ahb_smp_mem #(
    .DATA_WIDTH ( 32 )
  ) u_mem (
    .hclk    ( hclk    )
   ,.hresetn ( hresetn )
   ,.s_ahb   ( u_ahb   )
  );
```

どちらも使わない信号 (この例では HEXOKAY) は、`SYNTHESIS` を定義した lint で UNUSEDSIGNAL の警告になります
(シミュレーションではプロトコルチェックが読むので出ません)。

### 4.6 TB で使う (clocking block と TB_ROLE)

TB から信号を駆動するときは、interface を TB_ROLE 付きで置き、virtual interface の clocking block に書きます。

```systemverilog
  axi4_if #(
    .ADDR_WIDTH ( 32 )
   ,.DATA_WIDTH ( 64 )
   ,.ID_WIDTH   ( 4  )
   ,.TB_ROLE    ( 1  )   // TB がマネージャ側を mgr_cb で駆動する
  ) u_tb_axi (
    .aclk    ( aclk    )
   ,.aresetn ( aresetn )
  );

  axi4_smp_mem u_mem (
    .aclk    ( aclk     )
   ,.aresetn ( aresetn  )
   ,.s_axi   ( u_tb_axi )
  );

  // virtual interface の型は interface の parameter を全てそろえる (TB_ROLE / CHECK も)
  virtual axi4_if #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(4), .TB_ROLE(1)).mgr_tb vmgr;

  initial begin
    vmgr = u_tb_axi;
    @(vmgr.mgr_cb);
    vmgr.mgr_cb.awaddr  <= 32'h100;
    vmgr.mgr_cb.awvalid <= 1'b1;
    do begin
      @(vmgr.mgr_cb);
    end while( !vmgr.mgr_cb.awready );
    vmgr.mgr_cb.awvalid <= 1'b0;
  end
```

- clocking block の入力は `#1step` (エッジの直前の値)、出力はエッジの 100ps 後に変わります
- 観測だけなら TB_ROLE=0 のまま `mon_cb` を読みます (RTL 同士をつないだ interface もそのまま観測できます)
- TB_ROLE が必要な理由 : clocking block の出力に結び付いた変数は、continuous assignment で駆動してはいけません
  (IEEE 1800 の clocking block の章の最後の規則)。そこで clocking block の出力は interface の中の `tb_<信号名>`
  に書き、TB_ROLE で選んだ側だけを `assign <信号名> = tb_<信号名>;` で本物の信号につないでいます
- TB_ROLE がつながない側の clocking block に書くと、書いても信号は変わらないので、次の警告を 1 回出します

```text
[35000] %Warning: axi4_if.sv:523: tb_role_chk.u_axi4_1.g_chk_sub: axi4_if: sub_cb was written, but TB_ROLE=1 does not connect sub_cb to the bus (use TB_ROLE=2 or 3)
```

### 4.7 UVM で使う

sample/uvm/tb_axil_uvm.sv に、uvm_config_db で virtual interface を渡す例があります
(Verilator 5.052 + UVM 1800.2-2020.3.2 で確認。`make uvm`)。

```systemverilog
  // interface の parameter (TB_ROLE / CHECK も) を全部そろえた virtual interface の型
  typedef virtual axil_if #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .TB_ROLE(1)).mgr_tb axil_mgr_vif;

  // TB のトップ
  initial begin
    uvm_config_db#(axil_mgr_vif)::set(null, "uvm_test_top", "vif", u_axi);
    run_test("axil_wr_rd_test");
  end

  // テスト (またはドライバ) の build_phase
  if( !uvm_config_db#(axil_mgr_vif)::get(this,"","vif",vif) ) begin
    `uvm_fatal("NOVIF", "axil_mgr_vif is not set")
  end
```

### 4.8 合成

合成では `SYNTHESIS` を定義して読みます。信号と合成用の modport だけが残り、clocking block、TB 用の modport、
プロトコルチェック、TB_ROLE の確認は外れます。

```tcl
# Genus
read_hdl -sv -define SYNTHESIS { if/axi4_if.sv sample/axi4/axi4_smp_mgr.sv sample/axi4/axi4_smp_mem.sv sample/axi4/axi4_smp_top.sv }
elaborate axi4_smp_top

# Vivado
read_verilog -sv { if/axi4_if.sv sample/axi4/axi4_smp_mgr.sv sample/axi4/axi4_smp_mem.sv sample/axi4/axi4_smp_top.sv }
synth_design -top axi4_smp_top -part <デバイス> -verilog_define SYNTHESIS
```

`make files P=axi4` で、そのプロトコルの interface と合成できるサンプルのファイル一覧を出せます。
(合成ツールでの合成はここでは行っていません。合成で読む内容は Verilator の lint (`+define+SYNTHESIS`) で確認しています)

---------------------------------------------------------------------------------------------------

## 5. プロトコルチェック

違反は `$error` (メッセージに仕様の節を付けています)。CHECK=0 で止められます。
自己テスト (`check/tb_<p>_chk.sv`) は、正しい転送でエラーが出ないことと、違反ごとに決めたエラーが出ることを確かめます。

| interface | 主なチェック | 自己テストの違反の数 |
|---|---|---|
| axi4_if | VALID は READY まで下げず中身も変えない (IHI 0022E A3.2.1) / リセット中と解除直後のエッジは VALID=0 (A3.1.2) / AxBURST の予約値、AxSIZE がデータ幅以下、WRAP は 2・4・8・16 ビートでアライン、FIXED は 16 ビートまで、INCR は 4KB 境界をまたがない (A3.4.1) / 排他アクセスの制約 / WLAST が AWLEN+1 ビート目だけ (W が AW より先でも) / B は AW と最後の W の後、R は AR の後 (A3.3.1)、BID / RID が未完了の ID と合う、RLAST の位置 / EXOKAY は排他アクセスだけ / X・Z | 31 |
| axil_if | VALID の保持 (A3.2.1) / リセット (A3.1.2) / B は AW と W の後、R は AR の後 (A3.3.1) / EXOKAY を返さない / X・Z | 12 |
| ahb_if | 待ちの間のアドレスフェーズの保持 (ERROR の後の IDLE は可)、固定長バーストの BUSY は SEQ にだけ変えてよい (IHI 0033C 3.7.1 / 3.7.2) / 書き込みの待ちの間の HWDATA・HWSTRB の保持 (6.1.1) / HSIZE がデータ幅以下 (3.4) / アドレスのアライン (3.6) / バーストの SEQ・BUSY の位置、SEQ のアドレス (WRAP の折り返し)、制御の保持、ビート数 (ERROR の後の打ち切りは可)、1KB 境界 (3.2 / 3.6) / IDLE・BUSY には待ち無しの OKAY (3.2) / ERROR は 2 サイクル (5.1.3) / リセット中は IDLE と HREADYOUT=1 (IHI 0033A 7.1.2) / X・Z | 18 |
| apb_if | SETUP は 1 サイクルで次は ACCESS、SETUP から ACCESS と ACCESS の待ちの間は制御とデータを保持 (IHI 0024E 4.1 / 3.1.2) / 転送の次のサイクルは PENABLE=0 (3.1.1) / 読み出しの PSTRB は 0 (3.2) / リセット中は PSEL=0 (この interface の決まり) / X・Z | 6 |
| p2p_if | vld は転送まで下げず dat / strb / last も変えない / リセット中は vld=0 / X・Z | 3 |
| strm_if | TVALID は TREADY まで下げず中身も変えない (IHI 0051A 2.2.1) / リセット中と解除直後のエッジは TVALID=0 (2.7.2) / X・Z | 4 |

X・Z のチェックは 4 値のシミュレータで意味があります (Verilator は 2 値なので、X・Z のチェックは出ません)。

---------------------------------------------------------------------------------------------------

## 6. 実行方法と結果

必要なもの : Verilator 5.x (5.052 で確認)。`make uvm` だけ UVM 1800.2-2020.3.2 も必要です。

```text
cd sim
make                                     lint + 全サンプルの TB + 違反の注入 + チェックの自己テスト + TB_ROLE の確認
make lint                                interface + サンプルの RTL を -Wall で lint (SYNTHESIS あり / なしの 2 通り)
make sim                                 全サンプルの自己チェック TB
make bad                                 +BAD で各 TB にプロトコル違反を 1 つ入れ、決めたアサーションで止まること
make chk                                 チェックの自己テスト (正しい転送でエラーが出ない / 違反ごとに決めたエラーが出る)
make role                                TB_ROLE の確認 ($warning) の自己テスト
make run P=axi4                          1 つだけ実行 (P = axi4 axil ahb apb p2p strm)
make run P=axi4 PARAMS="-GDW=32 -GIW=1"  TB の parameter を変えて実行
make uvm UVM_HOME=<dir>                  UVM で使う例 (make all には入れていない。ビルドに 2 分ほど)
make files P=ahb                         そのプロトコルの interface と合成できるサンプルのファイル一覧
make clean
```

結果 (Verilator 5.052)

```text
lint axi4 (SYNTHESIS) : clean
lint axi4 (simulation) : clean
lint axil (SYNTHESIS) : clean
lint axil (simulation) : clean
lint ahb (SYNTHESIS) : clean
lint ahb (simulation) : clean
lint apb (SYNTHESIS) : clean
lint apb (simulation) : clean
lint p2p (SYNTHESIS) : clean
lint p2p (simulation) : clean
lint strm (SYNTHESIS) : clean
lint strm (simulation) : clean
[axi4] PASS
[axil] PASS
[ahb] PASS
[apb] PASS
[p2p] PASS
[strm] PASS
[axi4] +BAD : detected by a_aw_hold
[axil] +BAD : detected by a_aw_hold
[ahb] +BAD : detected by a_wait_hold
[apb] +BAD : detected by a_access_hold
[p2p] +BAD : detected by a_hold
[strm] +BAD : detected by a_hold
[axi4] SCN=0 legal traffic : no error
[axi4] violations detected : 31 / 31
[axil] SCN=0 legal traffic : no error
[axil] violations detected : 12 / 12
[ahb] SCN=0 legal traffic : no error
[ahb] violations detected : 18 / 18
[apb] SCN=0 legal traffic : no error
[apb] violations detected : 6 / 6
[p2p] SCN=0 legal traffic : no error
[p2p] violations detected : 3 / 3
[strm] SCN=0 legal traffic : no error
[strm] violations detected : 4 / 4
[role] TB_ROLE warnings for unconnected clocking blocks : 12 / 12

make uvm
UVM_INFO ../sample/uvm/tb_axil_uvm.sv(94) @ 105000: uvm_test_top [RD] addr 0x4 : data 0xcafe0001 OKAY
UVM_INFO ../sample/uvm/tb_axil_uvm.sv(100) @ 135000: uvm_test_top [RD] addr 0x40 : SLVERR
UVM_INFO ../sample/uvm/tb_axil_uvm.sv(112) @ 165000: uvm_test_top [TEST] TEST PASSED
[uvm] PASS
```

他のシミュレータの例 (ここでは実行していません)

```text
xrun -sv -timescale 1ns/1ps -top tb_axi4_smp if/axi4_if.sv sample/axi4/axi4_smp_mgr.sv sample/axi4/axi4_smp_mem.sv sample/axi4/axi4_smp_top.sv sample/axi4/tb_axi4_smp.sv
vcs -sverilog -timescale=1ns/1ps -top tb_axi4_smp if/axi4_if.sv sample/axi4/axi4_smp_mgr.sv sample/axi4/axi4_smp_mem.sv sample/axi4/axi4_smp_top.sv sample/axi4/tb_axi4_smp.sv && ./simv
```

`+BAD` (違反の注入) と `+SCN=<n>` (チェックの自己テスト) は、どのシミュレータでも同じように使えます。

---------------------------------------------------------------------------------------------------

## 7. 注意と制限

- 確認は Verilator 5.052 (2 値) だけで行っています。X・Z のチェックは 4 値のシミュレータで確認してください
- プロトコルチェックは主な規則だけです (仕様の全ての規則ではありません)。また、シミュレーションで流れた転送しか見ません。
  サインオフには 8 章の VIP を使うことを勧めます
- Verilator 5.052 の制限
  - interface の配列のポートの幅 (`$bits(m_apb[0].paddr)`) を、エラボレーションの時点では interface の既定の parameter で
    計算します。そのため、配列のポートの幅のチェックだけは `initial` で行っています (ahb_smp_ic の m_ahb、apb_smp_req の m_apb)
  - 下の階層にある interface の配列の要素 (`u_top.u_apb[0]`) を virtual interface に代入できません。
    tb_apb_smp の 1. は、階層参照で信号を数えています
  - SVA の `disable iff (!aresetn)` を、リセットを同期で使っているとみなし、SYNCASYNCNET の警告を出します
    (RTL のリセットは非同期)。Makefile の lint (SYNTHESIS なし) は、この警告だけを外しています
  - エラボレーション時の `$error` は USERERROR の警告になるので、Makefile は `-Werror-USERERROR` で止めています
- interface のクロックとリセットは、合成では使いません (未使用の警告を避ける `unused_ok` だけが残り、論理は残りません)
- AHB の DIRECT=0 のリンクは、HSEL と HREADY を dec のポートから出してください (出さないと駆動されません)
- p2p_if / strm_if はこのプロジェクト独自のプロトコルです。strm_if の TADDR は AXI4-Stream にはありません

---------------------------------------------------------------------------------------------------

## 8. 購入できるツール / IP (推奨)

| 製品 | 勧める理由 |
|---|---|
| Cadence Simulation VIP for AMBA | AXI (AXI-Lite を含む) / AHB (AHB-Lite を含む) / APB / ストリームに対応し、UVM で使え、プロトコルチェックとカバレッジモデルが付いています。この interface のチェックは主な規則だけなので、サインオフの検証はこちらで行うのが確実です |
| Cadence Jasper Formal VIP for Arm AMBA | AHB / APB / AXI / AXI-Stream の SVA のチェッカとカバーを、Jasper のフォーマル検証で使えます。シミュレーションで流れた転送だけでなく、仕様 (制約) を満たす全ての入力の組み合わせについて、RTL がプロトコルを守ることを確かめられます |
| Synopsys Verification IP for AMBA | AXI4 / AXI4-Lite / AHB / APB に対応したプロトコルチェックとカバレッジ。VCS を使う環境ならこちら |

---------------------------------------------------------------------------------------------------

## 9. 参考資料

- AMBA AXI and ACE Protocol Specification (Arm IHI 0022) : https://developer.arm.com/documentation/ihi0022/latest/
- AMBA AHB Protocol Specification (Arm IHI 0033) : https://developer.arm.com/documentation/ihi0033/latest/
- AMBA APB Protocol Specification (Arm IHI 0024) : https://developer.arm.com/documentation/ihi0024/latest/
- AMBA AXI-Stream Protocol Specification (Arm IHI 0051) : https://developer.arm.com/documentation/ihi0051/latest/
- IEEE 1800-2023 SystemVerilog : https://standards.ieee.org/ieee/1800/7743/
- clocking block の出力に結び付いた変数への continuous assignment が不可であること (Accellera sv-bc) : https://accellera.org/images/eda/sv-bc/10380.html
- Verilator の引数 (`--binary` / `--timing` / `+define+`) : https://verilator.org/guide/latest/exe_verilator.html
- Verilator の警告 (SYNCASYNCNET / UNUSEDSIGNAL) : https://verilator.org/guide/latest/warnings.html
- Genus (RTL Compiler) の `read_hdl -sv -define` : https://community.cadence.com/cadence_technology_forums/f/logic-design/2175/passing-defines-during-read_hdl
- Vivado の `synth_design -verilog_define` (UG835) : https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/synth_design
- Cadence Simulation VIP for AMBA : https://www.cadence.com/en_US/home/tools/system-design-and-verification/verification-ip/simulation-vip/amba.html
- Cadence Formal VIP for Arm AMBA : https://www.cadence.com/en_US/home/tools/system-design-and-verification/verification-ip/formal-vip/amba-arm.html
- Synopsys Verification IP for Arm AMBA : https://www.synopsys.com/verification/verification-ip/amba.html

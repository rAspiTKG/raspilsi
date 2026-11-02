## 9. 各ブロックの詳細

各ブロックについて、機能、端子表、代表的な信号の波形を示します。波形図は検証環境のテスト `b2r_wave_test`(PPC=8、clk 400 MHz、ctrl_clk 100 MHz)の波形から作ったものです。最初のフレームは 40×16 画素(入力は一様乱数、blc=800、WB: R=1.75 / B=1.5、fcs_th=4000 / fcs_gain=4)、2つ目は 64×16 画素で処理の途中にソフトリセット、3つ目は 32×16 画素で書き込み側の WREADY を 40% にしています。波形図の作り方は 13.8 にあります。

端子表の共通事項:
- `clk` / `rst_n` は映像系、`ctrl_clk` / `ctrl_rst_n` は制御系のクロックとリセットです(リセットは Low、非同期アサート・同期解除)。
- vld/busy/data のポート(`BAYER2RGB_VBD_IF`)は `.vld` / `.busy` / `.data` の3行に分けて書いています。
- `cfg_t` などの構造体の中身は `rtl/BAYER2RGB_PKG.sv` にあります。

### 9.1 BAYER2RGB(トップ階層)

8つのブロックをつなぎます(4.1)。トップ階層には論理はありません。

1フレームの流れ(40×16 画素の例)を下に示します。この図だけは、8クロックを1目盛りにまとめ、その区間に転送があれば1としています。

- 制御系で START を書くと、CDC を通って映像系に start が出ます。
- RD_DMA は読み出しバッファの空きの分だけ先にバーストを出し、CORE は読み出しデータが来ると処理を始めます。
- CORE は1ライン + 1ビート遅れて出力を始めます。WR_DMA はバースト分(このサイズでは1ライン = 8ビート)のデータがそろうと AW を出します。
- 最後のバーストの書き込み応答で frame_done になり、制御系で IRQ_STATUS.FRAME_DONE と irq が立ちます。

{{WAVE:top_frame}}

### 9.2 BAYER2RGB_AXIL_BRIDGE

AXI4-Lite スレーブを、レジスタアクセス要求(`req`)と応答(`rsp`)の vld/busy/data に変換します。

- AW、W、AR はそれぞれ1つずつ受け取って保持します(受け取ったチャネルの READY は、その要求を REG に出すまで0)。AW と W が両方そろったら書き込み要求を出します。
- 読み出しと書き込みが同時に待っているときは交互に出します。要求は1つずつ処理します。
- AXI 側の出力(READY、BVALID、RVALID、RDATA など)はすべて FF から出します。

{{PINS:BAYER2RGB_AXIL_BRIDGE}}

波形: IRQ_ENABLE(0x00C)への書き込み、VERSION(0x010)の読み出し、ACTIVE_WIDTH(0x020)と ACTIVE_HEIGHT(0x024)への書き込み。VALID から応答(BVALID / RVALID)まで4クロックです。

{{WAVE:axil_bridge}}

### 9.3 BAYER2RGB_REG

レジスタ(7章)を持ち、START と SW_RESET を CDC に1つずつ送り、映像系からのイベントで割り込みの要因とフレーム数を更新します。

- START は保留ビット `r_start_pend` に入れ、CDC が空いていて、フレームの処理中でもソフトリセットの後始末中でもないときに `o_start` を1クロック出します。
- SW_RESET は START より優先します。`o_sw_rst` を出してから、映像系の後始末が終わる(`i_evt.srst_done`)まで `r_srst_wait`=1 です。
- `o_irq` は FF から出します(IRQ_STATUS が変わった次のクロックで変わる)。
- `o_cfg` は現在のレジスタの値です。CDC が START のときに取り込みます。

{{PINS:BAYER2RGB_REG}}

波形1: START の書き込み(we=1、addr=0x000)の次のクロックで `r_start_pend`、その次で `o_start`。CDC が受け取ると `i_cdc_busy` が受け渡しの間1になります。`r_frm_busy` は frame_done まで1です。その後のアクセスはソフトウェアが IRQ_STATUS(0x008)を読んでいるところです。

{{WAVE:reg_start}}

波形2: `i_evt.frame_done` で `r_frm_busy` が0、IRQ_STATUS[0] が1、FRAME_COUNT が+1 になり、次のクロックで `o_irq` が1になります。ソフトウェアが IRQ_STATUS を読み(we=0)、1を書く(we=1)と IRQ_STATUS[0] が0になり、次のクロックで `o_irq` が0になります。

{{WAVE:reg_irq}}

### 9.4 BAYER2RGB_CDC

制御系と映像系の間で、設定・要求・イベントを受け渡します。多ビットのデータは同期化セルを通さず、トグルの要求と応答(ACK)だけを2段同期化します(MCP 方式 [R8])。

| 方向 | 内容 | 方式 |
|---|---|---|
| 制御系 → 映像系 | START(+ 設定 `cfg_t`)、SW_RESET | 要求トグル `r_req_c` → 2段同期 → 映像系で変化を検出。映像系が受け取った値(`r_req_d_v`)を ACK として返す。要求中は `r_pl_cfg` を変えない |
| 映像系 → 制御系 | frame_done、rd_err、wr_err、srst_done | イベントを保留ビット `r_ev_pend_v` にためて、まとめて1回のハンドシェイクで送る。送る順番は入れ替わらない |

- START: REG_UPDATE=1 なら `i_cfg` を `r_pl_cfg` に取り込んでから要求を出します。映像系は変化を検出したクロックで `r_pl_cfg` を `r_cfg_v`(フレームの設定)に移し、`o_ctl.start` を1クロック出します。
- SW_RESET: 映像系で `o_ctl.sw_rst` を1クロック出し、`r_abort_v`=1 にします。RD_DMA と WR_DMA の busy が両方0になったら `srst_done` イベントを送ります。
- 制御系の `o_busy` は要求を出してから ACK が戻るまで1です。REG はこの間に次の要求を出しません。

{{PINS:BAYER2RGB_CDC}}

波形1(START): 制御系で `i_start` → `r_req_c` が反転、`o_busy`=1。映像系で2段同期後の `s_req_v` が変わり、次のクロックで `o_ctl.start` と設定(`o_ctl.cfg.width` が 3840 → 40)が出ます。`r_req_d_v` が制御系で同期化されて `s_ack_c` になり、`o_busy` が0になります。

{{WAVE:cdc_start}}

波形2(イベント): 映像系の `i_wr_evt.frame_done` を保留ビットに入れ、次のクロックで `r_ev_req_v` を反転して送ります。制御系では同期化後の `s_ev_req_c` の変化で `o_evt.frame_done` を1クロック出します。ACK(`s_ev_ack_v`)が戻ると `r_ev_busy_v` が0になり、次のイベントを送れます。

{{WAVE:cdc_event}}

波形3(ソフトリセット): SW_RESET の書き込みで `r_srst_pend` → `o_sw_rst`、`r_srst_wait`=1。映像系で `o_ctl.sw_rst` が出ると、次のクロックで CORE のクリア(`s_clr`)と DMA の後始末(`r_abort`)が始まります。WR_DMA は発行済みのバーストの応答を待ち(`r_ost` が 2 → 1 → 0)、DMA が止まると `r_abort_v` が0になって `srst_done` を送ります。制御系で `i_evt.srst_done` を受けると `r_srst_wait` が0になり、STATUS.BUSY が0になります。

{{WAVE:sw_reset}}

### 9.5 BAYER2RGB_AXIM_RD_BRIDGE

読み出し要求(`ar`)と読み出しデータ(`r`)の vld/busy/data を AXI4 の AR / R に変換します。

- AR と R はそれぞれ2段スキッドバッファ(9.20)を通します。AXI 側の出力はすべて FF から出ます。
- ARID=0、ARSIZE=4(16バイト)、ARBURST=INCR、ARLOCK=0 に固定します。RID は見ません。
- 遅れ: `ar` → ARVALID が1クロック、RVALID → `r` が1クロック。

{{PINS:BAYER2RGB_AXIM_RD_BRIDGE}}

波形: フレームの始めに4バースト(1ライン = 40画素 × 2バイト = 80バイト = 5ビート、ARLEN=4、SRC_STRIDE=80)を続けて出し、RDATA を1クロック遅れで `r` に渡します。

{{WAVE:axim_rd_bridge}}

### 9.6 BAYER2RGB_RD_DMA

Bayer 画像をライン単位のバーストで読み出し、PPC 画素ずつ CORE に送ります。

- バースト長 = min(16, ラインの残りのビート数, 4KB 境界までのビート数)。ラインの終わりで次のライン(+SRC_STRIDE)に移ります。
- 読み出しバッファ(SFIFO、SRAM 64ビート)の空き(`r_credit`)をバースト長だけ予約してから AR を出します。R は止めません(RREADY=1)。
- 同時発行は4バーストまで(`r_ost`)。
- 1ビート(16バイト = 8画素)の各16bitの下位14bitを画素とし、PPC 画素ずつ CORE に送ります(PPC<8 のときは1ビートを 8/PPC 回に分ける)。
- テストパターンのときはメモリを読まず、値0のビートを同じ数だけ送ります。
- RRESP ≠ OKAY のとき `o_evt.rd_err` を1クロック出します(データはそのまま使う)。
- ソフトリセット: 新しい AR を止め、発行済みのバーストのデータを受けて捨てます(`r_abort`)。出力レジスタに残った AR は AXI の規則どおり出し切ります。

{{PINS:BAYER2RGB_RD_DMA}}

波形: `i_ctl.start` で動き始め、空き 64 から 5ビートずつ予約しながら4バーストまで出します(`r_credit` 64 → 59 → 54 → 49 → 44、`r_ost` 0 → 4)。データが届くと CORE に送り(`pix.vld`)、CORE が受け取ったビートの分だけ空きが戻ります。`pix.busy`=1 は CORE が行末の掃き出しなどで入力を受けないクロックです。

{{WAVE:rd_dma}}

### 9.7 BAYER2RGB_CORE

画像処理のパイプラインです(4.2)。IN_CTRL がステップを発行し、その後ろは固定の遅れで止まらずに流れます。

| 段 | ブロック | 遅れ | 出力 |
|---|---|---:|---|
| 0 | IN_CTRL | - | `s_stp0`(stp_t) |
| 1 | BLC | 1 | `s_stp1`(stp_t) |
| 2 | WB | 2 | `s_stp2`(stp_t) |
| 3 | LBUF | 2 | `s_win`(win_t) |
| 4 | DMSC | 2 | `s_dm`(dm_t) |
| 5 | FCS | 3 | `s_fc`(fc_t) |
| 6 | GAMMA | 3 | `s_gm`(gm_t) |
| 7 | OUT_FMT | 1 | `s_of_vld` / `s_of_data`(obeat_t) |
| 8 | OUT_FIFO | 3(書き込みから読み出し側まで) | `rgb`(vld/busy/data) |

設定(`s_cfg`)とソフトリセットのクリア(`s_clr`)は IN_CTRL で1段受け直してから各段に配ります。各段は `vld` などの制御だけリセットし、データの FF はリセットしません。

{{PINS:BAYER2RGB_CORE}}

波形: ライン1・列1 のステップ(最初の出力になる)が各段を進む様子です。LBUF の窓はライン1の列1のステップで最初に出ます(出力ライン0・列0)。IN_CTRL の出力から OUT_FMT の出力まで 1+2+2+2+3+3+1 = 14 クロックです。出力 FIFO に入ってから3クロックで `rgb.vld` が1になります。

{{WAVE:core_pipe}}

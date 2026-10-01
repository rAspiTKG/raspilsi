# AXI4-Full データ素通しモジュール / p2p bridge

AXI4-Full でデータを受け取り、そのまま出力するモジュール 3 構成と、
AXI4-Full ⇄ valid/busy 方式 p2p インタフェースの bridge 1 構成。
いずれも AW / W / B / AR / R の 5 チャネル全てで VALID/READY ハンドシェイクを実装している。

- 言語: SystemVerilog
- デフォルト: `ADDR_WIDTH=32` / `DATA_WIDTH=64` / `ID_WIDTH=4`

## ファイル構成

```
rtl/
  axi4_full_slave_mem.sv        ... AXI4-Full スレーブ + 内部メモリ (ループバック)
  axi4_full_passthrough.sv      ... AXI4-Full スレーブ → マスタ の素通し
  axi4_skid_buffer.sv           ... 上記が使う 1 チャネル分のスキッドバッファ
  axi4_full_slave_stream.sv     ... AXI4-Full スレーブ → 簡易ストリーム出力
  axi4_full_to_p2p_bridge.sv    ... AXI4-Full ⇄ p2p (vld/busy) bridge
  axi4_sync_fifo.sv             ... 上記が使う同期 FIFO
tb/
  axi4_full_master_bfm.sv       ... 検証用 AXI4-Full マスタ BFM
  p2p_source_bfm.sv             ... p2p 送信側モデル
  p2p_sink_bfm.sv               ... p2p 受信側モデル
  tb_axi4_full_slave_mem.sv
  tb_axi4_full_passthrough.sv
  tb_axi4_full_slave_stream.sv
  tb_axi4_full_to_p2p_bridge.sv
sim/
  Makefile                      ... Verilator 5.x 用
```

## 各モジュール

### 1. `axi4_full_slave_mem`

Write で受け取ったデータを内部メモリに格納し、同一アドレスの Read でそのまま返す。

| 項目 | 内容 |
| --- | --- |
| ポート | `s_axi_*` (AXI4-Full スレーブ) のみ |
| パラメータ | `ADDR_WIDTH` / `DATA_WIDTH` / `ID_WIDTH` / `MEM_DEPTH` |
| バースト | FIXED / INCR / WRAP |
| バイトイネーブル | `WSTRB` 対応 |
| メモリ | 同期読み出し (次ビートを 1 拍先読み) の simple dual-port |

制限: アウトスタンディングは Write/Read 各 1 本。W チャネルは AW 受領後に `WREADY`
をアサートする (W 先行は受け付けない。スレーブが `WREADY` を下げるのは AXI 的に合法)。

### 2. `axi4_full_passthrough`

スレーブポートで受けたトランザクションをマスタポートへ素通しする。
5 チャネルそれぞれに `axi4_skid_buffer` を 1 個ずつ置いている。

| 項目 | 内容 |
| --- | --- |
| ポート | `s_axi_*` (スレーブ) + `m_axi_*` (マスタ) |
| パラメータ | `ADDR_WIDTH` / `DATA_WIDTH` / `ID_WIDTH` / `BYPASS` |
| `BYPASS=0` | 全チャネルにスキッドバッファ挿入 (完全レジスタ出力、1beat/clk 維持) |
| `BYPASS=1` | 全チャネル単純結線 (組合せ素通し) |

スキッドバッファの性質:

- `m_valid` は `s_valid` から組合せで生成されない
- `s_ready` は `m_ready` から組合せで生成されない
- 上流/下流間に組合せパスが無いので、タイミング的に切り離しつつ挿入できる

制限: USER 信号 (`AxUSER`/`WUSER`/`BUSER`/`RUSER`) は未対応。

### 3. `axi4_full_slave_stream`

Write データを `data/valid/ready` の簡易ストリームへ素通しする。

| 項目 | 内容 |
| --- | --- |
| ポート | `s_axi_*` (スレーブ) + `m_t*` (ストリーム出力) |
| ストリーム | `m_tdata` / `m_tstrb` / `m_tlast` / `m_tid` / `m_taddr` / `m_tvalid` / `m_tready` |
| バックプレッシャ | `m_tready=0` の間は `WREADY=0` を返して上流を止める |
| Read チャネル | ダミー応答 (`RD_DUMMY_DATA` を `ARLEN+1` ビート、`RRESP` は `RD_RESP`) |

`m_taddr` は各ビートのアドレス (FIXED / INCR / WRAP のアドレス生成込み) をサイドバンドで
出しているので、下流でアドレスが必要な場合に使える。

### 4. `axi4_full_to_p2p_bridge`

AXI4-Full スレーブと、valid/busy 方式の p2p インタフェースを双方向に橋渡しする。

```
  AXI4-Full Write バースト --[送信 FIFO]--> p2p 出力 (vld/busy/dat)
  p2p 入力 (vld/busy/dat) --[受信 FIFO]--> AXI4-Full Read バースト
```

| 項目 | 内容 |
| --- | --- |
| ポート | `s_axi_*` (スレーブ) + `p2p_out_*` + `p2p_in_*` + FIFO レベル出力 |
| p2p 出力 | `p2p_out_dat` / `p2p_out_strb` / `p2p_out_last` / `p2p_out_vld` / `p2p_out_busy` |
| p2p 入力 | `p2p_in_dat` / `p2p_in_vld` / `p2p_in_busy` |
| `WR_FIFO_DEPTH` / `RD_FIFO_DEPTH` | 送信 / 受信 FIFO の深さ (2 以上)。既定 16 |
| `B_WAIT_DRAIN` | 0: 全ビートを送信 FIFO に積んだ時点で B 応答 (既定) / 1: p2p へ出し切るまで待つ |
| `RD_TIMEOUT` | 0: 無効 (既定) / >0: 指定サイクル p2p 入力が来なければ残りビートを SLVERR で返し切る |

`p2p_out_strb` / `p2p_out_last` は `WSTRB` / `WLAST` をそのまま出すサイドバンドで、
不要なら未接続でよい。

#### p2p プロトコル (busy = ready の反転)

- 送信側が `dat` と `vld` を、受信側が `busy` を駆動する
- `vld=1` かつ `busy=0` のクロック立ち上がりで 1 ビート転送成立
- `vld` は `busy` を待たずにアサートしてよく、転送成立まで下げてはならない

本モジュールでは組合せパスを作らない形にしている。

| 信号 | 生成元 | 依存 |
| --- | --- | --- |
| `p2p_out_vld` | 送信 FIFO の `rd_valid` (登録値) | `p2p_out_busy` に依存しない |
| `p2p_in_busy` | 受信 FIFO の満杯 (登録値) | `p2p_in_vld` に依存しない |
| `s_axi_wready` | 送信 FIFO の空き | `p2p_out_busy` には直結しない |

`p2p_out_busy` が立っている間は送信 FIFO に溜まり、満杯になると `WREADY` が下がって
AXI 側のマスタが止まる。逆に p2p 入力が来ないまま Read バーストが来た場合は
`RVALID` を上げずに待つ (AXI 的に合法)。`RD_TIMEOUT` を設定すると、その状態が続いた
ときに残りビートを `SLVERR` で返し切って AXI バスのハングを避けられる。
ただしタイムアウト後は p2p ストリームとの同期が失われるため、リセットで復帰させる前提。

制限:

- アドレス属性 (`AWADDR` / `ARADDR` / `AxSIZE` / `AxBURST` 等) は無視する。
  FIFO ポートとして振る舞うため、転送ビート数は `AWLEN` / `ARLEN` だけが決める
- アウトスタンディングは Write / Read 各 1 本
- p2p 側のデータ幅は `DATA_WIDTH` と同一 (幅変換なし)

## ハンドシェイクの実装方針

AXI4 spec A3.2.1 の規則に沿っている。

- VALID は READY を待たずにアサートしてよい (VALID → READY の組合せ依存は禁止)
- READY は VALID を待ってもよい
- VALID は握手が成立するまでデアサートしない

`axi4_full_slave_stream` では `m_tvalid` を `WVALID` から生成し (VALID → VALID なので可)、
`WREADY` を `m_tready` から生成している (READY → READY なので可)。組合せループは発生しない。

## シミュレーション

Verilator 5.x で確認済み。

```
cd sim
make            # 7 パターン全て実行
make tb1        # axi4_full_slave_mem
make tb2        # axi4_full_passthrough (BYPASS=0)
make tb2_byp    # axi4_full_passthrough (BYPASS=1)
make tb3        # axi4_full_slave_stream
make tb4        # axi4_full_to_p2p_bridge (B_WAIT_DRAIN=0, RD_TIMEOUT=0)
make tb4_drain  # axi4_full_to_p2p_bridge (B_WAIT_DRAIN=1)
make tb4_to     # axi4_full_to_p2p_bridge (RD_TIMEOUT=200)
```

Xcelium で流す場合は例えば以下。

```
xrun -sv rtl/*.sv tb/axi4_full_master_bfm.sv tb/tb_axi4_full_slave_mem.sv \
     -top tb_axi4_full_slave_mem
```

### テスト項目

| TB | 項目 |
| --- | --- |
| `tb_axi4_full_slave_mem` | INCR 8 ビート / 単一ビート / FIXED / WRAP (折り返し先アドレスも確認) / WSTRB 部分書き込み |
| `tb_axi4_full_passthrough` | INCR 8 ビート / WRAP 4 ビート / 16 ビート + 上下流の W ビート数一致 / `BYPASS=0,1` 両方 |
| `tb_axi4_full_slave_stream` | INCR 8 ビート / ランダムバックプレッシャ 16 ビート / WRAP の `m_taddr` / Read ダミー応答 |
| `tb_axi4_full_to_p2p_bridge` | Write 8 ビート→p2p 出力 (dat/strb/last) / ランダム busy 16 ビート / 固定 busy で FIFO 溢れ 24 ビート (`WREADY` が下がること) / p2p 入力先行の Read 8 ビート / Read 先行のアンダーラン + 送信側ギャップ / `RD_TIMEOUT>0` での SLVERR 返し切り |

いずれも `BRESP` / `RRESP` / `BID` / `RID` / `RLAST` の位置を併せて確認している。

### BFM のタイミング規約

シミュレータ間で評価順序に依存しないよう、以下の規約にしている。

- 駆動: `negedge aclk` で更新 (DUT が観測する `posedge` では既に安定)
- 観測: 握手 (`VALID && READY`) を `posedge` の `always_ff` でサンプルし、その結果を
  `negedge` でポーリング

`posedge` で相手側の信号を直接読むと、シミュレータによって NBA 更新前後のどちらを
読むかが変わり握手を取りこぼす。実ハードと同じ観測点にすることで回避している。

## 参考

- AMBA AXI Protocol Specification (Arm IHI 0022): https://developer.arm.com/documentation/ihi0022/latest/
  - A3.2 Basic transaction handshake — VALID/READY 規則
  - A3.4.1 Address structure — バーストアドレス生成の疑似コード
  - A3.4.4 Read and write response structure — RESP エンコード
- Cadence Stratus HLS (`cynw_p2p` 相当の vld/busy チャネル): https://www.cadence.com/en_US/home/tools/digital-design-and-signoff/synthesis/stratus-high-level-synthesis.html

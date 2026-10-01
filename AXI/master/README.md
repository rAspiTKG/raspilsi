# AXI4-Full マスタ版 (copy / stream / p2p bridge)

前回までのスレーブ版 (DUT が AXI スレーブとして要求を受ける側) を、DUT 自身が
AXI4-Full マスタとしてトランザクションを発行する構成に作り直したもの。
AW / W / B / AR / R の 5 チャネル全てで VALID/READY ハンドシェイクを実装している。

- 言語: SystemVerilog
- デフォルト: `ADDR_WIDTH=32` / `DATA_WIDTH=64` / `ID_WIDTH=4` / `MAX_BURST=16`
- 制御: valid/ready のコマンドポート (アドレス + ビート数) で起動し、`done` / `done_err` で完了通知

## スレーブ版との対応

| スレーブ版 | マスタ版 | 動作 |
| --- | --- | --- |
| `axi4_full_slave_mem` | `axi4_full_master_copy` | AXI Read → 内部バッファ → AXI Write (src → dst のメモリコピー) |
| `axi4_full_slave_stream` | `axi4_full_master_stream` | ストリーム入力 → AXI Write / AXI Read → ストリーム出力 |
| `axi4_full_to_p2p_bridge` | `axi4_full_master_p2p_bridge` | p2p 入力 → AXI Write / AXI Read → p2p 出力 |
| `axi4_full_passthrough` | (据え置き) | 元からスレーブポートとマスタポートの両方を持つため変更なし |

## ファイル構成

```
rtl/
  axi4_mst_wr_engine.sv           ... 共通: マスタ書き込みエンジン (AW / W / B)
  axi4_mst_rd_engine.sv           ... 共通: マスタ読み出しエンジン (AR / R)
  axi4_sync_fifo.sv               ... 共通: 同期 FIFO
  axi4_full_master_copy.sv        ... 1. コピーエンジン
  axi4_full_master_stream.sv      ... 2. ストリーム <-> AXI4 マスタ
  axi4_full_master_p2p_bridge.sv  ... 3. p2p (vld/busy) <-> AXI4 マスタ
  axi4_full_passthrough.sv        ... 4. スレーブ → マスタ素通し (据え置き)
  axi4_skid_buffer.sv             ... 4. が使うスキッドバッファ
tb/
  axi4_slave_mem_model.sv         ... 検証用 AXI4 スレーブ + メモリ
                                      (ストール / READY の出し方 / SLVERR 注入 / プロトコル違反検出)
  p2p_source_bfm.sv               ... p2p 送信側モデル
  p2p_sink_bfm.sv                 ... p2p 受信側モデル
  tb_axi4_full_master_copy.sv
  tb_axi4_full_master_stream.sv
  tb_axi4_full_master_p2p_bridge.sv
  axi4_full_master_bfm.sv         ... passthrough 用 (据え置き)
  axi4_full_slave_mem.sv          ... passthrough 用 (据え置き)
  tb_axi4_full_passthrough.sv     ... passthrough 用 (据え置き)
sim/
  Makefile                        ... Verilator 5.x 用
uvm/                              ... Verilator + UVM 環境 (axi4_full_master_copy)
  README.md                       ... 構成・実行方法・Verilator での注意点
  tb/  sim/
```

## 共通エンジン

3 つのトップはいずれも、下の 2 つのエンジンと FIFO の組み合わせで作っている。

### `axi4_mst_wr_engine` (AW / W / B)

```
cmd (addr, len) --> [バースト分割] --> AW
s_data/s_valid/s_ready --------------> W  (WLAST は各バーストの最終ビート)
                   s_count (データ源に溜まっているビート数)
B --> done / done_err
```

1. 転送を INCR バーストに分割する。1 バーストの長さは
   `min(残りビート数, MAX_BURST, 4KB 境界までのビート数)` (AXI4 spec A3.4.1)
2. `s_count >= バースト長` になってから AW を出す
3. AW と W を同時に出し、B を受けてから次のバーストへ進む (アウトスタンディング 1)
4. 全バースト完了で `done` を 1 サイクル。`BRESP != OKAY` または `BID` 不一致が
   1 回でもあれば `done_err=1`

2 は設計上の選択。AW を出した後に W を出せない状態が続くと、W に ID が無い AXI4 では
スレーブ (やインターコネクト) の書き込みチャネルを他のマスタごと塞いでしまうので、
1 バースト分のデータが揃うまで AW を出さない。

### `axi4_mst_rd_engine` (AR / R)

```
cmd (addr, len) --> [バースト分割] --> AR
R --> m_data/m_last/m_valid/m_ready  (m_last はコマンドの最終ビート)
      m_space (受け側 FIFO の空き)
```

- バースト分割は書き込み側と同じ
- `m_space >= バースト長` のときだけ AR を出す。R を受けきれずに `RREADY` を
  下げ続けてバスを塞ぐことがない
- `RRESP != OKAY` / `RID` 不一致 / `RLAST` の位置ずれのいずれかで `done_err=1`

### 出力する AXI 属性 (固定)

| 信号 | 値 |
| --- | --- |
| `AxSIZE` | `log2(DATA_WIDTH/8)` (常にバス幅) |
| `AxBURST` | INCR |
| `AxLEN` | 上記の分割結果 - 1 (最大 `MAX_BURST-1`) |
| `AxCACHE` | `4'b0011` (Normal Non-cacheable Bufferable) |
| `AxPROT` / `AxLOCK` / `AxQOS` / `AxREGION` | 0 |
| `WSTRB` | 全バイト有効 |
| `AWID` / `ARID` | パラメータ (`WR_ID` / `RD_ID`) |

### ハンドシェイクの実装方針 (AXI4 spec A3.2.1)

マスタ側の義務は「VALID は READY を待たずに出し、握手が成立するまで下げない」こと。

| 信号 | 生成元 | 依存 |
| --- | --- | --- |
| `AWVALID` / `ARVALID` | ステートの登録値 | READY に依存しない |
| `WVALID` | ステート && データ源の valid | VALID → VALID (READY に依存しない) |
| データ源の ready | ステート && `WREADY` | READY → READY |
| `RREADY` | ステート && 下流の ready | READY は VALID を待ってもよい |
| `BREADY` | B 待ちステート | 同上 |

データ源 (FIFO) が valid を保持する限り `WVALID` も保持されるので、握手前に下がることはない。

## 各モジュール

### 1. `axi4_full_master_copy`

```
      cmd (src, dst, len)
           |
  axi4_mst_rd_engine --> [ FIFO BUF_DEPTH ] --> axi4_mst_wr_engine
     AR / R                                       AW / W / B
```

| 項目 | 内容 |
| --- | --- |
| コマンド | `cmd_valid` / `cmd_ready` / `cmd_src` / `cmd_dst` / `cmd_len` (ビート数) |
| ステータス | `busy` / `done` (1 サイクル) / `done_err` |
| AXI | `m_axi_*` (マスタ。Read と Write を同時に使う) |
| パラメータ | `ADDR_WIDTH` / `DATA_WIDTH` / `ID_WIDTH` / `RD_ID` / `WR_ID` / `LEN_WIDTH` / `MAX_BURST` / `BUF_DEPTH` |

- 両エンジンがアイドルのときだけ `cmd_ready=1`。同じサイクルで両方にコマンドを渡す
- Read が先行して FIFO を満たし、Write は 1 バースト分溜まり次第追いかける (並行動作)
- `done` は Write 完了時。`done_err` は Read / Write どちらかのエラーで 1
- **`BUF_DEPTH >= 2*MAX_BURST` が必要** (シミュレーション開始時に `initial` 内の `$error` で
  チェック。合成ツールはこのチェックを無視するので、パラメータ変更時は注意)。
  src と dst で 4KB 境界の位置が違うと Read と Write のバースト境界がずれ、
  FIFO が小さいと「Write はデータ不足、Read は空き不足」で両方が止まり得る

```
例: MAX_BURST=16, BUF_DEPTH=16, src=0x1000 (境界まで 512 ビート), dst=0x1FC8 (境界まで 7 ビート)
  Read  16 ビート → FIFO=16
  Write  7 ビート → FIFO=9
  Read  は空き 16 待ち (空き 7) / Write は 16 ビート待ち (格納 9) → デッドロック
```

### 2. `axi4_full_master_stream`

```
s_tdata/s_tvalid/s_tready       --> [WR FIFO] --> axi4_mst_wr_engine --> AW/W/B
m_tdata/m_tlast/m_tvalid/m_tready <-- [RD FIFO] <-- axi4_mst_rd_engine <-- AR/R
```

| 項目 | 内容 |
| --- | --- |
| Write コマンド | `wr_cmd_valid` / `wr_cmd_ready` / `wr_cmd_addr` / `wr_cmd_len`、`wr_busy` / `wr_done` / `wr_done_err` |
| Read コマンド | `rd_cmd_valid` / `rd_cmd_ready` / `rd_cmd_addr` / `rd_cmd_len`、`rd_busy` / `rd_done` / `rd_done_err` |
| 入力ストリーム | `s_tdata` / `s_tvalid` / `s_tready` |
| 出力ストリーム | `m_tdata` / `m_tlast` / `m_tvalid` / `m_tready` |
| パラメータ | 上記 + `WR_FIFO_DEPTH` / `RD_FIFO_DEPTH` (既定 32、`>= MAX_BURST` が必要。copy と同じく `initial` でチェック) |

- Write と Read は独立したコマンドで同時に動く (`WR_ID=0` / `RD_ID=1`)
- `s_tready` は WR FIFO の空き、`m_tvalid` は RD FIFO の格納有無から作る (登録値)。
  ストリーム側と AXI 側の間に組合せパスは無い
- コマンドより先にデータを流してもよい (WR FIFO に溜まる)
- `wr_done` は最終 B 受領時 (メモリへの書き込み完了)。`rd_done` は最終 R 受領時で、
  データは RD FIFO に残っている場合があるので、ストリーム側の終端は `m_tlast` で判断する

### 3. `axi4_full_master_p2p_bridge`

2. のストリーム側を、前回と同じ valid/busy 方式 (busy = ready の反転、Stratus HLS の
`cynw_p2p` 相当) に置き換えたもの。

| 項目 | 内容 |
| --- | --- |
| p2p 入力 (Write データ) | `p2p_in_dat` / `p2p_in_vld` / `p2p_in_busy` |
| p2p 出力 (Read データ) | `p2p_out_dat` / `p2p_out_last` / `p2p_out_vld` / `p2p_out_busy` |
| ステータス | `wr_fifo_level` / `rd_fifo_level` (FIFO 格納数) |
| コマンド / パラメータ | 2. と同じ |

- `vld=1` かつ `busy=0` のクロック立ち上がりで 1 ビート転送成立
- `p2p_in_busy` は WR FIFO 満杯 (登録値)、`p2p_out_vld` は RD FIFO の格納有無 (登録値)。
  `p2p_out_busy` / `p2p_in_vld` からの組合せパスは無い
- `p2p_out_last` は Read コマンドごとの最終ビートで 1 (不要なら未接続でよい)

### 4. `axi4_full_passthrough` (据え置き)

前回のものをそのまま同梱している (スレーブポート → スキッドバッファ → マスタポート)。

## 接続例

```systemverilog
axi4_full_master_copy #(
  .ADDR_WIDTH(32)
 ,.DATA_WIDTH(64)
 ,.ID_WIDTH(4)
 ,.RD_ID(0)
 ,.WR_ID(1)
 ,.LEN_WIDTH(16)
 ,.MAX_BURST(16)
 ,.BUF_DEPTH(32)
) u_copy (
  .aclk(aclk)
 ,.aresetn(aresetn)
 ,.cmd_valid(cmd_valid)
 ,.cmd_ready(cmd_ready)
 ,.cmd_src(cmd_src)
 ,.cmd_dst(cmd_dst)
 ,.cmd_len(cmd_len)
 ,.busy(busy)
 ,.done(done)
 ,.done_err(done_err)
 ,.m_axi_awid(m_axi_awid)
 ,.m_axi_awaddr(m_axi_awaddr)
  // ... 以下 m_axi_* を AXI スレーブ (インターコネクト / メモリコントローラ) へ
);
```

コマンドのタイミング (サイクル 0 の終わりのクロックエッジで `cmd_valid && cmd_ready` が成立):

```
サイクル    0    1    2   ...  n    n+1
cmd_valid   1    0    0   ...  0    0
cmd_ready   1    0    0   ...  0    1     受付後は完了まで 0
busy        0    1    1   ...  1    0
done        0    0    0   ...  1    0     busy の最終サイクルに 1 サイクルだけ 1
done_err    -    -    -   ...  E    -     E = エラー有無。done と同じサイクルで見る
```

## 使用上の制約

- アドレスはバス幅 (`DATA_WIDTH/8` バイト) にアラインすること (下位ビットは無視)
- `cmd_len` はビート数 (0 なら即 `done`)。最大 `2^LEN_WIDTH - 1`
- アウトスタンディングは Write / Read 各 1 本。スループットはスレーブのレイテンシで
  頭打ちになる (B / R の往復ごとに数サイクル空く)
- WSTRB は常に全有効。バイト単位の部分書き込み・ナロー転送・WRAP / FIXED は出さない
- USER 信号 (`AxUSER` / `WUSER` / `BUSER` / `RUSER`) は未対応
- エラー応答を受けても転送は最後まで続け、完了時に `done_err` で通知する

## シミュレーション (簡易 TB)

Verilator 5.x で確認済み。

```
cd sim
make            # 4 本全て実行
make copy       # axi4_full_master_copy
make stream     # axi4_full_master_stream
make p2p        # axi4_full_master_p2p_bridge
make passthru   # axi4_full_passthrough (据え置き)
```

Xcelium で流す場合は例えば以下。

```
xrun -sv -timescale 1ns/1ps \
     rtl/axi4_sync_fifo.sv rtl/axi4_mst_wr_engine.sv rtl/axi4_mst_rd_engine.sv \
     rtl/axi4_full_master_copy.sv tb/axi4_slave_mem_model.sv tb/tb_axi4_full_master_copy.sv \
     -top tb_axi4_full_master_copy
```

### スレーブモデル `axi4_slave_mem_model`

DUT がマスタなので、TB 側は AXI スレーブ + メモリのモデルを持つ。
実行中に以下のノブを切り替えられる。

| ノブ | 内容 |
| --- | --- |
| `stall_pct` | AWREADY / WREADY / ARREADY / RVALID / BVALID をランダムに止める割合 (%) |
| `ready_wait_valid` | READY を VALID を見てから上げる (スレーブとして合法な実装) |
| `err_lo` / `err_hi` | この範囲を含むバーストに SLVERR を返す |

あわせてマスタ側の違反を検出する。

- 握手前の VALID デアサート、握手待ち中のペイロード変化 (AW / W / AR)
- 4KB 境界跨ぎ、`AxLEN+1 > MAX_BURST`、`AxSIZE` / `AxBURST` の不正

`ready_wait_valid` は、VALID が READY を待つ (A3.2.1 違反の) マスタを見つけるためのもの。
READY を先に出すスレーブとしか繋いでいないと、この違反はシミュレーションで露見しない。

### テスト項目

| TB | 項目 |
| --- | --- |
| `tb_axi4_full_master_copy` | 1 バースト / src・dst とも 4KB 跨ぎ (分割位置が違う) / 50% ストールで 300 ビート / 1 ビート・0 ビート / SLVERR 注入 (dst 側・src 側) / 連続コマンドと `cmd_ready` / READY が VALID を待つスレーブ |
| `tb_axi4_full_master_stream` | Write 32 → Read 32 (データと `m_tlast`) / 4KB 跨ぎ / ストール + 入力ギャップ + 出力バックプレッシャ / コマンドより先にデータ / Write と Read の同時実行 / SLVERR 注入 / READY が VALID を待つスレーブ |
| `tb_axi4_full_master_p2p_bridge` | 上と同じ項目を p2p (vld/busy) で |
| `tb_axi4_full_passthrough` | 前回と同じ |

いずれもデータ一致に加えて、発行されたバーストの本数・長さ (期待する分割と一致するか)、
`done_err`、プロトコル違反 0 件を確認している。

### 実行結果 (この環境)

Verilator 5.052 で 4 本とも PASS (警告 0 件)。RTL は 4 トップとも
`verilator --lint-only -Wall` で警告 0 件。

```
$ make
[INFO] TEST1 : AR bursts=1 AW bursts=1
[INFO] TEST2 : AR bursts=7 AW bursts=7
[INFO] TEST3 : AR bursts=19 AW bursts=19
  ...
[INFO] AR bursts=42 AW bursts=43 R beats=617 W beats=617 max_arlen=15 max_awlen=15
=== tb_axi4_full_master_copy : TEST PASSED ===
[INFO] AR bursts=30 AW bursts=32 R beats=442 W beats=462 max_arlen=15 max_awlen=15
=== tb_axi4_full_master_stream : TEST PASSED ===
[INFO] AR bursts=30 AW bursts=32 R beats=442 W beats=462 max_arlen=15 max_awlen=15
=== tb_axi4_full_master_p2p_bridge : TEST PASSED ===
=== tb_axi4_full_passthrough : TEST PASSED ===
```

TEST2 (src=0x2F80 / dst=0x40FC8 から 100 ビート) のバースト本数は、手計算の分割
(src: 16+16×5+4 → 7 本、dst: 7+16×5+13 → 7 本) と一致している。

参考までに、ストール無しのスレーブで 300 ビートのコピー (UVM の smoke で計測) は約 397
サイクル (約 0.76 beat/cycle)。アウトスタンディング 1 のため、バーストごとに AR→R と
W→B の往復の数サイクルが乗る。

### 検証環境の検出力確認

DUT のコピーにバグを 1 箇所ずつ入れて `tb_axi4_full_master_copy` を流した結果。

| 入れたバグ | 結果 | 検出したもの |
| --- | --- | --- |
| なし | PASS | |
| 4KB 境界でバーストを分割しない | FAIL | スレーブモデルのプロトコル違反検出 |
| WVALID を WREADY が来てから出す | FAIL | `ready_wait_valid` モードでデッドロック → タイムアウト |
| WVALID を握手前に下げる | FAIL | タイムアウト + データ不一致 |
| W データの 1 ビットを反転 | FAIL | データ比較 |
| RRESP を無視 | FAIL | `done_err` 不一致 |
| 2 バースト目以降の ARADDR をずらす | FAIL | データ比較 |

UVM 環境での同様の確認は `uvm/README.md` を参照。

## 参考

本文と RTL コメントの節番号は AXI 仕様 Issue E のもの。最新の Issue L では章立てが変わっている。

| 内容 | Issue E (2013) | Issue L (2025) |
| --- | --- | --- |
| VALID/READY 規則 | A3.2.1 Handshake process | A2.3 Valid-Ready transport |
| 4KB 境界 | A3.4.1 Address structure | A3.1 Transaction request |
| BRESP / RRESP | A3.4.4 Read and write response structure | A3.3.1 Write response / A3.3.2 Read response |
| AxCACHE | A4.4 Memory types | A4.3 Memory types |
| AXI4 に WID が無い | A5.4 Removal of write interleaving support | A5.5 Write data and response ordering |

- AMBA AXI Protocol Specification (Arm IHI 0022)
  - 最新版の入口: https://developer.arm.com/documentation/ihi0022/latest/
  - Issue E: https://documentation-service.arm.com/static/5f915b62f86e16515cdc3b1c
  - Issue L: https://documentation-service.arm.com/static/68b03beb01ae952d9559f9eb
- Arm, Learn the architecture - An introduction to AMBA AXI
  (「A source cannot wait for READY to be asserted before asserting VALID」
  「AXI4 removes the WID signal from the W channel」):
  https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/102202_0100_01_Introduction_to_AMBA_AXI.pdf
- AMBA AXI quick reference card (AxCACHE `0011` = Normal Non-cacheable Bufferable):
  https://community.arm.com/cfs-file/__key/communityserver-discussions-components-files/476/2072.AMBA_5F00_AXI_5F00_AHB_5F00_APB.pdf
- AMD (Xilinx) PG021 AXI DMA / PG022 AXI DataMover (同種のマスタ DMA の製品 IP):
  https://docs.amd.com/r/en-US/pg021_axi_dma / https://docs.amd.com/r/en-US/pg022_axi_datamover
- Cadence Stratus HLS (`cynw_p2p` 相当の vld/busy チャネル):
  https://www.cadence.com/en_US/home/tools/digital-design-and-signoff/synthesis/stratus-high-level-synthesis.html

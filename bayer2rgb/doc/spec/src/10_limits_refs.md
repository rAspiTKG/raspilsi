## 15. 既知の制約と注意事項

### 15.1 機能・性能

- 幅は8の倍数、高さは偶数です(それ以外の設定値は切り捨て)。最小は 16×16 です。
- 入力と出力の領域を重ねた変換(同じバッファでの変換)はできません。
- バイリニア補間は、エッジでの偽色やジッパー状のノイズが出やすい方式です。FCS はエッジ量に応じて色差を縮めますが、エッジ量は中心をはさむ同じ色どうしの差なので、中心を通る1画素幅の細い線では小さくなり、細い線の偽色は抑えられません。
- AXI の ID は1種類だけで、同時発行は読み出し・書き込みとも4バースト(64ビート)です。メモリの応答の遅れ(読み出しは AR から R、書き込みは最後の W から B まで)がおおよそ 64 クロック(400 MHz で 160 ns)を超えると、帯域が下がります。
- エラー応答を受けても処理は続けます。エラーの起きたアドレスは記録しません。
- 割り込みはレベル出力です。エッジで受けるシステムでは、IRQ_STATUS をクリアしてから次の要因で再び立ちます。

### 15.2 実装

- Foundry のプロセスでの論理合成・配置配線・STA はまだ行っていません(PDK と商用ツールがないため。雛形は 14.5)。ASAP7 では 400 MHz(WC コーナー)で、合成(PPC=8/4/2/1)と、配置配線の概略配線まで(PPC=8/2)を通しました(14.3、14.4)。詳細配線・寄生抽出・配線後の STA・IR ドロップは、この環境のメモリが足りず実行していません。ASAP7 の結果は傾向を見るためのもので、Foundry のプロセスの値ではありません。
- SRAM マクロと同期化セルは、シミュレーションでは振る舞いモデル、ASAP7 の合成では仮マクロと FF 2段です。量産の前に 12章の手順で Foundry の製品IPに置き換えてください。
- CDC の制約(11.2)を必ず入れてください。CDC 検証ツールでの確認はしていません。
- PPC=8 では、GAMMA の折れ点の選択(24チャネル × 2か所 × 37個の中から選ぶ)に配線が集中します。ASAP7 では使用率 40%・配置の密度 0.60 で概略配線が収束せず、30% / 0.42 に下げました(14.4)。量産の配置配線でも GAMMA のまわりの配置の密度を下げてください(Innovus の部分的な配置ブロッケージなど)。
- 配置配線の後で最も余裕が小さいのは、リセットの解除(rst_n のリカバリ)です(ASAP7 の概略配線の後で PPC=8 が +2.0 ps、PPC=2 が +3.9 ps)。リセットは IP の全体の制御の FF に広がるので、配線のバッファで 1 ns 程度遅れます。SoC に組み込むときは、リセットの同期化の FF を IP の近くに置く(SDC の `B2R_RST_PCT` を小さくできる)か、リセットの配線へのバッファの入れ方を見直してください(14.4.3)。
- 入出力の遅延は仮想クロック(`clk_io`、`ctrl_clk_io`)から測ります。CTS の後は、仮想クロックの遅れを実際のクロックツリーの遅れに合わせてください(Innovus の update_io_latency、ASAP7 の環境の `make io_latency`。14.2)。
- DFT(スキャン、メモリ BIST)と低消費電力の機能(クロックゲーティング、電源遮断)は入れていません(ツールで挿入する前提)。
- RTL と検証環境のコメントは UTF-8 の日本語です。

### 15.3 検証

- 回帰試験とカバレッジは Verilator で行いました。Xcelium 用の Makefile と波形の設定は用意していますが、この環境では Xcelium を実行していません(ライセンスがない)。
- Verilator では UVM を `UVM_NO_DPI` で使っています(正規表現を使う機能は使っていません)。
- 機能カバレッジは、Verilator の covergroup の集計とは別に、同じビンを名前で数えてログに出し、`tools/merge_cov.py` でまとめています。Xcelium では covergroup の結果を IMC でまとめられます。

## 16. 参考文献

| No | 文献 | 使ったところ |
|---|---|---|
| R1 | [MathWorks: demosaic](https://www.mathworks.com/help/images/ref/demosaic.html) | Bayer の並びの名前(左上 2×2 の読み順) |
| R2 | [libcamera: ColorFilterArrangement の定義](https://git.libcamera.org/libcamera/pinchartl/libcamera.git/tree/src/libcamera/property_ids_draft.yaml) | Bayer の並びの名前 |
| R3 | [OpenCV Q&A: BORDER_REFLECT vs BORDER_REFLECT_101](https://answers.opencv.org/question/50706/border_reflect-vs-border_reflect_101) | 端の処理(reflect-101: gfedcb\|abcdefgh\|gfedcba) |
| R4 | [Google Patents: US7502505B2](https://patents.google.com/patent/US7502505) | MHC 方式の特許 |
| R5 | [Malvar, He, Cutler, "High-quality linear interpolation for demosaicing of Bayer-patterned color images", ICASSP 2004](https://ieeexplore.ieee.org/document/1326587) | MHC 方式 |
| R6 | [Arm: AMBA AXI Protocol Specification (IHI 0022)](https://developer.arm.com/documentation/ihi0022/latest/) | AXI4 / AXI4-Lite の規則(VALID/READY、W と AW の順序、4KB 境界、WID の廃止) |
| R7 | [Wikipedia: sRGB](https://en.wikipedia.org/wiki/SRGB) | ガンマの既定値(sRGB の変換曲線) |
| R8 | [Cummings, "Clock Domain Crossing (CDC) Design & Verification Techniques Using SystemVerilog", SNUG Boston 2008](https://pdfcoffee.com/cummings-paper-cdc-pdf-pdf-free.html) | MCP 方式(トグル + 同期化 + ACK)によるデータの受け渡し |
| R9 | [AMD UG934: AXI4-Lite Interface](https://docs.amd.com/r/en-US/ug934_axi_videoIP/AXI4-Lite-Interface) | ビデオIPの標準レジスタ(レジスタ更新、バイパス、テストパターン) |
| R10 | [AMD PG286 Sensor Demosaic: Register Space](https://docs.amd.com/r/en-US/pg286-v-demosaic/Register-Space) | Bayer の並び・幅・高さのレジスタ |
| R11 | [Verilator: verilator_coverage](https://verilator.org/guide/latest/exe_verilator_coverage.html) | コードカバレッジの集計 |
| R12 | [Antmicro: Support for upstream UVM 2017 in Verilator](https://antmicro.com/blog/2025/10/support-for-upstream-uvm-2017-in-verilator) | Verilator での UVM 2017-1.0 |
| R13 | [CHIPS Alliance: Support for upstream UVM 2017 in Verilator](https://chipsalliance.org/news/uvm-verilator/) | Verilator での UVM 2017-1.0 |
| R14 | [WaveDrom README(svg.wavedrom.com)](https://cdn.jsdelivr.net/npm/wavedrom@3.6.1/README.md) | GitHub での WaveDrom の表示 |
| R15 | [Cadence Community: xrun dump all internal signals](https://community.cadence.com/cadence_technology_forums/f/functional-verification/57941/xrun-dump-all-internal-signals) | Xcelium の波形(database / probe) |
| R16 | [OpenTitan: xcelium.hjson](https://opensecura.googlesource.com/3p/lowrisc/opentitan/+/4a6b06b28416dbb335099ead987c909e31403d78/hw/dv/data/xcelium/xcelium.hjson) | Xcelium の UVM 指定(-uvmhome CDNS-1.2) |
| R17 | [cocotb: Simulator Support](https://docs.cocotb.org/en/latest/simulator_support.html) / [GTKWave(Flathub)](https://flathub.org/apps/io.github.gtkwave.GTKWave) | Verilator の FST 出力と GTKWave |
| R18 | [OpenROAD-flow-scripts(GitHub)](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) | 配置配線の流れ、ASAP7 のプラットフォーム(14章) |
| R19 | [sv2v(GitHub)](https://github.com/zachjs/sv2v) | SystemVerilog → Verilog の変換(14.3) |
| R20 | [yosys-slang(GitHub)](https://github.com/povik/yosys-slang) | Yosys で SystemVerilog を直接読む(14.3) |
| R21 | [ASAP7 PDK(GitHub)](https://github.com/The-OpenROAD-Project/asap7) | 7nm 相当の予測 PDK とセルライブラリ(14章) |
| R22 | [Yosys(GitHub)](https://github.com/YosysHQ/yosys) | 論理合成(14.3) |
| R23 | [OpenROAD(GitHub)](https://github.com/The-OpenROAD-Project/OpenROAD) | 配置配線のツール(14.4) |
| R24 | [OpenROAD-flow-scripts: Flow Variables](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html) | ORFS の変数(14.4) |
| R25 | [Microchip: set_max_delay(SDC)](https://onlinedocs.microchip.com/oxy/GUID-AFCB5DCC-964F-4BE7-AA46-C756FA87ED7B-en-US-21/GUID-CDCFAAE7-BB67-4F0A-9E54-88F759325E05.html) | `-ignore_clock_latency` の意味(11.2) |
| R26 | [OpenSTA(GitHub)](https://github.com/parallaxsw/OpenSTA) | 静的タイミング解析(14.3、14.4) |
| R27 | [Cadence Community: Propagated clock for reg2out](https://community.cadence.com/cadence_technology_forums/f/digital-implementation/27219/propagated-clock-for-reg2out) | 入出力の遅延を仮想クロックから測る方法と、CTS の後の update_io_latency(14.2) |

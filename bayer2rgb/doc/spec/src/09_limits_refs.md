## 14. 既知の制約と注意事項

### 14.1 機能・性能

- 幅は8の倍数、高さは偶数です(それ以外の設定値は切り捨て)。最小は 16×16 です。
- 入力と出力の領域を重ねた変換(同じバッファでの変換)はできません。
- バイリニア補間は、エッジでの偽色やジッパー状のノイズが出やすい方式です。FCS はエッジ量に応じて色差を縮めますが、エッジ量は中心をはさむ同じ色どうしの差なので、中心を通る1画素幅の細い線では小さくなり、細い線の偽色は抑えられません。
- AXI の ID は1種類だけで、同時発行は読み出し・書き込みとも4バースト(64ビート)です。メモリの応答の遅れ(読み出しは AR から R、書き込みは最後の W から B まで)がおおよそ 64 クロック(400 MHz で 160 ns)を超えると、帯域が下がります。
- エラー応答を受けても処理は続けます。エラーの起きたアドレスは記録しません。
- 割り込みはレベル出力です。エッジで受けるシステムでは、IRQ_STATUS をクリアしてから次の要因で再び立ちます。

### 14.2 実装

- 論理合成と静的タイミング解析(Foundry、400 MHz)はまだ行っていません。乗算のある段(WB: 14×16bit、FCS: 14×8bit と 15×9bit、GAMMA: 13×11bit)は、乗算と加算・丸めを別の段に分けて 400 MHz を狙った構成にしていますが、合成で確認が必要です。
- SRAM マクロと同期化セルは振る舞いモデルのままです。量産の前に 12章の手順で置き換えてください。
- CDC の制約(11.2)を必ず入れてください。CDC 検証ツールでの確認はしていません。
- DFT(スキャン、メモリ BIST)と低消費電力の機能(クロックゲーティング、電源遮断)は入れていません(ツールで挿入する前提)。
- RTL と検証環境のコメントは UTF-8 の日本語です。

### 14.3 検証

- 回帰試験とカバレッジは Verilator で行いました。Xcelium 用の Makefile と波形の設定は用意していますが、この環境では Xcelium を実行していません(ライセンスがない)。
- Verilator では UVM を `UVM_NO_DPI` で使っています(正規表現を使う機能は使っていません)。
- 機能カバレッジは、Verilator の covergroup の集計とは別に、同じビンを名前で数えてログに出し、`tools/merge_cov.py` でまとめています。Xcelium では covergroup の結果を IMC でまとめられます。

## 15. 参考文献

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

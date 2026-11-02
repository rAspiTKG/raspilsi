## 10. 既知の制約と注意事項

- 設定(i_cfg)はフレームの切り替えで自動では取り込みません。コアが空のときだけ変えてください(4.7)。変える時刻を守れない使い方をするときは、sof の転送で設定を取り込み、転送と一緒にパイプラインを運ぶ形に変える必要があります。
- フレームの区切り(sof / eol / eof)の並びは確かめません。画像の大きさも見ません。
- 出力が止められたとき、全段を止めます。段の間に空きがあっても詰めません(入力段だけは、空いていれば受け取る)。
- Xcelium での実行と、Foundry の PDK の流れ(`pd/commercial`)は、この環境では行っていません(ツールと PDK がないため)。
- ASAP7 の配置配線の結果は、予測 PDK での値です。GDS は KLayout がないので作っていません(`make gds` で作れます)。
- 入力の遅延の最小を 0 にしているので、入力ポートの直後の FF にホールド用バッファが入ります(9.3)。

## 11. 参考文献

| No | 文献 | 使ったところ |
|---|---|---|
| R1 | [STMicroelectronics: How to tune ISP using the STM32 ISP IQTune](https://wiki.st.com/stm32mcu/wiki/ISP:How_to_tune_ISP_using_the_STM32_ISP_IQTune) | 黒レベル(R / G / B ごとの黒のオフセットを引く)と ISP のゲイン(R / G / B ごと)を、デモザイクの前に行う(5章) |
| R2 | [ZipCPU: Building a Skid Buffer for AXI processing](https://zipcpu.com/blog/2019/05/22/skidbuffer.html) | スキッドで、止める信号(busy)を FF から出す(6.2) |
| R3 | [Antmicro: Support for upstream UVM 2017 in Verilator](https://antmicro.com/blog/2025/10/support-for-upstream-uvm-2017-in-verilator) | Verilator での UVM 1800.2-2017-1.0(8章) |
| R4 | [OpenTitan: xcelium.hjson](https://opensecura.googlesource.com/3p/lowrisc/opentitan/+/4a6b06b28416dbb335099ead987c909e31403d78/hw/dv/data/xcelium/xcelium.hjson) / [Cadence Community: xrun dump all internal signals](https://community.cadence.com/cadence_technology_forums/f/functional-verification/57941/xrun-dump-all-internal-signals) | Xcelium の UVM の指定(-uvmhome CDNS-1.2)と波形(8.6) |
| R5 | [cocotb: Simulator Support](https://docs.cocotb.org/en/latest/simulator_support.html) / [GTKWave(Flathub)](https://flathub.org/apps/io.github.gtkwave.GTKWave) | Verilator の FST 出力と GTKWave(8章) |
| R6 | [OpenROAD-flow-scripts(GitHub)](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) / [Flow Variables](https://openroad-flow-scripts.readthedocs.io/en/latest/user/FlowVariables.html) | 配置配線の流れと変数(IO_CONSTRAINTS、CORE_UTILIZATION、PLACE_DENSITY、NUM_CORES)(9.2) |
| R7 | [ASAP7 PDK(GitHub)](https://github.com/The-OpenROAD-Project/asap7) | 7nm 相当の予測 PDK とセルライブラリ(9章) |
| R8 | [Yosys(GitHub)](https://github.com/YosysHQ/yosys) / [OpenROAD(GitHub)](https://github.com/The-OpenROAD-Project/OpenROAD) / [OpenSTA(GitHub)](https://github.com/parallaxsw/OpenSTA) | 論理合成、配置配線、STA(9章) |
| R9 | [sv2v(GitHub)](https://github.com/zachjs/sv2v) / [sv2v issue #230](https://github.com/zachjs/sv2v/issues/230) | SystemVerilog → Verilog の変換。インタフェースはインスタンスを展開して変換する(9.1)。トップにできないことは v0.0.13 で確かめた(「Specified top module … has interface ports. Please instantiate it somewhere and use that as your top module instead.」) |
| R10 | [IEEE 1800-2017(SystemVerilog)](https://ieeexplore.ieee.org/document/8299595) | インタフェース、modport、packed struct(4章) |
| R11 | [OpenROAD: Pin Placer(set_io_pin_constraint)](https://openroad.readthedocs.io/en/latest/main/src/ppl/README.html) | 端子を辺ごとに置く(`-pin_names`、`-region left:*`)(9.2) |
| R12 | [Cadence Community: Propagated clock for reg2out](https://community.cadence.com/cadence_technology_forums/f/digital-implementation/27219/propagated-clock-for-reg2out) | 入出力の遅延を仮想クロックから測る方法と、CTS の後の update_io_latency(9.3) |
| R13 | [WaveDrom README(svg.wavedrom.com)](https://cdn.jsdelivr.net/npm/wavedrom@3.6.1/README.md) | GitHub での WaveDrom の表示(この文書の波形図) |
| R14 | [Verilator: verilator_coverage](https://verilator.org/guide/latest/exe_verilator_coverage.html) | コードカバレッジの集計(8.5) |

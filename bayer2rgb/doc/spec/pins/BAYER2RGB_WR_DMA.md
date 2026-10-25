| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |
|---|---|---|---|---|
| clk | 入力 | 映像系クロック(AXI4マスタ・画像処理)。400MHz | 1 | 立ち上がり |
| rst_n | 入力 | 映像系リセット。非同期アサート・同期解除(同期化は外部) | 1 | Low |
| i_ctl | 入力 | フレームの設定 + start(開始パルス)+ sw_rst(ソフトリセットパルス)(ctl_t) | 797 | - |
| rgb.vld | 入力 | COREの出力ビートが有効 | 1 | High |
| rgb.busy | 出力 | 受け取れない(詰め替え中・バッファが満杯) | 1 | High |
| rgb.data | 入力 | 出力ビート(obeat_t) | 195(PPC×24+3) | - |
| aw.vld | 出力 | 書き込み要求が有効 | 1 | High |
| aw.busy | 入力 | BRIDGEが要求を受け取れない | 1 | High |
| aw.data | 出力 | 要求(axreq_t) | 59 | - |
| w.vld | 出力 | 書き込みデータが有効 | 1 | High |
| w.busy | 入力 | BRIDGEがデータを受け取れない | 1 | High |
| w.data | 出力 | データ {last, strb[15:0], data[127:0]}(wbeat_t) | 145 | - |
| b.vld | 入力 | 書き込み応答が有効 | 1 | High |
| b.busy | 出力 | 応答を受け取れない(常に0) | 1 | High |
| b.data | 入力 | BRESP | 2 | - |
| o_evt | 出力 | 状態 {busy, frame_done(全バーストの応答を受けた、パルス), wr_err(パルス)} | 3 | - |

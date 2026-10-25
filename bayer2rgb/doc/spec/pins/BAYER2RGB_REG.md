| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |
|---|---|---|---|---|
| ctrl_clk | 入力 | 制御系クロック(AXI4-Liteスレーブ・レジスタ) | 1 | 立ち上がり |
| ctrl_rst_n | 入力 | 制御系リセット。非同期アサート・同期解除(同期化は外部) | 1 | Low |
| req.vld | 入力 | アクセス要求が有効 | 1 | High |
| req.busy | 出力 | 要求を受け取れない(応答を返している) | 1 | High |
| req.data | 入力 | 要求 {we, strb, addr, wdata}(regreq_t) | 49 | - |
| rsp.vld | 出力 | 応答が有効 | 1 | High |
| rsp.busy | 入力 | AXIL_BRIDGEが応答を受け取れない | 1 | High |
| rsp.data | 出力 | 応答 {resp, rdata}(regrsp_t) | 34 | - |
| o_cfg | 出力 | 現在のレジスタ値(cfg_t)。STARTのときにCDCが取り込む | 795 | - |
| o_start | 出力 | フレーム開始の要求(1クロックのパルス)。CDCが受け付けられるときだけ出す | 1 | High |
| o_sw_rst | 出力 | ソフトリセットの要求(1クロックのパルス) | 1 | High |
| i_cdc_busy | 入力 | CDCが要求を受け渡し中 | 1 | High |
| i_evt | 入力 | 映像系からのイベント {frame_done, rd_err, wr_err, srst_done}(各1クロックのパルス) | 4 | - |
| o_irq | 出力 | 割り込み(レベル) | 1 | High |

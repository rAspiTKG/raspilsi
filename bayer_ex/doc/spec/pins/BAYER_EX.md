| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |
|---|---|---|---|---|
| clk | 入力 | クロック。400MHz(すべての FF) | 1 | 立ち上がり |
| rst_n | 入力 | リセット。非同期アサート・同期解除(同期化は外部) | 1 | Low |
| i_cfg | 入力 | 設定 {bypass, phase, blc[3:0], gain[3:0]}(cfg_t)。コアの中にデータがないときだけ変える | 123(cfg_t) | - |
| i_vld | 入力 | 入力の data が有効 | 1 | High |
| o_busy | 出力 | 入力を受け取れない(FF から出す。スキッドが埋まったとき 1) | 1 | High |
| i_data | 入力 | 入力の転送(bayer4x2_t。Bayer の水平4画素 × 垂直2ラインと sof / eol / eof) | 115(bayer4x2_t) | - |
| o_vld | 出力 | 出力の data が有効(FF から出す) | 1 | High |
| i_busy | 入力 | 出力先が受け取れない | 1 | High |
| o_data | 出力 | 出力の転送(bayer4x2_t。画素は補正後、sof / eol / eof は入力のまま。FF から出す) | 115(bayer4x2_t) | - |

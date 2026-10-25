| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |
|---|---|---|---|---|
| ctrl_clk | 入力 | 制御系クロック(AXI4-Liteスレーブ・レジスタ) | 1 | 立ち上がり |
| ctrl_rst_n | 入力 | 制御系リセット。非同期アサート・同期解除(同期化は外部) | 1 | Low |
| BAYER2RGB_REG_AWADDR | 入力 | 書き込みアドレス(バイトアドレス。下位2ビットは見ない) | 12 | - |
| BAYER2RGB_REG_AWPROT | 入力 | 保護属性(使わない) | 3 | - |
| BAYER2RGB_REG_AWVALID | 入力 | 書き込みアドレスが有効 | 1 | High |
| BAYER2RGB_REG_AWREADY | 出力 | 書き込みアドレスを受け付けた | 1 | High |
| BAYER2RGB_REG_WDATA | 入力 | 書き込みデータ | 32 | - |
| BAYER2RGB_REG_WSTRB | 入力 | バイトイネーブル | 4 | - |
| BAYER2RGB_REG_WVALID | 入力 | 書き込みデータが有効 | 1 | High |
| BAYER2RGB_REG_WREADY | 出力 | 書き込みデータを受け付けた | 1 | High |
| BAYER2RGB_REG_BRESP | 出力 | 書き込み応答(常にOKAY) | 2 | - |
| BAYER2RGB_REG_BVALID | 出力 | 書き込み応答が有効 | 1 | High |
| BAYER2RGB_REG_BREADY | 入力 | 書き込み応答を受け取れる | 1 | High |
| BAYER2RGB_REG_ARADDR | 入力 | 読み出しアドレス(バイトアドレス。下位2ビットは見ない) | 12 | - |
| BAYER2RGB_REG_ARPROT | 入力 | 保護属性(使わない) | 3 | - |
| BAYER2RGB_REG_ARVALID | 入力 | 読み出しアドレスが有効 | 1 | High |
| BAYER2RGB_REG_ARREADY | 出力 | 読み出しアドレスを受け付けた | 1 | High |
| BAYER2RGB_REG_RDATA | 出力 | 読み出しデータ(未定義のアドレスは0) | 32 | - |
| BAYER2RGB_REG_RRESP | 出力 | 読み出し応答(常にOKAY) | 2 | - |
| BAYER2RGB_REG_RVALID | 出力 | 読み出しデータが有効 | 1 | High |
| BAYER2RGB_REG_RREADY | 入力 | 読み出しデータを受け取れる | 1 | High |
| req.vld | 出力 | REGへのアクセス要求が有効 | 1 | High |
| req.busy | 入力 | REGが要求を受け取れない | 1 | High |
| req.data | 出力 | 要求 {we, strb[3:0], addr[11:0], wdata[31:0]}(regreq_t) | 49 | - |
| rsp.vld | 入力 | REGからの応答が有効 | 1 | High |
| rsp.busy | 出力 | 応答を受け取れない(AXI側の応答を出している) | 1 | High |
| rsp.data | 入力 | 応答 {resp[1:0], rdata[31:0]}(regrsp_t) | 34 | - |

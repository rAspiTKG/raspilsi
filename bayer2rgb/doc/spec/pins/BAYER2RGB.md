| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |
|---|---|---|---|---|
| clk | 入力 | 映像系クロック(AXI4マスタ・画像処理)。400MHz | 1 | 立ち上がり |
| rst_n | 入力 | 映像系リセット。非同期アサート・同期解除(同期化は外部) | 1 | Low |
| ctrl_clk | 入力 | 制御系クロック(AXI4-Liteスレーブ・レジスタ) | 1 | 立ち上がり |
| ctrl_rst_n | 入力 | 制御系リセット。非同期アサート・同期解除(同期化は外部) | 1 | Low |
| irq | 出力 | 割り込み。IRQ_STATUS と IRQ_ENABLE の論理積のOR(レベル、ctrl_clk同期) | 1 | High |
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
| BAYER2RGB_MEM_AWID | 出力 | 書き込みID(常に0) | 4 | - |
| BAYER2RGB_MEM_AWADDR | 出力 | 書き込みアドレス(16バイト境界) | 40 | - |
| BAYER2RGB_MEM_AWLEN | 出力 | バーストのビート数-1(0〜15) | 8 | - |
| BAYER2RGB_MEM_AWSIZE | 出力 | 1ビートのバイト数(常に4 = 16バイト) | 3 | - |
| BAYER2RGB_MEM_AWBURST | 出力 | バーストの種類(常に1 = INCR) | 2 | - |
| BAYER2RGB_MEM_AWLOCK | 出力 | 排他アクセス(常に0) | 1 | High |
| BAYER2RGB_MEM_AWCACHE | 出力 | キャッシュ属性(AXI_ATTR.AWCACHE) | 4 | - |
| BAYER2RGB_MEM_AWPROT | 出力 | 保護属性(AXI_ATTR.AWPROT) | 3 | - |
| BAYER2RGB_MEM_AWQOS | 出力 | QoS(AXI_ATTR.AWQOS) | 4 | - |
| BAYER2RGB_MEM_AWVALID | 出力 | 書き込み要求が有効 | 1 | High |
| BAYER2RGB_MEM_AWREADY | 入力 | 書き込み要求を受け付けた | 1 | High |
| BAYER2RGB_MEM_WDATA | 出力 | 書き込みデータ(RGB888をR,G,B順に詰めたもの。バイト0が下位) | 128 | - |
| BAYER2RGB_MEM_WSTRB | 出力 | バイトイネーブル(ラインの最後の端数ビートだけ下位8バイト) | 16 | - |
| BAYER2RGB_MEM_WLAST | 出力 | バーストの最後のビート | 1 | High |
| BAYER2RGB_MEM_WVALID | 出力 | 書き込みデータが有効 | 1 | High |
| BAYER2RGB_MEM_WREADY | 入力 | 書き込みデータを受け付けた | 1 | High |
| BAYER2RGB_MEM_BID | 入力 | 応答ID(見ない) | 4 | - |
| BAYER2RGB_MEM_BRESP | 入力 | 書き込み応答(OKAY以外は IRQ_STATUS.WR_ERR) | 2 | - |
| BAYER2RGB_MEM_BVALID | 入力 | 書き込み応答が有効 | 1 | High |
| BAYER2RGB_MEM_BREADY | 出力 | 書き込み応答を受け取れる(常に受け取る) | 1 | High |
| BAYER2RGB_MEM_ARID | 出力 | 読み出しID(常に0) | 4 | - |
| BAYER2RGB_MEM_ARADDR | 出力 | 読み出しアドレス(16バイト境界) | 40 | - |
| BAYER2RGB_MEM_ARLEN | 出力 | バーストのビート数-1(0〜15) | 8 | - |
| BAYER2RGB_MEM_ARSIZE | 出力 | 1ビートのバイト数(常に4 = 16バイト) | 3 | - |
| BAYER2RGB_MEM_ARBURST | 出力 | バーストの種類(常に1 = INCR) | 2 | - |
| BAYER2RGB_MEM_ARLOCK | 出力 | 排他アクセス(常に0) | 1 | High |
| BAYER2RGB_MEM_ARCACHE | 出力 | キャッシュ属性(AXI_ATTR.ARCACHE) | 4 | - |
| BAYER2RGB_MEM_ARPROT | 出力 | 保護属性(AXI_ATTR.ARPROT) | 3 | - |
| BAYER2RGB_MEM_ARQOS | 出力 | QoS(AXI_ATTR.ARQOS) | 4 | - |
| BAYER2RGB_MEM_ARVALID | 出力 | 読み出し要求が有効 | 1 | High |
| BAYER2RGB_MEM_ARREADY | 入力 | 読み出し要求を受け付けた | 1 | High |
| BAYER2RGB_MEM_RID | 入力 | 応答ID(見ない) | 4 | - |
| BAYER2RGB_MEM_RDATA | 入力 | 読み出しデータ(16bit×8画素。各16bitの下位14bitを使う) | 128 | - |
| BAYER2RGB_MEM_RRESP | 入力 | 読み出し応答(OKAY以外は IRQ_STATUS.RD_ERR) | 2 | - |
| BAYER2RGB_MEM_RLAST | 入力 | バーストの最後のビート | 1 | High |
| BAYER2RGB_MEM_RVALID | 入力 | 読み出しデータが有効 | 1 | High |
| BAYER2RGB_MEM_RREADY | 出力 | 読み出しデータを受け取れる | 1 | High |

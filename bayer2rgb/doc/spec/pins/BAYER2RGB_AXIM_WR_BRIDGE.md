| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |
|---|---|---|---|---|
| clk | 入力 | 映像系クロック(AXI4マスタ・画像処理)。400MHz | 1 | 立ち上がり |
| rst_n | 入力 | 映像系リセット。非同期アサート・同期解除(同期化は外部) | 1 | Low |
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
| aw.vld | 入力 | 書き込み要求が有効 | 1 | High |
| aw.busy | 出力 | 要求を受け取れない(スキッドが満杯) | 1 | High |
| aw.data | 入力 | 要求(axreq_t) | 59 | - |
| w.vld | 入力 | 書き込みデータが有効 | 1 | High |
| w.busy | 出力 | データを受け取れない(スキッドが満杯) | 1 | High |
| w.data | 入力 | データ(wbeat_t) | 145 | - |
| b.vld | 出力 | 書き込み応答が有効 | 1 | High |
| b.busy | 入力 | WR_DMAが応答を受け取れない | 1 | High |
| b.data | 出力 | BRESP | 2 | - |

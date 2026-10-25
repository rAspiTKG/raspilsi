| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |
|---|---|---|---|---|
| clk | 入力 | 映像系クロック(AXI4マスタ・画像処理)。400MHz | 1 | 立ち上がり |
| rst_n | 入力 | 映像系リセット。非同期アサート・同期解除(同期化は外部) | 1 | Low |
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
| ar.vld | 入力 | 読み出し要求が有効 | 1 | High |
| ar.busy | 出力 | 要求を受け取れない(スキッドが満杯) | 1 | High |
| ar.data | 入力 | 要求 {qos, prot, cache, len, addr}(axreq_t) | 59 | - |
| r.vld | 出力 | 読み出しデータが有効 | 1 | High |
| r.busy | 入力 | RD_DMAがデータを受け取れない | 1 | High |
| r.data | 出力 | データ {resp, last, data[127:0]}(rbeat_t) | 131 | - |

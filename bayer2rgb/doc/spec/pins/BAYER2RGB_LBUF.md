| 信号名 | 入出力 | 信号仕様 | ビット幅 | 極性 |
|---|---|---|---|---|
| clk | 入力 | 映像系クロック(AXI4マスタ・画像処理)。400MHz | 1 | 立ち上がり |
| rst_n | 入力 | 映像系リセット。非同期アサート・同期解除(同期化は外部) | 1 | Low |
| i_clr | 入力 | 同期クリア(ソフトリセット)。1クロックのパルスで有効ビットを消す | 1 | High |
| i_stp | 入力 | ステップ(stp_t) | 136(PPC×14+24) | - |
| o_win | 出力 | 3×(PPC+2)画素の窓 {vld, sof, eol, eof, y, oc, win}(win_t、レイテンシ2) | 445(3×(PPC+2)×14+25) | - |
| o_sram0_ren | 出力 | SRAM0(2ライン前)の読み出し | 1 | High |
| o_sram0_raddr | 出力 | SRAM0の読み出しアドレス(列番号) | 9(log2(3840/PPC)) | - |
| i_sram0_rdata | 入力 | SRAM0の読み出しデータ(レイテンシ1) | 112(PPC×14) | - |
| o_sram0_wen | 出力 | SRAM0の書き込み(読み出しの次のクロック) | 1 | High |
| o_sram0_waddr | 出力 | SRAM0の書き込みアドレス | 9(log2(3840/PPC)) | - |
| o_sram0_wdata | 出力 | SRAM0の書き込みデータ(SRAM1の読み出し値) | 112(PPC×14) | - |
| o_sram1_ren | 出力 | SRAM1(1ライン前)の読み出し | 1 | High |
| o_sram1_raddr | 出力 | SRAM1の読み出しアドレス(列番号) | 9(log2(3840/PPC)) | - |
| i_sram1_rdata | 入力 | SRAM1の読み出しデータ(レイテンシ1) | 112(PPC×14) | - |
| o_sram1_wen | 出力 | SRAM1の書き込み(読み出しの次のクロック) | 1 | High |
| o_sram1_waddr | 出力 | SRAM1の書き込みアドレス | 9(log2(3840/PPC)) | - |
| o_sram1_wdata | 出力 | SRAM1の書き込みデータ(入力のビート) | 112(PPC×14) | - |

## 7. レジスタ

### 7.1 レジスタマップ

アクセス: RW = 読み書き、RO = 読み出し専用、W1C = 1を書いたビットを0にする、WO = 書き込みのみ(読むと0)。未定義のビットは書き込みを無視し、読むと0です。

| アドレス | 名前 | アクセス | リセット値 | 内容 |
|---|---|---|---|---|
| 0x000 | CONTROL | RW / WO | 0x0000_0002 | 開始、設定の取り込み、バイパス、テストパターン、自動再開、ソフトリセット |
| 0x004 | STATUS | RO | 0x0000_0000 | 動作中 |
| 0x008 | IRQ_STATUS | W1C | 0x0000_0000 | 割り込みの要因 |
| 0x00C | IRQ_ENABLE | RW | 0x0000_0000 | 割り込みの許可 |
| 0x010 | VERSION | RO | 0x0001_0000 | IP の版 |
| 0x014 | HWCFG0 | RO | 0x0870_0F00 | 最大の高さ・幅 |
| 0x018 | HWCFG1 | RO | 0x2810_0E08 | アドレス幅、ビートのバイト数、入力ビット幅、PPC(PPC=8 の値) |
| 0x01C | FRAME_COUNT | RO | 0x0000_0000 | 完了したフレームの数 |
| 0x020 | ACTIVE_WIDTH | RW | 0x0000_0F00 | 幅(画素) |
| 0x024 | ACTIVE_HEIGHT | RW | 0x0000_0870 | 高さ(ライン) |
| 0x028 | BAYER_PHASE | RW | 0x0000_0000 | Bayer の並び |
| 0x02C | FUNC_EN | RW | 0x0000_000F | 機能ごとの有効 |
| 0x030 | BLC_R_GR | RW | 0x0000_0000 | 黒レベル(R、Gr) |
| 0x034 | BLC_GB_B | RW | 0x0000_0000 | 黒レベル(Gb、B) |
| 0x038 | WB_R_GR | RW | 0x1000_1000 | WB ゲイン(R、Gr) |
| 0x03C | WB_GB_B | RW | 0x1000_1000 | WB ゲイン(Gb、B) |
| 0x040 | FCS_PARAM | RW | 0x0010_0100 | 彩度抑制のしきい値と傾き |
| 0x044 | TPG_SEL | RW | 0x0000_0000 | テストパターンの種類 |
| 0x048 | TPG_COLOR | RW | 0x0000_0000 | 単色パターンの色 |
| 0x050 | SRC_ADDR_L | RW | 0x0000_0000 | 入力の先頭アドレス [31:4] |
| 0x054 | SRC_ADDR_H | RW | 0x0000_0000 | 入力の先頭アドレス [39:32] |
| 0x058 | SRC_STRIDE | RW | 0x0000_0000 | 入力のライン間隔(バイト) |
| 0x060 | DST_ADDR_L | RW | 0x0000_0000 | 出力の先頭アドレス [31:4] |
| 0x064 | DST_ADDR_H | RW | 0x0000_0000 | 出力の先頭アドレス [39:32] |
| 0x068 | DST_STRIDE | RW | 0x0000_0000 | 出力のライン間隔(バイト) |
| 0x070 | AXI_ATTR | RW | 0x0000_0033 | AXI4 マスタの AxCACHE / AxPROT / AxQOS |
| 0x100〜0x148 | GAMMA_KNOT0〜18 | RW | sRGB(6.8) | ガンマの折れ点(1ワードに2点) |

### 7.2 各レジスタ

#### CONTROL(0x000)

| ビット | 名前 | アクセス | リセット値 | 内容 |
|---|---|---|---|---|
| 0 | START | WO | 0 | 1を書くとフレームの開始を要求する。動作中に書くと保留し、前のフレームが終わってから開始する(保留は1つ) |
| 1 | REG_UPDATE | RW | 1 | 1: 開始のときに現在のレジスタの値を取り込む。0: 前に取り込んだ設定のまま開始する(ビデオIPの「レジスタ更新」ビットと同じ考え方 [R9]) |
| 4 | BYPASS | RW | 0 | 1: デモザイクを通さず R=G=B=Bayer 値(BLC・WB 後)で出す。FCS は働かない |
| 5 | TEST_PATTERN | RW | 0 | 1: 入力メモリを読まず、テストパターンを出す(6.9) |
| 7 | AUTO_RESTART | RW | 0 | 1: フレームが終わると自動で次のフレームを開始する |
| 31 | SW_RESET | WO | 0 | 1を書くとソフトリセット(7.4)。同じ書き込みの START は無視する |

CONTROL を書くとビット 1/4/5/7 も書き換わります。START だけを立てるときも、これらのビットに今の値を入れて書いてください。

BYPASS と TEST_PATTERN も、REG_UPDATE=1 で開始したときに取り込まれます(フレームの途中では変わりません)。

#### STATUS(0x004)

| ビット | 名前 | 内容 |
|---|---|---|
| 0 | BUSY | 1: 開始の保留中、フレームの処理中、またはソフトリセットの後始末中 |

#### IRQ_STATUS(0x008)/ IRQ_ENABLE(0x00C)

| ビット | 名前 | 内容 |
|---|---|---|
| 0 | FRAME_DONE | フレームの書き込みがすべて終わった(全バーストの書き込み応答を受けた) |
| 1 | RD_ERR | 読み出しのエラー応答(RRESP ≠ OKAY)を受けた |
| 2 | WR_ERR | 書き込みのエラー応答(BRESP ≠ OKAY)を受けた |

IRQ_STATUS は1を書いたビットを0にします。クリアと要因の発生が同じクロックのときは要因を優先します。ソフトリセットでは IRQ_STATUS はクリアしません。

#### VERSION(0x010)、HWCFG0(0x014)、HWCFG1(0x018)

| レジスタ | ビット | 内容 |
|---|---|---|
| VERSION | 31:0 | 0x0001_0000(版 1.0) |
| HWCFG0 | 15:0 | 最大の幅 3840 |
| HWCFG0 | 31:16 | 最大の高さ 2160 |
| HWCFG1 | 7:0 | PPC(1/2/4/8) |
| HWCFG1 | 15:8 | 入力の画素のビット数 14 |
| HWCFG1 | 23:16 | AXI4 マスタの1ビートのバイト数 16 |
| HWCFG1 | 31:24 | AXI4 マスタのアドレス幅 40 |

#### FRAME_COUNT(0x01C)

完了したフレームの数(32bit、一周する)。ソフトリセットで0になります。

#### ACTIVE_WIDTH(0x020)、ACTIVE_HEIGHT(0x024)

| レジスタ | ビット | 内容 |
|---|---|---|
| ACTIVE_WIDTH | 11:0 | 幅(画素)。有効値は 6.1 のとおり(16〜3840、8の倍数に切り捨て) |
| ACTIVE_HEIGHT | 11:0 | 高さ(ライン)。有効値は 6.1 のとおり(16〜2160、偶数に切り捨て) |

レジスタには書いた値がそのまま残ります(読み出し値はクランプ前の値)。

#### BAYER_PHASE(0x028)

| ビット | 内容 |
|---|---|
| 1:0 | 0: RGGB、1: GRBG、2: GBRG、3: BGGR(画像の切り出し・反転で並びが変わるので、フレームごとに設定できるようにしている [R10]) |

#### FUNC_EN(0x02C)

| ビット | 名前 | 内容 |
|---|---|---|
| 0 | BLC_EN | 黒レベル補正 |
| 1 | WB_EN | ホワイトバランス(0 のとき 1.0倍) |
| 2 | FCS_EN | エッジ部の彩度抑制 |
| 3 | GAMMA_EN | ガンマ(0 のとき線形) |

#### BLC_R_GR(0x030)、BLC_GB_B(0x034)

| レジスタ | ビット | 内容 |
|---|---|---|
| BLC_R_GR | 13:0 | R の黒レベル |
| BLC_R_GR | 29:16 | Gr の黒レベル |
| BLC_GB_B | 13:0 | Gb の黒レベル |
| BLC_GB_B | 29:16 | B の黒レベル |

#### WB_R_GR(0x038)、WB_GB_B(0x03C)

| レジスタ | ビット | 内容 |
|---|---|---|
| WB_R_GR | 15:0 | R のゲイン(U4.12、0x1000 = 1.0) |
| WB_R_GR | 31:16 | Gr のゲイン |
| WB_GB_B | 15:0 | Gb のゲイン |
| WB_GB_B | 31:16 | B のゲイン |

#### FCS_PARAM(0x040)

| ビット | 名前 | 内容 |
|---|---|---|
| 13:0 | FCS_TH | 彩度を下げ始めるエッジ量(リセット値 256) |
| 23:16 | FCS_GAIN | 傾き。エッジ量が FCS_TH を 64×256/FCS_GAIN 超えると無彩色になる(リセット値 16 → 1024) |

#### TPG_SEL(0x044)、TPG_COLOR(0x048)

| レジスタ | ビット | 内容 |
|---|---|---|
| TPG_SEL | 1:0 | 0: カラーバー、1: ランプ、2: チェッカー、3: 単色 |
| TPG_COLOR | 23:0 | 単色の色 {R[23:16], G[15:8], B[7:0]} |

#### SRC_ADDR_L / H、SRC_STRIDE、DST_ADDR_L / H、DST_STRIDE(0x050〜0x068)

| レジスタ | ビット | 内容 |
|---|---|---|
| xxx_ADDR_L | 31:4 | 先頭アドレスの [31:4]。[3:0] は書けない(読むと0、16バイト境界) |
| xxx_ADDR_H | 7:0 | 先頭アドレスの [39:32] |
| xxx_STRIDE | 23:4 | ライン間隔(バイト)。[3:0] は書けない(16の倍数) |

SRC_STRIDE ≥ 幅×2、DST_STRIDE ≥ 幅×3 を16の倍数に切り上げた値、としてください(IP は検査しません)。

#### AXI_ATTR(0x070)

| ビット | 名前 | リセット値 |
|---|---|---|
| 3:0 | ARCACHE | 0b0011(Normal Non-cacheable Bufferable) |
| 7:4 | AWCACHE | 0b0011 |
| 10:8 | ARPROT | 0 |
| 14:12 | AWPROT | 0 |
| 19:16 | ARQOS | 0 |
| 23:20 | AWQOS | 0 |

#### GAMMA_KNOT0〜18(0x100〜0x148)

| レジスタ | ビット | 内容 |
|---|---|---|
| GAMMA_KNOTn(アドレス 0x100 + 4n) | 11:0 | 折れ点 knot[2n] の出力値(8.4 固定小数点) |
| GAMMA_KNOTn | 27:16 | 折れ点 knot[2n+1] の出力値(n = 18 は無し。knot は 0〜36) |

### 7.3 使い方

#### 1フレームの処理

```
1. IRQ_ENABLE に割り込みの許可を書く(使う場合)
2. ACTIVE_WIDTH / ACTIVE_HEIGHT / BAYER_PHASE / FUNC_EN / BLC / WB / FCS / TPG / GAMMA_KNOT を書く
3. SRC_ADDR_L/H、SRC_STRIDE、DST_ADDR_L/H、DST_STRIDE を書く
4. CONTROL に START=1、REG_UPDATE=1(と BYPASS / TEST_PATTERN / AUTO_RESTART)を書く
5. irq を待つ(または IRQ_STATUS.FRAME_DONE を読んで待つ)
6. IRQ_STATUS を読み、RD_ERR / WR_ERR が0なら出力は正しい
7. IRQ_STATUS に読んだ値を書いてクリアする
```

開始のとき(REG_UPDATE=1)にレジスタの値を取り込むので、処理中にレジスタを書き換えても処理中のフレームには影響しません。次のフレームの設定を処理中に書いておけます。

#### 連続処理(AUTO_RESTART)

- AUTO_RESTART=1 で START を書くと、フレームが終わるたびに次のフレームを自動で開始します。
- REG_UPDATE=1 のときは、自動で開始するたびにその時点のレジスタの値を取り込みます。設定をまとめて変えたいときは、REG_UPDATE=0 にしてからレジスタを書き、最後に REG_UPDATE=1 に戻します(次の開始で全部が同時に変わる)。
- 止めるときは AUTO_RESTART=0 を書きます(処理中のフレームは最後まで処理する)。すぐに止めるときはソフトリセットを使います。

### 7.4 ソフトリセット(CONTROL.SW_RESET)

SW_RESET に1を書くと、処理中のフレームを中断して初期状態に戻します。

1. 制御系: 保留中の START を取り消し、FRAME_COUNT を0にする。STATUS.BUSY は後始末が終わるまで1。
2. 映像系: CORE の各段の有効ビットを消す。RD_DMA / WR_DMA は新しい要求を出すのをやめる。
3. 発行済みのバーストは AXI の規則どおり終える。読み出しはデータを受けて捨てる。書き込みは AW を出したバーストの W を送り切り、応答を受ける。まだ AW を出していないデータは捨てる。
4. すべての応答を受けたら(DMA が止まったら)制御系に完了を知らせ、STATUS.BUSY が0になる。

- レジスタの設定値と IRQ_STATUS は変わりません。中断したフレームの FRAME_DONE は立ちません。
- 出力メモリには中断したフレームの一部が書かれています。
- BUSY=0 になってから次の START を書いてください(BUSY=1 の間に書いた START は後始末の後に開始します)。

### 7.5 エラー応答

RD_ERR / WR_ERR が立っても処理は止めません。フレームの終わり(FRAME_DONE)で IRQ_STATUS を確認し、エラーがあればそのフレームを使わないでください。

## 8. 内部インタフェース(vld/busy/data)

BRIDGE、DMA、CORE の間は `BAYER2RGB_VBD_IF` でつなぎます。

| 信号 | 向き | 内容 |
|---|---|---|
| vld | 送り側 → 受け側 | data が有効 |
| busy | 受け側 → 送り側 | 受け取れない |
| data | 送り側 → 受け側 | データ(幅はパラメータ DW) |

- vld=1 かつ busy=0 のクロックで1つ転送します。
- busy=1 の間、送り側は vld と data を保持します。
- vld は busy に組み合わせで依存してはいけません(busy は vld に依存してよい)。

{{WAVE:vbd_if}}

| リンク | 送り側 → 受け側 | data の型 | 幅 |
|---|---|---|---:|
| s_req | AXIL_BRIDGE → REG | regreq_t {we, strb[3:0], addr[11:0], wdata[31:0]} | 49 |
| s_rsp | REG → AXIL_BRIDGE | regrsp_t {resp[1:0], rdata[31:0]} | 34 |
| s_ar | RD_DMA → AXIM_RD_BRIDGE | axreq_t {qos[3:0], prot[2:0], cache[3:0], len[7:0], addr[39:0]} | 59 |
| s_r | AXIM_RD_BRIDGE → RD_DMA | rbeat_t {resp[1:0], last, data[127:0]} | 131 |
| s_pix | RD_DMA → CORE | PPC 画素 × 14bit | 112 |
| s_rgb | CORE → WR_DMA | obeat_t {eof, eol, sof, rgb[PPC×24-1:0]} | 195 |
| s_aw | WR_DMA → AXIM_WR_BRIDGE | axreq_t | 59 |
| s_w | WR_DMA → AXIM_WR_BRIDGE | wbeat_t {last, strb[15:0], data[127:0]} | 145 |
| s_b | AXIM_WR_BRIDGE → WR_DMA | BRESP[1:0] | 2 |

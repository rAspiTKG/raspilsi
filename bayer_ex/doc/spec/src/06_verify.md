## 8. 検証

UVM で検証環境を作りました。Verilator(5.053、UVM 1800.2-2017-1.0)と Xcelium(UVM は付属の CDNS-1.2、または同じ 1800.2-2017-1.0)の両方で動くように書いています [R3][R4]。波形は GTKWave で見られる形式(Verilator: FST、Xcelium: VCD)で出します [R5]。

### 8.1 構成

![検証環境](../arch/bayer_ex_tb.svg)

| 部品 | ファイル | 内容 |
|---|---|---|
| tb_top | `tb/tb_top.sv` | クロック(+CLK_PS、既定 2.5 ns)とリセットを作り、DUT と仮想インタフェースをつなぐ。DUT は `BAYER_EX_CORE`(既定)、`+define+BEX_DUT_TOP` で `BAYER_EX` |
| bex_vbd_if | `tb/bex_vbd_if.sv` | vld / busy / data の束(入力側と出力側で1つずつ)。転送の規則のアサーション |
| bex_misc_if | `tb/bex_misc_if.sv` | DUT の i_cfg と、テストからのリセットの要求(rst_req) |
| bex_in_agent | `tb/uvm/bex_agent.svh` | シーケンサ + ドライバ(vld / data を出し、busy=1 の間は保持)+ モニタ |
| bex_out_agent | 同上 | busy のドライバ(止めない / 乱数 / 長く止める / 止めたまま / 決めた並び)+ モニタ |
| bex_frame_seq | `tb/uvm/bex_item.svh` | 1フレームを転送に分けて送る。転送の間のあけ方(なし / 乱数 / ときどき長く / 指定) |
| bex_image | `tb/uvm/bex_image.svh` | 入力画像(乱数、ランプ、黒レベルの近く、最大値の近く、0 と 16383 の市松、一定値) |
| bex_cfg | `tb/uvm/bex_cfg.svh` | 設定。乱数は端の値(0、最大値、1.0倍)を一定の割合で選ぶ |
| bex_ref_model | `tb/uvm/bex_ref_model.svh` | 5章の式をそのまま整数で書いたリファレンスモデル |
| bex_scoreboard | `tb/uvm/bex_scoreboard.svh` | 入力の転送(そのときの設定つき)から期待値を作り、出力の転送と順に比べる。レイテンシ ≥ 3 を確かめる。リセットで期待値を捨てる |
| bex_coverage | `tb/uvm/bex_coverage.svh` | 機能カバレッジ(8.4) |
| テスト | `tb/uvm/bex_base_test.svh`、`bex_tests.svh` | 8.3 |

DUT の data のポートは `BAYER_EX_DATA_IF` です。tb_top は、検証環境側の束(bex_vbd_if)の data と、DUT につなぐインタフェースのインスタンス(s_i_pix / s_o_pix)の data を assign でつないでいます。

アサーション(bex_vbd_if。入力側と出力側の両方):

| 名前 | 内容 |
|---|---|
| a_hold | vld=1 かつ busy=1 のクロックの次も vld=1 で、data が変わらない |
| a_vld_known | vld が不定にならない |
| a_data_known | vld=1 のとき data が不定にならない |

違反は UVM のエラーとして数えます(テストは FAILED になる)。Verilator は2値なので、不定の検査は Xcelium で働きます。

### 8.2 チェックのしかた

- スコアボードが、入力の転送ごとに期待値を作り、出力の転送と1つずつ比べます(sof / eol / eof と8画素)。出力の順番が入力と同じであること、余分な出力・足りない出力がないことも確かめます。
- 期待値の計算に使う設定は、入力側のモニタが転送のクロックに i_cfg から取ります。
- `+BEX_DUMP=<ファイル>` を付けると、比べた組(設定・入力・出力)を書き出します。Python のモデル(`tools/bex_model.py check`)で、リファレンスモデルとは別に照合できます。

### 8.3 テスト

| テスト | 内容 |
|---|---|
| bex_smoke_test | 値が変わらない設定(黒レベル 0、ゲイン 1.0倍)と、ふつうの設定で1フレームずつ |
| bex_bypass_test | bypass=1(黒レベル・ゲインを乱数にしても入力のまま出る) |
| bex_phase_test | Bayer の並び4種類。色ごとに違う黒レベル・ゲインにして、色の選び方を確かめる |
| bex_edge_test | 端の値: 黒レベル最大、ゲイン 0 / 最大、黒レベルちょうど・±1、丸めの境目(0.5倍)、飽和の境目、1転送だけのフレーム、1列だけ、2ラインだけ |
| bex_random_test | 設定・大きさ・画像・入力の間・出力の busy を乱数で組み合わせる。同じ設定でフレームを続けて送る場合もある |
| bex_stall_test | 入力は続けて送り、出力を長く止める(スキッドが埋まって o_busy=1 になることを確かめる) |
| bex_throughput_test | 止めないとき、入力・出力とも間なく流れ(1転送/クロック)、o_busy=0 のままで、レイテンシがすべて 3 であること |
| bex_reset_test | 転送の途中でリセットを3回、出力を止めてコアが満杯のときに1回かける。リセット中の o_vld=0 / o_busy=0、中のデータを捨てること、その後も正しく動くこと |
| bex_cfg_change_test | 前のフレームの出力が終わった後、設定と次のフレームの最初の転送を同じクロックで変える(4.7 の最も厳しい時刻) |
| bex_wave_test | 仕様書の波形図用(決まった並び) |

回帰試験(`sim/tests.list`)は、DUT を `BAYER_EX_CORE` にしたビルド(core)で 41 本、`BAYER_EX` にしたビルド(top)で 8 本、合わせて 49 本を、シードを変えて実行します。

### 8.4 機能カバレッジ

| covergroup.coverpoint | ビン |
|---|---|
| cg_cfg.cp_phase / cp_bypass / x_phase_bypass | Bayer の並び4種類 × bypass |
| cg_ch.cp_blc | チャネルごとの黒レベル: 0 / 途中 / 最大(16383) |
| cg_ch.cp_gain | チャネルごとのゲイン: 0 / 1.0倍未満 / 1.0倍 / 1.0倍超 / 最大(0xFFFF) |
| cg_pix.x_site_res | 色4種類 × 画素の結果(bypass / 黒レベル以下で 0 / 16383 で飽和 / ふつう) |
| cg_xfer.cp_flag | sof / eol / eof / 1転送だけのフレーム |
| cg_hs.cp_ev | 入力: 続けて転送・間をあけて転送・o_busy で止められた・スキッドが埋まった。出力: 続けて転送・間をあけて転送・i_busy で止められた・o_vld=0 のときの i_busy。設定と最初の転送が同じクロック。データがあるとき・空のときのリセット |

covergroup とは別に、同じビンを名前つきで数えて `[COVBIN]` としてログに出し、`tools/merge_cov.py` で回帰試験全体をまとめます(シミュレータによらずにまとめるため。BAYER2RGB と同じ方法)。

### 8.5 結果

Verilator 5.053 での結果です(`make regress`、`make cov`)。

| 項目 | 結果 |
|---|---|
| 回帰試験(49本: core 41、top 8) | PASS 49 / FAIL 0 |
| スコアボードで比べた転送 | 49本の合計 24,773 転送。不一致 0。レイテンシは最小 3(止めたときは最大 90 クロック) |
| 機能カバレッジ | 53 / 53 ビン(100%) |
| RTL のコードカバレッジ(行 / 分岐) | 71 / 71 行(100%)、80 / 80 分岐(100%) |
| Python のモデルとの照合 | 6本のテスト(bex_random_test ×2、bex_edge_test、bex_phase_test、bex_bypass_test、bex_reset_test)の 1,754 転送ですべて一致 |
| lint(Verilator -Wall、トップ BAYER_EX) | 警告 0(パッケージの使わない定数だけ `rtl/bayer_ex_lint.vlt` で除外) |

**変異テスト**

検証環境が誤りを見つけられることを確かめるため、RTL にわざと誤りを1つずつ入れて、主なテスト7本(smoke、bypass、phase、edge、stall、random ×2)を流しました。`sim/` で `python3 ../tools/bex_mutate.py` を実行すると再現できます(変異ごとに RTL をコピーして書き換え、`make build RTL_F=... OBJ=...` でビルドします)。

| 変異 | 入れた誤り | 結果 | 失敗したテスト | 出たエラー |
|---|---|---|---|---|
| m1_site | 色の位置の計算で phase の2ビットを入れ替える(PKG の f_site) | 検出 | 4 / 7 本: phase、stall、random(1)、random(2) | スコアボード 172 件 |
| m2_round | ゲインの丸めの定数を 2048 → 2047(PIXCOR) | 検出 | 4 / 7 本: smoke、phase、edge、random(2) | スコアボード 61 件 |
| m3_skid | スキッドに受け取らない。止まっている間の転送を落とす(CORE) | 検出 | 7 / 7 本: smoke、bypass、phase、edge、stall、random(1)、random(2) | スコアボード 374 件、o_busy=1 にならない 1 件、出力が終わらない 44 件 |
| m4_hold | 2段目のデータが、止まっている間(i_en=0)も変わる(PIXCOR) | 検出 | 7 / 7 本: smoke、bypass、phase、edge、stall、random(1)、random(2) | スコアボード 256 件、アサーション 291 件 |
| m5_bypass | bypass=1 でも2段目のゲインをかける(PIXCOR) | 検出 | 3 / 7 本: bypass、stall、random(1) | スコアボード 197 件 |
| m6_sat | ゲインの結果を飽和させず、下位14ビットを出す(PIXCOR) | 検出 | 6 / 7 本: smoke、phase、edge、stall、random(1)、random(2) | スコアボード 230 件 |

6 種類すべてで、どれかのテストが失敗しました(誤りを見つけた)。ゲインの丸め(m2_round)や bypass(m5_bypass)のように一部のテストでしか出ない誤りもあるので、回帰試験ではシードを変えて同じテストを何本も流しています。

### 8.6 Xcelium と波形

- `make xrun TEST=bex_smoke_test` で Xcelium で実行します(この環境にはないので未実行)。`XWAVES=vcd` で `waves.vcd` を出し、GTKWave で見られます。`XWAVES=shm` は SimVision 用です。
- Verilator では `make run TEST=... WAVES=1` で `waves.fst` を出します(`gtkwave waves.fst`)。
- この仕様書の波形図は、`make build TRACE=vcd` でビルドして bex_wave_test を流した `waves.vcd` から `doc/tools/gen_waves.py` で作りました。

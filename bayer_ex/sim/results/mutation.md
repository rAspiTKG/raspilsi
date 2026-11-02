# 変異テストの結果(2026-10-31)

RTL にわざと誤りを1つずつ入れて、主なテスト7本(smoke、bypass、phase、edge、stall、random ×2。シード 11、12)を流した結果です。
`sim/` で `python3 ../tools/bex_mutate.py` を実行すると、同じ結果が `sim/mut/result.md` にできます。

| 変異 | 入れた誤り | 結果 | 失敗したテスト | 出たエラー |
|---|---|---|---|---|
| m1_site | 色の位置の計算で phase の2ビットを入れ替える(PKG の f_site) | 検出 | 4 / 7 本: phase、stall、random(1)、random(2) | スコアボード 172 件 |
| m2_round | ゲインの丸めの定数を 2048 → 2047(PIXCOR) | 検出 | 4 / 7 本: smoke、phase、edge、random(2) | スコアボード 61 件 |
| m3_skid | スキッドに受け取らない。止まっている間の転送を落とす(CORE) | 検出 | 7 / 7 本: smoke、bypass、phase、edge、stall、random(1)、random(2) | スコアボード 374 件、o_busy=1 にならない 1 件、出力が終わらない 44 件 |
| m4_hold | 2段目のデータが、止まっている間(i_en=0)も変わる(PIXCOR) | 検出 | 7 / 7 本: smoke、bypass、phase、edge、stall、random(1)、random(2) | スコアボード 256 件、アサーション 291 件 |
| m5_bypass | bypass=1 でも2段目のゲインをかける(PIXCOR) | 検出 | 3 / 7 本: bypass、stall、random(1) | スコアボード 197 件 |
| m6_sat | ゲインの結果を飽和させず、下位14ビットを出す(PIXCOR) | 検出 | 6 / 7 本: smoke、phase、edge、stall、random(1)、random(2) | スコアボード 230 件 |

検出 6 / 6

# 検証結果(2026-10-31、Verilator 5.053)

| ファイル | 内容 |
|---|---|
| `regress.txt` | 回帰試験(`make regress`、49本: DUT=BAYER_EX_CORE 41、DUT=BAYER_EX 8)の結果 |
| `regress_cov.txt` | カバレッジ付きの回帰試験(`make cov`、49本)の結果 |
| `functional_coverage.md` | 機能カバレッジ(`tools/merge_cov.py` で49本のログをまとめたもの) |
| `code_coverage.md` | RTL のコードカバレッジ(`tools/cov_summary.py`) |
| `check_model.txt` | `+BEX_DUMP` で出した組(設定・入力・出力)と Python モデル(`tools/bex_model.py check`)の照合 |
| `mutation.md` | 変異テスト(RTL にわざと誤りを入れて、テストが失敗することを確かめた結果。`tools/bex_mutate.py` の出力) |
| `lint_summary.txt` | `make lint`(Verilator -Wall、トップ BAYER_EX)の警告数 |

詳しくは仕様書 8章を見てください。

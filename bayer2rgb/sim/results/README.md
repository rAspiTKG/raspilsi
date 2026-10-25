# 検証結果(2026-10-25、Verilator 5.053)

| ファイル | 内容 |
|---|---|
| `regress.txt` | 回帰試験(`make regress`、89本)の結果 |
| `regress_cov.txt` | カバレッジ付きの回帰試験(`make cov`、89本)の結果 |
| `functional_coverage.md` | 機能カバレッジ(`tools/merge_cov.py` で89本のログをまとめたもの) |
| `code_coverage.md` | RTL のコードカバレッジ(`tools/cov_summary.py`) |
| `verilator_coverage_summary.txt` | `verilator_coverage` の集計(UVM などを含む全体。covergroup の行が機能カバレッジ) |
| `check_dumps.txt` | `+B2R_DUMP` で出したフレームと Python モデルの照合 |
| `lint_summary.txt` | `make lint`(Verilator -Wall)の警告数(PPC=8/4/2/1) |

詳しくは仕様書 13章を見てください。

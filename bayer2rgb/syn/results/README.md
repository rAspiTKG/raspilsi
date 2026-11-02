# 論理合成の結果(2026-10-25)

`syn/yosys` の `make`(Yosys 0.48+5、sv2v v0.0.13、OpenSTA 2.6.0、ASAP7 RVT の WC コーナー)の出力の写しです。

| ファイル | 内容 |
|---|---|
| `asap7_ppc8/area_summary.md` | モジュールごとのセル数と面積(`scripts/area_summary.py`) |
| `asap7_ppc8/area.txt` | Yosys の `stat`(セルの種類ごとの数、モジュールごと) |
| `asap7_ppc8/check.txt` | Yosys の `check`(問題 0 件) |
| `asap7_ppc8/sta_summary.txt` | 合成後の STA のまとめ(クロック、最悪の余裕、TNS) |
| `asap7_ppc8/sta_setup.txt` / `sta_hold.txt` | クロックの組み合わせごとの最も遅い・速い経路(配線の遅れなし) |
| `asap7_ppc8/sta_drv.txt` | 遷移時間・容量・ファンアウトの違反 |
| `asap7_ppc8/sta_cdc.txt` / `sta_cdc_paths.txt` | clk 側と ctrl_clk 側の間の経路の終点の数と、最も遅い経路(仕様書 11.2) |
| `asap7_ppc8/sram_macros.txt` | SRAM の仮マクロの一覧(大きさ、端子数、読み出しの遅れ) |
| `asap7_ppc4/`、`asap7_ppc2/`、`asap7_ppc1/` | PPC=4/2/1 の面積の表、STA のまとめ、CDC の経路の数、SRAM の一覧(`make PPC=<n>`) |

時間の単位は ps、容量は fF です(ASAP7 のライブラリの単位)。説明は仕様書 14.3 を見てください。

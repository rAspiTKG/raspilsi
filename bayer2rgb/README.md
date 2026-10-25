# BAYER2RGB

メモリ上の Bayer 画像(14bit)を RGB888 に変換してメモリへ書き戻す IP です(SystemVerilog)。黒レベル補正、ホワイトバランス、バイリニア補間、エッジ部の彩度抑制、ガンマを内蔵しています。

- 制御: AXI4-Lite スレーブ(`ctrl_clk`)、割り込み `irq`
- データ: AXI4 マスタ(`clk`、128bit / 40bit)
- 最大 3840×2160、1クロック 8画素(PPC=1/2/4/8 を選択可)、400 MHz で 4K 1フレーム 約 3.9 ms

仕様の詳細は [doc/spec/BAYER2RGB_spec.md](doc/spec/BAYER2RGB_spec.md) を見てください。

![BAYER2RGB トップ階層](doc/arch/bayer2rgb_top.svg)

## ディレクトリ

| パス | 内容 |
|---|---|
| `rtl/` | RTL(`rtl.f`)。`BAYER2RGB.sv` がトップ |
| `model/` | 製品IP(SRAM、同期化セル)の振る舞いモデル(`model.f`) |
| `tb/` | UVM 検証環境(`tb.f`、`tb/uvm/`) |
| `sim/` | Makefile、回帰試験(`run_regress.sh`、`tests.list`)、Xcelium の波形設定(`xrun_waves.tcl`) |
| `tools/` | Python のリファレンスモデル(`b2r_model.py`)、画像の生成・変換、照合、カバレッジの集計、コーディング規約の検査 |
| `doc/arch/` | ブロック図(`bayer2rgb_arch.drawio`、SVG) |
| `doc/spec/` | 仕様書、端子表(`pins/`)、波形図(`wave/`: WaveDrom の JSON と SVG) |
| `doc/tools/` | ブロック図・端子表・波形図・仕様書を作るスクリプト |

## 使い方

必要なもの: Verilator 5.053 以降、UVM 1800.2-2017-1.0(Verilator で使える版)、zlib と lz4(FST 出力)、Python 3(numpy、Pillow)。Xcelium でも動かせるようにしています(未実行。仕様書 14.3)。

```sh
export UVM_HOME=/path/to/uvm-2017-1.0   # src/uvm_pkg.sv があるディレクトリ
cd sim
make lint                                # RTL の lint
make run TEST=b2r_smoke_test             # Verilator で1テスト
make run TEST=b2r_random_test SEED=3 WAVES=1   # 波形 → gtkwave waves.fst
make regress                             # 回帰試験(logs/regress.txt)
make cov                                 # カバレッジ付き回帰試験(cov/)
make xrun TEST=b2r_smoke_test XWAVES=vcd # Xcelium(waves.vcd → GTKWave)
```

FST の出力に必要な lz4 / zlib を標準以外の場所に入れた場合は `VL_CFLAGS=-I<dir>/include VL_LDFLAGS=-L<dir>/lib` を付けてください。

## 検証の状況

Verilator 5.053 での結果です(詳細は `sim/results/` と仕様書 13章)。

| 項目 | 結果 |
|---|---|
| 回帰試験(89本: PPC=8/4/2/1、同期化セルの乱数遅延、クロック比の組み合わせ) | PASS 89 / FAIL 0 |
| リファレンスモデルとの照合 | 全フレームでビット一致(SV モデル。Python モデルとも 122 フレームで一致) |
| 機能カバレッジ | 93 / 93 ビン(100%) |
| RTL コードカバレッジ | 行 98.6%、分岐 97.7%(残りは到達しない部分のみ) |
| lint(Verilator -Wall) | 警告 0(PPC=8/4/2/1) |

## 量産に向けて残っている作業

- SRAM マクロと同期化セルFoundryの製品IPに置き換える(仕様書 12章)
- 論理合成と静的タイミング解析(400 MHz)、CDC 検証ツールでの確認(仕様書 11章)
- Xcelium での回帰試験とカバレッジ
- DFT(スキャン、メモリ BIST)の挿入

## コーディング規約

- `if( 条件 )`、`for( 初期化; 条件; 処理 )`、`while( 条件 )`。条件の中にはスペースを入れない
- begin / end は省略しない。`end else begin` は1行に書く。インデントは2スペース
- ポート・パラメータ・インスタンスの接続は先頭にカンマを置く(`,.rst_n (rst_n)`)
- AXI のポートは `大文字モジュール名_用途_AXIポート名`(`BAYER2RGB_MEM_AWADDR`)、内部信号は `s_`、FF は `r_` で始める

`python3 tools/style_check.py rtl model tb tools doc/tools` で規約の一部(if / for / while の書き方、begin の位置、インデント、1行1文)を検査できます。

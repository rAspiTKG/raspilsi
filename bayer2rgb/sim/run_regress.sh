#!/bin/bash
# ============================================================================
# 回帰試験: tests.list のテストを必要なビルドで実行し、結果を logs/regress.txt にまとめる
#   環境変数
#     UVM_HOME   UVM 1800.2-2017-1.0 のディレクトリ(必須)
#     COVERAGE=1 コードカバレッジを取る(cov/*.dat)
#     ONLY=<文字列>  テスト名にこの文字列を含む行だけ実行する
#     JOBS=<n>   同時に実行するテストの数(既定 2)
# ============================================================================
set -u
cd "$(dirname "$0")"
LIST=${LIST:-tests.list}
JOBS=${JOBS:-2}
COVERAGE=${COVERAGE:-0}
ONLY=${ONLY:-}
mkdir -p logs
[ "$COVERAGE" = "1" ] && mkdir -p cov

# ビルド名 → make の変数
build_vars() {
  case "$1" in
    ppc8) echo "PPC=8" ;;
    ppc4) echo "PPC=4" ;;
    ppc2) echo "PPC=2" ;;
    ppc1) echo "PPC=1" ;;
    cdc)  echo "PPC=8 CDC_RANDOM=1" ;;
    *)    echo "unknown" ;;
  esac
}

builds=$(grep -v '^\s*#' "$LIST" | awk 'NF>0 {print $1}' | sort -u)
for b in $builds; do
  vars=$(build_vars "$b")
  if [ "$vars" = "unknown" ]; then
    echo "不明なビルド: $b"
    exit 1
  fi
  echo "### build $b ($vars)"
  make --no-print-directory build $vars COVERAGE="$COVERAGE" || exit 1
done

obj_of() {
  local tag=""
  case "$1" in
    cdc) tag="_cdc" ;;
  esac
  [ "$COVERAGE" = "1" ] && tag="${tag}_cov"
  case "$1" in
    ppc8|cdc) echo "obj_ppc8${tag}" ;;
    ppc4) echo "obj_ppc4${tag}" ;;
    ppc2) echo "obj_ppc2${tag}" ;;
    ppc1) echo "obj_ppc1${tag}" ;;
  esac
}

run_one() {
  local b=$1 t=$2 s=$3 pa=$4 n=$5
  local obj log
  obj=$(obj_of "$b")
  log="logs/${b}_${t}_n${n}_s${s}.log"
  local covarg=""
  [ "$COVERAGE" = "1" ] && covarg="+verilator+coverage+file+cov/${b}_${t}_n${n}_s${s}.dat"
  # shellcheck disable=SC2086
  "./${obj}/Vtb_top" +UVM_TESTNAME="$t" +verilator+seed+"$s" +verilator+rand+reset+2 \
    +UVM_VERBOSITY=UVM_LOW $pa $covarg > "$log" 2>&1
  if grep -q "TEST PASSED" "$log" && ! grep -q "^%Error" "$log"; then
    echo "PASS $b $t seed=$s $pa"
  else
    echo "FAIL $b $t seed=$s $pa  ($log)"
  fi
}

: > logs/regress.txt
n=0
running=0
while read -r b t ns rest; do
  [ -z "${b:-}" ] && continue
  case "$b" in \#*) continue ;; esac
  if [ -n "$ONLY" ] && [[ "$t" != *"$ONLY"* ]]; then
    continue
  fi
  pa=$(echo "${rest:-}" | sed 's/#.*//')
  n=$((n+1))
  for ((k=1; k<=ns; k++)); do
    seed=$((n*100+k))
    run_one "$b" "$t" "$seed" "$pa" "$n" >> logs/regress.txt &
    running=$((running+1))
    if [ "$running" -ge "$JOBS" ]; then
      wait -n
      running=$((running-1))
    fi
  done
done < <(grep -v '^\s*#' "$LIST")
wait

npass=$(grep -c '^PASS' logs/regress.txt)
nfail=$(grep -c '^FAIL' logs/regress.txt)
sort -o logs/regress.txt logs/regress.txt
echo "----"
grep '^FAIL' logs/regress.txt
echo "合計: PASS=${npass} FAIL=${nfail}"
[ "$nfail" = "0" ]

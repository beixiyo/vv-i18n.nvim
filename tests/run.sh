#!/usr/bin/env bash
# vv-i18n 回归：headless 挂真实模块 + react-tool 真实 locale
# 逐个 *_spec.lua 各起一个隔离 nvim（每个 spec 末尾 qa!），汇总通过/失败
DIR="$(cd "$(dirname "$0")" && pwd)"

total_pass=0
total_fail=0

run_spec() {
  local spec="$1"
  echo "── ${spec##*/} ──"
  local out
  out="$(nvim --headless -n -i NONE --cmd 'set noswapfile shadafile=NONE' -u NONE \
    -c "luafile $spec" 2>&1 | grep -E 'PASS:|FAIL:|==')"
  echo "$out"
  local p f
  p="$(echo "$out" | grep -c '^PASS:')"
  f="$(echo "$out" | grep -c '^FAIL:')"
  total_pass=$((total_pass + p))
  total_fail=$((total_fail + f))
  echo
}

for spec in "$DIR"/writer_spec.lua "$DIR"/index_spec.lua "$DIR"/resolver_spec.lua \
            "$DIR"/init_spec.lua "$DIR"/integration_spec.lua "$DIR"/panel_spec.lua; do
  run_spec "$spec"
done

echo "════════════════════════════════════"
echo "总计: ${total_pass} PASS / ${total_fail} FAIL"
[ "$total_fail" -eq 0 ]

#!/usr/bin/env bash
# vv-i18n 回归：headless 挂真实模块 + react-tool 真实 locale
# 逐个 *_spec.lua 各起一个隔离 nvim（每个 spec 末尾 qa!），汇总通过/失败
DIR="$(cd "$(dirname "$0")" && pwd)"
NVIM_BIN="${NVIM_BIN:-nvim}"

total_pass=0
total_fail=0
process_fail=0

run_spec() {
  local spec="$1"
  echo "── ${spec##*/} ──"
  local raw status out summary p f
  if raw="$("$NVIM_BIN" --headless -n -i NONE --cmd 'set noswapfile shadafile=NONE' -u NONE \
    -c "luafile $spec" 2>&1)"; then
    status=0
  else
    status=$?
    process_fail=1
  fi
  out="$(printf '%s\n' "$raw" | grep -E 'PASS:|FAIL:|==' || true)"
  echo "$out"
  if [ "$status" -ne 0 ]; then
    echo "Neovim exited with status $status"
    printf '%s\n' "$raw" | grep -v -E 'PASS:|FAIL:|==' || true
  fi
  summary="$(printf '%s\n' "$raw" | grep -oE '== [0-9]+ PASS / [0-9]+ FAIL ==' | tail -n 1 || true)"
  if [ -z "$summary" ]; then
    echo "Missing test summary"
    process_fail=1
    echo
    return
  fi
  p="$(printf '%s\n' "$summary" | sed -E 's|^== ([0-9]+) PASS / ([0-9]+) FAIL ==$|\1|')"
  f="$(printf '%s\n' "$summary" | sed -E 's|^== ([0-9]+) PASS / ([0-9]+) FAIL ==$|\2|')"
  total_pass=$((total_pass + p))
  total_fail=$((total_fail + f))
  echo
}

verify_failure_gate() {
  local fixture="$DIR/runner_failure_fixture.lua"
  local raw
  echo "── ${fixture##*/} (expected failure) ──"
  if raw="$("$NVIM_BIN" --headless -n -i NONE --cmd 'set noswapfile shadafile=NONE' -u NONE \
    -c "luafile $fixture" 2>&1)"; then
    echo "FAIL: assertion failure returned exit 0"
    process_fail=1
  elif printf '%s\n' "$raw" | grep -q '== 1 PASS / 1 FAIL =='; then
    echo "PASS: assertion failure returned non-zero even with merged output"
  else
    echo "FAIL: assertion failure fixture did not reach its summary"
    printf '%s\n' "$raw"
    process_fail=1
  fi
  echo
}

for spec in "$DIR"/writer_spec.lua "$DIR"/index_spec.lua "$DIR"/resolver_spec.lua \
            "$DIR"/init_spec.lua "$DIR"/integration_spec.lua "$DIR"/panel_model_spec.lua \
            "$DIR"/panel_spec.lua "$DIR"/references_spec.lua "$DIR"/references_async_spec.lua; do
  run_spec "$spec"
done

verify_failure_gate

echo "════════════════════════════════════"
echo "总计: ${total_pass} PASS / ${total_fail} FAIL"
[ "$process_fail" -eq 0 ] && [ "$total_fail" -eq 0 ]

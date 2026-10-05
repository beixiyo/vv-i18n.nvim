# 仅声明已有源码和 runtime；在隔离 HOME/工作目录前解析
vv_test_dependency VV_TEST_ICONS vv-icons.nvim lua/vv-icons/init.lua
vv_test_path VV_TEST_PARSERS "$VV_TEST_SITE" \
  parser/typescript.so parser/tsx.so parser/javascript.so parser/json.so
vv_test_runtime VV_TEST_PARSERS
# 高亮查询文件可与 parser 放在一起，也可由 nvim-treesitter 提供
# TS/TSX/JS 继承 ecma 和 jsx 查询；也要校验这些实际查询文件
if [ -z "${VV_TEST_QUERIES:-}" ] && [ -f "$VV_TEST_PARSERS/queries/typescript/highlights.scm" ]; then
  VV_TEST_QUERIES=$VV_TEST_PARSERS
fi
vv_test_dependency VV_TEST_QUERIES nvim-treesitter \
  queries/typescript/highlights.scm queries/tsx/highlights.scm \
  queries/javascript/highlights.scm queries/json/highlights.scm \
  queries/ecma/highlights.scm queries/jsx/highlights.scm
vv_test_runtime VV_TEST_QUERIES

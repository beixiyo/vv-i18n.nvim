-- parser 只由显式本地依赖注入；不读取个人 Neovim 配置或下载
for _, lang in ipairs({ 'typescript', 'tsx', 'javascript', 'json' }) do
  local ok, err = pcall(vim.treesitter.language.add, lang)
  assert(ok, '本机 parser 缺失：' .. lang .. '：' .. tostring(err))
  assert(vim.treesitter.query.get(lang, 'highlights'), '高亮查询（含继承）缺失：' .. lang)
end

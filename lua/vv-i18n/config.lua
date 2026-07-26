-- Configuration owner. Callers only receive deep-copy snapshots.
local M = {}

---@type VVI18nConfig
local defaults = {
  root = nil,
  sources = {},
  hooks = { 'useTranslation' },
  t = { 't' },
  lang = { '{lang}.ts', '{lang}.tsx', '{lang}.js', '{lang}.json' },
  mount = 'top-key',
  namespace = 'hook-arg',
  namespace_separator = ':',
  key_separator = '.',
  quote_style = 'auto',
  indent = nil,
  display = {
    enable = true,
    lang = nil,
    preferred_langs = {},
    max_width = 40,
    icon = '󰗊 ',                  -- 译文前缀图标（i18n 图标）
    missing_icon = '⚠ ',
    hl = 'VVI18nPreview',         -- 译文高亮组
    missing_hl = 'VVI18nMissing', -- 缺失高亮组
    style = nil,                  -- 直接定义译文样式 { fg=, bg=, italic=, bold= }；nil=默认(注释色+斜体)
    missing_style = nil,          -- 缺失样式；nil=默认 link DiagnosticVirtualTextWarn
    render = nil,                 -- 函数自定义：fun(ctx)->string|{{text,hl},..}|nil；nil=默认(图标+译文)
  },
  panel = {
    width = 56,
    position = 'right',
    state = nil,
    mappings = nil,
    on_attach = nil,
    help = nil,
    render = nil,
  },
  references = {
    enable = true,
    icon = '󰗊 ',
    hl = 'Comment',
    jump_single = false,
    show_zero = false,
    render = nil,
    panel = {
      width = 62,
      position = 'right',
      preview_debounce_ms = 80,
      state = nil,
      mappings = nil,
      on_attach = nil,
      help = nil,
      render = nil,
    },
  },
  ft = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  project_config = true,   -- 探测项目根 .vv-i18n.lua（vim.secure 首次信任后全覆盖本配置）
  parse = nil,             -- 自定义读侧解析 fn(content, path)->{ leaves, top_keys? }；nil=默认 tree-sitter（JS/JSON）
}


local current = vim.deepcopy(defaults)
local base = vim.deepcopy(defaults)

function M.make(opts)
  local cfg = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  if opts then
    for _, key in ipairs({ 'sources', 't', 'hooks', 'ft', 'lang', 'mount', 'namespace' }) do
      if opts[key] ~= nil then cfg[key] = opts[key] end
    end
    if opts.display and opts.display.preferred_langs ~= nil then
      cfg.display.preferred_langs = opts.display.preferred_langs
    end
    if opts.panel ~= nil then
      cfg.panel = vim.tbl_deep_extend('force', vim.deepcopy(defaults.panel), opts.panel)
    end
    if opts.references and opts.references.panel ~= nil then
      cfg.references.panel = vim.tbl_deep_extend('force', vim.deepcopy(defaults.references.panel), opts.references.panel)
    end
  end
  return cfg
end

function M.setup(opts)
  base = M.make(opts)
  current = vim.deepcopy(base)
  return M.snapshot()
end

function M.activate(opts)
  current = M.make(opts or base)
  return M.snapshot()
end

function M.base()
  return vim.deepcopy(base)
end

function M.snapshot()
  return vim.deepcopy(current)
end

return M

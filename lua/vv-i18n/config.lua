-- 配置归属模块：setup(opts) 与项目根 .vv-i18n.lua 共用同一个 make() 归一化
-- 调用方只能获取深拷贝快照；运行时依赖（state 句柄）由 setup 第二参数注入，合并后派生
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
  ignore_key = nil,
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
    mappings = nil,
    on_attach = nil,
    help = nil,
    render = nil,
  },
  references = {
    enable = true,
    icon = '󰗊 ',
    icon_hl = 'VVI18nReferenceIcon',   -- 图标高亮组；默认 link Special（对齐 vv-symbols）
    icon_style = nil,                  -- 直接定义图标样式；nil=默认 link Special
    label = 'refs',                    -- 计数标签文案
    hl = 'Comment',
    count_hl = 'VVI18nReferenceCount',  -- 引用数数字高亮组；默认 link Special
    count_style = nil,                  -- 直接定义数字样式 { fg=, bold= }；nil=默认 link Special
    jump_single = false,
    show_zero = false,
    render = nil,
    scanners = {},
    panel = {
      width = 62,
      position = 'right',
      preview_debounce_ms = nil, -- nil 交给 vv-utils tree_panel 的默认值
      mappings = nil,
      on_attach = nil,
      help = nil,
      render = nil,
    },
  },
  unused = {
    copy = {
      render = nil,
      definition_language = 'en',
      include_values = false,
    },
    panel = {
      width = 68,
      position = 'right',
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


-- 列表字段：给出即整体替换（含空数组），不依赖 tbl_deep_extend 的列表判定
local replace_keys = { 'sources', 't', 'hooks', 'ft', 'lang', 'mount', 'namespace' }

---@type VVI18nDeps
local deps = {}

local current = vim.deepcopy(defaults)
local base = vim.deepcopy(defaults)

--- 把用户输入（setup 或 .vv-i18n.lua）归一化为完整配置，并挂上 deps 派生的 state
---@param opts? VVI18nOpts
---@return VVI18nConfig
function M.make(opts)
  local cfg = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

  if opts then
    for _, key in ipairs(replace_keys) do
      if opts[key] ~= nil then cfg[key] = opts[key] end
    end

    if opts.display and opts.display.preferred_langs ~= nil then
      cfg.display.preferred_langs = opts.display.preferred_langs
    end
  end

  -- 派生值：合并后再赋值；nil 时由各面板使用自身的共享状态
  cfg.panel.state = deps.panel_state
  cfg.references.panel.state = deps.references_state
  cfg.unused.panel.state = deps.unused_state

  return cfg
end

---@param opts? VVI18nOpts
---@param runtime_deps? VVI18nDeps 运行时依赖（如 state 句柄），不属于用户配置
---@return VVI18nConfig
function M.setup(opts, runtime_deps)
  deps = runtime_deps or {}
  base = M.make(opts)
  current = vim.deepcopy(base)
  return M.snapshot()
end

--- 项目配置（.vv-i18n.lua）激活或回落到 setup 配置；与 setup 走同一个 make()
---@param opts? VVI18nOpts
---@return VVI18nConfig
function M.activate(opts)
  -- base 已经过 make()，回落时直接复制，结果与再归一化一次相同
  if opts then
    current = M.make(opts)
  else
    current = vim.deepcopy(base)
  end

  return M.snapshot()
end

---@return VVI18nConfig
function M.base()
  return vim.deepcopy(base)
end

---@return VVI18nConfig
function M.snapshot()
  return vim.deepcopy(current)
end

return M

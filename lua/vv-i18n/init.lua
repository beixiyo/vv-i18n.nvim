-- vv-i18n.nvim — TS/TSX i18n 的预览 / 跳转 / 同步改（对标 lokalise · i18n-ally）
--
-- 让两套映射对齐到同一全键空间：文件侧（locale 文件里的 key → 全键）与调用侧
-- （源码 t('字面量') → 全键）。每个 source 描述一处来源，global 提供默认、source 可逐项覆盖
-- locale 来源 / 文件→语言 / 文件→命名空间(mount) / 调用点→前缀(namespace) 均「字面量或函数」
--
-- 内核全 tree-sitter：ast / reader / index / writer / resolver / display / editor / panel
-- 依赖：Neovim >= 0.13、tree-sitter typescript/tsx、vv-utils。布局与配置见 README
--
-- 用户命令：VVI18nKeys / Edit / Info / Jump / SetValue / AddKey / Reload / 预览开关
local ast = require('vv-i18n.ast')
local resolver = require('vv-i18n.resolver')
local Index = require('vv-i18n.index')
local writer = require('vv-i18n.writer')

local M = {}

---@class VVI18nSource
---@field prefix? string         命名空间根；''=无前缀 @default ''
---@field root? string           本源扫描根（相对 config.root 或绝对） @default config.root
---@field discover? string[]|fun(root: string): string[]  发现 locale 目录：glob 数组 或 函数 @default nil
---@field dirs? string[]         显式 locale 目录（与 discover 叠加） @default nil
---@field lang? string|string[]|fun(path): (string|table|nil)  文件→语言（覆盖全局）
---@field mount? 'top-key'|'filename'|'flat'|fun(ctx): string?  文件→命名空间（覆盖全局）
---@field namespace? 'flat'|'hook-arg'|'fixed'|'two-level'|fun(ctx): string?  调用点→前缀（覆盖全局）
---@field hooks? string[]        产出 t 的 hook 名（覆盖全局）
---@field t? string[]            翻译函数名（覆盖全局）
---@field parse? fun(content: string, path: string): table?  自定义读侧解析（覆盖全局）

---@class VVI18nConfig
---@field root? string           项目根；nil=自动探测 @default nil
---@field sources VVI18nSource[]  locale 来源（必填，可多个） @default {}
---@field hooks string[]         全局默认 hook 名 @default {'useTranslation'}
---@field t string[]             全局默认翻译函数名 @default {'t'}
---@field lang string|string[]|function  全局默认 文件→语言 @default {'{lang}.ts','{lang}.tsx','{lang}.js','{lang}.json'}
---@field mount string|function  全局默认 mount @default 'top-key'
---@field namespace string|function  全局默认 namespace @default 'hook-arg'
---@field namespace_separator string  绝对命名空间 ns<sep>key @default ':'
---@field key_separator string   全键各段连接符 @default '.'
---@field quote_style 'single'|'double'|'auto'  写回引号 @default 'auto'
---@field indent? string         写回缩进；nil=推断 @default nil
---@field display VVI18nDisplayConfig
---@field ft string[]            生效文件类型 @default ts/tsx/js/jsx
---@field project_config boolean 探测项目根 .vv-i18n.lua（首次信任后全覆盖本配置） @default true
---@field parse? fun(content: string, path: string): table?  自定义读侧解析（YAML/PO 等）；返回 { leaves: VVI18nLeaf[], top_keys?: string[] }。nil=默认 tree-sitter（JS/JSON）

---@class VVI18nLeaf  自定义 parse 须返回的叶子（与默认 reader 同形）
---@field path string[]          文件内逐层 key，如 { 'hero', 'title' }
---@field dotted string          点号路径 'hero.title'（拼全键用）
---@field kind 'string'|'array'|'other'  仅 'string' 可同步编辑
---@field value string           string→真实值；其它→原始文本
---@field row integer            值起点行（0-based，跳转用）
---@field col integer            值起点列（0-based）

---@class VVI18nDisplayConfig
---@field enable boolean         @default true
---@field lang? string           固定预览语言 @default nil
---@field preferred_langs string[]  预览首选语言优先级 @default {}
---@field max_width integer      译文最大显示宽度 @default 40
---@field icon string            译文前缀图标 @default '󰗊 '
---@field missing_icon string    @default '⚠ '
---@field hl string              译文高亮组 @default 'VVI18nPreview'
---@field missing_hl string      缺失高亮组 @default 'VVI18nMissing'
---@field style? vim.api.keyset.highlight  直接定义译文样式；nil=默认 注释色+斜体
---@field missing_style? vim.api.keyset.highlight  缺失样式；nil=默认 link DiagnosticVirtualTextWarn
---@field render? fun(ctx: VVI18nRenderCtx): (string|table[]|nil)  自定义渲染：返回字符串 / virt_text chunks / nil(落默认)

---@class VVI18nRenderCtx  display.render 收到的上下文
---@field full_key string        完整键（含前缀/命名空间）
---@field value? string          选中语言的译文（缺失/非字符串时为 nil）
---@field lang? string           选中的预览语言
---@field kind 'hit'|'missing'   命中 / 缺失
---@field missing boolean
---@field per table              该键各语言条目
---@field literal string         源码里 t() 的字面量键
---@field icon string            配置的图标
---@field hl string              配置的高亮组
---@field max_width integer

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
  ft = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  project_config = true,   -- 探测项目根 .vv-i18n.lua（vim.secure 首次信任后全覆盖本配置）
  parse = nil,             -- 自定义读侧解析 fn(content, path)->{ leaves, top_keys? }；nil=默认 tree-sitter（JS/JSON）
}

local PROJECT_FILE = '.vv-i18n.lua'

local config = vim.deepcopy(defaults)   -- 当前生效配置（table 标识稳定，原地更新，display 等持有引用者随之可见）
local base_config = config              -- setup 注入的基线（项目无 .vv-i18n.lua 时回退到它）
local state = { root = nil, indexes = nil, errors = {}, project_file = nil }

--------------------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------------------

local function to_set(list)
  local s = {}; for _, n in ipairs(list or {}) do s[n] = true end; return s
end

local function abspath(p, root)
  if vim.startswith(p, '/') then return p end
  return root .. '/' .. p
end

local function buf_lang(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == 'typescriptreact' or ft == 'javascriptreact' then return 'tsx' end
  if ft == 'javascript' then return 'javascript' end
  return 'typescript'
end

-- 把 opts 合并成完整配置（defaults 兜底 + list/函数字段整体覆盖，不被 deep_extend 按下标混合）
local function make_config(opts)
  local cfg = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  if opts then
    for _, k in ipairs({ 'sources', 't', 'hooks', 'ft', 'lang', 'mount', 'namespace' }) do
      if opts[k] ~= nil then cfg[k] = opts[k] end
    end
    if opts.display and opts.display.preferred_langs ~= nil then
      cfg.display.preferred_langs = opts.display.preferred_langs
    end
  end
  return cfg
end

-- 原地把 config 替换成 new 的内容（保持 config 表标识不变，display 等持有引用者立即可见）
local function set_config(new)
  if new == config then return end   -- 同一张表，无需(也不能)清空再拷
  for k in pairs(config) do config[k] = nil end
  for k, v in pairs(new) do config[k] = v end
end

-- 译文 / 缺失 高亮：style 给了就直接定义，否则默认（注释色 + 斜体 / link 诊断警告），随主题刷新
local function apply_display_hl()
  local d = config.display
  if d.style then
    pcall(vim.api.nvim_set_hl, 0, d.hl, d.style)
  else
    local ok, base = pcall(vim.api.nvim_get_hl, 0, { name = 'Comment', link = false })
    pcall(vim.api.nvim_set_hl, 0, d.hl, { fg = ok and base and base.fg or nil, italic = true })
  end
  if d.missing_style then
    pcall(vim.api.nvim_set_hl, 0, d.missing_hl, d.missing_style)
  else
    pcall(vim.api.nvim_set_hl, 0, d.missing_hl, { link = 'DiagnosticVirtualTextWarn', default = true })
  end
end

-- 从当前 buffer 向上找 .vv-i18n.lua，vim.secure 首次信任后加载（返回项目配置 + 所在目录）
---@return table? opts
---@return string? dir
local function load_project_config()
  if not config.project_config then return nil end
  local bufname = vim.api.nvim_buf_get_name(0)
  local base = bufname ~= '' and vim.fs.dirname(bufname) or vim.uv.cwd()
  local found = vim.fs.find(PROJECT_FILE, { upward = true, path = base, type = 'file' })[1]
  if not found then return nil end
  local ok, content = pcall(vim.secure.read, found)   -- 首次弹窗信任；拒绝 / 内容变动 → nil / 重弹
  if not ok or type(content) ~= 'string' then return nil end
  local chunk = load(content, '@' .. found)
  if not chunk then return nil end
  local rok, ret = pcall(chunk)
  if rok and type(ret) == 'table' then return ret, vim.fs.dirname(found) end
  return nil
end

--------------------------------------------------------------------------------
-- 根探测 + 索引生命周期
--------------------------------------------------------------------------------

local function find_root(start)
  local base = start
  if not base then
    local bufname = vim.api.nvim_buf_get_name(0)
    base = bufname ~= '' and vim.fs.dirname(bufname) or vim.uv.cwd()
  end
  local marker = vim.fs.find({ 'pnpm-workspace.yaml', 'nx.json', 'turbo.json' }, { path = base, upward = true })[1]
  if marker then return vim.fs.dirname(marker) end
  local any = vim.fs.find({ '.git', 'package.json' }, { path = base, upward = true })[1]
  return any and vim.fs.dirname(any) or vim.uv.cwd()
end

--- 合并 global 默认 + source 覆盖
local function norm_source(raw)
  return {
    prefix    = raw.prefix or '',
    root      = raw.root,
    discover  = raw.discover,
    dirs      = raw.dirs,
    lang      = raw.lang ~= nil and raw.lang or config.lang,
    mount     = raw.mount ~= nil and raw.mount or config.mount,
    namespace = raw.namespace ~= nil and raw.namespace or config.namespace,
    hooks     = raw.hooks or config.hooks,
    t         = raw.t or config.t,
    parse     = raw.parse ~= nil and raw.parse or config.parse,
  }
end

local function source_dirs(s, project_root)
  local root = s.root and abspath(s.root, project_root) or project_root
  local dirs = {}
  if type(s.discover) == 'table' then
    vim.list_extend(dirs, Index.discover_by_patterns(root, s.discover))
  elseif type(s.discover) == 'function' then
    vim.list_extend(dirs, s.discover(root) or {})
  end
  for _, d in ipairs(s.dirs or {}) do dirs[#dirs + 1] = abspath(d, root) end
  return dirs
end

--- 构建（或重建）全部来源索引
function M.reload()
  -- 项目级配置：有 .vv-i18n.lua 就全覆盖，否则回退 setup 基线
  local proj, proj_dir = load_project_config()
  set_config(proj and make_config(proj) or base_config)
  state.project_file = proj and proj_dir or nil
  apply_display_hl()

  state.root = config.root or proj_dir or find_root()
  state.indexes = {}
  state.errors = {}
  for _, raw in ipairs(config.sources) do
    local s = norm_source(raw)
    local dirs = source_dirs(s, state.root)
    local idx, errs = Index.build({
      dirs = dirs,
      prefix = s.prefix,
      key_separator = config.key_separator,
      mount = s.mount,
      lang = s.lang,
      parse = s.parse,
    })
    state.indexes[#state.indexes + 1] = {
      source = s,
      index = idx,
      ropts = {
        namespace_resolver = resolver.make_namespace(s.namespace, s.prefix, config.key_separator),
        namespace_separator = config.namespace_separator,
        key_separator = config.key_separator,
        t_functions = to_set(s.t),
        hook_names = to_set(s.hooks),
      },
    }
    vim.list_extend(state.errors, errs)
  end
  return state.indexes
end

local function ensure_indexes()
  if not state.indexes then M.reload() end
  return state.indexes
end

--------------------------------------------------------------------------------
-- 查询 API（多源）
--------------------------------------------------------------------------------

--- 全键 → 逐语言条目（首个命中的源）
function M.lookup(full_key)
  for _, e in ipairs(ensure_indexes()) do
    local per = e.index:get(full_key)
    if per then return per end
  end
end

--- 全键 → 应写入的物理文件（命名空间存在的源优先）
function M.files_for(full_key)
  for _, e in ipairs(ensure_indexes()) do
    if e.index:owns(full_key) then return e.index:resolve_files_for_key(full_key) end
  end
  return nil, 'no-index'
end

function M.has_keys()
  for _, e in ipairs(ensure_indexes()) do
    if e.index:any_keys() then return true end
  end
  return false
end

--- 归类：hit（命中）/ missing（命名空间存在但键缺）/ out（越界，不标注）
---@return 'hit'|'missing'|'out' kind
---@return table? per
function M.classify(full_key)
  for _, e in ipairs(ensure_indexes()) do
    local per = e.index:get(full_key)
    if per then return 'hit', per end
  end
  for _, e in ipairs(ensure_indexes()) do
    if e.index:owns(full_key) then return 'missing' end
  end
  return 'out'
end

function M.tree()
  local out = {}
  for _, e in ipairs(ensure_indexes()) do vim.list_extend(out, e.index:tree()) end
  return out
end

function M.missing_report()
  local out = {}
  for _, e in ipairs(ensure_indexes()) do vim.list_extend(out, e.index:missing_report()) end
  return out
end

-- 语言优先级：display.lang 固定 → preferred_langs 命中 → 字典序首个
local function choose_lang(has, sorted)
  if config.display.lang and has(config.display.lang) then return config.display.lang end
  for _, l in ipairs(config.display.preferred_langs or {}) do
    if has(l) then return l end
  end
  return sorted[1]
end

-- 从一组语言里按优先级选一个（不改入参）
local function choose_from(langs)
  local sorted = vim.deepcopy(langs)
  table.sort(sorted)
  local set = to_set(sorted)
  return choose_lang(function(l) return set[l] end, sorted)
end

function M.pick_lang(per) return choose_from(vim.tbl_keys(per)) end

function M.preferred_lang(langs) return choose_from(langs) end

--------------------------------------------------------------------------------
-- 解析（多源择优）
--------------------------------------------------------------------------------

--- 光标处解析全键：各源各试，命中索引者优先 > 有 hook 绑定者 > 首个
function M.resolve_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  local lang = buf_lang(bufnr)
  local first, with_hook
  for _, e in ipairs(ensure_indexes()) do
    local opts = vim.tbl_extend('force', e.ropts, { lang = lang })
    local res = resolver.resolve_in_content(content, pos[1] - 1, pos[2], opts)
    if res.ok then
      if e.index:get(res.full_key) then return res end
      first = first or res
      if res.hook and not with_hook then with_hook = res end
    end
  end
  return with_hook or first or { ok = false, reason = 'not-in-t-call' }
end

--- 枚举 buffer 内所有 t() → { row, full_key, kind('hit'|'missing'), per? }（多源去重，命中优先）
function M.collect_buffer(bufnr)
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  local lang = buf_lang(bufnr)
  local root = ast.parse_root(content, lang)   -- 解析一次，多源共用
  local hits, misses = {}, {}
  for _, e in ipairs(ensure_indexes()) do
    -- 空索引（非当前项目的 source）直接跳过，不白跑 resolver 遍历 —— 让全局堆一堆 source 也零成本
    if e.index:any_keys() then
      local opts = vim.tbl_extend('force', e.ropts, { lang = lang, root = root })
      for _, r in ipairs(resolver.collect_in_content(content, opts)) do
        local id = r.range.srow .. ':' .. r.range.scol
        local per = e.index:get(r.full_key)
        if per then
          hits[id] = { row = r.range.srow, range = r.range, literal = r.literal,
            full_key = r.full_key, kind = 'hit', per = per }
        elseif not misses[id] and e.index:owns(r.full_key) then
          misses[id] = { row = r.range.srow, range = r.range, literal = r.literal,
            full_key = r.full_key, kind = 'missing' }
        end
      end
    end
  end
  local out = {}
  for _, h in pairs(hits) do out[#out + 1] = h end
  for id, m in pairs(misses) do if not hits[id] then out[#out + 1] = m end end
  return out
end

--------------------------------------------------------------------------------
-- 命令
--------------------------------------------------------------------------------

local function notify(msg, level)
  vim.notify('[vv-i18n] ' .. msg, level or vim.log.levels.INFO)
end

local function cmd_info()
  local res = M.resolve_cursor()
  if not res.ok then return notify('光标处无 i18n 键：' .. (res.reason or '?'), vim.log.levels.WARN) end
  local per = M.lookup(res.full_key)
  local lines = { '键: ' .. res.full_key }
  if res.reason == 'no-binding' then lines[#lines + 1] = '(未找到翻译 hook 绑定，按字面量解析)' end
  if not per then
    lines[#lines + 1] = '⚠ 索引中未找到该键'
  else
    local langs = {}
    for l in pairs(per) do langs[#langs + 1] = l end
    table.sort(langs)
    for _, l in ipairs(langs) do
      local e = per[l]
      lines[#lines + 1] = ('  %-6s %s'):format(l, e.kind == 'string' and e.value or ('<' .. e.kind .. '>'))
    end
  end
  notify(table.concat(lines, '\n'))
end

local function cmd_jump()
  local res = M.resolve_cursor()
  if not res.ok then return notify('光标处无 i18n 键：' .. (res.reason or '?'), vim.log.levels.WARN) end
  local per = M.lookup(res.full_key)
  if not per then return notify('索引中未找到 ' .. res.full_key, vim.log.levels.WARN) end
  local e = per[M.pick_lang(per)]
  vim.cmd('edit ' .. vim.fn.fnameescape(e.file))
  pcall(vim.api.nvim_win_set_cursor, 0, { (e.row or 0) + 1, e.col or 0 })
  vim.cmd('normal! zz')
end

local function cmd_set_value()
  local res = M.resolve_cursor()
  if not res.ok then return notify('光标处无 i18n 键', vim.log.levels.WARN) end
  local per = M.lookup(res.full_key)
  if not per then return notify('索引中未找到 ' .. res.full_key, vim.log.levels.WARN) end
  local lang = M.pick_lang(per)
  local cur = per[lang]
  vim.ui.input({ prompt = ('改 %s [%s]: '):format(res.full_key, lang), default = cur.value or '' }, function(input)
    if input == nil then return end
    local r = writer.update_file(cur.file, cur.in_file_path, input,
      { quote_style = config.quote_style, indent = config.indent })
    if r.ok then notify(('已写入 %s [%s]'):format(res.full_key, lang)); M.reload()
    else notify('写入失败：' .. (r.reason or '?'), vim.log.levels.ERROR) end
  end)
end

local function cmd_add_key()
  local res = M.resolve_cursor()
  local function do_add(full_key)
    local files, err = M.files_for(full_key)
    if not files then return notify('无法定位文件：' .. tostring(err), vim.log.levels.WARN) end
    local missing = {}
    for _, f in ipairs(files) do if not f.exists then missing[#missing + 1] = f end end
    if #missing == 0 then return notify('该键各语言均已存在') end
    vim.ui.input({ prompt = ('补 %s（%d 个语言缺失）值: '):format(full_key, #missing) }, function(input)
      if input == nil or input == '' then return end
      local done, fails = 0, {}
      for _, f in ipairs(missing) do
        local r = writer.add_file(f.file, f.in_file_path, input, { quote_style = config.quote_style, indent = config.indent })
        if r.ok then done = done + 1 else fails[#fails + 1] = f.lang .. ':' .. (r.reason or '?') end
      end
      notify(('已补 %d 个语言%s'):format(done, #fails > 0 and ('，失败: ' .. table.concat(fails, ', ')) or ''))
      M.reload()
    end)
  end
  if res.ok then
    do_add(res.full_key)
  else
    vim.ui.input({ prompt = '要新增的全键: ' }, function(input)
      if input and input ~= '' then do_add(input) end
    end)
  end
end

function M.open_panel()
  require('vv-i18n.panel').toggle(M)
end

function M.edit_cursor()
  local res = M.resolve_cursor()
  if not res.ok then return notify('光标处无 i18n 键：' .. (res.reason or '?'), vim.log.levels.WARN) end
  require('vv-i18n.editor').open(M, res.full_key, { on_saved = function() M.reload() end })
end

--- 写回选项（editor 用）
function M.writer_opts()
  return { quote_style = config.quote_style, indent = config.indent }
end

--------------------------------------------------------------------------------
-- 行内预览
--------------------------------------------------------------------------------

function M.enable()  require('vv-i18n.display').enable(M, config) end
function M.disable() require('vv-i18n.display').disable() end
function M.toggle()  require('vv-i18n.display').toggle(M, config) end

--------------------------------------------------------------------------------
-- setup
--------------------------------------------------------------------------------

function M.setup(opts)
  base_config = make_config(opts or {})   -- setup 基线（项目无 .vv-i18n.lua 时用）
  set_config(base_config)

  apply_display_hl()
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('VVI18nHl', { clear = true }),
    callback = apply_display_hl,
  })
  -- 切目录（常见的切项目方式）→ 重建，吃新项目的 .vv-i18n.lua
  vim.api.nvim_create_autocmd('DirChanged', {
    group = vim.api.nvim_create_augroup('VVI18nProject', { clear = true }),
    callback = function() pcall(M.reload) end,
  })

  local cmd = vim.api.nvim_create_user_command
  cmd('VVI18nKeys',     function() M.open_panel() end, { desc = 'vv-i18n: 键浏览/同步编辑面板' })
  cmd('VVI18nEdit',     function() M.edit_cursor() end, { desc = 'vv-i18n: 多语言同步编辑' })
  cmd('VVI18nInfo',     cmd_info, { desc = 'vv-i18n: 光标处键各语言译文' })
  cmd('VVI18nJump',     cmd_jump, { desc = 'vv-i18n: 跳到 locale 定义' })
  cmd('VVI18nSetValue', cmd_set_value, { desc = 'vv-i18n: 改某语言值' })
  cmd('VVI18nAddKey',   cmd_add_key, { desc = 'vv-i18n: 补缺失语言' })
  cmd('VVI18nReload', function()
    M.reload()
    local nkeys = 0
    for _, e in ipairs(state.indexes or {}) do nkeys = nkeys + e.index:stats().keys end
    notify(('索引已重建：%d 源 / %d 键%s'):format(#(state.indexes or {}), nkeys,
      #state.errors > 0 and ('，%d 文件解析失败'):format(#state.errors) or ''))
  end, { desc = 'vv-i18n: 重建索引' })
  cmd('VVI18n',        function() M.toggle() end, { desc = 'vv-i18n: 行内预览开关' })
  cmd('VVI18nEnable',  function() M.enable() end, { desc = 'vv-i18n: 开启行内预览' })
  cmd('VVI18nDisable', function() M.disable() end, { desc = 'vv-i18n: 关闭行内预览' })
  cmd('VVI18nToggle',  function() M.toggle() end, { desc = 'vv-i18n: 切换行内预览' })

  if config.display.enable then
    vim.schedule(function() pcall(M.enable) end)
  end
end

function M.get_config() return config end
function M.get_state() return state end

return M

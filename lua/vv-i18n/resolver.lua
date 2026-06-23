-- vv-i18n.resolver — 调用点 → 运行时全键
--
-- 单 AST 路径：
--   1. 光标处定位 `t('key')` 调用的字符串字面量参数
--   2. 沿真实作用域向上找该 `t` 的来源 hook 绑定（默认 `useTranslation(...)`，可配）
--   3. 经可配置 namespace_resolver 把 hook 上下文 → key 前缀，再拼出全键
--
-- 默认中性（react-i18next 语义）：`useTranslation('ns')` → 前缀 `ns`、无参 → 无前缀
-- 绝对命名空间 `ns:key`（分隔符可配）直接展开。各分隔符 / 前缀规则均可在 config 覆盖；
-- 前缀规则由 `M.make_namespace` 的预设（flat / hook-arg / fixed / two-level）或自定义函数决定
local ast = require('vv-i18n.ast')

local M = {}

--- 由「字面量预设 | 函数」+ source 前缀 构建 namespace_resolver
--- ctx = { hook_name, hook_arg, callee, has_binding }，返回 key 前缀串（nil = 无前缀）：
---   'flat'      → nil（字面量即全键）
---   'hook-arg'  → [prefix.]<hook 参数>（react-i18next 风格）
---   'fixed'     → prefix（固定根，忽略 hook 参数）
---   'two-level' → prefix[.<hook 参数>]
---@param spec string|fun(ctx): string?
---@param prefix? string
---@param key_sep? string
---@return fun(ctx): string?
function M.make_namespace(spec, prefix, key_sep)
  prefix = prefix or ''
  key_sep = key_sep or '.'
  if type(spec) == 'function' then return spec end
  local function root() return prefix ~= '' and prefix or nil end
  local function join2(a, b) return a and (a .. key_sep .. b) or b end

  if spec == 'flat' then
    return function() return nil end
  elseif spec == 'fixed' then
    return function() return root() end
  elseif spec == 'two-level' then
    return function(ctx)
      if ctx.hook_arg and ctx.hook_arg ~= '' then return join2(root(), ctx.hook_arg) end
      return root()
    end
  else -- 'hook-arg'（默认/中性）
    return function(ctx)
      local a = ctx.hook_arg
      if a and a ~= '' then return join2(root(), a) end
      return root()
    end
  end
end

local DEFAULTS = {
  lang = 'typescript',
  t_functions = { t = true },              -- 视为翻译函数的标识符
  hook_names = { useTranslation = true },  -- 产出 t 的 hook（react-i18next 事实标准）
  namespace_resolver = M.make_namespace('hook-arg', '', '.'),
  namespace_separator = ':',               -- 绝对命名空间分隔符（ns<sep>key）
  key_separator = '.',                     -- 前缀与字面量的连接符
}

--- 取 call_expression 的 callee 名（identifier 或 member_expression 的 property）
local function callee_name(call, content)
  local fn = call:field('function')[1]
  if not fn then return nil end
  local t = fn:type()
  if t == 'identifier' then
    return ast.node_text(fn, content)
  elseif t == 'member_expression' then
    local prop = fn:field('property')[1]
    if prop then return ast.node_text(prop, content) end
  end
  return nil
end

--- call 的第一个字符串参数节点（key 字面量）
local function first_string_arg(call)
  local args = call:field('arguments')[1]
  if not args then return nil end
  for c in args:iter_children() do
    local t = c:type()
    if t == 'string' or t == 'template_string' then
      return c
    end
  end
  return nil
end

--- 从光标所在节点向上找最近的「t(string, ...)」调用
---@return TSNode? call
---@return TSNode? str
local function find_t_call(node, content, t_functions)
  local cur = node
  while cur do
    if cur:type() == 'call_expression' then
      local name = callee_name(cur, content)
      if name and t_functions[name] then
        local str = first_string_arg(cur)
        if str then return cur, str end
      end
    end
    cur = cur:parent()
  end
  return nil, nil
end

--- 字符串/无插值模板字面量 → 内部文本（key 不解码转义，原样剥引号即可）
local function literal_text(str, content)
  if str:type() == 'template_string' then
    for c in str:iter_children() do
      if c:type() == 'template_substitution' then
        return nil -- 含 ${}，不是静态 key
      end
    end
  end
  return ast.strip_quotes(ast.node_text(str, content))
end

--- 在某声明节点里匹配 `const <name> = hook(...)` / `const { name } = hook(...)`
---@return string? hook_name
---@return string? hook_arg
local function match_hook_decl(decl, name, content, hook_names)
  if decl:type() ~= 'lexical_declaration' and decl:type() ~= 'variable_declaration' then
    return nil
  end
  for d in decl:iter_children() do
    if d:type() == 'variable_declarator' then
      local lhs = d:field('name')[1]
      local rhs = d:field('value')[1]
      if not lhs or not rhs or rhs:type() ~= 'call_expression' then goto continue end

      -- rhs 必须是 hook 调用
      local hook = callee_name(rhs, content)
      if not hook or not hook_names[hook] then goto continue end

      -- lhs 命中：标识符直接同名，或解构里有该 shorthand
      local matched = false
      if lhs:type() == 'identifier' then
        matched = ast.node_text(lhs, content) == name
      elseif lhs:type() == 'object_pattern' then
        for p in lhs:iter_children() do
          local pt = p:type()
          if pt == 'shorthand_property_identifier_pattern' then
            if ast.node_text(p, content) == name then matched = true; break end
          elseif pt == 'pair_pattern' then
            local v = p:field('value')[1]
            if v and ast.node_text(v, content) == name then matched = true; break end
          end
        end
      end
      if not matched then goto continue end

      -- 取 hook 的首个字符串参数
      local arg
      local hargs = rhs:field('arguments')[1]
      if hargs then
        for c in hargs:iter_children() do
          if c:type() == 'string' or c:type() == 'template_string' then
            arg = literal_text(c, content)
            break
          end
        end
      end
      return hook, arg
    end
    ::continue::
  end
  return nil
end

--- 沿真实作用域向上找 t 的绑定（最近作用域优先）
---@return string? hook_name
---@return string? hook_arg
local function find_binding(node, name, content, hook_names)
  local scope = node
  while scope do
    for child in scope:iter_children() do
      local hook, arg = match_hook_decl(child, name, content, hook_names)
      if hook then return hook, arg end
    end
    scope = scope:parent()
  end
  return nil
end

--- 拼 prefix 与字面量（prefix 为 nil/'' 时字面量即全键）
local function join_key(prefix, literal, key_sep)
  if prefix and prefix ~= '' then return prefix .. key_sep .. literal end
  return literal
end

--- 解析一个已定位的 t(string,...) 调用 → 全键
---@param call TSNode
---@param str TSNode
---@param content string
---@param cfg table
---@return table result
local function resolve_call(call, str, content, cfg)
  local literal = literal_text(str, content)
  if not literal then return { ok = false, reason = 'dynamic-key' } end

  local srow, scol = str:start()
  local erow, ecol = str:end_()
  local range = { srow = srow, scol = scol, erow = erow, ecol = ecol }

  -- 绝对命名空间 ns<sep>key（分隔符可配）→ 展开为 ns<key_sep>key，不再叠前缀
  if cfg.namespace_separator and cfg.namespace_separator ~= '' then
    local at = literal:find(cfg.namespace_separator, 1, true)
    if at then
      local ns = literal:sub(1, at - 1)
      local rest = literal:sub(at + #cfg.namespace_separator)
      if ns ~= '' and rest ~= '' then
        return { ok = true, full_key = join_key(ns, rest, cfg.key_separator),
          literal = literal, prefix = ns, absolute = true, range = range }
      end
    end
  end

  local callee = callee_name(call, content)
  local hook, hook_arg = find_binding(call, callee, content, cfg.hook_names)

  local prefix = cfg.namespace_resolver({
    hook_name = hook, hook_arg = hook_arg, callee = callee, has_binding = hook ~= nil,
  })

  return {
    ok = true,
    full_key = join_key(prefix, literal, cfg.key_separator),
    literal = literal,
    prefix = prefix,
    hook = hook,
    hook_arg = hook_arg,
    range = range,
    reason = hook and nil or 'no-binding',  -- 信息性：未找到 hook 绑定（仍按 resolver 结果给全键）
  }
end

local function cfg_of(opts)
  opts = opts or {}
  return {
    lang = opts.lang or DEFAULTS.lang,
    t_functions = opts.t_functions or DEFAULTS.t_functions,
    hook_names = opts.hook_names or DEFAULTS.hook_names,
    namespace_resolver = opts.namespace_resolver or DEFAULTS.namespace_resolver,
    namespace_separator = opts.namespace_separator ~= nil and opts.namespace_separator or DEFAULTS.namespace_separator,
    key_separator = opts.key_separator or DEFAULTS.key_separator,
  }
end

--- 在 content 的 (row,col)（0-based）处解析全键
---@param content string
---@param row integer 0-based
---@param col integer 0-based
---@param opts? table  { lang, t_functions, hook_names, namespace_resolver, namespace_separator, key_separator }
---@return { ok: boolean, full_key?: string, literal?: string, prefix?: string, absolute?: boolean, hook?: string, hook_arg?: string, range?: table, reason?: string }
function M.resolve_in_content(content, row, col, opts)
  local cfg = cfg_of(opts)
  local root, err = ast.parse_root(content, cfg.lang)
  if not root then return { ok = false, reason = err } end

  local node = root:named_descendant_for_range(row, col, row, col)
  if not node then return { ok = false, reason = 'no-node-at-cursor' } end

  local call, str = find_t_call(node, content, cfg.t_functions)
  if not call then return { ok = false, reason = 'not-in-t-call' } end

  return resolve_call(call, str, content, cfg)
end

--- 枚举 content 内所有静态 t(string,...) 调用 → 解析结果列表（供整 buffer 预览 / 报告）
---@param content string
---@param opts? table
---@return table[] results  仅含 ok 且 full_key 的项
function M.collect_in_content(content, opts)
  local cfg = cfg_of(opts)
  -- opts.root：调用方已解析好的根（多源共用，省去逐源重 parse）
  local root = (opts and opts.root) or ast.parse_root(content, cfg.lang)
  if not root then return {} end

  local out = {}
  local function walk(node)
    if node:type() == 'call_expression' then
      local name = callee_name(node, content)
      if name and cfg.t_functions[name] then
        local str = first_string_arg(node)
        if str then
          local res = resolve_call(node, str, content, cfg)
          if res.ok and res.full_key then out[#out + 1] = res end
        end
      end
    end
    for c in node:iter_children() do walk(c) end
  end
  walk(root)
  return out
end

--- buffer 包装：在指定（或当前）窗口光标处解析
---@param bufnr? integer
---@param opts? table
function M.resolve_at_cursor(bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = opts or {}
  local win = vim.api.nvim_get_current_win()
  local pos = vim.api.nvim_win_get_cursor(win) -- {row 1-based, col 0-based}
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  if not opts.lang then
    local ft = vim.bo[bufnr].filetype
    opts.lang = (ft == 'typescriptreact' or ft == 'javascriptreact') and 'tsx'
      or (ft == 'javascript' and 'javascript')
      or 'typescript'
  end
  return M.resolve_in_content(content, pos[1] - 1, pos[2], opts)
end

return M

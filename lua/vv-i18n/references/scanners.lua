-- 引用扫描器注册表和按语言划分的采集适配器
--
-- 内置适配器负责 JS/TS Tree-sitter 安全检查。外部适配器声明文件扩展名、
-- 候选调用名称和证据采集器

local Ast = require('vv-i18n.ast')

local M = {}

local JS_EXTENSIONS = { 'ts', 'tsx', 'js', 'jsx' }

local function escape_lua_pattern(value)
  return (value:gsub('([^%w])', '%%%1'))
end

local function contains_reference_call(text, names)
  for _, name in ipairs(names or {}) do
    local pattern = '%f[_%w]' .. escape_lua_pattern(name) .. '%f[^_%w]%s*%('
    if text:find(pattern) then return true end
  end
  return false
end

local function inspect_parse_issues(node, content, names, issues)
  issues = issues or { unsafe = false, warnings = {} }
  if node:type() == 'ERROR' then
    local text = Ast.node_text(node, content)
    local row, col = node:start()
    if contains_reference_call(text, names) then
      issues.unsafe = true
    else
      issues.warnings[#issues.warnings + 1] = {
        reason = 'parser-error-outside-reference-call',
        row = row + 1,
        col = col,
        detail = vim.trim(text):sub(1, 200),
      }
    end
    return issues
  end
  if node:missing() then
    issues.unsafe = true
    return issues
  end
  for child in node:iter_children() do inspect_parse_issues(child, content, names, issues) end
  return issues
end

local function normalize_extensions(extensions, scanner_id)
  local out, seen = {}, {}
  for _, extension in ipairs(type(extensions) == 'table' and extensions or {}) do
    extension = type(extension) == 'string' and extension:gsub('^%.', '') or ''
    if extension == '' or not extension:match('^[%w_.+-]+$') then
      error(('%s has an invalid extension: %s'):format(scanner_id, tostring(extension)))
    end
    if not seen[extension] then seen[extension] = true; out[#out + 1] = extension end
  end
  if #out == 0 then error(scanner_id .. ' must declare at least one extension') end
  table.sort(out)
  return out
end

local function normalize_names(names, scanner_id)
  local out, seen = {}, {}
  for _, name in ipairs(type(names) == 'table' and names or {}) do
    if type(name) ~= 'string' or name == '' then
      error(('%s has an invalid reference name'):format(scanner_id))
    end
    if not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  if #out == 0 then error(scanner_id .. ' must declare at least one reference name') end
  table.sort(out)
  return out
end

local function custom_scanner(spec, index)
  local id = type(spec.id) == 'string' and spec.id or ('custom-' .. index)
  if type(spec.collect) ~= 'function' then error(id .. ' must provide collect(ctx)') end
  return {
    id = id,
    extensions = normalize_extensions(spec.extensions, id),
    names = normalize_names(spec.names, id),
    collect = spec.collect,
  }
end

local function builtin_scanner(plugin)
  local names = normalize_names(plugin.reference_names(), 'javascript')

  return {
    id = 'javascript',
    extensions = vim.deepcopy(JS_EXTENSIONS),
    names = names,
    collect = function(ctx)
      local warnings = {}
      local root, parse_error = Ast.parse_root(ctx.content, Ast.lang_for_path(ctx.path))

      if not root then return nil, warnings, parse_error or 'parse-failed' end
      if root:has_error() then
        local issues = inspect_parse_issues(root, ctx.content, names)
        if issues.unsafe then return nil, warnings, 'source-has-error' end
        warnings = issues.warnings
      end

      return plugin.collect_content(ctx.content, ctx.path), warnings, nil
    end,
  }
end

---@param plugin table
---@return string[] extensions
function M.extensions(plugin)
  local config = type(plugin.get_config) == 'function' and plugin.get_config() or {}
  local references = type(config.references) == 'table' and config.references or {}
  local out, seen = vim.deepcopy(JS_EXTENSIONS), {}
  for _, extension in ipairs(out) do seen[extension] = true end
  for index, spec in ipairs(type(references.scanners) == 'table' and references.scanners or {}) do
    local id = type(spec.id) == 'string' and spec.id or ('custom-' .. index)
    for _, extension in ipairs(normalize_extensions(spec.extensions, id)) do
      if not seen[extension] then seen[extension] = true; out[#out + 1] = extension end
    end
  end
  table.sort(out)
  return out
end

---@param plugin table
---@return table registry
function M.build(plugin)
  local config = type(plugin.get_config) == 'function' and plugin.get_config() or {}
  local references = type(config.references) == 'table' and config.references or {}
  local scanners = { builtin_scanner(plugin) }
  for index, spec in ipairs(type(references.scanners) == 'table' and references.scanners or {}) do
    scanners[#scanners + 1] = custom_scanner(spec, index)
  end

  local by_extension = {}
  for _, scanner in ipairs(scanners) do
    -- 后注册的外部扫描器会有意替换某个扩展名对应的内置适配器
    for _, extension in ipairs(scanner.extensions) do by_extension[extension] = scanner end
  end

  local extensions, names, seen_names = {}, {}, {}
  for extension in pairs(by_extension) do extensions[#extensions + 1] = extension end
  table.sort(extensions)
  for _, scanner in pairs(by_extension) do
    for _, name in ipairs(scanner.names) do
      if not seen_names[name] then seen_names[name] = true; names[#names + 1] = name end
    end
  end
  table.sort(names)
  local route_extensions = vim.deepcopy(extensions)
  table.sort(route_extensions, function(a, b)
    if #a == #b then return a < b end
    return #a > #b
  end)

  return {
    extensions = extensions,
    names = names,
    ignore_key = type(config.ignore_key) == 'function' and config.ignore_key or nil,
    for_path = function(path)
      for _, extension in ipairs(route_extensions) do
        if vim.endswith(path, '.' .. extension) then return by_extension[extension], extension end
      end
    end,
  }
end

local function valid_result(result)
  if type(result) ~= 'table' or type(result.kind) ~= 'string' then return false end
  local range = result.range
  if type(range) ~= 'table' or type(range.srow) ~= 'number' or type(range.scol) ~= 'number'
      or range.srow < 0 or range.scol < 0
  then return false end
  if result.kind == 'hit' then return type(result.full_key) == 'string' and result.full_key ~= '' end
  if result.kind == 'dynamic' then return type(result.pattern) == 'string' and result.pattern ~= '' end
  if result.kind == 'ambiguous' then
    if type(result.full_keys) ~= 'table' or #result.full_keys == 0 then return false end
    for _, full_key in ipairs(result.full_keys) do
      if type(full_key) ~= 'string' or full_key == '' then return false end
    end
    return true
  end
  if result.kind == 'missing' then return true end
  return false
end

---@param scanner table
---@param ctx table
---@return table? results
---@return table warnings
---@return string? error
function M.collect(scanner, ctx)
  local ok, results, warnings, collect_error = pcall(scanner.collect, ctx)
  warnings = type(warnings) == 'table' and warnings or {}

  if not ok then return nil, warnings, tostring(results) end
  if collect_error then return nil, warnings, tostring(collect_error) end
  if type(results) ~= 'table' then return nil, warnings, 'collect-returned-non-table' end

  for index, result in ipairs(results) do
    if not valid_result(result) then return nil, warnings, 'invalid-result-at-index-' .. index end
  end

  return results, warnings, nil
end

return M

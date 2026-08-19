-- 项目引用索引：协调 rg 扫描、tree-sitter 解析和按请求发布快照

local fs = require('vv-utils.fs')
local async = require('vv-utils.async')
local Store = require('vv-i18n.references.store')
local Scanners = require('vv-i18n.references.scanners')

local scan_scope = async.scope({ cancel_previous = true })
local store = Store.new()
local M = {}

local function new_scan(status, generation, root, extensions)
  return {
    status = status,
    generation = generation,
    root = root,
    files = 0,
    parsed = 0,
    failures = {},
    warnings = {},
    source_fingerprints = {},
    extensions = vim.deepcopy(extensions or {}),
  }
end

local state = {
  scanning = false,
  generation = 0,
  listeners = {},
  scan = new_scan('idle', 0),
}

local function emit()
  for _, callback in ipairs(state.listeners) do pcall(callback) end
end

local function relative(path, root)
  local prefix = root .. '/'
  return vim.startswith(path, prefix) and path:sub(#prefix + 1) or path
end

local function escape_regex(value)
  return (value:gsub('([\\.^$|?*+(){}%[%]])', '\\%1'))
end

local function is_current(request)
  return not request or request:is_current()
end

local function add_failure(request, failure)
  if not is_current(request) then return false end
  state.scan.failures[#state.scan.failures + 1] = failure
  return true
end

local function sort_failures()
  table.sort(state.scan.failures, function(a, b)
    local af = a.file or ''
    local bf = b.file or ''
    if af == bf then
      local ar = a.reason or ''
      local br = b.reason or ''
      if ar == br then return (a.detail or '') < (b.detail or '') end
      return ar < br
    end
    return af < bf
  end)
end

local function sort_warnings()
  table.sort(state.scan.warnings, function(a, b)
    if a.file == b.file then
      if a.row == b.row then return (a.col or 0) < (b.col or 0) end
      return (a.row or 0) < (b.row or 0)
    end
    return (a.file or '') < (b.file or '')
  end)
end

local function finish(request, callback)
  if not request:is_current() then return false end
  local remained_current = request:finish()
  if remained_current and callback then callback() end
  return remained_current
end

local function fail_scan(request, callback, failure)
  if not request:is_current() then return false end
  state.scanning = false
  state.scan.status = 'failed'
  add_failure(request, failure)
  sort_failures()
  emit()
  return finish(request, callback)
end

local function build_registry(plugin, request)
  local ok, registry = pcall(Scanners.build, plugin)
  if not request:is_current() then return nil, nil end
  if not ok then return nil, tostring(registry) end
  return registry, nil
end

local function complete_scan(request, callback)
  if not request:is_current() then return false end
  store.sort()
  sort_failures()
  sort_warnings()
  state.scanning = false
  state.scan.status = #state.scan.failures == 0 and 'complete' or 'failed'
  emit()
  return finish(request, callback)
end

local function index_file(path, root, request, registry)
  local ok, content = pcall(fs.read_all, path)

  if not is_current(request) then return false end
  state.scan.source_fingerprints[path] = nil
  if not ok or type(content) ~= 'string' then
    store.remove_file(path)
    add_failure(request, { file = path, reason = 'read-failed' })
    return true
  end

  local scanner, extension = registry.for_path(path)
  if not scanner then
    store.remove_file(path)
    add_failure(request, { file = path, reason = 'reference-scanner-unavailable' })
    return true
  end

  local lines = vim.split(content, '\n', { plain = true })
  local results, warnings, collect_error = Scanners.collect(scanner, {
    content = content,
    path = path,
    root = root,
    extension = extension,
    scanner = scanner.id,
  })
  if not is_current(request) then return false end
  if not results then
    store.remove_file(path)
    add_failure(request, { file = path, reason = collect_error or 'collect-content-failed', scanner = scanner.id })
    return true
  end
  for _, warning in ipairs(warnings) do
    warning.file = path
    warning.scanner = scanner.id
    state.scan.warnings[#state.scan.warnings + 1] = warning
  end
  state.scan.source_fingerprints[path] = vim.fn.sha256(content)
  state.scan.parsed = state.scan.parsed + 1

  local refs, dynamic_refs = {}, {}
  for _, result in ipairs(results) do
    if not is_current(request) then return false end

    if result.kind == 'hit' then
      local ref = {
        full_key = result.full_key,
        literal = result.literal,
        file = path,
        relative = relative(path, root),
        row = result.range.srow + 1,
        col = result.range.scol,
        line = vim.trim(lines[result.range.srow + 1] or ''),
      }
      refs[#refs + 1] = ref
    elseif result.kind == 'dynamic' then
      dynamic_refs[#dynamic_refs + 1] = {
        pattern = result.pattern,
        prefix = result.prefix,
        literal = result.literal,
        file = path,
        relative = relative(path, root),
        row = result.range.srow + 1,
        col = result.range.scol,
        line = vim.trim(lines[result.range.srow + 1] or ''),
      }
    elseif result.kind == 'ambiguous' then
      for _, full_key in ipairs(result.full_keys or {}) do
        dynamic_refs[#dynamic_refs + 1] = {
          pattern = full_key,
          prefix = full_key,
          literal = result.literal,
          reason = result.reason,
          file = path,
          relative = relative(path, root),
          row = result.range.srow + 1,
          col = result.range.scol,
          line = vim.trim(lines[result.range.srow + 1] or ''),
        }
      end
    end
  end

  if not is_current(request) then return false end
  store.replace_file(path, refs, dynamic_refs)
  return true
end

---@param plugin table
---@param callback? fun()
function M.refresh(plugin, callback)
  local request = scan_scope:begin()
  state.generation = state.generation + 1
  local generation = state.generation
  local root = plugin.get_state().root

  if not request:is_current() then return end

  -- 每次新扫描都使用新的仓库，绝不混入旧快照
  store.clear()
  if not root then
    state.scanning = false
    state.scan = new_scan('failed', generation)
    add_failure(request, { reason = 'project-root-unavailable' })
    emit()
    finish(request, callback)
    return
  end

  state.scanning = true
  state.scan = new_scan('scanning', generation, root)
  emit()
  if not request:is_current() then return end

  local registry, registry_error = build_registry(plugin, request)
  if not request:is_current() then return end
  if not registry then
    fail_scan(request, callback, { reason = 'reference-scanner-invalid', detail = registry_error })
    return
  end
  state.scan.extensions = vim.deepcopy(registry.extensions)

  local escaped = {}
  for _, name in ipairs(registry.names) do escaped[#escaped + 1] = escape_regex(name) end
  local pattern = [[(^|[^[:alnum:]_$])(]] .. table.concat(escaped, '|') .. [[)\s*\(]]
  local command = {
    'rg',
    '--files-with-matches',
    '--hidden',
    '--glob', '!**/node_modules/**',
    '--glob', '!**/.git/**',
    pattern,
    '.',
  }
  for _, extension in ipairs(registry.extensions) do
    table.insert(command, #command, '--glob')
    table.insert(command, #command, '*.' .. extension)
  end

  if vim.fn.executable('rg') ~= 1 then
    fail_scan(request, callback, { reason = 'rg-unavailable' })
    return
  end

  local process = assert(vim.system(command, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if not request:is_current() then return end

      if result.code ~= 0 and result.code ~= 1 then
        fail_scan(request, callback, {
          reason = 'rg-failed:' .. tostring(result.code),
          detail = vim.trim(result.stderr or ''),
        })
        return
      end

      local files = result.code == 0 and vim.split(result.stdout or '', '\n', { trimempty = true }) or {}
      state.scan.files = #files
      local index = 1

      local function batch()
        if not request:is_current() then return end

        local last = math.min(index + 19, #files)
        for current = index, last do
          if not index_file(
            root .. '/' .. files[current]:gsub('^%./', ''),
            root,
            request,
            registry
          ) then return end
        end
        index = last + 1

        if index <= #files then
          vim.schedule(batch)
          return
        end

        complete_scan(request, callback)
      end

      batch()
    end)
  end))

  request:set_cancel(function()
    pcall(process.kill, process, 'sigterm')
  end)
end

---@param plugin table
---@param path string
function M.update_file(plugin, path)
  local root = plugin.get_state().root
  if not root then
    M.refresh(plugin)
    return
  end
  if not vim.startswith(path, root .. '/') then return end

  -- 全量扫描进行中，或当前快照属于其他根目录时，局部更新不能发布完整快照
  if state.scanning or state.scan.status ~= 'complete' or state.scan.root ~= root then
    M.refresh(plugin)
    return
  end

  local request = scan_scope:begin()
  state.generation = state.generation + 1
  local generation = state.generation
  if not request:is_current() then return end

  state.scan.generation = generation
  state.scan.failures = {}
  for index = #state.scan.warnings, 1, -1 do
    if state.scan.warnings[index].file == path then table.remove(state.scan.warnings, index) end
  end
  local registry, registry_error = build_registry(plugin, request)
  if not request:is_current() then return end
  if not registry then
    fail_scan(request, nil, { reason = 'reference-scanner-invalid', detail = registry_error })
    return
  end
  state.scan.extensions = vim.deepcopy(registry.extensions)
  if not index_file(path, root, request, registry) then return end
  if not request:is_current() then return end

  complete_scan(request)
end

---@param full_key string
---@return table[]
function M.get(full_key)
  return store.get(full_key)
end

function M.snapshot()
  local data = store.snapshot()
  return vim.deepcopy({
    scanning = state.scanning,
    generation = state.generation,
    by_key = data.by_key,
    dynamic_evidence = data.dynamic_evidence,
    scan = state.scan,
  })
end

---@param callback fun()
---@return fun()
function M.subscribe(callback)
  state.listeners[#state.listeners + 1] = callback
  return function()
    for index = #state.listeners, 1, -1 do
      if state.listeners[index] == callback then table.remove(state.listeners, index) end
    end
  end
end

function M.is_scanning()
  return state.scanning
end

function M.clear()
  scan_scope:cancel()
  state.generation = state.generation + 1
  state.scanning = false
  store.clear()
  state.scan = new_scan('idle', state.generation)
  emit()
end

return M

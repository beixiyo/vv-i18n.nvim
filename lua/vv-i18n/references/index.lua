-- 项目引用索引：先用 rg 筛出候选文件，再交给 vv-i18n 的 tree-sitter resolver 精确解析

local fs = require('vv-utils.fs')

local M = {}

local state = {
  generation = 0,
  scanning = false,
  by_key = {},
  by_file = {},
  listeners = {},
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

local function remove_file(path)
  for _, ref in ipairs(state.by_file[path] or {}) do
    local items = state.by_key[ref.full_key] or {}
    for index = #items, 1, -1 do
      if items[index].file == path then table.remove(items, index) end
    end
    if #items == 0 then state.by_key[ref.full_key] = nil end
  end
  state.by_file[path] = nil
end

local function index_file(plugin, path, root)
  remove_file(path)

  local ok, content = pcall(fs.read_all, path)
  if not ok or type(content) ~= 'string' then return end

  local lines = vim.split(content, '\n', { plain = true })
  local refs = {}
  for _, result in ipairs(plugin.collect_content(content, path)) do
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
      state.by_key[ref.full_key] = state.by_key[ref.full_key] or {}
      state.by_key[ref.full_key][#state.by_key[ref.full_key] + 1] = ref
    end
  end
  state.by_file[path] = refs
end

---@param plugin table
---@param callback? fun()
function M.refresh(plugin, callback)
  local root = plugin.get_state().root
  if not root then return end

  state.generation = state.generation + 1
  local generation = state.generation
  state.scanning = true
  state.by_key = {}
  state.by_file = {}
  emit()

  local names = plugin.reference_names()
  if #names == 0 then
    state.scanning = false
    emit()
    if callback then callback() end
    return
  end

  local escaped = {}
  for _, name in ipairs(names) do
    escaped[#escaped + 1] = escape_regex(name)
  end
  local pattern = [[\b(]] .. table.concat(escaped, '|') .. [[)\s*\(]]
  local command = {
    'rg',
    '--files-with-matches',
    '--hidden',
    '--glob', '*.{ts,tsx,js,jsx}',
    '--glob', '!**/node_modules/**',
    '--glob', '!**/.git/**',
    pattern,
    '.',
  }

  if vim.fn.executable('rg') ~= 1 then
    state.scanning = false
    emit()
    if callback then callback() end
    return
  end

  vim.system(command, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if generation ~= state.generation then return end

      local files = result.code == 0 and vim.split(result.stdout or '', '\n', { trimempty = true }) or {}
      local index = 1

      local function batch()
        if generation ~= state.generation then return end

        local last = math.min(index + 19, #files)
        for current = index, last do
          index_file(plugin, root .. '/' .. files[current]:gsub('^%./', ''), root)
        end
        index = last + 1

        if index <= #files then
          vim.schedule(batch)
          return
        end

        for _, refs in pairs(state.by_key) do
          table.sort(refs, function(a, b)
            if a.relative == b.relative then
              if a.row == b.row then return a.col < b.col end
              return a.row < b.row
            end
            return a.relative < b.relative
          end)
        end

        state.scanning = false
        emit()
        if callback then callback() end
      end

      batch()
    end)
  end)
end

---@param plugin table
---@param path string
function M.update_file(plugin, path)
  local root = plugin.get_state().root
  if not root or not vim.startswith(path, root .. '/') then return end

  index_file(plugin, path, root)
  emit()
end

---@param full_key string
---@return table[]
function M.get(full_key)
  return state.by_key[full_key] or {}
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
  state.generation = state.generation + 1
  state.scanning = false
  state.by_key = {}
  state.by_file = {}
  emit()
end

return M

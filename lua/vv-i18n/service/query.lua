-- Read-only public queries over the private runtime index.
local ast = require('vv-i18n.ast')
local resolver = require('vv-i18n.resolver')
local Index = require('vv-i18n.service.index')

local M = {}

local function buf_lang(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == 'typescriptreact' or ft == 'javascriptreact' then return 'tsx' end
  return ft == 'javascript' and 'javascript' or 'typescript'
end

local function indexes(state, plugin)
  return Index.ensure(state, plugin)
end

function M.lookup(state, plugin, full_key)
  for _, source in ipairs(indexes(state, plugin)) do
    local per = source.index:get(full_key)
    if per then return per end
  end
end

function M.files_for(state, plugin, full_key)
  for _, source in ipairs(indexes(state, plugin)) do
    if source.index:owns(full_key) then return source.index:resolve_files_for_key(full_key) end
  end
  return nil, 'no-index'
end

function M.has_keys(state, plugin)
  for _, source in ipairs(indexes(state, plugin)) do
    if source.index:any_keys() then return true end
  end
  return false
end

function M.classify(state, plugin, full_key)
  for _, source in ipairs(indexes(state, plugin)) do
    local per = source.index:get(full_key)
    if per then return 'hit', per end
  end
  for _, source in ipairs(indexes(state, plugin)) do
    if source.index:owns(full_key) then return 'missing' end
  end
  return 'out'
end

function M.tree(state, plugin)
  local out = {}
  for _, source in ipairs(indexes(state, plugin)) do vim.list_extend(out, source.index:tree()) end
  return out
end

function M.missing_report(state, plugin)
  local out = {}
  for _, source in ipairs(indexes(state, plugin)) do vim.list_extend(out, source.index:missing_report()) end
  return out
end

function M.definitions_for_file(state, plugin, path)
  local normalized = vim.fs.normalize(path)
  local out = {}
  for _, source in ipairs(indexes(state, plugin)) do
    for _, full_key in ipairs(source.index:all_keys()) do
      for lang, entry in pairs(source.index:get(full_key) or {}) do
        if vim.fs.normalize(entry.file) == normalized then
          out[#out + 1] = { full_key = full_key, lang = lang, entry = entry }
        end
      end
    end
  end
  return out
end

local function preferred_lang(state, langs)
  local sorted = vim.deepcopy(langs)
  table.sort(sorted)
  local available = {}
  for _, lang in ipairs(sorted) do available[lang] = true end
  if state.config.display.lang and available[state.config.display.lang] then return state.config.display.lang end
  for _, lang in ipairs(state.config.display.preferred_langs or {}) do
    if available[lang] then return lang end
  end
  return sorted[1]
end

function M.pick_lang(state, _, per)
  return preferred_lang(state, vim.tbl_keys(per))
end

function M.preferred_lang(state, _, langs)
  return preferred_lang(state, langs)
end

function M.resolve_cursor(state, plugin, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  local first, with_hook
  for _, source in ipairs(indexes(state, plugin)) do
    local opts = vim.tbl_extend('force', source.ropts, { lang = buf_lang(bufnr) })
    local result = resolver.resolve_in_content(content, pos[1] - 1, pos[2], opts)
    if result.ok then
      if source.index:get(result.full_key) then return result end
      first = first or result
      if result.hook and not with_hook then with_hook = result end
    end
  end
  return with_hook or first or { ok = false, reason = 'not-in-t-call' }
end

local function collect_content(state, plugin, content, lang)
  local root = ast.parse_root(content, lang)
  local hits, misses = {}, {}
  for _, source in ipairs(indexes(state, plugin)) do
    if source.index:any_keys() then
      local opts = vim.tbl_extend('force', source.ropts, { lang = lang, root = root })
      for _, result in ipairs(resolver.collect_in_content(content, opts)) do
        local id = result.range.srow .. ':' .. result.range.scol
        local per = source.index:get(result.full_key)
        if per then
          hits[id] = { row = result.range.srow, range = result.range, literal = result.literal,
            full_key = result.full_key, kind = 'hit', per = per }
        elseif not misses[id] and source.index:owns(result.full_key) then
          misses[id] = { row = result.range.srow, range = result.range, literal = result.literal,
            full_key = result.full_key, kind = 'missing' }
        end
      end
    end
  end
  local out = {}
  for _, hit in pairs(hits) do out[#out + 1] = hit end
  for id, miss in pairs(misses) do if not hits[id] then out[#out + 1] = miss end end
  return out
end

function M.collect_buffer(state, plugin, bufnr)
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  return collect_content(state, plugin, content, buf_lang(bufnr))
end

function M.collect_content(state, plugin, content, path)
  local extension = path:match('%.([^.]+)$')
  local lang = (extension == 'tsx' or extension == 'jsx') and 'tsx'
    or extension == 'js' and 'javascript' or 'typescript'
  return collect_content(state, plugin, content, lang)
end

function M.reference_names(state, plugin)
  local names, seen = {}, {}
  for _, source in ipairs(indexes(state, plugin)) do
    for name in pairs(source.ropts.t_functions or {}) do
      if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
  end
  table.sort(names)
  return names
end

function M.definition_at_cursor(state, plugin, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  for _, definition in ipairs(M.definitions_for_file(state, plugin, path)) do
    if (definition.entry.row or 0) == row then return definition.full_key end
  end
end

return M

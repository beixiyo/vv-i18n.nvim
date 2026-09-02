-- 基于私有运行时索引的只读公共查询
local ast = require('vv-i18n.ast')
local resolver = require('vv-i18n.resolver')
local Index = require('vv-i18n.service.index')

local M = {}

local function buf_lang(bufnr)
  return ast.lang_for_buffer(bufnr)
end

local function indexes(state, plugin)
  return Index.ensure(state, plugin)
end

--- 该 source 的索引是否忽略此键；兼容只实现 get/owns/all_keys 的最小 index 替身（测试与外部注入）
local function is_ignored(source, full_key)
  return source.index.is_ignored ~= nil and source.index:is_ignored(full_key)
end

--- bufnr 对应窗口的光标（0-based 行列）。buffer 不在任何窗口显示时返回 nil，避免拿别的窗口的光标去解析它
---@param bufnr integer
---@return integer? row
---@return integer? col
local function cursor_in_buffer(bufnr)
  local win = bufnr == vim.api.nvim_get_current_buf() and vim.api.nvim_get_current_win() or vim.fn.bufwinid(bufnr)
  if win == -1 then return nil, nil end
  local pos = vim.api.nvim_win_get_cursor(win)
  return pos[1] - 1, pos[2]
end

function M.lookup(state, plugin, full_key)
  for _, source in ipairs(indexes(state, plugin)) do
    local per = source.index:get(full_key)
    if per then return per end
  end
end

function M.files_for(state, plugin, full_key)
  -- resolve_files_for_key 的 bad-prefix / unknown-mount 即“该 source 不拥有此键”，继续找下一个；ignored-key 直接终止
  for _, source in ipairs(indexes(state, plugin)) do
    local files, err = source.index:resolve_files_for_key(full_key)
    if files then return files end
    if err == 'ignored-key' then return nil, err end
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
  for source_index, source in ipairs(indexes(state, plugin)) do
    for _, group in ipairs(source.index:tree()) do
      group.source_id = source_index
      group.writable = source.source.parse == nil
      out[#out + 1] = group
    end
  end
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
  local row, col = cursor_in_buffer(bufnr)

  if row == nil or col == nil then return { ok = false, reason = 'buffer-not-visible' } end

  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  local first, with_hook, ignored

  for _, source in ipairs(indexes(state, plugin)) do
    local opts = vim.tbl_extend('force', source.ropts, { lang = buf_lang(bufnr) })
    local result = resolver.resolve_in_content(content, row, col, opts)

    if result.ok then
      if is_ignored(source, result.full_key) then
        ignored = true
      else
        if source.index:get(result.full_key) then return result end
        first = first or result
        if result.hook and not with_hook then with_hook = result end
      end
    end
  end

  local definition = M.definition_at_cursor(state, plugin, bufnr)

  if definition then return { ok = true, full_key = definition, definition = true } end
  if with_hook or first then return with_hook or first end

  return { ok = false, reason = ignored and 'ignored-key' or 'not-in-t-call' }
end

local function collect_content(state, plugin, content, lang)
  local root = ast.parse_root(content, lang)
  local calls = {}

  -- ambiguous 结果契约：
  -- { kind = 'ambiguous', range, row, literal, full_keys = string[],
  --   candidates = { { full_key = string, source_ids = integer[] } },
  --   source_ids = integer[], reason = string }
  -- references/index 将 ambiguous 的每个可能全键记为精确保护证据，避免误删

  local function call_for(id, result)
    local call = calls[id]
    if not call then
      call = {
        row = result.range.srow,
        range = result.range,
        literal = result.literal,
        observations = {},
      }
      calls[id] = call
    end
    return call
  end

  for source_id, source in ipairs(indexes(state, plugin)) do
    if source.index:any_keys() then
      -- all_keys() 内部会排序；一个 source 在一次 buffer 扫描中只取一次
      local all_keys = source.index:all_keys()
      local prefix_matches = {}
      local function keys_with_prefix(prefix)
        if prefix_matches[prefix] then return prefix_matches[prefix] end
        local matched = {}

        for _, full_key in ipairs(all_keys) do
          if vim.startswith(full_key, prefix) then matched[#matched + 1] = full_key end
        end

        prefix_matches[prefix] = matched
        return matched
      end

      local opts = vim.tbl_extend('force', source.ropts, { lang = lang, root = root })

      for _, result in ipairs(resolver.collect_in_content(content, opts)) do
        if not (result.full_key and is_ignored(source, result.full_key)) then
          local id = result.range.srow .. ':' .. result.range.scol
          local call = call_for(id, result)
          local per = result.full_key and source.index:get(result.full_key)

          local observation = {
            source_id = source_id,
            result = result,
            per = per,
            owns = result.full_key and source.index:owns(result.full_key) or false,
          }
          call.observations[#call.observations + 1] = observation

          if result.dynamic_prefix and result.dynamic_literal_prefix ~= '' then
            local matched = keys_with_prefix(result.dynamic_prefix)

            if #matched > 0 then
              call.dynamic = call.dynamic or {}
              local key = result.dynamic_prefix .. ':' .. source_id
              call.dynamic[key] = {
                row = result.range.srow,
                range = result.range,
                literal = result.literal,
                prefix = result.dynamic_prefix,
                pattern = result.dynamic_prefix .. '*',
                kind = 'dynamic',
                source_id = source_id,
              }
            end
          end

          if result.unsafe_dynamic then
            call.unsafe_dynamic = call.unsafe_dynamic or {}
            call.unsafe_dynamic[#call.unsafe_dynamic + 1] = observation
          end
        end
      end
    end
  end

  local out = {}

  local function append_call(call)
    local keys, by_key = {}, {}
    local source_ids = {}

    for _, observation in ipairs(call.observations) do
      local result = observation.result
      if result.full_key and not by_key[result.full_key] then
        by_key[result.full_key] = { full_key = result.full_key, source_ids = {} }
        keys[#keys + 1] = result.full_key
      end

      if result.full_key then
        local owners = by_key[result.full_key].source_ids
        if not owners[observation.source_id] then owners[observation.source_id] = true end
      end
      source_ids[observation.source_id] = true
    end
    table.sort(keys)

    local unsafe = call.unsafe_dynamic and #call.unsafe_dynamic > 0
    if unsafe then
      -- references/index.lua 识别 dynamic 并把 '*' 交给 unused/model 作为全局保护
      local source_list = {}
      for source_id in pairs(source_ids) do source_list[#source_list + 1] = source_id end

      table.sort(source_list)
      out[#out + 1] = {
        row = call.row,
        range = call.range,
        literal = call.literal,
        prefix = '',
        pattern = '*',
        kind = 'dynamic',
        unsafe = true,
        reason = 'unreliable-key',
        source_ids = source_list,
      }
    elseif #keys > 1 then
      local candidates = {}

      for _, full_key in ipairs(keys) do
        local item = by_key[full_key]
        local ids = {}
        for source_id in pairs(item.source_ids) do ids[#ids + 1] = source_id end
        table.sort(ids)
        candidates[#candidates + 1] = { full_key = full_key, source_ids = ids }
      end

      local ids = {}
      for source_id in pairs(source_ids) do ids[#ids + 1] = source_id end

      table.sort(ids)
      out[#out + 1] = {
        row = call.row,
        range = call.range,
        literal = call.literal,
        kind = 'ambiguous',
        reason = 'multiple-sources-resolved-different-keys',
        full_keys = keys,
        candidates = candidates,
        source_ids = ids,
      }
    elseif #keys == 1 then
      local full_key = keys[1]
      local hit, owned

      for _, observation in ipairs(call.observations) do
        if observation.result.full_key == full_key then
          if observation.per then hit = observation; break end
          owned = owned or observation.owns
        end
      end

      if hit then
        out[#out + 1] = {
          row = call.row,
          range = call.range,
          literal = hit.result.literal,
          full_key = full_key,
          kind = 'hit',
          per = hit.per,
          source_id = hit.source_id,
        }
      elseif owned then
        local source_id
        for id in pairs(by_key[full_key].source_ids) do source_id = id; break end

        out[#out + 1] = {
          row = call.row,
          range = call.range,
          literal = call.literal,
          full_key = full_key,
          kind = 'missing',
          source_id = source_id,
        }
      end
    end

    if call.dynamic then
      for _, dynamic in pairs(call.dynamic) do out[#out + 1] = dynamic end
    end
  end

  local ordered = {}

  for _, call in pairs(calls) do ordered[#ordered + 1] = call end
  table.sort(ordered, function(a, b)
    if a.row == b.row then return a.range.scol < b.range.scol end
    return a.row < b.row
  end)

  for _, call in ipairs(ordered) do append_call(call) end

  table.sort(out, function(a, b)
    if a.row == b.row then
      if a.range.scol == b.range.scol then return a.kind < b.kind end
      return a.range.scol < b.range.scol
    end
    return a.row < b.row
  end)

  return out
end

function M.collect_buffer(state, plugin, bufnr)
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  return collect_content(state, plugin, content, buf_lang(bufnr))
end

function M.collect_content(state, plugin, content, path)
  return collect_content(state, plugin, content, ast.lang_for_path(path))
end

function M.reference_names(state, plugin)
  local names, seen = {}, {}

  for _, source in ipairs(indexes(state, plugin)) do
    for name in pairs(source.ropts.t_functions or {}) do
      if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    for name in pairs(source.ropts.hook_names or {}) do
      if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
  end

  table.sort(names)

  return names
end

--- 光标处的 locale 定义 → 完整 key。匹配优先级：
---   1. 光标落在 key 节点范围内（key_range，0-based、end-exclusive）
---   2. 同一行光标左侧最近的 key（光标在值、冒号或逗号上；同行多个定义不会串到别的 key）
---   3. 值起始行匹配：跨行值、行首缩进，或自定义 parser 未返回 key_range；同行多个候选取最左
---@return string? full_key
function M.definition_at_cursor(state, plugin, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row, col = cursor_in_buffer(bufnr)
  if row == nil or col == nil then return nil end
  local path = vim.api.nvim_buf_get_name(bufnr)

  local function contains(range)
    if row < range.srow or row > range.erow then return false end
    if range.srow == range.erow then return col >= range.scol and col < range.ecol end
    if row == range.srow then return col >= range.scol end
    if row == range.erow then return col < range.ecol end
    return true
  end

  local preceding, preceding_col
  local on_value_row, on_value_row_col

  for _, definition in ipairs(M.definitions_for_file(state, plugin, path)) do
    local entry = definition.entry
    local range = entry.key_range
    if range and contains(range) then return definition.full_key end

    if range and range.srow == row and range.scol <= col and (preceding_col == nil or range.scol > preceding_col) then
      preceding, preceding_col = definition, range.scol
    end

    if (entry.row or 0) == row then
      local key_col = range and range.srow == row and range.scol or -1
      if on_value_row == nil or key_col < on_value_row_col then
        on_value_row, on_value_row_col = definition, key_col
      end
    end
  end

  if preceding then return preceding.full_key end
  if on_value_row then return on_value_row.full_key end
end

return M

-- 潜在无用 key 面板数据投影
--
-- 将分析报告和选择状态转换为 TreePanel 节点及渲染规格
-- 不持有窗口、扫描器、剪贴板或文件系统副作用

local M = {}
local Filter = require('vv-i18n.filter')
local util = require('vv-i18n.util')

local function node_id(key)
  return ('key:%d:%s'):format(#key, key)
end

---@param item table
---@param query string?
---@return boolean
local function matches(item, query)
  local fields = { item.full_key, item.rel, item.mount }
  for _, definition in ipairs(item.definitions or {}) do
    fields[#fields + 1] = definition.file
    fields[#fields + 1] = definition.value
  end
  return Filter.matches(fields, query)
end

---@param report table?
---@param query? string
---@return table[] nodes
function M.nodes(report, query)
  local groups, order = {}, {}
  for _, candidate in ipairs((report and report.candidates) or {}) do
    if matches(candidate, query) then
      local mount = candidate.mount or '(flat)'
      local group = groups[mount]
      if not group then
        group = {
          id = 'mount:' .. mount,
          label = mount,
          selectable = false,
          children = {},
          data = { kind = 'group' },
        }
        groups[mount] = group
        order[#order + 1] = group
      end
      group.children[#group.children + 1] = {
        id = node_id(candidate.full_key),
        label = candidate.rel or candidate.full_key,
        data = { kind = 'candidate', item = candidate },
      }
    end
  end
  table.sort(order, function(a, b) return a.label < b.label end)

  local unknown = (report and report.unknown) or {}
  if #unknown > 0 then
    local group = {
      id = 'unknown',
      label = 'Unknown — dynamic or unsafe references',
      selectable = false,
      children = {},
      data = { kind = 'group' },
    }
    for _, item in ipairs(unknown) do
      if matches(item, query) then
        group.children[#group.children + 1] = {
          id = 'unknown:' .. node_id(item.full_key),
          label = item.full_key,
          data = { kind = 'unknown', item = item },
        }
      end
    end
    if #group.children > 0 then order[#order + 1] = group end
  end
  return order
end

---@param report table?
---@param query? string
---@return integer
function M.match_count(report, query)
  local count = 0
  for _, collection in ipairs({
    (report and report.candidates) or {},
    (report and report.unknown) or {},
  }) do
    for _, item in ipairs(collection) do
      if matches(item, query) then count = count + 1 end
    end
  end
  return count
end

---@param node table?
---@return table? item
function M.item_of(node)
  local data = node and node.data
  return data and (data.kind == 'candidate' or data.kind == 'unknown') and data.item or nil
end

---@param node table?
---@return table? candidate
function M.candidate_of(node)
  local item = M.item_of(node)
  return item and item.status == 'candidate-unused' and item or nil
end

---@param ctx table
---@param selected table<string, boolean>
---@param preferred_lang? fun(langs: string[]): string?
---@return table
function M.node(ctx, selected, preferred_lang)
  local indent = string.rep('  ', ctx.depth)
  if ctx.has_children then
    return {
      chunks = {
        { indent .. (ctx.folded and ' ' or ' '), 'Comment' },
        { ctx.node.label, 'Directory' },
      },
      virt_text = { { tostring(#ctx.node.children), 'Comment' } },
    }
  end

  local item = M.item_of(ctx.node)
  local is_unknown = item and item.status == 'unknown'
  local checked = item and not is_unknown and selected[item.full_key]
  local langs = vim.tbl_keys((item and item.per) or {})
  local lang = preferred_lang and preferred_lang(langs) or nil
  local value = lang and util.entry_value(item.per[lang]) or nil
  return {
    chunks = {
      { indent .. (is_unknown and '? ' or checked and ' ' or ' '),
        is_unknown and 'DiagnosticInfo' or checked and 'DiagnosticOk' or 'Comment' },
      { ctx.node.label, 'Identifier' },
    },
    virt_text = value and { { util.truncate(value, 36), 'String' } } or nil,
    virt_text_pos = 'eol',
  }
end

---@param report table?
---@param query? string
---@param match_count? integer
---@return table
function M.header(report, query, match_count)
  report = report or { stats = {}, scan = {} }
  local status = report.scan.status
  local suffix = status and status ~= 'complete' and (' · ' .. status) or ''
  local filter = vim.trim(query or '')
  local summary = filter ~= ''
      and ('%d matches · /%s'):format(match_count or 0, filter)
    or ('%d candidates · %d unknown%s'):format(
      report.stats.candidates or 0, report.stats.unknown or 0, suffix)
  return {
    chunks = { { '  󰅖 Potentially unused keys', 'Title' } },
    virt_text = { { summary, 'Comment' } },
  }
end

function M.empty(report, query)
  if vim.trim(query or '') ~= '' then
    return { text = ("  No matches for '%s'"):format(query), hl = 'Comment' }
  end
  local status = report and report.scan and report.scan.status
  if status == 'scanning' then return { text = '  Scanning project references', hl = 'Comment' } end
  if status and status ~= 'complete' then
    return { text = '  Reference scan incomplete · press r to rescan', hl = 'DiagnosticWarn' }
  end
  return { text = '  No potential unused or unknown keys', hl = 'Comment' }
end

function M.toolbar()
  return {
    { key = 'x', label = 'Select' },
    { key = '/', label = 'Filter' },
    { key = 'c', label = 'Copy' },
    { key = 'C', label = 'Copy all' },
    { key = 'd', label = 'Delete' },
    { key = 'D', label = 'Delete all' },
    { key = 'r', label = 'Rescan' },
  }
end

return M

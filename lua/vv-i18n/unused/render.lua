-- 潜在无用 key 面板数据投影
--
-- 将分析报告和选择状态转换为 TreePanel 节点及渲染规格
-- 不持有窗口、扫描器、剪贴板或文件系统副作用

local M = {}

local function node_id(key)
  return ('key:%d:%s'):format(#key, key)
end

---@param report table?
---@return table[] nodes
function M.nodes(report)
  local groups, order = {}, {}
  for _, candidate in ipairs((report and report.candidates) or {}) do
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
      group.children[#group.children + 1] = {
        id = 'unknown:' .. node_id(item.full_key),
        label = item.full_key,
        data = { kind = 'unknown', item = item },
      }
    end
    order[#order + 1] = group
  end
  return order
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
---@return table
function M.node(ctx, selected)
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
  return {
    chunks = {
      { indent .. (is_unknown and '? ' or checked and ' ' or ' '),
        is_unknown and 'DiagnosticInfo' or checked and 'DiagnosticOk' or 'Comment' },
      { ctx.node.label, 'Identifier' },
    },
    virt_text = { { is_unknown and 'unknown' or 'candidate', is_unknown and 'DiagnosticInfo' or 'DiagnosticWarn' } },
  }
end

---@param report table?
---@return table
function M.header(report)
  report = report or { stats = {}, scan = {} }
  local status = report.scan.status
  local suffix = status and status ~= 'complete' and (' · ' .. status) or ''
  return {
    chunks = { { '  󰅖 Potentially unused keys', 'Title' } },
    virt_text = { { ('%d candidates · %d unknown%s'):format(
      report.stats.candidates or 0, report.stats.unknown or 0, suffix), 'Comment' } },
  }
end

function M.empty(report)
  local status = report and report.scan and report.scan.status
  if status == 'scanning' then return { text = '  Scanning project references', hl = 'Comment' } end
  if status and status ~= 'complete' then
    return { text = '  Reference scan incomplete · press r to rescan', hl = 'DiagnosticWarn' }
  end
  return { text = '  No potential unused or unknown keys', hl = 'Comment' }
end

function M.winbar()
  return {
    chunks = {
      { ' x ', 'Special' }, { 'Select', 'Comment' },
      { ' · c ', 'Special' }, { 'Copy', 'Comment' },
      { ' · C ', 'Special' }, { 'Copy all', 'Comment' },
      { ' · d ', 'Special' }, { 'Delete', 'Comment' },
      { ' · D ', 'Special' }, { 'Delete all', 'Comment' },
      { ' · r ', 'Special' }, { 'Rescan', 'Comment' },
    },
  }
end

return M

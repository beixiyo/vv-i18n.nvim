-- 潜在无用 key 工作流动作
--
-- 负责重建报告、选择、剪贴板交付、全新扫描后的删除确认和事务删除
-- 不创建或渲染 TreePanel 窗口

local Editor = require('vv-utils.editor')
local Confirm = require('vv-utils.confirm')
local Model = require('vv-i18n.unused.model')
local Copy = require('vv-i18n.unused.copy')
local Delete = require('vv-i18n.unused.delete')
local References = require('vv-i18n.references.index')

local M = {}

local function notify(message, level)
  vim.notify('[vv-i18n] ' .. message, level or vim.log.levels.INFO)
end

local function keys_of(items)
  local keys = {}
  for _, item in ipairs(items or {}) do keys[item.full_key] = true end
  return keys
end

local function sync_loaded_buffers(entries)
  local changed = {}
  for _, entry in ipairs(entries) do changed[entry.path] = true end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and changed[vim.api.nvim_buf_get_name(buf)] then
      vim.api.nvim_buf_call(buf, function() vim.cmd('checktime') end)
    end
  end
end

---@param plugin table
---@return table actions
function M.new(plugin)
  local self = {
    plugin = plugin,
    report = nil,
    selected = {},
  }

  function self:rebuild()
    local snapshot = References.snapshot()
    local plugin_state = self.plugin.get_state()
    snapshot.scan.root = plugin_state.root
    snapshot.scan.locale_failures = plugin_state.errors or {}
    snapshot.scan.scanning = snapshot.scanning
    self.report = Model.analyze({
      tree = self.plugin.tree(),
      references = snapshot.by_key,
      dynamic_evidence = snapshot.dynamic_evidence,
      scan = snapshot.scan,
    })
    return self.report
  end

  function self:toggle(candidate, panel)
    if not candidate or candidate.status ~= 'candidate-unused' then return end
    self.selected[candidate.full_key] = not self.selected[candidate.full_key] or nil
    panel:refresh()
  end

  function self:selected_candidates(fallback)
    local out = {}
    for _, candidate in ipairs((self.report and self.report.candidates) or {}) do
      if self.selected[candidate.full_key] then out[#out + 1] = candidate end
    end
    if #out == 0 and fallback and fallback.status == 'candidate-unused' then out[1] = fallback end
    return out
  end

  function self:copy(current, copy_all)
    self:rebuild()
    local scan = self.report and self.report.scan or {}
    if scan.status ~= 'complete' then
      local message = scan.status == 'scanning'
          and 'Reference scan is still running; copy again when it completes'
        or 'Reference scan is incomplete; rescan before copying'
      return notify(message, vim.log.levels.WARN)
    end

    local candidates = {}
    if copy_all then
      candidates = (self.report and self.report.candidates) or {}
    else
      candidates = self:selected_candidates()
    end
    local unknown = copy_all and ((self.report and self.report.unknown) or {}) or {}
    if not copy_all and #candidates == 0 and current then
      if current.status == 'unknown' then unknown = { current } else candidates = { current } end
    end

    local count = #candidates + #unknown
    if count == 0 then return notify('No audit items to copy', vim.log.levels.WARN) end
    local ctx = vim.deepcopy(self.report)
    ctx.candidates = candidates
    ctx.unknown = unknown
    ctx.stats.candidates = #candidates
    ctx.stats.unknown = #unknown
    local copy_config = self.plugin.get_config().unused.copy
    ctx.copy = vim.deepcopy(copy_config)
    local renderer = copy_config.render or Copy.render_default
    local ok, content = pcall(renderer, ctx)
    if not ok or type(content) ~= 'string' then
      return notify('Copy rendering failed: ' .. tostring(content), vim.log.levels.ERROR)
    end
    local copied, copy_error = pcall(Editor.copy, content, { title = 'vv-i18n', silent = true })
    if not copied then
      return notify('Failed to write to clipboard: ' .. tostring(copy_error), vim.log.levels.ERROR)
    end
    notify(('Copied audit material for %d key(s)'):format(count))
  end

  local function current_candidates(requested)
    local wanted = keys_of(requested)
    local current = {}
    for _, candidate in ipairs((self.report and self.report.candidates) or {}) do
      if wanted[candidate.full_key] then
        current[#current + 1] = candidate
        wanted[candidate.full_key] = nil
      end
    end
    return current, next(wanted) == nil
  end

  local function can_delete()
    local scan = self.report and self.report.scan or {}
    if scan.status ~= 'complete' then
      return false, 'Reference scan did not complete successfully: ' .. tostring(scan.status or 'unknown')
    end
    if #(scan.failures or {}) > 0 then return false, 'Some reference files failed to load' end
    if #(scan.locale_failures or {}) > 0 then return false, 'Some locale files failed to parse' end
    return true
  end

  local function build_plan(candidates)
    local snapshot = References.snapshot()
    return Delete.build(candidates, {
      generation = snapshot.generation,
      root = snapshot.scan.root,
      source_fingerprints = snapshot.scan.source_fingerprints,
    })
  end

  local function execute(plan, panel)
    local snapshot = References.snapshot()
    local ok, err = Delete.apply(plan, {
      scanning = snapshot.scanning,
      status = snapshot.scan.status,
      generation = snapshot.generation,
      root = snapshot.scan.root,
    })
    if not ok then return notify('Delete failed: ' .. tostring(err), vim.log.levels.ERROR) end
    sync_loaded_buffers(plan.entries)
    for _, candidate in ipairs(plan.candidates) do self.selected[candidate.full_key] = nil end
    self.plugin.reload()
    if panel:is_open() then panel:refresh() end
    notify(('Deleted %d key(s) across %d file(s)'):format(#plan.candidates, #plan.entries))
  end

  local function refresh_report(panel, callback)
    References.refresh(self.plugin, function()
      self:rebuild()
      if panel:is_open() then panel:refresh() end
      callback()
    end)
  end

  function self:confirm_delete(requested, panel)
    if #requested == 0 then return notify('No candidates selected', vim.log.levels.WARN) end
    local requested_keys = vim.tbl_keys(keys_of(requested))
    table.sort(requested_keys)

    -- 先刷新，避免为已经过期的报告展示确认对话框
    refresh_report(panel, function()
      local candidates, unchanged = current_candidates(requested)
      if not unchanged then
        return notify('Candidates changed after rescanning; review the refreshed report', vim.log.levels.WARN)
      end
      local allowed, reason = can_delete()
      if not allowed then return notify(reason, vim.log.levels.ERROR) end
      local plan, err = build_plan(candidates)
      if not plan then return notify(err, vim.log.levels.ERROR) end

      Confirm.open({
        title = 'Delete potentially unused keys?',
        message = {
          'Static scanning only produces candidates; it cannot prove that these keys are unused at runtime.',
          'A second full scan runs after confirmation before any locale file is changed.',
        },
        details = {
          { label = 'Keys', value = table.concat(requested_keys, '\n') },
          { label = 'Files', value = tostring(#plan.entries) },
          { label = 'Diff', value = plan.diff, separator_before = true },
        },
        severity = 'danger',
        confirm_label = 'Delete',
        on_confirm = function()
          -- 确认对话框打开期间，外部工具可能修改源文件
          -- 再次刷新，重新分类准确的目标 key，然后构建新的不可变计划
          refresh_report(panel, function()
            local latest, still_candidates = current_candidates(requested)
            if not still_candidates then
              return notify('Delete cancelled because references changed', vim.log.levels.WARN)
            end
            local latest_allowed, latest_reason = can_delete()
            if not latest_allowed then return notify(latest_reason, vim.log.levels.ERROR) end
            local latest_plan, latest_error = build_plan(latest)
            if not latest_plan then return notify(latest_error, vim.log.levels.ERROR) end
            execute(latest_plan, panel)
          end)
        end,
      })
    end)
  end

  return self
end

return M

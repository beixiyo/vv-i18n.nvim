-- 潜在无用 key 面板
--
-- 只把“静态引用扫描未命中”展示为候选。复制负责交付核查证据，删除负责
-- 生成不可变计划并经多文件事务落盘；扫描不完整时拒绝删除。

local State = require('vv-utils.state')
local TreePanel = require('vv-utils.tree_panel')
local Loading = require('vv-utils.loading')
local Actions = require('vv-i18n.unused.actions')
local Render = require('vv-i18n.unused.render')
local References = require('vv-i18n.references.index')

local M = {}

local active_panel
local active_actions
local panel_state = State.register('vv-i18n', 'unused')

local function jump(candidate, panel)
  local definition = candidate and candidate.definitions and candidate.definitions[1]
  if not definition or not definition.file then return end
  local source_win = panel.source_win
  if source_win and vim.api.nvim_win_is_valid(source_win) then vim.api.nvim_set_current_win(source_win) end
  vim.cmd('edit ' .. vim.fn.fnameescape(definition.file))
  pcall(vim.api.nvim_win_set_cursor, 0, { (definition.row or 0) + 1, definition.col or 0 })
  vim.cmd('normal! zz')
end

local function create_panel(plugin, actions)
  local opts = plugin.get_config().unused.panel
  local mappings = opts.mappings
  local panel
  local unsubscribe
  local panel_buf
  local stop_loading

  local function sync_loading()
    local scanning = actions.report and actions.report.scan and actions.report.scan.status == 'scanning'
    if not scanning then
      if stop_loading then stop_loading(); stop_loading = nil end
      return
    end
    if stop_loading or not panel_buf or not vim.api.nvim_buf_is_valid(panel_buf) then return end
    stop_loading = Loading.start({
      buf = panel_buf,
      get_row = function() return 1 end,
      prefix = ' ',
    })
  end

  panel = TreePanel.new({
    id = 'vv-i18n-unused',
    title = 'Potentially unused keys',
    filetype = 'vv-i18n-unused',
    width = opts.width,
    state = opts.state or panel_state,
    position = opts.position,
    help = opts.help,
    source = function() return Render.nodes(actions.report) end,
    open = function(node) jump(Render.item_of(node), panel) end,
    jump = function(node) jump(Render.item_of(node), panel) end,
    on_refresh = function()
      References.refresh(plugin, function()
        if panel:is_open() then actions:rebuild(); panel:refresh() end
      end)
    end,
    on_attach = function(current, buf)
      panel_buf = buf
      if mappings == nil then
        TreePanel.apply_default_mappings(current, {
          x = { desc = 'Toggle selection', callback = function(ctx)
            actions:toggle(Render.candidate_of(ctx.node), ctx.panel)
          end },
          c = { desc = 'Copy selected or current', callback = function(ctx)
            actions:copy(Render.item_of(ctx.node), false)
          end },
          C = { desc = 'Copy all', callback = function() actions:copy(nil, true) end },
          d = { desc = 'Delete selected or current', callback = function(ctx)
            actions:confirm_delete(actions:selected_candidates(Render.candidate_of(ctx.node)), ctx.panel)
          end },
          D = { desc = 'Delete all', callback = function(ctx)
            actions:confirm_delete(actions.report.candidates or {}, ctx.panel)
          end },
          r = { desc = 'Rescan', callback = function(ctx) ctx.panel:execute('refresh') end },
        })
      elseif mappings ~= false then
        TreePanel.apply_mappings(current, mappings)
      end
      require('vv-utils.mouse').block_visual_drag(buf)
      if opts.on_attach then opts.on_attach(current, buf) end
      sync_loading()
    end,
    on_close = function()
      if stop_loading then stop_loading(); stop_loading = nil end
      if unsubscribe then unsubscribe() end
      if active_panel == panel then active_panel = nil end
      if active_actions == actions then active_actions = nil end
    end,
    render = vim.tbl_extend('force', {
      header = function() return Render.header(actions.report) end,
      node = function(ctx) return Render.node(ctx, actions.selected) end,
      empty = function() return Render.empty(actions.report) end,
      winbar = Render.winbar,
    }, opts.render or {}),
  })
  panel:open()
  unsubscribe = References.subscribe(function()
    if panel:is_open() then
      actions:rebuild()
      panel:refresh()
      sync_loading()
    end
  end)
  sync_loading()
  return panel
end

function M.open(plugin)
  if active_panel and active_panel:is_open() then
    active_actions:rebuild()
    active_panel:refresh()
    vim.api.nvim_set_current_win(active_panel.win)
    return
  end
  active_actions = Actions.new(plugin)
  active_actions:rebuild()
  active_panel = create_panel(plugin, active_actions)
end

function M.toggle(plugin)
  if active_panel and active_panel:is_open() then return active_panel:close() end
  M.open(plugin)
end

function M.close()
  if not active_panel or not active_panel:is_open() then return false end
  active_panel:close()
  return true
end

return M

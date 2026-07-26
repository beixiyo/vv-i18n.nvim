---@diagnostic disable: undefined-field
-- i18n 键浏览面板：负责业务树转换、完整度渲染与编辑动作
--
-- 窗口、折叠、导航、帮助和宽度持久化统一委托给 vv-utils.tree_panel

local State = require('vv-utils.state')
local TreePanel = require('vv-utils.tree_panel')
local Model = require('vv-i18n.panel.model')
local Render = require('vv-i18n.panel.render')

local M = {}

local active_panel
local panel_state = State.register('vv-i18n', 'keys')
local view = {
  plugin = nil,
  source_tree = {},
  tree = {},
  languages = {},
  selected_lang = nil,
  only_missing = false,
  group_by = 'mount',
}

local function rebuild_tree()
  view.source_tree = view.plugin and view.plugin.tree() or {}
  view.languages = Model.languages(view.source_tree)
  if not vim.list_contains(view.languages, view.selected_lang) then
    view.selected_lang = view.plugin and view.plugin.preferred_lang(view.languages) or nil
  end
  view.tree = Model.build(view.source_tree, view.group_by)
end

local function make_nodes()
  return Model.nodes(view.tree, view.group_by, view.only_missing, {
    languages = view.languages,
    selected_lang = view.selected_lang,
  })
end

local function focus_first_key(panel)
  if not panel:is_open() then return end

  local first
  for line, row in pairs(panel.rows) do
    if row.node.data and row.node.data.kind == 'key' and (not first or line < first) then
      first = line
    end
  end
  if first then vim.api.nvim_win_set_cursor(panel.win, { first, 0 }) end
end

local function refresh(panel, focus_first)
  rebuild_tree()
  panel:refresh()
  if focus_first then focus_first_key(panel) end
end

local function edit_node(node, panel)
  local data = node and node.data
  if not data or data.kind ~= 'key' then return end

  local plugin = view.plugin
  if not plugin then return end
  require('vv-i18n.editor').open(plugin, data.key.full, {
    focus_lang = data.key.target_lang,
    target_win = panel.source_win,
    on_jump = function()
      if panel:is_open() then panel:close() end
    end,
    on_saved = function()
      plugin.reload()
      if panel:is_open() then refresh(panel) end
    end,
  })
end

local function open_node(node, panel)
  local data = node and node.data
  if not data then return end

  if data.kind == 'language' then
    view.selected_lang = data.lang
    panel:refresh()
    return
  end

  edit_node(node, panel)
end

local function business_mappings()
  return {
    e = {
      desc = 'edit',
      callback = function(ctx) edit_node(ctx.node, ctx.panel) end,
    },
    m = {
      desc = 'only_missing',
      callback = function(ctx)
        view.only_missing = not view.only_missing
        refresh(ctx.panel)
      end,
    },
    g = {
      desc = 'group_by_missing_lang',
      callback = function(ctx)
        view.group_by = view.group_by == 'missing_lang' and 'mount' or 'missing_lang'
        refresh(ctx.panel, true)
      end,
    },
    r = {
      desc = 'reload',
      callback = function(ctx)
        view.plugin.reload()
        refresh(ctx.panel)
      end,
    },
    ['<LeftRelease>'] = {
      desc = 'click',
      callback = function(ctx)
        if ctx.node and ctx.node.data
            and (ctx.node.data.kind == 'group' or ctx.node.data.kind == 'languages')
        then
          ctx.panel:execute('toggle_node')
        else
          open_node(ctx.node, ctx.panel)
        end
      end,
    },
  }
end

local function help_options(configured)
  if configured == false then return false end

  configured = type(configured) == 'table' and configured or {}
  local options = vim.tbl_extend('force', {
    title = 'vv-i18n keymaps',
    title_icon = '󰗊',
    filetype = 'vv-i18n-help',
    categories = { 'Navigate', 'View', 'Mouse' },
  }, configured)
  options.actions = vim.tbl_deep_extend('force', {
    edit = { cat = 'Navigate' },
    only_missing = { cat = 'View' },
    group_by_missing_lang = { cat = 'View' },
    reload = { cat = 'View' },
    click = { cat = 'Mouse' },
  }, configured.actions or {})
  return options
end

local function create_panel(plugin)
  local opts = plugin.get_config().panel
  local mappings = opts.mappings
  local render = vim.tbl_extend('force', Render.defaults(view), opts.render or {})
  local panel

  panel = TreePanel.new({
    id = 'vv-i18n-keys',
    title = 'i18n keys',
    filetype = 'vv-i18n-panel',
    width = opts.width,
    state = opts.state or panel_state,
    position = opts.position,
    help = help_options(opts.help),
    source = make_nodes,
    render = render,
    open = function(node) open_node(node, panel) end,
    jump = function(node) edit_node(node, panel) end,
    on_refresh = function() view.plugin.reload(); refresh(panel) end,
    on_attach = function(current, buf)
      if mappings == nil then
        TreePanel.apply_default_mappings(current, business_mappings())
      elseif mappings ~= false then
        TreePanel.apply_mappings(current, mappings)
      end
      require('vv-utils.mouse').block_visual_drag(buf)
      if opts.on_attach then opts.on_attach(current, buf) end
      vim.wo[current.win].winhighlight =
        'Normal:NormalFloat,CursorLine:PmenuSel,EndOfBuffer:NonText'
      vim.wo[current.win].statusline = ' '
    end,
    on_close = function()
      if active_panel == panel then active_panel = nil end
      view.plugin = nil
      view.source_tree = {}
      view.tree = {}
      view.languages = {}
    end,
  })
  return panel
end

---@param plugin table
---@param opts? { only_missing?: boolean, group_by?: 'mount'|'missing_lang' }
function M.open(plugin, opts)
  opts = opts or {}
  view.plugin = plugin
  view.only_missing = opts.only_missing == true
  view.group_by = opts.group_by or 'mount'
  rebuild_tree()

  if active_panel and active_panel:is_open() then
    active_panel:refresh()
    vim.api.nvim_set_current_win(active_panel.win)
    focus_first_key(active_panel)
    return
  end

  local panel = create_panel(plugin)
  panel:open()
  active_panel = panel
  focus_first_key(panel)
end

function M.close()
  if not active_panel or not active_panel:is_open() then return false end
  active_panel:close()
  return true
end

---@param plugin table
---@param opts? { only_missing?: boolean, group_by?: 'mount'|'missing_lang' }
function M.toggle(plugin, opts)
  if active_panel and active_panel:is_open() and not opts then
    active_panel:close()
  else
    M.open(plugin, opts)
  end
end

function M.missing_count(plugin)
  return Model.missing_total(plugin and plugin.tree() or {})
end

return M

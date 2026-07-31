-- Setup, teardown, highlights, autocmds, and user-command registration.
local Config = require('vv-i18n.config')
local Index = require('vv-i18n.service.index')
local Runtime = require('vv-i18n.service.runtime')
local Commands = require('vv-i18n.service.commands')

local M = {}

local function apply_display_hl(state)
  local display = state.config.display
  if display.style then
    pcall(vim.api.nvim_set_hl, 0, display.hl, display.style)
  else
    local ok, base = pcall(vim.api.nvim_get_hl, 0, { name = 'Comment', link = false })
    pcall(vim.api.nvim_set_hl, 0, display.hl, { fg = ok and base and base.fg or nil, italic = true })
  end
  if display.missing_style then
    pcall(vim.api.nvim_set_hl, 0, display.missing_hl, display.missing_style)
  else
    pcall(vim.api.nvim_set_hl, 0, display.missing_hl, { link = 'DiagnosticVirtualTextWarn', default = true })
  end
end

local function register_commands(state, plugin)
  local command = vim.api.nvim_create_user_command
  command('VVI18nKeys', function() Commands.open_panel(plugin) end, { desc = 'vv-i18n: 键浏览/同步编辑面板' })
  command('VVI18nMissing', function() Commands.open_missing_panel(plugin) end, { desc = 'vv-i18n: 缺失 key 检测面板' })
  command('VVI18nReferences', function() Commands.open_references(plugin) end, { desc = 'vv-i18n: 当前 key 引用侧栏' })
  command('VVI18nEdit', function() Commands.edit_cursor(plugin) end, { desc = 'vv-i18n: 多语言同步编辑' })
  command('VVI18nInfo', function() Commands.info(plugin) end, { desc = 'vv-i18n: 光标处键各语言译文' })
  command('VVI18nJump', function() Commands.jump(plugin) end, { desc = 'vv-i18n: 跳到 locale 定义' })
  command('VVI18nSetValue', function() Commands.set_value(plugin) end, { desc = 'vv-i18n: 改某语言值' })
  command('VVI18nAddKey', function() Commands.add_key(plugin) end, { desc = 'vv-i18n: 补缺失语言' })
  command('VVI18nReload', function() plugin.reload(); Commands.notify_reload(state) end, { desc = 'vv-i18n: 重建索引' })
  command('VVI18n', function() plugin.toggle() end, { desc = 'vv-i18n: 行内预览开关' })
  command('VVI18nEnable', function() plugin.enable() end, { desc = 'vv-i18n: 开启行内预览' })
  command('VVI18nDisable', function() plugin.disable() end, { desc = 'vv-i18n: 关闭行内预览' })
  command('VVI18nToggle', function() plugin.toggle() end, { desc = 'vv-i18n: 切换行内预览' })
end

local function enable_references(state, plugin)
  require('vv-i18n.references.display').enable(plugin, state.config.references)
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('VVI18nReferencesIndex', { clear = true }),
    pattern = { '*.ts', '*.tsx', '*.js', '*.jsx' },
    callback = function(event)
      require('vv-i18n.references.index').update_file(plugin, vim.api.nvim_buf_get_name(event.buf))
    end,
  })
end

function M.reload(state, plugin)
  local indexes = Index.reload(state, plugin)
  apply_display_hl(state)
  return indexes
end

function M.setup(state, plugin, opts)
  state.setup_epoch = state.setup_epoch + 1
  local epoch = state.setup_epoch

  require('vv-i18n.references.display').disable()
  require('vv-i18n.display').disable()

  pcall(vim.api.nvim_del_augroup_by_name, 'VVI18nReferencesIndex')

  Runtime.set_config(state, Config.setup(opts or {}))

  if not state.config.references.enable then
    require('vv-i18n.references.index').clear()
    state.references_dirty = true
  end
  apply_display_hl(state)

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('VVI18nHl', { clear = true }),
    callback = function() apply_display_hl(state) end,
  })
  vim.api.nvim_create_autocmd('DirChanged', {
    group = vim.api.nvim_create_augroup('VVI18nProject', { clear = true }),
    callback = function() pcall(plugin.reload) end,
  })
  register_commands(state, plugin)

  if state.config.references.enable then
    enable_references(state, plugin)
  end
  vim.schedule(function()
    if state.setup_epoch ~= epoch then return end

    local had_indexes = state.indexes ~= nil
    Index.ensure(state, plugin)
    if state.setup_epoch ~= epoch then return end

    apply_display_hl(state)
    if state.config.references.enable then
      enable_references(state, plugin)
      if had_indexes and state.references_dirty then
        require('vv-i18n.references.index').refresh(plugin)
        state.references_dirty = false
      end
    else
      require('vv-i18n.references.display').disable()
      pcall(vim.api.nvim_del_augroup_by_name, 'VVI18nReferencesIndex')
      require('vv-i18n.references.index').clear()
      state.references_dirty = true
    end
    if state.config.display.enable then pcall(plugin.enable) end
  end)
end

return M

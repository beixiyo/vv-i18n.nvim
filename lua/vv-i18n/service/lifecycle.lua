-- setup、teardown、高亮、autocmd 与用户命令注册
local Config = require('vv-i18n.config')
local Index = require('vv-i18n.service.index')
local Runtime = require('vv-i18n.service.runtime')
local Commands = require('vv-i18n.service.commands')
local References = require('vv-i18n.references.index')
local ReferenceScanners = require('vv-i18n.references.scanners')

local M = {}

--- 取高亮组前景色并向 Normal 背景混入 amount 比例，得到同色相的柔和版本；缺少前景或背景时原样返回
---@param group string
---@param amount number 0-1，越大越接近背景
---@return integer? fg
local function muted_fg(group, amount)
  local ok, base = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if not ok or type(base) ~= 'table' or type(base.fg) ~= 'number' then return nil end
  local nok, normal = pcall(vim.api.nvim_get_hl, 0, { name = 'Normal', link = false })
  if not nok or type(normal) ~= 'table' or type(normal.bg) ~= 'number' then return base.fg end
  local mok, mixed = pcall(function()
    local color = require('vv-utils.color')
    return color.to_integer(color.mix(base.fg, normal.bg, amount))
  end)
  return mok and mixed or base.fg
end

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

  -- 引用数数字：默认借主题 Statement 的前景色（多数主题为紫/品红），向 Normal 背景混色压低饱和度，
  -- 使其在行尾虚拟文本里醒目但不刺眼；不加粗。随 ColorScheme 重算
  local references = state.config.references
  if references.count_style then
    pcall(vim.api.nvim_set_hl, 0, references.count_hl, references.count_style)
  else
    pcall(vim.api.nvim_set_hl, 0, references.count_hl, { fg = muted_fg('Statement', 0.3) })
  end
end

local function register_commands(state, plugin)
  local command = vim.api.nvim_create_user_command
  command('VVI18nKeys', function() Commands.open_panel(plugin) end, { desc = 'vv-i18n: 键浏览/同步编辑面板' })
  command('VVI18nMissing', function() Commands.open_missing_panel(plugin) end, { desc = 'vv-i18n: 缺失 key 检测面板' })
  command('VVI18nReferences', function() Commands.open_references(plugin) end, { desc = 'vv-i18n: 当前 key 引用侧栏' })
  command('VVI18nUnused', function() Commands.open_unused_panel(plugin) end, { desc = 'vv-i18n: 潜在无用 key 面板' })
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
  local patterns = {}
  for _, extension in ipairs(ReferenceScanners.extensions(plugin)) do
    patterns[#patterns + 1] = '*.' .. extension
  end
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('VVI18nReferencesIndex', { clear = true }),
    pattern = patterns,
    callback = function(event)
      require('vv-i18n.references.index').update_file(plugin, vim.api.nvim_buf_get_name(event.buf))
    end,
  })
end

function M.reload(state, plugin)
  -- 先撤销旧 root 的引用快照，避免 A→B 重载窗口暴露旧索引
  References.clear()
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

  local had_indexes = state.indexes ~= nil
  Runtime.set_config(state, Config.setup(opts or {}))
  if had_indexes and not state.indexes then References.clear() end

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

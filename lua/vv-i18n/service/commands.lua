-- Command handlers and interactive entry points.
local writer = require('vv-i18n.writer')

local M = {}

local function notify(message, level)
  vim.notify('[vv-i18n] ' .. message, level or vim.log.levels.INFO)
end

function M.info(plugin)
  local result = plugin.resolve_cursor()
  if not result.ok then return notify('光标处无 i18n 键：' .. (result.reason or '?'), vim.log.levels.WARN) end
  require('vv-i18n.info').open(plugin, result.full_key, {
    note = result.reason == 'no-binding' and '未找到翻译 hook 绑定，按字面量解析' or nil,
  })
end

function M.jump(plugin)
  local result = plugin.resolve_cursor()
  if not result.ok then return notify('光标处无 i18n 键：' .. (result.reason or '?'), vim.log.levels.WARN) end
  local per = plugin.lookup(result.full_key)
  if not per then return notify('索引中未找到 ' .. result.full_key, vim.log.levels.WARN) end
  local entry = per[plugin.pick_lang(per)]
  vim.cmd('edit ' .. vim.fn.fnameescape(entry.file))
  pcall(vim.api.nvim_win_set_cursor, 0, { (entry.row or 0) + 1, entry.col or 0 })
  vim.cmd('normal! zz')
end

function M.set_value(plugin)
  local result = plugin.resolve_cursor()
  if not result.ok then return notify('光标处无 i18n 键', vim.log.levels.WARN) end
  local per = plugin.lookup(result.full_key)
  if not per then return notify('索引中未找到 ' .. result.full_key, vim.log.levels.WARN) end
  local lang = plugin.pick_lang(per)
  local current = per[lang]
  vim.ui.input({ prompt = ('改 %s [%s]: '):format(result.full_key, lang), default = current.value or '' }, function(input)
    if input == nil then return end
    local write = writer.update_file(current.file, current.in_file_path, input, plugin.writer_opts())
    if write.ok then
      notify(('已写入 %s [%s]'):format(result.full_key, lang))
      plugin.reload()
    else
      notify('写入失败：' .. (write.reason or '?'), vim.log.levels.ERROR)
    end
  end)
end

function M.add_key(plugin)
  local result = plugin.resolve_cursor()
  local function add(full_key)
    local files, error = plugin.files_for(full_key)
    if not files then return notify('无法定位文件：' .. tostring(error), vim.log.levels.WARN) end
    local missing = {}
    for _, file in ipairs(files) do if not file.exists then missing[#missing + 1] = file end end
    if #missing == 0 then return notify('该键各语言均已存在') end
    vim.ui.input({ prompt = ('补 %s（%d 个语言缺失）值: '):format(full_key, #missing) }, function(input)
      if input == nil or input == '' then return end
      local done, failures = 0, {}
      for _, file in ipairs(missing) do
        local write = writer.add_file(file.file, file.in_file_path, input, plugin.writer_opts())
        if write.ok then done = done + 1 else failures[#failures + 1] = file.lang .. ':' .. (write.reason or '?') end
      end
      notify(('已补 %d 个语言%s'):format(done, #failures > 0 and ('，失败: ' .. table.concat(failures, ', ')) or ''))
      plugin.reload()
    end)
  end
  if result.ok then return add(result.full_key) end
  vim.ui.input({ prompt = '要新增的全键: ' }, function(input)
    if input and input ~= '' then add(input) end
  end)
end

function M.open_panel(plugin)
  require('vv-i18n.panel').toggle(plugin)
end

function M.open_missing_panel(plugin)
  require('vv-i18n.panel').open(plugin, { only_missing = true, group_by = 'missing_lang' })
end

function M.open_references(plugin)
  local panel = require('vv-i18n.references.panel')
  local references = require('vv-i18n.references.index')
  local resolved = plugin.resolve_cursor()
  local full_key = resolved.ok and resolved.full_key or plugin.definition_at_cursor()
  if not full_key then return notify('No i18n key under cursor', vim.log.levels.WARN) end

  local items = references.get(full_key)
  if plugin.get_config().references.jump_single and #items == 1 then
    panel.close()
    require('vv-i18n.references.navigation').jump(items[1])
    return
  end
  panel.toggle(plugin, full_key)
end

function M.edit_cursor(plugin)
  local result = plugin.resolve_cursor()
  if not result.ok then return notify('光标处无 i18n 键：' .. (result.reason or '?'), vim.log.levels.WARN) end
  require('vv-i18n.editor').open(plugin, result.full_key, {
    target_win = vim.api.nvim_get_current_win(),
    on_saved = function() plugin.reload() end,
  })
end

function M.notify_reload(state)
  local keys = 0
  for _, source in ipairs(state.indexes or {}) do keys = keys + source.index:stats().keys end
  notify(('索引已重建：%d 源 / %d 键%s'):format(#(state.indexes or {}), keys,
    #state.errors > 0 and ('，%d 文件解析失败'):format(#state.errors) or ''))
end

return M

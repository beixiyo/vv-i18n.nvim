-- vv-i18n.editor — 单键多语言同步编辑器
--
-- 每种语言占一行固定输入槽，语言标签以 overlay virtual text 渲染
-- model 负责数据与写回，fields 负责输入槽约束，navigation 负责定义跳转
local fields = require('vv-i18n.editor.fields')
local model = require('vv-i18n.editor.model')
local navigation = require('vv-i18n.editor.navigation')

local M = {}

local state = nil

local function close()
  if state and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state = nil
end

local function current_values()
  if not state then return {} end
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  return model.from_edit_lines(lines, state.value_col)
end

local function pending_writes()
  if not state then return {} end
  return model.diff(state.rows, current_values())
end

local function request_close()
  if not state then return true end
  if #pending_writes() == 0 then
    close()
    return true
  end

  local choice = vim.fn.confirm(
    'Discard unsaved changes?',
    '&Yes\n&No',
    2
  )
  if choice ~= 1 then return false end

  close()
  return true
end

local function save()
  if not state then return end
  local writes = pending_writes()
  local writer_opts = state.plugin.writer_opts and state.plugin.writer_opts() or {}
  local changed, fails, applied = model.apply(writes, writer_opts)

  local on_saved = state.on_saved
  local key = state.full_key
  model.accept_applied(state.rows, applied)
  fields.render(state)
  if #fails == 0 then vim.bo[state.buf].modified = false end

  if #fails > 0 then
    vim.notify(('[vv-i18n] Failed to save %s: %s'):format(key, table.concat(fails, ', ')), vim.log.levels.ERROR)
  elseif changed > 0 then
    vim.notify(('[vv-i18n] Saved %s (%d changes)'):format(key, changed))
  else
    vim.notify('[vv-i18n] No changes')
  end
  if on_saved then pcall(on_saved, changed) end
end

local function jump_to_definition()
  if not state then return end
  if #pending_writes() > 0 then
    return vim.notify('[vv-i18n] Unsaved changes. Press <C-s> to save first', vim.log.levels.WARN)
  end

  local row = fields.current_row(state)
  if row then navigation.jump(state, row, close) end
end

local function install_keymaps(buf)
  local map = function(mode, lhs, callback, opts)
    vim.keymap.set(mode, lhs, callback, vim.tbl_extend('force', {
      buffer = buf,
      silent = true,
      nowait = true,
      desc = 'vv-i18n: editor',
    }, opts or {}))
  end
  local row = function() return fields.current_row(state) end
  local focus = function(offset, insert)
    fields.focus(state, row() + offset, insert)
  end

  map({ 'n', 'i' }, '<C-s>', save)
  map('n', '<CR>', jump_to_definition)
  map('n', 'j', function() focus(1, false) end)
  map('n', 'k', function() focus(-1, false) end)
  map('n', '<Down>', function() focus(1, false) end)
  map('n', '<Up>', function() focus(-1, false) end)
  map('n', '<Tab>', function() focus(1, false) end)
  map('n', '<S-Tab>', function() focus(-1, false) end)
  map('n', 'o', function() focus(1, true) end)
  map('n', 'O', function() focus(-1, true) end)
  map('n', 'dd', function() fields.clear(state, false) end)
  map('n', 'cc', function() fields.clear(state, true) end)
  map('n', 'S', function() fields.clear(state, true) end)
  map('n', 'J', '<Nop>')
  map('n', '0', function() fields.focus_start(state) end)
  map('n', '^', function() fields.focus_start(state) end)
  map('n', 'I', function()
    fields.set_cursor(state, row(), state.value_col)
    vim.cmd('startinsert')
  end)
  map('i', '<CR>', function()
    vim.cmd('stopinsert')
    jump_to_definition()
  end)
  map('i', '<Tab>', function() focus(1, true) end)
  map('i', '<S-Tab>', function() focus(-1, true) end)
  map('i', '<BS>', function()
    return vim.api.nvim_win_get_cursor(state.win)[2] <= state.value_col
      and ''
      or '<BS>'
  end, { expr = true })
  map('i', '<Del>', function()
    local current_row = row()
    local line = vim.api.nvim_buf_get_lines(buf, current_row - 1, current_row, false)[1] or ''
    return vim.api.nvim_win_get_cursor(state.win)[2] >= #line
      and ''
      or '<Del>'
  end, { expr = true })
  map('n', 'q', request_close)
  map('n', '<Esc>', request_close)
end

local function install_autocmds(buf)
  vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = save })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'InsertEnter' }, {
    buffer = buf,
    callback = function() fields.clamp_cursor(state) end,
  })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = buf,
    callback = function() fields.guard_structure(state) end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      if state and state.buf == buf then state = nil end
    end,
  })
end

--- 打开某键的多语言编辑浮窗
---@param plugin table vv-i18n 主模块
---@param full_key string
---@param opts? { on_saved?: fun(changed: integer), focus_lang?: string, target_win?: integer }
function M.open(plugin, full_key, opts)
  opts = opts or {}
  if state and state.win and vim.api.nvim_win_is_valid(state.win) and not request_close() then return end

  local rows, lines, err = model.plan(plugin, full_key)
  if not rows then
    return vim.notify('[vv-i18n] Unable to locate locale files: ' .. tostring(err), vim.log.levels.WARN)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local edit_lines, value_col = model.to_edit_lines(rows, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'vv-i18n-editor'
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, edit_lines)

  local width = #full_key + 4
  for _, line in ipairs(edit_lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 8)
  end
  width = math.max(60, math.min(width, vim.o.columns - 8))
  local height = math.max(#lines, 1)
  local target_win = opts.target_win or navigation.main_window()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' 󰗊 ' .. full_key .. ' ',
    title_pos = 'center',
    footer = ' Jump ↵ · Save ^s · Next ⇥ · Close q ',
    footer_pos = 'center',
  })
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder'
  vim.wo[win].virtualedit = 'onemore'

  state = {
    buf = buf,
    win = win,
    full_key = full_key,
    rows = rows,
    lang_width = model.lang_width(rows),
    value_col = value_col,
    last_lines = vim.deepcopy(edit_lines),
    target_win = target_win,
    on_saved = opts.on_saved,
    plugin = plugin,
  }

  install_keymaps(buf)
  install_autocmds(buf)
  pcall(require('vv-utils.mouse').block_visual_drag, buf)
  fields.render(state)

  local focus_index = 1
  if opts.focus_lang then
    for i, row in ipairs(rows) do
      if row.lang == opts.focus_lang then
        focus_index = i
        break
      end
    end
  end
  fields.focus(state, focus_index, false)
end

M.plan = model.plan
M.diff = model.diff
M.apply = model.apply
M._close = close

return M

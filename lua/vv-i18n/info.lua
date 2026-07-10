-- vv-i18n.info — 光标处 key 的多语言译文预览窗口
--
-- 替代 notify 长文本：译文进入可聚焦浮窗，方便滚动、复制，并可用 e/<CR> 跳到
-- 既有多语言编辑器
local hl = require('vv-utils.hl')

local M = {}

local ns = vim.api.nvim_create_namespace('vv_i18n_info')
local state = nil

hl.register('vv-i18n.info.hl', {
  VVI18nInfoTitle   = { link = 'Title' },
  VVI18nInfoKey     = { link = 'Identifier' },
  VVI18nInfoLang    = { link = 'Constant' },
  VVI18nInfoValue   = { link = 'String' },
  VVI18nInfoMissing = { link = 'DiagnosticWarn' },
  VVI18nInfoNote    = { link = 'Comment' },
  VVI18nInfoFooter  = { link = 'Comment' },
})

local function close()
  if state and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state = nil
end

local function sorted_langs(per)
  local langs = {}
  for lang in pairs(per or {}) do langs[#langs + 1] = lang end
  table.sort(langs)
  return langs
end

local function lang_width(langs)
  local width = 0
  for _, lang in ipairs(langs) do
    width = math.max(width, vim.fn.strdisplaywidth(lang))
  end
  return math.max(width, 4)
end

local function build_lines(plugin, full_key, per, note)
  local lines, hls = {}, {}
  local function add_hl(row, col, end_col, group)
    hls[#hls + 1] = { row = row, col = col, end_col = end_col, group = group }
  end

  local title = '  󰗊  i18n preview'
  lines[#lines + 1] = title
  add_hl(#lines - 1, 0, #title, 'VVI18nInfoTitle')

  local key_line = '  key  ' .. full_key
  lines[#lines + 1] = key_line
  add_hl(#lines - 1, 7, #key_line, 'VVI18nInfoKey')

  if note then
    local note_line = '  ' .. note
    lines[#lines + 1] = note_line
    add_hl(#lines - 1, 0, #note_line, 'VVI18nInfoNote')
  end

  lines[#lines + 1] = ''

  if not per then
    local missing = '  索引中未找到该键'
    lines[#lines + 1] = missing
    add_hl(#lines - 1, 0, #missing, 'VVI18nInfoMissing')
  else
    local langs = sorted_langs(per)
    local width = lang_width(langs)
    local preferred = plugin.preferred_lang(langs)

    for _, lang in ipairs(langs) do
      local entry = per[lang]
      local value = entry.kind == 'string' and entry.value or ('<' .. entry.kind .. '>')
      local prefix = '  ' .. lang .. string.rep(' ', width - vim.fn.strdisplaywidth(lang)) .. '  '
      local line = prefix .. value
      lines[#lines + 1] = line
      local lnum = #lines - 1
      add_hl(lnum, 2, 2 + #lang, lang == preferred and 'VVI18nInfoKey' or 'VVI18nInfoLang')
      add_hl(lnum, #prefix, #line, 'VVI18nInfoValue')
    end
  end

  lines[#lines + 1] = ''
  local footer = '  e/<CR> 编辑 · r 重载 · y 复制 key · q 关闭'
  lines[#lines + 1] = footer
  add_hl(#lines - 1, 0, #footer, 'VVI18nInfoFooter')

  return lines, hls
end

local function render()
  if not state or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local lines, hls = build_lines(state.plugin, state.full_key, state.per, state.note)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, h.row, h.col, {
      end_col = h.end_col,
      hl_group = h.group,
    })
  end
end

local function refresh()
  if not state then return end
  state.plugin.reload()
  state.per = state.plugin.lookup(state.full_key)
  render()
end

local function edit()
  if not state then return end
  local plugin = state.plugin
  local full_key = state.full_key
  close()
  require('vv-i18n.editor').open(plugin, full_key, {
    on_saved = function()
      plugin.reload()
    end,
  })
end

local function copy_key()
  if state then pcall(vim.fn.setreg, '+', state.full_key) end
end

---@param plugin table
---@param full_key string
---@param opts? { note?: string }
function M.open(plugin, full_key, opts)
  opts = opts or {}
  if state and state.win and vim.api.nvim_win_is_valid(state.win) then close() end

  local per = plugin.lookup(full_key)
  local lines = build_lines(plugin, full_key, per, opts.note)

  local width = math.max(48, #full_key + 12)
  for _, line in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(line) + 2) end
  width = math.max(20, math.min(width, math.max(20, vim.o.columns - 8)))
  local height = math.max(1, math.min(#lines, math.max(1, vim.o.lines - 6)))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'vv-i18n-info'
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = 'minimal',
    border = 'rounded',
    title = ' i18n ',
    title_pos = 'center',
  })

  require('vv-utils.ui_window').hide_chrome(win, { cursorline = true })
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder,CursorLine:PmenuSel'

  state = {
    buf = buf,
    win = win,
    plugin = plugin,
    full_key = full_key,
    per = per,
    note = opts.note,
  }
  render()

  pcall(require('vv-utils.mouse').block_visual_drag, buf)

  local map = function(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, silent = true, nowait = true, desc = 'vv-i18n: ' .. desc })
  end
  map('<CR>', edit, 'edit')
  map('e', edit, 'edit')
  map('r', refresh, 'reload')
  map('y', copy_key, 'copy_key')
  map('q', close, 'close')
  map('<Esc>', close, 'close')

  vim.api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function() state = nil end })
end

M._close = close

return M

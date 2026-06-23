-- vv-i18n.panel — 键浏览 / 完整度树 / 同步编辑入口（对标 lokalise 键列表）
--
-- 按挂载点（hero/common/…）分组列出所有键，每行示主语言译文 + 各语言完整度
-- 勾叉徽标；<CR> 打开多语言同步编辑浮窗（editor.lua）。窗口骨架照 vv-flow/panel
local hl = require('vv-utils.hl')
local truncate = require('vv-i18n.util').truncate

local M = {}

local ns = vim.api.nvim_create_namespace('vv_i18n_panel')

---@type { buf: integer?, win: integer?, prev_win: integer?, plugin: table?, tree: table[]?, only_missing: boolean }
local state = { only_missing = false }

-- 行 → 数据：{ kind='group'|'key', group_idx, key? }
local line_map = {}

local CHEV_OPEN, CHEV_CLOSED = '▾', '▸'

hl.register('vv-i18n.panel.hl', {
  VVI18nPanelTitle   = { link = 'Title' },
  VVI18nPanelSep     = { link = 'Comment' },
  VVI18nPanelChevron = { link = 'Comment' },
  VVI18nPanelGroup   = { link = 'Directory' },
  VVI18nPanelCount   = { link = 'Comment' },
  VVI18nPanelKey     = { link = 'Identifier' },
  VVI18nPanelValue   = { link = 'String' },
  VVI18nPanelOk      = { link = 'DiagnosticOk' },
  VVI18nPanelMiss    = { link = 'DiagnosticWarn' },
  VVI18nPanelFooter  = { link = 'Comment' },
  VVI18nPanelEmpty   = { link = 'Comment' },
})

-- 该键完整度徽标：组内每语言一个 ✓/·
local function badge(group, key)
  local cells = {}
  for _, l in ipairs(group.langs) do
    cells[#cells + 1] = { (key.per[l] and '✓' or '·'), key.per[l] and 'VVI18nPanelOk' or 'VVI18nPanelMiss' }
  end
  return cells
end

local function visible_keys(group)
  if not state.only_missing then return group.keys end
  local out = {}
  for _, k in ipairs(group.keys) do if #k.missing > 0 then out[#out + 1] = k end end
  return out
end

local function render()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  line_map = {}
  local lines, marks = {}, {}
  local function mark(row, col, ecol, group)
    marks[#marks + 1] = { row, col, { end_col = ecol, hl_group = group } }
  end

  local tree = state.tree or {}
  local total, missing_total = 0, 0
  for _, g in ipairs(tree) do
    total = total + #g.keys
    for _, k in ipairs(g.keys) do if #k.missing > 0 then missing_total = missing_total + 1 end end
  end

  local title = '  󰗊  i18n keys'
  lines[#lines + 1] = title
  mark(0, 0, #title, 'VVI18nPanelTitle')
  local meta = string.format('  %d keys · %d groups · %d missing%s',
    total, #tree, missing_total, state.only_missing and ' · [missing]' or '')
  marks[#marks + 1] = { 0, #title, { virt_text = { { meta, 'VVI18nPanelCount' } }, virt_text_pos = 'eol' } }

  local sep = string.rep('─', 40)
  lines[#lines + 1] = sep
  mark(1, 0, #sep, 'VVI18nPanelSep')

  if total == 0 then
    lines[#lines + 1] = ''
    local s = '  (无键，:VVI18nReload 重建索引)'
    lines[#lines + 1] = s
    mark(#lines - 1, 0, #s, 'VVI18nPanelEmpty')
  else
    for gidx, g in ipairs(tree) do
      local vis = visible_keys(g)
      if not (state.only_missing and #vis == 0) then
        lines[#lines + 1] = ''
        local chev = g.open == false and CHEV_CLOSED or CHEV_OPEN
        local head = string.format('%s %s', chev, g.mount)
        lines[#lines + 1] = head
        local hi = #lines - 1
        line_map[#lines] = { kind = 'group', group_idx = gidx }
        mark(hi, 0, #chev, 'VVI18nPanelChevron')
        mark(hi, #chev + 1, #head, 'VVI18nPanelGroup')
        marks[#marks + 1] = { hi, #head, { virt_text = {
          { string.format('  (%d)', #vis), 'VVI18nPanelCount' },
        }, virt_text_pos = 'eol' } }

        if g.open ~= false then
          local plang = state.plugin.preferred_lang(g.langs)
          for _, k in ipairs(vis) do
            local pe = k.per[plang]
            local val = pe and (pe.kind == 'string' and pe.value or ('<' .. pe.kind .. '>')) or ''
            local rel = truncate(k.rel, 28)
            local line = string.format('   %-28s %s', rel, truncate(val, 30))
            lines[#lines + 1] = line
            local li = #lines - 1
            line_map[#lines] = { kind = 'key', group_idx = gidx, key = k }
            mark(li, 3, 3 + #rel, 'VVI18nPanelKey')
            -- 徽标走行尾虚拟文本
            local vt = { { '  ', 'Normal' } }
            for _, c in ipairs(badge(g, k)) do vt[#vt + 1] = c end
            if #k.missing > 0 then
              vt[#vt + 1] = { '  缺 ' .. table.concat(k.missing, ','), 'VVI18nPanelMiss' }
            end
            marks[#marks + 1] = { li, #line, { virt_text = vt, virt_text_pos = 'eol' } }
          end
        end
      end
    end
  end

  lines[#lines + 1] = ''
  local footer = '  j/k 移动 · <CR> 编辑/折叠 · m 仅缺失 · r 重载 · q 关闭'
  lines[#lines + 1] = footer
  mark(#lines - 1, 0, #footer, 'VVI18nPanelFooter')

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, m[1], m[2], m[3])
  end
end

local function rebuild()
  state.tree = state.plugin and state.plugin.tree() or {}
  render()
end

local function selectable_lines()
  local ls = {}
  for lnum in pairs(line_map) do ls[#ls + 1] = lnum end
  table.sort(ls)
  return ls
end

local function navigate(dir)
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then return end
  local ls = selectable_lines()
  if #ls == 0 then return end
  local cur = vim.api.nvim_win_get_cursor(state.win)[1]
  local dst
  if dir == 'j' then
    for _, l in ipairs(ls) do if l > cur then dst = l; break end end
    dst = dst or ls[1]
  else
    for i = #ls, 1, -1 do if ls[i] < cur then dst = ls[i]; break end end
    dst = dst or ls[#ls]
  end
  vim.api.nvim_win_set_cursor(state.win, { dst, 0 })
end

local function on_enter()
  local info = line_map[vim.fn.line('.')]
  if not info then return end
  if info.kind == 'group' then
    local g = state.tree[info.group_idx]
    g.open = (g.open == false)
    render()
  elseif info.kind == 'key' then
    require('vv-i18n.editor').open(state.plugin, info.key.full, {
      on_saved = function()
        state.plugin.reload()
        rebuild()
      end,
    })
  end
end

local function toggle_missing()
  state.only_missing = not state.only_missing
  render()
end

local function create_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].filetype = 'vv-i18n-panel'
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false

  local map = function(lhs, fn, action)
    vim.keymap.set('n', lhs, fn, { buffer = buf, silent = true, nowait = true, desc = 'vv-i18n: ' .. action })
  end
  map('<CR>', on_enter, 'edit / toggle group')
  map('j', function() navigate('j') end, 'next')
  map('k', function() navigate('k') end, 'prev')
  map('<Down>', function() navigate('j') end, 'next')
  map('<Up>', function() navigate('k') end, 'prev')
  map('m', toggle_missing, 'only missing')
  map('r', function() state.plugin.reload(); rebuild() end, 'reload')
  map('q', function() M.close() end, 'close')
  map('<Esc>', function() M.close() end, 'close')

  -- 鼠标：左键松开 = 进入；屏蔽默认 visual 选区（拖拽 / 多击 / 右键，含跨窗兜底）
  map('<LeftRelease>', on_enter, 'click')
  pcall(require('vv-utils.mouse').guard_panel, buf)

  return buf
end

local function cleanup()
  line_map = {}
  state.buf = nil
  state.win = nil
  state.tree = nil
end

function M.open(plugin)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end
  state.plugin = plugin
  state.prev_win = vim.api.nvim_get_current_win()
  state.buf = create_buf()

  vim.cmd('botright 56vsplit')
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)
  require('vv-utils.ui_window').hide_chrome(state.win, { cursorline = true, winfixwidth = true })
  vim.wo[state.win].winhighlight = 'Normal:NormalFloat,CursorLine:PmenuSel,EndOfBuffer:NonText'
  vim.wo[state.win].statusline = ' '

  vim.api.nvim_create_autocmd('BufWipeout', { buffer = state.buf, once = true, callback = cleanup })

  rebuild()
  -- 光标落到首个键行
  local ls = selectable_lines()
  for _, l in ipairs(ls) do
    if (line_map[l] or {}).kind == 'key' then
      pcall(vim.api.nvim_win_set_cursor, state.win, { l, 0 }); break
    end
  end
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  else
    cleanup()
  end
end

function M.toggle(plugin)
  if state.win and vim.api.nvim_win_is_valid(state.win) then M.close() else M.open(plugin) end
end

return M

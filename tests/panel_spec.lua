-- vv-i18n editor(plan/diff/apply) + panel 渲染（ns-app fixture）
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')   -- 自定位 rtp

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local i18n = require('vv-i18n')
local editor = require('vv-i18n.editor')
local panel = require('vv-i18n.panel')
local State = require('vv-utils.state')

local check, done = H.checker()
local panel_state_path = vim.fn.tempname()
local panel_state = State.register('vv-i18n-test', 'keys-panel', {
  path = panel_state_path,
})

local HERO_ZH = H.fixture('ns-app/src/components/Hero/locales/zh-CN.ts')
local orig = H.read(HERO_ZH)

local config = H.ns_config()
config.panel = { state = panel_state }
i18n.setup(config)
i18n.reload()

-- editor.plan：已存在键 → 各语言行（en-US < zh-CN 字典序）
local rows, lines = editor.plan(i18n, 'app.hero.title')
check('plan 2 行(en-US/zh-CN)', rows and #rows == 2, rows and #rows)
if rows then
  check('plan 行1=en-US 有值', rows[1].lang == 'en-US' and lines[1] ~= '')
  check('plan 行2=zh-CN 值=英雄', rows[2].lang == 'zh-CN' and lines[2] == '英雄', lines[2])
end

-- 复数对象与标量同 key：不走 add，展开形态后逐项 update
local prows, plines = editor.plan(i18n, 'app.hero.items')
check('plan 复数对象展开为 3 行', prows and #prows == 3, prows and #prows)
if prows then
  check('plan 含 en-US.one', prows[1].label == 'en-US.one' and plines[1] == '{{count}} item')
  check('plan 含 en-US.other', prows[2].label == 'en-US.other' and plines[2] == '{{count}} items')
  check('plan 含 zh-CN 标量', prows[3].lang == 'zh-CN' and plines[3] == '共 {{count}} 项')

  local writes = editor.diff(prows, { '{{count}} item!', plines[2], plines[3] })
  check('复数形态编辑走 update', #writes == 1 and writes[1].action == 'update'
    and table.concat(writes[1].in_file_path, '.') == 'hero.items.one')
  local changed, fails = editor.apply(writes, { dry_run = true })
  check('复数形态 dry-run 可写回', changed == 1 and #fails == 0, table.concat(fails, ','))
end

-- editor.diff：改 zh-CN → 1 处 update
if rows then
  local writes = editor.diff(rows, { lines[1], '英雄★' })
  check('diff 1 处 update 命中 zh-CN 文件', #writes == 1 and writes[1].file == HERO_ZH)
  local changed, fails = editor.apply(writes, { dry_run = true })
  check('apply dry-run changed=1', changed == 1 and #fails == 0, table.concat(fails, ','))
end

-- 全新键 → 各语言 add
local nrows = editor.plan(i18n, 'app.hero.brandNew')
check('plan 新键 orig=nil', nrows and nrows[1].orig == nil)
if nrows then
  local writes = editor.diff(nrows, { 'NewEN', '新中' })
  check('diff 新键 2 处 add', #writes == 2 and writes[1].action == 'add')
  local changed, fails = editor.apply(writes, { dry_run = true })
  check('apply dry-run 新键 changed=2', changed == 2 and #fails == 0)
end

check('真实 fixture 未被改动（全程 dry-run）', H.read(HERO_ZH) == orig)

-- panel：真开窗读 buffer
local source_win = vim.api.nvim_get_current_win()
panel.open(i18n)
local pbuf = vim.api.nvim_get_current_buf()
local function panel_lines()
  return vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)
end

local function joined_panel()
  return table.concat(panel_lines(), '\n')
end

local function find_line(needle)
  for i, line in ipairs(panel_lines()) do
    if line:find(needle, 1, true) then return i end
  end
end

local function run_map(lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(pbuf, 'n')) do
    if m.lhs == lhs and m.callback then
      m.callback()
      return true
    end
  end
  return false
end

local function find_map(buf, mode, lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhs == lhs then return m end
  end
end

local joined = joined_panel()
check('keys panel 复用 vv-utils tree-panel',
  vim.api.nvim_buf_get_name(pbuf) == 'vv-tree-panel://vv-i18n-keys',
  vim.api.nvim_buf_get_name(pbuf))
check('panel 含 hero 组', joined:find('hero', 1, true) ~= nil)
check('panel 含 title 键', joined:find('title', 1, true) ~= nil)
check('panel 含译文(Hero/英雄)', joined:find('Hero', 1, true) ~= nil or joined:find('英雄', 1, true) ~= nil)
check('panel 标题含 i18n keys', joined:find('i18n keys', 1, true) ~= nil)
check('panel 顶部包含真实语言选择器',
  joined:find('Languages', 1, true) ~= nil
    and joined:find('● en-US', 1, true) ~= nil
    and joined:find('[LANGUAGES', 1, true) == nil)
local panel_winbar = vim.wo[0].winbar
check('快捷键提示固定在顶部 winbar',
  panel_winbar:find('h/l Fold', 1, true) ~= nil
    and joined:find('h/l Fold', 1, true) == nil)
check('panel 默认包含 C-n/C-p 导航',
  find_map(pbuf, 'n', '<C-N>') ~= nil and find_map(pbuf, 'n', '<C-P>') ~= nil)
check('业务映射通过通用 mapping spec 提供帮助描述',
  find_map(pbuf, 'n', 'm').desc == 'vv-tree-panel: only_missing'
    and find_map(pbuf, 'n', 'g').desc == 'vv-tree-panel: group_by_missing_lang')

local zh_lnum = find_line('zh-CN')
check('panel 找到 zh-CN 语言节点', zh_lnum ~= nil)
if zh_lnum then
  vim.api.nvim_win_set_cursor(0, { zh_lnum, 0 })
  check('语言节点 Enter 映射存在', run_map('<CR>'))
  check('Enter 切换语言后 panel 保持打开',
    vim.api.nvim_get_current_buf() == pbuf)
  check('语言选择状态切换到 zh-CN',
    joined_panel():find('● zh-CN', 1, true) ~= nil)
  local switched_title = find_line('title')
  check('key 预览跟随切换为 zh-CN',
    switched_title
      and panel_lines()[switched_title]:find('英雄', 1, true) ~= nil,
    switched_title and panel_lines()[switched_title])
end

vim.cmd('vertical resize 48')
vim.api.nvim_exec_autocmds('WinResized', {})
check('keys panel 宽度写入通用状态仓库', vim.wait(500, function()
  return panel_state:get('width') == 48
end), panel_state:get('width'))

local title_lnum = find_line('title')
check('panel 找到 title 行', title_lnum ~= nil)
if title_lnum then
  vim.api.nvim_win_set_cursor(0, { title_lnum, 0 })
  check('panel h 映射存在', run_map('h'))
  local closed = joined_panel()
  local fold_closed = require('vv-icons').raw.ui.fold_closed.glyph
  check('panel h 可从 key 行收起父组', closed:find('title', 1, true) == nil)
  check('panel 折叠图标同 vv-explorer', closed:find(fold_closed, 1, true) ~= nil)

  local hero_lnum = find_line('hero')
  check('panel 找到 hero 组行', hero_lnum ~= nil)
  if hero_lnum then
    vim.api.nvim_win_set_cursor(0, { hero_lnum, 0 })
    check('panel l 映射存在', run_map('l'))
    check('panel l 可展开组', joined_panel():find('title', 1, true) ~= nil)
  end
end

vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(pbuf), 0 })
vim.cmd('normal! zt')
check('滚动 keys 后固定快捷键提示仍存在', vim.wo[0].winbar == panel_winbar)

check('panel g? 映射存在', run_map('g?'))
local help_buf = vim.api.nvim_get_current_buf()
local help_text = table.concat(vim.api.nvim_buf_get_lines(help_buf, 0, -1, false), '\n')
check('panel g? 打开帮助面板', vim.bo[help_buf].filetype == 'vv-i18n-help')
check('help 含 group by missing lang', help_text:find('group by missing lang', 1, true) ~= nil)
pcall(vim.api.nvim_win_close, 0, true)

panel.open(i18n, { only_missing = true, group_by = 'missing_lang' })
local missing = joined_panel()
check('panel 缺失组含 ja-JP', missing:find('ja-JP', 1, true) ~= nil)
check('panel 缺失组含 common.cancel', missing:find('common.cancel', 1, true) ~= nil)
check('missing panel 光标落在缺失 key', (vim.api.nvim_get_current_line() or ''):find('common.cancel', 1, true) ~= nil)
local missing_lnum = find_line('common.cancel')
check('missing panel 找到 common.cancel 行', missing_lnum ~= nil)
if missing_lnum then
  vim.api.nvim_win_set_cursor(0, { missing_lnum, 0 })
  check('missing panel e 打开编辑器', run_map('e'))
  local edit_buf = vim.api.nvim_get_current_buf()
  local edit_win = vim.api.nvim_get_current_win()
  local edit_lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
  local rows = editor.plan(i18n, 'app.common.cancel')
  local ja_lnum
  local lang_width = 0
  for i, row in ipairs(rows or {}) do
    local name = row.label or row.lang
    lang_width = math.max(lang_width, vim.fn.strdisplaywidth(name))
    if row.lang == 'ja-JP' then
      ja_lnum = i
    end
  end
  local value_col = lang_width + 3

  check('缺失编辑器已打开', vim.bo[edit_buf].filetype == 'vv-i18n-editor')
  check('所有语言共用单窗口单光标', rows and #edit_lines == #rows and vim.api.nvim_get_current_win() == edit_win)
  check('输入区没有 cursorline 背景', not vim.wo[edit_win].cursorline
    and not vim.wo[edit_win].winhighlight:find('CursorLine', 1, true))
  check('编辑器聚焦 ja-JP 缺失输入框', ja_lnum and vim.api.nvim_win_get_cursor(0)[1] == ja_lnum)

  local footer = vim.api.nvim_win_get_config(edit_win).footer or {}
  local footer_text = ''
  for _, chunk in ipairs(footer) do footer_text = footer_text .. (chunk[1] or '') end
  check('footer 使用快捷键符号', footer_text:find('Jump ↵', 1, true) ~= nil
    and footer_text:find('Save ^s', 1, true) ~= nil
    and footer_text:find('<CR>', 1, true) == nil)

  local editor_ns = vim.api.nvim_get_namespaces().vv_i18n_editor
  local marks = vim.api.nvim_buf_get_extmarks(edit_buf, editor_ns, { ja_lnum - 1, 0 }, { ja_lnum - 1, -1 }, { details = true })
  local label = marks[1] and marks[1][4].virt_text and marks[1][4].virt_text[1][1] or ''
  check('语言标签使用 overlay 虚拟文本', label:find('ja-JP', 1, true) ~= nil
    and edit_lines[ja_lnum]:find('ja-JP', 1, true) == nil)

  vim.api.nvim_win_set_cursor(0, { ja_lnum, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = edit_buf })
  check('光标不会落在语言标签上', vim.api.nvim_win_get_cursor(0)[2] > lang_width)

  check('编辑器 normal <C-S> 映射存在', find_map(edit_buf, 'n', '<C-S>') ~= nil)
  check('编辑器 insert <C-S> 映射存在', find_map(edit_buf, 'i', '<C-S>') ~= nil)
  check('编辑器 <CR> 跳转映射存在', find_map(edit_buf, 'n', '<CR>') ~= nil)
  check('编辑器 insert <CR> 跳转映射存在', find_map(edit_buf, 'i', '<CR>') ~= nil)

  vim.api.nvim_buf_set_lines(edit_buf, ja_lnum - 1, ja_lnum, false, {
    string.rep(' ', value_col) .. 'draft',
  })
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = edit_buf })
  local jump_map = find_map(edit_buf, 'n', '<CR>')
  if jump_map and jump_map.callback then jump_map.callback() end
  check('未保存修改会阻止跳转', vim.api.nvim_win_is_valid(edit_win)
    and vim.api.nvim_get_current_buf() == edit_buf)

  local close_map = find_map(edit_buf, 'n', 'q')
  local confirm = vim.fn.confirm
  vim.fn.confirm = function() return 2 end
  if close_map and close_map.callback then close_map.callback() end
  vim.fn.confirm = confirm
  check('关闭确认选择 No 时保留编辑器', vim.api.nvim_win_is_valid(edit_win)
    and vim.api.nvim_get_current_buf() == edit_buf)

  vim.api.nvim_feedkeys(vim.keycode('dd'), 'mx', false)
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = edit_buf })
  local cleared = vim.api.nvim_buf_get_lines(edit_buf, ja_lnum - 1, ja_lnum, false)[1] or ''
  check('真实 dd 只清空当前输入框', vim.api.nvim_buf_line_count(edit_buf) == #rows
    and cleared == string.rep(' ', value_col))
  check('dd 后光标仍在值区域起点', vim.api.nvim_win_get_cursor(edit_win)[2] == value_col)

  local backspace_map = find_map(edit_buf, 'i', '<BS>')
  local boundary_result = backspace_map and backspace_map.callback and backspace_map.callback()
  check('Backspace 到边界后直接吞键', boundary_result == '', vim.inspect(boundary_result))

  vim.api.nvim_buf_set_lines(edit_buf, ja_lnum - 1, ja_lnum, false, {
    string.rep(' ', value_col) .. 'a',
  })
  vim.api.nvim_win_set_cursor(edit_win, { ja_lnum, value_col + 1 })
  local content_result = backspace_map and backspace_map.callback and backspace_map.callback()
  check('Backspace 在内容区返回真实删除键', content_result ~= '' and content_result ~= '<Nop>',
    vim.inspect(content_result))
  vim.api.nvim_buf_set_lines(edit_buf, ja_lnum - 1, ja_lnum, false, {
    string.rep(' ', value_col),
  })
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = edit_buf })

  vim.api.nvim_win_set_cursor(edit_win, { ja_lnum, value_col })
  vim.api.nvim_feedkeys('X', 'nx', false)
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = edit_buf })
  local after_x = vim.api.nvim_buf_get_lines(edit_buf, ja_lnum - 1, ja_lnum, false)[1] or ''
  check('X 不会破坏标签占位列', after_x == string.rep(' ', value_col), vim.inspect(after_x))

  local stable_lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
  vim.api.nvim_buf_set_lines(edit_buf, ja_lnum - 1, ja_lnum, false, {})
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = edit_buf })
  check('结构性删行会恢复输入框', vim.deep_equal(
    vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false),
    stable_lines
  ))

  local save_map = find_map(edit_buf, 'n', '<C-S>')
  if save_map and save_map.callback then save_map.callback() end
  check('编辑器保存后窗口保持打开', vim.api.nvim_get_current_buf() == edit_buf)

  local jump_lnum, jump_entry
  local per = i18n.lookup('app.common.cancel')
  for i, row in ipairs(rows or {}) do
    if per and per[row.lang] then
      jump_lnum = i
      jump_entry = per[row.lang]
      break
    end
  end
  vim.api.nvim_win_set_cursor(edit_win, { jump_lnum, value_col })
  vim.api.nvim_feedkeys('i' .. vim.keycode('<CR>'), 'mx', false)
  check('编辑器 <CR> 关闭浮窗并打开 locale 文件', jump_entry
    and not vim.api.nvim_win_is_valid(edit_win)
    and vim.api.nvim_buf_get_name(0) == jump_entry.file)
  check('编辑器跳转后 keys panel 自动关闭', #vim.fn.win_findbuf(pbuf) == 0)
  check('编辑器跳回 panel 打开前的来源窗口', vim.api.nvim_get_current_win() == source_win)
  check('编辑器 <CR> 定位当前语言 key', jump_entry
    and vim.api.nvim_win_get_cursor(0)[1] == (jump_entry.row or 0) + 1)

  editor.open(i18n, 'app.common.cancel', {
    focus_lang = 'ja-JP',
    target_win = source_win,
  })
  local discard_buf = vim.api.nvim_get_current_buf()
  local discard_win = vim.api.nvim_get_current_win()
  local discard_rows = editor.plan(i18n, 'app.common.cancel')
  local discard_lnum
  for i, row in ipairs(discard_rows or {}) do
    if row.lang == 'ja-JP' then discard_lnum = i; break end
  end
  vim.api.nvim_buf_set_lines(discard_buf, discard_lnum - 1, discard_lnum, false, {
    string.rep(' ', value_col) .. 'discard me',
  })
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = discard_buf })
  local discard_map = find_map(discard_buf, 'n', 'q')
  confirm = vim.fn.confirm
  vim.fn.confirm = function() return 1 end
  if discard_map and discard_map.callback then discard_map.callback() end
  vim.fn.confirm = confirm
  check('关闭确认选择 Yes 时丢弃修改并关闭', not vim.api.nvim_win_is_valid(discard_win))
end
panel.close()
panel.open(i18n)
check('keys panel 重新打开恢复宽度', vim.api.nvim_win_get_width(0) == 48,
  vim.api.nvim_win_get_width(0))
panel.close()
vim.fn.delete(panel_state_path)

done()
vim.cmd('qa!')

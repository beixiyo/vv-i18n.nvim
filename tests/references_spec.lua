-- 引用索引、定义处计数与 Trouble 风格引用侧栏

dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local i18n = require('vv-i18n')
local References = require('vv-i18n.references.index')
local ReferenceDisplay = require('vv-i18n.references.display')
local State = require('vv-utils.state')

local check, done = H.checker()
local state_path = vim.fn.tempname()
local references_state = State.register('vv-i18n-test', 'references', {
  path = state_path,
})

local config = H.ns_config()
config.references = {
  panel = {
    state = references_state,
    mappings = {
      za = 'toggle_node',
      zR = 'expand_all',
      x = 'close_panel',
    },
  },
}
i18n.setup(config)
i18n.setup(config)
local display_autocmds = vim.api.nvim_get_autocmds({ group = 'VVI18nReferencesDisplay' })
check('重配不叠加 references display autocmd', #display_autocmds == 2, #display_autocmds)

local disabled_config = vim.deepcopy(config)
disabled_config.references.enable = false
i18n.setup(disabled_config)
local has_index_listener = pcall(vim.api.nvim_get_autocmds, { group = 'VVI18nReferencesIndex' })
check('references=false 不注册 index listener 且 display 已释放', not has_index_listener
  and not ReferenceDisplay.is_enabled())

i18n.setup(config)
i18n.reload()

check('命令 VVI18nReferences 注册', vim.fn.exists(':VVI18nReferences') == 2)
check('引用扫描完成', vim.wait(3000, function() return not References.is_scanning() end))

local refs = References.get('app.hero.title')
check('hero.title 有 2 个精确引用', #refs == 2, #refs)
local home_ref
for _, ref in ipairs(refs) do
  if ref.relative == 'src/pages/Home.tsx' then home_ref = ref break end
end
check('引用位置包含 Home.tsx', home_ref ~= nil)
check('引用行保留源码摘要', home_ref and home_ref.line:find("t('hero.title')", 1, true) ~= nil)

local locale = H.fixture('ns-app/src/components/Hero/locales/en-US.ts')
local locale_buf = vim.fn.bufadd(locale)
vim.fn.bufload(locale_buf)
vim.api.nvim_set_current_buf(locale_buf)
ReferenceDisplay.refresh()

local marks = vim.api.nvim_buf_get_extmarks(
  locale_buf,
  vim.api.nvim_create_namespace('vv-i18n-references'),
  0,
  -1,
  { details = true }
)
local count_text
local zero_text
for _, mark in ipairs(marks) do
  local chunks = mark[4].virt_text or {}
  for _, chunk in ipairs(chunks) do
    if chunk[1]:find('2 references', 1, true) then count_text = chunk[1] end
    if chunk[1]:find('0 references', 1, true) then zero_text = chunk[1] end
  end
end
check('定义处显示引用数虚拟文本', count_text ~= nil, count_text)
check('默认不显示零引用虚拟文本', zero_text == nil, zero_text)

local source_buf = vim.fn.bufadd(H.fixture('ns-app/src/pages/Home.tsx'))
vim.fn.bufload(source_buf)
vim.bo[source_buf].filetype = 'typescriptreact'
vim.api.nvim_set_current_buf(source_buf)
local source_win = vim.api.nvim_get_current_win()
local function move_to_key(key)
  vim.api.nvim_set_current_win(source_win)
  for line, text in ipairs(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)) do
    local col = text:find(key, 1, true)
    if col then
      vim.api.nvim_win_set_cursor(source_win, { line, col - 1 })
      return
    end
  end
end
move_to_key('hero.title')

local failing_config = vim.deepcopy(config)
failing_config.references.panel.on_attach = function() error('attach failed') end
i18n.setup(failing_config)
local windows_before_failed_open = #vim.api.nvim_list_wins()
local failed_open = pcall(vim.cmd, 'VVI18nReferences')
check('引用侧栏 attach 异常会回滚窗口', not failed_open
  and #vim.api.nvim_list_wins() == windows_before_failed_open)
i18n.setup(config)

local snapshot = i18n.get_config()
snapshot.references.panel.on_attach = function() error('must not leak') end
check('配置快照外部修改不污染运行时', pcall(vim.cmd, 'VVI18nReferences'))
require('vv-i18n.references.panel').close()

local panel_config = i18n.get_config().references.panel

vim.cmd('VVI18nReferences')
local panel_buf = vim.api.nvim_get_current_buf()
local panel_text = table.concat(vim.api.nvim_buf_get_lines(panel_buf, 0, -1, false), '\n')
check('引用侧栏使用独立 filetype', vim.bo[panel_buf].filetype == 'vv-i18n-references')
check('引用侧栏按文件分组', panel_text:find('src/pages/Home.tsx', 1, true) ~= nil)
check('引用侧栏折叠过长路径',
  panel_text:find('src/…/marketing/pages/HomeTitle.tsx', 1, true) ~= nil)
check('引用侧栏含引用源码', panel_text:find("t('hero.title')", 1, true) ~= nil)

move_to_key('hero.cta')
vim.cmd('VVI18nReferences')
local switched_buf = vim.api.nvim_get_current_buf()
local switched_text = table.concat(vim.api.nvim_buf_get_lines(switched_buf, 0, -1, false), '\n')
check('命令可将已打开的引用侧栏切换到另一 key',
  vim.bo[switched_buf].filetype == 'vv-i18n-references'
    and switched_text:find('app.hero.cta', 1, true) ~= nil)

move_to_key('hero.title')
vim.cmd('VVI18nReferences')
panel_buf = vim.api.nvim_get_current_buf()
panel_text = table.concat(vim.api.nvim_buf_get_lines(panel_buf, 0, -1, false), '\n')

local syntax_marks = vim.api.nvim_buf_get_extmarks(
  panel_buf,
  vim.api.nvim_create_namespace('vv-utils-tree-panel-vv-i18n-references'),
  0,
  -1,
  { details = true }
)
local has_syntax_highlight = false
for _, mark in ipairs(syntax_marks) do
  local group = mark[4].hl_group
  if type(group) == 'string' and group:sub(1, 1) == '@' then
    has_syntax_highlight = true
    break
  end
end
check('引用源码使用 Tree-sitter 语法高亮', has_syntax_highlight)
check('引用侧栏支持折叠', vim.fn.maparg('za', 'n', false, true).buffer == 1)
check('引用侧栏支持展开全部', vim.fn.maparg('zR', 'n', false, true).buffer == 1)
check('引用侧栏接受外部快捷键配置', vim.fn.maparg('q', 'n', false, true).buffer ~= 1
  and vim.fn.maparg('x', 'n', false, true).buffer == 1)

local initial_width = vim.api.nvim_win_get_width(0)
local resized_width = initial_width + 3
check('引用侧栏不接管用户 resize 快捷键',
  vim.fn.maparg('<C-A-Left>', 'n', false, true).buffer ~= 1
    and vim.fn.maparg('<C-A-Right>', 'n', false, true).buffer ~= 1)
vim.cmd('vertical resize +3')
check('引用侧栏接受外部 resize', vim.api.nvim_win_get_width(0) == resized_width,
  vim.api.nvim_win_get_width(0))
vim.api.nvim_exec_autocmds('WinResized', {})
check('显式 WinResized 事件防抖写入共享状态', vim.wait(500, function()
  return references_state:get('width') == resized_width
end), references_state:get('width'))

vim.fn.maparg('x', 'n', false, true).callback()
check('外部映射可调用内置 action', vim.bo.filetype ~= 'vv-i18n-references',
  vim.bo.filetype)

for line, text in ipairs(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)) do
  local col = text:find('hero.cta', 1, true)
  if col then
    vim.api.nvim_win_set_cursor(0, { line, col - 1 })
    break
  end
end
local default_mapping_config = vim.deepcopy(config)
default_mapping_config.references.panel.mappings = nil
i18n.setup(default_mapping_config)
vim.cmd('VVI18nReferences')
check('不同 key 共用引用侧栏宽度状态', vim.api.nvim_win_get_width(0) == resized_width,
  vim.api.nvim_win_get_width(0))
panel_buf = vim.api.nvim_get_current_buf()
local panel_win = vim.api.nvim_get_current_win()
check('默认映射包含 jk/C-n/p、hl、Enter、gf 与 g?',
  vim.fn.maparg('j', 'n', false, true).buffer == 1
    and vim.fn.maparg('k', 'n', false, true).buffer == 1
    and vim.fn.maparg('<C-N>', 'n', false, true).buffer == 1
    and vim.fn.maparg('<C-P>', 'n', false, true).buffer == 1
    and vim.fn.maparg('h', 'n', false, true).buffer == 1
    and vim.fn.maparg('l', 'n', false, true).buffer == 1
    and vim.fn.maparg('<CR>', 'n', false, true).buffer == 1
    and vim.fn.maparg('gf', 'n', false, true).buffer == 1
    and vim.fn.maparg('g?', 'n', false, true).buffer == 1)

vim.api.nvim_win_set_cursor(panel_win, { 2, 0 })
vim.fn.maparg('h', 'n', false, true).callback()
check('h 收起节点后光标保持原节点', vim.api.nvim_win_get_cursor(panel_win)[1] == 2,
  vim.api.nvim_win_get_cursor(panel_win)[1])
vim.fn.maparg('l', 'n', false, true).callback()
check('l 展开节点后光标保持原节点', vim.api.nvim_win_get_cursor(panel_win)[1] == 2,
  vim.api.nvim_win_get_cursor(panel_win)[1])
vim.fn.maparg('<C-N>', 'n', false, true).callback()
check('C-n 移动到下一节点', vim.api.nvim_win_get_cursor(panel_win)[1] == 3,
  vim.api.nvim_win_get_cursor(panel_win)[1])
vim.fn.maparg('<C-P>', 'n', false, true).callback()
check('C-p 移动到上一节点', vim.api.nvim_win_get_cursor(panel_win)[1] == 2,
  vim.api.nvim_win_get_cursor(panel_win)[1])
vim.fn.maparg('j', 'n', false, true).callback()
check('j 移动到下一节点', vim.api.nvim_win_get_cursor(panel_win)[1] == 3,
  vim.api.nvim_win_get_cursor(panel_win)[1])
vim.fn.maparg('h', 'n', false, true).callback()
check('引用叶节点按一次 h 直接折叠文件节点',
  vim.api.nvim_win_get_cursor(panel_win)[1] == 2
    and vim.api.nvim_buf_line_count(panel_buf) == 2,
  vim.api.nvim_win_get_cursor(panel_win)[1])
vim.fn.maparg('l', 'n', false, true).callback()
vim.fn.maparg('j', 'n', false, true).callback()

vim.fn.maparg('<CR>', 'n', false, true).callback()
check('Enter 进入引用但保留 panel', #vim.fn.win_findbuf(panel_buf) == 1)
check('Enter 进入引用不会改变 panel 宽度',
  vim.api.nvim_win_get_width(panel_win) == resized_width,
  vim.api.nvim_win_get_width(panel_win))
vim.api.nvim_set_current_win(panel_win)
vim.fn.maparg('gf', 'n', false, true).callback()
check('gf 进入引用并关闭 panel', #vim.fn.win_findbuf(panel_buf) == 0)

local direct_config = vim.deepcopy(default_mapping_config)
direct_config.references.jump_single = true
direct_config.references.show_zero = true
i18n.setup(direct_config)
i18n.reload()
check('重配后引用扫描完成', vim.wait(3000, function() return not References.is_scanning() end))

vim.api.nvim_set_current_buf(locale_buf)
ReferenceDisplay.refresh()
local zero_visible
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(
  locale_buf,
  vim.api.nvim_create_namespace('vv-i18n-references'),
  0,
  -1,
  { details = true }
)) do
  for _, chunk in ipairs(mark[4].virt_text or {}) do
    if chunk[1]:find('0 references', 1, true) then zero_visible = true end
  end
end
check('show_zero=true 显示零引用虚拟文本', zero_visible == true)

for line, text in ipairs(vim.api.nvim_buf_get_lines(locale_buf, 0, -1, false)) do
  local col = text:find('cta', 1, true)
  if col then
    vim.api.nvim_win_set_cursor(0, { line, col - 1 })
    break
  end
end
vim.cmd('VVI18nReferences')
check('jump_single=true 时单个引用直接跳转且不打开侧栏',
  vim.api.nvim_buf_get_name(0) == H.fixture('ns-app/src/pages/Home.tsx')
    and vim.api.nvim_win_get_cursor(0)[1] == 8
    and vim.bo.filetype ~= 'vv-i18n-references')

local persisted = references_state:get('width')
check('引用侧栏宽度已持久化到共享状态仓库', persisted == resized_width, persisted)
vim.fn.delete(state_path)

done()
vim.cmd('qa!')

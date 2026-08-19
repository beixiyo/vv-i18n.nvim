-- unused action：选择和复制必须从真实分析报告流向真实渲染器与剪贴板边界
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local Actions = require('vv-i18n.unused.actions')
local Editor = require('vv-utils.editor')
local Confirm = require('vv-utils.confirm')
local References = require('vv-i18n.references.index')
local check, done = H.checker()

local original_snapshot = References.snapshot
local original_refresh = References.refresh
local original_copy = Editor.copy
local original_confirm_open = Confirm.open
local copied
References.snapshot = function()
  return {
    by_key = { ['common.old'] = {} }, dynamic_evidence = {}, scanning = false,
    generation = 4, scan = { status = 'complete', root = '/project' },
  }
end
Editor.copy = function(content) copied = content; return true end

local plugin = {
  get_state = function() return { root = '/project', errors = {} } end,
  get_config = function() return { unused = { copy = { definition_language = 'en', include_values = false } } } end,
  tree = function() return { { mount = 'common', keys = {
    { full = 'common.old', rel = 'old', per = { en = { file = '/project/en.json', kind = 'string', value = 'Old' } } },
  } } } end,
}
local actions = Actions.new(plugin)
local report = actions:rebuild()
local refreshes = 0
local panel = { refresh = function() refreshes = refreshes + 1 end }
local candidate = report.candidates[1]
actions:toggle(candidate, panel)
check('选择候选会刷新面板且写入选中状态', refreshes == 1 and actions.selected['common.old'] == true)
actions:copy(candidate, false)
check('复制选中候选会交付真实 Markdown', type(copied) == 'string'
  and copied:find('common.old', 1, true) ~= nil and copied:find('候选', 1, true) ~= nil)

-- 删除确认边界可替换，但两次刷新、计划与磁盘事务必须走真实生产实现
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local locale = root .. '/en.json'
vim.fn.writefile({ '{', '  "old": "Old",', '  "keep": "Keep"', '}' }, locale)
local delete_candidate = {
  full = 'common.old', rel = 'old', per = {
    en = { file = locale, in_file_path = { 'old' }, kind = 'string', value = 'Old' },
  },
}
References.snapshot = function()
  return {
    by_key = { ['common.old'] = {} }, dynamic_evidence = {}, scanning = false,
    generation = 5, scan = { status = 'complete', root = root, source_fingerprints = {} },
  }
end
References.refresh = function(_, callback) callback() end
local confirmation
Confirm.open = function(opts) confirmation = opts end
local reloads = 0
local delete_plugin = {
  get_state = function() return { root = root, errors = {} } end,
  get_config = plugin.get_config,
  tree = function() return { { mount = 'common', keys = { delete_candidate } } } end,
  reload = function() reloads = reloads + 1 end,
}
local delete_actions = Actions.new(delete_plugin)
delete_actions:rebuild()
local delete_panel = { is_open = function() return false end, refresh = function() error('closed panel must not refresh') end }
delete_actions:confirm_delete(delete_actions.report.candidates, delete_panel)
check('删除先展示确认而未写入', type(confirmation and confirmation.on_confirm) == 'function'
  and table.concat(vim.fn.readfile(locale), '\n'):find('"old"', 1, true) ~= nil)
confirmation.on_confirm()
check('确认后重扫并事务删除，再重建索引', vim.fn.readfile(locale)[2]:find('"old"', 1, true) == nil
  and reloads == 1)
vim.fn.delete(root, 'rf')

Editor.copy = original_copy
References.snapshot = original_snapshot
References.refresh = original_refresh
Confirm.open = original_confirm_open
done()
vim.cmd('qa!')

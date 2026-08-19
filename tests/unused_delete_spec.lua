-- unused 删除计划：验证多语言写回、过期扫描和磁盘快照门禁
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')

local H = dofile(debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$') .. '/helper.lua')
local Delete = require('vv-i18n.unused.delete')
local check, done = H.checker()

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local en = root .. '/en.json'
local zh = root .. '/zh.json'
vim.fn.writefile({ '{', '  "keep": "Keep",', '  "old": "Old"', '}' }, en)
vim.fn.writefile({ '{', '  "keep": "保留",', '  "old": "旧"', '}' }, zh)

local function read(path) return table.concat(vim.fn.readfile(path), '\n') .. '\n' end
local function candidate()
  return {
    full_key = 'old',
    status = 'candidate-unused',
    writable = true,
    per = {
      ['en-US'] = { file = en, in_file_path = { 'old' }, kind = 'string' },
      ['zh-CN'] = { file = zh, in_file_path = { 'old' }, kind = 'string' },
    },
  }
end

local plan = assert(Delete.build({ candidate() }, { generation = 3, root = root }))
check('删除计划包含全部语言文件但不提前写盘', #plan.entries == 2
  and read(en):find('"old"', 1, true) ~= nil
  and read(zh):find('"old"', 1, true) ~= nil)
check('删除计划提供 unified diff', plan.diff:find('-  "old"', 1, true) ~= nil)
check('删除计划按文件路径稳定排序', plan.entries[1].path == en and plan.entries[2].path == zh)

local stale_ok = Delete.apply(plan, { status = 'complete', generation = 4, root = root })
check('扫描代际变化时拒绝删除且文件不变', stale_ok == false
  and read(en):find('"old"', 1, true) ~= nil
  and read(zh):find('"old"', 1, true) ~= nil)

vim.fn.writefile({ '{', '  "keep": "外部改动",', '  "old": "旧"', '}' }, zh)
local changed_ok = Delete.apply(plan, { status = 'complete', generation = 3, root = root })
check('确认后文件变化时事务预检拒绝且不产生部分删除', changed_ok == false
  and read(en):find('"old"', 1, true) ~= nil
  and read(zh):find('"old"', 1, true) ~= nil)

vim.fn.writefile({ '{', '  "keep": "保留",', '  "old": "旧"', '}' }, zh)
local fresh_plan = assert(Delete.build({ candidate() }, { generation = 5, root = root }))
local applied = Delete.apply(fresh_plan, { status = 'complete', generation = 5, root = root })
check('完整快照下事务删除所有语言', applied == true
  and read(en):find('"old"', 1, true) == nil
  and read(zh):find('"old"', 1, true) == nil
  and read(en):find('"keep"', 1, true) ~= nil)

vim.fn.writefile({ '{', '  "keep": "Keep",', '  "old": "Old"', '}' }, en)
vim.fn.writefile({ '{', '  "keep": "保留",', '  "old": "旧"', '}' }, zh)
local source = root .. '/consumer.ts'
vim.fn.writefile({ "t('keep')" }, source)
local source_content = read(source)
local guarded_plan = assert(Delete.build({ candidate() }, {
  generation = 6,
  root = root,
  source_fingerprints = { [source] = vim.fn.sha256(source_content) },
}))
vim.fn.writefile({ "t('old')" }, source)
local source_changed_ok = Delete.apply(guarded_plan, {
  status = 'complete',
  generation = 6,
  root = root,
})
check('确认后引用源文件变化时拒绝删除', source_changed_ok == false
  and read(en):find('"old"', 1, true) ~= nil
  and read(zh):find('"old"', 1, true) ~= nil)

vim.fn.delete(root, 'rf')
done()
vim.cmd('qa!')

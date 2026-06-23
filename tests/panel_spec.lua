-- vv-i18n editor(plan/diff/apply) + panel 渲染（ns-app fixture）
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')   -- 自定位 rtp

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local i18n = require('vv-i18n')
local editor = require('vv-i18n.editor')
local panel = require('vv-i18n.panel')

local check, done = H.checker()

local HERO_ZH = H.fixture('ns-app/src/components/Hero/locales/zh-CN.ts')
local orig = H.read(HERO_ZH)

i18n.setup(H.ns_config())
i18n.reload()

-- editor.plan：已存在键 → 各语言行（en-US < zh-CN 字典序）
local rows, lines = editor.plan(i18n, 'app.hero.title')
check('plan 2 行(en-US/zh-CN)', rows and #rows == 2, rows and #rows)
if rows then
  check('plan 行1=en-US 有值', rows[1].lang == 'en-US' and lines[1] ~= '')
  check('plan 行2=zh-CN 值=英雄', rows[2].lang == 'zh-CN' and lines[2] == '英雄', lines[2])
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
panel.open(i18n)
local pbuf = vim.api.nvim_get_current_buf()
local joined = table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, false), '\n')
check('panel 含 hero 组', joined:find('hero', 1, true) ~= nil)
check('panel 含 title 键', joined:find('title', 1, true) ~= nil)
check('panel 含译文(Hero/英雄)', joined:find('Hero', 1, true) ~= nil or joined:find('英雄', 1, true) ~= nil)
check('panel 标题含 i18n keys', joined:find('i18n keys', 1, true) ~= nil)
panel.close()

done()
vim.cmd('qa!')

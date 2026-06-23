-- vv-i18n.index：三种布局（top-key / filename / flat）+ tree/missing
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')   -- 自定位 rtp

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local Index = require('vv-i18n.index')
local writer = require('vv-i18n.writer')

local check, done = H.checker()

--------------------------------------------------------------------------------
-- 布局 A：top-key（命名空间在文件内顶层 key）
--------------------------------------------------------------------------------
local dirsA = Index.discover_by_patterns(H.fixture('ns-app/src'), { 'components/*/locales', 'i18n/common' })
check('A discover 3 目录', #dirsA == 3, #dirsA)
local A = Index.build({ dirs = dirsA, prefix = 'app', mount = 'top-key', lang = '{lang}.ts' })
check('A app.hero.title 命中', A:get('app.hero.title') ~= nil)
check('A zh=英雄', (A:get('app.hero.title') or {})['zh-CN'] and A:get('app.hero.title')['zh-CN'].value == '英雄')
local fA = A:resolve_files_for_key('app.hero.title')
check('A resolve 2 文件', fA and #fA == 2, fA and #fA)
check('A in_file_path=hero.title（含顶层 key）', fA and table.concat(fA[1].in_file_path, '.') == 'hero.title')
check('A card.tags 是 array', (A:get('app.card.tags') or {})['zh-CN'] and A:get('app.card.tags')['zh-CN'].kind == 'array')
check('A common.cancel 缺 ja-JP', #A:missing('app.common.cancel') == 1 and A:missing('app.common.cancel')[1] == 'ja-JP')
check('A common.ok 不缺', #A:missing('app.common.ok') == 0)
-- tree
local treeA = A:tree()
check('A tree 3 组', #treeA == 3, #treeA)
-- index→writer dry-run
local okA = true
for _, f in ipairs(fA or {}) do
  if not writer.update_file(f.file, f.in_file_path, 'x', { dry_run = true }).ok then okA = false end
end
check('A index→writer dry-run', okA)

--------------------------------------------------------------------------------
-- 布局 B：filename（命名空间在文件名，键在文件根）
--------------------------------------------------------------------------------
local dirsB = Index.discover_by_patterns(H.fixture('file-ns/src'), { 'locales' })
local B = Index.build({ dirs = dirsB, prefix = '', mount = 'filename', lang = '{lang}/{ns}.json' })
check('B common.ok 命中', B:get('common.ok') ~= nil)
check('B zh common.ok=确定', (B:get('common.ok') or {})['zh-CN'] and B:get('common.ok')['zh-CN'].value == '确定')
check('B home.title 命中', B:get('home.title') ~= nil)
local fB = B:resolve_files_for_key('common.ok')
check('B resolve 2 文件', fB and #fB == 2, fB and #fB)
check('B in_file_path=ok（去掉 ns）', fB and table.concat(fB[1].in_file_path, '.') == 'ok')

--------------------------------------------------------------------------------
-- 布局 C：flat（无命名空间）
--------------------------------------------------------------------------------
local dirsC = Index.discover_by_patterns(H.fixture('flat-app'), { 'locales' })
local C = Index.build({ dirs = dirsC, prefix = '', mount = 'flat', lang = '{lang}.ts' })
check('C greeting.hello 命中', C:get('greeting.hello') ~= nil)
local fC = C:resolve_files_for_key('greeting.hello')
check('C resolve 2 文件', fC and #fC == 2, fC and #fC)
check('C in_file_path=greeting.hello', fC and table.concat(fC[1].in_file_path, '.') == 'greeting.hello')

--------------------------------------------------------------------------------
-- 带 prefix 的 flat / 坏前缀
--------------------------------------------------------------------------------
local D = Index.build({ dirs = dirsC, prefix = 'app', mount = 'flat', lang = '{lang}.ts' })
check('D 带前缀 flat → app.greeting.hello', D:get('app.greeting.hello') ~= nil)
local bad, berr = A:resolve_files_for_key('other.x.y')
check('坏前缀 → bad-prefix', bad == nil and berr == 'bad-prefix', berr)

--------------------------------------------------------------------------------
-- 自定义读侧解析 parse（非 JS/JSON 格式，这里用 key=value）
--------------------------------------------------------------------------------
local function kv_parse(content, _)
  local leaves, top, row = {}, {}, 0
  for line in (content .. '\n'):gmatch('([^\n]*)\n') do
    local k, v = line:match('^%s*([%w%.]+)%s*=%s*(.-)%s*$')
    if k then
      top[#top + 1] = k
      leaves[#leaves + 1] = { path = { k }, dotted = k, kind = 'string', value = v, row = row, col = 0 }
    end
    row = row + 1
  end
  return { top_keys = top, leaves = leaves }
end
local dirsP = Index.discover_by_patterns(H.fixture('custom-kv'), { 'locales' })
local P = Index.build({ dirs = dirsP, prefix = '', mount = 'flat', lang = '{lang}.kv', parse = kv_parse })
check('parse: greeting.hello 命中', P:get('greeting.hello') ~= nil)
check('parse: zh=你好', (P:get('greeting.hello') or {})['zh-CN'] and P:get('greeting.hello')['zh-CN'].value == '你好')
check('parse: row 透传(跳转用)', (P:get('greeting.hello') or {})['en-US'] and P:get('greeting.hello')['en-US'].row == 0)
check('parse: 2 语言', (function() local f = P:resolve_files_for_key('nav.home'); return f and #f == 2 end)())

done()
vim.cmd('qa!')

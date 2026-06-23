-- vv-i18n.resolver：三布局调用点解析 + make_namespace + 端到端
vim.opt.runtimepath:prepend('/home/dev/.config/nvim/vendors/vv-i18n.nvim')
vim.opt.runtimepath:prepend('/home/dev/.config/nvim/vendors/vv-utils.nvim')
vim.opt.runtimepath:append('/home/dev/.local/share/nvim/site')

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local resolver = require('vv-i18n.resolver')
local Index = require('vv-i18n.index')

local check, done = H.checker()

local function locate(content, needle)
  local row = 0
  for line in (content .. '\n'):gmatch('([^\n]*)\n') do
    local s = line:find(needle, 1, true)
    if s then return row, s - 1 end
    row = row + 1
  end
end

--------------------------------------------------------------------------------
-- A. top-key + two-level（useT() → app、useT('common') → app.common）
--------------------------------------------------------------------------------
local A = { lang = 'tsx', namespace_resolver = resolver.make_namespace('two-level', 'app', '.'), hook_names = { useT = true } }
local home = H.read(H.fixture('ns-app/src/pages/Home.tsx'))

local r1, c1 = locate(home, 'hero.title')
local res1 = resolver.resolve_in_content(home, r1, c1, A)
check('A useT() → app.hero.title', res1.ok and res1.full_key == 'app.hero.title', res1.full_key)

local r2, c2 = locate(home, "'ok'")
local res2 = resolver.resolve_in_content(home, r2, c2 + 1, A)
check('A useT(common) → app.common.ok', res2.ok and res2.full_key == 'app.common.ok', res2.full_key)

--------------------------------------------------------------------------------
-- B. filename + hook-arg（useTranslation('common') → common.x）
--------------------------------------------------------------------------------
local B = { lang = 'tsx', namespace_resolver = resolver.make_namespace('hook-arg', '', '.'), hook_names = { useTranslation = true } }
local appB = H.read(H.fixture('file-ns/src/App.tsx'))
local rb, cb = locate(appB, "'ok'")
local resB = resolver.resolve_in_content(appB, rb, cb + 1, B)
check('B useTranslation(common) → common.ok', resB.ok and resB.full_key == 'common.ok', resB.full_key)

--------------------------------------------------------------------------------
-- C. flat（namespace='flat' → 无前缀，字面量即全键）
--------------------------------------------------------------------------------
local C = { lang = 'tsx', namespace_resolver = resolver.make_namespace('flat', '', '.'), hook_names = { useTranslation = true } }
local appC = H.read(H.fixture('flat-app/src/App.tsx'))
local rc, cc = locate(appC, 'greeting.hello')
local resC = resolver.resolve_in_content(appC, rc, cc, C)
check('C flat → greeting.hello（无前缀）', resC.ok and resC.full_key == 'greeting.hello', resC.full_key)
check('C prefix 为 nil', resC.prefix == nil)

--------------------------------------------------------------------------------
-- make_namespace 四预设单测
--------------------------------------------------------------------------------
local function ns(spec, prefix, ctx) return resolver.make_namespace(spec, prefix, '.')(ctx) end
check('preset flat → nil', ns('flat', 'app', { hook_arg = 'x' }) == nil)
check('preset fixed → prefix', ns('fixed', 'app', { hook_arg = 'x' }) == 'app')
check('preset hook-arg(无前缀) → arg', ns('hook-arg', '', { hook_arg = 'common' }) == 'common')
check('preset hook-arg(有前缀) → prefix.arg', ns('hook-arg', 'app', { hook_arg = 'common' }) == 'app.common')
check('preset two-level(无参) → prefix', ns('two-level', 'app', {}) == 'app')
check('preset two-level(有参) → prefix.arg', ns('two-level', 'app', { hook_arg = 'common' }) == 'app.common')

--------------------------------------------------------------------------------
-- 负路径
--------------------------------------------------------------------------------
local plain = "const a = foo('not.key')\n"
local rp, cp = locate(plain, 'not.key')
check('非 t 调用 not-in-t-call', (not resolver.resolve_in_content(plain, rp, cp, A).ok), nil)
local dyn = "const t = useT()\nconst x = t(`hero.${k}`)\n"
local rd, cd = locate(dyn, 'hero.')
check('动态 key dynamic-key', resolver.resolve_in_content(dyn, rd, cd, A).reason == 'dynamic-key')

--------------------------------------------------------------------------------
-- 端到端：resolver → index（三布局各命中）
--------------------------------------------------------------------------------
local idxA = Index.build({ dirs = Index.discover_by_patterns(H.fixture('ns-app/src'), { 'components/*/locales', 'i18n/common' }), prefix = 'app', mount = 'top-key', lang = '{lang}.ts' })
check('A resolver→index', idxA:get(res1.full_key) ~= nil)
local idxB = Index.build({ dirs = Index.discover_by_patterns(H.fixture('file-ns/src'), { 'locales' }), prefix = '', mount = 'filename', lang = '{lang}/{ns}.json' })
check('B resolver→index', idxB:get(resB.full_key) ~= nil)
local idxC = Index.build({ dirs = Index.discover_by_patterns(H.fixture('flat-app'), { 'locales' }), prefix = '', mount = 'flat', lang = '{lang}.ts' })
check('C resolver→index', idxC:get(resC.full_key) ~= nil and idxC:get(resC.full_key)['zh-CN'].value == '你好')

done()
vim.cmd('qa!')

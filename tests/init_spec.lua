-- vv-i18n init：单源 + 多源(mono-repo) + display.compute + preferred_langs
vim.opt.runtimepath:prepend('/home/dev/.config/nvim/vendors/vv-i18n.nvim')
vim.opt.runtimepath:prepend('/home/dev/.config/nvim/vendors/vv-utils.nvim')
vim.opt.runtimepath:append('/home/dev/.local/share/nvim/site')

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local i18n = require('vv-i18n')
local display = require('vv-i18n.display')

local check, done = H.checker()

--------------------------------------------------------------------------------
-- 单源（top-key 布局）
--------------------------------------------------------------------------------
i18n.setup(H.ns_config())
check('命令 VVI18nKeys 注册', vim.fn.exists(':VVI18nKeys') == 2)
check('命令 VVI18nEdit 注册', vim.fn.exists(':VVI18nEdit') == 2)

i18n.reload()
check('lookup app.common.ok=确定', (i18n.lookup('app.common.ok') or {})['zh-CN']
  and i18n.lookup('app.common.ok')['zh-CN'].value == '确定')
local files = i18n.files_for('app.hero.title')
check('files_for 2 文件', files and #files == 2, files and #files)
check('has_keys 真', i18n.has_keys())
check('classify 命中', (i18n.classify('app.hero.title')) == 'hit')
check('classify 缺键=missing', (i18n.classify('app.hero.NOPE')) == 'missing')
check('classify 越界=out', (i18n.classify('zzz.foo')) == 'out')

-- display.compute（挂真实 Home.tsx，走 collect_buffer 多源）
local buf = vim.fn.bufadd(H.fixture('ns-app/src/pages/Home.tsx'))
vim.fn.bufload(buf)
vim.bo[buf].filetype = 'typescriptreact'
local items = display.compute(i18n, i18n.get_config(), buf)
check('compute 有预览项', #items > 0, #items)
local hit
for _, it in ipairs(items) do if it.full_key == 'app.hero.title' then hit = it end end
check('compute 命中 app.hero.title', hit ~= nil and not hit.missing)

-- S6 preferred_langs
check('默认 preferred_lang = 字典序首个 en-US', i18n.preferred_lang({ 'zh-CN', 'en-US' }) == 'en-US')
i18n.setup(vim.tbl_deep_extend('force', H.ns_config(), { display = { preferred_langs = { 'zh-CN' } } }))
i18n.reload()
check('preferred_langs={zh-CN} → zh-CN', i18n.preferred_lang({ 'zh-CN', 'en-US' }) == 'zh-CN')

--------------------------------------------------------------------------------
-- 多源（mono-repo）：top-key 源 + filename 源 共存
--------------------------------------------------------------------------------
i18n.setup({
  root = H.FIXTURES,
  display = { enable = false },
  sources = {
    { prefix = 'app', root = 'ns-app/src', discover = { 'components/*/locales', 'i18n/common' },
      mount = 'top-key', namespace = 'two-level', lang = '{lang}.ts', hooks = { 'useT' } },
    { prefix = '', root = 'file-ns/src', discover = { 'locales' },
      mount = 'filename', namespace = 'hook-arg', lang = '{lang}/{ns}.json', hooks = { 'useTranslation' } },
  },
})
local idxs = i18n.reload()
check('多源建 2 索引', #idxs == 2, #idxs)
check('多源 lookup 源1 app.hero.title', i18n.lookup('app.hero.title') ~= nil)
check('多源 lookup 源2 common.ok', i18n.lookup('common.ok') ~= nil)
check('多源 files_for 源2', (function() local f = i18n.files_for('common.ok'); return f and #f == 2 end)())

done()
vim.cmd('qa!')

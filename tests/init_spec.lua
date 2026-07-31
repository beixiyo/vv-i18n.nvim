-- vv-i18n init：单源 + 多源(mono-repo) + display.compute + preferred_langs
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')   -- 自定位 rtp

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local i18n = require('vv-i18n')
local display = require('vv-i18n.display')

local check, done = H.checker()

--------------------------------------------------------------------------------
-- 连续 setup 的 scheduled 生命周期
--------------------------------------------------------------------------------
local enabled_config = vim.tbl_deep_extend('force', H.ns_config(), {
  display = { enable = true },
})
i18n.setup(enabled_config)
i18n.setup(H.ns_config())
vim.wait(50)

check('旧 setup 的 scheduled enable 不穿透 display.enable=false', not display.is_enabled())

--------------------------------------------------------------------------------
-- setup A→B 必须重建 production index
--------------------------------------------------------------------------------
i18n.setup(H.ns_config())
i18n.reload()
check('A 配置索引已建立', i18n.lookup('app.hero.title') ~= nil)

i18n.setup(H.file_ns_config())
check('B setup 后 lookup 立即使用 B 索引', i18n.lookup('common.ok') ~= nil)
check('B setup 后旧 A 索引已失效', i18n.lookup('app.hero.title') == nil)

--------------------------------------------------------------------------------
-- project config 生效时，fallback display 重配不得重建索引
--------------------------------------------------------------------------------
local project_root = vim.fn.tempname()
vim.fn.mkdir(vim.fs.joinpath(project_root, 'locales'), 'p')
vim.fn.mkdir(vim.fs.joinpath(project_root, 'src'), 'p')
vim.fn.writefile({
  "export default { greeting: { hello: 'Hello' } }",
}, vim.fs.joinpath(project_root, 'locales', 'en-US.ts'))
vim.fn.writefile({
  "const value = t('greeting.hello')",
}, vim.fs.joinpath(project_root, 'src', 'App.ts'))
vim.fn.writefile({
  'return {',
  "  root = " .. string.format('%q', project_root) .. ',',
  '  sources = { {',
  "    discover = function(root)",
  "      _G.VV_I18N_PROJECT_DISCOVER = (_G.VV_I18N_PROJECT_DISCOVER or 0) + 1",
  "      return { root .. '/locales' }",
  "    end,",
  "    mount = 'flat', namespace = 'flat', lang = '{lang}.ts',",
  '  } },',
  '  display = { enable = false },',
  '}',
}, vim.fs.joinpath(project_root, '.vv-i18n.lua'))
local project_buf = vim.fn.bufadd(vim.fs.joinpath(project_root, 'src', 'App.ts'))
vim.fn.bufload(project_buf)
vim.api.nvim_set_current_buf(project_buf)

local original_secure_read = vim.secure.read
vim.secure.read = function(path)
  return table.concat(vim.fn.readfile(path), '\n')
end
_G.VV_I18N_PROJECT_DISCOVER = 0
i18n.setup(H.ns_config())
_G.VV_I18N_PROJECT_DISCOVER = 0
i18n.reload()
check('trusted project fixture 使用项目配置建立索引',
  i18n.lookup('greeting.hello') ~= nil and _G.VV_I18N_PROJECT_DISCOVER == 1,
  vim.inspect({ count = _G.VV_I18N_PROJECT_DISCOVER, value = i18n.lookup('greeting.hello') }))

local display_only = H.ns_config()
display_only.display.max_width = 73
i18n.setup(display_only)
vim.wait(50)
check('active project 下 display-only fallback setup 不重建索引',
  _G.VV_I18N_PROJECT_DISCOVER == 1, _G.VV_I18N_PROJECT_DISCOVER)

local disable_project = H.ns_config()
disable_project.project_config = false
i18n.setup(disable_project)
vim.wait(50)
check('影响项目选择的 setup 会失效并重建 fallback 索引',
  i18n.lookup('app.hero.title') ~= nil and i18n.lookup('greeting.hello') == nil)
vim.secure.read = original_secure_read
_G.VV_I18N_PROJECT_DISCOVER = nil
vim.fn.delete(project_root, 'rf')

--------------------------------------------------------------------------------
-- 单源（top-key 布局）
--------------------------------------------------------------------------------
i18n.setup(H.ns_config())
check('命令 VVI18nKeys 注册', vim.fn.exists(':VVI18nKeys') == 2)
check('命令 VVI18nMissing 注册', vim.fn.exists(':VVI18nMissing') == 2)
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

vim.api.nvim_set_current_buf(buf)
local src_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
for i, line in ipairs(src_lines) do
  local col = line:find('hero.title', 1, true)
  if col then
    vim.api.nvim_win_set_cursor(0, { i, col - 1 })
    break
  end
end
vim.cmd('VVI18nInfo')
local info_buf = vim.api.nvim_get_current_buf()
local info_text = table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), '\n')
check('VVI18nInfo 打开窗口', vim.bo[info_buf].filetype == 'vv-i18n-info')
check('VVI18nInfo 含当前 key', info_text:find('app.hero.title', 1, true) ~= nil)
check('VVI18nInfo 含译文', info_text:find('Hero', 1, true) ~= nil and info_text:find('英雄', 1, true) ~= nil)
pcall(vim.api.nvim_win_close, 0, true)

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

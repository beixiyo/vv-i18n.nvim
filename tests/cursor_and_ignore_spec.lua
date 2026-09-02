-- 定义位置光标解析与 ignore_key 公共契约的端到端回归
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local i18n = require('vv-i18n')
local References = require('vv-i18n.references.index')

local check, done = H.checker()
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = assert(vim.uv.fs_realpath(root))
local locales = vim.fs.joinpath(root, 'locales')
local source_path = vim.fs.joinpath(root, 'src', 'App.ts')
local custom_source_path = vim.fs.joinpath(root, 'src', 'extra.py')
local definition_path = vim.fs.joinpath(locales, 'en-US.json')

vim.fn.mkdir(locales, 'p')
vim.fn.mkdir(vim.fs.dirname(source_path), 'p')
vim.fn.writefile({
  '{',
  '  "visible": {',
  '    "title":',
  '      "Hello"',
  '  },',
  '  "alpha": "A", "beta": "B",',
  '  "_private": "Internal"',
  '}',
}, definition_path)
vim.fn.writefile({
  '{',
  '  "visible": {',
  '    "title":',
  '      "你好"',
  '  },',
  '  "alpha": "甲", "beta": "乙",',
  '  "_private": "内部"',
  '}',
}, vim.fs.joinpath(locales, 'zh-CN.json'))
vim.fn.writefile({
  "const visible = t('visible.title')",
  "const privateValue = t('_private')",
}, source_path)
vim.fn.writefile({ "gettext('_private')" }, custom_source_path)

i18n.setup({
  root = root,
  sources = {
    {
      discover = { 'locales' },
      mount = 'flat',
      namespace = 'flat',
      lang = '{lang}.json',
    },
  },
  display = { enable = false },
  ignore_key = function(full_key) return vim.startswith(full_key, '_') end,
  references = {
    scanners = { {
      id = 'python',
      extensions = { 'py' },
      names = { 'gettext' },
      collect = function()
        return { {
          kind = 'hit',
          full_key = '_private',
          literal = '_private',
          range = { srow = 0, scol = 0, erow = 0, ecol = 19 },
        } }
      end,
    } },
  },
})
i18n.reload()
check('引用扫描完成', vim.wait(3000, function() return not References.is_scanning() end))
check('自定义 scanner 的候选文件已被真实扫描',
  References.snapshot().scan.source_fingerprints[custom_source_path] ~= nil)

local function move_to(path, filetype, needle)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].filetype = filetype
  vim.api.nvim_set_current_buf(buf)
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local col = line:find(needle, 1, true)
    if col then
      vim.api.nvim_win_set_cursor(0, { lnum, col - 1 })
      return buf
    end
  end
  error('needle not found: ' .. needle)
end

local definition_buf = move_to(definition_path, 'json', '"title"')
local resolved = i18n.resolve_cursor()
local definitions = i18n.definitions_for_file(definition_path)
local direct_definition = i18n.definition_at_cursor()
check('JSON 多行值的定义 key 可解析为完整 key', resolved.ok
  and resolved.full_key == 'visible.title' and resolved.definition == true, vim.inspect({
    resolved = resolved,
    cursor = vim.api.nvim_win_get_cursor(0),
    direct_definition = direct_definition,
    path = vim.api.nvim_buf_get_name(0),
    definitions = definitions,
  }))

-- 同一行两个定义：光标在第二个 key 的值上不能串到字母序靠前的 alpha
move_to(definition_path, 'json', '"B"')
check('同行多个定义时光标在值上解析为左侧最近的 key', i18n.definition_at_cursor() == 'beta',
  vim.inspect(i18n.definition_at_cursor()))
move_to(definition_path, 'json', '"Hello"')
check('跨行值所在行仍解析为该 key', i18n.definition_at_cursor() == 'visible.title')

-- 传入未显示在任何窗口的 buffer 时不得借用当前窗口的光标
local hidden_buf = vim.fn.bufadd(source_path)
vim.fn.bufload(hidden_buf)
local hidden = i18n.resolve_cursor(hidden_buf)
check('不可见 buffer 的 resolve_cursor 返回 buffer-not-visible', not hidden.ok and hidden.reason == 'buffer-not-visible',
  vim.inspect(hidden))

move_to(definition_path, 'json', '"title"')
vim.cmd('VVI18nInfo')
local info_buf = vim.api.nvim_get_current_buf()
local info_text = table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), '\n')
check('定义 key 上可执行 VVI18nInfo', vim.bo[info_buf].filetype == 'vv-i18n-info'
  and info_text:find('visible.title', 1, true) ~= nil)
pcall(vim.api.nvim_win_close, 0, true)

vim.api.nvim_set_current_buf(definition_buf)
vim.cmd('VVI18nReferences')
local references_buf = vim.api.nvim_get_current_buf()
local references_text = table.concat(vim.api.nvim_buf_get_lines(references_buf, 0, -1, false), '\n')
check('定义 key 上可执行 VVI18nReferences', vim.bo[references_buf].filetype == 'vv-i18n-references'
  and references_text:find('src/App.ts', 1, true) ~= nil)
require('vv-i18n.references.panel').close()

check('ignore_key 从定义索引排除匹配 key', i18n.lookup('_private') == nil)
local ignored_files, ignored_error = i18n.files_for('_private')
check('ignore_key 阻止写操作定位匹配 key', ignored_files == nil and ignored_error == 'ignored-key', ignored_error)
check('ignore_key 从引用索引排除匹配 key', #References.get('_private') == 0)
check('未忽略 key 仍保留定义和引用', i18n.lookup('visible.title') ~= nil
  and #References.get('visible.title') == 1)

move_to(source_path, 'typescript', '_private')
local ignored = i18n.resolve_cursor()
check('ignore_key 同时屏蔽调用点光标操作', not ignored.ok and ignored.reason == 'ignored-key', vim.inspect(ignored))

-- 回调抛错：索引构建与引用扫描都不得中断，错误进入 errors / failures，该 key 按不忽略处理
local function setup_with_ignore(ignore_key)
  i18n.setup({
    root = root,
    sources = { { discover = { 'locales' }, mount = 'flat', namespace = 'flat', lang = '{lang}.json' } },
    display = { enable = false },
    ignore_key = ignore_key,
    references = { scanners = { {
      id = 'python',
      extensions = { 'py' },
      names = { 'gettext' },
      collect = function()
        return { { kind = 'hit', full_key = 'only.in.scanner', literal = 'x', range = { srow = 0, scol = 0, erow = 0, ecol = 1 } } }
      end,
    } } },
  })
end

setup_with_ignore(function(full_key)
  if full_key == 'only.in.scanner' then error('scan boom') end
  return full_key:match('^_')   -- 返回 string 真值而非 boolean
end)
local reload_ok = pcall(i18n.reload)
check('引用扫描阶段 ignore_key 抛错后扫描仍能结束', reload_ok
  and vim.wait(3000, function() return not References.is_scanning() end))
local scan = References.snapshot().scan
local scan_failure
for _, failure in ipairs(scan.failures) do
  if failure.reason == 'ignore-key-error' and failure.file == custom_source_path then scan_failure = failure end
end
check('扫描阶段抛错记入 failures 且 key 按不忽略处理', scan_failure ~= nil and #References.get('only.in.scanner') == 1,
  vim.inspect(scan.failures))
check('ignore_key 返回非 boolean 真值同样生效', i18n.lookup('_private') == nil)

setup_with_ignore(function(full_key)
  if full_key == 'alpha' then error('build boom') end
  return false
end)
local build_ok = pcall(i18n.reload)
local build_state = i18n.get_state()
local build_failure
for _, failure in ipairs(build_state.errors) do
  if vim.startswith(failure.reason or '', 'ignore-key-error:') and failure.file == definition_path then
    build_failure = failure
  end
end
check('索引构建阶段 ignore_key 抛错不中断构建', build_ok and i18n.lookup('alpha') ~= nil and i18n.lookup('beta') ~= nil)
check('构建阶段抛错按文件记入索引 errors', build_failure ~= nil, vim.inspect(build_state.errors))
vim.wait(3000, function() return not References.is_scanning() end)

vim.fn.delete(root, 'rf')
done()
vim.cmd('qa!')

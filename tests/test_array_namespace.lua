local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ icons = true, fixtures = true, setup = 'bootstrap.lua' })

T['数组命名空间贯穿解析索引且不猜动态首项'] = function()
  child.lua_func(function()
    local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helper.lua')
    local i18n = require('vv-i18n')
    local Query = require('vv-i18n.service.query')
    local resolver = require('vv-i18n.resolver')
    local check = H.checker()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/locales/en-US', 'p')
    vim.fn.mkdir(root .. '/locales/zh-CN', 'p')
    for _, lang in ipairs({ 'en-US', 'zh-CN' }) do
      vim.fn.writefile({ '{"list":{"audioError":"error"}}' }, root .. '/locales/' .. lang .. '/cards.json')
      vim.fn.writefile({ '{"other":"other"}' }, root .. '/locales/' .. lang .. '/recorder.json')
    end
    i18n.setup({ root = root, sources = {{ discover = { 'locales' }, mount = 'filename',
      namespace = 'hook-arg', lang = '{lang}/{ns}.json', hooks = { 'useTranslation' } }},
      display = { enable = false }, references = { enable = false } })
    i18n.reload()
    vim.cmd.enew()
    vim.bo.filetype = 'typescriptreact'
    local function resolve(hook, key)
      local lines = { 'const { t } = useTranslation(' .. hook .. ')', "t('" .. key .. "')" }
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.api.nvim_win_set_cursor(0, { 2, 4 })
      return i18n.resolve_cursor(), table.concat(lines, '\n')
    end
    local result, content = resolve("[ /* 首项 */ 'cards', 'recorder' ]", 'list.audioError')
    check('数组首项经真实光标解析为 cards.list.audioError', result.ok and result.full_key == 'cards.list.audioError', result.full_key)
    local files, err = i18n.files_for(result.full_key)
    check('真实索引返回两语言文件', files and #files == 2, err)
    local collected = Query.collect_content(i18n.get_state(), i18n, content, root .. '/App.tsx')
    check('生产收集命中首命名空间', collected[1] and collected[1].kind == 'hit' and collected[1].full_key == 'cards.list.audioError')
    local absolute = resolve("['cards', 'recorder']", 'recorder:other')
    check('显式命名空间覆盖数组首项', absolute.ok and absolute.full_key == 'recorder.other')
    local single = resolve("'cards'", 'list.audioError')
    check('普通字符串保持原行为', single.ok and single.full_key == 'cards.list.audioError')
    local template = resolve('[`cards`, `recorder`]', 'list.audioError')
    check('无插值模板首项按静态字面量处理', template.ok and template.full_key == 'cards.list.audioError')
    for _, hook in ipairs({ '[]', "[dynamic, 'cards']", "[...names, 'cards']", "[, 'cards']", "[`${name}`, 'cards']", "names, 'cards'" }) do
      local cursor, source = resolve(hook, 'list.audioError')
      check('未知命名空间不生成光标全键：' .. hook, not cursor.ok)
      local rows = Query.collect_content(i18n.get_state(), i18n, source, root .. '/App.tsx')
      check('未知命名空间保留全局动态保护：' .. hook, rows[1] and rows[1].kind == 'dynamic' and rows[1].unsafe and rows[1].pattern == '*')
      local explicit = resolve(hook, 'recorder:other')
      check('未知 hook 的显式命名空间仍可解析：' .. hook, explicit.ok and explicit.full_key == 'recorder.other')
    end
    local invalid = resolver.resolve_in_content([[const { t } = useTranslation(names)
t('recorder:\u12')]], 1, 5)
    check('显式命名空间不绕过 key 解码可靠性', not invalid.ok and invalid.unsafe_dynamic)
    local no_arg = resolver.resolve_in_content("const { t } = useTranslation()\nt('plain')", 1, 4)
    check('无参保持无前缀行为', no_arg.ok and no_arg.full_key == 'plain')
  end)
end

return T

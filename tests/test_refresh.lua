-- 真实场景在独立子进程中执行；收集阶段仅注册具名用例。
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ icons = true, fixtures = true, setup = 'bootstrap.lua' })

T["外部修改与手动重建及时更新预览和定义缓存"] = function()
  child.lua_func(function()
    -- vv-i18n 索引新鲜度：locale 文件在 nvim 外部被改写（Agent / 其它工具）后行内预览自动跟上，
    -- 手动 reload 后预览立即重算，不需要再 toggle

    local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helper.lua')
    local i18n = require('vv-i18n')

    local check = H.checker()

    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/locales', 'p')
    vim.fn.mkdir(root .. '/src', 'p')
    local locale = root .. '/locales/en-US.ts'

    local function write_locale(entries)
      local body = {}
      for k, v in pairs(entries) do body[#body + 1] = ("%s: '%s'"):format(k, v) end
      table.sort(body)
      vim.fn.writefile({ 'export default { greeting: { ' .. table.concat(body, ', ') .. ' } }' }, locale)
    end

    write_locale({ hello = 'Hello' })
    vim.fn.writefile({
      '// preview',
      "const a = t('greeting.hello')",
      "const b = t('greeting.bye')",
    }, root .. '/src/App.ts')

    vim.cmd.edit(root .. '/src/App.ts')
    vim.bo.filetype = 'typescript'
    vim.api.nvim_win_set_cursor(0, { 1, 0 })   -- 光标不压在任何 t() 上，否则该项会被 token 级还原

    i18n.setup({
      root = root,
      sources = { { prefix = '', discover = { 'locales' }, mount = 'flat', namespace = 'flat', lang = '{lang}.ts' } },
      display = { enable = true },
    })
    vim.wait(100)

    local ns = vim.api.nvim_create_namespace('vv_i18n_preview')

    --- 第 row 行（1-based）预览插入的文本
    local function preview_at(row)
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, { row - 1, 0 }, { row - 1, -1 }, { details = true })) do
        local chunks = m[4].virt_text or {}
        local text = {}
        for _, c in ipairs(chunks) do text[#text + 1] = c[1] end
        return table.concat(text)
      end
    end

    check('初始：已有 key 显示译文', (preview_at(2) or ''):find('Hello', 1, true) ~= nil, preview_at(2))
    check('初始：未定义 key 显示缺失', (preview_at(3) or ''):find('greeting.bye', 1, true) ~= nil, preview_at(3))

    -- 外部补上 key（不经 nvim 写盘），切回 nvim
    write_locale({ hello = 'Hello', bye = 'Bye' })
    vim.api.nvim_exec_autocmds('FocusGained', {})
    vim.wait(100)
    check('外部新增 key 后 FocusGained 自动重建并显示译文',
      (preview_at(3) or ''):find('Bye', 1, true) ~= nil and not (preview_at(3) or ''):find('greeting.bye', 1, true),
      preview_at(3))

    -- 不触发任何事件，直接手动 reload：预览必须立即反映新索引
    write_locale({ hello = 'Hello', bye = 'Goodbye' })
    i18n.reload()
    check('手动 reload 后预览立即重算（无需 toggle）',
      (preview_at(3) or ''):find('Goodbye', 1, true) ~= nil, preview_at(3))

    -- locale 未变时事件不触发重建
    vim.api.nvim_exec_autocmds('FocusGained', {})
    vim.wait(100)
    check('locale 未变时不重建索引', i18n.refresh_if_stale() == false)

    -- definitions_for_file 走反查表缓存：reload 换了索引后必须反映新键，不能返回旧快照
    local function defined_keys()
      local keys = {}
      for _, d in ipairs(i18n.definitions_for_file(locale)) do keys[#keys + 1] = d.full_key end
      table.sort(keys)
      return table.concat(keys, ',')
    end
    check('reload 前 locale 文件的定义', defined_keys() == 'greeting.bye,greeting.hello', defined_keys())
    write_locale({ hello = 'Hello', bye = 'Goodbye', later = 'Later' })
    i18n.reload()
    check('reload 后 definitions_for_file 反映新增键', defined_keys() == 'greeting.bye,greeting.hello,greeting.later',
      defined_keys())

    -- 预览按 changedtick 缓存：内容没变的进窗事件只重绘，内容变了必须重算
    vim.api.nvim_buf_set_lines(0, 2, 3, false, { "const b = t('greeting.later')" })
    vim.api.nvim_exec_autocmds('BufEnter', { buffer = 0 })
    vim.wait(100)
    check('buffer 内容改动后再次进入会重算预览', (preview_at(3) or ''):find('Later', 1, true) ~= nil, preview_at(3))
  end)
end

return T

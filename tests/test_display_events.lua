-- 真实事件 + extmark 结果验证，计数用于约束已证实的重复工作，不替代行为断言
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ icons = true, setup = 'bootstrap.lua' })

local function prepare()
  child.lua_func(function()
    local P = require('vv-i18n')
    local root = vim.env.VV_TEST_TMP .. '/project'
    vim.fn.mkdir(root .. '/locales/base', 'p')
    -- Neovim 的 buffer 名会解析 macOS /var、/tmp 符号链接；fixture root 使用同一规范路径
    root = assert(vim.uv.fs_realpath(root))
    vim.fn.writefile({ 'export default { one: "One", two: "Two" }' }, root .. '/locales/base/en.ts')
    vim.fn.writefile({ '// preview', "t('a:one'); t('a:two')" }, root .. '/source.ts')
    vim.cmd.edit(root .. '/source.ts')
    vim.bo.filetype = 'typescript'
    local config = {
      root = root, project_config = false,
      sources = {
        { prefix = 'a', discover = { 'locales/*' }, mount = 'flat', namespace = 'fixed', lang = '{lang}.ts' },
        { prefix = 'b', discover = { 'locales/*' }, mount = 'flat', namespace = 'fixed', lang = '{lang}.ts' },
      },
      display = { enable = true, lang = 'en' },
    }
    P.setup(config)
    vim.wait(50)
    local ns = vim.api.nvim_create_namespace('vv_i18n_preview')
    local buf = vim.api.nvim_get_current_buf()
    F = { plugin = P, root = root, buf = buf, ns = ns, config = config, counts = {} }
    function F.event(name)
      vim.api.nvim_exec_autocmds(name, { buffer = 0 })
    end
    function F.marks()
      return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    end
    function F.text()
      local out = {}
      for _, mark in ipairs(F.marks()) do
        for _, chunk in ipairs(mark[4].virt_text or {}) do out[#out + 1] = chunk[1] end
      end
      return table.concat(out, '|')
    end
    function F.move(row, col)
      vim.api.nvim_win_set_cursor(0, { row, col })
      F.event('CursorMoved')
    end
    local function observe(object, key, name, preview_only)
      local original = object[key]
      object[key] = function(...)
        if not preview_only or select(2, ...) == ns then
          F.counts[name] = (F.counts[name] or 0) + 1
        end
        return original(...)
      end
    end
    observe(vim.api, 'nvim_buf_set_extmark', 'set', true)
    observe(vim.api, 'nvim_buf_clear_namespace', 'clear', true)
    observe(vim.api, 'nvim_buf_del_extmark', 'delete', true)
    observe(P, 'collect_buffer', 'collect')
    observe(require('vv-i18n.index'), 'walk_files', 'walk')
    observe(require('vv-i18n.service.index'), 'reload', 'reload')
    assert(#F.marks() == 2 and F.text():find('One') and F.text():find('Two'), '前置：真实调用必须显示两个译文')
  end)
end

T['光标进出只改当前项，同行其他译文与项外移动保持装饰身份'] = function()
  prepare()
  child.lua_func(function()
    local original = F.marks()
    for col = 0, 8 do F.move(1, col) end
    assert(vim.deep_equal(F.marks(), original), '项外移动不能重建未变化的译文 extmark')
    assert(not F.counts.set and not F.counts.clear and not F.counts.collect, '项外移动不得重画或重新解析')
    F.move(2, 4)
    local remaining = F.marks()
    assert(#remaining == 1 and remaining[1][1] == original[2][1] and F.text():find('Two'),
      '进入第一个 key 应只还原它，同行第二个译文保持原 mark')
    F.move(2, 5)
    assert(vim.deep_equal(F.marks(), remaining), '同一 key 内移动不应重复更新装饰')
    F.move(2, 16)
    assert(#F.marks() == 1 and F.text():find('One') and not F.text():find('Two'), '直接移到第二个 key 应恢复第一个译文')
    F.move(1, 0)
    assert(#F.marks() == 2 and F.text():find('Two'), '移出 key 后应恢复全部译文')
    assert(F.counts.set == 2 and F.counts.delete == 2 and not F.counts.clear and not F.counts.collect,
      '两项进出只需要各恢复一次、删除一次，不应全 buffer 重画或解析')

    -- 内容改变后先来光标事件，也不能按旧坐标恢复隐藏的 key
    F.move(2, 4)
    vim.api.nvim_buf_set_lines(F.buf, 1, 2, false, { "t('a:two')" })
    F.move(1, 0)
    F.event('TextChanged')
    vim.wait(50)
    assert(#F.marks() == 1 and F.text():find('Two') and not F.text():find('One'), '源文件编辑后必须按新内容重算')
    F.plugin.disable()
    assert(#F.marks() == 0, 'disable 必须清除局部更新持有的所有 mark')
    F.event('CursorMoved')
    assert(#F.marks() == 0, '关闭后光标事件不能重建预览')
  end)
end

T['同一 buffer 多窗刷新只解析一次，配置和切根仍立即重算'] = function()
  prepare()
  child.lua_func(function()
    vim.cmd.vsplit()
    vim.wait(50)
    F.counts = {}
    F.plugin.reload()
    assert(F.counts.collect == 1, '同一次 reload 的多个窗口不能重复解析同一 buffer')
    assert(#F.marks() == 2 and F.text():find('One'), '去重后仍显示真实译文')
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      assert(vim.wo[win].conceallevel == 2, '每个窗口仍须设置 conceal')
    end
    F.config.ignore_key = function(key) return key == 'a.one' end
    F.config.display.render = function(ctx) return 'custom:' .. ctx.value end
    F.plugin.setup(F.config)
    vim.wait(50)
    assert(#F.marks() == 1 and F.text():find('custom:Two'), 'ignore 和 renderer 改动必须撤销旧预览缓存')

    local next_root = F.root .. '/next'
    vim.fn.mkdir(next_root .. '/locales/base', 'p')
    vim.fn.writefile({ 'export default { two: "Next root" }' }, next_root .. '/locales/base/en.ts')
    F.config.root = next_root
    F.plugin.setup(F.config)
    vim.wait(50)
    assert(F.plugin.get_state({ indexes = false }).root == next_root and F.text():find('custom:Next root'),
      '切 root 后不能复用上一项目的译文')
    F.plugin.disable()
    F.config.sources = {}
    F.plugin.setup(F.config)
    vim.wait(50)
    F.counts = {}
    F.event('FocusGained')
    vim.wait(50)
    assert(#F.marks() == 0 and not F.plugin.has_keys() and not F.counts.walk, '无 sources 时不能遗留预览或遍历 locale')
  end)
end

T['共目录指纹单轮复用，外部增删改与无关 buffer 事件仍发现变化'] = function()
  prepare()
  child.lua_func(function()
    local R = require('vv-i18n.references.index')
    F.event('FocusGained')
    vim.wait(50)
    assert(F.counts.walk == 1 and not F.counts.reload, '同次指纹读取应只遍历共用目录一次，且未变时不重建')
    assert(#F.marks() == 2 and F.text():find('One'), '未变的指纹检查不得影响译文')

    -- 无关 buffer 不能提前按 ft 过滤掉外部 locale 发现；保留另一个可见源码窗口
    vim.cmd.vsplit()
    vim.cmd.enew()
    vim.bo.filetype = 'text'
    vim.wait(50)
    local locale = F.root .. '/locales/base/en.ts'
    vim.fn.writefile({ 'export default { one: "Changed", two: "Two" }' }, locale)
    F.event('FocusGained')
    vim.wait(50)
    assert(F.text():find('Changed') and F.plugin.lookup('b.one').en.value == 'Changed',
      '无关 buffer 的 FocusGained 仍应更新所有 source 及可见译文')

    vim.fn.writefile({ 'export default { one: "French" }' }, F.root .. '/locales/base/fr.ts')
    F.event('FocusGained')
    vim.wait(50)
    assert(F.plugin.lookup('a.one').fr.value == 'French', '同目录外部新增 locale 文件必须被发现')
    vim.fn.delete(F.root .. '/locales/base/fr.ts')
    F.event('FocusGained')
    vim.wait(50)
    assert(F.plugin.lookup('a.one').fr == nil, '外部删除 locale 文件必须撤销该语言')

    vim.fn.mkdir(F.root .. '/locales/added', 'p')
    vim.fn.writefile({ 'export default { extra: "Extra" }' }, F.root .. '/locales/added/en.ts')
    F.event('FocusGained')
    vim.wait(50)
    assert(F.plugin.lookup('a.extra') and F.plugin.lookup('b.extra'), 'glob 新目录必须在两个 source 中发现')
    R.ensure(F.plugin)
    assert(R.is_scanning(), '前置：真实引用扫描应处于在途状态')
    local generation = R.snapshot().generation
    vim.api.nvim_set_current_buf(F.buf)
    vim.api.nvim_buf_set_lines(F.buf, -1, -1, false, { "t('a:extra')" })
    vim.cmd.write()
    assert(R.is_scanning() and R.snapshot().generation > generation, '扫描中保存必须经 BufWritePost 重启全扫')
    assert(vim.wait(3000, function() return not R.is_scanning() end), '真实引用扫描必须完成')
    vim.wait(50)
    assert(#R.get('a.one') == 1 and #R.get('a.two') == 1 and #R.get('a.extra') == 1,
      '重启后的引用结果应包含刚保存的调用，不得发布旧扫描结果')
    assert(#F.marks() == 3 and F.text():find('Extra'), '保存后预览同样应使用新的源码内容')
    vim.fn.delete(F.root .. '/locales/added', 'rf')
    vim.fn.writefile({ 'export default { two: "Two" }' }, locale)
    F.event('FocusGained')
    vim.wait(50)
    assert(not F.plugin.lookup('a.extra') and not F.plugin.lookup('a.one'), '删除目录及 key 必须使旧 locale 索引失效')
    assert(R.snapshot().scan.status == 'idle', 'locale 重建必须撤销引用证据且不启动无消费者扫描')
    R.ensure(F.plugin)
    assert(vim.wait(3000, function() return not R.is_scanning() end))
    assert(#R.get('a.one') == 0 and #R.get('a.two') == 1, '引用重扫不能继续发布已删除 key 的旧命中')
  end)
end

return T

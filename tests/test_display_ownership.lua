-- 真实 setup / enable / 进窗 / disable 链路；窗口选项始终读 raw local
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ icons = true, setup = 'bootstrap.lua' })

local function prepare()
  child.lua_func(function()
    local P = require('vv-i18n')
    local root = vim.env.VV_TEST_TMP .. '/project'
    vim.fn.mkdir(root .. '/locales', 'p')
    root = assert(vim.uv.fs_realpath(root))
    vim.fn.writefile({ 'export default { one: "One" }' }, root .. '/locales/en.ts')
    for _, name in ipairs({ 'a.ts', 'b.ts', 'note.md' }) do
      vim.fn.writefile({ '// preview', "t('one')" }, root .. '/' .. name)
    end
    vim.cmd.edit(root .. '/a.ts')
    vim.bo.filetype = 'typescript'
    F = { plugin = P, root = root, win = vim.api.nvim_get_current_win() }
    function F.set(cl, cc)
      vim.api.nvim_set_option_value('conceallevel', cl, { win = F.win, scope = 'local' })
      vim.api.nvim_set_option_value('concealcursor', cc, { win = F.win, scope = 'local' })
    end
    function F.values(scope)
      return {
        vim.api.nvim_get_option_value('conceallevel', { win = F.win, scope = scope or 'local' }),
        vim.api.nvim_get_option_value('concealcursor', { win = F.win, scope = scope or 'local' }),
      }
    end
    function F.expect(cl, cc, message)
      assert(vim.deep_equal(F.values(), { cl, cc }), message .. ': ' .. vim.inspect(F.values()))
    end
    function F.enter(name, ft)
      vim.cmd.edit(root .. '/' .. name)
      vim.bo.filetype = ft
      vim.wait(50)
    end
    F.set(1, 'n')
    F.global = F.values('global')
    F.config = {
      root = root, project_config = false,
      sources = { { discover = { 'locales' }, mount = 'flat', namespace = 'flat', lang = '{lang}.ts' } },
      display = { enable = false, lang = 'en' }, references = { enable = false },
    }
    P.setup(F.config)
    vim.wait(50)
    P.enable()
    F.expect(2, 'nvic', '启用必须接管匹配 buffer')
    local marks = vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace('vv_i18n_preview'), 0, -1, { details = true })
    assert(#marks == 1 and marks[1][4].virt_text[1][1]:find('One'), '前置：生产链必须显示真实译文')
  end)
end

T['同窗切到另一个匹配 buffer 后恢复新 buffer 的基线'] = function()
  prepare()
  child.lua_func(function()
    -- 新文件继承窗口 global，不是 A 的 local=1/n
    F.enter('b.ts', 'typescript')
    F.expect(2, 'nvic', '进入 B 后仍须接管')
    F.plugin.disable()
    F.expect(F.global[1], F.global[2], '关闭不得把 A 的基线写进 B')
    assert(vim.deep_equal(F.values('global'), F.global), '接管及恢复不得改窗口 global 副本')
  end)
end

T['切到不匹配 buffer 后关闭不得恢复前一个 buffer 的值'] = function()
  prepare()
  child.lua_func(function()
    F.enter('note.md', 'markdown')
    -- 即使 markdown 恰好等于插件施加值，也不能据数值误认 ownership
    F.set(2, 'nvic')
    F.plugin.disable()
    F.expect(2, 'nvic', 'buffer 身份不同必须跳过恢复')
  end)
end

T['同 buffer 正常恢复且重复关闭不再次写入'] = function()
  prepare()
  child.lua_func(function()
    F.plugin.disable()
    F.expect(1, 'n', '无后来 owner 时恢复两个字段')
    F.set(3, 'v')
    F.plugin.disable()
    F.expect(3, 'v', '重复 disable 不能沿用已释放记录')
    F.plugin.enable()
    F.expect(2, 'nvic', '重新启用应接管')
    F.plugin.disable()
    F.expect(3, 'v', '重新启用必须保存新的基线')
  end)
end

T['后来 owner 仅改 conceallevel 时保留它并恢复 concealcursor'] = function()
  prepare()
  child.lua_func(function()
    F.set(3, 'nvic')
    F.plugin.disable()
    F.expect(3, 'n', '比较与恢复必须逐字段而非整组处理')
  end)
end

T['后来 owner 仅改 concealcursor 时保留它并恢复 conceallevel'] = function()
  prepare()
  child.lua_func(function()
    F.set(2, 'v')
    F.plugin.disable()
    F.expect(1, 'v', 'concealcursor 被修改不应阻止 conceallevel 恢复')
  end)
end

T['后来 owner 修改两个字段时关闭均不覆盖'] = function()
  prepare()
  child.lua_func(function()
    F.set(3, 'v')
    F.plugin.disable()
    F.expect(3, 'v', '关闭必须保留后来 owner 的两个字段')
  end)
end

T['启用期间重新进窗仍接管同 buffer 且保持原基线'] = function()
  prepare()
  child.lua_func(function()
    local source = F.win
    vim.cmd.vsplit()
    local other = vim.api.nvim_get_current_win()
    F.enter('note.md', 'markdown')
    F.set(3, 'v')
    vim.api.nvim_set_current_win(source)
    vim.wait(50)
    F.expect(2, 'nvic', '重新进入匹配窗口必须重新接管后来修改')
    F.plugin.disable()
    F.expect(1, 'n', '同 buffer 重新接管沿用本次启用的基线')
    vim.api.nvim_win_close(other, true)
  end)
end

T['关闭或禁用配置后的排队事件不能重写选项'] = function()
  prepare()
  child.lua_func(function()
    vim.api.nvim_exec_autocmds('BufEnter', { buffer = 0 })
    F.set(3, 'nvic')
    F.plugin.disable()
    vim.wait(50)
    F.expect(3, 'n', '关闭后排队事件不得重新接管')
    F.plugin.enable()
    vim.api.nvim_exec_autocmds('BufEnter', { buffer = 0 })
    F.set(2, 'v')
    F.plugin.setup(F.config)
    vim.wait(50)
    F.expect(3, 'v', 'setup 禁用展示时同样按字段释放，旧事件不能写回')
    F.plugin.disable()
    F.expect(3, 'v', 'setup 后重复关闭不得写回旧基线')
  end)
end

return T

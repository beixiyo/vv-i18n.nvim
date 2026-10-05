-- 真实场景在独立子进程中执行；收集阶段仅注册具名用例。
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ icons = true, fixtures = true, setup = 'bootstrap.lua' })

T["真实调用行显示译文且禁用清空预览"] = function()
  child.lua_func(function()
    -- vv-i18n 集成：setup→enable→真 extmark 渲染（ns-app fixture）

    local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helper.lua')
    local i18n = require('vv-i18n')

    local check = H.checker()

    i18n.setup(H.ns_config())
    i18n.reload()

    local buf = vim.fn.bufadd(H.fixture('ns-app/src/pages/Home.tsx'))
    vim.fn.bufload(buf)
    vim.bo[buf].filetype = 'typescriptreact'
    vim.api.nvim_set_current_buf(buf)

    i18n.enable()

    local ns = vim.api.nvim_get_namespaces()['vv_i18n_preview']
    check('预览 namespace 存在', ns ~= nil)

    local marks = ns and vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) or {}
    check('渲染出 extmark(≥1)', #marks >= 1, #marks)

    local title_row
    for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if line:find("t('hero.title')", 1, true) then title_row = row - 1 end
    end
    local title_mark
    for _, m in ipairs(marks) do
      if m[2] == title_row then title_mark = m end
    end
    local title_text = ''
    for _, chunk in ipairs((title_mark and title_mark[4] and title_mark[4].virt_text) or {}) do
      title_text = title_text .. (chunk[1] or '')
    end
    check('hero.title 调用行渲染其译文', title_mark ~= nil
      and (title_text:find('Hero', 1, true) or title_text:find('英雄', 1, true)))

    i18n.disable()
    local after = ns and vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) or {}
    check('disable 后 extmark 清空', #after == 0, #after)
  end)
end

return T

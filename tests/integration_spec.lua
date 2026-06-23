-- vv-i18n 集成：setup→enable→真 extmark 渲染（ns-app fixture）
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')   -- 自定位 rtp

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local i18n = require('vv-i18n')

local check, done = H.checker()

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

local found = false
for _, m in ipairs(marks) do
  local vt = m[4] and m[4].virt_text
  if vt then
    for _, chunk in ipairs(vt) do
      if type(chunk[1]) == 'string'
        and (chunk[1]:find('Hero', 1, true) or chunk[1]:find('英雄', 1, true)) then
        found = true
      end
    end
  end
end
check('extmark 虚拟文本含 hero.title 译文', found)

i18n.disable()
local after = ns and vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) or {}
check('disable 后 extmark 清空', #after == 0, #after)

done()
vim.cmd('qa!')

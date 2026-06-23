-- 测试 rtp 自定位引导：脱离机器绝对路径，可在任意 clone 处运行
--   * 插件根     = 本文件上级（tests/ 的父目录）
--   * vv-utils   = 同级目录的 vv-utils.nvim（vendors 并列布局），或环境变量 $VV_UTILS 覆盖
--   * parsers    = stdpath('data')/site（tree-sitter typescript/tsx 等）
local here = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')   -- .../tests
local root = here:match('(.*)/[^/]*$')                                  -- 插件根
local vendors = root:match('(.*)/[^/]*$')                               -- 并列插件所在目录

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.env.VV_UTILS or (vendors .. '/vv-utils.nvim'))
vim.opt.runtimepath:append(vim.fn.stdpath('data') .. '/site')

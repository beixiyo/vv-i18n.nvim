-- vv-i18n.writer golden 回归：仓库内 fixture + 内联用例（仅依赖同级 vv-utils）
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')   -- 自定位 rtp

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local W = require('vv-i18n.writer')
local HERO = H.fixture('ns-app/src/components/Hero/locales/zh-CN.ts')

local check, done = H.checker()

-- 返回 (公共前缀长, a 的差异中段, b 的差异中段)
local function diff_span(a, b)
  local la, lb = #a, #b
  local p = 0
  while p < la and p < lb and a:byte(p + 1) == b:byte(p + 1) do p = p + 1 end
  local s = 0
  while s < (la - p) and s < (lb - p) and a:byte(la - s) == b:byte(lb - s) do s = s + 1 end
  return p, a:sub(p + 1, la - s), b:sub(p + 1, lb - s)
end

local src = H.read(HERO)
check('fixture 读取', #src > 0)

-- T1 改已有值（单引号普通字符串）
local r1 = W.update_in_content(src, { 'hero', 'title' }, '英雄★')
check('① 改值 ok', r1.ok, r1.reason)
if r1.ok then
  check('① 新值就位', r1.content:find("title: '英雄★'", 1, true) ~= nil)
  check('① 旧值消失', r1.content:find("title: '英雄'", 1, true) == nil)
  check('① as const 保全', r1.content:find('as const', 1, true) ~= nil)
  check('① 回填后逐字节 == 原文', r1.content:gsub("title: '英雄★'", "title: '英雄'", 1) == src)
end

-- T2 改含 {{count}} 插值占位的值（内联，应作普通 string）
local tpl_count = "export const x = {\n  msg: '已过滤 {{count}} 项',\n} as const\n"
local r2 = W.update_in_content(tpl_count, { 'msg' }, '共 {{count}} 项')
check('② 改 {{}} 值 ok', r2.ok, r2.reason)
if r2.ok then
  check('② {{count}} 占位保留', r2.content:find("msg: '共 {{count}} 项'", 1, true) ~= nil)
end

-- T3 在既有对象内加叶子键（Hero 用尾逗号风格 → 纯插入）
local r3 = W.add_in_content(src, { 'hero', 'newBtn' }, '新按钮')
check('③ 加叶子键 ok', r3.ok, r3.reason)
if r3.ok then
  check('③ 含新键', r3.content:find("newBtn: '新按钮'", 1, true) ~= nil)
  local _, a = diff_span(src, r3.content)
  check('③ 纯插入（无内容被删）', a:match('^[%s,]*$') ~= nil, '[' .. a .. ']')
  check('③ 既有兄弟键完好', r3.content:find("cta: '开始使用'", 1, true) ~= nil)
end

-- T4 加嵌套链（中间层不存在 → 自动建）
local r4 = W.add_in_content(src, { 'hero', 'brandNewSection', 'deep', 'leaf' }, '深值')
check('④ 加嵌套链 ok', r4.ok, r4.reason)
if r4.ok then
  check('④ 含中间层', r4.content:find('brandNewSection: {', 1, true) ~= nil)
  check('④ 含叶子', r4.content:find("leaf: '深值'", 1, true) ~= nil)
end

-- T5 拒绝重复键
local r5 = W.add_in_content(src, { 'hero', 'title' }, 'X')
check('⑤ 拒绝重复键', (not r5.ok) and r5.reason == 'key-exists', r5.reason)

-- T6 拒绝模板字面量插值值（内联）
local tpl = 'export const x = {\n  a: `hi ${name}`,\n} as const\n'
local r6 = W.update_in_content(tpl, { 'a' }, 'new')
check('⑥ 拒绝 ${} 模板插值', (not r6.ok) and r6.reason == 'template-interpolation-unsupported', r6.reason)

-- T7 文件封装 dry-run（只读不落盘）
local r7 = W.update_file(HERO, { 'hero', 'title' }, 'X', { dry_run = true })
check('⑦ update_file dry-run ok（未落盘）', r7.ok, r7.reason)
check('⑦ 真实文件未被改动', H.read(HERO) == src)

-- T8 无尾逗号风格的加键（内联）
local nc = "export const x = {\n  a: '1'\n} as const\n"
local r8 = W.add_in_content(nc, { 'b' }, '2')
check('⑧ 无尾逗号风格加键 ok', r8.ok, r8.reason)
if r8.ok then
  check('⑧ 给前键补逗号 + 新键', r8.content:find("a: '1',", 1, true) and r8.content:find("b: '2'", 1, true))
end

-- T9 引号风格自动推断（S1）：双引号文件加键 → 新键也用双引号
local dq = 'export const x = {\n  a: "1",\n} as const\n'
local r9 = W.add_in_content(dq, { 'b' }, '2')
check('⑨ 双引号文件 add ok', r9.ok, r9.reason)
if r9.ok then
  check('⑨ 新键用双引号（auto 推断）', r9.content:find('b: "2"', 1, true) ~= nil
    and r9.content:find("b: '2'", 1, true) == nil)
end

-- T10 引号风格显式覆盖：单引号文件强制 double
local r10 = W.add_in_content(nc, { 'c' }, '3', nil, { quote_style = 'double' })
check('⑩ quote_style=double 覆盖', r10.ok and r10.content:find('c: "3"', 1, true) ~= nil, r10.reason)

done()
vim.cmd('qa!')

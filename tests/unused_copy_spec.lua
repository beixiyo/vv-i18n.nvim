-- unused 默认 Markdown 渲染：复制给 LLM 的内容必须包含证据和完整盲区
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')

local H = dofile(debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$') .. '/helper.lua')
local Copy = require('vv-i18n.unused.copy')
local Model = require('vv-i18n.unused.model')
local check, done = H.checker()

local report = Model.analyze({
  tree = {
    { mount = 'cards', keys = {
      { full = 'cards.old.title', rel = 'old.title', missing = {}, per = {
        ['en-US'] = { file = '/project/locales/en.json', row = 4, col = 2, value = 'Old title', kind = 'string' },
        ['zh-CN'] = { file = '/project/locales/zh.json', row = 4, col = 2, value = '旧标题', kind = 'string' },
      } },
    } },
  },
  references = { ['cards.old.title'] = {} },
  scan = { root = '/project', status = 'complete', files = 12, parsed = 11, parse_failures = { 'broken.ts' }, extensions = { 'ts', 'tsx' } },
})
local rendered = Copy.render_default(report)

check('默认复制内容是中文紧凑 Markdown', rendered:find('# i18n 潜在无用 key 审查', 1, true) ~= nil
  and rendered:find('## 候选', 1, true) ~= nil
  and rendered:find('## 静态分析盲区', 1, true) ~= nil
  and rendered:find('直接删除高置信度无用 key', 1, true) ~= nil
  and rendered:find('## 审查要求', 1, true) == nil)
check('项目绝对路径只在顶部出现且定义使用相对路径', rendered:find('项目：`/project`', 1, true) ~= nil
  and rendered:find('locales/en.json:5:3', 1, true) ~= nil
  and rendered:find('/project/locales/en.json', 1, true) == nil)
check('默认只展示英文定义且不重复语言标签', rendered:find('locales/en.json:5:3', 1, true) ~= nil
  and rendered:find('locales/zh.json', 1, true) == nil
  and rendered:find('[en-US]', 1, true) == nil
  and rendered:find('Old title', 1, true) == nil
  and rendered:find('旧标题', 1, true) == nil)
check('候选包含扫描元数据和完整盲区清单', rendered:find('/project', 1, true) ~= nil
  and rendered:find('动态变量', 1, true) ~= nil
  and rendered:find('其他仓库', 1, true) ~= nil)

local zh_rendered = Copy.render_default(vim.tbl_extend('force', vim.deepcopy(report), {
  copy = { definition_language = 'zh-CN', include_values = true },
}))
check('可指定定义语言并展示对应 value', zh_rendered:find('locales/zh.json:5:3', 1, true) ~= nil
  and zh_rendered:find('旧标题', 1, true) ~= nil
  and zh_rendered:find('locales/en.json', 1, true) == nil)

local all_rendered = Copy.render_default(vim.tbl_extend('force', vim.deepcopy(report), {
  copy = { definition_language = 'all' },
}))
check('definition_language=all 展示全部定义路径且不重复语言标签',
  all_rendered:find('locales/en.json:5:3', 1, true) ~= nil
    and all_rendered:find('locales/zh.json:5:3', 1, true) ~= nil
    and all_rendered:find('[en-US]', 1, true) == nil
    and all_rendered:find('[zh-CN]', 1, true) == nil)

local fallback_rendered = Copy.render_default(vim.tbl_extend('force', vim.deepcopy(report), {
  copy = { definition_language = 'fr-FR' },
}))
check('指定语言缺失时稳定回退首个语言', fallback_rendered:find('locales/en.json:5:3', 1, true) ~= nil
  and fallback_rendered:find('locales/zh.json', 1, true) == nil)

local dynamic_report = Model.analyze({
  tree = {
    { mount = 'cards', keys = {
      { full = 'cards.dynamic.title', rel = 'dynamic.title', per = {
        ['en-US'] = { file = 'locales/en.json', row = 8, col = 2, value = 'Dynamic title', kind = 'string' },
      } },
    } },
  },
  references = { ['cards.dynamic.title'] = {} },
  scan = { root = '/project', status = 'complete' },
  dynamic_evidence = {
    ['cards.dynamic.*'] = { { relative = 'src/Card.tsx', row = 13, col = 4,
      line = 't(`cards.dynamic.${key}`)' } },
  },
})
local dynamic_rendered = Copy.render_default(dynamic_report)
check('无法判断的 key 复制时包含动态调用位置',
  dynamic_rendered:find('cards.dynamic.title', 1, true) ~= nil
    and dynamic_rendered:find('src/Card.tsx:13:5', 1, true) ~= nil
    and dynamic_rendered:find('`[D]` 动态翻译调用可能匹配该 key', 1, true) ~= nil
    and dynamic_rendered:find('[D]; 动态证据：', 1, true) ~= nil)

check('空上下文仍稳健返回 Markdown', type(Copy.render_default()) == 'string'
  and Copy.render_default({ candidates = {} }):find('- 无', 1, true) ~= nil)

done()
vim.cmd('qa!')

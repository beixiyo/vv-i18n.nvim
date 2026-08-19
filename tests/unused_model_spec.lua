-- unused 候选模型：只验证「未命中引用」候选，不把结果升级成绝对结论
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')

local H = dofile(debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$') .. '/helper.lua')
local Model = require('vv-i18n.unused.model')
local check, done = H.checker()

local tree = {
  {
    mount = 'common',
    keys = {
      {
        full = 'common.keep',
        rel = 'keep',
        missing = {},
        per = { ['en-US'] = { file = 'locales/en.json', row = 2, col = 4, value = 'Keep me', kind = 'string', line = 'keep: Keep me' } },
      },
      {
        full = 'common.old',
        rel = 'old',
        missing = { 'zh-CN' },
        per = {
          ['en-US'] = { file = 'locales/en.json', row = 8, col = 4, value = 'Old', kind = 'string', line = 'old: Old' },
          ['zh-CN'] = { file = 'locales/zh.json', row = 8, col = 4, value = '旧', kind = 'string', line = 'old: 旧' },
        },
      },
    },
  },
}

local candidates = Model.build(tree, {
  ['common.keep'] = { { file = 'src/a.ts', row = 1, col = 2 } },
  ['common.old'] = {},
}, {
  scan = { root = '/project', files = 4, status = 'complete' },
})

check('只返回引用为空的候选', #candidates == 1 and candidates[1].full == 'common.old')
check('候选保留兼容字段', candidates[1].status == 'candidate-unused'
  and candidates[1].full_key == 'common.old'
  and candidates[1].mount == 'common'
  and candidates[1].missing[1] == 'zh-CN'
  and candidates[1].per['en-US'].value == 'Old'
  and #candidates[1].refs == 0)
check('候选保留定义位置和值', candidates[1].definitions[1].file == 'locales/en.json'
  and candidates[1].definitions[1].row == 8
  and candidates[1].definitions[1].value == 'Old'
  and candidates[1].definitions[1].context == 'old: Old')
check('候选带相邻 key 便于外部核查', #candidates[1].related_keys == 1
  and candidates[1].related_keys[1] == 'common.keep')

local report = Model.analyze({ tree = tree, references = { ['common.old'] = {} }, scan = { status = 'complete' } })
check('完整分析报告保留扫描状态和统计', report.stats.total == 2
  and report.stats.used == 0
  and report.stats.candidates == 2
  and vim.tbl_contains(report.limitations, '动态变量、模板插值、字符串拼接、条件分支或函数返回值生成的 key')
  and vim.tbl_contains(report.limitations, '其他仓库、共享包、已发布 npm 包或部署后服务中的消费者'))

local unknown = Model.analyze({ tree = tree, scan = { status = 'complete' } })
check('缺少引用查询时不伪造未使用结论', #unknown.candidates == 0
  and #unknown.unknown == 2
  and unknown.unknown[1].status == 'unknown')

local overlapping = Model.analyze({
  tree = {
    { source_id = 1, mount = 'common', keys = { tree[1].keys[2] } },
    { source_id = 2, mount = 'common', keys = { tree[1].keys[2] } },
  },
  references = { ['common.old'] = {} },
  scan = { status = 'complete' },
})
check('跨 source 同名 key 不进入可删除候选', #overlapping.candidates == 0
  and #overlapping.unknown == 1
  and overlapping.unknown[1].unknown_reason:find('multiple locale sources', 1, true) ~= nil)

local read_only = Model.analyze({
  tree = { { source_id = 1, writable = false, mount = 'common', keys = { tree[1].keys[2] } } },
  references = { ['common.old'] = {} },
  scan = { status = 'complete' },
})
check('自定义只读 parser 的 key 不进入可删除候选', #read_only.candidates == 0
  and #read_only.unknown == 1
  and read_only.unknown[1].unknown_reason:find('read-only custom parser', 1, true) ~= nil)

local dynamic = Model.analyze({
  tree = tree,
  references = { ['common.keep'] = {}, ['common.old'] = {} },
  dynamic_evidence = {
    ['common.*'] = { { file = 'src/dynamic.ts', row = 4, col = 8, line = 't(`common.${key}`)' } },
  },
  scan = { status = 'complete' },
})
check('动态前缀覆盖的 key 不进入可删除候选', #dynamic.candidates == 0
  and #dynamic.unknown == 2
  and dynamic.stats.unknown == 2)
check('动态前缀证据保留调用位置', dynamic.unknown[1].dynamic_evidence[1].file == 'src/dynamic.ts'
  and dynamic.unknown[1].unknown_reason:find('dynamic translation call', 1, true) ~= nil)

local scanning = Model.analyze({
  tree = tree,
  references = { ['common.keep'] = {}, ['common.old'] = {} },
  scan = { status = 'scanning' },
})
check('引用扫描未完成时不把全局状态复制到每个 key', #scanning.candidates == 0
  and #scanning.unknown == 0 and scanning.stats.total == 2)

local non_string = Model.analyze({
  tree = { { mount = 'common', keys = {
    { full = 'common.plural', per = { ['en-US'] = { kind = 'plural', value = '{}' } } },
    { full = 'common.array', per = { ['en-US'] = { kind = 'array', value = '[]' } } },
    { full = 'common.other', per = { ['en-US'] = { kind = 'other', value = 'value' } } },
  } } },
  references = { ['common.plural'] = {}, ['common.array'] = {}, ['common.other'] = {} },
  scan = { status = 'complete' },
})
check('plural/array/非字符串定义都归入 unknown', #non_string.candidates == 0
  and #non_string.unknown == 3
  and non_string.unknown[1].unknown_reason:find('not a deletable string', 1, true) ~= nil)

done()
vim.cmd('qa!')

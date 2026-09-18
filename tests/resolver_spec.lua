-- vv-i18n.resolver：三布局调用点解析 + make_namespace + 端到端
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')   -- 自定位 rtp

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local ast = require('vv-i18n.ast')
local resolver = require('vv-i18n.resolver')
local Index = require('vv-i18n.index')
local Query = require('vv-i18n.service.query')

local check, done = H.checker()

local function locate(content, needle)
  local row = 0
  for line in (content .. '\n'):gmatch('([^\n]*)\n') do
    local s = line:find(needle, 1, true)
    if s then return row, s - 1 end
    row = row + 1
  end
end

--------------------------------------------------------------------------------
-- A. top-key + two-level（useT() → app、useT('common') → app.common）
--------------------------------------------------------------------------------
local A = { lang = 'tsx', namespace_resolver = resolver.make_namespace('two-level', 'app', '.'), hook_names = { useT = true } }
local home = H.read(H.fixture('ns-app/src/pages/Home.tsx'))

local r1, c1 = locate(home, 'hero.title')
local res1 = resolver.resolve_in_content(home, r1, c1, A)
check('A useT() → app.hero.title', res1.ok and res1.full_key == 'app.hero.title', res1.full_key)

local r2, c2 = locate(home, "'ok'")
local res2 = resolver.resolve_in_content(home, r2, c2 + 1, A)
check('A useT(common) → app.common.ok', res2.ok and res2.full_key == 'app.common.ok', res2.full_key)

--------------------------------------------------------------------------------
-- B. filename + hook-arg（useTranslation('common') → common.x）
--------------------------------------------------------------------------------
local B = { lang = 'tsx', namespace_resolver = resolver.make_namespace('hook-arg', '', '.'), hook_names = { useTranslation = true } }
local appB = H.read(H.fixture('file-ns/src/App.tsx'))
local rb, cb = locate(appB, "'ok'")
local resB = resolver.resolve_in_content(appB, rb, cb + 1, B)
check('B useTranslation(common) → common.ok', resB.ok and resB.full_key == 'common.ok', resB.full_key)

--------------------------------------------------------------------------------
-- C. flat（namespace='flat' → 无前缀，字面量即全键）
--------------------------------------------------------------------------------
local C = { lang = 'tsx', namespace_resolver = resolver.make_namespace('flat', '', '.'), hook_names = { useTranslation = true } }
local appC = H.read(H.fixture('flat-app/src/App.tsx'))
local rc, cc = locate(appC, 'greeting.hello')
local resC = resolver.resolve_in_content(appC, rc, cc, C)
check('C flat → greeting.hello（无前缀）', resC.ok and resC.full_key == 'greeting.hello', resC.full_key)
check('C prefix 为 nil', resC.prefix == nil)

--------------------------------------------------------------------------------
-- make_namespace 四预设单测
--------------------------------------------------------------------------------
local function ns(spec, prefix, ctx) return resolver.make_namespace(spec, prefix, '.')(ctx) end
check('preset flat → nil', ns('flat', 'app', { hook_arg = 'x' }) == nil)
check('preset fixed → prefix', ns('fixed', 'app', { hook_arg = 'x' }) == 'app')
check('preset hook-arg(无前缀) → arg', ns('hook-arg', '', { hook_arg = 'common' }) == 'common')
check('preset hook-arg(有前缀) → prefix.arg', ns('hook-arg', 'app', { hook_arg = 'common' }) == 'app.common')
check('preset two-level(无参) → prefix', ns('two-level', 'app', {}) == 'app')
check('preset two-level(有参) → prefix.arg', ns('two-level', 'app', { hook_arg = 'common' }) == 'app.common')
local custom_namespace = resolver.make_namespace(function(ctx)
  return ctx.hook_name == 'useT' and 'custom.' .. (ctx.hook_arg or 'root') or nil
end, '', '.')
local custom_result = resolver.resolve_in_content(home, r2, c2 + 1, {
  lang = 'tsx', namespace_resolver = custom_namespace, hook_names = { useT = true },
})
check('自定义 namespace 函数参与真实调用解析', custom_result.ok and custom_result.full_key == 'custom.common.ok')

--------------------------------------------------------------------------------
-- 负路径
--------------------------------------------------------------------------------
local plain = "const a = foo('not.key')\n"
local rp, cp = locate(plain, 'not.key')
check('非 t 调用 not-in-t-call', (not resolver.resolve_in_content(plain, rp, cp, A).ok), nil)
local dyn = "const t = useT()\nconst x = t(`hero.${k}`)\n"
local rd, cd = locate(dyn, 'hero.')
local dyn_res = resolver.resolve_in_content(dyn, rd, cd, A)
check('动态 key dynamic-key', dyn_res.reason == 'dynamic-key')
check('动态 key 保留可证明的固定前缀', dyn_res.dynamic_prefix == 'app.hero.', dyn_res.dynamic_prefix)
local dyn_all = resolver.collect_in_content(dyn, A)
check('整文枚举保留动态前缀证据', #dyn_all == 1
  and dyn_all[1].dynamic_prefix == 'app.hero.')
local no_fixed = "const t = useT()\nconst x = t(`${prefix}${key}`)\n"
local no_fixed_result = resolver.collect_in_content(no_fixed, A)[1]
check('以插值开头的模板不伪造字面前缀', no_fixed_result
  and no_fixed_result.dynamic_literal_prefix == '')

--------------------------------------------------------------------------------
-- D. 字符串转义：调用侧与 locale 侧使用同一运行时文本
--------------------------------------------------------------------------------
local escaped = [[const t = useT()
const x = t('hero.\u0074itle')
]]
local re, ce = locate(escaped, '\\u0074itle')
local escaped_result = resolver.resolve_in_content(escaped, re, ce, A)
check('静态字符串解码 unicode 转义', escaped_result.ok and escaped_result.full_key == 'app.hero.title', escaped_result.full_key)
local decoded, decoded_reliable = ast.decode_string([["hero.\u0074itle"]])
check('ast 解码结果标记可靠', decoded == 'hero.title' and decoded_reliable)
check('locale key strip_quotes 也按运行时解码', ast.strip_quotes([["hero.\u0074itle"]]) == 'hero.title')

local escaped_dynamic = [[const t = useT()
const x = t(`hero.\u0074i${key}`)
]]
local red, ced = locate(escaped_dynamic, '\\u0074i')
local escaped_dynamic_result = resolver.resolve_in_content(escaped_dynamic, red, ced, A)
check('动态固定前缀解码 unicode 转义', escaped_dynamic_result.dynamic_prefix == 'app.hero.ti', escaped_dynamic_result.dynamic_prefix)

local unreliable_dynamic = [[const t = useT()
const x = t(`hero.\u{110000}${key}`)
]]
local rud, cud = locate(unreliable_dynamic, '\\u{110000}')
local unreliable_result = resolver.resolve_in_content(unreliable_dynamic, rud, cud, A)
check('非法转义不伪造动态前缀', unreliable_result.unsafe_dynamic and unreliable_result.reason == 'unreliable-key', unreliable_result.reason)
check('非法转义可被整文收集为安全证据', resolver.collect_in_content(unreliable_dynamic, A)[1].unsafe_dynamic)

check('路径语言推断集中在 ast', ast.lang_for_path('x.TSX') == 'tsx'
  and ast.lang_for_path('x.MJS') == 'javascript')
check('filetype 语言推断集中在 ast', ast.lang_for_filetype('typescriptreact') == 'tsx'
  and ast.lang_for_filetype('javascript') == 'javascript')

--------------------------------------------------------------------------------
-- E. 多 source 聚合：同一调用的歧义不能被 row:col 覆盖
--------------------------------------------------------------------------------
local function fake_index(entries)
  local index = { entries = entries, all_keys_calls = 0 }
  function index:any_keys() return next(self.entries) ~= nil end
  function index:all_keys()
    self.all_keys_calls = self.all_keys_calls + 1
    local out = {}
    for key in pairs(self.entries) do out[#out + 1] = key end
    table.sort(out)
    return out
  end
  function index:get(full_key) return self.entries[full_key] end
  function index:owns(full_key) return self.entries[full_key] ~= nil end
  return index
end

local function query_source(namespace, index)
  return {
    index = index,
    ropts = {
      namespace_resolver = resolver.make_namespace('fixed', namespace, '.'),
      namespace_separator = ':',
      key_separator = '.',
      t_functions = { t = true },
      hook_names = { useT = true },
    },
  }
end

local common_entry = { ['en-US'] = { value = 'ok' } }
local app_index = fake_index({ ['app.ok'] = common_entry })
local common_index = fake_index({ ['common.ok'] = common_entry })
local query_state = { indexes = {
  query_source('app', app_index),
  query_source('common', common_index),
} }
local ambiguous_results = Query.collect_content(query_state, {}, "const t = useT()\nt('ok')", 'fixture.ts')
local ambiguous = ambiguous_results[1]
check('多 source 不覆盖不同 full key', ambiguous and ambiguous.kind == 'ambiguous'
  and #ambiguous.full_keys == 2 and ambiguous.full_keys[1] == 'app.ok'
  and ambiguous.full_keys[2] == 'common.ok', ambiguous and ambiguous.kind)
check('歧义结果保留 source_ids/candidates', ambiguous and #ambiguous.source_ids == 2
  and #ambiguous.candidates == 2)

-- 回归：路径作用域。配了 root 的 source 只认领 root 下的文件；
-- 修复前：ns-app 文件里的 t('ok') 会被 file-ns 源凭 no-binding 前缀解析成另一个 key，
-- 整体判 ambiguous → 行内预览/引用计数全部丢失（同一 root 内互斥包彼此污染）
local scoped_state = { indexes = {
  vim.tbl_extend('force', query_source('app', app_index), { root_path = H.fixture('ns-app') }),
  vim.tbl_extend('force', query_source('common', common_index), { root_path = H.fixture('file-ns') }),
} }
local scoped_content = "const t = useT()\nt('ok')"
local ns_results = Query.collect_content(scoped_state, {}, scoped_content, H.fixture('ns-app/src/pages/Home.tsx'))
check('root 内文件只由该 source 解析并命中', ns_results[1] and ns_results[1].kind == 'hit'
  and ns_results[1].full_key == 'app.ok', ns_results[1] and ns_results[1].kind)
check('命中保留全量列表 source_id 编号', ns_results[1] and ns_results[1].source_id == 1,
  ns_results[1] and ns_results[1].source_id)
local file_ns_results = Query.collect_content(scoped_state, {}, scoped_content, H.fixture('file-ns/src/App.tsx'))
check('另一 root 内文件由另一 source 认领', file_ns_results[1] and file_ns_results[1].kind == 'hit'
  and file_ns_results[1].full_key == 'common.ok', file_ns_results[1] and file_ns_results[1].full_key)
check('跨 root 认领仍按全量 source_id 归属', file_ns_results[1] and file_ns_results[1].source_id == 2,
  file_ns_results[1] and file_ns_results[1].source_id)
-- 绝对命名空间 ns:key 前缀无关，豁免辖区过滤：辖区外 source 仍能提供命中，
-- 修复前会被一刀切丢弃导致预览与引用计数丢失
local abs_results = Query.collect_content(scoped_state, {}, "const t = useT()\nt('common:ok')",
  H.fixture('ns-app/src/pages/Home.tsx'))
check('绝对命名空间跨 root 仍命中', abs_results[1] and abs_results[1].kind == 'hit'
  and abs_results[1].full_key == 'common.ok', abs_results[1] and abs_results[1].kind)
local outside_results = Query.collect_content(scoped_state, {}, scoped_content, H.fixture('flat-app/src/App.tsx'))
check('任何 root 外的文件回退全 source 尝试（保留歧义保护）', outside_results[1]
  and outside_results[1].kind == 'ambiguous' and #outside_results[1].full_keys == 2,
  outside_results[1] and outside_results[1].kind)

local dynamic_index = fake_index({ ['app.hero.title'] = common_entry, ['app.hero.body'] = common_entry })
local dynamic_state = { indexes = { query_source('app', dynamic_index) } }
local dynamic_results = Query.collect_content(dynamic_state, {}, [[const t = useT()
const a = t(`hero.${key}`)
const b = t(`hero.${other}`)
]], 'fixture.ts')
local dynamic_count = 0
for _, result in ipairs(dynamic_results) do
  if result.kind == 'dynamic' then dynamic_count = dynamic_count + 1 end
end
check('多个动态调用各自保留完整且不重复的候选', dynamic_count == 2
  and dynamic_results[1].pattern == 'app.hero.*'
  and dynamic_results[2].pattern == 'app.hero.*')

local unsafe_index = fake_index({ ['app.hero.title'] = common_entry })
local unsafe_state = { indexes = { query_source('app', unsafe_index) } }
local unsafe_results = Query.collect_content(unsafe_state, {}, [[const t = useT()
const x = t(`hero.\u12${key}`)
]], 'fixture.ts')
check('不可靠转义转换为全局动态保护', unsafe_results[1] and unsafe_results[1].kind == 'dynamic'
  and unsafe_results[1].unsafe and unsafe_results[1].pattern == '*')

--------------------------------------------------------------------------------
-- 端到端：resolver → index（三布局各命中）
--------------------------------------------------------------------------------
local idxA = Index.build({ dirs = Index.discover_by_patterns(H.fixture('ns-app/src'), { 'components/*/locales', 'i18n/common' }), prefix = 'app', mount = 'top-key', lang = '{lang}.ts' })
check('A resolver→index', idxA:get(res1.full_key) ~= nil)
local idxB = Index.build({ dirs = Index.discover_by_patterns(H.fixture('file-ns/src'), { 'locales' }), prefix = '', mount = 'filename', lang = '{lang}/{ns}.json' })
check('B resolver→index', idxB:get(resB.full_key) ~= nil)
local idxC = Index.build({ dirs = Index.discover_by_patterns(H.fixture('flat-app'), { 'locales' }), prefix = '', mount = 'flat', lang = '{lang}.ts' })
check('C resolver→index', idxC:get(resC.full_key) ~= nil and idxC:get(resC.full_key)['zh-CN'].value == '你好')

done()
vim.cmd('qa!')

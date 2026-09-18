-- vv-i18n unused 候选分析
--
-- 这里故意只做数据转换：静态扫描没有找到引用，只能产生候选，不能证明键
-- 绝对未使用。UI、扫描生命周期和删除事务由上层模块负责

local M = {}

local LIMITATIONS = {
  '动态变量、模板插值、字符串拼接、条件分支或函数返回值生成的 key',
  '有限枚举、对象映射、数组 fallback 和 computed property 生成的 key',
  'key 存放在 schema、菜单、路由元数据或组件 props 中，稍后才由通用组件消费',
  '翻译函数 alias、wrapper、参数传递、返回值、bind/call/apply 或可选调用',
  'computed member（translator[method]）和 tagged template 等非普通调用语法',
  '未建模的同名函数、全局函数或没有 hook 绑定的 t() 可能产生误报或漏报',
  '自定义 hook、自研 i18n 适配层和运行时注入的翻译函数',
  '动态 namespace、namespace 数组、ns options、fallbackNS 和 keyPrefix',
  'i18n.t(key, options) 中由 options 决定 namespace 或 fallback 的情况',
  'Trans、FormattedMessage 及其他声明式翻译组件的静态和动态 i18nKey',
  'locale 文本内部的 $t(...)、嵌套翻译、插值表达式和引用链',
  '直接读取 locale 对象、导入资源对象或调用 i18n resource API',
  'plural 变体（zero/one/two/few/many/other）不应拆成独立 key',
  'context 变体、fallback key、namespace fallback 和 language fallback',
  'returnObjects=true 对父 key 的引用可能覆盖整棵子树',
  '后端、数据库、配置、插件、URL、用户输入或运行时数据产生的 key',
  '其他仓库、共享包、已发布 npm 包或部署后服务中的消费者',
  '生成代码、代码变换、宏和构建器可能使源码 key 与运行时 key 不同',
  '未纳入 sources 的目录或 source root 之外的消费者',
  '未扫描的 Vue、Svelte、HTML、Markdown、Lua、Swift、模板和配置文件',
  '多语言资源由服务端或远端配置动态下发，而本地没有定义',
  '测试、Storybook、fixture、demo 中的引用不能代表生产代码仍在使用',
  '已经不可达的死代码、未发布入口或条件编译分支会造成假使用',
  'locale 解析失败、文件读取失败或自定义 parse 返回不完整结果',
  'locale spread、导入合并、动态对象属性和生成式 locale 文件',
  '多个 source 重叠、同一 full key 多处定义或 namespace 所有权不明确',
  '扫描候选文件的 ripgrep 模式可能漏掉没有显式翻译函数名的消费者',
}

local function copy(value, seen)
  if type(value) ~= 'table' then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  return result
end

local function list(value)
  if type(value) ~= 'table' then return {} end
  local out = {}
  for index, item in ipairs(value) do out[index] = item end
  return out
end

local function as_references(source, full_key)
  if type(source) == 'function' then
    local ok, result = pcall(source, full_key)
    if ok then return type(result) == 'table' and result or {}, nil end
    return {}, tostring(result)
  end
  if type(source) == 'table' then
    if type(source.get) == 'function' then
      local ok, result = pcall(source.get, source, full_key)
      if ok then return type(result) == 'table' and result or {}, nil end
      return {}, tostring(result)
    end
    return type(source[full_key]) == 'table' and source[full_key] or {}, nil
  end
  return nil, 'reference getter is unavailable'
end

local function sort_by_key(a, b)
  return tostring(a.full_key or '') < tostring(b.full_key or '')
end

local function definition(entry, lang, group)
  entry = type(entry) == 'table' and entry or {}
  return {
    lang = lang,
    file = entry.file or entry.path,
    relative = entry.relative,
    row = entry.row,
    col = entry.col,
    value = entry.value,
    kind = entry.kind,
    context = entry.context or entry.line or entry.source,
    variants = copy(entry.variants),
    mount = group and group.mount,
  }
end

local function has_non_string_definition(definitions)
  for _, item in ipairs(definitions) do
    if item.kind ~= 'string' then return true end
  end
  return false
end

local function adjacent(group, index)
  local keys = group and group.keys or {}
  local out = {}
  for offset = -2, 2 do
    local item = keys[index + offset]
    if item and offset ~= 0 and item.full then out[#out + 1] = item.full end
  end
  return out
end

local function evidence(dynamic, key)
  if type(dynamic) ~= 'table' then return {} end
  if dynamic[key] ~= nil then return list(dynamic[key]) end
  local out = {}
  for pattern, items in pairs(dynamic) do
    if type(pattern) == 'string' and pattern:sub(-1) == '*'
        and key:sub(1, #pattern - 1) == pattern:sub(1, -2)
    then
      for _, item in ipairs(type(items) == 'table' and items or {}) do out[#out + 1] = item end
    end
  end
  return out
end

--- 将 locale tree 和引用查询转换为潜在无用键报告
---@param opts table { tree: table[], references|references_getter: function|table, scan|scan_metadata?: table, dynamic_evidence?: table }
---@return table report { candidates, unknown, stats, scan, limitations }
function M.analyze(opts)
  opts = opts or {}
  local tree = opts.tree or opts.locale_tree or {}
  local refs = opts.references or opts.references_getter
  local dynamic = opts.dynamic_evidence or opts.dynamic or ((opts.scan or opts.scan_metadata or {}).dynamic_evidence)
  local scan = copy(opts.scan or opts.scan_metadata or {})
  local scan_complete = scan.status == 'complete'
  local candidates, unknown, seen = {}, {}, {}
  local total, used = 0, 0
  local getter_available = refs ~= nil
  local ownership = {}

  for group_index, group in ipairs(type(tree) == 'table' and tree or {}) do
    for _, item in ipairs(type(group.keys) == 'table' and group.keys or {}) do
      local full_key = type(item) == 'table' and (item.full or item.full_key) or nil
      if full_key then
        ownership[full_key] = ownership[full_key] or {}
        ownership[full_key][group.source_id or group_index] = true
      end
    end
  end

  for _, group in ipairs(type(tree) == 'table' and tree or {}) do
    local keys = type(group) == 'table' and group.keys or {}
    for key_index, item in ipairs(type(keys) == 'table' and keys or {}) do
      local full_key = type(item) == 'table' and (item.full or item.full_key) or nil
      if full_key and not seen[full_key] then
        seen[full_key] = true
        total = total + 1
        local references, error = as_references(refs, full_key)
        local item_dynamic = evidence(dynamic, full_key)
        local record = {
          full_key = full_key,
          full = full_key,
          status = 'candidate-unused',
          source = group.source or group.source_id,
          source_id = group.source_id,
          writable = group.writable ~= false,
          mount = group.mount,
          rel = item.rel,
          missing = copy(item.missing or {}),
          definitions = {},
          references = copy(references or {}),
          refs = copy(references or {}),
          per = copy(item.per or {}),
          dynamic_evidence = copy(item.dynamic_evidence or item_dynamic),
          related_keys = copy(item.related_keys or adjacent(group, key_index)),
        }

        for lang, entry in pairs(item.per or {}) do
          record.definitions[#record.definitions + 1] = definition(entry, lang, group)
        end
        table.sort(record.definitions, function(a, b) return tostring(a.lang or '') < tostring(b.lang or '') end)

        if not scan_complete then
          -- 扫描中的全局状态不展开到每个 key，避免制造海量重复 unknown
        elseif vim.tbl_count(ownership[full_key] or {}) > 1 then
          record.status = 'unknown'
          record.unknown_reason = 'multiple locale sources own the same full key'
          unknown[#unknown + 1] = record
        elseif group.writable == false then
          record.status = 'unknown'
          record.unknown_reason = 'source uses a read-only custom parser'
          unknown[#unknown + 1] = record
        elseif not getter_available or error then
          record.status = 'unknown'
          record.unknown_reason = error or 'reference getter is unavailable'
          unknown[#unknown + 1] = record
        elseif has_non_string_definition(record.definitions) then
          record.status = 'unknown'
          record.unknown_reason = 'definition is not a deletable string value'
          unknown[#unknown + 1] = record
        elseif #references > 0 then
          used = used + 1
        elseif #item_dynamic > 0 then
          record.status = 'unknown'
          record.unknown_reason = 'a dynamic translation call may match this key'
          unknown[#unknown + 1] = record
        else
          candidates[#candidates + 1] = record
        end
      end
    end
  end

  table.sort(candidates, sort_by_key)
  table.sort(unknown, sort_by_key)
  local limitations = copy(LIMITATIONS)
  for _, item in ipairs(type(scan.limitations) == 'table' and scan.limitations or {}) do
    limitations[#limitations + 1] = item
  end
  return {
    candidates = candidates,
    unknown = unknown,
    stats = {
      total = total,
      used = used,
      candidates = #candidates,
      unknown = #unknown,
    },
    scan = scan,
    limitations = limitations,
  }
end

--- 兼容面板接线的简洁入口，只返回候选列表
---@param tree table[] locale tree
---@param references function|table 引用快照或 full key -> 引用 getter
---@param opts? table 额外 scan/dynamic_evidence 等元数据
---@return table[] candidates
function M.build_candidates(tree, references, opts)
  opts = copy(opts or {})
  opts.tree = tree
  opts.references = references
  return M.analyze(opts).candidates
end

-- build 的位置参数形式是公开契约；保留 analyze 作为完整报告入口
M.build = M.build_candidates

--- 返回完整的静态分析盲区清单；每次调用返回独立副本
---@return string[]
function M.limitations()
  return copy(LIMITATIONS)
end

return M

-- vv-i18n 无用 key 审计 Markdown 渲染器
--
-- 让批量复制内容与 key 数量保持合理比例：默认只输出一个项目根目录、每个 key
-- 一个选中的 locale 定义，以及根目录下的相对路径

local M = {}

local DEFAULT_LIMITATIONS = require('vv-i18n.unused.model').limitations()
local STATUS_LABELS = {
  idle = '空闲',
  scanning = '扫描中',
  complete = '已完成',
  failed = '失败',
}
local REASONS = {
  ['multiple locale sources own the same full key'] = { code = 'O', label = '多个 locale 来源定义了同一个完整 key' },
  ['source uses a read-only custom parser'] = { code = 'R', label = '来源使用只读自定义解析器，无法安全删除' },
  ['reference getter is unavailable'] = { code = 'Q', label = '引用查询不可用' },
  ['definition is not a deletable string value'] = { code = 'V', label = '定义不是可安全删除的字符串值' },
  ['a dynamic translation call may match this key'] = { code = 'D', label = '动态翻译调用可能匹配该 key' },
}

local function text(value, fallback)
  if value == nil then return fallback or '' end
  return tostring(value)
end

local function markdown(value)
  return text(value):gsub('([`\n])', { ['`'] = '\\`', ['\n'] = ' ' })
end

local function relative_path(path, root)
  if type(path) ~= 'string' or path == '' then return '<未知文件>' end
  if type(root) ~= 'string' or root == '' then return path end
  local normalized_root = vim.fs.normalize(root):gsub('/+$', '')
  local normalized_path = vim.fs.normalize(path)
  local prefix = normalized_root .. '/'
  return vim.startswith(normalized_path, prefix) and normalized_path:sub(#prefix + 1) or normalized_path
end

local function location(item, root, zero_based_row, zero_based_col)
  item = type(item) == 'table' and item or {}
  local file = item.relative or relative_path(item.file or item.path, root)
  local row = item.row ~= nil and tonumber(item.row) or nil
  local col = item.col ~= nil and tonumber(item.col) or nil
  if zero_based_row and row then row = row + 1 end
  if zero_based_col and col then col = col + 1 end
  return ('%s:%s:%s'):format(file, row or '?', col or '?')
end

local function language_matches(actual, requested)
  if actual == requested then return true end
  local base = requested:match('^([^%-_]+)$')
  return base ~= nil and (vim.startswith(actual, base .. '-') or vim.startswith(actual, base .. '_'))
end

local function selected_definitions(item, requested)
  local definitions = type(item.definitions) == 'table' and item.definitions or {}
  if requested == 'all' then return definitions end
  for _, definition in ipairs(definitions) do
    if definition.lang and language_matches(definition.lang, requested) then return { definition } end
  end
  return definitions[1] and { definitions[1] } or {}
end

local function definition_parts(item, options, root)
  local parts = {}
  for _, definition in ipairs(selected_definitions(item, options.definition_language)) do
    local part = location(definition, root, true, true)
    if options.include_values and definition.value ~= nil then
      part = part .. ' = `' .. markdown(definition.value) .. '`'
    end
    parts[#parts + 1] = part
  end
  return parts
end

local function first_evidence(item, root)
  local evidence = type(item.dynamic_evidence) == 'table' and item.dynamic_evidence[1] or nil
  if not evidence then return nil end
  -- 引用证据使用从 1 开始的行号和从 0 开始的列号
  return location(evidence, root, false, true)
end

local function item_line(item, options, root, unknown, used_reasons)
  local details = definition_parts(item, options, root)
  if unknown and item.unknown_reason then
    local reason = REASONS[item.unknown_reason]
    if reason then
      used_reasons[reason.code] = reason.label
      details[#details + 1] = '[' .. reason.code .. ']'
    else
      details[#details + 1] = markdown(item.unknown_reason)
    end
  end
  local evidence = unknown and first_evidence(item, root) or nil
  if evidence then details[#details + 1] = '动态证据：' .. evidence end
  local suffix = #details > 0 and (' — ' .. table.concat(details, '; ')) or ''
  return ('- `%s`%s'):format(markdown(item.full_key or item.key), suffix)
end

local function append_items(out, title, items, options, root, unknown, used_reasons)
  out[#out + 1] = title
  if type(items) ~= 'table' or #items == 0 then
    out[#out + 1] = '- 无'
  else
    for _, item in ipairs(items) do
      out[#out + 1] = item_line(item, options, root, unknown, used_reasons)
    end
  end
  out[#out + 1] = ''
end

local function normalized_options(ctx)
  local copy = type(ctx.copy) == 'table' and ctx.copy or {}
  local language = copy.definition_language
  if type(language) ~= 'string' or language == '' then language = 'en' end
  return {
    definition_language = language,
    include_values = copy.include_values == true,
  }
end

--- 渲染供 LLM 审查的紧凑 Markdown
---@param ctx table?
---@return string
function M.render_default(ctx)
  ctx = type(ctx) == 'table' and ctx or {}
  local scan = type(ctx.scan or ctx.scan_metadata) == 'table' and (ctx.scan or ctx.scan_metadata) or {}
  local root = scan.root or scan.project_root or '<未知项目>'
  local stats = type(ctx.stats) == 'table' and ctx.stats or {}
  local candidates = type(ctx.candidates) == 'table' and ctx.candidates or {}
  local unknown = type(ctx.unknown) == 'table' and ctx.unknown or {}
  local options = normalized_options(ctx)
  local used_reasons = {}
  local candidate_lines, unknown_lines = {}, {}
  append_items(candidate_lines, '## 候选', candidates, options, root, false, used_reasons)
  append_items(unknown_lines, '## 未知', unknown, options, root, true, used_reasons)
  local out = {
    '# i18n 潜在无用 key 审查',
    '',
    '- 项目：`' .. markdown(root) .. '`',
    ('- 扫描：%s；%s 个文件；%s 个候选；%s 个未知'):format(
      markdown(STATUS_LABELS[scan.status] or scan.status or '未知'), text(scan.files, '?'), text(stats.candidates, #candidates),
      text(stats.unknown, #unknown)),
    '- 候选仅表示静态扫描未命中引用，不能证明 key 确实未使用',
    '- 任务：直接删除高置信度无用 key，不确定项保留',
    '',
  }
  if next(used_reasons) then
    out[#out + 1] = '## 标识'
    local codes = vim.tbl_keys(used_reasons)
    table.sort(codes)
    for _, code in ipairs(codes) do out[#out + 1] = ('- `[%s]` %s'):format(code, used_reasons[code]) end
    out[#out + 1] = ''
  end
  out[#out + 1] = '## 静态分析盲区'
  for _, limitation in ipairs(ctx.limitations or DEFAULT_LIMITATIONS) do
    out[#out + 1] = '- ' .. markdown(limitation)
  end
  out[#out + 1] = ''
  vim.list_extend(out, candidate_lines)
  vim.list_extend(out, unknown_lines)
  if out[#out] == '' then table.remove(out) end
  return table.concat(out, '\n')
end

M.render = M.render_default

return M

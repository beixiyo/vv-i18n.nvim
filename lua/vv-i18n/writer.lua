-- vv-i18n.writer — tree-sitter 字节段外科写回
--
-- 用 tree-sitter 定位目标 `pair` 节点，按字节范围替换值 / 在对象内插入新键，
-- 保全 `as const` / 注释 / 其余键的逐字节不变；写入前对新文本重新 parse 验证，
-- 有语法错则放弃、不落盘。替代 yelog `add_key.lua` 用字符数括号的脆弱实现
--
-- 解析底座（find_root_object / 字节范围 / 校验 / 编码）已抽到 vv-i18n.ast 共享
local ast = require('vv-i18n.ast')
local fs = require('vv-utils.fs')

local M = {}

local byte_range = ast.byte_range
local node_text = ast.node_text
local render_key = ast.render_key
local encode = ast.encode_string
local find_root_object = ast.find_root_object
local find_pair = ast.find_pair
local validate = ast.validate

--- 取节点所在行的前导缩进
local function indent_of(content, start_byte)
  local before = content:sub(1, start_byte)
  local line = before:match('([^\n]*)$') or ''
  return line:match('^%s*') or ''
end

--------------------------------------------------------------------------------
-- 改已有值
--------------------------------------------------------------------------------

---@param content string  源文件内容
---@param key_path string[]  逐层 key（如 { 'hero', 'title' }）
---@param new_value string  真实字符串值（未转义）
---@param lang? string  默认 'typescript'
---@return { ok: boolean, content?: string, reason?: string }
function M.update_in_content(content, key_path, new_value, lang)
  lang = lang or 'typescript'
  local obj, err = find_root_object(content, lang)
  if not obj then return { ok = false, reason = err } end

  local cur = obj
  for i = 1, #key_path - 1 do
    local pair = find_pair(cur, key_path[i], content)
    if not pair then return { ok = false, reason = 'path-missing:' .. key_path[i] } end
    local v = pair:field('value')[1]
    if not v or v:type() ~= 'object' then return { ok = false, reason = 'not-object:' .. key_path[i] } end
    cur = v
  end

  local last = find_pair(cur, key_path[#key_path], content)
  if not last then return { ok = false, reason = 'key-not-found' } end
  local vnode = last:field('value')[1]
  if not vnode then return { ok = false, reason = 'no-value' } end

  local vt = vnode:type()
  if vt == 'template_string' then
    for c in vnode:iter_children() do
      if c:type() == 'template_substitution' then
        return { ok = false, reason = 'template-interpolation-unsupported' }
      end
    end
  elseif vt ~= 'string' then
    return { ok = false, reason = 'value-not-string:' .. vt }
  end

  local orig = node_text(vnode, content)
  local quote = orig:sub(1, 1)
  local literal = encode(new_value, quote)
  local sb, eb = byte_range(vnode)
  local new_content = content:sub(1, sb) .. literal .. content:sub(eb + 1)

  if not validate(new_content, lang) then
    return { ok = false, reason = 'reparse-error' }
  end
  return { ok = true, content = new_content }
end

--------------------------------------------------------------------------------
-- 新增键（必要时建中间对象层）
--------------------------------------------------------------------------------

--- 为 remaining 路径构建插入片段（最后一段是叶子值）。indent=当前缩进，unit=缩进步进
local function build_snippet(remaining, value, indent, quote, unit, lang)
  if #remaining == 1 then
    local key = lang == 'json' and encode(remaining[1], '"') or render_key(remaining[1])
    return key .. ': ' .. encode(value, quote)
  end
  local head = remaining[1]
  local rest = { unpack(remaining, 2) }
  local inner = build_snippet(rest, value, indent .. unit, quote, unit, lang)
  local key = lang == 'json' and encode(head, '"') or render_key(head)
  return key .. ': {\n' .. indent .. unit .. inner .. '\n' .. indent .. '}'
end

--- 推断目标文件既有的引号风格（取第一处 string 字面量），默认单引号
local function infer_quote(obj, content)
  local found
  local function scan(o)
    if found then return end
    for c in o:iter_children() do
      if c:type() == 'pair' then
        local v = c:field('value')[1]
        if v then
          local t = v:type()
          if t == 'string' then
            local q = node_text(v, content):sub(1, 1)
            if q == "'" or q == '"' then found = q; return end
          elseif t == 'object' then
            scan(v)
          end
        end
      end
    end
  end
  scan(obj)
  return found or "'"
end

--- 推断缩进步进（首个嵌套对象的子缩进 - 父缩进），默认两空格
local function infer_indent_unit(obj, content)
  local unit
  local function scan(o)
    if unit then return end
    for c in o:iter_children() do
      if c:type() == 'pair' then
        local v = c:field('value')[1]
        if v and v:type() == 'object' then
          local pind = indent_of(content, select(1, byte_range(c)))
          for cc in v:iter_children() do
            if cc:type() == 'pair' then
              local cind = indent_of(content, select(1, byte_range(cc)))
              if #cind > #pind then unit = cind:sub(#pind + 1); return end
            end
          end
          scan(v)
        end
      end
    end
  end
  scan(obj)
  return unit or '  '
end

--- 据 quote_style 决定引号：single/double 直给，auto/nil 推断
local function resolve_quote(obj, content, quote_style, lang)
  if lang == 'json' then return '"' end
  if quote_style == 'single' then return "'" end
  if quote_style == 'double' then return '"' end
  return infer_quote(obj, content)
end

---@param content string
---@param key_path string[]
---@param value string
---@param lang? string
---@param opts? { quote_style?: 'single'|'double'|'auto', indent?: string }  默认 auto 推断
---@return { ok: boolean, content?: string, reason?: string }
function M.add_in_content(content, key_path, value, lang, opts)
  lang = lang or 'typescript'
  opts = opts or {}
  local obj, err = find_root_object(content, lang)
  if not obj then return { ok = false, reason = err } end

  local quote = resolve_quote(obj, content, opts.quote_style, lang)
  local unit = opts.indent or infer_indent_unit(obj, content)

  -- 沿已有对象层下钻
  local cur = obj
  local idx = 1
  while idx < #key_path do
    local pair = find_pair(cur, key_path[idx], content)
    if not pair then break end
    local v = pair:field('value')[1]
    if not v or v:type() ~= 'object' then return { ok = false, reason = 'path-collision:' .. key_path[idx] } end
    cur = v
    idx = idx + 1
  end

  if idx == #key_path and find_pair(cur, key_path[#key_path], content) then
    return { ok = false, reason = 'key-exists' }
  end

  local remaining = { unpack(key_path, idx) }

  -- 收集 cur 的直接 pair 子节点
  local pairs_in = {}
  for c in cur:iter_children() do
    if c:type() == 'pair' then pairs_in[#pairs_in + 1] = c end
  end

  local new_content
  if #pairs_in == 0 then
    -- 空对象：在 { 与 } 之间插入
    local osb = select(1, byte_range(cur))
    local obj_indent = indent_of(content, osb)
    local inner_indent = obj_indent .. unit
    local snippet = build_snippet(remaining, value, inner_indent, quote, unit, lang)
    -- cur 节点文本以 '{' 开头，osb 为 '{' 的 0-based 起点 → '{' 是 1-based 第 osb+1 个字符
    new_content = content:sub(1, osb + 1)
      .. '\n' .. inner_indent .. snippet .. '\n' .. obj_indent
      .. content:sub(osb + 2)
  else
    local last_pair = pairs_in[#pairs_in]
    local lsb, leb = byte_range(last_pair)
    local indent = indent_of(content, lsb)
    local snippet = build_snippet(remaining, value, indent, quote, unit, lang)

    local tail = content:sub(leb + 1)
    local lead_comma = tail:match('^%s*,')
    if lead_comma then
      -- 既有尾逗号风格：插在该逗号之后，自身也补尾逗号
      local after = leb + #lead_comma
      new_content = content:sub(1, after)
        .. '\n' .. indent .. snippet .. ','
        .. content:sub(after + 1)
    else
      -- 无尾逗号：给上一个 pair 补逗号，自身不带尾逗号
      new_content = content:sub(1, leb)
        .. ',\n' .. indent .. snippet
        .. content:sub(leb + 1)
    end
  end

  if not validate(new_content, lang) then
    return { ok = false, reason = 'reparse-error' }
  end
  return { ok = true, content = new_content }
end

--------------------------------------------------------------------------------
-- 删除键
--------------------------------------------------------------------------------

--- 从 content 中删除指定 pair。只删除目标 pair 和它对应的逗号，保留目标前后
--- 的空白与注释；即使父对象因此变空，也不会递归删除父对象。
---
--- 逗号是 object 的匿名 tree-sitter 子节点，不通过字符串搜索猜测位置，避免
--- 把值字符串、注释或嵌套对象中的逗号误删。
---@param content string
---@param key_path string[] 逐层 key（如 { 'hero', 'title' }）
---@param lang? string 默认 'typescript'
---@param opts? table 为未来删除策略保留的选项；当前不递归清空父对象
---@return { ok: boolean, content?: string, reason?: string }
function M.delete_in_content(content, key_path, lang, opts)
  lang = lang or 'typescript'
  opts = opts or {}
  if type(key_path) ~= 'table' or #key_path == 0 then
    return { ok = false, reason = 'invalid-key-path' }
  end

  local obj, err = find_root_object(content, lang)
  if not obj then return { ok = false, reason = err } end

  local cur = obj
  for i = 1, #key_path - 1 do
    local pair = find_pair(cur, key_path[i], content)
    if not pair then return { ok = false, reason = 'path-missing:' .. key_path[i] } end
    local v = pair:field('value')[1]
    if not v or v:type() ~= 'object' then
      return { ok = false, reason = 'not-object:' .. key_path[i] }
    end
    cur = v
  end

  local target = find_pair(cur, key_path[#key_path], content)
  if not target then return { ok = false, reason = 'key-not-found' } end

  local target_start, target_end = byte_range(target)
  local children = {}
  for child in cur:iter_children() do
    children[#children + 1] = child
  end

  local target_index
  for i, child in ipairs(children) do
    if child:type() == 'pair' then
      local child_start, child_end = byte_range(child)
      if child_start == target_start and child_end == target_end then
        target_index = i
        break
      end
    end
  end
  if not target_index then return { ok = false, reason = 'pair-not-found' } end

  -- 优先使用 pair 后面的逗号；对于最后一个 pair，使用它前面的逗号
  -- pair 节点之间的注释和空白不会被纳入任一删除范围
  -- 因此相邻注释可以保留
  local comma
  for i = target_index + 1, #children do
    local child_type = children[i]:type()
    if child_type == 'pair' then break end
    if child_type == ',' then
      comma = children[i]
      break
    end
  end
  if not comma then
    for i = target_index - 1, 1, -1 do
      local child_type = children[i]:type()
      if child_type == 'pair' then break end
      if child_type == ',' then
        comma = children[i]
        break
      end
    end
  end

  local edits = { { target_start, target_end } }
  if comma then
    local comma_start, comma_end = byte_range(comma)
    edits[#edits + 1] = { comma_start, comma_end }
  end

  table.sort(edits, function(a, b) return a[1] > b[1] end)
  local new_content = content
  for _, edit in ipairs(edits) do
    new_content = new_content:sub(1, edit[1]) .. new_content:sub(edit[2] + 1)
  end

  if not validate(new_content, lang) then
    return { ok = false, reason = 'reparse-error' }
  end
  return { ok = true, content = new_content }
end

--------------------------------------------------------------------------------
-- 文件 / buffer 封装
--------------------------------------------------------------------------------

local lang_for = ast.lang_for_path

local function run_file_operation(path, opts, transform)
  opts = opts or {}
  local read_ok, content = pcall(fs.read_all, path)
  if not read_ok or not content then return { ok = false, reason = 'read-failed' } end

  local result = transform(content, lang_for(path), opts)
  if result.ok and not opts.dry_run then
    local write_ok, write_error = pcall(fs.write_all, path, result.content)
    if not write_ok then return { ok = false, reason = 'write-failed:' .. tostring(write_error) } end
  end
  return result
end

--- 改文件里某 key 的值；dry_run=true 只返回新内容不落盘
function M.update_file(path, key_path, new_value, opts)
  return run_file_operation(path, opts, function(content, lang)
    return M.update_in_content(content, key_path, new_value, lang)
  end)
end

--- 给文件新增 key；dry_run=true 只返回新内容不落盘；quote_style/indent 控制风格（默认 auto）
function M.add_file(path, key_path, value, opts)
  return run_file_operation(path, opts, function(content, lang, normalized_opts)
    return M.add_in_content(content, key_path, value, lang, {
      quote_style = normalized_opts.quote_style,
      indent = normalized_opts.indent,
    })
  end)
end

--- 删除文件里某 key；dry_run=true 只返回新内容不落盘。
--- 默认不递归清空删除后变空的父对象。
function M.delete_file(path, key_path, opts)
  return run_file_operation(path, opts, function(content, lang, normalized_opts)
    return M.delete_in_content(content, key_path, lang, normalized_opts)
  end)
end

return M

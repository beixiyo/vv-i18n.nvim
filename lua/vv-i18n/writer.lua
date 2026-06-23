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
local strip_quotes = ast.strip_quotes
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
local function build_snippet(remaining, value, indent, quote, unit)
  if #remaining == 1 then
    return render_key(remaining[1]) .. ': ' .. encode(value, quote)
  end
  local head = remaining[1]
  local rest = { unpack(remaining, 2) }
  local inner = build_snippet(rest, value, indent .. unit, quote, unit)
  return render_key(head) .. ': {\n' .. indent .. unit .. inner .. '\n' .. indent .. '}'
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
local function resolve_quote(obj, content, quote_style)
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

  local quote = resolve_quote(obj, content, opts.quote_style)
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
    local snippet = build_snippet(remaining, value, inner_indent, quote, unit)
    -- cur 节点文本以 '{' 开头，osb 为 '{' 的 0-based 起点 → '{' 是 1-based 第 osb+1 个字符
    new_content = content:sub(1, osb + 1)
      .. '\n' .. inner_indent .. snippet .. '\n' .. obj_indent
      .. content:sub(osb + 2)
  else
    local last_pair = pairs_in[#pairs_in]
    local lsb, leb = byte_range(last_pair)
    local indent = indent_of(content, lsb)
    local snippet = build_snippet(remaining, value, indent, quote, unit)

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
-- 文件 / buffer 封装
--------------------------------------------------------------------------------

local lang_for = ast.lang_for_path

--- 改文件里某 key 的值；dry_run=true 只返回新内容不落盘
function M.update_file(path, key_path, new_value, opts)
  opts = opts or {}
  local rok, content = pcall(fs.read_all, path)
  if not rok or not content then return { ok = false, reason = 'read-failed' } end
  local r = M.update_in_content(content, key_path, new_value, lang_for(path))
  if r.ok and not opts.dry_run then
    local wok, werr = pcall(fs.write_all, path, r.content)
    if not wok then return { ok = false, reason = 'write-failed:' .. tostring(werr) } end
  end
  return r
end

--- 给文件新增 key；dry_run=true 只返回新内容不落盘；quote_style/indent 控制风格（默认 auto）
function M.add_file(path, key_path, value, opts)
  opts = opts or {}
  local rok, content = pcall(fs.read_all, path)
  if not rok or not content then return { ok = false, reason = 'read-failed' } end
  local r = M.add_in_content(content, key_path, value, lang_for(path),
    { quote_style = opts.quote_style, indent = opts.indent })
  if r.ok and not opts.dry_run then
    local wok, werr = pcall(fs.write_all, path, r.content)
    if not wok then return { ok = false, reason = 'write-failed:' .. tostring(werr) } end
  end
  return r
end

return M

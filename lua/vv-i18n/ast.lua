-- vv-i18n.ast — 共享 tree-sitter 原语
--
-- writer（写回）与 reader（读取）共用的底座：解析 TS/JS 源、定位 locale 根对象、
-- 取节点字节范围、字符串字面量编解码、重 parse 校验。集中一处避免双实现走味
--
-- 读侧解析思路（find_root_object）参考 yelog/i18n.nvim（Apache-2.0）parser.lua 的
-- find_export_object，已按本模块需要重写
local M = {}

--- 节点字节范围。`node:start()` / `node:end_()` 第 3 个返回值即字节偏移（nvim 0.13 可用）
---@param node TSNode
---@return integer start_byte 0-based, inclusive
---@return integer end_byte   0-based, exclusive
function M.byte_range(node)
  local _, _, sb = node:start()
  local _, _, eb = node:end_()
  return sb, eb
end

---@param node TSNode
---@param content string
---@return string
function M.node_text(node, content)
  return vim.treesitter.get_node_text(node, content)
end

--- 去掉成对的首尾引号（单 / 双 / 反引号）
---@param s string
---@return string
function M.strip_quotes(s)
  if #s >= 2 then
    local a, b = s:sub(1, 1), s:sub(-1)
    if (a == '"' or a == "'" or a == '`') and a == b then
      return s:sub(2, -2)
    end
  end
  return s
end

--- 把 JS 字符串字面量「文本」解码成真实字符串（处理转义）
--- 仅做单遍扫描，覆盖常见转义；未知 `\x` 原样保留反斜杠后字符
---@param literal string  含引号的字面量文本，如 "'a\\nb'"
---@return string
function M.decode_string(literal)
  local body = M.strip_quotes(literal)
  local out = {}
  local i = 1
  local n = #body
  while i <= n do
    local c = body:sub(i, i)
    if c == '\\' and i < n then
      local nx = body:sub(i + 1, i + 1)
      if nx == 'n' then out[#out + 1] = '\n'; i = i + 2
      elseif nx == 't' then out[#out + 1] = '\t'; i = i + 2
      elseif nx == 'r' then out[#out + 1] = '\r'; i = i + 2
      elseif nx == 'b' then out[#out + 1] = '\b'; i = i + 2
      elseif nx == 'f' then out[#out + 1] = '\f'; i = i + 2
      elseif nx == '0' then out[#out + 1] = '\0'; i = i + 2
      elseif nx == '\\' or nx == "'" or nx == '"' or nx == '`' or nx == '/' then
        out[#out + 1] = nx; i = i + 2
      elseif nx == 'u' then
        local hex = body:sub(i + 2):match('^%x%x%x%x')
        if hex then
          out[#out + 1] = vim.fn.nr2char(tonumber(hex, 16))
          i = i + 6
        else
          -- \u{XXXX} 形式
          local braced = body:sub(i + 2):match('^{(%x+)}')
          if braced then
            out[#out + 1] = vim.fn.nr2char(tonumber(braced, 16))
            i = i + 4 + #braced
          else
            out[#out + 1] = nx; i = i + 2
          end
        end
      elseif nx == 'x' then
        local hex = body:sub(i + 2):match('^%x%x')
        if hex then
          out[#out + 1] = vim.fn.nr2char(tonumber(hex, 16))
          i = i + 4
        else
          out[#out + 1] = nx; i = i + 2
        end
      else
        out[#out + 1] = nx; i = i + 2
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- 把真实字符串编码成目标引号风格的字面量（与 decode_string 对称）
---@param s string
---@param quote? string  "'" | '"'，默认单引号
---@return string
function M.encode_string(s, quote)
  quote = (quote == '"') and '"' or "'"
  local out = s:gsub('\\', '\\\\')
  out = out:gsub('\n', '\\n'):gsub('\t', '\\t'):gsub('\r', '\\r')
  out = out:gsub(quote, '\\' .. quote)
  return quote .. out .. quote
end

--- 合法 JS 标识符不加引号，否则单引号包裹
---@param k string
---@return string
function M.render_key(k)
  if k:match('^[%a_$][%w_$]*$') then
    return k
  end
  return "'" .. k:gsub('\\', '\\\\'):gsub("'", "\\'") .. "'"
end

--- 解析 content 得到根节点
---@param content string
---@param lang string
---@return TSNode? root
---@return string? err
function M.parse_root(content, lang)
  local ok, parser = pcall(vim.treesitter.get_string_parser, content, lang)
  if not ok or not parser then
    return nil, 'parser-init-failed'
  end
  local trees = parser:parse()
  local tree = trees and trees[1]
  if not tree then
    return nil, 'no-tree'
  end
  return tree:root(), nil
end

local function unwrap(v)
  while v and (v:type() == 'as_expression' or v:type() == 'satisfies_expression') do
    v = v:named_child(0)
  end
  return v
end

--- 解析 content 为 TS 树并返回 locale 根对象节点
--- 支持 `export const X = {...} (as const|satisfies T)` / `export default {...}` /
--- `module.exports = {...}` / 裸 `{...}`
---@param content string
---@param lang string
---@return TSNode? obj
---@return string? err
function M.find_root_object(content, lang)
  local root, err = M.parse_root(content, lang)
  if not root then return nil, err end
  if root:has_error() then return nil, 'source-has-error' end

  local function dig(node)
    for child in node:iter_children() do
      local t = child:type()
      if t == 'export_statement' or t == 'expression_statement' then
        for g in child:iter_children() do
          local gt = g:type()
          if gt == 'object' then
            return g
          elseif gt == 'lexical_declaration' or gt == 'variable_declaration' then
            for decl in g:iter_children() do
              if decl:type() == 'variable_declarator' then
                local v = unwrap(decl:field('value')[1])
                if v and v:type() == 'object' then
                  return v
                end
              end
            end
          elseif gt == 'assignment_expression' then
            local r = unwrap(g:field('right')[1])
            if r and r:type() == 'object' then
              return r
            end
          end
        end
      elseif t == 'object' then
        return child
      else
        local found = dig(child)
        if found then return found end
      end
    end
    return nil
  end

  local obj = dig(root)
  if not obj then
    return nil, 'no-root-object'
  end
  return obj, nil
end

--- 遍历 object 节点的直接 pair 子节点
---@param obj TSNode
---@return fun(): TSNode?
function M.iter_pairs(obj)
  local it = obj:iter_children()
  return function()
    while true do
      local c = it()
      if not c then return nil end
      if c:type() == 'pair' then return c end
    end
  end
end

--- 在 object 节点的直接子 pair 里找 key == seg 的那个
---@param obj TSNode
---@param seg string
---@param content string
---@return TSNode? pair
function M.find_pair(obj, seg, content)
  for pair in M.iter_pairs(obj) do
    local k = pair:field('key')[1]
    if k and M.strip_quotes(M.node_text(k, content)) == seg then
      return pair
    end
  end
  return nil
end

--- 重新 parse 校验新文本无语法错
---@param content string
---@param lang string
---@return boolean
function M.validate(content, lang)
  local root = M.parse_root(content, lang)
  if not root then return false end
  return not root:has_error()
end

--- 按扩展名推断 tree-sitter 语言
---@param path string
---@return string
function M.lang_for_path(path)
  local ext = path:match('%.([%w]+)$')
  if ext == 'tsx' then return 'tsx' end
  if ext == 'jsx' then return 'tsx' end
  if ext == 'js' or ext == 'mjs' or ext == 'cjs' then return 'javascript' end
  if ext == 'json' then return 'json' end
  return 'typescript'
end

return M

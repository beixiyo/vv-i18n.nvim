-- vv-i18n.reader — 单个 locale 文件 → 扁平叶子表
--
-- 用 tree-sitter 把 `export const zhCN = { hero: { title: '英雄' } }` 这类模块解析成
-- 扁平叶子列表，每个叶子带：
--   * path     文件内逐层 key（{'hero','title'}）—— 供 writer 精确回写
--   * dotted   点号路径（'hero.title'）—— 供索引拼全键
--   * kind     'string' | 'array' | 'other'（仅 string 可同步编辑，array/other 只读）
--   * value    string 类型时为解码后真实值；否则为原始文本
--   * row/col  值节点 0-based 起点 —— 供跳转
--
-- 顶层 key（top_keys）即该文件挂载到命名空间前缀下的二级 key
local ast = require('vv-i18n.ast')
local fs = require('vv-utils.fs')

local M = {}

--- 判定值节点类型并取出可用信息
---@param vnode TSNode
---@param content string
---@return string kind
---@return string value  string→解码值；否则原始文本
local function classify(vnode, content)
  local t = vnode:type()
  if t == 'string' then
    return 'string', ast.decode_string(ast.node_text(vnode, content))
  end
  if t == 'template_string' then
    for c in vnode:iter_children() do
      if c:type() == 'template_substitution' then
        -- 含 ${} 插值，无法当纯文本同步编辑
        return 'other', ast.node_text(vnode, content)
      end
    end
    return 'string', ast.decode_string(ast.node_text(vnode, content))
  end
  if t == 'array' then
    return 'array', ast.node_text(vnode, content)
  end
  return 'other', ast.node_text(vnode, content)
end

--- 递归收集 object 节点下的叶子
---@param obj TSNode
---@param content string
---@param prefix string[]  当前路径
---@param leaves table[]   累积列表（原地追加）
local function collect(obj, content, prefix, leaves)
  for pair in ast.iter_pairs(obj) do
    local knode = pair:field('key')[1]
    local vnode = pair:field('value')[1]
    if knode and vnode then
      local key = ast.strip_quotes(ast.node_text(knode, content))
      prefix[#prefix + 1] = key
      if vnode:type() == 'object' then
        collect(vnode, content, prefix, leaves)
      else
        local kind, value = classify(vnode, content)
        local row, col = vnode:start()
        local path = vim.list_extend({}, prefix)   -- 仅在叶子处物化一次副本
        leaves[#leaves + 1] = {
          path = path,
          dotted = table.concat(path, '.'),
          kind = kind,
          value = value,
          row = row,
          col = col,
        }
      end
      prefix[#prefix] = nil
    end
  end
end

--- 读取并解析 locale 文件内容
---@param content string
---@param lang? string  tree-sitter 语言，默认 'typescript'
---@return { ok: boolean, top_keys?: string[], leaves?: table[], reason?: string }
function M.parse_content(content, lang)
  lang = lang or 'typescript'
  local obj, err = ast.find_root_object(content, lang)
  if not obj then return { ok = false, reason = err } end

  local top_keys = {}
  for pair in ast.iter_pairs(obj) do
    local k = pair:field('key')[1]
    if k then top_keys[#top_keys + 1] = ast.strip_quotes(ast.node_text(k, content)) end
  end

  local leaves = {}
  collect(obj, content, {}, leaves)

  return { ok = true, top_keys = top_keys, leaves = leaves }
end

--- 读取 locale 文件路径
---@param path string
---@return { ok: boolean, top_keys?: string[], leaves?: table[], reason?: string }
function M.parse_file(path)
  local ok, content = pcall(fs.read_all, path)
  if not ok or not content then return { ok = false, reason = 'read-failed' } end
  return M.parse_content(content, ast.lang_for_path(path))
end

return M

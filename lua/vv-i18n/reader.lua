-- vv-i18n.reader — 单个 locale 文件 → 扁平翻译条目
--
-- 用 tree-sitter 把 `export const zhCN = { hero: { title: '英雄' } }` 这类模块解析成
-- 扁平叶子列表，每个叶子带：
--   * path     文件内逐层 key（{'hero','title'}）—— 供 writer 精确回写
--   * dotted   点号路径（'hero.title'）—— 供索引拼全键
--   * kind     'string' | 'plural' | 'array' | 'other'
--   * value    string 类型时为解码后真实值；否则为原始文本
--   * row/col  值节点 0-based 起点 —— 供跳转
--
-- 复数对象（one/other/zero/two/few/many）是一个翻译值，不是普通命名空间。它作为
-- plural 条目进入索引，variants 保留各形态供 editor 展开编辑，避免把父 key 误报缺失
--
-- 顶层 key（top_keys）即该文件挂载到命名空间前缀下的二级 key
local ast = require('vv-i18n.ast')
local fs = require('vv-utils.fs')

local M = {}

local plural_forms = {
  zero = true,
  one = true,
  two = true,
  few = true,
  many = true,
  other = true,
}

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

--- 若 obj 是 CLDR 复数对象，返回可编辑形态；普通对象返回 nil
---@param obj TSNode
---@param content string
---@param prefix string[]
---@return table[]?
local function plural_variants(obj, content, prefix)
  local variants = {}
  for pair in ast.iter_pairs(obj) do
    local knode = pair:field('key')[1]
    local vnode = pair:field('value')[1]
    if not knode or not vnode then return nil end

    local form = ast.strip_quotes(ast.node_text(knode, content))
    if not plural_forms[form] then return nil end

    local kind, value = classify(vnode, content)
    if kind ~= 'string' then return nil end
    local row, col = vnode:start()
    local path = vim.list_extend({}, prefix)
    path[#path + 1] = form
    variants[#variants + 1] = {
      form = form,
      path = path,
      kind = kind,
      value = value,
      row = row,
      col = col,
    }
  end

  if #variants == 0 then return nil end
  return variants
end

--- 递归收集 object 节点下的叶子
---@param obj TSNode
---@param content string
---@param prefix string[]  当前路径
---@param leaves table[]   可作为翻译值的条目（原地追加）
---@param objects table[]  普通结构对象（用于检测同路径已占用）
local function collect(obj, content, prefix, leaves, objects)
  for pair in ast.iter_pairs(obj) do
    local knode = pair:field('key')[1]
    local vnode = pair:field('value')[1]
    if knode and vnode then
      local key = ast.strip_quotes(ast.node_text(knode, content))
      prefix[#prefix + 1] = key
      if vnode:type() == 'object' then
        local variants = plural_variants(vnode, content, prefix)
        local row, col = vnode:start()
        local path = vim.list_extend({}, prefix)
        if variants then
          leaves[#leaves + 1] = {
            path = path,
            dotted = table.concat(path, '.'),
            kind = 'plural',
            value = ast.node_text(vnode, content),
            variants = variants,
            row = row,
            col = col,
          }
        else
          objects[#objects + 1] = {
            path = path,
            dotted = table.concat(path, '.'),
            kind = 'object',
            value = ast.node_text(vnode, content),
            row = row,
            col = col,
          }
          collect(vnode, content, prefix, leaves, objects)
        end
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
---@return { ok: boolean, top_keys?: string[], leaves?: table[], objects?: table[], reason?: string }
function M.parse_content(content, lang)
  lang = lang or 'typescript'
  local obj, err = ast.find_root_object(content, lang)
  if not obj then return { ok = false, reason = err } end

  local top_keys = {}
  for pair in ast.iter_pairs(obj) do
    local k = pair:field('key')[1]
    if k then top_keys[#top_keys + 1] = ast.strip_quotes(ast.node_text(k, content)) end
  end

  local leaves, objects = {}, {}
  collect(obj, content, {}, leaves, objects)

  return { ok = true, top_keys = top_keys, leaves = leaves, objects = objects }
end

--- 读取 locale 文件路径
---@param path string
---@return { ok: boolean, top_keys?: string[], leaves?: table[], objects?: table[], reason?: string }
function M.parse_file(path)
  local ok, content = pcall(fs.read_all, path)
  if not ok or not content then return { ok = false, reason = 'read-failed' } end
  return M.parse_content(content, ast.lang_for_path(path))
end

return M

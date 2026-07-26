---@diagnostic disable: param-type-mismatch
-- i18n 键面板的数据转换
--
-- 本模块不持有窗口或面板状态，只把插件索引转换为 tree_panel 节点

local M = {}

--- 生成无分隔符歧义的 opaque ID；调用方不得从 ID 反解业务字段
---@param kind string
---@param parts (string|number)[]
---@return string
local function node_id(kind, parts)
  local encoded = { kind }
  for _, part in ipairs(parts) do
    local value = tostring(part)
    encoded[#encoded + 1] = ('%d:%s'):format(#value, value)
  end
  return table.concat(encoded, ':')
end

local function visible_keys(group, group_by, only_missing)
  if group_by == 'missing_lang' or not only_missing then return group.keys or {} end

  local keys = {}
  for _, key in ipairs(group.keys or {}) do
    if #(key.missing or {}) > 0 then keys[#keys + 1] = key end
  end
  return keys
end

---@param tree table[]
---@return table[]
local function group_by_missing_lang(tree)
  local by_lang = {}
  for _, group in ipairs(tree or {}) do
    for _, key in ipairs(group.keys or {}) do
      for _, lang in ipairs(key.missing or {}) do
        local target = by_lang[lang]
        if not target then
          target = { mount = lang, langs = {}, keys = {}, missing_lang = lang }
          by_lang[lang] = target
        end

        local rel = key.rel
        if group.mount and group.mount ~= '(flat)' and not vim.startswith(rel, group.mount .. '.') then
          rel = group.mount .. '.' .. rel
        end

        target.keys[#target.keys + 1] = {
          full = key.full,
          rel = rel,
          per = key.per,
          missing = key.missing,
          langs = group.langs,
          target_lang = lang,
          source_mount = group.mount,
        }
      end
    end
  end

  local result = {}
  for _, group in pairs(by_lang) do
    table.sort(group.keys, function(a, b) return a.full < b.full end)
    result[#result + 1] = group
  end
  table.sort(result, function(a, b) return a.mount < b.mount end)
  return result
end

---@param source_tree? table[]
---@param group_by 'mount'|'missing_lang'
---@return table[]
function M.build(source_tree, group_by)
---@diagnostic disable-next-line: param-type-mismatch
  if group_by == 'missing_lang' then return group_by_missing_lang(source_tree) end
  return source_tree or {}
end

---@param tree? table[]
---@return string[]
function M.languages(tree)
  local seen = {}
  local languages = {}
  for _, group in ipairs(tree or {}) do
    for _, lang in ipairs(group.langs or {}) do
      if not seen[lang] then
        seen[lang] = true
        languages[#languages + 1] = lang
      end
    end
  end
  table.sort(languages)
  return languages
end

---@param tree? table[]
---@param group_by 'mount'|'missing_lang'
---@param only_missing boolean
---@param selector? { languages: string[], selected_lang?: string }
---@return VVTreePanelNode[]
function M.nodes(tree, group_by, only_missing, selector)
  local nodes = {}

  if selector and #selector.languages > 0 then
    local children = {}
    for _, lang in ipairs(selector.languages) do
      children[#children + 1] = {
        id = node_id('language', { lang }),
        label = lang,
        data = {
          kind = 'language',
          lang = lang,
          selected = lang == selector.selected_lang,
        },
      }
    end
    nodes[#nodes + 1] = {
      id = node_id('languages', { 'selector' }),
      label = 'Languages',
      selectable = false,
      children = children,
      data = { kind = 'languages', count = #children },
    }
  end

  local group_occurrences = {}
  for _, group in ipairs(tree or {}) do
    local group_name = group.missing_lang or group.mount
    local occurrence_key = node_id('group-occurrence', { group_by, group_name })
    local occurrence = (group_occurrences[occurrence_key] or 0) + 1
    group_occurrences[occurrence_key] = occurrence

    local keys = visible_keys(group, group_by, only_missing)
    if not (only_missing and #keys == 0) then
      local id = node_id('group', { group_by, group_name, occurrence })
      local children = {}
      for _, key in ipairs(keys) do
        children[#children + 1] = {
          id = node_id('key', { id, key.full }),
          label = key.rel,
          data = { kind = 'key', key = key, group = group },
        }
      end
      nodes[#nodes + 1] = {
        id = id,
        label = group.mount,
        selectable = false,
        children = children,
        data = { kind = 'group', group = group, count = #keys },
      }
    end
  end
  return nodes
end

---@param tree? table[]
---@return integer
function M.missing_total(tree)
  local seen = {}
  local total = 0
  for _, group in ipairs(tree or {}) do
    for _, key in ipairs(group.keys or {}) do
      if #(key.missing or {}) > 0 and not seen[key.full] then
        seen[key.full] = true
        total = total + 1
      end
    end
  end
  return total
end

---@param tree table[]
---@return integer total
---@return integer missing
function M.summary(tree)
  local seen = {}
  local total = 0
  local missing = 0
  for _, group in ipairs(tree or {}) do
    for _, key in ipairs(group.keys or {}) do
      if not seen[key.full] then
        seen[key.full] = true
        total = total + 1
        if #(key.missing or {}) > 0 then missing = missing + 1 end
      end
    end
  end
  return total, missing
end

return M

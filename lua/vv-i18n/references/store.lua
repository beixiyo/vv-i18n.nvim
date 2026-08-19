-- 引用证据仓库：只负责按文件原子替换、删除和读取索引数据

local M = {}

local function evidence_id(evidence)
  return table.concat({
    evidence.file or '',
    tostring(evidence.row or ''),
    tostring(evidence.col or ''),
    evidence.pattern or '',
  }, '\31')
end

local function sort_refs(refs)
  table.sort(refs, function(a, b)
    if a.relative == b.relative then
      if a.row == b.row then
        if a.col == b.col then return (a.full_key or '') < (b.full_key or '') end
        return a.col < b.col
      end
      return a.row < b.row
    end
    return a.relative < b.relative
  end)
end

local function sort_evidence(evidence)
  table.sort(evidence, function(a, b)
    if a.relative == b.relative then
      if a.row == b.row then
        if a.col == b.col then return (a.pattern or '') < (b.pattern or '') end
        return a.col < b.col
      end
      return a.row < b.row
    end
    return a.relative < b.relative
  end)
end

---@return table
function M.new()
  local data = {
    by_key = {},
    by_file = {},
    dynamic_evidence = {},
    dynamic_by_file = {},
  }

  local function remove_file(path)
    for _, ref in ipairs(data.by_file[path] or {}) do
      local items = data.by_key[ref.full_key] or {}
      for index = #items, 1, -1 do
        if items[index].file == path then table.remove(items, index) end
      end
      if #items == 0 then data.by_key[ref.full_key] = nil end
    end
    data.by_file[path] = nil

    for _, evidence in ipairs(data.dynamic_by_file[path] or {}) do
      local items = data.dynamic_evidence[evidence.pattern] or {}
      for index = #items, 1, -1 do
        if evidence_id(items[index]) == evidence_id(evidence) then table.remove(items, index) end
      end
      if #items == 0 then data.dynamic_evidence[evidence.pattern] = nil end
    end
    data.dynamic_by_file[path] = nil
  end

  local function replace_file(path, refs, dynamic_refs)
    remove_file(path)

    for _, ref in ipairs(refs or {}) do
      data.by_key[ref.full_key] = data.by_key[ref.full_key] or {}
      data.by_key[ref.full_key][#data.by_key[ref.full_key] + 1] = ref
    end
    data.by_file[path] = refs or {}

    local unique = {}
    for _, evidence in ipairs(dynamic_refs or {}) do
      local id = evidence_id(evidence)
      local previous = unique[id]
      if not previous or (evidence.literal or '') < (previous.literal or '') then
        unique[id] = evidence
      end
    end
    local deduped = vim.tbl_values(unique)
    sort_evidence(deduped)
    for _, evidence in ipairs(deduped) do
      data.dynamic_evidence[evidence.pattern] = data.dynamic_evidence[evidence.pattern] or {}
      data.dynamic_evidence[evidence.pattern][#data.dynamic_evidence[evidence.pattern] + 1] = evidence
    end
    data.dynamic_by_file[path] = deduped
  end

  return {
    clear = function()
      data.by_key = {}
      data.by_file = {}
      data.dynamic_evidence = {}
      data.dynamic_by_file = {}
    end,
    get = function(full_key)
      return data.by_key[full_key] or {}
    end,
    replace_file = replace_file,
    remove_file = remove_file,
    sort = function()
      for _, refs in pairs(data.by_key) do sort_refs(refs) end
      for _, evidence in pairs(data.dynamic_evidence) do sort_evidence(evidence) end
      for _, evidence in pairs(data.dynamic_by_file) do sort_evidence(evidence) end
    end,
    snapshot = function()
      return vim.deepcopy({
        by_key = data.by_key,
        dynamic_evidence = data.dynamic_evidence,
      })
    end,
  }
end

return M

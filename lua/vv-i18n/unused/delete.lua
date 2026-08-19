-- 潜在无用 key 的删除计划与事务执行
--
-- 纯计划阶段读取并重写内存快照；执行阶段校验引用扫描代际，再交给 vv-utils
-- 文件事务验证磁盘快照、拒绝未保存 buffer，并在部分失败时补偿回滚。

local Fs = require('vv-utils.fs')
local Writer = require('vv-i18n.writer')
local Ast = require('vv-i18n.ast')

local M = {}

---@param candidates table[]
---@param scan { generation: integer, root?: string }
---@return table? plan
---@return string? error
function M.build(candidates, scan)
  local files = {}
  for _, candidate in ipairs(candidates or {}) do
    if candidate.status ~= 'candidate-unused' or candidate.writable == false then
      return nil, candidate.full_key .. ' is not a deletable candidate'
    end
    for _, entry in pairs(candidate.per or {}) do
      if entry.kind ~= 'string' then
        return nil, ('%s contains a non-deletable %s definition'):format(candidate.full_key, tostring(entry.kind))
      end
      if not entry.file or type(entry.in_file_path) ~= 'table' then
        return nil, candidate.full_key .. ' has no writable definition location'
      end
      local file = files[entry.file]
      if not file then
        local ok, content = pcall(Fs.read_all, entry.file)
        if not ok then return nil, 'Failed to read: ' .. entry.file end
        file = { path = entry.file, old = content, new = content, paths = {}, keys = {} }
        files[entry.file] = file
      end
      local path_id = table.concat(entry.in_file_path, '\0')
      if not file.paths[path_id] then
        file.paths[path_id] = true
        file.keys[#file.keys + 1] = { full = candidate.full_key, path = entry.in_file_path }
      end
    end
  end

  local file_list = {}
  for _, file in pairs(files) do file_list[#file_list + 1] = file end
  table.sort(file_list, function(a, b) return a.path < b.path end)

  local entries, diffs = {}, {}
  for _, file in ipairs(file_list) do
    table.sort(file.keys, function(a, b)
      if #a.path ~= #b.path then return #a.path > #b.path end
      local a_path, b_path = table.concat(a.path, '\0'), table.concat(b.path, '\0')
      if a_path ~= b_path then return a_path < b_path end
      return a.full < b.full
    end)
    for _, key in ipairs(file.keys) do
      local result = Writer.delete_in_content(file.new, key.path, Ast.lang_for_path(file.path))
      if not result.ok then
        return nil, ('%s delete plan failed: %s'):format(key.full, result.reason or '?')
      end
      file.new = result.content
    end
    entries[#entries + 1] = { path = file.path, old = file.old, new = file.new }
    diffs[#diffs + 1] = vim.diff(file.old, file.new, { result_type = 'unified', ctxlen = 2 })
  end
  return {
    entries = entries,
    diff = table.concat(diffs, '\n'),
    candidates = vim.deepcopy(candidates),
    generation = scan.generation,
    root = scan.root,
    source_fingerprints = vim.deepcopy(scan.source_fingerprints or {}),
  }
end

---@param plan table
---@param scan { generation: integer, root?: string, status?: string, scanning?: boolean }
---@return boolean ok
---@return string? error
function M.apply(plan, scan)
  if scan.scanning or scan.status ~= 'complete'
      or scan.generation ~= plan.generation or scan.root ~= plan.root
  then
    return false, 'Reference scan changed; rebuild the delete plan'
  end
  for path, expected in pairs(plan.source_fingerprints or {}) do
    local ok, content = pcall(Fs.read_all, path)
    if not ok or vim.fn.sha256(content) ~= expected then
      return false, 'Reference source changed after scanning: ' .. path
    end
  end
  local transaction = Fs.new_transaction()
  local ok, err = transaction:apply(plan.entries)
  if not ok then return false, tostring(err) end
  return true
end

return M

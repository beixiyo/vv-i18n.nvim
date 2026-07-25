-- vv-i18n.editor.model — 编辑器行模型、差异计算与写回
local writer = require('vv-i18n.writer')

local M = {}

local LABEL_GAP = 3

function M.row_label(row)
  return row.label or row.lang
end

function M.lang_width(rows)
  local width = 0
  for _, row in ipairs(rows) do
    width = math.max(width, vim.fn.strdisplaywidth(M.row_label(row)))
  end
  return width
end

function M.value_col(rows)
  return M.lang_width(rows) + LABEL_GAP
end

function M.to_edit_lines(rows, value_lines)
  local col = M.value_col(rows)
  local edit_lines = {}
  for i, line in ipairs(value_lines) do
    edit_lines[i] = string.rep(' ', col) .. line
  end
  return edit_lines, col
end

function M.from_edit_lines(lines, col)
  local values = {}
  for i, line in ipairs(lines) do
    values[i] = #line >= col and line:sub(col + 1) or ''
  end
  return values
end

--- 由初始 rows + 编辑后行内容算出需要的写入操作
---@param rows table[]
---@param new_lines string[]
---@return { action: 'add'|'update', lang: string, file: string, in_file_path: string[], value: string }[]
function M.diff(rows, new_lines)
  local writes = {}
  for i, row in ipairs(rows) do
    local new = new_lines[i] or ''
    if not row.skip then
      if row.orig == nil then
        if new ~= '' then
          writes[#writes + 1] = {
            action = 'add',
            lang = M.row_label(row),
            file = row.file,
            in_file_path = row.in_file_path,
            value = new,
          }
        end
      elseif new ~= row.orig then
        writes[#writes + 1] = {
          action = 'update',
          lang = M.row_label(row),
          file = row.file,
          in_file_path = row.in_file_path,
          value = new,
        }
      end
    end
  end
  return writes
end

--- 由 plugin + 全键算出初始 rows + 行
---@param plugin table
---@param full_key string
---@return table[]? rows
---@return string[]? lines
---@return string? err
function M.plan(plugin, full_key)
  local files, err = plugin.files_for(full_key)
  if not files then return nil, nil, err end
  local per = plugin.lookup(full_key) or {}
  local rows, lines = {}, {}

  local function append_row(file, entry, label)
    local kind = entry and entry.kind or 'string'
    local skip = entry ~= nil and kind ~= 'string'
    rows[#rows + 1] = {
      lang = file.lang,
      label = label,
      file = entry and entry.file or file.file,
      in_file_path = entry and entry.in_file_path or file.in_file_path,
      orig = entry and entry.value or nil,
      kind = kind,
      skip = skip,
    }
    lines[#lines + 1] = skip and ('<' .. kind .. '>') or (entry and entry.value) or ''
  end

  for _, file in ipairs(files) do
    local entry = per[file.lang]
    if entry and entry.kind == 'plural' and #(entry.variants or {}) > 0 then
      for _, variant in ipairs(entry.variants) do
        append_row(file, {
          file = entry.file,
          in_file_path = variant.path,
          kind = variant.kind,
          value = variant.value,
        }, file.lang .. '.' .. variant.form)
      end
    else
      append_row(file, entry)
    end
  end
  return rows, lines
end

--- 执行写入；opts.dry_run 只算不落盘
---@param writes table[]
---@param opts? { dry_run?: boolean, quote_style?: string, indent?: string }
---@return integer changed
---@return string[] fails
---@return table[] applied
function M.apply(writes, opts)
  opts = opts or {}
  local writer_opts = {
    dry_run = opts.dry_run,
    quote_style = opts.quote_style,
    indent = opts.indent,
  }
  local changed, fails, applied = 0, {}, {}

  for _, write in ipairs(writes) do
    local result = write.action == 'add'
      and writer.add_file(write.file, write.in_file_path, write.value, writer_opts)
      or writer.update_file(write.file, write.in_file_path, write.value, writer_opts)
    if result.ok then
      changed = changed + 1
      applied[#applied + 1] = write
    else
      fails[#fails + 1] = write.lang .. ':' .. (result.reason or '?')
    end
  end
  return changed, fails, applied
end

function M.accept_applied(rows, applied)
  for _, write in ipairs(applied) do
    for _, row in ipairs(rows) do
      if row.file == write.file and vim.deep_equal(row.in_file_path, write.in_file_path) then
        row.orig = write.value
        row.kind = 'string'
        row.skip = false
        break
      end
    end
  end
end

return M

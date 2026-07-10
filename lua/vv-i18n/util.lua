-- vv-i18n.util — 跨模块共享小工具（display / panel 共用）
local M = {}

--- 按显示宽度截断（UTF-8 安全），超出补省略号；换行折成 ↵
---@param s string?
---@param max integer  最大显示宽度
---@return string
function M.truncate(s, max)
  s = (s or ''):gsub('\n', '↵')
  if vim.fn.strdisplaywidth(s) <= max then return s end
  local out, w = {}, 0
  for ch in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
    local cw = vim.fn.strdisplaywidth(ch)
    if w + cw > max - 1 then break end
    out[#out + 1] = ch
    w = w + cw
  end
  return table.concat(out) .. '…'
end

--- 取适合单行预览的译文；复数优先 other，其次首个字符串形态
---@param entry table?
---@return string?
function M.entry_value(entry)
  if not entry then return nil end
  if entry.kind == 'string' then return entry.value end

  if entry.kind == 'plural' then
    local first
    for _, variant in ipairs(entry.variants or {}) do
      if variant.kind == 'string' then
        if variant.form == 'other' then return variant.value end
        first = first or variant.value
      end
    end
    return first or '<plural>'
  end

  return '<' .. (entry.kind or 'other') .. '>'
end

return M

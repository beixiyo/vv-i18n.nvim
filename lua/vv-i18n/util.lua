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

return M

-- vv-i18n 列表面板的通用过滤机制
--
-- 负责大小写无关的文本匹配，并将各面板的业务回调适配到 vv-utils.prompt

local Prompt = require('vv-utils.prompt')

local M = {}

---@param fields any[]
---@param query string?
---@return boolean
function M.matches(fields, query)
  query = vim.trim(query or ''):lower()
  if query == '' then return true end

  for _, field in ipairs(fields) do
    if tostring(field or ''):lower():find(query, 1, true) then return true end
  end
  return false
end

---@class VVI18nFilterOpts
---@field initial? string
---@field filetype string
---@field label? string
---@field placeholder? string
---@field status? fun(): string
---@field on_change fun(query: string)
---@field on_accept fun(query: string)
---@field on_cancel fun()

---@param panel_win integer
---@param opts VVI18nFilterOpts
---@return VVPromptHandle?
function M.open(panel_win, opts)
  return Prompt.open(panel_win, {
    initial = opts.initial,
    filetype = opts.filetype,
    icon = '/',
    label = opts.label or 'Filter',
    placeholder = opts.placeholder or 'type to filter…',
    get_status = opts.status,
    on_change = opts.on_change,
    on_accept = opts.on_accept,
    on_cancel = opts.on_cancel,
  })
end

return M

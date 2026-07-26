-- Project discovery is pure policy; service owns the resulting runtime state.
local M = {}

local project_file = '.vv-i18n.lua'

function M.load(config)
  if not config.project_config then return nil end
  local bufname = vim.api.nvim_buf_get_name(0)
  local base = bufname ~= '' and vim.fs.dirname(bufname) or vim.uv.cwd()
  local found = vim.fs.find(project_file, { upward = true, path = base, type = 'file' })[1]
  if not found then return nil end
  local ok, content = pcall(vim.secure.read, found)
  if not ok or type(content) ~= 'string' then return nil end
  local chunk = load(content, '@' .. found)
  if not chunk then return nil end
  local loaded, opts = pcall(chunk)
  return loaded and type(opts) == 'table' and opts or nil,
    loaded and type(opts) == 'table' and vim.fs.dirname(found) or nil
end

function M.find_root(start)
  local base = start
  if not base then
    local bufname = vim.api.nvim_buf_get_name(0)
    base = bufname ~= '' and vim.fs.dirname(bufname) or vim.uv.cwd()
  end
  local marker = vim.fs.find({ 'pnpm-workspace.yaml', 'nx.json', 'turbo.json' }, { path = base, upward = true })[1]
  if marker then return vim.fs.dirname(marker) end
  local any = vim.fs.find({ '.git', 'package.json' }, { path = base, upward = true })[1]
  return any and vim.fs.dirname(any) or vim.uv.cwd()
end

return M

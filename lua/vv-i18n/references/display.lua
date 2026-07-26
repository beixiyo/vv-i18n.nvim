-- locale 定义处的引用数虚拟文本

local M = {}

local ns = vim.api.nvim_create_namespace('vv-i18n-references')
local plugin
local enabled = false
local unsubscribe
local augroup

local function default_chunks(ctx)
  local label = ctx.count == 1 and 'reference' or 'references'
  return { { ('%s%d %s'):format(ctx.icon, ctx.count, label), ctx.hl } }
end

local function render_buffer(bufnr)
  if not enabled or not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local config = plugin.get_config().references
  if not config.enable then return end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then return end

  local seen = {}
  for _, definition in ipairs(plugin.definitions_for_file(path)) do
    local id = definition.full_key .. ':' .. definition.entry.row

    if not seen[id] then
      seen[id] = true
      local count = #require('vv-i18n.references.index').get(definition.full_key)

      if count > 0 or config.show_zero then
        local ctx = {
          full_key = definition.full_key,
          lang = definition.lang,
          entry = definition.entry,
          count = count,
          icon = config.icon,
          hl = config.hl,
        }

        local chunks = config.render and config.render(ctx) or nil
        if type(chunks) == 'string' then chunks = { { chunks, config.hl } } end
        chunks = chunks or default_chunks(ctx)

        vim.api.nvim_buf_set_extmark(bufnr, ns, definition.entry.row or 0, 0, {
          virt_text = chunks,
          virt_text_pos = 'eol',
        })
      end
    end
  end
end

function M.refresh()
  if not enabled then return end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then pcall(render_buffer, bufnr) end
  end
end

---@param owner table
---@param opts table
function M.enable(owner, opts)
  if not opts.enable then
    M.disable()
    return false
  end

  if enabled then
    plugin = owner
    M.refresh()
    return true
  end

  plugin = owner
  enabled = true

  augroup = vim.api.nvim_create_augroup('VVI18nReferencesDisplay', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost' }, {
    group = augroup,
    callback = function(event) vim.schedule(function() pcall(render_buffer, event.buf) end) end,
  })

  unsubscribe = require('vv-i18n.references.index').subscribe(M.refresh)
  M.refresh()
  return true
end

function M.disable()
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  if unsubscribe then
    unsubscribe()
    unsubscribe = nil
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
    end
  end

  plugin = nil
  enabled = false
end

function M.is_enabled()
  return enabled
end

return M

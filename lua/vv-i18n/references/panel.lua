-- 当前 i18n key 的引用侧栏

local TreePanel = require('vv-utils.tree_panel')
local Filter = require('vv-i18n.filter')
local References = require('vv-i18n.references.index')
local Ast = require('vv-i18n.ast')
local Path = require('vv-utils.path')
local State = require('vv-utils.state')

local M = {}

local active_panel
local active_key
local references_state = State.register('vv-i18n', 'references')

local function file_lang(path)
  local filetype = vim.filetype.match({ filename = path })
  if not filetype then return nil end
  return Ast.lang_for_filetype(filetype) or vim.treesitter.language.get_lang(filetype) or filetype
end

local function file_nodes(full_key, query)
  local groups = {}
  local order = {}

  for _, ref in ipairs(References.get(full_key)) do
    if Filter.matches({ ref.relative, ref.file, ref.line, ref.row, ref.col }, query) then
      local group = groups[ref.file]
      if not group then
        group = {
          id = 'file:' .. ref.file,
          label = Path.collapse_middle(ref.relative, { head = 1, tail = 3 }),
          selectable = false,
          children = {},
          data = { relative = ref.relative },
        }
        groups[ref.file] = group
        order[#order + 1] = group
      end

      group.children[#group.children + 1] = {
        id = ('ref:%s:%d:%d'):format(ref.file, ref.row, ref.col),
        label = ref.line,
        location = {
          file = ref.file,
          row = ref.row,
          col = ref.col,
        },
        data = ref,
      }
    end
  end

  table.sort(order, function(a, b) return a.data.relative < b.data.relative end)
  return order
end

---@param ctx VVTreePanelRenderContext
---@param syntax_cache table<string, VVTreePanelChunk[]>
local function node_renderer(ctx, syntax_cache)
  local node = ctx.node
  local indent = string.rep('  ', ctx.depth)
  if ctx.has_children then
    return {
      chunks = {
        { indent .. (ctx.folded and ' ' or ' '), 'Comment' },
        { node.label, 'Directory' },
      },
      virt_text = { { tostring(#node.children), 'Comment' } },
    }
  end

  local ref = node.data
  local lang = file_lang(ref.file)
  local cache_key = (lang or '') .. '\0' .. node.label
  local code_chunks = syntax_cache[cache_key]
  if not code_chunks then
    code_chunks = TreePanel.syntax_chunks(node.label, lang, 'Normal')
    syntax_cache[cache_key] = code_chunks
  end
  local chunks = {
    { indent .. ('%d:%d  '):format(ref.row, ref.col + 1), 'LineNr' },
  }
  vim.list_extend(chunks, code_chunks)

  return {
    chunks = chunks,
  }
end

---@return boolean closed
function M.close()
  if not active_panel or not active_panel:is_open() then return false end
  active_panel:close()
  return true
end

---@param plugin table
---@param full_key string
function M.toggle(plugin, full_key)
  if active_panel and active_panel:is_open() then
    if active_key == full_key then
      active_panel:close()
      return
    end
    active_panel:close()
  end

  local opts = plugin.get_config().references.panel
  local mappings = opts.mappings
  local syntax_cache = {}
  local unsubscribe
  local panel
  local filter_query = ''
  local filter_prompt

  local function rebuild(query)
    filter_query = query or ''
    panel:refresh()
  end

  local function open_filter()
    local initial = filter_query
    filter_prompt = Filter.open(panel.win, {
      initial = initial,
      filetype = 'vv-i18n-references-filter',
      label = 'Filter references',
      placeholder = 'type to filter references…',
      status = function()
        if filter_query == '' then return '' end
        local count = 0
        for _, group in ipairs(file_nodes(full_key, filter_query)) do count = count + #group.children end
        return count == 1 and '1 match' or string.format('%d matches', count)
      end,
      on_change = rebuild,
      on_accept = rebuild,
      on_cancel = function() rebuild(initial) end,
    })
  end

  panel = TreePanel.new({
    id = 'vv-i18n-references',
    title = 'References',
    filetype = 'vv-i18n-references',
    width = opts.width,
    state = opts.state or references_state,
    position = opts.position,
    preview_debounce_ms = opts.preview_debounce_ms,
    help = opts.help,
    toolbar = {
      items = {
        { label = 'Navigate', key = 'j/k' },
        { label = 'Fold', key = 'h/l' },
        { label = 'Open', key = '<CR>' },
        { label = 'Jump', key = 'gf' },
        { label = 'Filter', key = '/' },
        { label = 'Help', key = 'g?' },
        { label = 'Close', key = 'q' },
      },
    },
    on_attach = function(current, buf)
      if mappings == nil then
        TreePanel.apply_default_mappings(current, {
          ['/'] = { desc = 'Filter references', callback = open_filter },
        })
      elseif mappings ~= false then
        TreePanel.apply_mappings(current, mappings)
      end
      if opts.on_attach then opts.on_attach(current, buf) end
    end,
    source = function() return file_nodes(full_key, filter_query) end,
    on_refresh = function()
      References.refresh(plugin, function()
        if panel:is_open() then panel:refresh() end
      end)
    end,
    on_close = function()
      if filter_prompt then filter_prompt.close(); filter_prompt = nil end
      if unsubscribe then unsubscribe() end
      if active_panel == panel then
        active_panel = nil
        active_key = nil
      end
    end,
    render = {
      header = function()
        local total = #References.get(full_key)
        local count = 0
        for _, group in ipairs(file_nodes(full_key, filter_query)) do count = count + #group.children end
        return {
          chunks = {
            { '  󰌹 ', 'Title' },
            { full_key, 'Title' },
          },
          virt_text = { { filter_query ~= ''
            and ('%d/%d · /%s'):format(count, total, filter_query)
            or tostring(total), 'Comment' } },
        }
      end,
      node = opts.render or function(ctx) return node_renderer(ctx, syntax_cache) end,
      empty = function()
        if filter_query ~= '' then
          return { text = ("  No matches for '%s'"):format(filter_query), hl = 'Comment' }
        end
        return {
          text = References.is_scanning() and '  Scanning references…' or '  No references',
          hl = 'Comment',
        }
      end,
    },
  })
  local ok, err = xpcall(function()
    panel:open()
    unsubscribe = References.subscribe(function()
      if panel:is_open() then panel:refresh() end
    end)
  end, debug.traceback)
  if not ok then
    panel:close()
    error(err, 0)
  end

  active_panel = panel
  active_key = full_key
end

return M

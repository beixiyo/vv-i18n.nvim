-- i18n 键面板的默认渲染器

local Model = require('vv-i18n.panel.model')
local hl = require('vv-utils.hl')
local util = require('vv-i18n.util')

local M = {}

local function ui_icon(key, fallback)
  local ok, icons = pcall(require, 'vv-icons')
---@diagnostic disable-next-line: undefined-field
  local entry = ok and icons.raw and icons.raw.ui and icons.raw.ui[key]
  return (entry and entry.glyph) or fallback
end

local CHEV_OPEN = ui_icon('fold_open', '')
local CHEV_CLOSED = ui_icon('fold_closed', '')

hl.register('vv-i18n.panel.hl', {
  VVI18nPanelTitle   = { link = 'Title' },
  VVI18nPanelChevron = { link = 'Comment' },
  VVI18nPanelGroup   = { link = 'Directory' },
  VVI18nPanelCount   = { link = 'Comment' },
  VVI18nPanelKey     = { link = 'Identifier' },
  VVI18nPanelValue   = { link = 'String' },
  VVI18nPanelLanguage = { link = 'Comment' },
  VVI18nPanelLanguageSelected = { link = 'Special' },
  VVI18nPanelOk      = { link = 'DiagnosticOk' },
  VVI18nPanelMiss    = { link = 'DiagnosticWarn' },
  VVI18nPanelWinbar  = { link = 'Comment' },
  VVI18nPanelEmpty   = { link = 'Comment' },
})

local function badge(group, key)
  local chunks = { { '  ', 'Normal' } }
  for _, lang in ipairs(key.langs or group.langs or {}) do
    chunks[#chunks + 1] = {
      key.per[lang] and '✓' or '·',
      key.per[lang] and 'VVI18nPanelOk' or 'VVI18nPanelMiss',
    }
  end
  if #(key.missing or {}) > 0 then
    chunks[#chunks + 1] = {
      '  Missing: ' .. table.concat(key.missing, ','),
      'VVI18nPanelMiss',
    }
  end
  return chunks
end

---@param view table
---@param ctx VVTreePanelRenderContext
---@return VVTreePanelRenderRow
local function render_node(view, ctx)
  local data = ctx.node.data
  local indent = string.rep('  ', ctx.depth)
  if data.kind == 'group' or data.kind == 'languages' then
    return {
      chunks = {
        { (ctx.folded and CHEV_CLOSED or CHEV_OPEN) .. ' ', 'VVI18nPanelChevron' },
        { ctx.node.label, 'VVI18nPanelGroup' },
      },
      virt_text = { { ('  (%d)'):format(data.count), 'VVI18nPanelCount' } },
      virt_text_pos = 'eol',
    }
  end

  if data.kind == 'language' then
    local language_hl = data.selected
        and 'VVI18nPanelLanguageSelected'
      or 'VVI18nPanelLanguage'
    return {
      chunks = {
        { indent, 'Normal' },
        { data.selected and '● ' or '○ ', language_hl },
        { data.lang, language_hl },
      },
    }
  end

  local key = data.key
  local group = data.group
  local lang = view.selected_lang or view.plugin.preferred_lang(key.langs or group.langs)
  local value = util.entry_value(key.per[lang])
  local rel = util.truncate(key.rel, 28)
  return {
    chunks = {
      { indent .. ' ', 'Normal' },
      { rel, 'VVI18nPanelKey' },
      { string.rep(' ', math.max(1, 29 - vim.fn.strdisplaywidth(rel))), 'Normal' },
      {
        value and util.truncate(value, 30) or '—',
        value and 'VVI18nPanelValue' or 'VVI18nPanelMiss',
      },
    },
    virt_text = badge(group, key),
    virt_text_pos = 'eol',
  }
end

function M.toolbar()
  return {
    { label = 'Fold', key = 'h/l' },
    { label = 'Filter', key = '/' },
    { label = 'Select/Edit', key = '<CR>' },
    { label = 'Edit', key = 'e' },
    { label = 'Miss', key = 'm' },
    { label = 'Group', key = 'g' },
    { label = 'Help', key = 'g?' },
    { label = 'Close', key = 'q' },
  }
end

---@param view table
---@return VVTreePanelRenderers
function M.defaults(view)
  return {
    header = function()
      local total, missing = Model.summary(view.tree)
      local mode = view.group_by == 'missing_lang' and ' · by missing lang' or ''
      local filter = view.only_missing and ' · missing only' or ''
      local language = view.selected_lang and (' · ' .. view.selected_lang) or ''
      local query = view.filter_query ~= '' and (' · /' .. view.filter_query) or ''
      local visible = Model.visible_total(view.tree, view.group_by, view.only_missing, view.filter_query)
      local key_count = view.filter_query ~= ''
          and ('%d/%d keys'):format(visible, total)
        or ('%d keys'):format(total)
      return {
        chunks = {
          { '  󰗊  ', 'VVI18nPanelTitle' },
          { 'i18n keys', 'VVI18nPanelTitle' },
        },
        virt_text = {
          { ('%s · %d groups · %d missing%s%s%s%s')
            :format(key_count, #(view.tree or {}), missing, mode, filter, language, query), 'VVI18nPanelCount' },
        },
      }
    end,
    node = function(ctx) return render_node(view, ctx) end,
    empty = function()
      if view.filter_query ~= '' then
        return { text = ("  No matches for '%s'"):format(view.filter_query), hl = 'VVI18nPanelEmpty' }
      end
      return {
        text = '  (No keys. Run :VVI18nReload to rebuild the index.)',
        hl = 'VVI18nPanelEmpty',
      }
    end,
  }
end

return M

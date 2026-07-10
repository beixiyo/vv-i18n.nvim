-- vv-i18n.help — 面板内 g? 键位帮助，复用 vv-utils.help_panel

local HelpPanel = require('vv-utils.help_panel')

local M = {}

local ACTIONS = {
  edit_or_toggle        = { cat = 'Navigate', icon = '' },
  open_or_edit          = { cat = 'Navigate', icon = '' },
  close_group           = { cat = 'Navigate', icon = '' },
  next                  = { cat = 'Navigate', icon = '' },
  prev                  = { cat = 'Navigate', icon = '' },
  only_missing          = { cat = 'View',     icon = '' },
  group_by_missing_lang = { cat = 'View',     icon = '' },
  reload                = { cat = 'View',     icon = '' },
  help                  = { cat = 'View',     icon = '' },
  click                 = { cat = 'Mouse',    icon = '' },
  close                 = { cat = 'Panel',    icon = '' },
}

local CATEGORIES = { 'Navigate', 'View', 'Mouse', 'Panel' }

---@param state table
function M.open(state)
  HelpPanel.open({
    source_buf  = state.buf,
    desc_prefix = 'vv-i18n: ',
    actions     = ACTIONS,
    categories  = CATEGORIES,
    title       = 'vv-i18n keymaps',
    title_icon  = '󰗊',
    filetype    = 'vv-i18n-help',
  })
end

return M

-- Private runtime owner. No module-level plugin state escapes this instance.
local Config = require('vv-i18n.config')

local M = {}

function M.new()
  return {
    config = Config.snapshot(),
    root = nil,
    indexes = nil,
    errors = {},
    project_file = nil,
  }
end

function M.set_config(state, config)
  state.config = vim.deepcopy(config)
end

function M.get_config(state)
  return vim.deepcopy(state.config)
end

function M.get_state(state)
  return vim.deepcopy({
    root = state.root,
    indexes = state.indexes,
    errors = state.errors,
    project_file = state.project_file,
  })
end

return M

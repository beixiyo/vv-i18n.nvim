-- Private runtime owner. No module-level plugin state escapes this instance.
local Config = require('vv-i18n.config')

local M = {}

local function index_inputs(config)
  local inputs = {}

  for _, key in ipairs({
    'root',
    'project_config',
    'sources',
    'key_separator',
    'namespace_separator',
    'lang',
    'mount',
    'namespace',
    'hooks',
    't',
    'parse',
  }) do
    inputs[key] = config[key]
  end

  return inputs
end

local function project_inputs(config)
  return {
    project_config = config.project_config,
  }
end

function M.new()
  local config = Config.snapshot()

  return {
    base_config = vim.deepcopy(config),
    config = config,
    root = nil,
    indexes = nil,
    errors = {},
    project_file = nil,
    references_dirty = true,
    setup_epoch = 0,
  }
end

function M.set_config(state, config)
  local previous = state.base_config
  local has_project_config = state.project_file ~= nil
  local previous_inputs = has_project_config and project_inputs(previous) or index_inputs(previous)
  local next_inputs = has_project_config and project_inputs(config) or index_inputs(config)
  local index_changed = not vim.deep_equal(previous_inputs, next_inputs)

  state.base_config = vim.deepcopy(config)
  if index_changed or not has_project_config then
    state.config = vim.deepcopy(config)
  end
  if not index_changed then return end

  state.root = nil
  state.indexes = nil
  state.errors = {}
  state.project_file = nil
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

-- 私有运行时归属对象；插件状态不会从模块级实例中泄漏
local Config = require('vv-i18n.config')

local M = {}

local function index_inputs(config)
  local inputs = {}

  for _, key in ipairs({
    'root',
    'project_config',
    'sources',
    'key_separator',
    'ignore_key',
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

---@param opts? VVI18nStateOpts
function M.get_state(state, opts)
  opts = opts or {}
  local snapshot = {
    root = state.root,
    errors = state.errors,
    project_file = state.project_file,
  }
  -- metadata 消费方不遍历索引图；必须在 deepcopy 前排除，而非复制后丢弃
  if opts.indexes ~= false then snapshot.indexes = state.indexes end
  return vim.deepcopy(snapshot)
end

return M

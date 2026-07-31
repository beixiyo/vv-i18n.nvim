-- Locale source normalization and index rebuilding.
local Index = require('vv-i18n.index')
local Project = require('vv-i18n.project')
local Config = require('vv-i18n.config')
local resolver = require('vv-i18n.resolver')

local M = {}

local function to_set(list)
  local set = {}
  for _, name in ipairs(list or {}) do set[name] = true end
  return set
end

local function abspath(path, root)
  return vim.startswith(path, '/') and path or root .. '/' .. path
end

local function normalize_source(config, raw)
  return {
    prefix = raw.prefix or '',
    root = raw.root,
    discover = raw.discover,
    dirs = raw.dirs,
    lang = raw.lang ~= nil and raw.lang or config.lang,
    mount = raw.mount ~= nil and raw.mount or config.mount,
    namespace = raw.namespace ~= nil and raw.namespace or config.namespace,
    hooks = raw.hooks or config.hooks,
    t = raw.t or config.t,
    parse = raw.parse ~= nil and raw.parse or config.parse,
  }
end

local function source_dirs(source, project_root)
  local root = source.root and abspath(source.root, project_root) or project_root
  local dirs = {}

  if type(source.discover) == 'table' then
    vim.list_extend(dirs, Index.discover_by_patterns(root, source.discover))
  elseif type(source.discover) == 'function' then
    vim.list_extend(dirs, source.discover(root) or {})
  end

  for _, dir in ipairs(source.dirs or {}) do dirs[#dirs + 1] = abspath(dir, root) end

  return dirs
end

function M.reload(state, plugin)
  local project, project_dir = Project.load(state.base_config)

  state.config = project and Config.activate(project) or Config.activate(state.base_config)
  state.project_file = project and project_dir or nil
  state.root = state.config.root or project_dir or Project.find_root()
  state.indexes = {}
  state.errors = {}

  for _, raw in ipairs(state.config.sources) do
    local source = normalize_source(state.config, raw)
    local index, errors = Index.build({
      dirs = source_dirs(source, state.root),
      prefix = source.prefix,
      key_separator = state.config.key_separator,
      mount = source.mount,
      lang = source.lang,
      parse = source.parse,
    })
    state.indexes[#state.indexes + 1] = {
      source = source,
      index = index,
      ropts = {
        namespace_resolver = resolver.make_namespace(source.namespace, source.prefix, state.config.key_separator),
        namespace_separator = state.config.namespace_separator,
        key_separator = state.config.key_separator,
        t_functions = to_set(source.t),
        hook_names = to_set(source.hooks),
      },
    }
    vim.list_extend(state.errors, errors)
  end

  if state.config.references.enable then
    require('vv-i18n.references.index').refresh(plugin)
    state.references_dirty = false
  else
    require('vv-i18n.references.index').clear()
    state.references_dirty = true
  end
  return state.indexes
end

function M.ensure(state, plugin)
  if not state.indexes then M.reload(state, plugin) end
  return state.indexes
end

return M

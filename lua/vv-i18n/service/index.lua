-- locale 来源归一化与索引重建
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

--- 相对 root 拼绝对路径并归一化（去尾部斜杠），供调用点按 root 作用域过滤
local function scoped_root(path, root)
  local dir = vim.fs.normalize(abspath(path, root))
  return (dir:gsub('/+$', ''))
end

local function normalize_source(config, raw)
  return {
    prefix = raw.prefix or '',
    -- 空串 root 等同未配置（不参与调用点辖区），避免 '' 被当作 truthy 认领整个项目根
    root = raw.root ~= nil and raw.root ~= '' and raw.root or nil,
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

--- locale 文件指纹：各 source 目录下全部文件的路径 + mtime + size
--- 新增 / 删除 / 改写 locale 文件，以及目录集合变化，都会改变指纹
---@param dir_lists string[][]  每个 source 的 locale 目录
---@return string
local function fingerprint(dir_lists)
  local parts = {}
  for _, dirs in ipairs(dir_lists) do
    for _, dir in ipairs(dirs) do
      parts[#parts + 1] = 'D' .. dir
      for _, f in ipairs(Index.walk_files(dir)) do
        local st = vim.uv.fs_stat(f.path)
        if st then
          parts[#parts + 1] = ('%s\0%d.%d\0%d'):format(f.path, st.mtime.sec, st.mtime.nsec, st.size)
        end
      end
    end
  end
  return table.concat(parts, '\n')
end

function M.reload(state, plugin)
  local project, project_dir = Project.load(state.base_config)

  state.config = project and Config.activate(project) or Config.activate(state.base_config)
  state.project_file = project and project_dir or nil
  state.root = state.config.root or project_dir or Project.find_root()
  state.indexes = {}
  state.errors = {}

  -- 每个 source 只解析一次目录（discover 可能是带副作用的用户函数），构建与指纹共用
  local sources, dir_lists = {}, {}
  for i, raw in ipairs(state.config.sources) do
    sources[i] = normalize_source(state.config, raw)
    dir_lists[i] = source_dirs(sources[i], state.root)
  end
  -- 构建前取指纹：构建期间发生的改写会让下次 is_stale 命中，而不是被这次快照吞掉
  state.fingerprint = fingerprint(dir_lists)

  for i, source in ipairs(sources) do
    local index, errors = Index.build({
      dirs = dir_lists[i],
      prefix = source.prefix,
      key_separator = state.config.key_separator,
      ignore_key = state.config.ignore_key,
      mount = source.mount,
      lang = source.lang,
      parse = source.parse,
    })
    state.indexes[#state.indexes + 1] = {
      source = source,
      root_path = source.root and scoped_root(source.root, state.root) or nil,
      dirs = dir_lists[i],
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

--- 磁盘上的 locale 文件是否已偏离当前索引（外部工具 / Agent 改写、新增、删除）
--- 未建过索引时返回 false：交给 ensure 首次构建
---@param state table
---@return boolean
function M.is_stale(state)
  if not state.indexes then return false end
  local dir_lists = {}
  for i, entry in ipairs(state.indexes) do
    -- glob 形式重新匹配以发现新增的 locale 目录；函数形式是用户代码，沿用上次的结果
    dir_lists[i] = type(entry.source.discover) == 'function' and entry.dirs
      or source_dirs(entry.source, state.root)
  end
  return fingerprint(dir_lists) ~= state.fingerprint
end

function M.ensure(state, plugin)
  if not state.indexes then M.reload(state, plugin) end
  return state.indexes
end

return M

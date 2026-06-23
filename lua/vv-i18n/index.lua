-- vv-i18n.index — locale 全键索引（mount 策略化，适配多种布局）
--
-- 把一个 source 的若干 locale 目录扫成「全键 → 逐语言条目」的索引。命名空间从哪来由
-- `mount` 决定，故同一套代码适配三类布局：
--   * top-key：namespace = 文件内容顶层 key（in-file 路径含它）
--   * filename：namespace = 文件名/路径模板捕获的 {ns}（键在文件根）
--   * flat：无 namespace（整源一个桶）
--   * 函数：自定义 fn(ctx) -> namespace
--
-- 全键 = [prefix] <key_sep> <namespace 链> <key_sep> 文件内路径。完整度按挂载点语言集衡量
local reader = require('vv-i18n.reader')
local tmpl = require('vv-i18n.tmpl')
local fs = require('vv-utils.fs')

local M = {}

local FLAT = '\1flat'   -- flat 布局的单桶哨兵 mount_key

--- 递归列出目录下所有文件（相对路径 + 完整路径）
---@param dir string
---@return { rel: string, path: string }[]
local function walk_files(dir)
  local out = {}
  local ok = pcall(function()
    for name, t in vim.fs.dir(dir, { depth = 8 }) do
      if t == 'file' then out[#out + 1] = { rel = name, path = dir .. '/' .. name } end
    end
  end)
  if not ok then return {} end
  return out
end

--- 文件名 stem（去目录去扩展名）
local function stem_of(path)
  local base = path:match('([^/\\]+)$') or path
  return (base:gsub('%.[%w]+$', ''))
end

--- 挂载点内某键缺失的语言（per 可为 nil）
---@param mount { langs: string[] }
---@param per table?
---@return string[]
local function langs_missing(mount, per)
  per = per or {}
  local out = {}
  for _, lang in ipairs(mount.langs) do
    if per[lang] == nil then out[#out + 1] = lang end
  end
  return out
end

local Index = {}
Index.__index = Index

--- 拆全键 → mount_key, 文件内路径[], 相对显示名。prefix 不匹配返回 nil
---@param full_key string
---@return string? mount_key
---@return string[]? in_file_path
---@return string? rel
function Index:decompose(full_key)
  local rest
  if self.prefix == '' then
    rest = full_key
  else
    local head = self.prefix .. self.key_sep
    if full_key:sub(1, #head) ~= head then return nil end
    rest = full_key:sub(#head + 1)
  end
  local segs = vim.split(rest, self.key_sep, { plain = true })
  if #segs == 0 or segs[1] == '' then return nil end

  if self.mount_kind == 'flat' then
    return FLAT, segs, table.concat(segs, '.')
  elseif self.mount_kind == 'top-key' then
    -- namespace 即首段，且在文件内容里 → in_file_path 含首段；rel 去掉首段
    local rel = #segs > 1 and table.concat({ unpack(segs, 2) }, '.') or segs[1]
    return segs[1], segs, rel
  else
    -- filename / 函数：namespace 是前置段，不在文件内 → in_file_path 去掉首段
    local in_file = { unpack(segs, 2) }
    if #in_file == 0 then return nil end
    return segs[1], in_file, table.concat(in_file, '.')
  end
end

function Index:get(full_key)
  return self.keys[full_key]
end

--- 本索引是否含任意键（早退，不数全量）
---@return boolean
function Index:any_keys()
  for _ in pairs(self.keys) do return true end
  return false
end

--- 该全键是否属于本索引（前缀匹配且命名空间挂载点存在）
---@param full_key string
---@return boolean
function Index:owns(full_key)
  local mount_key = self:decompose(full_key)
  return mount_key ~= nil and self.mounts[mount_key] ~= nil
end

--- 全键 → 应写入的物理文件（含尚不存在该键的语言）
---@param full_key string
---@return { lang: string, file: string, in_file_path: string[], exists: boolean }[]?
---@return string? err
function Index:resolve_files_for_key(full_key)
  local mount_key, in_file_path = self:decompose(full_key)
  if not mount_key then return nil, 'bad-prefix' end
  local mount = self.mounts[mount_key]
  if not mount then return nil, 'unknown-mount:' .. mount_key end

  local per = self.keys[full_key] or {}
  local out = {}
  for _, lang in ipairs(mount.langs) do
    out[#out + 1] = {
      lang = lang,
      file = mount.files[lang],
      in_file_path = in_file_path,
      exists = per[lang] ~= nil,
    }
  end
  table.sort(out, function(a, b) return a.lang < b.lang end)
  return out, nil
end

--- 某全键在其挂载点内缺失的语言
function Index:missing(full_key)
  local mount_key = self:decompose(full_key)
  local mount = mount_key and self.mounts[mount_key]
  if not mount then return {} end
  return langs_missing(mount, self.keys[full_key])
end

function Index:all_keys()
  local out = {}
  for k in pairs(self.keys) do out[#out + 1] = k end
  table.sort(out)
  return out
end

--- 按挂载点分组的树模型
function Index:tree()
  local by_mount = {}
  for _, full in ipairs(self:all_keys()) do
    local mount_key, _, rel = self:decompose(full)
    if mount_key then
      local m = self.mounts[mount_key]
      local g = by_mount[mount_key]
      if not g then
        g = {
          mount = mount_key == FLAT and (self.prefix ~= '' and self.prefix or '(flat)') or mount_key,
          langs = m and m.langs or {},
          keys = {},
        }
        by_mount[mount_key] = g
      end
      g.keys[#g.keys + 1] = {
        full = full, rel = rel, per = self.keys[full],
        missing = m and langs_missing(m, self.keys[full]) or {},
      }
    end
  end
  local out = {}
  for _, g in pairs(by_mount) do
    table.sort(g.keys, function(a, b) return a.rel < b.rel end)
    out[#out + 1] = g
  end
  table.sort(out, function(a, b) return a.mount < b.mount end)
  return out
end

--- 缺失漏译报告
function Index:missing_report()
  local out = {}
  for _, full in ipairs(self:all_keys()) do
    local mount_key = self:decompose(full)
    local mount = mount_key and self.mounts[mount_key]
    local miss = mount and langs_missing(mount, self.keys[full]) or {}
    if #miss > 0 then
      out[#out + 1] = { full = full, mount = mount_key, missing = miss }
    end
  end
  return out
end

function Index:stats()
  local nkeys = 0
  for _ in pairs(self.keys) do nkeys = nkeys + 1 end
  local nmounts = 0
  for _ in pairs(self.mounts) do nmounts = nmounts + 1 end
  return { keys = nkeys, mounts = nmounts, langs = self.langs }
end

--- 一个文件贡献的 namespace 段（仅 filename / 函数 布局会问此处；
--- top-key 的 ns 在每个 leaf 首段、flat 无 ns，均不经此）
---@param mount 'filename'|fun(ctx): string?
---@param ctx table
---@return string?
local function file_namespace(mount, ctx)
  if type(mount) == 'function' then return mount(ctx) end
  return ctx.ns or stem_of(ctx.path)   -- 'filename'
end

--- 构建索引（一个 source 一个 index）
---@param opts { dirs: string[], prefix?: string, key_separator?: string, mount?: any, lang?: any, parse?: fun(content: string, path: string): table? }
---@return Index index
---@return table[] errors  解析失败清单（不静默吞）
function M.build(opts)
  opts = opts or {}
  local prefix = opts.prefix or ''
  local key_sep = opts.key_separator or '.'
  local mount = opts.mount or 'top-key'
  local mount_kind = type(mount) == 'function' and 'fn' or mount
  local lang_matcher = tmpl.compile(opts.lang or { '{lang}.ts', '{lang}.tsx', '{lang}.js', '{lang}.json' })
  local custom_parse = opts.parse   -- 自定义读侧解析（YAML/PO 等）：fn(content, path) -> { top_keys?, leaves }

  -- 解析一个 locale 文件：有自定义 parse 就用它，否则默认 tree-sitter
  local function parse_one(path)
    if type(custom_parse) ~= 'function' then return reader.parse_file(path) end
    local rok, content = pcall(fs.read_all, path)
    if not rok or type(content) ~= 'string' then return { ok = false, reason = 'read-failed' } end
    local pok, res = pcall(custom_parse, content, path)
    if not pok then return { ok = false, reason = 'parse-error:' .. tostring(res) } end
    if type(res) ~= 'table' or type(res.leaves) ~= 'table' then return { ok = false, reason = 'parse-bad-shape' } end
    return { ok = true, top_keys = res.top_keys or {}, leaves = res.leaves }
  end

  local self = setmetatable({
    prefix = prefix,
    key_sep = key_sep,
    mount_kind = mount_kind,
    keys = {},
    mounts = {},
    langs = {},
  }, Index)

  local errors = {}
  local lang_set = {}

  local function join(...)
    local parts = {}
    for _, p in ipairs({ ... }) do
      if p and p ~= '' then parts[#parts + 1] = p end
    end
    return table.concat(parts, key_sep)
  end

  local function register_mount(mount_key, lang, path)
    local m = self.mounts[mount_key]
    if not m then m = { files = {}, langs = {} }; self.mounts[mount_key] = m end
    if not m.files[lang] then
      m.files[lang] = path
      m.langs[#m.langs + 1] = lang
    end
  end

  for _, dir in ipairs(opts.dirs or {}) do
    for _, f in ipairs(walk_files(dir)) do
      local matched = lang_matcher(f.rel, f.path)
      if matched then
        local res = parse_one(f.path)
        if not res.ok then
          errors[#errors + 1] = { dir = dir, lang = matched.lang, file = f.path, reason = res.reason }
        else
          local lang = matched.lang
          lang_set[lang] = true
          -- ns 仅 filename / 函数 布局需要（top-key 走顶层 key、flat 无 ns）
          local ns
          if mount_kind ~= 'top-key' and mount_kind ~= 'flat' then
            ns = file_namespace(mount, { path = f.path, lang = lang, ns = matched.ns, top_keys = res.top_keys })
          end

          if mount_kind == 'top-key' then
            for _, top in ipairs(res.top_keys) do register_mount(top, lang, f.path) end
          else
            register_mount(mount_kind == 'flat' and FLAT or ns, lang, f.path)
          end

          for _, leaf in ipairs(res.leaves) do
            local full
            if mount_kind == 'top-key' or mount_kind == 'flat' then
              full = join(prefix, leaf.dotted)
            else
              full = join(prefix, ns, leaf.dotted)
            end
            local per = self.keys[full]
            if not per then per = {}; self.keys[full] = per end
            per[lang] = {
              file = f.path,
              in_file_path = leaf.path,
              kind = leaf.kind,
              value = leaf.value,
              row = leaf.row,
              col = leaf.col,
            }
          end
        end
      end
    end
  end

  for _, m in pairs(self.mounts) do table.sort(m.langs) end
  for lang in pairs(lang_set) do self.langs[#self.langs + 1] = lang end
  table.sort(self.langs)

  return self, errors
end

--- 按 glob 模式（相对 root）发现 locale 目录
---@param root string
---@param patterns string[]
---@return string[] dirs
function M.discover_by_patterns(root, patterns)
  local seen, dirs = {}, {}
  for _, pat in ipairs(patterns or {}) do
    -- nosuf=true：发现结果不受用户 'wildignore'/'suffixes' 影响（否则会静默丢 locale 目录）
    local matched = vim.fn.glob(root .. '/' .. pat, true, true)
    table.sort(matched)
    for _, p in ipairs(matched) do
      if vim.fn.isdirectory(p) == 1 and not seen[p] then
        seen[p] = true
        dirs[#dirs + 1] = p
      end
    end
  end
  return dirs
end

return M

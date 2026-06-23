-- vv-i18n.tmpl — 文件路径 → { lang, ns } 匹配器
--
-- 把「字面量模板 / 模板数组 / 函数」三形态统一编译成一个匹配器：
--   * 模板：含 `{lang}` / `{ns}` 占位，匹配**相对 locale 目录的路径**
--       '{lang}.ts'            → 'zh-CN.ts'        → { lang='zh-CN' }
--       '{lang}/{ns}.json'     → 'en-US/common.json' → { lang='en-US', ns='common' }
--       '{ns}.{lang}.json'     → 'common.zh-CN.json' → { lang='zh-CN', ns='common' }
--   * 数组：逐个试，首个命中为准
--   * 函数：收**完整路径**，返回 lang 字符串或 { lang=, ns= } 或 nil（非语言文件）
local M = {}

local MAGIC = '([%^%$%(%)%%%.%[%]%*%+%-%?])'

--- 单个模板 → 匹配函数(relpath) -> {lang, ns} | nil
local function compile_one(tmpl)
  local order = {}
  for name in tmpl:gmatch('{(%w+)}') do order[#order + 1] = name end
  local pat = tmpl:gsub(MAGIC, '%%%1')   -- 转义 Lua 魔法字符（{ } 非魔法，保留）
  pat = pat:gsub('{%w+}', '([^/]+)')      -- 占位 → 捕获
  pat = '^' .. pat .. '$'
  return function(relpath)
    local caps = { relpath:match(pat) }
    if #caps == 0 then return nil end
    local out = {}
    for i, name in ipairs(order) do out[name] = caps[i] end
    if not out.lang then return nil end
    return out
  end
end

--- 把 spec（string | string[] | function）编译成 matcher(relpath, fullpath) -> {lang, ns} | nil
---@param spec string|string[]|fun(path: string): (string|table|nil)
---@return fun(relpath: string, fullpath: string): table?
function M.compile(spec)
  if type(spec) == 'function' then
    return function(_, fullpath)
      local r = spec(fullpath)
      if not r then return nil end
      if type(r) == 'string' then return { lang = r } end
      if type(r) == 'table' and r.lang then return r end
      return nil
    end
  end

  local templates = type(spec) == 'string' and { spec } or spec
  local matchers = {}
  for _, t in ipairs(templates) do matchers[#matchers + 1] = compile_one(t) end

  return function(relpath, _)
    for _, m in ipairs(matchers) do
      local r = m(relpath)
      if r then return r end
    end
    return nil
  end
end

return M

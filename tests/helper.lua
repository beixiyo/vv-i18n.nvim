-- 测试公共：fixture 路径（自定位，便携）+ 三布局配置 + 断言器
--
-- 三种 fixture 各验一类布局，同时反证「字面量+函数双形态、source 覆盖全局」可用：
--   ns-app   —— top-key 布局（命名空间在文件内顶层 key）+ two-level 前缀 + 自定义 hook
--   file-ns  —— filename 布局（命名空间在文件名）+ hook-arg 前缀（react-i18next 风格）
--   flat-app —— flat 布局（无命名空间）+ 中性默认
local H = {}

local src = debug.getinfo(1, 'S').source:sub(2)
local TESTS_DIR = src:match('(.*)/[^/]*$')
H.FIXTURES = TESTS_DIR .. '/fixtures'

function H.fixture(rel)
  return H.FIXTURES .. '/' .. rel
end

function H.read(path)
  local f = assert(io.open(path, 'r')); local c = f:read('*a'); f:close(); return c
end

--- top-key 布局
function H.ns_config()
  return {
    root = H.fixture('ns-app'),
    sources = {
      {
        prefix = 'app',
        root = 'src',
        discover = { 'components/*/locales', 'i18n/common' },
        mount = 'top-key',
        namespace = 'two-level',
        lang = '{lang}.ts',
        hooks = { 'useT' },
      },
    },
    display = { enable = false },
  }
end

--- filename 布局（react-i18next 风格）
function H.file_ns_config()
  return {
    root = H.fixture('file-ns'),
    sources = {
      {
        prefix = '',
        root = 'src',
        discover = { 'locales' },
        mount = 'filename',
        namespace = 'hook-arg',
        lang = '{lang}/{ns}.json',
        hooks = { 'useTranslation' },
      },
    },
    display = { enable = false },
  }
end

--- flat 布局（无命名空间 + 中性默认）
function H.flat_config()
  return {
    root = H.fixture('flat-app'),
    sources = {
      { prefix = '', discover = { 'locales' }, mount = 'flat', namespace = 'flat', lang = '{lang}.ts' },
    },
    display = { enable = false },
  }
end

function H.checker()
  local pass, fail = 0, 0
  local function check(name, ok, extra)
    if ok then pass = pass + 1; print('PASS: ' .. name)
    else fail = fail + 1; print('FAIL: ' .. name .. (extra and ('  → ' .. tostring(extra)) or '')) end
  end
  local function done()
    print(('== %d PASS / %d FAIL =='):format(pass, fail))
    return pass, fail
  end
  return check, done
end

return H

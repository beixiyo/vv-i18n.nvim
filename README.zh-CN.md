<div align="center">
  <h1>vv-i18n.nvim</h1>
  <p><a href="./README.md">English</a> | 中文</p>
  <img src="https://github.com/beixiyo/vv-i18n.nvim/releases/download/assets-2026-07-25/vv-i18n.png" alt="vv-i18n 演示" width="900" />
  <p>想要我的 Neovim 配置？查看 <a href="https://github.com/beixiyo/dotfiles">dotfiles</a></p>
  <p><strong>TS/TSX i18n 的行内预览 / 跳转定义 / 同步改值 / 补缺失语言</strong>，对标 <em>lokalise</em> · <em>i18n-ally</em></p>
  <p>
    <img src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.10+" />
    <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />
  </p>
</div>

面向通用工具够不着的项目：locale 是 TS/JS 模块具名导出（或 JSON），运行时把多个文件合并到
命名空间根下、hook 注入前缀。**locale 来源 / 文件→语言 / 文件→命名空间 / 调用点→前缀
均「字面量或函数」可配**，默认中性，内核全 tree-sitter

## 先对号入座：你的项目是哪种布局？

| 布局         | 命名空间在哪         | 例子                                    | 全键             | 配 `mount`   |
| ------------ | -------------------- | --------------------------------------- | ---------------- | ------------ |
| **top-key**  | 文件**内容**顶层 key | `Hero/zh-CN.ts` = `{ hero: { title } }` | `hero.title`     | `'top-key'`  |
| **filename** | **文件名 / 路径**    | `en/common.json` = `{ ok }`             | `common.ok`      | `'filename'` |
| **flat**     | 无                   | `zh-CN.ts` = `{ greeting: { hello } }`  | `greeting.hello` | `'flat'`     |

## 安装（PackSpec / lazy.nvim）

```lua
{
  url = 'beixiyo/vv-i18n.nvim',
  main = 'vv-i18n',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  ft = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  opts = {
    sources = { { prefix = '', discover = { 'src/locales' }, mount = 'flat', namespace = 'flat' } },
  },
}
```

> `sources` 默认为空 → 不激活；按你的布局配好才生效，非匹配项目零噪声

## 按布局对照配置（找到你的文件树，抄对应那段）

> locale 文件格式：**JS / TS 对象导出 + JSON**（`export const x = {...} (as const)` / `export default {...}` / `module.exports` / 裸 `{...}` / `.json`）。其它格式（YAML / PO 等）传 `parse` 自定义解析函数读入（见下「自定义解析」）

### top-key —— 命名空间在文件**内容**顶层 key

```
packages/ui/src/
  components/Hero/locales/
    zh-CN.ts   = { hero: { title: '英雄' } }   → 全键  ui.hero.title
    en-US.ts
  i18n/common/{zh-CN,en-US}.ts                 → 全键  ui.common.*
```

```ts
const t = useUiT()                            // hook 注入前缀 ui
t('hero.title')   // Hero/locales/zh-CN.ts  { hero: { title } }  →  ui.hero.title
```

```lua
{
  prefix    = 'ui',
  root      = 'packages/ui/src',
  discover  = { 'components/*/locales', 'i18n/common' },
  mount     = 'top-key',
  namespace = 'two-level',   -- useUiT() 注入前缀 ui
  lang      = '{lang}.ts',
  hooks     = { 'useUiT' },
}
```

### filename —— 命名空间在**文件名 / 路径**（键在文件根，react-i18next 标准）

```
src/locales/
  en-US/common.json = { ok: 'OK' }   → 全键  common.ok
  en-US/home.json                    → 全键  home.*
  zh-CN/common.json
```

```ts
const { t } = useTranslation('common')        // hook 参数 = 命名空间
t('ok')   // locales/zh-CN/common.json  { ok }  →  common.ok
```

```lua
{
  prefix    = '',
  root      = 'src/locales',
  lang      = '{lang}/{ns}.json',   -- en-US/common.json → lang=en-US, ns=common
  mount     = 'filename',
  namespace = 'hook-arg',
  hooks     = { 'useTranslation' },
}
```

### flat —— **无**命名空间

```
locales/
  zh-CN.ts = { greeting: { hello: '你好' } }   → 全键  greeting.hello
  en-US.ts
```

```ts
const { t } = useTranslation()
t('greeting.hello')   // locales/zh-CN.ts  { greeting: { hello } }  →  greeting.hello
```

```lua
{
  prefix    = '',
  discover  = { 'locales' },
  mount     = 'flat',
  namespace = 'flat',
  lang      = '{lang}.ts',
}
```

### mono-repo —— 一包一源，各自规则（混用上面任意布局）

```lua
sources = {
  { prefix = 'web', root = 'apps/web',        discover = { 'src/locales' },         mount = 'flat',     namespace = 'flat' },
  { prefix = 'ui',  root = 'packages/ui/src', discover = { 'components/*/locales' }, mount = 'top-key',  namespace = 'two-level', hooks = { 'useUiT' } },
}
```

## 四个可配轴（每个都「字面量 | 函数」）

| 轴          | 作用            | 字面量                                              | 函数                       |
| ----------- | --------------- | --------------------------------------------------- | -------------------------- |
| `discover`  | 找 locale 目录  | `{ 'components/*/locales' }`（glob，相对 `root`）   | `fn(root) -> dirs`         |
| `lang`      | 文件 → 语言码   | `'{lang}.ts'` / `'{lang}/{ns}.json'` / 数组         | `fn(path) -> 'zh-CN'\|nil` |
| `mount`     | 文件 → 命名空间 | `'top-key'` / `'filename'` / `'flat'`               | `fn(ctx) -> ns`            |
| `namespace` | 调用点 → 前缀   | `'flat'` / `'hook-arg'` / `'fixed'` / `'two-level'` | `fn(ctx) -> prefix\|nil`   |

`namespace` 字面量含义：

- `flat`：`t('x')` → `x`
- `hook-arg`：`useXxx('common')` → 前缀 `common`（`t('ok')` → `common.ok`）
- `fixed`：固定用 source 的 `prefix`，忽略 hook 参数
- `two-level`：`prefix[.<hook 参数>]`

> `prefix` 只写在 source 上，索引侧与调用侧共用（单一真相）。`mount` 与 `namespace` 须配成对
> （上方每行都成对）

## 完整配置参考

```lua
require('vv-i18n').setup({
  root = nil,                          -- nil：自动探测项目根
  sources = {
    {
      prefix = '',
      root = nil,                      -- 相对项目根，或绝对路径
      discover = nil,                  -- glob 数组或 function(root) -> 目录列表
      dirs = nil,                      -- 显式目录，与 discover 合并
      lang = nil,                      -- 覆盖全局 lang
      mount = nil,                     -- 覆盖全局 mount
      namespace = nil,                 -- 覆盖全局 namespace
      hooks = nil,                     -- 覆盖全局 hooks
      t = nil,                         -- 覆盖全局翻译函数名
      parse = nil,                     -- 覆盖全局读侧解析器
    },
  },
  hooks = { 'useTranslation' },
  t = { 't' },
  lang = { '{lang}.ts', '{lang}.tsx', '{lang}.js', '{lang}.json' },
  mount = 'top-key',
  namespace = 'hook-arg',
  namespace_separator = ':',
  key_separator = '.',
  ignore_key = nil,                    -- function(full_key) -> boolean；返回真值会在所有功能中排除该 key
  quote_style = 'auto',                -- 'single' | 'double' | 'auto'
  indent = nil,                        -- nil：从目标文件推断
  display = {
    enable = true,
    lang = nil,
    preferred_langs = {},              -- 空时选择字典序首个语言
    max_width = 40,
    icon = '󰗊 ',
    missing_icon = '⚠ ',
    hl = 'VVI18nPreview',
    missing_hl = 'VVI18nMissing',
    style = nil,                       -- 覆盖 hl 的高亮属性
    missing_style = nil,
    render = nil,                      -- function(ctx) -> 字符串 | 虚拟文本片段 | nil
  },
  panel = {
    width = 56,
    position = 'right',
    state = nil,                       -- 默认使用共享状态 vv-i18n/keys
    mappings = nil,                    -- nil=默认，false=不注册，table=完整替换
    on_attach = nil,
    help = nil,
    render = nil,                      -- 自定义 winbar/header/node/empty/footer
  },
  references = {
    enable = true,
    icon = '󰗊 ',
    hl = 'Comment',                    -- 图标与文字高亮
    count_hl = 'VVI18nReferenceCount', -- 数字高亮组
    count_style = nil,                 -- nil：主题 `Statement` 前景色向背景混 30%（柔和、不加粗）；或 { fg = '#f5c2e7' }
    jump_single = false,               -- 只有一个引用时直接跳转
    show_zero = false,                 -- 显示零引用虚拟文本
    render = nil,                      -- 自定义定义处引用数
    scanners = {},                     -- 新增或覆盖其他语言 scanner
    panel = {
      width = 62,
      position = 'right',
      preview_debounce_ms = 80,
      state = nil,
      mappings = nil,
      on_attach = nil,
      help = nil,
      render = nil,                    -- 自定义引用节点
    },
  },
  unused = {
    copy = {
      definition_language = 'en',      -- 'all' 或指定语言；缺失时自动回退
      include_values = false,
      render = nil,                    -- function(ctx) -> Markdown 字符串
    },
    panel = {
      width = 68,
      position = 'right',
      state = nil,
      mappings = nil,
      on_attach = nil,
      help = nil,
      render = nil,
    },
  },
  ft = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  project_config = true,               -- 加载可信的 .vv-i18n.lua
  parse = nil,                         -- 自定义读侧解析器
})
```

`ignore_key` 收到的是**完整 key**，包含 source `prefix` 与 namespace（例如 `app.common._draft`），因此按 key 名做规则时应逐段匹配，而不是匹配整串。返回真值的 key 会从定义索引、引用索引、面板、unused 分析、光标操作和写入定位中排除；回调抛错会记入索引 errors 或扫描 failures，该 key 按不忽略处理。例如，忽略任一段以 `_` 开头的 key：

```lua
ignore_key = function(full_key)
  for segment in full_key:gmatch('[^.]+') do
    if vim.startswith(segment, '_') then return true end
  end
  return false
end
```

### 自定义 `display.render`

渲染函数接收以下上下文，返回字符串、虚拟文本片段，或返回 `nil` 使用默认渲染：

```lua
display = {
  render = function(ctx)
    -- ctx = { full_key, value, lang, kind, missing, per, literal, icon, hl, max_width }
    if ctx.missing then return { { '✗ ' .. ctx.literal, 'Error' } } end
    return { { ctx.icon, 'Comment' }, { ctx.value, 'String' } }
  end,
}
```

## 项目级配置 `.vv-i18n.lua`

项目根放一个 `.vv-i18n.lua`，**整份覆盖** nvim 里的配置（nvim setup 仅作默认/兜底）。这样一份 nvim 配置
即可适配多个项目，各自带精确 source：

```lua
-- <项目根>/.vv-i18n.lua
return {
  sources = {
    { prefix = '', discover = { 'src/locales' }, mount = 'filename', namespace = 'hook-arg' },
  },
}
```

- 从当前文件向上找 `.vv-i18n.lua`；找到则**全覆盖**，找不到回退 nvim 基线
- **安全**：经 Neovim 内置 `vim.secure` —— 首次加载弹窗确认信任，内容改动后重新确认（信任记录在
  `stdpath('state')/trust`，由 nvim 维护）
- 切目录（`:cd`）自动重载；或随时 `:VVI18nReload`。关掉用 `project_config = false`

## 自定义解析 `parse`（读侧，任意格式）

默认解析器只认 JS/TS 对象 + JSON。其它格式（YAML / `.properties` / PO …）传一个 `parse` 函数（全局或 per-source）：收文件内容、返回叶子列表,即得**预览 / 跳转 / 完整度**

```lua
-- 例：key=value 行格式
parse = function(content, path)
  local leaves, top, row = {}, {}, 0
  for line in (content .. '\n'):gmatch('([^\n]*)\n') do
    local k, v = line:match('^%s*([%w%.]+)%s*=%s*(.-)%s*$')
    if k then
      top[#top + 1] = k
      leaves[#leaves + 1] = { path = { k }, dotted = k, kind = 'string', value = v, row = row, col = 0 }
    end
    row = row + 1
  end
  return { leaves = leaves, top_keys = top }
end
```

- 返回 `{ leaves = VVI18nLeaf[], top_keys? }`;`leaf = { path=string[], dotted, kind='string', value, row, col, key_range? }`(`row/col` 0-based,供跳转)
- `key_range = { srow, scol, erow, ecol }`(0-based、end-exclusive)可选:提供时光标命令按 key 节点精确定位定义;缺省时退化为按值起始行匹配
- **仅读侧**。写回（`:VVI18nEdit` / `AddKey` / `SetValue`）仍是 tree-sitter 字节段引擎,对自定义格式不可用

## 命令

所有依赖光标位置的命令都同时支持翻译调用点和 locale key 定义位置

| 命令                               | 作用                           |
| ---------------------------------- | ------------------------------ |
| `:VVI18nKeys`                      | 键浏览 / 完整度 / 同步编辑面板 |
| `:VVI18nMissing`                   | 仅缺失 key，按缺失语言分组     |
| `:VVI18nReferences`                | 打开光标处调用或定义的引用侧栏 |
| `:VVI18nUnused`                    | 潜在无用 key 核查/复制/删除面板 |
| `:VVI18nEdit`                      | 光标处调用或定义的同步编辑浮窗 |
| `:VVI18nInfo`                      | 光标处调用或定义的各语言译文   |
| `:VVI18nJump`                      | 跳到 locale 定义               |
| `:VVI18nSetValue`                  | 改某语言值（单语言快速）       |
| `:VVI18nAddKey`                    | 补缺失语言                     |
| `:VVI18nReload`                    | 重建索引                       |
| `:VVI18n[Enable\|Disable\|Toggle]` | 行内预览开关                   |

### 潜在无用 key

`:VVI18nUnused` 展示引用扫描没有命中的**候选**

对于 ``t(`prefix.${value}`)`` 这类动态模板，扫描器只记录可静态证明的固定前缀和调用位置，
不推导运行时值。被该前缀覆盖的 key 显示在 `Unknown` 分组

### 扩展其他语言的引用 scanner

内置 scanner 支持 `ts`、`tsx`、`js`、`jsx`。其他语言通过 adapter 接入：

```lua
references = {
  scanners = {
    {
      id = 'python',
      extensions = { 'py' },
      names = { 'gettext', '_' },
      collect = function(ctx)
        return my_python_i18n_scanner(ctx.content, ctx.path)
      end,
    },
  },
}
```

`collect` 返回带 0-based `range` 的 `hit`、`dynamic`、`ambiguous` 或 `missing`；字段见
[`VVI18nReferenceResult`](lua/vv-i18n/types.lua)

## 测试

```bash
bash tests/run.sh
```

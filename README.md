# vv-i18n.nvim

TS/TSX i18n 的**行内预览 / 跳转定义 / 同步改值 / 补缺失语言**，对标 _lokalise_ · _i18n-ally_

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

## 全部配置

```lua
require('vv-i18n').setup({
  root = nil,                          -- nil = 自动探测

  -- 全局默认（每个 source 可覆盖同名字段）
  hooks = { 'useTranslation' },
  t = { 't' },
  lang = { '{lang}.ts', '{lang}.json' },
  mount = 'top-key',
  namespace = 'hook-arg',

  sources = { --[[ 见上 ]] },

  -- 高级
  namespace_separator = ':',           -- 绝对命名空间 ns<sep>key；'' 关闭
  key_separator = '.',
  quote_style = 'auto',                -- 写回引号 single|double|auto
  indent = nil,                        -- 写回缩进，nil=推断
  project_config = true,               -- 探测项目根 .vv-i18n.lua（见下）
  parse = nil,                         -- 自定义读侧解析（非 JS/JSON 格式，见下）

  display = {
    enable = true,
    preferred_langs = {},              -- 预览首选语言（空=字典序首个）
    max_width = 40,
    icon = '󰗊 ',                       -- 译文前缀图标
    -- 样式：style 直接定义 { fg=, bg=, italic=, bold= }；不给则默认 注释色 + 斜体（随主题）
    style = nil,                       -- 译文样式（覆盖 hl）
    missing_style = nil,               -- 缺失样式
    -- 也可只换高亮组：hl / missing_hl；或 lang（固定预览语言）/ missing_icon
    render = nil,                      -- 函数完全自定义渲染（见下）
  },
})
```

> 预览模式：**conceal 就地替换** —— 隐藏 `t('key')` 里的字符串、inline 插入「图标 + 译文」，
> **长度随译文动态变化**（代码会随之重排）；**光标落在该 `t()` 上自动还原**原文（token 级，同行多个互不干扰）
> 缺失键显示 `⚠ 键`。依赖 conceal：开启时给匹配窗口设 `conceallevel=2` / `concealcursor`，关闭时还原

### 自定义渲染 `display.render`

收上下文、返回字符串或 virt_text chunks（`nil` 落默认）：

```lua
display = {
  render = function(ctx)
    -- ctx = { full_key, value, lang, kind, missing, per, literal, icon, hl, max_width }
    if ctx.missing then return { { '✗ ' .. ctx.literal, 'Error' } } end
    return { { ctx.icon, 'Comment' }, { ctx.value, 'String' } }  -- 图标与译文分色
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

- 返回 `{ leaves = VVI18nLeaf[], top_keys? }`;`leaf = { path=string[], dotted, kind='string', value, row, col }`(`row/col` 0-based,供跳转)
- **仅读侧**。写回（`:VVI18nEdit` / `AddKey` / `SetValue`）仍是 tree-sitter 字节段引擎,对自定义格式不可用

## 命令

| 命令                               | 作用                           |
| ---------------------------------- | ------------------------------ |
| `:VVI18nKeys`                      | 键浏览 / 完整度 / 同步编辑面板 |
| `:VVI18nEdit`                      | 光标处键的多语言同步编辑浮窗   |
| `:VVI18nInfo`                      | 光标处键各语言译文             |
| `:VVI18nJump`                      | 跳到 locale 定义               |
| `:VVI18nSetValue`                  | 改某语言值（单语言快速）       |
| `:VVI18nAddKey`                    | 补缺失语言                     |
| `:VVI18nReload`                    | 重建索引                       |
| `:VVI18n[Enable\|Disable\|Toggle]` | 行内预览开关                   |

## 测试

```bash
bash tests/run.sh
```


<div align="center">
  <h1>vv-i18n.nvim</h1>
  <p>English | <a href="./README.zh-CN.md">中文</a></p>
  <img src="https://github.com/beixiyo/vv-i18n.nvim/releases/download/assets-2026-07-25/vv-i18n.png" alt="vv-i18n demo" width="900" />
  <p>Want my Neovim config? See <a href="https://github.com/beixiyo/dotfiles">dotfiles</a></p>
  <p><strong>Inline previews, definition jumps, synchronized edits, and missing-locale completion for TS/TSX i18n</strong>, inspired by <em>lokalise</em> and <em>i18n-ally</em></p>
  <p>
    <img src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.10+" />
    <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />
  </p>
</div>

vv-i18n targets projects that generic tools cannot model: locale data may be named exports from TS/JS modules or JSON, several files may be mounted below a namespace at runtime, and hooks may inject key prefixes. **Locale discovery, file-to-language mapping, file-to-namespace mapping, and call-site prefixes each accept either a literal strategy or a function.** Defaults are neutral, and the core parser uses treesitter throughout.

## Identify your project layout

| Layout | Namespace location | Example | Fully qualified key | `mount` |
|--------|--------------------|---------|---------------------|---------|
| **top-key** | Top-level key inside the file | `Hero/zh-CN.ts` = `{ hero: { title } }` | `hero.title` | `'top-key'` |
| **filename** | Filename or path | `en/common.json` = `{ ok }` | `common.ok` | `'filename'` |
| **flat** | No namespace | `zh-CN.ts` = `{ greeting: { hello } }` | `greeting.hello` | `'flat'` |

## Installation with PackSpec or lazy.nvim

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

> `sources` is empty by default, so the plugin remains inactive until a layout is configured and produces no noise in unrelated projects.

## Configuration by layout

Locale files may be **JS/TS object exports or JSON**: `export const x = {...} (as const)`, `export default {...}`, `module.exports`, a bare object, or `.json`. For YAML, PO, and other formats, provide a custom read-side `parse` function as described below.

### top-key: namespace stored in the file content

```text
packages/ui/src/
  components/Hero/locales/
    zh-CN.ts   = { hero: { title: 'Hero' } }   → ui.hero.title
    en-US.ts
  i18n/common/{zh-CN,en-US}.ts                 → ui.common.*
```

```ts
const t = useUiT()          // The hook injects the ui prefix
t('hero.title')             // Resolves to ui.hero.title
```

```lua
{
  prefix    = 'ui',
  root      = 'packages/ui/src',
  discover  = { 'components/*/locales', 'i18n/common' },
  mount     = 'top-key',
  namespace = 'two-level',
  lang      = '{lang}.ts',
  hooks     = { 'useUiT' },
}
```

### filename: namespace stored in the filename or path

This is the standard `react-i18next` layout, with keys at the file root.

```text
src/locales/
  en-US/common.json = { ok: 'OK' }   → common.ok
  en-US/home.json                    → home.*
  zh-CN/common.json
```

```ts
const { t } = useTranslation('common') // The hook argument supplies the namespace
t('ok')                                // Resolves to common.ok
```

```lua
{
  prefix    = '',
  root      = 'src/locales',
  lang      = '{lang}/{ns}.json',
  mount     = 'filename',
  namespace = 'hook-arg',
  hooks     = { 'useTranslation' },
}
```

### flat: no namespace

```text
locales/
  zh-CN.ts = { greeting: { hello: 'Hello' } }   → greeting.hello
  en-US.ts
```

```ts
const { t } = useTranslation()
t('greeting.hello')
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

### Monorepos: one source per package

Each source may use any layout above:

```lua
sources = {
  { prefix = 'web', root = 'apps/web', discover = { 'src/locales' }, mount = 'flat', namespace = 'flat' },
  { prefix = 'ui', root = 'packages/ui/src', discover = { 'components/*/locales' }, mount = 'top-key', namespace = 'two-level', hooks = { 'useUiT' } },
}
```

## Four configurable axes

Every axis accepts either a literal strategy or a function.

| Axis | Purpose | Literal | Function |
|------|---------|---------|----------|
| `discover` | Locate locale directories | `{ 'components/*/locales' }`, a glob relative to `root` | `fn(root) -> dirs` |
| `lang` | Map a file to a language code | `'{lang}.ts'`, `'{lang}/{ns}.json'`, or an array | `fn(path) -> 'en-US'\|nil` |
| `mount` | Map a file to a namespace | `'top-key'`, `'filename'`, or `'flat'` | `fn(ctx) -> ns` |
| `namespace` | Map a call site to a prefix | `'flat'`, `'hook-arg'`, `'fixed'`, or `'two-level'` | `fn(ctx) -> prefix\|nil` |

Literal `namespace` strategies mean:

- `flat`: `t('x')` resolves to `x`
- `hook-arg`: `useXxx('common')` contributes `common`, so `t('ok')` resolves to `common.ok`
- `fixed`: always uses the source `prefix` and ignores hook arguments
- `two-level`: combines `prefix` with an optional hook argument

`prefix` belongs only to the source and is shared by indexing and call-site resolution as a single source of truth. Pair `mount` and `namespace` consistently, as in each layout above.

## Complete configuration

```lua
require('vv-i18n').setup({
  root = nil,                          -- nil enables automatic detection
  hooks = { 'useTranslation' },        -- Global defaults, overridable per source
  t = { 't' },
  lang = { '{lang}.ts', '{lang}.json' },
  mount = 'top-key',
  namespace = 'hook-arg',
  sources = { --[[ see above ]] },
  namespace_separator = ':',           -- Absolute namespace ns<sep>key; '' disables it
  key_separator = '.',
  quote_style = 'auto',                -- single | double | auto when writing
  indent = nil,                        -- nil infers indentation when writing
  project_config = true,               -- Detect .vv-i18n.lua at the project root
  parse = nil,                         -- Custom read-side parser for non-JS/JSON formats
  display = {
    enable = true,
    preferred_langs = {},              -- Empty selects the first language alphabetically
    max_width = 40,
    icon = '󰗊 ',
    style = nil,                       -- Translation style overriding its highlight
    missing_style = nil,
    -- hl, missing_hl, lang, and missing_icon may also be overridden
    render = nil,                      -- Fully custom rendering function
  },
})
```

Preview mode uses **in-place concealment**. It hides the string inside `t('key')` and inserts the icon and translation inline. Its width follows the translated value and reflows surrounding code. Moving the cursor onto that `t()` restores the source token, independently for multiple calls on one line. Missing keys display `⚠ key`. Matching windows temporarily receive `conceallevel=2` and `concealcursor`, and their original values are restored when preview is disabled.

### Custom `display.render`

The renderer receives context and returns a string or virtual-text chunks. Returning `nil` uses the default renderer.

```lua
display = {
  render = function(ctx)
    -- { full_key, value, lang, kind, missing, per, literal, icon, hl, max_width }
    if ctx.missing then return { { '✗ ' .. ctx.literal, 'Error' } } end
    return { { ctx.icon, 'Comment' }, { ctx.value, 'String' } }
  end,
}
```

## Project configuration with `.vv-i18n.lua`

Place `.vv-i18n.lua` at a project root to **replace the entire Neovim configuration** for that project. The `setup()` configuration remains the fallback, allowing one editor configuration to support projects with precise, independent sources.

```lua
-- <project-root>/.vv-i18n.lua
return {
  sources = {
    { prefix = '', discover = { 'src/locales' }, mount = 'filename', namespace = 'hook-arg' },
  },
}
```

- The plugin searches upward from the current file. A discovered file fully replaces the baseline; otherwise the baseline remains active
- Loading is protected by Neovim's `vim.secure`. The first load asks for trust, and changed content requires confirmation again. Neovim stores trust records under `stdpath('state')/trust`
- Changing directories with `:cd` reloads the configuration automatically; `:VVI18nReload` reloads on demand. Set `project_config = false` to disable discovery

## Custom read-side parsing

The default parser recognizes JS/TS objects and JSON. For YAML, `.properties`, PO, or another format, provide `parse` globally or per source. It receives the file content and path and returns leaves, enabling previews, definition jumps, and completeness checks.

```lua
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

Return `{ leaves = VVI18nLeaf[], top_keys? }`, where each leaf is `{ path=string[], dotted, kind='string', value, row, col }`; `row` and `col` are zero-based definition positions. This hook is **read-only**. Write operations such as `:VVI18nEdit`, `:VVI18nAddKey`, and `:VVI18nSetValue` still use the treesitter byte-range engine and are unavailable for custom formats.

## Commands

| Command | Action |
|---------|--------|
| `:VVI18nKeys` | Browse keys, inspect completeness, and synchronize values |
| `:VVI18nMissing` | Show only missing keys, grouped by missing language |
| `:VVI18nEdit` | Edit all language values for the key under the cursor |
| `:VVI18nInfo` | Show every translation for the key under the cursor |
| `:VVI18nJump` | Jump to a locale definition |
| `:VVI18nSetValue` | Quickly update one language |
| `:VVI18nAddKey` | Add missing language values |
| `:VVI18nReload` | Rebuild the index |
| `:VVI18nEnable`, `:VVI18nDisable`, `:VVI18nToggle` | Control inline previews |

## Tests

```bash
bash tests/run.sh
```

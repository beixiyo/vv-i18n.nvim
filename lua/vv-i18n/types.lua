-- 仅供 LuaLS 使用的公共类型声明；运行时代码不得依赖此模块
---@class VVI18nSource
---@field prefix? string         命名空间根；''=无前缀 @default ''
---@field root? string           本源扫描根（相对 config.root 或绝对）；同时是调用点解析的作用域：配了 root 时只解析该目录下文件中的 t() 调用，nil=不限（目录默认 config.root） @default nil
---@field discover? string[]|fun(root: string): string[]  发现 locale 目录：glob 数组 或 函数 @default nil
---@field dirs? string[]         显式 locale 目录（与 discover 叠加） @default nil
---@field lang? string|string[]|fun(path): (string|table|nil)  文件→语言（覆盖全局）
---@field mount? 'top-key'|'filename'|'flat'|fun(ctx): string?  文件→命名空间（覆盖全局）
---@field namespace? 'flat'|'hook-arg'|'fixed'|'two-level'|fun(ctx): string?  调用点→前缀（覆盖全局）
---@field hooks? string[]        产出 t 的 hook 名（覆盖全局）
---@field t? string[]            翻译函数名（覆盖全局）
---@field parse? fun(content: string, path: string): table?  自定义读侧解析（覆盖全局）

---@class VVI18nConfig
---@field root? string           项目根；nil=自动探测 @default nil
---@field sources VVI18nSource[]  locale 来源（必填，可多个） @default {}
---@field hooks string[]         全局默认 hook 名 @default {'useTranslation'}
---@field t string[]             全局默认翻译函数名 @default {'t'}
---@field lang string|string[]|function  全局默认 文件→语言 @default {'{lang}.ts','{lang}.tsx','{lang}.js','{lang}.json'}
---@field mount string|function  全局默认 mount @default 'top-key'
---@field namespace string|function  全局默认 namespace @default 'hook-arg'
---@field namespace_separator string  绝对命名空间 ns<sep>key @default ':'
---@field key_separator string   全键各段连接符 @default '.'
---@field ignore_key? fun(full_key: string): boolean  参数为含 source prefix 与 namespace 的完整 key；返回真值时从索引、引用与光标操作排除；抛错记入 errors 并按不忽略处理 @default nil
---@field quote_style 'single'|'double'|'auto'  写回引号 @default 'auto'
---@field indent? string         写回缩进；nil=推断 @default nil
---@field display VVI18nDisplayConfig
---@field panel VVI18nKeyPanelConfig
---@field references VVI18nReferencesConfig
---@field unused VVI18nUnusedConfig
---@field ft string[]            生效文件类型 @default ts/tsx/js/jsx
---@field project_config boolean 探测项目根 .vv-i18n.lua（首次信任后全覆盖本配置） @default true
---@field parse? fun(content: string, path: string): table?  自定义读侧解析（YAML/PO 等）；返回 { leaves: VVI18nLeaf[], top_keys?: string[] }。nil=默认 tree-sitter（JS/JSON）

---@class VVI18nLeaf  自定义 parse 须返回的叶子（与默认 reader 同形）
---@field path string[]          文件内逐层 key，如 { 'hero', 'title' }
---@field dotted string          点号路径 'hero.title'（拼全键用）
---@field kind 'string'|'array'|'other'  仅 'string' 可同步编辑
---@field value string           string→真实值；其它→原始文本
---@field row integer            值起点行（0-based，跳转用）
---@field col integer            值起点列（0-based）
---@field key_range? {srow: integer, scol: integer, erow: integer, ecol: integer}  key 节点范围（0-based，定义位置光标操作用）

---@class VVI18nDisplayConfig
---@field enable boolean         @default true
---@field lang? string           固定预览语言 @default nil
---@field preferred_langs string[]  预览首选语言优先级 @default {}
---@field max_width integer      译文最大显示宽度 @default 40
---@field icon string            译文前缀图标 @default '󰗊 '
---@field missing_icon string    @default '⚠ '
---@field hl string              译文高亮组 @default 'VVI18nPreview'
---@field missing_hl string      缺失高亮组 @default 'VVI18nMissing'
---@field style? vim.api.keyset.highlight  直接定义译文样式；nil=默认 注释色+斜体
---@field missing_style? vim.api.keyset.highlight  缺失样式；nil=默认 link DiagnosticVirtualTextWarn
---@field render? fun(ctx: VVI18nRenderCtx): (string|table[]|nil)  自定义渲染：返回字符串 / virt_text chunks / nil(落默认)

---@class VVI18nKeyPanelConfig
---@field width integer          键浏览侧栏宽度 @default 56
---@field position 'left'|'right'  侧栏位置 @default 'right'
---@field state? VVStateHandle   宽度持久状态；默认注册 vv-i18n/keys @default nil
---@field mappings? false|VVTreePanelMappings  快捷键；table=完全自定义，false=不注册 @default nil
---@field on_attach? fun(panel: VVTreePanel, buf: integer)  panel buffer 配置入口
---@field help? false|VVTreePanelHelpOptions  g? 帮助面板配置 @default nil
---@field render? VVTreePanelRenderers  winbar/header/node/empty/footer 自定义渲染

---@class VVI18nRenderCtx  display.render 收到的上下文
---@field full_key string        完整键（含前缀/命名空间）
---@field value? string          选中语言的译文（缺失/非字符串时为 nil）
---@field lang? string           选中的预览语言
---@field kind 'hit'|'missing'   命中 / 缺失
---@field missing boolean
---@field per table              该键各语言条目
---@field literal string         源码里 t() 的字面量键
---@field icon string            配置的图标
---@field hl string              配置的高亮组
---@field max_width integer

---@class VVI18nReferencesConfig
---@field enable boolean         扫描项目引用并在定义处显示计数 @default true
---@field icon string            定义处引用数图标 @default '󰗊 '
---@field icon_hl string         图标高亮组 @default 'VVI18nReferenceIcon'
---@field icon_style? vim.api.keyset.highlight  图标样式；nil=link Special（对齐 vv-symbols） @default nil
---@field label string           计数标签文案 @default 'refs'
---@field hl string              定义处引用数文字高亮 @default 'Comment'
---@field count_hl string        定义处引用数数字高亮组 @default 'VVI18nReferenceCount'
---@field count_style? vim.api.keyset.highlight  数字样式；nil=link Special
---@field jump_single boolean    单个引用时直接跳转，不打开侧栏 @default false
---@field show_zero boolean      是否显示零引用虚拟文本 @default false
---@field render? fun(ctx: table): (string|table[]|nil)  定义处虚拟文本自定义渲染
---@field scanners VVI18nReferenceScanner[]  附加引用 scanner；相同扩展名覆盖内置 JS/TS scanner @default {}
---@field panel VVI18nReferencesPanelConfig

---@class VVI18nReferenceScanner
---@field id? string             诊断标识 @default custom-N
---@field extensions string[]    支持的扩展名，不带前导点
---@field names string[]         用于候选文件预筛选的调用名
---@field collect fun(ctx: VVI18nReferenceScannerContext): VVI18nReferenceResult[]  返回引用证据；抛错会阻断完整扫描

---@class VVI18nReferenceScannerContext
---@field content string
---@field path string            文件绝对路径
---@field root string            项目根
---@field extension string
---@field scanner string         scanner id

---@class VVI18nReferenceResult
---@field kind 'hit'|'dynamic'|'ambiguous'|'missing'
---@field range {srow: integer, scol: integer, erow?: integer, ecol?: integer}  0-based 源码范围
---@field literal? string        源码中的原始或解码后 key
---@field full_key? string       hit/missing 的完整 key
---@field pattern? string        dynamic 保护模式，例如 cards.*
---@field prefix? string         dynamic 的静态固定前缀
---@field full_keys? string[]    ambiguous 的所有可能完整 key

---@class VVI18nReferencesPanelConfig
---@field width integer          侧栏宽度 @default 62
---@field position 'left'|'right'  侧栏位置 @default 'right'
---@field preview_debounce_ms integer  光标预览防抖 @default 80
---@field state? VVStateHandle   侧栏状态；默认注册 vv-i18n/references @default nil
---@field mappings? false|VVTreePanelMappings  快捷键；table=完全自定义，false=不注册 @default nil
---@field on_attach? fun(panel: VVTreePanel, buf: integer)  panel buffer 配置入口
---@field help? false|VVTreePanelHelpOptions  g? 帮助面板配置 @default nil
---@field render? fun(ctx: VVTreePanelRenderContext): VVTreePanelRenderRow|string  节点自定义渲染

---@class VVI18nUnusedConfig
---@field copy VVI18nUnusedCopyConfig
---@field panel VVI18nUnusedPanelConfig

---@class VVI18nUnusedCopyConfig
---@field render? fun(ctx: table): string  自定义复制内容；nil=紧凑 Markdown 审查提示
---@field definition_language string  定义路径和值使用的语言；'all'=全部，缺失时稳定回退到首个语言 @default 'en'
---@field include_values boolean  是否在定义路径后输出该语言的翻译值 @default false

---@class VVI18nUnusedPanelConfig
---@field width integer @default 68
---@field position 'left'|'right' @default 'right'
---@field state? VVStateHandle
---@field mappings? false|VVTreePanelMappings
---@field on_attach? fun(panel: VVTreePanel, buf: integer)
---@field help? false|VVTreePanelHelpOptions
---@field render? VVTreePanelRenderers

return {}

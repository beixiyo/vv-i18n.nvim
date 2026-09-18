# Changelog

## 0.1.5 - 2026-09-18

### Added

- 引用数图标独立高亮组 `VVI18nReferenceIcon`，数字默认色从主题 Statement 混色改为 link `Special`
- 引用数标签文案可配置：`references.label`，默认 `'refs'`
- 定义处引用数改为 combine 高亮模式，背景跟随底层行（光标行 cursorline 不再被截断成背景色块）

### Fixed

- 多 source 项目回归：调用点解析按 source `root` 划定辖区，文件只由所在 root 的 source 解析；
  修复互斥包的 source 凭 no-binding 前缀造出竞争 key，把命中整体判 `ambiguous`，
  导致行内预览与引用计数全部丢失的问题。绝对命名空间 `ns:key` 前缀无关、豁免辖区过滤；
  不在任何 root 内的文件仍由全部 source 尝试（保留歧义保护）；空串 `root` 视为未配置

## 0.1.4 - 2026-09-02

### Added

- 光标位于 locale 文件的 key 定义处时，可直接操作该 key
- 定义处引用数虚拟文本的数字改为独立高亮组 `VVI18nReferenceCount`
- 新增 `ignore_key(full_key)`

## 0.1.3 - 2026-08-19

### Added

- 新增 `:VVI18nUnused` 潜在无用 key 面板，支持逐项/批量复制审查材料及事务删除
- 新增可配置引用 scanner adapter；内置 JS/TS scanner 与外部语言 scanner 共用统一证据契约
- 动态模板、歧义调用和不可靠字符串转义会生成保护证据，避免把运行时 key 误判为可删除候选
- 无用 key 复制内容支持自定义 renderer、定义语言选择、value 开关和紧凑中文 Markdown
- keys、missing、references 与 unused 侧栏支持 `/` 实时筛选；可匹配 key、译文、文件路径与引用源码

### Changed

- 引用索引按 registry/store/scanner 职责拆分，全量与增量扫描统一 latest-wins 生命周期
- editor 与 info 浮窗复用 `vv-utils.ui_window`，扫描过程复用 `vv-utils.loading`
- locale 写回统一文件操作流程，并支持安全删除 JSON/JS/TS 对象 key
- 树形侧栏快捷键提示改用 `vv-utils.tree_panel` 固定多行 toolbar：按宽度完整换行、独立滚动

## 0.1.2 - 2026-08-04

### Fixed

- 引用索引扫描改为 latest-wins：后续刷新或 clear 会物理终止旧的 `rg` 进程，并阻止已排队的旧回调重新写入索引

## 0.1.1 - 2026-07-26

### Added

- 在 locale 原始定义处显示引用数虚拟文本
- 新增 `:VVI18nReferences`，使用可折叠的 Trouble 风格侧栏浏览、预览并跳转当前 key 的全部引用
- 引用计数和侧栏节点均支持自定义 render 函数
- 引用查询可配置单个结果直接跳转，以及是否显示零引用虚拟文本

### Changed

- 多语言编辑器改为单窗口固定输入槽，语言标签使用虚拟文本，保存后保持窗口打开
- `<CR>` 在 Normal 和 Insert 模式下跳转当前语言定义，`<C-s>` 统一保存
- 编辑器按数据模型、输入槽、跳转和生命周期拆分为 `editor/` 模块
- `:VVI18nKeys` 复用 `vv-utils.tree_panel`，支持左右位置、持久宽度、自定义映射与渲染；顶部语言选择会即时切换下方 key 预览
- 引用侧栏复用 `vv-utils.tree_panel` 的树模型、折叠状态、预览和跳转生命周期
- 配置、项目发现、索引查询、命令和生命周期按职责拆分为独立模块

### Fixed

- 未保存内容跳转时给出英文提示，关闭时仅确认 `Yes` 后丢弃修改
- 修复 Backspace 到输入槽边界后插入 `<Nop>` 的问题
- 修复 `dd` 清空输入槽后光标落入语言标签区域、后续输入无效的问题
- 修复多 split 场景跳转到错误窗口的问题
- 编辑器跳转 locale 定义时关闭 keys panel，避免随后关闭 panel 又恢复最初的 buffer 与光标
- 已打开的引用侧栏可直接切换到光标下的另一 key
- 缺失语言分组的顶部统计按完整 key 去重

## 0.1.0 - 2026-07-13

### Added

- `VVI18nInfo` 改为可聚焦的多语言预览窗口，支持编辑、重载和复制 key
- 新增 `:VVI18nMissing`，直接打开仅缺失 key、按缺失语言分组的面板
- 面板新增 `g?` 帮助窗口，复用 `vv-utils.help_panel`

### Changed

- 面板支持从分组行或 key 行使用 `h/l`、方向键折叠展开，并复用 `vv-icons` 文件树图标
- `g` 可在普通挂载点分组和缺失语言分组之间切换
- 多语言编辑器使用固定值列和简洁英文提示；打开缺失项时直接聚焦对应语言的输入位置
- 复数译文按 `one`、`other` 等 CLDR 形态展开为独立可编辑行，单行预览优先展示 `other`

### Fixed

- `display`：`ft_match` 在 `vim.schedule` 延迟回调里可能拿到已被 wipe 的 buffer id（瞬态 buffer 一开即关），裸读 `vim.bo[bufnr]` 抛 `Invalid buffer id`。补 `nvim_buf_is_valid` 守卫
- 修复复数对象父 key 被误报为缺失，保存时触发 `key-exists` 的问题
- 修复缺失项编辑器光标停在行首、空值行看不出输入位置的问题

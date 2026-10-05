# Changelog

## 0.1.8 - 2026-10-04

### Changed

- 引用侧栏扫描时显示动画与 `…` 计数，避免误报零引用
- 无用 key 面板扫描动画改用 `vv-utils.loading`

## 0.1.7 - 2026-09-30

### Changed

- 优化定义引用数查询与行内预览缓存，buffer 切换开销从约 25ms 降至约 1ms

## 0.1.6 - 2026-09-26

### Added

- 新增 `refresh_if_stale()`，检测磁盘 locale 变化并重建索引、刷新预览

### Fixed

- 外部改写 locale 后，切回 nvim、进入 buffer、编辑或保存时自动更新预览；`:VVI18nReload` 后也立即刷新

## 0.1.5 - 2026-09-18

### Added

- 新增引用图标高亮组 `VVI18nReferenceIcon` 与 `references.label`（默认 `'refs'`），引用数字默认高亮改为链接 `Special`
- 定义处引用数保留底层行背景，不再截断 cursorline

### Fixed

- 多 source 调用解析按 `root` 隔离，修复跨包歧义导致预览和计数丢失；`ns:key` 豁免过滤，辖区外文件仍尝试全部 source，空串 `root` 视为未配置

## 0.1.4 - 2026-09-02

### Added

- 光标位于 locale key 定义处时可直接操作该 key
- 新增引用数字高亮组 `VVI18nReferenceCount` 与 `ignore_key(full_key)`

## 0.1.3 - 2026-08-19

### Added

- 新增 `:VVI18nUnused` 潜在无用 key 面板，支持逐项/批量复制审查材料及事务删除，并可自定义复制格式
- 新增引用 scanner adapter，内置 JS/TS 与外部语言 scanner 共用证据契约
- 动态模板、歧义调用与不可靠字符串转义会保护相关 key，避免误删运行时 key
- keys、missing、references 与 unused 侧栏支持 `/` 实时筛选 key、译文、路径与引用源码

### Changed

- 全量与增量引用扫描统一为 latest-wins，扫描显示加载动画
- locale 写回支持安全删除 JSON/JS/TS 对象 key
- 树形侧栏快捷键提示使用固定多行 toolbar，支持按宽度换行与独立滚动

## 0.1.2 - 2026-08-04

### Fixed

- 后续引用刷新或 clear 会终止旧 `rg` 进程，过期回调不再写回索引

## 0.1.1 - 2026-07-26

### Added

- locale 定义处显示引用数，新增 `:VVI18nReferences` 可折叠侧栏浏览、预览并跳转引用
- 引用计数与侧栏节点支持自定义 renderer，引用查询可配置单结果直接跳转与零引用显示

### Changed

- 多语言编辑器改为单窗口固定输入槽与虚拟语言标签，保存后保持打开；Normal / Insert 下 `<CR>` 跳转定义，`<C-s>` 保存
- `:VVI18nKeys` 支持左右位置、持久宽度、自定义映射与渲染，语言选择即时更新 key 预览

### Fixed

- 未保存内容跳转时给出英文提示，关闭时仅确认 `Yes` 后丢弃修改
- 修复输入槽边界 Backspace 插入 `<Nop>`、`dd` 后光标进入标签区域导致输入无效的问题
- 修复多 split 跳错窗口，以及跳转定义后关闭 keys panel 恢复旧 buffer 与光标的问题
- 已打开的引用侧栏可切换到光标下另一 key，缺失语言顶部统计按完整 key 去重

## 0.1.0 - 2026-07-13

### Added

- `VVI18nInfo` 改为可聚焦多语言预览窗口，支持编辑、重载与复制 key
- 新增 `:VVI18nMissing` 按缺失语言分组的面板，以及 `g?` 帮助窗口

### Changed

- 面板支持在分组或 key 行用 `h/l`、方向键折叠展开，使用 `vv-icons` 文件树图标；`g` 切换挂载点与缺失语言分组
- 多语言编辑器使用固定值列和简洁英文提示，缺失项直接聚焦对应语言输入位置
- CLDR 复数形态展开为独立可编辑行，单行预览优先展示 `other`

### Fixed

- 瞬态 buffer 被 wipe 后的预览回调不再报 `Invalid buffer id`
- 修复复数父 key 误报缺失并在保存时触发 `key-exists`，以及缺失项光标与空值输入位置不清晰的问题

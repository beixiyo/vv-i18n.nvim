# Changelog

## Unreleased

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

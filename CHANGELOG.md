# Changelog

## Unreleased

### Fixed

- `display`：`ft_match` 在 `vim.schedule` 延迟回调里可能拿到已被 wipe 的 buffer id（瞬态 buffer 一开即关），裸读 `vim.bo[bufnr]` 抛 `Invalid buffer id`。补 `nvim_buf_is_valid` 守卫

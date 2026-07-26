-- vv-i18n.editor.navigation — locale 定义解析与目标窗口跳转
local M = {}

function M.main_window()
  local current = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(current).relative == '' then return current end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == '' then return win end
  end
end

function M.current_definition(state, row)
  local target = state.rows[row]
  local per = state.plugin.lookup(state.full_key)
  local entry = per and per[target.lang]
  if not entry then return end

  if target.label and target.label ~= target.lang then
    local form = target.label:sub(#target.lang + 2)
    for _, variant in ipairs(entry.variants or {}) do
      if variant.form == form then
        return {
          file = entry.file,
          row = variant.row,
          col = variant.col,
        }
      end
    end
  end

  return entry
end

function M.jump(state, row, close)
  local entry = M.current_definition(state, row)
  if not entry then
    return vim.notify('[vv-i18n] No definition found for the current language', vim.log.levels.WARN)
  end

  local target_win = state.target_win
  local on_jump = state.on_jump
  close()
  if on_jump then pcall(on_jump, entry) end
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(entry.file))
  pcall(vim.api.nvim_win_set_cursor, 0, { (entry.row or 0) + 1, entry.col or 0 })
  vim.cmd('normal! zz')
end

return M

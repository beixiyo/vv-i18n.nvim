-- Reference location navigation.

local M = {}

---@param reference { file: string, row: integer, col?: integer }
function M.jump(reference)
  vim.cmd('edit ' .. vim.fn.fnameescape(reference.file))
  pcall(vim.api.nvim_win_set_cursor, 0, {
    math.max(1, reference.row or 1),
    math.max(0, reference.col or 0),
  })
  vim.cmd('normal! zz')
end

return M

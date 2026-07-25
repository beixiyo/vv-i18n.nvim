-- vv-i18n.editor.fields — 固定输入槽渲染、光标约束与结构保护
local model = require('vv-i18n.editor.model')

local M = {}

local ns = vim.api.nvim_create_namespace('vv_i18n_editor')

function M.render(state)
  if not state then return end
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for i, row in ipairs(state.rows) do
    local name = model.row_label(row)
    local label = name
      .. string.rep(' ', state.lang_width - vim.fn.strdisplaywidth(name))
      .. string.rep(' ', state.value_col - state.lang_width)
    local hl = row.skip and 'Comment' or (row.orig == nil and 'DiagnosticVirtualTextWarn' or 'Identifier')
    pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, i - 1, 0, {
      virt_text = { { label, hl } },
      virt_text_pos = 'overlay',
    })
  end
end

function M.set_cursor(state, row, col)
  if not state or not vim.api.nvim_win_is_valid(state.win) then return end
  pcall(vim.api.nvim_win_set_cursor, state.win, { row, col })
end

function M.current_row(state)
  if not state or not vim.api.nvim_win_is_valid(state.win) then return end
  return vim.api.nvim_win_get_cursor(state.win)[1]
end

function M.clamp_cursor(state)
  local row = M.current_row(state)
  if not row then return end

  local line = vim.api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1] or ''
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  if cursor[2] < state.value_col then
    M.set_cursor(state, row, math.min(state.value_col, #line))
  end
end

function M.focus_start(state)
  local row = M.current_row(state)
  if not row then return end
  local line = vim.api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1] or ''
  M.set_cursor(state, row, math.min(state.value_col, #line))
end

function M.focus(state, index, insert)
  if not state or #state.rows == 0 then return end
  index = ((index - 1) % #state.rows) + 1
  local line = vim.api.nvim_buf_get_lines(state.buf, index - 1, index, false)[1] or ''

  M.set_cursor(state, index, #line)
  if insert and not state.rows[index].skip then vim.cmd('startinsert') end
end

function M.clear(state, insert)
  local row = M.current_row(state)
  if not row or state.rows[row].skip then return end

  local line = string.rep(' ', state.value_col)
  vim.api.nvim_buf_set_lines(state.buf, row - 1, row, false, { line })
  M.set_cursor(state, row, #line)
  if insert then vim.cmd('startinsert') end
end

function M.guard_structure(state)
  if not state or state.repairing then return end
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local prefix = string.rep(' ', state.value_col)
  local valid = #lines == #state.rows

  if valid then
    for _, line in ipairs(lines) do
      if line:sub(1, state.value_col) ~= prefix then
        valid = false
        break
      end
    end
  end

  if not valid then
    state.repairing = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, state.last_lines)
    state.repairing = false
  else
    state.last_lines = vim.deepcopy(lines)
  end

  M.render(state)
  M.clamp_cursor(state)
end

return M

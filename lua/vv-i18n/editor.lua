-- vv-i18n.editor — 单键多语言同步编辑浮窗（lokalise 式「一屏改所有语言」）
--
-- 每个目标语言一行；语言名走 inline 虚拟文本，buffer 内**只存纯译文值**，故存盘时
-- 按行号对应语言、整行即新值，解析零歧义。改动经已证 writer 字节写回：
--   * 原本存在且值变了 → update_file
--   * 原本缺失且填了值 → add_file（自动建中间层）
--   * array/other 非字符串值 → 只读跳过
local writer = require('vv-i18n.writer')

local M = {}

local ns = vim.api.nvim_create_namespace('vv_i18n_editor')
local state = nil  -- { buf, win, full_key, rows = {lang,file,in_file_path,orig,kind,skip}[], on_saved }

local function close()
  if state and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state = nil
end

local function render_chrome()
  if not state then return end
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  local maxw = 0
  for _, r in ipairs(state.rows) do maxw = math.max(maxw, vim.fn.strdisplaywidth(r.lang)) end
  for i, r in ipairs(state.rows) do
    local label = r.lang .. string.rep(' ', maxw - vim.fn.strdisplaywidth(r.lang)) .. '  '
    local hl = r.skip and 'Comment' or (r.orig == nil and 'DiagnosticVirtualTextWarn' or 'Identifier')
    local vt = { { label, hl } }
    if r.skip then vt[#vt + 1] = { '<' .. r.kind .. '> ', 'Comment' } end
    if r.orig == nil and not r.skip then vt[#vt + 1] = { '⚠ ', 'DiagnosticVirtualTextWarn' } end
    pcall(vim.api.nvim_buf_set_extmark, state.buf, ns, i - 1, 0, {
      virt_text = vt,
      virt_text_pos = 'inline',
    })
  end
end

--- 由初始 rows + 编辑后行内容算出需要的写入操作（纯函数，便于测试）
---@param rows table[]
---@param new_lines string[]
---@return { action: 'add'|'update', lang: string, file: string, in_file_path: string[], value: string }[]
function M.diff(rows, new_lines)
  local writes = {}
  for i, r in ipairs(rows) do
    local new = new_lines[i] or ''
    if not r.skip then
      if r.orig == nil then
        if new ~= '' then
          writes[#writes + 1] = { action = 'add', lang = r.lang, file = r.file, in_file_path = r.in_file_path, value = new }
        end
      elseif new ~= r.orig then
        writes[#writes + 1] = { action = 'update', lang = r.lang, file = r.file, in_file_path = r.in_file_path, value = new }
      end
    end
  end
  return writes
end

--- 由 plugin + 全键算出初始 rows + 行（纯函数，便于测试）
---@param plugin table
---@param full_key string
---@return table[]? rows
---@return string[]? lines
---@return string? err
function M.plan(plugin, full_key)
  local files, err = plugin.files_for(full_key)
  if not files then return nil, nil, err end
  local per = plugin.lookup(full_key) or {}
  local rows, lines = {}, {}
  for _, f in ipairs(files) do
    local e = per[f.lang]
    local kind = e and e.kind or 'string'
    local skip = e ~= nil and kind ~= 'string'
    rows[#rows + 1] = {
      lang = f.lang, file = f.file, in_file_path = f.in_file_path,
      orig = e and e.value or nil, kind = kind, skip = skip,
    }
    lines[#lines + 1] = (skip and ('<' .. kind .. '>')) or (e and e.value) or ''
  end
  return rows, lines
end

--- 执行写入；opts.dry_run 只算不落盘
---@param writes table[]
---@param opts? { dry_run?: boolean }
---@return integer changed
---@return string[] fails
function M.apply(writes, opts)
  opts = opts or {}
  local wopts = { dry_run = opts.dry_run, quote_style = opts.quote_style, indent = opts.indent }
  local changed, fails = 0, {}
  for _, w in ipairs(writes) do
    local res = w.action == 'add'
      and writer.add_file(w.file, w.in_file_path, w.value, wopts)
      or writer.update_file(w.file, w.in_file_path, w.value, wopts)
    if res.ok then changed = changed + 1 else fails[#fails + 1] = w.lang .. ':' .. (res.reason or '?') end
  end
  return changed, fails
end

local function save()
  if not state then return end
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local writes = M.diff(state.rows, lines)
  local wopts = state.plugin and state.plugin.writer_opts and state.plugin.writer_opts() or {}
  local changed, fails = M.apply(writes, wopts)

  local on_saved = state.on_saved
  local key = state.full_key
  close()
  if #fails > 0 then
    vim.notify(('[vv-i18n] %s 部分失败：%s'):format(key, table.concat(fails, ', ')), vim.log.levels.ERROR)
  elseif changed > 0 then
    vim.notify(('[vv-i18n] 已同步 %s（%d 处）'):format(key, changed))
  else
    vim.notify('[vv-i18n] 无改动')
  end
  if on_saved then pcall(on_saved, changed) end
end

--- 打开某键的多语言编辑浮窗
---@param plugin table  vv-i18n 主模块（lookup / files_for）
---@param full_key string
---@param opts? { on_saved?: fun(changed: integer) }
function M.open(plugin, full_key, opts)
  opts = opts or {}
  local rows, lines, err = M.plan(plugin, full_key)
  if not rows then
    return vim.notify('[vv-i18n] 无法定位文件：' .. tostring(err), vim.log.levels.WARN)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- 宽度：键名 / 最长值 / 下限 60
  local width = #full_key + 4
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l) + 12) end
  width = math.max(60, math.min(width, vim.o.columns - 8))
  local height = math.max(#lines, 1)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' 󰗊 ' .. full_key .. ' ',
    title_pos = 'center',
    footer = ' <CR>/:w 保存 · q/<Esc> 取消 ',
    footer_pos = 'center',
  })
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder'

  state = { buf = buf, win = win, full_key = full_key, rows = rows, on_saved = opts.on_saved, plugin = plugin }
  render_chrome()

  pcall(require('vv-utils.mouse').block_visual_drag, buf)

  local map = function(mode, lhs, fn)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, silent = true, nowait = true, desc = 'vv-i18n: editor' })
  end
  map('n', '<CR>', save)
  map('n', 'q', close)
  map('n', '<Esc>', close)
  map('n', 'ZZ', save)
  -- :w 视作保存
  vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = save })
  -- 编辑后刷新 inline label（行号不变，值变不影响 label，仅防御性重绘）
  vim.api.nvim_create_autocmd('TextChanged', {
    buffer = buf,
    callback = function() if state then render_chrome() end end,
  })

  -- 光标落在首行值上
  pcall(vim.api.nvim_win_set_cursor, win, { 1, #(lines[1] or '') })
end

M._close = close

return M

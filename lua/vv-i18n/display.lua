-- vv-i18n.display — 行内译文预览（conceal 抹掉原 key + inline 虚拟文本，长度随译文动态变化）
--
-- 整 buffer 枚举所有 t() 调用（plugin.collect_buffer，多源）：
--   命中 → conceal 隐藏字符串字面量、inline 插入「图标 + 译文」（无尾部空白，代码会随之重排）
--   缺失 → 隐藏并插入「⚠ + 键」（警告色）
-- 渲染内容可由 display.render(ctx) 函数完全自定义（返回字符串 或 virt_text chunks）
-- 光标落在某 t() 上 → 删该项 extmark 还原原文（token 级，同行其它仍显译文）
-- 依赖 conceal：enable 给匹配窗口设 conceallevel=2 / concealcursor='nvic'，disable 还原
local truncate = require('vv-i18n.util').truncate

local M = {}

local ns = vim.api.nvim_create_namespace('vv_i18n_preview')
local enabled = false
local augroup = nil
local cache = {}      -- bufnr -> { items }
local touched = {}    -- winid -> { cl, cc }  （conceal 选项原值，还原用）

--- 组装一项的 virt_text chunks（支持 display.render 函数自定义）
---@return table[] chunks  { {text, hl}, ... }
local function build_chunks(plugin, config, r)
  local d = config.display
  local hit = r.kind == 'hit'
  local lang = hit and plugin.pick_lang(r.per) or nil
  local entry = hit and r.per[lang] or nil
  local value = entry and (entry.kind == 'string' and entry.value or ('<' .. entry.kind .. '>')) or nil
  local hl = hit and d.hl or d.missing_hl

  if type(d.render) == 'function' then
    local ok, ret = pcall(d.render, {
      full_key = r.full_key, value = value, lang = lang, kind = r.kind,
      missing = not hit, per = r.per, literal = r.literal,
      icon = hit and d.icon or d.missing_icon, hl = hl, max_width = d.max_width,
    })
    if ok and ret ~= nil then
      if type(ret) == 'string' then return { { ret, hl } } end
      if type(ret) == 'table' then return ret end
    end
    -- ret==nil / 出错 → 落默认
  end

  if hit then
    return { { (d.icon or '') .. truncate(value, d.max_width), hl } }
  end
  return { { (d.missing_icon or '⚠ ') .. (r.literal or r.full_key), hl } }
end

--- 计算某 buffer 的预览项（纯函数，不依赖光标）
---@param plugin table
---@param config table
---@param bufnr integer
---@return { range: table, kind: 'hit'|'missing', full_key: string, missing: boolean, chunks: table[] }[]
function M.compute(plugin, config, bufnr)
  -- 本项目未配置 i18n 作用域（无任何键）→ 不渲染
  if not plugin.has_keys() then return {} end

  local items = {}
  for _, r in ipairs(plugin.collect_buffer(bufnr)) do
    -- 仅处理单行字符串字面量
    local single = r.range and r.range.erow == r.range.srow
    if single and (r.kind == 'hit' or r.kind == 'missing') then
      items[#items + 1] = {
        range = r.range, kind = r.kind, full_key = r.full_key, missing = r.kind == 'missing',
        chunks = build_chunks(plugin, config, r),
      }
    end
  end
  return items
end

--- 把一项画成：conceal 隐藏原字面量 + inline 插入译文（自然长度）
local function draw_item(bufnr, it)
  local rg = it.range
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, rg.srow, rg.scol, {
    end_row = rg.erow,
    end_col = rg.ecol,
    conceal = '',                 -- 抹掉原 key 宽度（配合 conceallevel=2）
    virt_text = it.chunks,
    virt_text_pos = 'inline',     -- 译文按自然长度插入 → 动态长度、无空白
    hl_mode = 'combine',
  })
end

--- 从缓存重绘：跳过光标正落在其字面量范围内的项（token 级还原），不重新 parse
local function redraw(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  if not enabled then return end
  local st = cache[bufnr]
  if not st then return end

  local cur_row, cur_col = -1, -1
  if vim.api.nvim_get_current_buf() == bufnr then
    local pos = vim.api.nvim_win_get_cursor(0)
    cur_row, cur_col = pos[1] - 1, pos[2]
  end

  for _, it in ipairs(st.items) do
    local rg = it.range
    local on_it = cur_row == rg.srow and cur_col >= rg.scol and cur_col < rg.ecol
    if not on_it then draw_item(bufnr, it) end
  end
end

--- 重新计算（parse）+ 缓存 + 绘制
local function recompute(plugin, config, bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  cache[bufnr] = { items = M.compute(plugin, config, bufnr) }
  redraw(bufnr)
end

--- 重算并渲染（外部入口 / 测试用）
function M.render(plugin, config, bufnr)
  recompute(plugin, config, bufnr or vim.api.nvim_get_current_buf())
end

local function ft_match(bufnr, ft_list)
  local ft = vim.bo[bufnr].filetype
  for _, f in ipairs(ft_list) do if f == ft then return true end end
  return false
end

--- 给窗口装上 conceal（首次保存原值），译文才能隐藏原 key
local function set_conceal(win)
  if touched[win] then return end
  touched[win] = { cl = vim.wo[win].conceallevel, cc = vim.wo[win].concealcursor }
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = 'nvic'   -- 始终 conceal，还原全靠 token 级删 extmark
end

local function restore_conceal()
  for win, saved in pairs(touched) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(function()
        vim.wo[win].conceallevel = saved.cl
        vim.wo[win].concealcursor = saved.cc
      end)
    end
  end
  touched = {}
end

function M.enable(plugin, config)
  if enabled then return end
  enabled = true
  augroup = vim.api.nvim_create_augroup('VVI18nDisplay', { clear = true })

  -- 内容 / 进窗 → 装 conceal + 重算（含 parse）
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'WinEnter', 'BufWritePost', 'TextChanged', 'InsertLeave' }, {
    group = augroup,
    callback = vim.schedule_wrap(function(args)
      if not enabled or not ft_match(args.buf, config.ft) then return end
      if vim.api.nvim_get_current_buf() == args.buf then set_conceal(vim.api.nvim_get_current_win()) end
      recompute(plugin, config, args.buf)
    end),
  })
  -- 光标移动 → 只重绘（不 parse），实现 token 级还原
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = augroup,
    callback = function(args)
      if enabled and cache[args.buf] then redraw(args.buf) end
    end,
  })

  -- 立即处理所有窗口里已加载的匹配 buffer
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_loaded(b) and ft_match(b, config.ft) then
      set_conceal(win)
      recompute(plugin, config, b)
    end
  end
end

function M.disable()
  enabled = false
  if augroup then pcall(vim.api.nvim_del_augroup_by_id, augroup); augroup = nil end
  restore_conceal()
  cache = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      pcall(vim.api.nvim_buf_clear_namespace, b, ns, 0, -1)
    end
  end
end

function M.toggle(plugin, config)
  if enabled then M.disable() else M.enable(plugin, config) end
end

function M.is_enabled() return enabled end

return M

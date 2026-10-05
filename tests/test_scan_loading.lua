-- 真实场景在独立子进程中执行；收集阶段仅注册具名用例。
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ icons = true, fixtures = true, setup = 'bootstrap.lua' })

T["引用扫描期间面板显示加载帧且终结释放时钟"] = function()
  child.lua_func(function()
    -- 引用扫描在途时的 loading 帧：引用侧栏与无用 key 面板
    --
    -- 捕获：扫描中计数显示 0 被误读为无引用；帧落错行或扫描结束后残留；
    -- 面板关闭后共享时钟 timer 泄漏；无用 key 面板仍调用已删除的 Loading.start


    local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helper.lua')
    local i18n = require('vv-i18n')
    local References = require('vv-i18n.references.index')
    local ReferencesPanel = require('vv-i18n.references.panel')
    local UnusedPanel = require('vv-i18n.unused.panel')
    local Clock = require('vv-utils.loading.clock')

    local check = H.checker()

    --- 收集 buffer 中所有 loading mark 的 { row(1-based), pos }
    --- loading 用匿名 namespace，按帧的默认高亮组 VVLoading 识别（ns_id = -1 覆盖匿名 namespace）
    local function loading_marks(buf)
      local out = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
        local virt = mark[4].virt_text
        if virt and virt[1] and virt[1][2] == 'VVLoading' then
          out[#out + 1] = { row = mark[2] + 1, pos = mark[4].virt_text_pos }
        end
      end
      return out
    end

    --- 标题行右侧计数文本
    local function header_count(buf)
      local ns = vim.api.nvim_create_namespace('vv-utils-tree-panel-vv-i18n-references')
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { 0, -1 }, { details = true })) do
        local virt = mark[4].virt_text
        if virt and mark[4].virt_text_pos == 'right_align' then return virt[1][1] end
      end
    end

    local function wait_scan()
      return vim.wait(3000, function() return not References.is_scanning() end)
    end

    local config = H.ns_config()
    config.references = { enable = true }
    i18n.setup(config)
    i18n.reload()
    check('初始扫描完成', wait_scan())

    -- 引用侧栏：扫描中打开
    References.refresh(i18n)
    check('refresh 后处于扫描中', References.is_scanning())
    ReferencesPanel.toggle(i18n, 'app.hero.title')
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    check('扫描中第 2 行为空状态', lines[2] == '  Scanning references…', lines[2])
    check('扫描中计数显示 … 而非 0', header_count(buf) == '…', header_count(buf))
    local marks = loading_marks(buf)
    check('扫描中 loading 帧在第 2 行 eol',
      #marks == 1 and marks[1].row == 2 and marks[1].pos == 'eol', vim.inspect(marks))
    check('扫描中共享时钟在运行', Clock._timer_count() > 0)

    check('扫描完成', wait_scan())
    vim.wait(50)
    check('扫描结束后 loading 帧消失', #loading_marks(buf) == 0, vim.inspect(loading_marks(buf)))
    check('扫描结束后计数为真实引用数',
      header_count(buf) == tostring(#References.get('app.hero.title')) and header_count(buf) ~= '0',
      header_count(buf))
    check('扫描结束后共享时钟释放', Clock._timer_count() == 0, Clock._timer_count())
    ReferencesPanel.close()

    -- 引用侧栏：扫描中关闭
    References.refresh(i18n)
    ReferencesPanel.toggle(i18n, 'app.hero.title')
    check('重新扫描时帧再次出现', #loading_marks(vim.api.nvim_get_current_buf()) == 1)
    ReferencesPanel.close()
    check('扫描在途时关闭侧栏不残留 timer', Clock._timer_count() == 0, Clock._timer_count())
    wait_scan()

    -- 无用 key 面板：扫描中打开（迁移前调用已删除的 Loading.start 会抛错）
    References.refresh(i18n)
    local opened, err = pcall(UnusedPanel.open, i18n)
    check('扫描中打开无用 key 面板不报错', opened, err)
    buf = vim.api.nvim_get_current_buf()
    marks = loading_marks(buf)
    check('无用 key 面板 loading 帧在第 1 行 eol',
      #marks == 1 and marks[1].row == 1 and marks[1].pos == 'eol', vim.inspect(marks))
    check('扫描完成', wait_scan())
    vim.wait(50)
    check('无用 key 面板扫描结束后帧消失', #loading_marks(buf) == 0, vim.inspect(loading_marks(buf)))
    check('无用 key 面板扫描结束后共享时钟释放', Clock._timer_count() == 0, Clock._timer_count())

    References.refresh(i18n)
    vim.wait(10)
    UnusedPanel.close()
    check('无用 key 面板扫描在途时关闭不残留 timer', Clock._timer_count() == 0, Clock._timer_count())
    wait_scan()
  end)
end

return T

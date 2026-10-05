-- 每个具名用例独占 Neovim、cwd、HOME、XDG 与临时根；失败路径同样由父 hook 清理
local M = {}
local Processes = dofile(assert(vim.env.VV_UTILS) .. '/dev/test/process.lua')

function M.new_set(opts)
  opts = opts or {}
  local MiniTest = require('mini.test')
  local child = MiniTest.new_child_neovim()
  local root, pid
  local keys = { 'HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME',
    'XDG_CACHE_HOME', 'XDG_RUNTIME_DIR', 'TMPDIR' }
  local function cleanup()
    local ok, err = pcall(function()
      if child.is_running() then
        local errors = child.lua_get('AsyncErrors')
        assert(#errors == 0, '异步回调异常：' .. table.concat(errors, '\n'))
      end
    end)
    local descendants_ok, descendants_error = pcall(Processes.stop_descendants, pid)
    local stopped, stop_err = pcall(child.stop)
    if root then
      -- 恢复 fixture 目录权限，防止拒绝访问场景阻止失败清理
      local function unlock(path)
        local stat = vim.uv.fs_lstat(path)
        if not stat or stat.type ~= 'directory' then
          return
        end
        assert(vim.uv.fs_chmod(path, 493))
        for name in vim.fs.dir(path) do
          unlock(path .. '/' .. name)
        end
      end
      unlock(root)
      assert(vim.fn.delete(root, 'rf') == 0, '清理 fixture 失败：' .. root)
      root = nil
    end
    assert(descendants_ok, descendants_error)
    assert(stopped, stop_err)
    assert(ok, err)
  end
  local T = MiniTest.new_set({
    hooks = {
      pre_case = function()
        pid = nil
        root = assert(vim.uv.fs_mkdtemp(assert(vim.env.TMPDIR) .. '/vv-test-case-XXXXXX'))
        local saved, cwd = {}, vim.fn.getcwd()
        for _, key in ipairs(keys) do
          saved[key] = vim.env[key]
        end
        local started, err = pcall(function()
          for _, key in ipairs(keys) do
            local path = root .. '/' .. key:lower()
            vim.fn.mkdir(path, 'p')
            vim.env[key] = path
          end
          vim.cmd.cd(vim.fn.fnameescape(root))
          child.start({ '-u', 'NONE', '-i', 'NONE' }, { nvim_executable = vim.v.progpath })
        end)
        for _, key in ipairs(keys) do
          vim.env[key] = saved[key]
        end
        vim.cmd.cd(vim.fn.fnameescape(cwd))
        if child.job then
          pid = vim.fn.jobpid(child.job.id)
        end
        assert(started, err)
        child.lua_func(function(path, options)
          AsyncErrors = {}
          vim.env.VV_TEST_TMP = path
          vim.opt.packpath = ''
          dofile(vim.env.VV_UTILS .. '/dev/test/runtime.lua').apply()
          -- 显式选中的 parser/query 优先于默认 site 和 Neovim 内置 runtime
          vim.opt.runtimepath:prepend(assert(vim.env.VV_TEST_PARSERS))
          vim.opt.runtimepath:prepend(assert(vim.env.VV_TEST_QUERIES))
          vim.opt.runtimepath:prepend(vim.env.VV_UTILS)
          vim.opt.runtimepath:prepend(vim.env.VV_TEST_REPO)
          if options.icons then
            local icons = assert(vim.env.VV_TEST_ICONS, '请设置 VV_TEST_ICONS 为已安装 vv-icons.nvim 源码目录')
            assert(vim.fn.filereadable(icons .. '/lua/vv-icons/init.lua') == 1, 'VV_TEST_ICONS 源码不存在')
            vim.opt.runtimepath:prepend(icons)
          end
          local schedule = vim.schedule
          vim.schedule = function(callback)
            schedule(function()
              local ok, err = xpcall(callback, debug.traceback)
              if not ok then
                AsyncErrors[#AsyncErrors + 1] = tostring(err)
              end
            end)
          end
          if options.fixtures then
            local result = vim.system({ 'cp', '-R', vim.env.VV_TEST_REPO .. '/tests/fixtures', path .. '/fixtures' }):wait()
            assert(result.code == 0, '复制真实 fixture 失败：' .. (result.stderr or ''))
          end
          if options.setup then
            dofile(vim.env.VV_TEST_REPO .. '/tests/' .. options.setup)
          end
        end, root, opts)
      end,
      post_case = cleanup,
    },
  })
  return T, child
end

return M

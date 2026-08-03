-- 引用索引的 latest-wins、物理进程取消与 clear 生命周期回归

dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local check, done = H.checker()

local original_system = vim.system
local original_schedule = vim.schedule
local original_executable = vim.fn.executable
local systems = {}
local scheduled = {}

vim.fn.executable = function(command)
  if command == 'rg' then return 1 end
  return original_executable(command)
end
vim.schedule = function(callback) scheduled[#scheduled + 1] = callback end
vim.system = function(command, options, callback)
  local process = {
    command = command,
    options = options,
    callback = callback,
    killed = false,
  }
  function process:kill() self.killed = true end
  systems[#systems + 1] = process
  return process
end

package.loaded['vv-i18n.references.index'] = nil
local References = require('vv-i18n.references.index')
local root_a = vim.fn.tempname()
local root_b = vim.fn.tempname()
vim.fn.mkdir(root_a, 'p')
vim.fn.mkdir(root_b, 'p')
vim.fn.writefile({ "t('old.key')" }, root_a .. '/a.ts')
vim.fn.writefile({ "t('new.key')" }, root_b .. '/b.ts')

local function plugin(root, key)
  return {
    get_state = function() return { root = root } end,
    reference_names = function() return { 't' } end,
    collect_content = function()
      return {
        {
          kind = 'hit',
          full_key = key,
          literal = key,
          range = { srow = 0, scol = 0 },
        },
      }
    end,
  }
end

local a_done = false
local b_done = false
References.refresh(plugin(root_a, 'old.key'), function() a_done = true end)
References.refresh(plugin(root_b, 'new.key'), function() b_done = true end)
check('新 refresh 物理取消旧 rg', systems[1].killed == true)

systems[2].callback({ code = 0, stdout = 'b.ts\n' })
systems[1].callback({ code = 0, stdout = 'a.ts\n' })
scheduled[1]()
scheduled[2]()
check('B 先返回后只保留 B 的引用', b_done and not a_done
  and #References.get('new.key') == 1 and #References.get('old.key') == 0)

local clear_done = false
References.refresh(plugin(root_a, 'old.key'), function() clear_done = true end)
systems[3].callback({ code = 0, stdout = 'a.ts\n' })
References.clear()
scheduled[3]()
check('clear 后已排队 callback 不得复活索引', systems[3].killed == true
  and not clear_done and #References.get('old.key') == 0 and not References.is_scanning())

local reentrant_done = false
local cleared_from_listener = false
local unsubscribe = References.subscribe(function()
  if not References.is_scanning() and not cleared_from_listener then
    cleared_from_listener = true
    References.clear()
  end
end)
References.refresh(plugin(root_b, 'new.key'), function() reentrant_done = true end)
systems[4].callback({ code = 0, stdout = 'b.ts\n' })
scheduled[4]()
check('完成事件中 clear 会废弃同一批旧 completion callback',
  cleared_from_listener and not reentrant_done and #References.get('new.key') == 0)
unsubscribe()

References.clear()
systems = {}
scheduled = {}
local initial_a_done = false
local initial_b_done = false
local initial_reentered = false
local initial_unsubscribe = References.subscribe(function()
  if References.is_scanning() and not initial_reentered then
    initial_reentered = true
    References.refresh(plugin(root_b, 'new.key'), function() initial_b_done = true end)
  end
end)
References.refresh(plugin(root_a, 'old.key'), function() initial_a_done = true end)
check('初始 emit 同步触发 B 后 A 不再启动 rg', initial_reentered
  and #systems == 1 and systems[1].options.cwd == root_b and not initial_a_done)
systems[1].callback({ code = 0, stdout = 'b.ts\n' })
scheduled[1]()
check('初始 emit 重入后 B 独占 scanning 与 completion', initial_b_done
  and not initial_a_done and #References.get('new.key') == 1)
initial_unsubscribe()

References.clear()
systems = {}
scheduled = {}
local fast_a_done = false
local fast_b_done = false
local fast_a = plugin(root_a, 'old.key')
fast_a.reference_names = function()
  References.refresh(plugin(root_b, 'new.key'), function() fast_b_done = true end)
  return {}
end
References.refresh(fast_a, function() fast_a_done = true end)
check('reference_names 重入 B 后 A 的 empty fast path 不清 B scanning',
  References.is_scanning() and #systems == 1 and systems[1].options.cwd == root_b
    and not fast_a_done)
systems[1].callback({ code = 0, stdout = 'b.ts\n' })
scheduled[1]()
check('empty fast path 重入只投递 B completion', fast_b_done and not fast_a_done
  and #References.get('new.key') == 1 and #References.get('old.key') == 0)

References.clear()
systems = {}
scheduled = {}
local collect_a_done = false
local collect_b_done = false
local collect_reentered = false
local collect_a = plugin(root_a, 'old.key')
collect_a.collect_content = function()
  if not collect_reentered then
    collect_reentered = true
    References.refresh(plugin(root_b, 'new.key'), function() collect_b_done = true end)
  end
  return {
    {
      kind = 'hit',
      full_key = 'old.key',
      literal = 'old.key',
      range = { srow = 0, scol = 0 },
    },
  }
end
References.refresh(collect_a, function() collect_a_done = true end)
systems[1].callback({ code = 0, stdout = 'a.ts\n' })
scheduled[1]()
check('collect_content 重入 B 后 A 不提交局部索引', collect_reentered
  and #systems == 2 and #References.get('old.key') == 0 and not collect_a_done)
systems[2].callback({ code = 0, stdout = 'b.ts\n' })
scheduled[2]()
check('collect_content 重入最终只保留 B', collect_b_done and not collect_a_done
  and #References.get('new.key') == 1 and #References.get('old.key') == 0)

vim.system = original_system
vim.schedule = original_schedule
vim.fn.executable = original_executable
vim.fn.delete(root_a, 'rf')
vim.fn.delete(root_b, 'rf')

done()
vim.cmd('qa!')

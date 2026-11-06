-- 引用快照完整性回归：依赖失效、局部失败恢复与异常发布
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ icons = true, fixtures = true, setup = 'bootstrap.lua' })

T['locale 补 key 后按需重建引用，活动面板自动恢复'] = function()
  child.lua_func(function()
    local i18n = require('vv-i18n')
    local R = require('vv-i18n.references.index')
    local Panel = require('vv-i18n.references.panel')
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. '/locales', 'p')
    local locale = root .. '/locales/en-US.ts'
    vim.fn.writefile({ "export default { known: 'Known' }" }, locale)
    vim.fn.writefile({ "t('added')" }, root .. '/source.ts')
    i18n.setup({
      root = root,
      project_config = false,
      sources = { { discover = { 'locales' }, mount = 'flat', namespace = 'flat', lang = '{lang}.ts' } },
      display = { enable = false },
    })
    i18n.reload()
    vim.wait(50)
    R.ensure(i18n)
    assert(vim.wait(3000, function() return not R.is_scanning() end))
    assert(#R.get('added') == 0)

    vim.fn.writefile({ "export default { known: 'Known', added: 'Added' }" }, locale)
    i18n.reload()
    assert(not R.is_scanning(), '没有引用消费者时 reload 不应启动扫描')
    assert(R.snapshot().scan.status == 'idle', 'locale 变化必须撤销旧完整快照')
    assert(R.ensure(i18n), '下次消费必须重新扫描')
    assert(vim.wait(3000, function() return not R.is_scanning() end))
    assert(#R.get('added') == 1, '补定义后原有源码调用必须进入引用索引')

    Panel.toggle(i18n, 'added')
    vim.fn.writefile({ "export default { known: 'Known' }" }, locale)
    i18n.reload()
    assert(R.is_scanning(), '活动引用面板应消费失效通知并重扫')
    assert(vim.wait(3000, function() return not R.is_scanning() end))
    assert(#R.get('added') == 0, '不能保留已经删除定义的命中')
    Panel.close()
  end)
end

T['增量更新保留其他文件和全局失败，修复失败文件才能恢复完整'] = function()
  child.lua_func(function()
    local R = require('vv-i18n.references.index')
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, 'p')
    local bad, good = root .. '/bad.ts', root .. '/good.ts'
    vim.fn.writefile({ "t('broken'" }, bad)
    vim.fn.writefile({ "t('good')" }, good)
    local p = {
      get_state = function() return { root = root } end,
      reference_names = function() return { 't' } end,
      collect_content = function(_, path)
        return { { kind = 'hit', full_key = path == bad and 'broken' or 'good', range = { srow = 0, scol = 0 } } }
      end,
    }
    R.refresh(p)
    assert(vim.wait(3000, function() return not R.is_scanning() end))
    assert(R.snapshot().scan.status == 'failed')
    R.update_file(p, good)
    local scan = R.snapshot().scan
    assert(scan.status == 'failed' and #scan.failures == 1 and scan.failures[1].file == bad,
      '更新正常文件不能抹掉另一个文件的失败')
    assert(scan.parsed == 1, 'parsed 应是当前成功文件数，不能按保存次数累加')
    vim.fn.writefile({ "t('broken')" }, bad)
    R.update_file(p, bad)
    scan = R.snapshot().scan
    assert(scan.status == 'complete' and #scan.failures == 0 and scan.parsed == 2)

    -- 模拟 rg 全局失败：一次局部成功不能把未完成的全仓枚举修成 complete
    local system = vim.system
    vim.system = function(_, _, callback)
      vim.schedule(function() callback({ code = 2, stderr = 'fixture failure' }) end)
      return { kill = function() end }
    end
    R.refresh(p)
    assert(vim.wait(3000, function() return not R.is_scanning() end))
    vim.system = system
    R.update_file(p, good)
    assert(R.snapshot().scan.status == 'failed', '全局失败不能被单文件更新消除')
    R.refresh(p)
    assert(vim.wait(3000, function() return not R.is_scanning() end))
    assert(R.snapshot().scan.status == 'complete', '成功全扫才能恢复全局完整性')
  end)
end

T['worker 意外异常不得发布完整快照，空 root 的 ensure 不启动请求'] = function()
  child.lua_func(function()
    local R = require('vv-i18n.references.index')
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, 'p')
    local path = root .. '/source.ts'
    vim.fn.writefile({ "t('key')" }, path)
    local p = {
      get_state = function() return { root = root } end,
      reference_names = function() return { 't' } end,
      collect_content = function()
        return { { kind = 'hit', full_key = 'key', range = { srow = 0, scol = 0 } } }
      end,
    }
    -- 故障注入到真实 worker 的仓库写入边界，验证 batch.errors 的接入而非复制循环
    local Store = require('vv-i18n.references.store')
    local new = Store.new
    Store.new = function()
      local store = new()
      store.replace_file = function() error('fixture store failure') end
      return store
    end
    package.loaded['vv-i18n.references.index'] = nil
    R = require('vv-i18n.references.index')
    Store.new = new
    R.refresh(p)
    assert(vim.wait(3000, function() return not R.is_scanning() end))
    local scan = R.snapshot().scan
    assert(scan.status == 'failed' and #scan.failures == 1 and scan.failures[1].file == path,
      'worker 异常必须作为文件失败发布')
    assert(scan.source_fingerprints[path] == nil and scan.parsed == 0,
      '异常文件不能残留成功指纹或成功计数')
    R.clear()
    local generation = R.snapshot().generation
    assert(not R.ensure({ get_state = function() return {} end }), '空 root 不应启动失败请求')
    assert(R.snapshot().generation == generation and R.snapshot().scan.status == 'idle')
  end)
end

return T

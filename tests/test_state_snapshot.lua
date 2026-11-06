-- 真实 locale 索引上的快照隔离与 metadata 消费成本回归
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ icons = true, setup = 'bootstrap.lua' })

local function setup_project()
  child.lua_func(function()
    local plugin = require('vv-i18n')
    local references = require('vv-i18n.references.index')
    local root = assert(vim.env.VV_TEST_TMP) .. '/project-a'
    vim.fn.mkdir(root .. '/locales', 'p')
    local values = {}
    for i = 1, 1000 do values['key' .. i] = 'Value ' .. i end
    vim.fn.writefile({ vim.json.encode(values) }, root .. '/locales/en.json')
    -- 真实 reader 无法从非对象 locale 建索引，错误必须保留到 metadata / unused 报告
    vim.fn.writefile({ 'null' }, root .. '/locales/fr.json')
    vim.fn.writefile({ "t('key1')" }, root .. '/source.ts')
    local config = {
      root = root,
      project_config = false,
      display = { enable = false },
      sources = { { discover = { 'locales' }, mount = 'flat', namespace = 'flat', lang = '{lang}.json' } },
    }
    plugin.setup(config)
    local indexes = plugin.reload()
    vim.wait(20)
    assert(#indexes[1].index:all_keys() == 1000, '必须建立真实的大 locale 索引')
    assert(plugin.lookup('key1').en.value == 'Value 1', '真实译文必须可查')
    assert(#plugin.get_state().errors == 1, '损坏 locale 必须产生真实构建错误')
    assert(references.snapshot().scan.status == 'idle', '无消费者的 setup/reload 不应扫描')

    Fixture = { plugin = plugin, references = references, root = root, config = config, indexes = indexes }
    -- 不替换查询或扫描；只统计实际 deepcopy 是否接收当前内部索引图，并始终执行原函数
    function Fixture.observe(callback)
      local deepcopy, copies = vim.deepcopy, 0
      vim.deepcopy = function(value, ...)
        if value == Fixture.indexes or (type(value) == 'table' and value.indexes == Fixture.indexes) then
          copies = copies + 1
        end
        return deepcopy(value, ...)
      end
      local ok, result = pcall(callback)
      vim.deepcopy = deepcopy
      assert(ok, result)
      return result, copies
    end
  end)
end

T['默认完整快照的嵌套修改不反写索引与错误'] = function()
  setup_project()
  child.lua_func(function()
    local F = Fixture
    local snapshot, copies = F.observe(function() return F.plugin.get_state() end)
    assert(copies == 1, '计数探针必须识别真实完整快照的索引复制')
    local explicit = F.plugin.get_state({ indexes = true })
    local omitted = F.plugin.get_state({})
    assert(explicit.indexes[1].index:get('key1').en.value == 'Value 1'
      and omitted.indexes[1].index:get('key1').en.value == 'Value 1', 'true 和省略 indexes 均保留完整快照')
    snapshot.indexes[1].index:get('key1').en.value = '篡改译文'
    snapshot.indexes[1].source.discover[1] = '篡改目录'
    snapshot.errors[1].reason = '篡改错误'
    snapshot.root = '篡改根'
    local current = F.plugin.get_state()
    assert(F.plugin.lookup('key1').en.value == 'Value 1', '快照中的嵌套译文不得反写内部索引')
    assert(current.indexes[1].source.discover[1] == 'locales', '快照中的嵌套 source 不得反写配置')
    assert(current.errors[1].reason ~= '篡改错误' and current.root == F.root, '错误和根必须隔离')
  end)
end

T['metadata 在重载和换根后保留真实状态且不复制索引'] = function()
  setup_project()
  child.lua_func(function()
    local F = Fixture
    local metadata, copies = F.observe(function() return F.plugin.get_state({ indexes = false }) end)
    assert(copies == 0, 'metadata 不得先复制索引再丢弃，实际复制次数：' .. copies)
    assert(metadata.indexes == nil and metadata.root == F.root and metadata.project_file == nil,
      'metadata 只省略 indexes，不改变根和项目配置状态')
    assert(metadata.errors[1].file == F.root .. '/locales/fr.json', 'metadata 必须保留真实 locale 错误')
    metadata.errors[1].reason = '篡改错误'
    assert(F.plugin.get_state({ indexes = false }).errors[1].reason ~= '篡改错误', 'metadata 错误必须深拷贝隔离')

    vim.fn.writefile({ '{"key1":"Updated"}' }, F.root .. '/locales/en.json')
    vim.fn.delete(F.root .. '/locales/fr.json')
    F.indexes = F.plugin.reload()
    local reloaded, reload_copies = F.observe(function() return F.plugin.get_state({ indexes = false }) end)
    assert(reload_copies == 0 and #reloaded.errors == 0 and reloaded.root == F.root,
      'reload 后 metadata 必须反映错误恢复，且仍不复制索引')
    assert(F.plugin.lookup('key1').en.value == 'Updated', 'reload 必须使用真实更新后的 locale')

    local next_root = assert(vim.env.VV_TEST_TMP) .. '/project-b'
    vim.fn.mkdir(next_root .. '/locales', 'p')
    vim.fn.writefile({ '{"other":"Other"}' }, next_root .. '/locales/en.json')
    vim.fn.writefile({ "t('other')" }, next_root .. '/source.ts')
    F.config.root = next_root
    F.plugin.setup(F.config)
    F.indexes = F.plugin.reload()
    local changed, changed_copies = F.observe(function() return F.plugin.get_state({ indexes = false }) end)
    assert(changed_copies == 0 and changed.root == next_root and #changed.errors == 0, '换 root 后不能返回旧 metadata')
    assert(F.plugin.lookup('key1') == nil and F.plugin.lookup('other').en.value == 'Other', '换 root 必须替换旧索引')
    assert(F.references.ensure(F.plugin), '新 root 首次消费必须启动扫描')
    assert(vim.wait(3000, function() return not F.references.is_scanning() end), '新 root 扫描必须结束')
    assert(F.references.snapshot().scan.root == next_root and #F.references.get('other') == 1
      and #F.references.get('key1') == 0, '扫描必须使用新 root 的真实调用点')
  end)
end

T['引用消费与 unused 报告读取 metadata 不复制大索引'] = function()
  setup_project()
  child.lua_func(function()
    local F = Fixture
    local started, first_copies = F.observe(function() return F.references.ensure(F.plugin) end)
    assert(started, '首次 ensure 必须启动真实扫描')
    assert(vim.wait(3000, function() return not F.references.is_scanning() end), '首次扫描必须结束')
    local snapshot = F.references.snapshot()
    assert(snapshot.scan.status == 'complete' and snapshot.scan.root == F.root and #F.references.get('key1') == 1,
      '首次扫描必须发布当前 root 的真实引用')
    local repeated, repeated_copies = F.observe(function() return F.references.ensure(F.plugin) end)
    assert(not repeated and F.references.snapshot().generation == snapshot.generation, '重复消费不得重扫')
    assert(first_copies == 0 and repeated_copies == 0,
      ('ensure 不应复制大索引：首次=%d，重复=%d'):format(first_copies, repeated_copies))

    vim.fn.writefile({ "t('key2')" }, F.root .. '/source.ts')
    local _, update_copies = F.observe(function() F.references.update_file(F.plugin, F.root .. '/source.ts') end)
    assert(update_copies == 0, '单文件更新读取 root 不应复制大索引')
    assert(#F.references.get('key1') == 0 and #F.references.get('key2') == 1, '真实增量更新必须替换旧引用')
    local actions = require('vv-i18n.unused.actions').new(F.plugin)
    local report, report_copies = F.observe(function() return actions:rebuild() end)
    assert(report_copies == 0, 'unused 报告只需 root/errors，不应复制大索引')
    assert(report.scan.root == F.root and report.scan.locale_failures[1].file == F.root .. '/locales/fr.json',
      'unused 报告必须保留当前根和真实 locale 错误')
    assert(report.stats.total == 1000 and report.stats.used == 1 and #report.candidates == 999,
      'metadata 路径不能改变真实 unused 分析结果')
  end)
end

return T

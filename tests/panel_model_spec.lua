---@diagnostic disable: param-type-mismatch
-- i18n 键面板纯数据转换测试

dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')

local SPEC_DIR = debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')
local H = dofile(SPEC_DIR .. '/helper.lua')
local Model = require('vv-i18n.panel.model')
local TreeModel = require('vv-utils.tree_panel.model')

local check, done = H.checker()

local source = {
  {
    mount = 'common',
    langs = { 'en-US', 'zh-CN', 'ja-JP' },
    keys = {
      {
        full = 'common.ok',
        rel = 'ok',
        per = { ['en-US'] = {}, ['zh-CN'] = {}, ['ja-JP'] = {} },
        missing = {},
      },
      {
        full = 'common.cancel',
        rel = 'cancel',
        per = { ['en-US'] = {} },
        missing = { 'ja-JP', 'zh-CN' },
      },
    },
  },
}

local regular = Model.nodes(Model.build(source, 'mount'), 'mount', false)
check('常规分组保留全部键',
  #regular == 1 and #regular[1].children == 2)
check('同组键生成不同 opaque ID',
  regular[1].children[1].id ~= regular[1].children[2].id)

local languages = Model.languages(source)
local with_selector = Model.nodes(source, 'mount', false, {
  languages = languages,
  selected_lang = 'zh-CN',
})
check('语言选择器使用真实语言并置于树顶部',
  with_selector[1].data.kind == 'languages'
    and #with_selector[1].children == 3
    and with_selector[1].children[1].label == 'en-US')
check('语言选择器标记当前语言',
  with_selector[1].children[3].data.selected == true
    and with_selector[1].children[3].data.lang == 'zh-CN')

local filtered = Model.nodes(source, 'mount', true)
check('only_missing 过滤完整键',
  #filtered == 1
    and #filtered[1].children == 1
    and filtered[1].children[1].label == 'cancel')

local by_lang = Model.build(source, 'missing_lang')
local grouped = Model.nodes(by_lang, 'missing_lang', true)
check('一个键缺两种语言时生成两个语言组',
  #grouped == 2
    and grouped[1].label == 'ja-JP'
    and grouped[2].label == 'zh-CN')
check('跨语言组的重复键仍有唯一节点 ID',
  grouped[1].children[1].id ~= grouped[2].children[1].id)
check('缺失计数按完整键去重', Model.missing_total(by_lang) == 1)
local grouped_total, grouped_missing = Model.summary(by_lang)
check('缺失语言分组的顶部统计按完整键去重',
  grouped_total == 1 and grouped_missing == 1,
  ('%d total / %d missing'):format(grouped_total, grouped_missing))

local empty = Model.build(nil, 'mount')
check('空输入返回可遍历空表', type(empty) == 'table' and #empty == 0)
check('空输入统计为零',
  Model.missing_total(nil) == 0
    and select(1, Model.summary(nil)) == 0
    and select(2, Model.summary(nil)) == 0)

local duplicate_mounts = {
  {
    mount = 'common',
    keys = {
      { full = 'common.ready', rel = 'ready', per = {}, missing = {} },
    },
  },
  {
    mount = 'common',
    keys = {
      { full = 'common.cancel', rel = 'cancel', per = {}, missing = { 'zh-CN' } },
    },
  },
}
local duplicate_nodes = Model.nodes(duplicate_mounts, 'mount', false)
check('多个 source 的同名 mount 仍生成唯一组 ID',
  #duplicate_nodes == 2 and duplicate_nodes[1].id ~= duplicate_nodes[2].id)
local flattened = TreeModel.flatten(duplicate_nodes, {})
check('同名 mount 可通过 TreePanel 重复 ID 校验', #flattened == 4)

local filtered_duplicates = Model.nodes(duplicate_mounts, 'mount', true)
check('过滤掉前一个同名组后保留原组 ID',
  #filtered_duplicates == 1 and filtered_duplicates[1].id == duplicate_nodes[2].id)

local ambiguous_values = Model.nodes({
  { mount = 'a', keys = { { full = 'b:c', rel = 'b:c', per = {}, missing = {} } } },
  { mount = 'a:b', keys = { { full = 'c', rel = 'c', per = {}, missing = {} } } },
}, 'mount', false)
check('包含分隔符的 mount 和 key 不会产生 ID 碰撞',
  ambiguous_values[1].children[1].id ~= ambiguous_values[2].children[1].id)

done()
vim.cmd('qa!')

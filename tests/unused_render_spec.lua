-- unused 面板投影：筛选必须覆盖候选与 unknown，并移除没有命中项的空分组
dofile((debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$')) .. '/bootstrap.lua')

local H = dofile(debug.getinfo(1, 'S').source:sub(2):match('(.*)/[^/]*$') .. '/helper.lua')
local Render = require('vv-i18n.unused.render')
local check, done = H.checker()

local report = {
  candidates = {
    {
      status = 'candidate-unused',
      full_key = 'app.chatInput.placeholder',
      rel = 'chatInput.placeholder',
      mount = 'app',
      definitions = {
        { lang = 'en-US', file = '/project/locales/en/app.json', value = 'Ask anything' },
        { lang = 'zh-CN', file = '/project/locales/zh/app.json', value = '询问任何问题' },
      },
      per = {
        ['en-US'] = { kind = 'string', value = 'Ask anything' },
        ['zh-CN'] = { kind = 'string', value = '询问任何问题' },
      },
    },
    {
      status = 'candidate-unused',
      full_key = 'settings.account.title',
      rel = 'account.title',
      mount = 'settings',
      definitions = { { file = '/project/locales/en/settings.json', value = 'Account' } },
    },
  },
  unknown = {
    {
      status = 'unknown',
      full_key = 'comps.chatInput.send',
      mount = 'comps',
      definitions = { { file = '/project/locales/en/comps.json', value = 'Send' } },
    },
  },
}

local by_key = Render.nodes(report, 'CHATINPUT')
check('筛选大小写不敏感并同时保留候选与 unknown', #by_key == 2
  and by_key[1].label == 'app'
  and by_key[1].children[1].data.item.full_key == 'app.chatInput.placeholder'
  and by_key[2].id == 'unknown'
  and by_key[2].children[1].data.item.full_key == 'comps.chatInput.send')

local by_value = Render.nodes(report, 'ask anything')
check('筛选可匹配国际化 value 且不留下空分组', #by_value == 1
  and #by_value[1].children == 1
  and by_value[1].children[1].data.item.full_key == 'app.chatInput.placeholder')

check('匹配计数与面板投影使用相同规则', Render.match_count(report, 'chatinput') == 2
  and Render.match_count(report, 'missing') == 0)

local row = Render.node({
  node = by_key[1].children[1],
  depth = 1,
  has_children = false,
}, {}, function() return 'zh-CN' end)
check('unused key 右侧按首选语言显示译文', row.virt_text
  and row.virt_text[1][1] == '询问任何问题'
  and row.virt_text_pos == 'eol')

done()
vim.cmd('qa!')

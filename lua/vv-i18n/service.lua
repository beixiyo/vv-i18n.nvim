-- Public facade. Stateful ownership and behavior live in service/* modules.
require('vv-i18n.types')

local Runtime = require('vv-i18n.service.runtime')
local Query = require('vv-i18n.service.query')
local Commands = require('vv-i18n.service.commands')
local Lifecycle = require('vv-i18n.service.lifecycle')

local M = {}
local state = Runtime.new()

function M.setup(opts) return Lifecycle.setup(state, M, opts) end
function M.reload() return Lifecycle.reload(state, M) end
function M.lookup(full_key) return Query.lookup(state, M, full_key) end
function M.files_for(full_key) return Query.files_for(state, M, full_key) end
function M.has_keys() return Query.has_keys(state, M) end
function M.classify(full_key) return Query.classify(state, M, full_key) end
function M.tree() return Query.tree(state, M) end
function M.missing_report() return Query.missing_report(state, M) end
function M.definitions_for_file(path) return Query.definitions_for_file(state, M, path) end
function M.pick_lang(per) return Query.pick_lang(state, M, per) end
function M.preferred_lang(langs) return Query.preferred_lang(state, M, langs) end
function M.resolve_cursor(bufnr) return Query.resolve_cursor(state, M, bufnr) end
function M.collect_buffer(bufnr) return Query.collect_buffer(state, M, bufnr) end
function M.collect_content(content, path) return Query.collect_content(state, M, content, path) end
function M.reference_names() return Query.reference_names(state, M) end
function M.definition_at_cursor(bufnr) return Query.definition_at_cursor(state, M, bufnr) end
function M.open_panel() return Commands.open_panel(M) end
function M.open_missing_panel() return Commands.open_missing_panel(M) end
function M.open_references() return Commands.open_references(M) end
function M.edit_cursor() return Commands.edit_cursor(M) end
function M.writer_opts() return { quote_style = state.config.quote_style, indent = state.config.indent } end
function M.enable() return require('vv-i18n.display').enable(M, state.config) end
function M.disable() return require('vv-i18n.display').disable() end
function M.toggle() return require('vv-i18n.display').toggle(M, state.config) end
function M.get_config() return Runtime.get_config(state) end
function M.get_state() return Runtime.get_state(state) end

return M

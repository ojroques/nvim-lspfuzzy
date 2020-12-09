-- nvim-lspfuzzy
-- By Olivier Roques
-- github.com/ojroques

-------------------- ALIASES -------------------------------
local cmd, fn, g = vim.cmd, vim.fn, vim.g
local lsp = require 'vim.lsp'

-------------------- OPTIONS -------------------------------
local opts = {
  methods = 'all',        -- either 'all' or a list of methods
  fzf_options = {},       -- options passed to FZF
  fzf_modifier = ':~:.',  -- format FZF entries, see |filename-modifiers|
  fzf_trim = true,        -- trim FZF entries
}

-------------------- HELPERS -------------------------------
local function echo(hlgroup, msg)
  cmd('echohl ' .. hlgroup)
  cmd('echo "lspfuzzy: ' .. msg .. '"')
  cmd('echohl None')
end

local function extend_start(tbl, values)
  for i, _ in ipairs(values) do
    table.insert(tbl, 1, values[#values + 1 - i])
  end
end

-------------------- FZF FUNCTIONS -------------------------
local function item_to_entry(item)
  local filename = fn.fnamemodify(item.filename, opts.fzf_modifier)
  local text = opts.fzf_trim and vim.trim(item.text) or item.text
  return filename .. ':' .. item.lnum .. ':' .. item.col .. ': ' .. text
end

local function jump(entry)
  if not entry or entry == '' then return end
  local split = vim.split(entry, ':')
  local uri = vim.uri_from_fname(fn.fnamemodify(split[1], ':p'))
  local line = tonumber(split[2]) - 1
  local column = tonumber(split[3]) - 1
  local position = {line = line, character = column}
  local range = {start = position, ['end'] = position}
  local location = {uri = uri, range = range}
  lsp.util.jump_to_location(location)
end

local function fzf(source)
  if not g.loaded_fzf then
    echo('WarningMsg', 'FZF is not loaded.')
    return
  end
  local fzf_opts = opts.fzf_options
  if not fzf_opts or vim.tbl_isempty(fzf_opts) then
    if fn.exists('*fzf#vim#with_preview') ~= 0 then
      local extra_opts = {'--delimiter', ':', '--preview-window', '+{2}-/2'}
      fzf_opts = fn['fzf#vim#with_preview']().options
      extend_start(fzf_opts, extra_opts)
    end
  end
  local fzf_opts_wrap = fn['fzf#wrap']({source = source, options = fzf_opts})
  fzf_opts_wrap['sink*'] = nil
  fzf_opts_wrap['sink'] = jump
  fn['fzf#run'](fzf_opts_wrap)
end

-------------------- LSP HANDLERS --------------------------
local function symbol_handler(_, _, result, _, bufnr)
  if not result or vim.tbl_isempty(result) then return end
  local items = lsp.util.symbols_to_items(result, bufnr)
  local source = vim.tbl_map(item_to_entry, items)
  fzf(source)
end

local function location_handler(_, _, result)
  if not result or vim.tbl_isempty(result) then return end
  if not vim.tbl_islist(result) then
    lsp.util.jump_to_location(result)
    return
  end
  if #result == 1 then
    lsp.util.jump_to_location(result[1])
    return
  end
  local items = lsp.util.locations_to_items(result)
  local source = vim.tbl_map(item_to_entry, items)
  fzf(source)
end

local function make_call_hierarchy_handler(direction)
  return function(_, _, result)
    if not result or vim.tbl_isempty(result) then return end
    local items = {}
    for _, call_hierarchy_call in pairs(result) do
      local call_hierarchy_item = call_hierarchy_call[direction]
      for _, range in pairs(call_hierarchy_call.fromRanges) do
        table.insert(items, {
          filename = vim.uri_to_fname(call_hierarchy_item.uri),
          text = call_hierarchy_item.name,
          lnum = range.start.line + 1,
          col = range.start.character + 1,
        })
      end
    end
    local source = vim.tbl_map(item_to_entry, items)
    fzf(source)
  end
end

-------------------- SETUP ---------------------------------
local handlers = {
  ['callHierarchy/incomingCalls'] = make_call_hierarchy_handler('from'),
  ['callHierarchy/outgoingCalls'] = make_call_hierarchy_handler('to'),
  ['textDocument/declaration'] = location_handler,
  ['textDocument/definition'] = location_handler,
  ['textDocument/documentSymbol'] = symbol_handler,
  ['textDocument/implementation'] = location_handler,
  ['textDocument/references'] = location_handler,
  ['textDocument/typeDefinition'] = location_handler,
  ['workspace/symbol'] = symbol_handler,
}

local function set_handler(method)
  lsp.handlers[method] = handlers[method]
end

local function setup(user_opts)
  opts = vim.tbl_extend('keep', user_opts, opts)
  local methods = opts.methods
  if methods == 'all' then
    methods = vim.tbl_keys(handlers)
  end
  vim.tbl_map(set_handler, methods)
end

------------------------------------------------------------
return {
  setup = setup,
}

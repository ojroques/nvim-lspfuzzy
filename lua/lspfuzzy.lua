-- nvim-lspfuzzy
-- By Olivier Roques
-- github.com/ojroques

-------------------- ALIASES -------------------------------
local cmd, fn, g = vim.cmd, vim.fn, vim.g
local lsp = require 'vim.lsp'

-------------------- OPTIONS -------------------------------
local opts = {
  methods = 'all',         -- either 'all' or a list of LSP methods
  fzf_options = {},        -- options passed to FZF
  fzf_action = {           -- additional FZF commands
    ['ctrl-t'] = 'tabedit',  -- go to location in a new tab
    ['ctrl-v'] = 'vsplit',   -- go to location in a vertical split
    ['ctrl-x'] = 'split',    -- go to location in a horizontal split
  },
  fzf_modifier = ':~:.',   -- format FZF entries, see |filename-modifiers|
  fzf_trim = true,         -- trim FZF entries
}

-------------------- HELPERS -------------------------------
local function echo(hlgroup, msg)
  cmd('echohl ' .. hlgroup)
  cmd('echo "lspfuzzy: ' .. msg .. '"')
  cmd('echohl None')
end

local function lsp_to_fzf(item)
  local filename = fn.fnamemodify(item.filename, opts.fzf_modifier)
  local text = opts.fzf_trim and vim.trim(item.text) or item.text
  return filename .. ':' .. item.lnum .. ':' .. item.col .. ': ' .. text
end

local function fzf_to_lsp(entry)
  local split = vim.split(entry, ':')
  local uri = vim.uri_from_fname(fn.fnamemodify(split[1], ':p'))
  local line = tonumber(split[2]) - 1
  local column = tonumber(split[3]) - 1
  local position = {line = line, character = column}
  local range = {start = position, ['end'] = position}
  return {uri = uri, range = range}
end

-------------------- FZF FUNCTIONS -------------------------
local function jump(entries)
  if not entries or #entries < 2 then return end
  local key = table.remove(entries, 1)
  local locations = vim.tbl_map(fzf_to_lsp, entries)
  -- A FZF action was used
  if opts.fzf_action[key] then
    cmd(opts.fzf_action[key])
  end
  -- Use the quickfix list to store remaining locations
  if #locations > 1 then
    lsp.util.set_qflist(lsp.util.locations_to_items(locations))
    cmd 'copen'
    cmd 'wincmd p'
  end
  lsp.util.jump_to_location(locations[1])
end

local function fzf(source)
  if not g.loaded_fzf then
    echo('WarningMsg', 'FZF is not loaded.')
    return
  end
  local fzf_opts = opts.fzf_options
  -- Set up default FZF options
  if not fzf_opts or vim.tbl_isempty(fzf_opts) then
    fzf_opts = {
      '--ansi',
      '--bind', 'ctrl-a:select-all,ctrl-d:deselect-all',
      '--expect', table.concat(vim.tbl_keys(opts.fzf_action), ','),
      '--multi',
    }
    -- Enable preview with fzf.vim
    if g.loaded_fzf_vim then
      vim.list_extend(fzf_opts, {
        '--delimiter', ':',
        '--preview-window', '+{2}-/2'
      })
      vim.list_extend(fzf_opts, fn['fzf#vim#with_preview']().options)
    end
  end
  local fzf_opts_wrap = fn['fzf#wrap']({source = source, options = fzf_opts})
  fzf_opts_wrap['sink*'] = jump  -- 'sink*' needs to be assigned outside wrap()
  fn['fzf#run'](fzf_opts_wrap)
end

-------------------- LSP HANDLERS --------------------------
local function symbol_handler(_, _, result, _, bufnr)
  if not result or vim.tbl_isempty(result) then return end
  local items = lsp.util.symbols_to_items(result, bufnr)
  local source = vim.tbl_map(lsp_to_fzf, items)
  fzf(source)
end

local function location_handler(_, _, result)
  if not result or vim.tbl_isempty(result) then return end
  -- Jump immediately if not a list
  if not vim.tbl_islist(result) then
    lsp.util.jump_to_location(result)
    return
  end
  -- Jump immediately if there is only one location
  if #result == 1 then
    lsp.util.jump_to_location(result[1])
    return
  end
  local items = lsp.util.locations_to_items(result)
  local source = vim.tbl_map(lsp_to_fzf, items)
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
    local source = vim.tbl_map(lsp_to_fzf, items)
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

local function setup(user_opts)
  local set_handler = function(m) lsp.handlers[m] = handlers[m] end
  -- Use the FZF 'action' option instead of default commands
  if g.fzf_action then
    opts.fzf_action = g.fzf_action
  end
  opts = vim.tbl_extend('keep', user_opts, opts)
  -- Redefine all LSP handlers
  if opts.methods == 'all' then
    opts.methods = vim.tbl_keys(handlers)
  end
  vim.tbl_map(set_handler, opts.methods)
end

------------------------------------------------------------
return {
  setup = setup,
}

-- nvim-lspfuzzy
-- By Olivier Roques
-- github.com/ojroques

-------------------- VARIABLES -----------------------------
local fmt = string.format
local offset_encoding    -- hold client offset encoding (see :h vim.lsp.client)
local last_results = {}  -- hold last location results
local ansi_purple = '\u{001b}[35m'
local ansi_green = '\u{001b}[32m'
local ansi_reset = '\u{001b}[0m'

-------------------- OPTIONS -------------------------------
local opts = {
  methods = 'all',         -- either 'all' or a list of LSP methods
  jump_one = true,         -- jump immediately if there is only one location
  save_last = false,       -- save last location results for the :LspFuzzyLast command
  callback = nil,          -- callback called after jumping to a location
  fzf_preview = {          -- arguments to the FZF '--preview-window' option
    'right:+{2}-/2'          -- preview on the right and centered on entry
  },
  fzf_action = {               -- FZF actions
    ['ctrl-t'] = 'tab split',  -- go to location in a new tab
    ['ctrl-v'] = 'vsplit',     -- go to location in a vertical split
    ['ctrl-x'] = 'split',      -- go to location in a horizontal split
  },
  fzf_modifier = ':~:.',   -- format FZF entries, see |filename-modifiers|
  fzf_trim = true,         -- trim FZF entries
}

-------------------- HELPERS -------------------------------
local function echo(hlgroup, msg)
  vim.cmd(fmt('echohl %s', hlgroup))
  vim.cmd(fmt('echom "[lspfuzzy] %s"', msg))
  vim.cmd('echohl None')
end

local function lsp_to_fzf(item)
  local path = vim.fn.fnamemodify(item.filename, opts.fzf_modifier)
  local text = opts.fzf_trim and vim.trim(item.text) or item.text
  return fmt(
    ansi_purple .. '%s:'
    .. ansi_green .. '%s:'
    .. ansi_reset .. '%s: %s', path, item.lnum, item.col, text
  )
end

local function fzf_to_lsp(entry)
  local split = vim.split(entry, ':')
  local uri = vim.uri_from_fname(vim.fn.fnamemodify(split[1], ':p'))
  local line = tonumber(split[2]) - 1
  local column = tonumber(split[3]) - 1
  local position = {line = line, character = column}
  local range = {start = position, ['end'] = position}
  return {uri = uri, range = range}
end

local function jump_to_location(location)
  vim.lsp.util.jump_to_location(location, offset_encoding)
  if type(opts.callback) == 'function' then
    opts.callback()
  end
end

-------------------- FZF FUNCTIONS -------------------------
local function jump(entries)
  if not entries or #entries < 2 then
    return
  end

  -- Retrieve user action
  local key = table.remove(entries, 1)
  local action = opts.fzf_action[key]

  -- Apply user action to all entries if it's a function
  if type(action) == 'function' then
    action(entries)
    return
  end

  -- Convert FZF entries to locations
  local locations = vim.tbl_map(fzf_to_lsp, entries)

  -- Use the quickfix list to store remaining locations
  if #locations > 1 then
    vim.lsp.util.set_qflist(vim.lsp.util.locations_to_items(locations, offset_encoding))
    vim.cmd 'copen'
    vim.cmd 'wincmd p'
  end

  -- Apply user action to the first location
  if action then
    vim.cmd(fmt('%s %s', action, vim.uri_to_fname(locations[1].uri)))
  end

  -- Jump to the first location
  jump_to_location(locations[1])
end

local function build_fzf_opts(label, preview, multi)
  local prompt = fmt('%s> ', label)
  local fzf_opts = {
    '--ansi',
    '--delimiter', ':',
    '--keep-right',
    '--prompt', prompt,
  }

  -- Enable FZF actions
  if opts.fzf_action and not vim.tbl_isempty(opts.fzf_action) then
    vim.list_extend(fzf_opts, {
      '--expect', table.concat(vim.tbl_keys(opts.fzf_action), ',')
    })
  end

  -- Enable preview with fzf.vim
  if preview and opts.fzf_preview and vim.g.loaded_fzf_vim then
    local args = vim.fn['fzf#vim#with_preview'](unpack(opts.fzf_preview)).options
    vim.list_extend(fzf_opts, args)
  end

  -- Enable multi-selection
  if multi then
    vim.list_extend(fzf_opts, {
      '--bind', 'ctrl-a:select-all,ctrl-d:deselect-all',
      '--multi',
    })
  end

  return fzf_opts
end

local function fzf(source, label, sink, preview, multi)
  if not vim.g.loaded_fzf then
    return echo('WarningMsg', 'FZF is not loaded')
  end

  -- Save jump results for the :LspFuzzyLast command
  if opts.save_last and sink == jump then
    last_results = {source = source, label = label, preview = preview, multi = multi}
  end

  -- Build FZF options
  local fzf_opts = build_fzf_opts(label, preview, multi)
  local fzf_opts_wrap = vim.fn['fzf#wrap']({source = source, options = fzf_opts})
  fzf_opts_wrap['sink*'] = sink  -- 'sink*' needs to be defined outside wrap()

  -- Run FZF
  vim.fn['fzf#run'](fzf_opts_wrap)
end

-------------------- LSP HANDLERS --------------------------
local function symbol_handler(label, result, ctx)
  local items = vim.lsp.util.symbols_to_items(result, ctx.bufnr)
  local source = vim.tbl_map(lsp_to_fzf, items)
  fzf(source, label, jump, true, true)
end

local function location_handler(label, result)
  result = vim.tbl_islist(result) and result or {result}

  if opts.jump_one and #result == 1 then
    return jump_to_location(result[1])
  end

  local items = vim.lsp.util.locations_to_items(result, offset_encoding)
  local source = vim.tbl_map(lsp_to_fzf, items)
  fzf(source, label, jump, true, true)
end

local function make_call_hierarchy_handler(direction)
  return function(label, result)
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
    fzf(source, label, jump, true, true)
  end
end

-------------------- COMMANDS ------------------------------
local function diagnostics_cmd(diagnostics)
  local label = 'Diagnostics'
  local items = {}

  for _, diagnostic in ipairs(diagnostics) do
    table.insert(items, {
      filename = vim.api.nvim_buf_get_name(diagnostic.bufnr),
      text = diagnostic.message,
      lnum = diagnostic.lnum + 1,
      col = diagnostic.col + 1,
    })
  end

  if vim.tbl_isempty(items) then
    return echo('None', fmt('No %s available', string.lower(label)))
  end

  offset_encoding = 'utf-16'

  local source = vim.tbl_map(lsp_to_fzf, items)
  fzf(source, label, jump, true, true)
end

local function last_results_cmd()
  if not opts.save_last then
    echo('WarningMsg', "The 'save_last' option is set to false")
    return
  end

  if not last_results or vim.tbl_isempty(last_results) then
    echo('None', 'No location results to display yet')
    return
  end

  local label = fmt('%s (last)', last_results.label)
  fzf(last_results.source, label, jump, last_results.preview, last_results.multi)
end

-------------------- SETUP ---------------------------------
local handlers = {
  ['callHierarchy/incomingCalls'] = {label = 'Incoming Calls', target = make_call_hierarchy_handler('from')},
  ['callHierarchy/outgoingCalls'] = {label = 'Outgoing Calls', target = make_call_hierarchy_handler('to')},
  ['textDocument/declaration'] = {label = 'Declarations', target = location_handler},
  ['textDocument/definition'] = {label = 'Definitions', target = location_handler},
  ['textDocument/documentSymbol'] = {label = 'Document Symbols', target = symbol_handler},
  ['textDocument/implementation'] = {label = 'Implementations', target = location_handler},
  ['textDocument/references'] = {label = 'References', target = location_handler},
  ['textDocument/typeDefinition'] = {label = 'Type Definitions', target = location_handler},
  ['workspace/symbol'] = {label = 'Workspace Symbols', target = symbol_handler},
}

local function wrap_handler(handler)
  return function(err, result, ctx, config)
    if err then
      return echo('ErrorMsg', err.message)
    end

    -- Print error if no result
    if not result or vim.tbl_isempty(result) then
      return echo('None', fmt('No %s found', string.lower(handler.label)))
    end

    -- Save offset encoding
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    offset_encoding = client and client.offset_encoding or 'utf-16'

    return handler.target(handler.label, result, ctx, config)
  end
end

local function load_fzf_opts()
  local fzf_opts = {}

  fzf_opts.fzf_action = vim.g.fzf_action
  fzf_opts.fzf_preview = vim.g.fzf_preview_window

  if type(fzf_opts.fzf_preview) == 'string' then
    fzf_opts.fzf_preview = {fzf_opts.fzf_preview}
  end

  return fzf_opts
end

local function setup(user_opts)
  if vim.fn.has('nvim-0.6') == 0 then
    echo('WarningMsg', 'This plugin requires at least Neovim 0.6')
    return
  end

  -- Load FZF options
  opts = vim.tbl_extend('keep', load_fzf_opts(), opts)

  -- Load user options
  if user_opts then
    opts = vim.tbl_extend('keep', user_opts, opts)
  end

  -- Use all handlers
  if opts.methods == 'all' then
    opts.methods = vim.tbl_keys(handlers)
  end

  -- Set LSP handlers
  for _, m in ipairs(opts.methods) do
    vim.lsp.handlers[m] = wrap_handler(handlers[m])
  end
end

------------------------------------------------------------
return {
  diagnostics = function(bufnr)
    bufnr = tonumber(bufnr)
    diagnostics_cmd(vim.diagnostic.get(bufnr))
  end,
  diagnostics_all = function()
    diagnostics_cmd(vim.diagnostic.get())
  end,
  last_results = function()
    last_results_cmd()
  end,
  setup = setup,
}

# nvim-lspfuzzy

This plugin makes Neovim LSP use [FZF](https://github.com/junegunn/fzf) to
display results and jump around the code.

It works by redefining LSP handlers to custom ones that call FZF, therefore
you don't need to change any of your LSP mappings. It's also **small**
(currently sitting at ~160 LOC) and **written entirely in Lua**.

The plugin is compatible only with Neovim 0.5+.

## Installation

#### With Packer
In your *plugins.lua*:
```lua
cmd 'packadd packer.nvim'
return require('packer').startup(function()
  use {
    'ojroques/nvim-lspfuzzy'
    requires = {
      'junegunn/fzf',
      {'junegunn/fzf.vim', opt = true}  -- to enable preview (optional)
    }
  }
end)
```

#### With Plug
In your *.vimrc* or *init.vim*:
```vim
call plug#begin()
Plug 'junegunn/fzf', {'do': {-> fzf#install()}}
Plug 'junegunn/fzf.vim'  " to enable preview (optional)
Plug 'ojroques/nvim-lspfuzzy'
```

#### With Paq
[Paq](https://github.com/savq/paq-nvim) is a lightweight package manager
written in Lua for Neovim. In your *init.lua*:
```lua
cmd 'packadd paq-nvim'
local paq = require('paq-nvim').paq
paq 'junegunn/fzf'
paq 'junegunn/fzf.vim'  -- to enable preview (optional)
paq 'ojroques/nvim-lspfuzzy'
```

## Usage
Simply add this line to your *init.lua*:
```lua
require('lspfuzzy').setup {}
```

If you're using a *.vimrc* or *init.vim*, you need to enclose the line in a lua
block:
```vim
lua <<EOF
require('lspfuzzy').setup {}
EOF
```

You can pass options to the `setup()` function. Here are the default settings:
```lua
require('lspfuzzy').setup {
  methods = 'all',        -- either 'all' or a list of LSP methods (see below)
  fzf_options = {},       -- options passed to FZF
  fzf_modifier = ':~:.',  -- format FZF entries, see |filename-modifiers|
  fzf_trim = true,        -- trim FZF entries
}
```

Usual shortcuts from FZF are enabled:
* `tab`: select multiple entries
* `shift+tab`: deselect an entry
* `ctrl-a`: select all entries
* `ctrl-d`: deselect all entries
* `ctrl-t`: open location in a new tab
* `ctrl-v`: open location in a vertical split
* `ctrl-x`: open location in a horizontal split

## Supported LSP methods
You can enable FZF only for a subset of LSP methods by passing them as a list
to the `methods` option when calling `setup()`. The supported LSP methods are:
```
callHierarchy/incomingCalls
callHierarchy/outgoingCalls
textDocument/declaration
textDocument/definition
textDocument/documentSymbol
textDocument/implementation
textDocument/references
textDocument/typeDefinition
workspace/symbol
```

## Troubleshoot

#### Using the `fzf_modifier` option breaks the plugin.
The plugin uses the filename contained in the FZF entry selected by the user
to jump to the correct location. Therefore it must resolve to a valid path.
For instance `:.` or `:p` can be used but not `:t`.

## License
[LICENSE](./LICENSE)

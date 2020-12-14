" nvim-lspfuzzy
" By Olivier Roques
" github.com/ojroques

if exists('g:loaded_lspfuzzy')
  finish
endif

command! LspDiagnostics lua require('lspfuzzy').diagnostics()

let g:loaded_lspfuzzy = 1

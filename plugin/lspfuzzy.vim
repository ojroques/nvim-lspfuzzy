" nvim-lspfuzzy
" By Olivier Roques
" github.com/ojroques

if exists('g:loaded_lspfuzzy')
  finish
endif

command! -nargs=1 LspDiagnostics lua require('lspfuzzy').diagnostics(<f-args>)
command! LspDiagnosticsAll lua require('lspfuzzy').diagnostics_all()

let g:loaded_lspfuzzy = 1

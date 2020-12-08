if exists('g:loaded_lspfuzzy')
  finish
endif

command! FuzzyTest lua require('lspfuzzy').test()

let g:loaded_lspfuzzy = 1

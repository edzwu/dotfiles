" line_number.vim - toggle absolute and relative line numbers together
"
" Map: <leader>Ln

if exists('g:loaded_line_number')
  finish
endif
let g:loaded_line_number = 1

function! s:ToggleLineNumber() abort
  if &number || &relativenumber
    set nonumber norelativenumber
    echo 'Line numbers off'
  else
    set number relativenumber
    echo 'Line numbers on'
  endif
endfunction

" Keep both options synchronized even if one was changed manually.
nnoremap <silent> <leader>Ln :call <SID>ToggleLineNumber()<CR>

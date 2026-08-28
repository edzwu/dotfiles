" miru_snippet.vim — 光标处函数 → membox miru 网页
" 用法: 光标放在函数内, 执行 :MiruSnippet

if exists('g:loaded_miru_snippet')
  finish
endif
let g:loaded_miru_snippet = 1

command! MiruSnippet call miru_snippet#send()

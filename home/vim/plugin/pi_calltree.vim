" pi_calltree.vim — vim-lsp call hierarchy → pi → 交互式 HTML
" 用法: 光标放在函数名上, 执行 :PiCallTree [depth] [down|up|both]
"       depth 默认 3; 方向默认 both(双向)，down=只看被调用，up=只看调用者

if exists('g:loaded_pi_calltree')
  finish
endif
let g:loaded_pi_calltree = 1

command! -nargs=* -complete=customlist,pi_calltree#complete PiCallTree call pi_calltree#start(<f-args>)
command! PiCallTreeLog call pi_calltree#open_log()

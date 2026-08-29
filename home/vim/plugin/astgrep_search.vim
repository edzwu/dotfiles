" astgrep_search.vim — 交互式搜索窗口(fzf,按下即弹):ast-grep + rg 合并
" 用法:
"   \g                   按下立即弹出 fzf 窗口(vimrc 里映射),窗口内输入实时搜索
"     直接输入  = ast-grep AST 搜索,如 detect_from_document / $A.unwrap()
"     k:        = kind 候选列表,输字母前缀过滤(如 k:f → fn/for)
"                 选中回车进入该类型搜索模式,接着输名字过滤:
"                 k: → fn → 回车 → detect_from_document → 回车跳转
"     r:文本    = rg 全文搜索(正则),如 r:DetectionConfig
"   打开时显示模式库模板(选中回车自动填入搜索)
"   \G                   全屏版;fzf 里可多选(alt-a 全选),回车结果进 quickfix
"   :AstGrep <pattern>    等价,可预填
"   默认搜 vim 当前目录(和原 :Rg 一致),想搜别的 repo 先 :cd 过去
"   语言按当前 buffer 的 filetype 自动推断,可用 let g:astgrep_lang="Rust" 覆盖
"   依赖: ast-grep CLI、rg、fzf.vim
"   注: 原 :Rg 命令仍在(after/plugin/rg_fzf.vim),可手动调用

if exists('g:loaded_astgrep_search')
  finish
endif
let g:loaded_astgrep_search = 1

command! -bang -nargs=* AstGrep call astgrep_search#run(<q-args>, <bang>0)
" 快捷键在 vimrc:\g = :AstGrep / \G = :AstGrep!
" nnoremap <leader>a :AstGrep<CR>  " 如需 leader 键备选,取消注释

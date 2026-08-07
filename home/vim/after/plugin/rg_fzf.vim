" plugin/rg_fzf.vim
" Commands + <Plug> 映射；实现都在 autoload/zw/rg.vim

if exists('g:loaded_zw_rg_fzf') | finish | endif

" ---- 依赖检查（可选，缺失时给出一次性提示） -------------------------------
" Consider fzf.vim present if its autoload file is on &rtp
if empty(globpath(&rtp, 'autoload/fzf/vim.vim'))
  if !exists('g:loaded_zw_rg_fzf_missing')
    echohl WarningMsg
    echom '[zw-rg] fzf.vim not on runtimepath (install fzf + fzf.vim).'
    echohl None
    let g:loaded_zw_rg_fzf_missing = 1
  endif
  finish
endif
" Leaf may need the absolute-path fallback even after vimrc updates $PATH.
if !executable('rg') && !executable('/opt/homebrew/bin/rg')
  echohl WarningMsg | echom '[zw-rg] ripgrep (rg) not found in PATH.' | echohl None
endif

let g:loaded_zw_rg_fzf = 1

" ---- Rg 搜索命令（调用 autoload/zw/rg.vim） -------------------------------
command! -nargs=* Rg      call zw#rg#run('smart', <q-args>)
command! -nargs=* Rgcs  call zw#rg#run('case',  <q-args>)
command! -nargs=* RgExact call zw#rg#run('exact', <q-args>)
command! -nargs=* Rgf     call zw#rg#run('file',  <q-args>)

" ---- Rg 做替换的工作 ------------------------------------------------------
nnoremap <silent> <Plug>(zw-rg-replace-files)  :<C-u>call zw#rg#replace_in_files_prompt()<CR>
nnoremap <silent> <Plug>(zw-rg-replace-buffer) :<C-u>call zw#rg#replace_in_buffer_prompt()<CR>
" ---- 默认键位（仅当用户未关闭时设置） ------------------------------
if get(g:, 'zw_rg_default_mappings', 0)
  nmap <silent> <leader>rfs <Plug>(zw-rg-replace-files)
  nmap <silent> <leader>rf <Plug>(zw-rg-replace-buffer)
endif

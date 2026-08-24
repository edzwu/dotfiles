" gtags_fzf.vim - gtags 查询结果 → fzf 弹窗(bat 预览)→ quickfix 工作台
"
" 方案 C 的实现:把 gtags 的定义/引用/调用者查询送进 fzf,弹窗里用 bat 预览,
" Tab 多选,Enter 后:
"   - 单选(未标记):直接跳到文件:行(快走路径)
"   - 多选(已标记):全部进 quickfix(工作台路径,第 0/1 层的 p 预览/]q 翻页/\qh 历史全部生效)
"
" 依赖: gtags(global/gtags-cscope)、fzf.vim、bat(预览用,缺省回退 cat -n)
" 数据源是 gtags(名字匹配);类型精确的引用请用 vim-lsp 的 \lr

" 查询并解析 gtags 输出,返回 [[绝对路径, 行号, 文本], ...]
" flag: g=定义  r=引用  c=调用者(谁调用了它)
function! gtags_fzf#items(word, flag) abort
  let l:root = exists('b:gutentags_root') ? b:gutentags_root : getcwd()
  let l:cmd = a:flag ==# 'c'
        \ ? printf('cd %s && gtags-cscope -L3 %s', shellescape(l:root), shellescape(a:word))
        \ : printf('cd %s && global -x%s %s', shellescape(l:root), a:flag ==# 'r' ? 'r' : '', shellescape(a:word))
  let l:items = []
  for l:line in systemlist(l:cmd)
    let l:fields = split(l:line)
    if len(l:fields) < 3
      continue
    endif
    if l:fields[1] =~# '^\d\+$' && filereadable(l:root . '/' . l:fields[2])
      " global -x/-xr: symbol line file text
      let [l:file, l:lnum, l:text] = [l:fields[2], str2nr(l:fields[1]), join(l:fields[3:], ' ')]
    elseif l:fields[2] =~# '^\d\+$'
      " gtags-cscope -L: file symbol line text
      let [l:file, l:lnum, l:text] = [l:fields[0], str2nr(l:fields[2]), join(l:fields[3:], ' ')]
    else
      continue
    endif
    call add(l:items, [l:root . '/' . l:file, l:lnum, l:text])
  endfor
  return l:items
endfunction

" 打开 fzf 弹窗(多选 + bat 预览)
" flag: g/r/c, label: 用于 fzf 历史记录前缀(如 'def'/'ref'/'call')
function! gtags_fzf#run(flag, label) abort
  let l:word = expand('<cword>')
  if l:word ==# ''
    echom '[gtags-fzf] no word under cursor'
    return
  endif
  let l:items = gtags_fzf#items(l:word, a:flag)
  if empty(l:items)
    echom printf('[gtags-fzf] no result: %s', l:word)
    return
  endif
  let l:root = exists('b:gutentags_root') ? b:gutentags_root : getcwd()
  " 供 fzf 显示的格式: 绝对路径:行号: 文本(用 : 分隔,preview 取 {1}=文件 {2}=行)
  let l:source = map(copy(l:items), 'v:val[0] . ":" . v:val[1] . ": " . v:val[2]')
  let l:cat = executable('bat') ? 'bat --color=always -n' : 'cat -n'
  let l:preview = 'cd ' . shellescape(l:root) . ' && ' . l:cat . ' -H {2} {1}'
  call fzf#run(fzf#wrap(a:label, {
        \ 'source': l:source,
        \ 'sink*': function('gtags_fzf#apply'),
        \ 'options': [
        \   '--multi',
        \   '--bind', 'ctrl-a:select-all',
        \   '--prompt', printf('%s %s> ', a:label, l:word),
        \   '--delimiter', ':',
        \   '--preview', l:preview,
        \   '--preview-window', 'right:60%',
        \ ],
        \ 'down': '40%',
        \ }))
endfunction

" fzf 多选回调: 单选快跳, 多选进 quickfix 工作台
function! gtags_fzf#apply(selected) abort
  if empty(a:selected)
    return
  endif
  let l:qf = []
  for l:item in a:selected
    " 格式: 绝对路径:行号: 文本。文件路径不含 ':'(macOS),
    " 正文里的 ':' 用 join(parts[2:], ':') 原样保留,比正则稳
    let l:parts = split(l:item, ':')
    if len(l:parts) < 2 || l:parts[1] !~# '^\d\+$'
      continue
    endif
    call add(l:qf, {'filename': l:parts[0], 'lnum': str2nr(l:parts[1]), 'text': join(l:parts[2:], ':')})
  endfor
  if empty(l:qf)
    return
  endif
  if len(l:qf) == 1
    " 快走路径: 单选直接跳转
    execute 'edit +' . l:qf[0].lnum . ' ' . fnameescape(l:qf[0].filename)
    return
  endif
  " 工作台路径: 多选进 quickfix,第 0/1 层的 p/]q/[q/\qh 全部接管
  call setqflist([], 'r', {'items': l:qf})
  botright copen
endfunction

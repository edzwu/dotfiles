" autoload/zw/rg.vim
" 旧逻辑保留：Rg 搜索 + FZF 选择 + 逐文件替换（y/n/a/q）

" ---------- 搜索公用 ----------
function! zw#rg#_base() abort
  return 'rg --column --line-number --no-heading --color=always --hidden --with-filename --glob "!{.git,node_modules}/*" '
endfunction


function! zw#rg#_preview() abort
  return fzf#vim#with_preview({
        \ 'options': [
        \   '--multi',
        \   '--preview',
        \   'bat --theme=base16-256 --color=always --style=numbers --highlight-line {2} {1}'
        \ ]
        \ })
endfunction


" mode: smart/case/exact/file;可选第三参 fullscreen(0/1)
" smart 模式空参数 → 交互式窗口(按下即弹,输入实时过滤,全 repo 搜索)
function! zw#rg#run(mode, args, ...) abort
  let l:fullscreen = a:0 ? a:1 : 0
  if a:mode ==# 'smart' && empty(a:args)
    return zw#rg#interactive(l:fullscreen)
  endif
  let base = zw#rg#_base()
  if a:mode ==# 'smart'
    let cmd = base . '--smart-case ' . a:args
  elseif a:mode ==# 'case'
    let cmd = base . '--case-sensitive ' . a:args
  elseif a:mode ==# 'exact'
    " PCRE2 词边界：(?<!\w)pat(?!\w)
    let pat = '(?<!\w)'.a:args.'(?!\w)'
    let cmd = base . '--pcre2 --case-sensitive ' . shellescape(pat)
  elseif a:mode ==# 'file'
    let cmd = base . '--pcre2 --case-sensitive ' . a:args . ' ' . shellescape(expand('%:p'))
  else
    echoerr 'Unknown mode: ' . a:mode | return
  endif
  call fzf#vim#grep(cmd, 1, zw#rg#_preview(), l:fullscreen)
endfunction

" ---------- 交互式全局搜索(\g:按下即弹,输入即搜,与 filetype 无关) ----------

" 去除 ANSI 颜色码(rg --color=always 输出,fzf --ansi 渲染,sink 收到原始行)
function! s:strip_ansi(s) abort
  return substitute(a:s, '\%x1b\[[0-9;]*m', '', 'g')
endfunction

" 解析 file:lnum:col:text → quickfix dict
function! s:to_qf(line) abort
  let l:m = matchlist(s:strip_ansi(a:line), '^\(.\{-}\):\(\d\+\):\(\d\+\):\(.*\)$')
  if empty(l:m[1]) || empty(l:m[2]) | return {} | endif
  return {'filename': l:m[1], 'lnum': str2nr(l:m[2]), 'col': str2nr(l:m[3]), 'text': l:m[4]}
endfunction

" 单条跳转 / 多条(alt-a 全选)进 quickfix
function! s:grep_sink(lines) abort
  let l:list = filter(map(copy(a:lines), 's:to_qf(v:val)'), '!empty(v:val)')
  if empty(l:list) | return | endif
  if len(l:list) == 1
    let l:item = l:list[0]
    execute 'edit ' . fnameescape(l:item.filename)
    call cursor(l:item.lnum, l:item.col)
    normal! zvzz
  else
    call setqflist(l:list, 'r')
    copen
  endif
endfunction

function! zw#rg#interactive(bang) abort
  " {q} 由 fzf 负责 shell-escape,勿再额外套引号;空 query 不触发搜索
  let l:reload = zw#rg#_base() . '--smart-case -- {q} || true'
  let l:spec = zw#rg#_preview()
  let l:opts = {
        \ 'source': 'true',
        \ 'sink*': function('s:grep_sink'),
        \ 'options': ['--ansi', '--disabled', '--prompt', 'Rg> ',
        \             '--multi', '--bind', 'alt-a:select-all,alt-d:deselect-all',
        \             '--bind', 'change:reload:' . l:reload,
        \             '--header', '输入即全 repo rg 搜索 | alt-a 全选回车进 quickfix',
        \             '--delimiter', ':', '--preview-window', '+{2}/2']
        \ }
  call extend(l:opts.options, l:spec.options)
  if a:bang
    let l:opts.fullscreen = 1
  endif
  return fzf#run(fzf#wrap(l:opts))
endfunction

" ---------- 旧逻辑：跨文件替换入口 ----------
" 跨文件替换入口
function! zw#rg#replace_in_files_prompt() abort
  let l:target = input('🔎 搜索词: ', expand('<cword>'))
  if empty(l:target) | return | endif

  " 默认值就是原词
  let l:replace = input('↪ 替换为: ', l:target)
  if l:replace ==# l:target
    echo '未修改'
    return
  endif

  let l:rg_cmd = 'rg --vimgrep --no-heading --hidden --glob "!{.git,node_modules}/*" ' .
        \          '--pcre2 --case-sensitive ' . shellescape('(?<!\w)'.l:target.'(?!\w)')

  let l:spec = zw#rg#_preview()
  let l:spec['sink*'] = function('zw#rg#ReplaceInFiles', [l:target, l:replace])
  call fzf#vim#grep(l:rg_cmd, 1, l:spec, 0)
endfunction

" ---------- 旧逻辑：逐文件执行替换（y/n/a/q） ----------
" selected: fzf 传来的选中行列表（file:lnum:col:text）
function! zw#rg#ReplaceInFiles(target, replace, selected) abort
  let l:replace_all = 0
  for l:item in a:selected
    " 解析 file:line:col:text
    let l:m = matchlist(l:item, '^\(.\+\):\(\d\+\):\(\d\+\):.*$')
    if len(l:m) < 4 | continue | endif
    let l:file = l:m[1]
    let l:lnum = str2nr(l:m[2])
    let l:col  = str2nr(l:m[3])

    if !filereadable(l:file) || !filewritable(l:file)
      echohl WarningMsg | echom '跳过不可写文件：' . l:file | echohl None
      continue
    endif

    " 打开文件（不污染 alt-file）
    silent! execute 'keepalt edit ' . fnameescape(l:file)

    if &buftype ==# 'nofile' || !&modifiable
      echohl WarningMsg | echom '跳过特殊缓冲区：' . l:file | echohl None
      continue
    endif

    " 跳到相应位置（主要用于可视反馈）
    call cursor(l:lnum, l:col)

    " 与旧版一致：忽略大小写 + 词边界
    let l:pat = '\c\<'.escape(a:target, '/\').'\>'
    let l:rep = escape(a:replace, '/\')

    if l:replace_all
      " 全文件全局
      silent execute '%s/'.l:pat.'/'.l:rep.'/g'
      write
    else
      echohl Question
      echom '替换：' . a:target . '  -->  ' . a:replace . '   (y/n/a/q)?'
      echohl None
      let l:ch = nr2char(getchar())
      redraw
      if l:ch ==# 'a'
        let l:replace_all = 1
        silent execute '%s/'.l:pat.'/'.l:rep.'/g'
        write
      elseif l:ch ==# 'y'
        " 当前行一次（与旧逻辑一致）
        silent execute 's/'.l:pat.'/'.l:rep.'/'
        write
      elseif l:ch ==# 'q'
        break
      else
        " n：跳过
      endif
    endif
  endfor
endfunction

" ---------- （可选）仅当前文件替换，复用旧匹配规则 ----------
" 仅当前文件替换
function! zw#rg#replace_in_buffer_prompt() abort
  let l:target = input('🔎 搜索词: ', expand('<cword>'))
  if empty(l:target) | return | endif

  " 默认值就是原词
  let l:replace = input('↪ 替换为: ', l:target)
  if l:replace ==# l:target
    echo '未修改'
    return
  endif

  let l:pat = '\c\<'.escape(l:target, '/\').'\>'
  let l:rep = escape(l:replace, '/\')
  execute '%s/'.l:pat.'/'.l:rep.'/gc'
  write
endfunction


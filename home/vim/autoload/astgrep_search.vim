" astgrep_search.vim — 交互式 ast-grep 搜索(fzf 窗口,按下即弹)
" 窗口行为:
"   打开时列出模式库/节点类型模板([pattern] 说明 每行,选中 Enter 即搜索)
"   直接输入 → 实时 AST 搜索(change:reload)
"   k: 前缀 → 渐进过滤 kind;Enter 确认后清空 query,进入名字搜索阶段
"   名字阶段输入框只显示名字;空输入 Backspace 返回 kind 阶段
"   结果回车:单条跳转 / 多条(alt-a)进 quickfix
" 语言按当前 buffer filetype 推断,可用 g:astgrep_lang 覆盖
" reload 逻辑在 bin/astgrep_reload.sh(模板库 + pattern/kind 搜索)

" filetype → ast-grep run -l 的语言名
let s:languages = {
      \ 'rust':           'Rust',
      \ 'go':             'Go',
      \ 'python':         'Python',
      \ 'c':              'C',
      \ 'cpp':            'Cpp',
      \ 'javascript':     'JavaScript',
      \ 'typescript':     'TypeScript',
      \ 'typescriptreact': 'Tsx',
      \ 'html':           'Html',
      \ 'css':            'Css',
      \ 'lua':            'Lua',
      \ 'java':           'Java',
      \ 'kotlin':         'Kotlin',
      \ 'sh':             'Bash',
      \ 'zsh':            'Bash',
      \ 'json':           'Json',
      \ 'php':            'Php',
      \ }

function! s:fail(msg) abort
  echoerr '[astgrep] ' . a:msg
endfunction

" 语言推断:g:astgrep_lang > filetype 映射
function! s:detect_lang() abort
  let l:override = get(g:, 'astgrep_lang', '')
  return empty(l:override) ? get(s:languages, &filetype, '') : l:override
endfunction

" 解析 fzf 结果行 path:line[:col[:content]] → quickfix dict
function! s:to_qf(line) abort
  let parts = matchlist(a:line, '\(.\{-}\)\s*:\s*\(\d\+\)\%(\s*:\s*\(\d\+\)\)\?\%(\s*:\(.*\)\)\?')
  if empty(parts[1]) || empty(parts[2])
    return {}
  endif
  let dict = {'filename': parts[1], 'lnum': str2nr(parts[2]), 'text': parts[4]}
  if len(parts[3])
    let dict.col = str2nr(parts[3])
  endif
  return dict
endfunction

" 去除 ANSI 颜色码(模板/候选行带颜色,fzf --ansi 渲染,sink 收到的是原始行)
function! s:strip_ansi(s) abort
  return substitute(a:s, '\%x1b\[[0-9;]*m', '', 'g')
endfunction

" fzf sink:正常只接收搜索结果;模板分支保留为非 transform 路径的兜底
function! s:sink(state_file, lines) abort
  call delete(a:state_file)
  let lines = map(copy(a:lines), 's:strip_ansi(v:val)')
  if empty(lines) | return | endif
  " 模板行:tab 前是可搜的 pattern/k:kind
  if lines[0] =~# "\t"
    let pattern = matchstr(lines[0], '^[^\t]*')
    call astgrep_search#run(pattern, 0)
    return
  endif
  let list = filter(map(copy(lines), 's:to_qf(v:val)'), '!empty(v:val)')
  if empty(list) | return | endif
  if len(list) == 1
    let item = list[0]
    execute 'edit ' . fnameescape(item.filename)
    execute item.lnum
    if has_key(item, 'col')
      call cursor(0, item.col)
    endif
    normal! zvzz
  else
    call setqflist(list, 'r')
    copen
  endif
endfunction

function! astgrep_search#run(query, bang) abort
  if !executable('ast-grep')
    call s:fail('找不到 ast-grep CLI(brew install ast-grep)')
    return
  endif
  let l:lang = s:detect_lang()
  if empty(l:lang)
    call s:fail('当前 filetype 不支持: ' . &filetype . '(可用 let g:astgrep_lang="Rust" 覆盖)')
    return
  endif
  " junegunn/fzf 把 fzf#run/fzf#wrap 定义在 plugin/fzf.vim(不是 autoload/),
  " fzf#vim#with_preview 在 fzf.vim 插件的 autoload/fzf/vim.vim,两者都检查。
  if empty(globpath(&rtp, 'plugin/fzf.vim')) || empty(globpath(&rtp, 'autoload/fzf/vim.vim'))
    call s:fail('需要 fzf + fzf.vim(Plug junegunn/fzf, junegunn/fzf.vim)')
    return
  endif

  " reload 命令读取会话状态。kind 确认后状态写入临时文件,
  " 第二阶段 query 只包含名字,例如 detect_from_document。
  " {q}/{} 由 fzf 负责 shell-escape,勿再额外套引号。
  let l:script = expand('~/.vim/bin/astgrep_reload.sh')
  let l:state = tempname()
  call writefile(['ast'], l:state)
  let l:base = 'bash ' . shellescape(l:script)
  let l:state_arg = shellescape(l:state)
  let l:reload = l:base . ' reload ' . l:lang . ' ' . l:state_arg . ' {q}'
  let l:enter = l:base . ' enter ' . l:lang . ' ' . l:state_arg . ' {}'
  let l:prompt = l:base . ' prompt ' . l:state_arg . ' {q}'
  let l:backspace = l:base . ' backspace ' . l:state_arg . ' {q}'
  let l:abort = l:base . ' abort ' . l:state_arg
  let l:initial_prompt = a:query =~# '^k:' ? 'Kind> ' : a:query =~# '^r:' ? 'Rg> ' : 'AST> '

  let l:spec = fzf#vim#with_preview()
  " fzf 同一事件的后一个 bind 会覆盖前一个,change actions 必须合并。
  let l:opts = {
        \ 'source': l:reload,
        \ 'sink*': function('s:sink', [l:state]),
        \ 'options': ['--ansi', '--disabled', '--query', a:query, '--prompt', l:initial_prompt,
        \             '--multi', '--bind', 'alt-a:select-all,alt-d:deselect-all',
        \             '--bind', 'start:reload:' . l:reload,
        \             '--bind', 'change:reload(' . l:reload . ')+transform-prompt(' . l:prompt . ')',
        \             '--bind', 'enter:transform:' . l:enter,
        \             '--bind', 'backspace:transform:' . l:backspace,
        \             '--bind', 'esc:transform:' . l:abort,
        \             '--header', 'k: 输入前缀→Enter选类型 | 再输入名字→Enter跳转 | 空输入Backspace返回',
        \             '--delimiter', ':', '--preview-window', '+{2}/2']
        \ }
  call extend(l:opts.options, l:spec.options)
  if a:bang
    let l:opts.fullscreen = 1
  endif
  return fzf#run(fzf#wrap(l:opts))
endfunction

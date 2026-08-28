" miru_snippet.vim — 把光标处的函数体发到 membox miru 网页查看
" 流程: ast-grep 定位函数 → mm doc new 建文档 → 写入 snippet → mm doc view --web 拿 URL
" 依赖: ast-grep CLI、membox 的 mm 二进制、macOS open
" 配置: let g:miru_snippet_mm = '~/repo/membox/bin/mm'   " mm 路径（默认先试 PATH）
"       let g:miru_snippet_auto_open = 0                 " 置 0 只 echo URL 不开浏览器
"
" 注意: 本 vim 构建里 autoload 函数中的 system(List) 会抛 E730（疑似编译 bug），
" 所以下面的 system() 一律用 String + shellescape 形式。job_start(List) 不受影响。

" filetype → ast-grep 语言 + 函数节点 kind
let s:languages = {
      \ 'rust':           {'lang': 'Rust',       'kinds': ['function_item']},
      \ 'go':             {'lang': 'Go',         'kinds': ['function_declaration', 'method_declaration']},
      \ 'python':         {'lang': 'Python',     'kinds': ['function_definition']},
      \ 'c':              {'lang': 'C',          'kinds': ['function_definition']},
      \ 'cpp':            {'lang': 'Cpp',        'kinds': ['function_definition']},
      \ 'javascript':     {'lang': 'JavaScript', 'kinds': ['function_declaration', 'generator_function_declaration', 'method_definition']},
      \ 'typescript':     {'lang': 'TypeScript', 'kinds': ['function_declaration', 'generator_function_declaration', 'method_definition']},
      \ 'typescriptreact': {'lang': 'Tsx',       'kinds': ['function_declaration', 'generator_function_declaration', 'method_definition']},
      \ }

function! s:mm() abort
  let l:custom = get(g:, 'miru_snippet_mm', '')
  if !empty(l:custom) | return expand(l:custom) | endif
  let l:on_path = exepath('mm')
  return empty(l:on_path) ? expand('~/repo/membox/bin/mm') : l:on_path
endfunction

function! s:fail(msg) abort
  echoerr '[miru-snippet] ' . a:msg
endfunction

" 返回包含 cursor 的最小函数节点；光标落在函数上方 ≤5 行的注释/属性上时
" 也算命中（rust 的 doc comment 不在 function_item 节点范围内）
function! s:find_function(matches, cursor0) abort
  let l:best = {}
  let l:below = {}
  for l:m in a:matches
    let l:r = l:m.range
    if l:r.start.line <= a:cursor0 && a:cursor0 <= l:r.end.line
      if empty(l:best) || l:m.charCount < l:best.charCount
        let l:best = l:m
      endif
    elseif 0 <= l:r.start.line - a:cursor0 && l:r.start.line - a:cursor0 <= 5
      if empty(l:below) || l:r.start.line < l:below.range.start.line
        let l:below = l:m
      endif
    endif
  endfor
  return empty(l:best) ? l:below : l:best
endfunction

function! miru_snippet#send() abort
  if !has_key(s:languages, &filetype)
    call s:fail('不支持的 filetype: ' . &filetype . '（可在 autoload 里加映射）')
    return
  endif
  let l:file = expand('%:p')
  if empty(l:file) || !filereadable(l:file)
    call s:fail('当前 buffer 没有已保存的文件')
    return
  endif
  if empty(exepath('ast-grep'))
    call s:fail('找不到 ast-grep CLI')
    return
  endif

  let l:cfg = s:languages[&filetype]
  let l:rule = json_encode({
        \ 'id': 'miru-snippet',
        \ 'language': l:cfg.lang,
        \ 'rule': {'any': map(copy(l:cfg.kinds), '{"kind": v:val}')},
        \ })
  let l:out = system('ast-grep scan --inline-rules ' . shellescape(l:rule) . ' --json ' . shellescape(l:file))
  if v:shell_error != 0
    call s:fail('ast-grep 失败: ' . l:out)
    return
  endif

  let l:fn = s:find_function(json_decode(l:out), line('.') - 1)  " ast-grep 行号 0-based
  if empty(l:fn)
    call s:fail('光标不在任何函数内')
    return
  endif

  let l:start_line = l:fn.range.start.line + 1
  let l:title = strpart(split(l:fn.text, "\n")[0], 0, 60)
  let l:title = fnamemodify(l:file, ':t') . ':' . l:start_line . ' ' . l:title
  let l:md = join([
        \ '# ' . l:title,
        \ '',
        \ '来源: `' . l:file . ':' . l:start_line . '`',
        \ '',
        \ '```' . tolower(l:cfg.lang),
        \ l:fn.text,
        \ '```',
        \ ], "\n")

  let l:mm = shellescape(s:mm())
  let l:res = system(l:mm . ' doc new ' . shellescape(l:title) . ' --no-open --json')
  if v:shell_error != 0
    call s:fail('mm doc new 失败: ' . l:res)
    return
  endif
  let l:doc = json_decode(l:res).document
  call writefile(split(l:md, "\n"), l:doc.path)

  " view --web 会确保 web companion 在跑，--no-open 只打印 URL 让我们自己处理
  let l:served = system(l:mm . ' doc view ' . shellescape(l:doc.id) . ' --web --no-open')
  let l:url = matchstr(l:served, 'https\?://\S\+')
  if empty(l:url)
    call s:fail('没拿到 miru URL: ' . l:served)
    return
  endif
  if get(g:, 'miru_snippet_auto_open', 1)
    call system('open ' . shellescape(l:url))
  endif
  echom '[miru-snippet] ' . l:url
endfunction

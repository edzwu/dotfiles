" autoload/pi_calltree.vim — 核心实现
" 流程: prepareCallHierarchy → 递归 out/incomingCalls → JSON → pi -p 生成 HTML → 本地 HTTP 打开
" 输出: ~/.cache/pi-calltree/*.html，经 python3 -m http.server 以 http://127.0.0.1:8777/<file>.html 访问
" 诊断: 日志文件（默认 /tmp/pi-calltree.log）+ quickfix 进度窗（pi 阶段 3s 心跳）+ 90s LSP watchdog
" 配置: let g:pi_calltree_log = '/tmp/pi-calltree.log'
"       let g:pi_calltree_serve = 0       " 置 0 回退 file:// 打开
"       let g:pi_calltree_port = 8777     " 本地静态服务端口
"       let g:pi_calltree_direction = 'down'  " 默认方向：both(双向)/down(被调用)/up(调用者)

let s:state = {}

function! s:logfile() abort
  return get(g:, 'pi_calltree_log', '/tmp/pi-calltree.log')
endfunction

function! s:log(msg) abort
  call writefile([strftime('%H:%M:%S') . ' ' . a:msg], s:logfile(), 'a')
endfunction

" ---- 进度显示：quickfix 窗口 + echo + 日志 ----
" 每次运行新建一个 qf 列表（action ' '），用户已有的 grep/lsp 列表留在栈里（:colder 可回）
function! s:ui_render(lines) abort
  if !exists('s:qfid') | let s:qfid = 0 | endif
  let l:what = {'title': 'pi-calltree', 'items': map(copy(a:lines), '{"text": v:val}')}
  " 更新本插件的 qf 列表；列表已被清掉（返回 -1）就新建
  if s:qfid == 0 || setqflist([], 'r', extend(copy(l:what), {'id': s:qfid})) == -1
    call setqflist([], ' ', l:what)
    let s:qfid = getqflist({'id': 0}).id
  endif
  " 只在没打开时才 copen（copen 抢焦点，开完马上 wincmd p 退回）
  if getqflist({'id': s:qfid, 'winid': 0}).winid == 0
    botright copen 4
    wincmd p
  endif
endfunction

function! s:progress(msg) abort
  call s:log(a:msg)
  echo '[pi-calltree] ' . a:msg
  if !exists('s:lines') | let s:lines = [] | endif
  call add(s:lines, strftime('%H:%M:%S') . '  ' . a:msg)
  if len(s:lines) > 3
    let s:lines = s:lines[-3:]
  endif
  call s:ui_render(s:lines)
endfunction

function! pi_calltree#complete(A, L, P) abort
  return ['down', 'up', 'both', '2', '3', '4', '5']
endfunction

function! pi_calltree#start(...) abort
  " 参数解析：数字 = depth，down/up/both = 方向（顺序任意）
  let l:depth = 3
  let l:direction = get(g:, 'pi_calltree_direction', 'both')
  for l:arg in a:000
    if l:arg =~# '^\d\+$'
      let l:depth = str2nr(l:arg)
    elseif l:arg =~? '^\(up\|caller\)'
      let l:direction = 'up'
    elseif l:arg =~? '^both'
      let l:direction = 'both'
    elseif l:arg =~? '^\(down\|callee\)'
      let l:direction = 'down'
    endif
  endfor
  call writefile(['=== pi-calltree ' . strftime('%F %T') . ' ==='], s:logfile())
  let s:qfid = 0   " 每次运行用新的 qf 列表，不覆盖上一轮结果
  " 并发守卫：上一个任务还在跑时不覆盖它的 state/pi，避免回调错乱
  if !empty(s:state)
    echoerr '[pi-calltree] 上一次 LSP 查询还在进行中，等进度窗归零再试'
    return
  endif
  if exists('s:pi') && !empty(s:pi)
    echoerr '[pi-calltree] 上一次 pi 生成还在进行中，等它完成再试'
    return
  endif
  if !exists('*lsp#get_allowed_servers')
    call s:fail('需要 vim-lsp')
    return
  endif
  if empty(exepath('pi'))
    call s:fail('找不到 pi CLI（不在 PATH 里）')
    return
  endif
  let l:servers = filter(lsp#get_allowed_servers(), 'lsp#capabilities#has_call_hierarchy_provider(v:val)')
  if empty(l:servers)
    call s:fail('当前 buffer 没有支持 callHierarchy 的 LSP server（rust-analyzer 启动了吗？）')
    return
  endif
  let s:state = {
        \ 'depth': l:depth,
        \ 'direction': l:direction,
        \ 'server': l:servers[0],
        \ 'roots': [],
        \ 'pending': 1,
        \ 'expanded': {},
        \ }
  let l:dir_label = {'down': '下游(被调用)', 'up': '上游(调用者)', 'both': '双向'}[l:direction]
  call s:progress('LSP server: ' . s:state.server . '，depth=' . l:depth . '，方向=' . l:dir_label . '，发送 prepareCallHierarchy')
  call lsp#send_request(s:state.server, {
        \ 'method': 'textDocument/prepareCallHierarchy',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'position': lsp#get_position(),
        \ },
        \ 'on_notification': function('s:on_prepare'),
        \ })
  " watchdog：任何一步挂起都能在 90s 后给出明确错误而不是干等
  call timer_start(90000, function('s:watchdog'))
endfunction

function! s:watchdog(timer) abort
  if empty(s:state) | return | endif
  call s:log('WATCHDOG: 90s 超时，pending=' . s:state.pending . ' —— LSP server 未响应或回调丢失')
  let s:state = {}
  call s:progress('✗ 超时：LSP 90 秒未响应。日志: ' . s:logfile())
  echoerr '[pi-calltree] 超时：LSP 90 秒未响应。日志: ' . s:logfile()
endfunction

function! s:fail(msg) abort
  call s:log('FAIL: ' . a:msg)
  let s:state = {}
  call s:progress('✗ ' . a:msg)
  echoerr '[pi-calltree] ' . a:msg . '（日志: ' . s:logfile() . '）'
endfunction

function! s:new_node(item) abort
  let l:path = lsp#utils#uri_to_path(a:item['uri'])
  return {
        \ 'name': a:item['name'],
        \ 'detail': get(a:item, 'detail', ''),
        \ 'file': fnamemodify(l:path, ':.'),
        \ 'line': a:item['range']['start']['line'] + 1,
        \ 'children': [],
        \ 'parents': [],
        \ '_item': a:item,
        \ '_key': a:item['uri'] . '#' . a:item['range']['start']['line'],
        \ }
endfunction

function! s:on_prepare(data) abort
  if empty(s:state) | return | endif
  let s:state.pending -= 1
  if lsp#client#is_error(a:data['response']) || !has_key(a:data['response'], 'result')
    call s:fail('prepareCallHierarchy 请求失败')
    return
  endif
  let l:items = a:data['response']['result']
  if empty(l:items)
    call s:fail('光标处没有可用的 call hierarchy 项（要在函数名上）')
    return
  endif
  call s:progress('根节点: ' . l:items[0]['name'] . '，开始递归 call hierarchy（' . s:state.direction . '）')
  let l:dirs = s:state.direction ==# 'both' ? ['up', 'down'] : [s:state.direction]
  for l:item in l:items
    let l:node = s:new_node(l:item)
    call add(s:state.roots, l:node)
    for l:d in l:dirs
      call s:fetch(l:node, 1, l:d)
    endfor
  endfor
  call s:maybe_finish()
endfunction

" dir: 'down' = outgoingCalls(被调用), 'up' = incomingCalls(调用者)
function! s:fetch(node, depth, dir) abort
  let l:field = a:dir ==# 'up' ? 'parents' : 'children'
  if a:depth > s:state.depth
    let a:node[l:field] = []
    return
  endif
  " up/down 分开判重：同一函数在调用者树和被调用树里都要能展开
  let l:key = a:dir . '#' . a:node['_key']
  if has_key(s:state.expanded, l:key)
    let a:node[l:field] = []
    let a:node['recursive_' . a:dir] = 1
    return
  endif
  let s:state.expanded[l:key] = 1
  let s:state.pending += 1
  call lsp#send_request(s:state.server, {
        \ 'method': a:dir ==# 'up' ? 'callHierarchy/incomingCalls' : 'callHierarchy/outgoingCalls',
        \ 'params': { 'item': a:node['_item'] },
        \ 'on_notification': function('s:on_calls', [a:node, a:depth, a:dir]),
        \ })
endfunction

function! s:on_calls(node, depth, dir, data) abort
  if empty(s:state) | return | endif
  let s:state.pending -= 1
  let l:field = a:dir ==# 'up' ? 'parents' : 'children'
  let l:label = a:dir ==# 'up' ? 'incomingCalls' : 'outgoingCalls'
  call s:progress('LSP ' . l:label . ': ' . a:node['name'] . '（剩余请求 ' . s:state.pending . '）')
  if !lsp#client#is_error(a:data['response']) && has_key(a:data['response'], 'result')
    let l:calls = a:data['response']['result']
    if type(l:calls) == v:t_list
      let l:seen = {}
      for l:call in l:calls
        " incomingCalls 的对端键是 from，outgoingCalls 是 to
        let l:child = s:new_node(l:call[a:dir ==# 'up' ? 'from' : 'to'])
        " 默认只保留项目内的调用：':.' 化后仍是绝对路径 = 项目外（std/依赖库）
        if get(g:, 'pi_calltree_project_only', 1) && l:child['file'] =~# '^/'
          continue
        endif
        if has_key(l:seen, l:child['_key'])
          continue
        endif
        let l:seen[l:child['_key']] = 1
        call add(a:node[l:field], l:child)
        call s:fetch(l:child, a:depth + 1, a:dir)
      endfor
    endif
  endif
  call s:maybe_finish()
endfunction

" ---- 输出目录 + 本地静态服务（python3 -m http.server，随 vim 退出被杀掉） ----
function! s:outdir() abort
  let l:dir = expand('~/.cache/pi-calltree')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  return l:dir
endfunction

function! s:ensure_server() abort
  if exists('s:server_job') && job_status(s:server_job) ==# 'run'
    return 1
  endif
  let l:port = get(g:, 'pi_calltree_port', 8777)
  let l:job = job_start(['python3', '-m', 'http.server', string(l:port),
        \ '--bind', '127.0.0.1', '--directory', s:outdir()],
        \ {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
  if job_status(l:job) ==# 'run'
    let s:server_job = l:job
    call s:log('HTTP server 已启动: http://127.0.0.1:' . l:port . '/ (root: ' . s:outdir() . ')')
    return 1
  endif
  call s:log('HTTP server 启动失败（端口 ' . l:port . ' 被占？），回退 file://')
  return 0
endfunction

function! s:strip(node) abort
  let l:out = { 'name': a:node['name'], 'detail': a:node['detail'], 'file': a:node['file'], 'line': a:node['line'] }
  if get(a:node, 'recursive_down', 0)
    let l:out['recursive'] = 1
  endif
  if get(a:node, 'recursive_up', 0)
    let l:out['recursive_up'] = 1
  endif
  if !empty(a:node['children'])
    let l:out['children'] = map(copy(a:node['children']), 's:strip(v:val)')
  endif
  if !empty(a:node['parents'])
    let l:out['parents'] = map(copy(a:node['parents']), 's:strip(v:val)')
  endif
  return l:out
endfunction

function! s:maybe_finish() abort
  if empty(s:state) || s:state.pending > 0 | return | endif
  let l:roots = map(copy(s:state.roots), 's:strip(v:val)')
  let l:server = s:state.server
  if len(l:roots) == 1
    let l:tree = l:roots[0]
  else
    let l:tree = { 'name': '(root)', 'detail': '', 'file': '', 'line': 0, 'children': l:roots }
  endif
  let s:state = {}

  let l:base = s:outdir() . '/calltree-' . strftime('%Y%m%d-%H%M%S')
  let l:json_path = l:base . '.json'
  let l:html_path = l:base . '.html'
  let l:template = expand('~/.vim/pi_calltree_template.html')
  call writefile([json_encode(l:tree)], l:json_path)
  call s:log('调用树 JSON 已写入: ' . l:json_path)

  let l:prompt = join([
        \ '请基于调用树 JSON 生成一个交互式 HTML 页面。直接用 read 工具读取文件、write 工具写结果。',
        \ '',
        \ '输入：',
        \ '- 调用树 JSON: ' . l:json_path . ' （schema: {name, detail, file, line, children?, parents?, recursive?, recursive_up?}；children=下游被调用，parents=上游调用者）',
        \ '- HTML 模板: ' . l:template . ' （含占位符 __TITLE__ / __SUBTITLE__ / __TREE_DATA__）',
        \ '',
        \ '要求：',
        \ '1. 将 JSON 转为模板 const DATA 的节点格式 {name, loc, desc, stage, children?}：',
        \ '   - loc = "file:line"；file 为空时省略 loc',
        \ '   - desc = 一句简短中文职责说明（依据 name/detail 推断；拿不准就省略该字段，不要编造）',
        \ '   - recursive 或 recursive_up 为 true 的节点：desc 写 "（递归引用，不再展开）"，不生成下级',
        \ '   - 若根节点同时有 parents 和 children：DATA 根节点的 children 固定为两个分组节点',
        \ '     {"name":"↑ 调用者 callers","desc":"谁调用了它","children":<parents 转换结果>}',
        \ '     和 {"name":"↓ 被调用 callees","desc":"它调用了谁","children":<children 转换结果>}；',
        \ '     parents 子树的每个节点仍按自身 parents 继续向上递归转换',
        \ '   - 只有 parents 没有 children：直接用 parents 作为根节点的 children',
        \ '   - stage：根节点 0；第一层子节点按所属模块分组循环分配 1-5；后代继承同组 stage',
        \ '2. __TITLE__ 替换为 "<根节点 name> · 调用关系树"',
        \ '3. __SUBTITLE__ 替换为 "由 ' . l:server . ' call hierarchy 生成 · 点击节点展开/折叠"',
        \ '4. 将结果写入: ' . l:html_path . ' 。除占位符外不要改动模板。',
        \ '5. 最后只回复一行：输出文件路径。',
        \ ], "\n")

  call s:progress('调用 pi 生成 HTML（通常 10-40 秒）…')
  if exists('*job_start')
    " --mode json：pi 输出 NDJSON 事件流（thinking/text/tool_execution），用于心跳进度
    " 注意：Vim 的 job 选项是 exit_cb / out_cb / err_cb（Neovim 才用 on_exit）
    " in_io null 关键：Vim 默认给 job 一根不关闭的 stdin 管道，pi 会一直等 stdin EOF
    let s:pi = {'start': localtime(), 'tools': 0, 'phase': '启动'}
    let l:job = job_start(['pi', '-p', '--mode', 'json', '--no-session', '--tools', 'read,write', l:prompt], {
          \ 'in_io': 'null',
          \ 'exit_cb': function('s:on_pi_exit', [l:html_path]),
          \ 'out_cb': function('s:on_pi_output', ['stdout']),
          \ 'err_cb': function('s:on_pi_output', ['stderr']),
          \ })
    let s:pi.job = l:job
    call timer_start(3000, function('s:pi_heartbeat'), {'repeat': -1})
  else
    call system(['pi', '-p', '--no-session', '--tools', 'read,write', l:prompt])
    call s:on_pi_exit(l:html_path, 0, v:shell_error)
  endif
endfunction

" ---- pi 阶段心跳：每 3s 刷新一行状态（不计入日志，避免刷屏） ----
function! s:pi_heartbeat(timer) abort
  if !exists('s:pi') || empty(s:pi)
    call timer_stop(a:timer)
    return
  endif
  let l:elapsed = localtime() - s:pi.start
  let l:hint = ''
  if job_status(s:pi.job) !=# 'run'
    let l:hint = '（进程已退出，等待收尾…）'
  elseif l:elapsed > 120
    let l:hint = '（较慢但没卡死，:PiCallTreeLog 看详情）'
  endif
  let l:line = printf('⏳ pi 运行中 %ds · %s · 工具 %d 次%s',
        \ l:elapsed, s:pi.phase, s:pi.tools, l:hint)
  call s:ui_render(get(s:, 'lines', []) + [l:line])
endfunction

function! s:on_pi_output(stream, channel, msg) abort
  if a:stream ==# 'stderr'
    call s:log('pi stderr: ' . a:msg)
    return
  endif
  " stdout 是 --mode json 的 NDJSON 事件流。一次生成有几百行，
  " 99% 是 thinking/text delta——先字符串粗筛，命中才 json_decode
  if !exists('s:pi') || empty(s:pi) | return | endif
  if a:msg !~# '_start\|tool_execution'
    return
  endif
  try
    let l:ev = json_decode(a:msg)
  catch
    return
  endtry
  let l:type = get(l:ev, 'type', '')
  if l:type ==# 'tool_execution_start'
    let s:pi.tools += 1
    let s:pi.phase = '工具: ' . get(l:ev, 'toolName', '?')
    call s:log('pi 工具调用: ' . get(l:ev, 'toolName', '?'))
  elseif l:type ==# 'tool_execution_end'
    let s:pi.phase = get(l:ev, 'isError', v:false) ? '工具出错' : '思考'
  elseif l:type ==# 'message_update'
    let l:sub = get(get(l:ev, 'assistantMessageEvent', {}), 'type', '')
    if l:sub ==# 'thinking_start'
      let s:pi.phase = '思考'
    elseif l:sub ==# 'text_start'
      let s:pi.phase = '生成回复'
    elseif l:sub ==# 'toolcall_start'
      let s:pi.phase = '准备工具调用'
    endif
  endif
endfunction

function! s:on_pi_exit(html_path, job, status) abort
  " 防御：autoload 热加载/回调参数异常时强制转类型，避免 E730
  let l:path = type(a:html_path) == v:t_list ? get(a:html_path, 0, '') : a:html_path
  let l:status = type(a:status) == v:t_number ? a:status : -1
  let s:pi = {}   " 停掉心跳 timer（下一轮自己 timer_stop）
  call s:log('pi 退出，status=' . l:status)
  let s:lines = []   " 清空过程行，只留结果行；窗口不关，:cclose 手动关
  if l:status == 0 && filereadable(l:path)
    let l:url = 'file://' . l:path
    if get(g:, 'pi_calltree_serve', 1) && !empty(exepath('python3')) && s:ensure_server()
      let l:url = 'http://127.0.0.1:' . get(g:, 'pi_calltree_port', 8777) . '/' . fnamemodify(l:path, ':t')
    endif
    call s:log('HTML: ' . l:url)
    " 留在底部窗口（可用 gx 打开），同时 echom 到消息区（终端 Ctrl/Cmd+点击）
    call s:progress('✓ ' . l:url . '  (gx 打开，:cclose 关闭)')
    echom '[pi-calltree] ' . l:url
    if get(g:, 'pi_calltree_auto_open', 0)
      call system(['open', l:path])
    endif
  else
    call s:progress('✗ pi 生成失败 (exit ' . l:status . ')。日志: ' . s:logfile())
    echoerr '[pi-calltree] pi 生成失败 (exit ' . l:status . ')。日志: ' . s:logfile()
  endif
endfunction

function! pi_calltree#open_log() abort
  execute 'tabnew ' . fnameescape(s:logfile())
endfunction

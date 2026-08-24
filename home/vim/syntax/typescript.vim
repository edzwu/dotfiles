" Lightweight TypeScript syntax.
"
" Vim 9.1's built-in TypeScript syntax is based on yats and can hit
" 'redrawtime' exceeded while scrolling some files. Keep this intentionally
" small so redraw stays predictable.
if exists('b:current_syntax')
  finish
endif

syntax case match
syntax sync minlines=8 maxlines=40
setlocal regexpengine=1

syntax keyword typescriptLightKeyword
      \ as async await break case catch class const continue debugger declare default
      \ delete do else enum export extends finally for from function get if implements
      \ import in infer interface instanceof is keyof let module namespace new of
      \ private protected public readonly return satisfies set static switch this
      \ throw try type typeof var void while with yield

syntax keyword typescriptLightType
      \ any bigint boolean false never null number object string symbol true undefined
      \ unknown

syntax keyword typescriptLightTodo TODO FIXME XXX NOTE contained
syntax match typescriptLightLineComment +//.*$+ contains=typescriptLightTodo
syntax region typescriptLightBlockComment start="/\*" end="\*/" contains=typescriptLightTodo keepend

syntax region typescriptLightString start=+"+ skip=+\\\\\|\\"+ end=+"+ oneline
syntax region typescriptLightString start=+'+ skip=+\\\\\|\\'+ end=+'+ oneline
" 模板字符串支持多行(TS 中常见);未闭合时延伸到文件尾属正常语法行为
syntax region typescriptLightTemplate start=+`+ skip=+\\\\\|\\`+ end=+`+
syntax match typescriptLightNumber "\v<\d+(\.\d+)?([eE][+-]?\d+)?>"
syntax match typescriptLightOperator "=>\|[?:=+\-*/%<>!&|]\+"

" Cheap brace-block folding so foldmethod=syntax works (zM/zR).
" 注意: transparent 区域的 contains 必须显式列出所有高亮组 + 自身(嵌套),
" 否则 {} 内部的所有高亮都会被吞掉(之前的 bug: 只 contains 自身)
syntax cluster typescriptLightTop contains=typescriptLightKeyword,typescriptLightType,typescriptLightTodo,typescriptLightLineComment,typescriptLightBlockComment,typescriptLightString,typescriptLightTemplate,typescriptLightNumber,typescriptLightOperator
syntax region typescriptLightBlock start="{" end="}" transparent fold contains=@typescriptLightTop,typescriptLightBlock

highlight default link typescriptLightKeyword Keyword
highlight default link typescriptLightType Type
highlight default link typescriptLightTodo Todo
highlight default link typescriptLightLineComment Comment
highlight default link typescriptLightBlockComment Comment
highlight default link typescriptLightString String
highlight default link typescriptLightTemplate String
highlight default link typescriptLightNumber Number
highlight default link typescriptLightOperator Operator

let b:current_syntax = 'typescript_light'

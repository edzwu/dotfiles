#!/usr/bin/env bash
# astgrep_reload.sh — \g 搜索窗口的 reload 命令
# 用法: astgrep_reload.sh <Lang> "<query>"
#   query 由 fzf 的 {q} 传入(已被 fzf 单引号转义,含 $/空格安全)
#   输入模式:
#     直接输入     → ast-grep AST 搜索(名字或 pattern)
#     k:           → 显示该语言全部 kind 候选(渐进披露)
#     k:f / k:fn   → 按前缀逐步收窄 kind 候选
#     候选上 Enter → 隐藏 kind 状态并清空输入框,进入名字搜索阶段
#     名字阶段     → 一次加载该 kind 的结果,由 fzf 本地渐进过滤名字
#     k:<ESQuery>  → 组合选择器,如 k:call_expression > identifier
#     r:<text>     → rg 文本搜索(正则),如 r:DetectionConfig
#   空输入 → 模式库模板(格式: <pattern|k:kind> <TAB> <说明>)
#   模板/候选行(含 TAB)由 fzf transform 在同一窗口内切换状态
set -u

TAB="$(printf '\t')"

# fzf 会话模式。kind 选择后的类型保存在临时状态文件中,
# 第二阶段输入框只显示名字,不暴露内部的 k:fn 前缀。
case "${1:-}" in
  enter)
    lang="$2"
    state_file="$3"
    line="${4:-}"
    line="$(printf '%s' "$line" | sed $'s/\x1b\\[[0-9;]*m//g')"
    case "$line" in
      *"$TAB"*)
        pat="${line%%"$TAB"*}"
        case "$pat" in
          k:*)
            kind="${pat#k:}"
            printf 'kind:%s' "$kind" > "$state_file"
            # 第一阶段依赖 change:reload;进入名字阶段后解绑 change,
            # 一次加载全部节点并启用 fzf 本地过滤,避免每个字符重跑 ast-grep。
            printf -v reload_cmd 'bash %q reload %q %q %q' "$0" "$lang" "$state_file" ''
            printf 'unbind(change)+clear-query+enable-search+reload(%s)+change-prompt:%s name> ' \
              "$reload_cmd" "$kind"
            ;;
          *) printf 'change-query:%s' "$pat" ;;
        esac
        ;;
      *) echo 'accept' ;;
    esac
    exit 0
    ;;
  prompt)
    state_file="$2"
    q="${3:-}"
    state="$(cat "$state_file" 2>/dev/null || printf 'ast')"
    case "$state" in
      kind:*) printf '%s name> ' "${state#kind:}" ;;
      *)
        case "$q" in
          k:*) printf 'Kind> ' ;;
          r:*) printf 'Rg> ' ;;
          *)   printf 'AST> ' ;;
        esac
        ;;
    esac
    exit 0
    ;;
  backspace)
    state_file="$2"
    q="${3:-}"
    state="$(cat "$state_file" 2>/dev/null || printf 'ast')"
    if [[ "$state" == kind:* && -z "$q" ]]; then
      printf 'ast' > "$state_file"
      echo 'disable-search+rebind(change)+change-query:k:+change-prompt:Kind> '
    else
      echo 'backward-delete-char'
    fi
    exit 0
    ;;
  abort)
    rm -f -- "$2"
    echo 'abort'
    exit 0
    ;;
  reload)
    lang="$2"
    state_file="$3"
    q="${4:-}"
    state="$(cat "$state_file" 2>/dev/null || printf 'ast')"
    ;;
  *)
    # 兼容直接调用:astgrep_reload.sh <Lang> <query>
    lang="$1"
    q="${2:-}"
    state='ast'
    ;;
esac

q="${q%%$'\t'*}"
if [[ "$state" == kind:* ]]; then
  q="k:${state#kind:} $q"
fi

# 颜色(fzf --ansi 渲染;vim sink 收到原始行时会 strip)
C_KD=$'\e[36m'    # 青色: pattern/kind 名
C_DIM=$'\e[2m'    # 暗灰: 说明文字
C_HDR=$'\e[2;3m'  # 暗灰斜体: 分组标题
C_RST=$'\e[0m'

# ---- 各语言的 kind 候选列表(模板库 + k: 渐进披露共用) ----
# 候选以别名为主展示(好记好输),说明里注完整 kind 名
# 参数 plain: 输出无色版(候选模式,避免 ANSI 干扰匹配)
kind_lines() {
  if [ "${1:-}" = "plain" ]; then
    local C_KD='' C_DIM='' C_HDR='' C_RST=''
  fi
  case "$lang" in
    Rust)
      printf '%s\n' \
        "${C_KD}k:fn${C_RST}${TAB}${C_DIM}函数定义,含 impl 方法(function_item)${C_RST}" \
        "${C_KD}k:struct${C_RST}${TAB}${C_DIM}struct 定义(struct_item)${C_RST}" \
        "${C_KD}k:enum${C_RST}${TAB}${C_DIM}enum 定义(enum_item)${C_RST}" \
        "${C_KD}k:trait${C_RST}${TAB}${C_DIM}trait 定义(trait_item)${C_RST}" \
        "${C_KD}k:impl${C_RST}${TAB}${C_DIM}impl 块(impl_item)${C_RST}" \
        "${C_KD}k:match${C_RST}${TAB}${C_DIM}match 表达式(match_expression)${C_RST}" \
        "${C_KD}k:if${C_RST}${TAB}${C_DIM}if 表达式(if_expression)${C_RST}" \
        "${C_KD}k:for${C_RST}${TAB}${C_DIM}for 循环(for_expression)${C_RST}" \
        "${C_KD}k:call${C_RST}${TAB}${C_DIM}函数/方法调用(call_expression)${C_RST}" \
        "${C_KD}k:macro${C_RST}${TAB}${C_DIM}宏调用(macro_invocation)${C_RST}" \
        "${C_KD}k:let${C_RST}${TAB}${C_DIM}let 绑定(let_declaration)${C_RST}" \
        "${C_KD}k:comment${C_RST}${TAB}${C_DIM}注释(line_comment + block_comment)${C_RST}" \
        ;;
    Go)
      printf '%s\n' \
        "${C_KD}k:fn${C_RST}${TAB}${C_DIM}函数定义(function_declaration)${C_RST}" \
        "${C_KD}k:method${C_RST}${TAB}${C_DIM}方法定义(method_declaration)${C_RST}" \
        "${C_KD}k:type${C_RST}${TAB}${C_DIM}类型声明(type_declaration)${C_RST}" \
        "${C_KD}k:if${C_RST}${TAB}${C_DIM}if 语句(if_statement)${C_RST}" \
        "${C_KD}k:for${C_RST}${TAB}${C_DIM}for 语句(for_statement)${C_RST}" \
        "${C_KD}k:call${C_RST}${TAB}${C_DIM}函数调用(call_expression)${C_RST}" \
        "${C_KD}k:comment${C_RST}${TAB}${C_DIM}注释(comment)${C_RST}" \
        ;;
    Python)
      printf '%s\n' \
        "${C_KD}k:fn${C_RST}${TAB}${C_DIM}函数定义(function_definition)${C_RST}" \
        "${C_KD}k:class${C_RST}${TAB}${C_DIM}class 定义(class_definition)${C_RST}" \
        "${C_KD}k:call${C_RST}${TAB}${C_DIM}函数调用(call)${C_RST}" \
        "${C_KD}k:if${C_RST}${TAB}${C_DIM}if 语句(if_statement)${C_RST}" \
        "${C_KD}k:comment${C_RST}${TAB}${C_DIM}注释(comment)${C_RST}" \
        ;;
    JavaScript|TypeScript|Tsx)
      printf '%s\n' \
        "${C_KD}k:fn${C_RST}${TAB}${C_DIM}函数定义(function_declaration)${C_RST}" \
        "${C_KD}k:method${C_RST}${TAB}${C_DIM}方法定义(method_definition)${C_RST}" \
        "${C_KD}k:class${C_RST}${TAB}${C_DIM}class 定义(class_declaration)${C_RST}" \
        "${C_KD}k:call${C_RST}${TAB}${C_DIM}调用(call_expression)${C_RST}" \
        "${C_KD}k:if${C_RST}${TAB}${C_DIM}if 语句(if_statement)${C_RST}" \
        "${C_KD}k:comment${C_RST}${TAB}${C_DIM}注释(comment)${C_RST}" \
        ;;
    *) : ;;
  esac
}

# ---- 判断单 token 是否为已知别名或完整 kind 名 ----
# (已不需要:候选模式统一前缀过滤,无需判断已知)

# 模板/候选行输出辅助:tpl <pattern> <说明>; hdr <分组标题>
tpl() { printf '%s\n' "${C_KD}$1${C_RST}${TAB}${C_DIM}$2${C_RST}"; }
hdr() { printf '%s\n' "${C_HDR}── $1 ──${C_RST}"; }

# ---- 空输入:模式库模板 ----
if [ -z "$q" ]; then
  case "$lang" in
    Rust)
      hdr '模式'
      tpl 'pub struct $NAME { $$$ }' 'struct 定义'
      tpl 'enum $NAME { $$$ }' 'enum 定义'
      tpl 'trait $NAME { $$$ }' 'trait 定义'
      tpl 'impl $NAME { $$$ }' 'impl 块'
      tpl 'fn $NAME($$$)' '函数定义'
      tpl 'pub fn $NAME($$$) -> Result<$$$>' '返回 Result 的 pub fn'
      tpl 'fn $NAME(&self, $$$)' '方法定义'
      tpl 'match $E { $$$ }' 'match 表达式'
      tpl 'if $A && $B { $$$ }' '二元条件 if'
      tpl 'if let $A = $B { $$$ }' 'if-let'
      tpl 'for $A in $B { $$$ }' 'for 循环'
      tpl 'let $A = $B;' 'let 绑定'
      tpl '$A.unwrap()' 'unwrap() 调用(潜在 panic)'
      tpl '$A.clone()' 'clone() 调用'
      tpl '$A::default()' '任意类型 default() 调用'
      tpl '$A::new($$$)' '任意类型 new() 调用'
      tpl 'Some($A)' 'Some() 构造'
      ;;
    Go)
      hdr '模式'
      tpl 'type $NAME struct { $$$ }' 'struct 定义'
      tpl 'type $NAME interface { $$$ }' 'interface 定义'
      tpl 'func $NAME($$$)' '函数定义'
      tpl 'func ($R $T) $NAME($$$)' '方法定义'
      tpl 'func $NAME($$$) error' '返回 error 的函数'
      tpl 'if $A != nil { $$$ }' 'nil 检查'
      tpl 'for $A := range $B { $$$ }' 'for-range'
      tpl 'switch $A { $$$ }' 'switch'
      ;;
    Python)
      hdr '模式'
      tpl 'class $NAME: $$$' 'class 定义'
      tpl 'def $NAME($$$):' '函数定义'
      tpl 'def $NAME(self, $$$):' '方法定义'
      tpl 'async def $NAME($$$):' 'async 函数'
      tpl 'if $A is None:' 'None 检查'
      tpl 'for $A in $B:' 'for 循环'
      tpl 'with $A as $B:' 'with 上下文'
      tpl 'try: $$$' 'try 块'
      ;;
    JavaScript|TypeScript|Tsx)
      hdr '模式'
      tpl 'function $NAME($$$) { $$$ }' '函数定义'
      tpl 'class $NAME { $$$ }' 'class 定义'
      tpl 'const $NAME = ($$$) => { $$$ }' '箭头函数'
      tpl 'if ($A) { $$$ }' 'if'
      tpl 'for (const $A of $B) { $$$ }' 'for-of'
      tpl 'try { $$$ } catch ($E) { $$$ }' 'try-catch'
      tpl '$A.map($$$)' 'map 调用'
      tpl '$A.filter($$$)' 'filter 调用'
      ;;
    *)
      printf '%s\n' \
        "function/class/struct 定义: 输入对应语言的关键字 + { \$\$\$ }" \
        "k:<kind>  只按节点类型搜,如 k:function_item" \
        "\$A 匹配任意单个节点,\$\$\$ 匹配零到多个节点" \
        "提示: 也可以直接输入标识符(如 DetectionConfig)按文本方式匹配" \
        ;;
  esac
  kl="$(kind_lines)"
  if [ -n "$kl" ]; then
    hdr 'kind(节点类型)'
    printf '%s\n' "$kl"
  fi
  exit 0
fi

# ---- k: 节点类型搜索 ----
if [ "${q#k:}" != "$q" ]; then
  rest="${q#k:}"

  # 候选模式(渐进披露):无空格的单 token → 按前缀过滤别名候选
  #   k:        → 全部候选
  #   k:f       → k:fn / k:for
  #   k:fn      → 只剩 k:fn(Enter 确认进入该类型搜索)
  if [[ "$rest" != *[[:space:]]* ]]; then
    if [ -z "$rest" ]; then
      kind_lines plain
    else
      kind_lines plain | grep -i "^k:$rest"
    fi
    exit 0
  fi

  # 执行模式(含空格):
  #   k:fn␣                       → 该类型全部节点(定义行)
  #   k:fn detect_from_document   → 名字过滤(子串)
  #   k:call_expression > identifier → ESQuery 组合(整体当 kind)
  if [[ "$rest" =~ ^([^[:space:]]+)[[:space:]]+$ ]]; then
    kind_part="${BASH_REMATCH[1]}"
    name_part=""
  elif [[ "$rest" =~ ^([^[:space:]]+)[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*$ ]]; then
    kind_part="${BASH_REMATCH[1]}"
    name_part="${BASH_REMATCH[2]}"
  else
    kind_part="$rest"
    name_part=""
  fi

  # 别名 → kind 列表(按语言;非别名原样作为完整 kind 名/ESQuery)
  kinds=""
  case "$lang:$kind_part" in
    Rust:fn)      kinds="function_item function_signature_item" ;;
    Rust:struct)  kinds="struct_item" ;;
    Rust:enum)    kinds="enum_item" ;;
    Rust:trait)   kinds="trait_item" ;;
    Rust:impl)    kinds="impl_item" ;;
    Rust:match)   kinds="match_expression" ;;
    Rust:if)      kinds="if_expression" ;;
    Rust:for)     kinds="for_expression" ;;
    Rust:call)    kinds="call_expression" ;;
    Rust:macro)   kinds="macro_invocation" ;;
    Rust:let)     kinds="let_declaration" ;;
    Rust:comment) kinds="line_comment block_comment" ;;
    Go:fn)        kinds="function_declaration" ;;
    Go:method)    kinds="method_declaration" ;;
    Go:type)      kinds="type_declaration" ;;
    Go:if)        kinds="if_statement" ;;
    Go:for)       kinds="for_statement" ;;
    Go:call)      kinds="call_expression" ;;
    Python:fn)    kinds="function_definition" ;;
    Python:class) kinds="class_definition" ;;
    Python:call)  kinds="call" ;;
    Python:if)    kinds="if_statement" ;;
    JavaScript:fn|TypeScript:fn|Tsx:fn)       kinds="function_declaration" ;;
    JavaScript:method|TypeScript:method|Tsx:method) kinds="method_definition" ;;
    JavaScript:class|TypeScript:class|Tsx:class)    kinds="class_declaration" ;;
    JavaScript:call|TypeScript:call|Tsx:call)       kinds="call_expression" ;;
    JavaScript:if|TypeScript:if|Tsx:if)             kinds="if_statement" ;;
    *)            kinds="$kind_part" ;;
  esac

  # kind 输出整个节点文本(多行),走 --json 取每个节点首行(定义行)输出,
  # 保证 fzf 列表每行跳转到节点起始行;name_part 非空时按首行子串过滤。
  for k in $kinds; do
    ast-grep run -l "$lang" --kind "$k" --json . 2>/dev/null | python3 -c "
import json,sys
name=sys.argv[1]
try: data=json.load(sys.stdin)
except Exception: sys.exit(0)
out=[]
for m in data:
    fl=m['text'].split('\\n',1)[0]
    if not name or name in fl:
        out.append('%s:%d:%s'%(m['file'],m['range']['start']['line']+1,fl))
if out:
    try: print('\\n'.join(out))
    except BrokenPipeError: pass
" "$name_part"
  done
  exit 0
fi

# ---- r: rg 文本搜索 ----
if [ "${q#r:}" != "$q" ]; then
  # 不带 --color,保持纯文本供 sink 解析
  rg --column --line-number --no-heading --smart-case --hidden \
     --glob '!{.git,node_modules}/*' -- "${q#r:}" 2>/dev/null
  exit 0
fi

# ---- 默认:ast-grep pattern 搜索 ----
ast-grep run -l "$lang" -p "$q" 2>/dev/null

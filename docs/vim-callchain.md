# Vim 追调用链优化方案(汇总)

> 基于 2026-08 的调查:gtags 对 TS 的支持修复 + quickfix 体验优化。
> 分层结构:第 0 层是基础盘,越往上越可选。

## 背景

- gtags 已修复:`GTAGSLABEL` 切回 `native-pygments`(内置 C 系解析 + pygments 兜底 TS/JS),
  `~/.global` 恢复为指向 `home/global` 的软链接。TS 的定义/符号/调用点查询(`\cg`/`\cs`/`\cc`)复活。
- TS 调用链仍以 LSP 为主:`\lr`(references,类型精确)。
- 痛点:gtags/cscope 结果进 quickfix 后,反复"跳转→回退→再查",体验粗糙。
  整个优化系列围绕 **quickfix 体验** 展开。

## 第 0 层:纯 vimrc,零依赖(基础盘)

```vim
" quickfix 快速导航
nnoremap ]q :cnext<CR>
nnoremap [q :cprev<CR>
nnoremap ]Q :clast<CR>
nnoremap [Q :cfirst<CR>
nnoremap <leader>q :copen<CR>
nnoremap <leader>Q :cclose<CR>
" 有结果才自动弹 quickfix
autocmd QuickFixCmdPost * cwindow
" quickfix 历史(vim 8+ 原生 colder/cnewer,无需插件):
" \cc 覆盖结果后仍能翻回上一次查询
nnoremap <leader>qh :colder<CR>
nnoremap <leader>qH :cnewer<CR>
```

## 第 1 层:quickfix 预览(核心体验)

**决策:先用 vim-preview 试**(已停止维护,但纯 VimScript、零依赖、够用);
体验不佳则换 vim-quickui,键位无缝迁移(见下)。

```vim
Plug 'skywind3000/vim-preview'

" ===== vim-preview: quickfix 预览 & 标签预览 =====
" quickfix 窗口: p 预览当前项, P 关闭预览, Enter 正常跳转
autocmd FileType qf nnoremap <silent><buffer> p :PreviewQuickfix<cr>
autocmd FileType qf nnoremap <silent><buffer> P :PreviewClose<cr>
" F3: 循环预览光标下符号的定义(重载/多文件同名时反复按)
noremap <F3> :PreviewTag<cr>
" F4: 命令栏显示最近函数签名(插入模式可用,不用离开 insert)
noremap <F4> :PreviewSignature!<cr>
inoremap <F4> <c-\><c-o>:PreviewSignature!<cr>
" Alt+U/D: 滚动预览窗口,不离开当前窗口(需终端 Option 当 Meta)
noremap <m-u> :PreviewScroll -1<cr>
noremap <m-d> :PreviewScroll +1<cr>
```

**替换方案(vim-quickui)**:`Plug 'skywind3000/vim-quickui'`,
qf 窗口 `p` 改为 `:call quickui#tools#preview_quickfix()<CR>`,其余键位不变。

## 第 2 层:标签预览增强(可选)

PreviewTag/PreviewSignature 依赖 ctags 的行号和签名字段:

```vim
let g:gutentags_ctags_extra_args = ['--fields=+nS']   " 原为 +S
```

注意:对已有 `~/.cache/tags/*-tags` 缓存不生效,需重新生成
(`:GutentagsUpdate` 或删 `*-tags` 目录)。不影响第 1 层主流程。

## 第 3 层:fzf 兜底进 quickfix(可选)

```vim
nnoremap <leader>G :Rg!<Space>   " 结果直接进 quickfix,配合 p 预览 + ]q 扫描
```

## 键位速查

| 键位 | 功能 | 归属 |
|---|---|---|
| `\cc` / `\cd` | cscope 谁调用了它 / 它调用了谁 | gutentags_plus |
| `\cg` / `\cs` | 定义 / 符号引用 | gutentags_plus |
| `\lr` | LSP 精确引用(TS 调用链主力) | vim-lsp |
| `]q` `[q` `]Q` `[Q` | quickfix 上下/首尾 | 第 0 层 |
| `\q` / `\Q` | 开/关 quickfix | 第 0 层 |
| `\qh` / `\qH` | quickfix 历史回溯/前进 | 第 0 层 |
| `p` / `P`(qf 窗口内) | 预览当前项 / 关预览 | 第 1 层 |
| `F3` / `F4` | 循环预览定义 / 函数签名 | 第 1 层 |
| `Alt+U/D` | 滚动预览窗口 | 第 1 层 |
| `\G` | Rg 结果进 quickfix | 第 3 层 |

## 测试清单

1. 打开任意项目,光标停函数上 `\cc` → quickfix 弹出 → `p` 预览 → 移动光标再 `p` → `Enter` 跳转 → `<C-w>z` 关预览
2. 光标停函数名 `F3` 循环预览定义
3. 插入模式输入 `funcName(` 后 `F4` 看签名
4. `\cc` 连续查两个符号后,`\qh` 翻回第一个结果

## 回滚

- 第 1 层:删 Plug 行 + 键位块,`:PlugClean` 清插件
- 第 0/2/3 层:删对应配置即可,无副作用

## 实施状态

- [x] gtags 修复:GTAGSLABEL → native-pygments(vimrc + profile.d + gtags.conf + 缓存清理 + 软链接恢复)
- [ ] 第 0 层(建议)
- [ ] 第 1 层 vim-preview(建议,先试)
- [ ] 第 2 层(可选)
- [ ] 第 3 层(可选)

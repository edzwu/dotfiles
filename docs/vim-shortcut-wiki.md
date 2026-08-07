# Vim Shortcut Wiki

> Leader = `\`（backslash）

## LSP 代码导航（vim-lsp + clangd / pyright / gopls）

| 快捷键 | 功能 |
|--------|------|
| `\lr` | **Find References** — 找所有使用处 |
| `\ld` | Go to Definition — 跳定义 |
| `\li` | Go to Implementation — 跳实现（虚函数/接口） |
| `\ly` | Type Definition — 跳类型定义 |
| `\lh` | Hover — 显示签名/文档 |
| `\ln` | Rename — 重命名 |
| `\la` | Code Action |
| `\lc` | Call Hierarchy Incoming — 谁调了我 |
| `\lC` | Call Hierarchy Outgoing — 我调了谁 |
| `\ls` | Document Symbol — 当前文件符号大纲 |
| `\lt` | LSP Toggle — 开关 LSP 服务 |
| `Ctrl+]` | 跳定义（tagfunc，LSP 优先，fallback ctags） |
| `[g` | 上一个诊断（错误/警告） |
| `]g` | 下一个诊断 |

## gtags 代码导航（gutentags + gutentags_plus）

| 快捷键 | 功能 |
|--------|------|
| `\cs` | **Symbol / References** — 找所有使用处 |
| `\cg` | Definition — 跳定义 |
| `\cc` | Callers — 谁调了我 |
| `\cd` | Called functions — 我调了谁 |
| `\ct` | Text search — 文本搜索 |
| `\ce` | Egrep — 正则搜索 |
| `\cf` | File — 文件搜索 |
| `\ci` | Include — 谁 include 了某文件 |
| `\ca` | Assignment — 赋值处 |
| `\cz` | Ctag — ctags 定义 |
| `\ck` | Kill — 断开 gtags 连接 |
| `:GtagsRebuild` | 强制重建 gtags 数据库 |

## 搜索 / 文件

| 快捷键 | 功能 |
|--------|------|
| `\g` | Rg 全局搜索（输入模式） |
| `Ctrl+p` | fzf 文件搜索 |
| `\o` | fzf History（最近文件） |
| `Space e` | 打开文件（带补全） |

## 文件树 / 窗口

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+n` | NERDTree 开关 |
| `\n` | NERDTree 定位当前文件 |
| `\m` | 窗口最大化切换 |
| `F8` | Tagbar 符号侧栏 |
| `F12` | 透明背景切换 |

## 高亮 / 标记

| 快捷键 | 功能 |
|--------|------|
| `hh` | 高亮光标处单词（带计数统计） |
| `hx` | 清除所有手动高亮 |
| `hc` | 显示当前高亮索引 |
| `hj` / `hk` | 跳到下/上一个高亮位置 |
| `hg` | 按索引跳转到指定高亮 |

## 编辑 / 杂项

| 快捷键 | 功能 |
|--------|------|
| `\yp` | 复制当前文件完整路径 |
| `\yf` | 复制当前文件名 |
| `\x` | 插入 inbox 标记（normal/insert 均可） |
| `\i` | 打开 inbox 浮动终端 |
| `\I` | 切换 inbox 浮动终端 |
| `F5` | 插入当前时间戳（insert 模式） |
| `\rfs` | Rg 跨文件替换 |
| `\rf` | Rg 当前 buffer 替换 |
| `\mt` | 移动到第 3 行 |
| `\m0` | 移动到第 1 行 |
| `\mb` | 移动到最后一行 |

## C++ 代码阅读典型流程

```
1. \cs 或 \lr    → 找"谁用了这个类/函数"（结果进 quickfix）
2. \cg 或 \ld    → 跳到定义
3. Ctrl+]        → 快速跳转（LSP 优先）
4. Ctrl+o        → 跳回
5. \cc 或 \lc    → 看调用链
6. :copen        → 打开 quickfix 列表浏览结果
7. :cn / :cp     → 下/上一个结果
```

## LSP vs gtags 选择

| 场景 | 用 LSP (`\l*`) | 用 gtags (`\c*`) |
|------|----------------|------------------|
| 有 `compile_commands.json` | ✅ 语义精确 | ✅ 也行 |
| 无编译数据库 | ⚠️ 使用 fallback flags，精度下降 | ✅ 开箱即用 |
| 模板/重载/虚函数 | ✅ 理解语义 | ⚠️ 按符号匹配 |
| 宏展开后的名字 | ⚠️ 可能找不到 | ✅ `\ct` 文本搜索可命中 |
| 跨语言（C++ + Python 混合） | ✅ 各语言 server 分别处理 | ❌ builtin parser 不支持 Python |

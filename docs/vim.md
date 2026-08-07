 你的传统 Vim 配置内容（确实很复杂）

  home/vimrc + home/vim/ 包含：

   模块          文件                       说明
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   插件管理      autoload/plug.vim          vim-plug（完整拷贝）
   终端浮动窗    autoload/zw/floaterm.vim   Floaterm 快捷键封装
   RG 搜索替换   autoload/zw/rg.vim         跨文件搜索+交互式替换
   透明背景      autoload/transparent.vim   F12 切换透明
   专注计时器    plugin/focus_task.vim      Airline 集成的番茄钟
   Inbox 笔记    plugin/inbox_float.vim     <leader>i 打开 inbox.md
   行移动        plugin/line_move.vim       <leader>mt/mb/m0
   透明切换      plugin/transparent.vim     F12 绑定
   插件列表      vimrc                      vim-plug 声明了 ~20 个插件（fzf、nerdtree、gutentags、airline 等）
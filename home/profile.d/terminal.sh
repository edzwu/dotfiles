# Terminal tweaks
# 禁用终端 XOFF 流控(Ctrl+S/Ctrl+Q 冻结/解冻),把这两个键留给程序使用
# 只在交互式终端下执行,避免影响脚本/管道

if [ -t 0 ]; then
  stty -ixon
fi

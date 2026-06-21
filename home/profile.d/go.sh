# Go configuration
# 用户级安装到 ~/.local/go

if [ -d "$HOME/.local/go/bin" ]; then
  export PATH="$HOME/.local/go/bin:$PATH"
fi

# Go tools installed via `go install` (default GOPATH ~/go/bin)
if [ -d "$HOME/go/bin" ]; then
  export PATH="$HOME/go/bin:$PATH"
fi

# 国内镜像：解决 go mod tidy / go build 访问官方源超时/卡死
export GOPROXY=https://goproxy.cn,https://goproxy.io,direct
export GOSUMDB=sum.golang.google.cn

# 私有模块（按需修改），不走代理、不校验 checksum
# export GOPRIVATE=*.example.com,github.com/myorg

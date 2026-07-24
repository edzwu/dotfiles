#!/usr/bin/env bash
# =============================================================================
# App: Go
# =============================================================================
# 安装用户级 Go（~/.local/go），通过 profile.d 注入 PATH。
# =============================================================================

APP_NAME="go"
APP_DESC="The Go programming language"
APP_DEPS=()

# 不通过包管理器安装，而是下载官方 release tarball
# APP_BREW_FORMULA="go"
# APP_APT_PACKAGE="golang-go"

GO_VERSION="${GO_VERSION:-1.26.5}"
MIN_GO_VERSION="${MIN_GO_VERSION:-1.25.0}"

_go_bin() {
  command -v go 2>/dev/null || true
}

_get_go_version() {
  if has_cmd go; then
    go version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
  else
    echo "0.0.0"
  fi
}

_version_ge() {
  [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" == "$2" ]]
}

_go_platform_suffix() {
  local os="${DETECTED_OS:-linux}"
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
  esac
  echo "${os}-${arch}"
}

app_install() {
  local current_version
  current_version="$(_get_go_version)"

  if _version_ge "$current_version" "$MIN_GO_VERSION"; then
    log_info "  Already installed: Go $current_version (>= $MIN_GO_VERSION)"
    return 0
  fi

  if [[ "$current_version" != "0.0.0" ]]; then
    log_warn "  Go $current_version is too old (need >= $MIN_GO_VERSION), upgrading..."
  else
    log "  Installing Go $GO_VERSION to ~/.local/go..."
  fi

  local suffix
  suffix="$(_go_platform_suffix)"
  local go_tar="go${GO_VERSION}.${suffix}.tar.gz"
  local go_url="https://mirrors.aliyun.com/golang/${go_tar}"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  log "    Downloading ${go_tar}..."
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "    [dry-run] Would download: $go_url"
    rm -rf "$tmp_dir"
    return 0
  fi

  if ! curl -fsL -A "Mozilla/5.0" --retry 3 --retry-delay 2 \
       -o "${tmp_dir}/${go_tar}" "$go_url" 2>/dev/null; then
    rm -rf "$tmp_dir"
    die "Failed to download Go from $go_url"
  fi

  local file_size
  file_size="$(stat -c%s "${tmp_dir}/${go_tar}" 2>/dev/null || stat -f%z "${tmp_dir}/${go_tar}" 2>/dev/null || echo 0)"
  if [[ "$file_size" -lt 10000000 ]]; then
    rm -rf "$tmp_dir"
    die "Downloaded Go tarball is too small (${file_size} bytes)"
  fi

  log "    Extracting to ~/.local/go..."
  rm -rf "$HOME/.local/go"
  ensure_dir "$HOME/.local"
  tar -C "$HOME/.local" -xzf "${tmp_dir}/${go_tar}"
  rm -rf "$tmp_dir"

  export PATH="$HOME/.local/go/bin:$PATH"
  log_success "  Go $(_get_go_version): installed"
}

app_configure() {
  local profile_src="$DOTFILES/home/profile.d/go.sh"
  if [[ -f "$profile_src" ]]; then
    ensure_dir "$HOME/.profile.d"
    link_file "$profile_src" "$HOME/.profile.d/go.sh"
  fi
}

app_post_install() {
  if has_cmd go; then
    log_info "  Go configured. Try: go version"
  fi
}

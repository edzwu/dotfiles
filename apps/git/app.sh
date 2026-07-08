#!/usr/bin/env bash
# =============================================================================
# App: Git
# =============================================================================
# 跨平台共享的 Git 配置。
# =============================================================================

APP_NAME="git"
APP_DESC="Distributed version control system"
APP_DEPS=()

# 包名声明（供 pkg_install_auto 使用）
APP_BREW_FORMULA="git"
APP_APT_PACKAGE="git"

# Delta 包名（按平台）
DELTA_BREW_FORMULA="git-delta"
DELTA_APT_PACKAGE="git-delta"

# 当 apt 中没有 git-delta 时（如 Ubuntu 20.04），从 GitHub releases 安装 .deb
_install_delta_from_github() {
  if ! has_cmd dpkg; then
    return 1
  fi

  local arch
  arch="$(dpkg --print-architecture)"

  local latest_tag
  latest_tag="$(curl -fsSL https://api.github.com/repos/dandavison/delta/releases/latest | jq -r '.tag_name')"
  if [[ -z "$latest_tag" || "$latest_tag" == "null" ]]; then
    return 1
  fi

  local deb_url="https://github.com/dandavison/delta/releases/download/${latest_tag}/git-delta-musl_${latest_tag#v}_${arch}.deb"
  local tmp_deb="/tmp/git-delta_${latest_tag}.deb"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "  [dry-run] Would download and install delta from GitHub: $deb_url"
    return 0
  fi

  log "  Downloading delta ${latest_tag} from GitHub..."
  if curl -fsSL -o "$tmp_deb" "$deb_url"; then
    sudo dpkg -i "$tmp_deb" && rm -f "$tmp_deb"
  else
    rm -f "$tmp_deb"
    return 1
  fi
}

# 默认安装：使用平台包管理器
app_install() {
  # 尝试自动安装，如果失败则跳过（因为 git 通常已预装）
  pkg_install_auto "$APP_NAME" || true

  # 尝试安装 delta（增强 diff/pager），失败不阻塞
  local delta_pkg=""
  case "${DETECTED_OS:-}" in
    darwin) delta_pkg="$DELTA_BREW_FORMULA" ;;
    linux)  delta_pkg="$DELTA_APT_PACKAGE" ;;
  esac

  if [[ -n "$delta_pkg" ]]; then
    log "  Installing optional: $delta_pkg"
    if ! pkg_install "$delta_pkg" 2>/dev/null; then
      if [[ "${DETECTED_OS:-}" == "linux" ]]; then
        _install_delta_from_github || log_warn "  delta not installed, will use default pager"
      else
        log_warn "  $delta_pkg not installed, will use default pager"
      fi
    fi
  fi
}

# 配置：链接共享的 git 配置
app_configure() {
  local config_dir="$APP_DIR/config"

  link_home_file "$config_dir/gitconfig" ".gitconfig"
  link_home_file "$config_dir/gitignore_global" ".gitignore_global"
}

# 安装后：设置一些动态配置
app_post_install() {
  local gitconfig_local="$HOME/.gitconfig_local"
  ensure_dir "$(dirname "$gitconfig_local")"

  # 如果 delta 已安装，配置它为 pager；否则 fallback 到默认 pager
  if has_cmd delta; then
    git config --file "$gitconfig_local" core.pager "delta"
    git config --file "$gitconfig_local" delta.side-by-side "true"
    git config --file "$gitconfig_local" delta.line-numbers "true"
  else
    git config --file "$gitconfig_local" --unset core.pager 2>/dev/null || true
    log_info "  Using default git pager (delta not available)"
  fi
}

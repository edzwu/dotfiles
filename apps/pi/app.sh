#!/usr/bin/env bash
# =============================================================================
# App: pi (coding agent harness)
# =============================================================================
# 通过官方安装脚本安装 pi: curl -fsSL https://pi.dev/install.sh | sh
# 默认不安装；使用 ./init.sh --app pi 手动触发。
# =============================================================================

APP_NAME="pi"
APP_DESC="pi coding agent harness"
APP_DEPS=()

# pi 不在系统包管理器中，通过官方脚本安装
# APP_BREW_FORMULA=""
# APP_APT_PACKAGE=""
# APP_WINGET_ID=""

_is_pi_installed() {
  has_cmd pi || [[ -x "$HOME/.local/bin/pi" ]] || [[ -x "$HOME/bin/pi" ]]
}

app_install() {
  if _is_pi_installed; then
    log_info "  Already installed: pi"
    return 0
  fi

  log "  Installing pi via https://pi.dev/install.sh..."

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "  [dry-run] Would run: curl -fsSL https://pi.dev/install.sh | sh"
    return 0
  fi

  local install_url="https://pi.dev/install.sh"

  if has_cmd curl; then
    curl -fsSL "$install_url" | sh
  elif has_cmd wget; then
    wget -qO- "$install_url" | sh
  else
    die "Need curl or wget to install pi"
  fi

  if ! _is_pi_installed; then
    die "pi install failed"
  fi

  log_success "  pi installed"
}

app_post_install() {
  if _is_pi_installed; then
    log_info "  pi is ready. Try: pi --help"
  fi
}

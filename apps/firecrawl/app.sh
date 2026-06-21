#!/usr/bin/env bash
# =============================================================================
# App: Firecrawl
# =============================================================================
# Firecrawl API 本地配置管理。
# 敏感信息（FIRECRAWL_API_KEY）存放在 ~/.profile.d/firecrawl.local.sh，
# 不进入 git；仓库中仅保留模板文件作为显式提示。
# =============================================================================

APP_NAME="firecrawl"
APP_DESC="Firecrawl API configuration"
APP_DEPS=(bash)

# 不需要通过包管理器安装
# APP_BREW_FORMULA=""
# APP_APT_PACKAGE=""

app_install() {
  # Firecrawl 是纯 API 配置，无需安装二进制
  :
}

app_configure() {
  local profile_d="$HOME/.profile.d"
  ensure_dir "$profile_d"

  local template="$DOTFILES/home/profile.d/firecrawl.local.sh.template"
  local local_file="$profile_d/firecrawl.local.sh"

  if [[ ! -f "$local_file" ]]; then
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
      log "  [dry-run] Would copy Firecrawl template to ${local_file}"
    else
      cp "$template" "$local_file"
      log_info "  Created Firecrawl local config: ${local_file}"
    fi
  fi
}

app_post_install() {
  local local_file="$HOME/.profile.d/firecrawl.local.sh"

  log ""
  log_info "  Firecrawl configuration note:"
  log_info "    Local file:  ${local_file}"
  log_info "    Template:    ${DOTFILES}/home/profile.d/firecrawl.local.sh.template"
  log_info "    Please edit ${local_file} and set your FIRECRAWL_API_KEY"
  log_info "    Then run:    source ~/.zprofile"
}

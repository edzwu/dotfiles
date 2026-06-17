#!/usr/bin/env bash
# =============================================================================
# App override: ctags (macOS)
# =============================================================================
# macOS ships with BSD ctags at /usr/bin/ctags, which is incompatible with
# vim-gutentags. We completely ignore it and use Homebrew's universal-ctags.
# =============================================================================

# Return the path to Homebrew's ctags, or empty string if not found.
_brew_ctags_bin() {
  if [[ -x /opt/homebrew/bin/ctags ]]; then
    printf '%s' '/opt/homebrew/bin/ctags'
  elif [[ -x /usr/local/bin/ctags ]]; then
    printf '%s' '/usr/local/bin/ctags'
  else
    printf '%s' ''
  fi
}

app_install() {
  local brew_ctags
  brew_ctags="$(_brew_ctags_bin)"

  if [[ -n "$brew_ctags" ]]; then
    log_info "  Already installed: Universal Ctags ($brew_ctags)"
    return 0
  fi

  pkg_install_auto "$APP_NAME"
}

app_configure() {
  local brew_ctags
  brew_ctags="$(_brew_ctags_bin)"

  if [[ -z "$brew_ctags" ]]; then
    log_warn "  Homebrew ctags not found, skipping symlink"
    return 0
  fi

  # Create a symlink in ~/.local/bin so it takes precedence over /usr/bin/ctags.
  ensure_dir "$HOME/.local/bin"
  link_file "$brew_ctags" "$HOME/.local/bin/ctags"
}

app_post_install() {
  local brew_ctags
  brew_ctags="$(_brew_ctags_bin)"

  if [[ -n "$brew_ctags" ]]; then
    log_success "  Universal Ctags is ready ($brew_ctags)"
    log_info "  ~/.local/bin/ctags -> $brew_ctags"
  else
    log_warn "  ctags not found in Homebrew paths"
  fi
}

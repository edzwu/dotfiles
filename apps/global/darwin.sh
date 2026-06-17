#!/usr/bin/env bash
# =============================================================================
# App override: global/gtags (macOS)
# =============================================================================
# On macOS, Homebrew ships a gtags.conf whose universal-ctags plugin parser
# points to the correct Homebrew ctags path. Use that instead of the generic
# dotfiles gtags.conf, which assumes Ubuntu-style paths like
# /usr/bin/ctags-universal.
# =============================================================================

# Return the path to Homebrew's gtags.conf, or empty string if not found.
_brew_gtags_conf() {
  if [[ -f /opt/homebrew/etc/gtags.conf ]]; then
    printf '%s' '/opt/homebrew/etc/gtags.conf'
  elif [[ -f /usr/local/etc/gtags.conf ]]; then
    printf '%s' '/usr/local/etc/gtags.conf'
  else
    printf '%s' ''
  fi
}

app_install() {
  pkg_install_auto "$APP_NAME"
}

app_configure() {
  local brew_gtags_conf
  brew_gtags_conf="$(_brew_gtags_conf)"

  if [[ -z "$brew_gtags_conf" ]]; then
    log_warn "  Homebrew gtags.conf not found, skipping config link"
    return 0
  fi

  # Replace the whole ~/.global directory symlink (pointing to dotfiles'
  # home/global) with a real directory, then link only gtags.conf to the
  # Homebrew-provided config. This avoids modifying files inside the
  # dotfiles repository when global's config needs to differ by OS.
  local dotfiles_global_dir="$DOTFILES/home/global"
  local home_global_dir="$HOME/.global"

  if [[ -L "$home_global_dir" ]]; then
    local current_target
    current_target="$(readlink "$home_global_dir")"
    if [[ "$current_target" == "$dotfiles_global_dir" ]]; then
      rm "$home_global_dir"
    fi
  fi

  if [[ -e "$home_global_dir" && ! -d "$home_global_dir" ]]; then
    # Existing file or symlink to something else; back it up.
    local backup="${home_global_dir}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$home_global_dir" "$backup"
    log_info "  Backed up: $home_global_dir → $backup"
  fi

  ensure_dir "$home_global_dir"
  link_file "$brew_gtags_conf" "$home_global_dir/gtags.conf"
}

app_post_install() {
  if has_cmd gtags; then
    log_info "  global (gtags) configured. Try: gtags --version"
  fi
}

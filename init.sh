#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Dotfiles 主入口脚本
# =============================================================================
# 用法:
#   ./init.sh                    # 按当前 OS 的清单安装
#   ./init.sh --dry-run          # 预览模式
#   ./init.sh --check            # 检查已安装/缺失/未启用的 App
#   ./init.sh --list-apps        # 列出所有可用 App
#   ./init.sh --app git          # 只安装/配置单个 App
# =============================================================================

# 基础路径
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES

# 导入共享库
# shellcheck source=/dev/null
source "$DOTFILES/lib/common.sh"

# 全局状态
DRY_RUN=0
TARGET_APP=""
MODE="install"   # install | check | list-apps

# =============================================================================
# TOML 解析
# =============================================================================
# 简单 TOML 解析器，支持 [section] 和 key = value（含引号字符串）
# 输出格式: section.key=value
# =============================================================================
toml_parse() {
  local file="$1"
  local section=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    # 去掉行首空白
    line="${line#"${line%%[![:space:]]*}"}"
    # 跳过注释和空行
    [[ -z "$line" || "$line" == \#* ]] && continue

    # 匹配 [section]
    if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\][[:space:]]*$ ]]; then
      section="${BASH_REMATCH[1]}"
      continue
    fi

    # 匹配 key = value
    if [[ "$line" =~ ^([a-zA-Z0-9_-]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      # 去掉首尾引号
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"
      # 去掉行尾注释
      value="${value%%#*}"
      # trim 左右空白
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      echo "${section}.${key}=${value}"
    fi
  done < "$file"
}

# 从 catalog.toml 构建 App 元数据
# 注意：使用 eval 模拟关联数组以兼容 bash 3.2 (macOS 默认)
# CATALOG_APPS 是普通数组，存储所有 App 名称列表

load_catalog() {
  local catalog="$DOTFILES/manifests/catalog.toml"
  if [[ ! -f "$catalog" ]]; then
    die "Catalog not found: $catalog"
  fi

  CATALOG_APPS=()
  while IFS='=' read -r key value; do
    [[ -z "$key" ]] && continue
    local app_name="${key%%.*}"
    local attr="${key#*.}"

    # 记录 App 名称列表（去重）
    local found=0
    local a
    for a in "${CATALOG_APPS[@]:-}"; do
      if [[ "$a" == "$app_name" ]]; then
        found=1
        break
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      CATALOG_APPS+=("$app_name")
    fi

    local safe_name
    safe_name="$(_safe_var_name "$app_name")"
    # 对 value 中的双引号转义，然后用双引号包裹赋值
    local dq='"'
    local escaped_value="${value//$dq/\\\"}"
    case "$attr" in
      desc)
        eval "APP_DESC_${safe_name}=\"$escaped_value\""
        ;;
      platforms)
        eval "APP_PLATFORM_${safe_name}=\"$escaped_value\""
        ;;
      group)
        eval "APP_GROUP_${safe_name}=\"$escaped_value\""
        ;;
    esac
  done < <(toml_parse "$catalog")
}

# 从当前 OS 的清单读取要安装的 App
declare -a MANIFEST_APPS=()

load_manifest() {
  local manifest="$DOTFILES/manifests/${DETECTED_OS}.toml"
  if [[ ! -f "$manifest" ]]; then
    die "Manifest not found for OS '${DETECTED_OS}': $manifest"
  fi

  MANIFEST_APPS=()
  while IFS='=' read -r key value; do
    [[ -z "$key" ]] && continue
    # toml_parse 输出格式: section.key=value
    # 例如: core.bash=true
    # App 名是 key 部分（bash），value 是开关（true/false）
    local app_name="${key#*.}"
    if [[ "$value" == "true" ]]; then
      MANIFEST_APPS+=("$app_name")
    fi
  done < <(toml_parse "$manifest")
}

# 安全的变量名（bash 变量名不能含连字符）
_safe_var_name() {
  printf '%s' "$1" | tr '-' '_'
}

# 获取 App 的平台限制（兼容 bash 3.2）
_app_platforms() {
  local app_name="$1"
  local var_name
  var_name="$(_safe_var_name "$app_name")"
  eval "printf '%s' \"\${APP_PLATFORM_${var_name}:-}\""
}

# 获取 App 描述（兼容 bash 3.2）
_app_desc() {
  local app_name="$1"
  local var_name
  var_name="$(_safe_var_name "$app_name")"
  eval "printf '%s' \"\${APP_DESC_${var_name}:-}\""
}

# 获取 App 分组（兼容 bash 3.2）
_app_group() {
  local app_name="$1"
  local var_name
  var_name="$(_safe_var_name "$app_name")"
  eval "printf '%s' \"\${APP_GROUP_${var_name}:-other}\""
}

# 检查 App 名称是否存在于 catalog
_app_exists() {
  local name="$1"
  for app in "${CATALOG_APPS[@]}"; do
    [[ "$app" == "$name" ]] && return 0
  done
  return 1
}

# 检查分组名称是否存在于 catalog
_group_exists() {
  local name="$1"
  for app in "${CATALOG_APPS[@]}"; do
    local g
    g="$(_app_group "$app")"
    [[ "$g" == "$name" ]] && return 0
  done
  return 1
}

# 获取某分组下所有在当前平台支持的 App
_apps_in_group() {
  local group="$1"
  for app in "${CATALOG_APPS[@]}"; do
    local g
    g="$(_app_group "$app")"
    if [[ "$g" == "$group" ]] && app_is_supported "$app"; then
      printf '%s\n' "$app"
    fi
  done
}

# 检查 App 是否在当前平台支持
app_is_supported() {
  local app_name="$1"
  local platforms
  platforms="$(_app_platforms "$app_name")"
  [[ -z "$platforms" ]] && return 0

  # 解析 platforms = ["darwin", "linux"]
  platforms="${platforms//\[/}"
  platforms="${platforms//\]/}"
  platforms="${platforms//\"/}"
  platforms="${platforms//\'/}"
  platforms="${platforms//,/ }"

  for p in $platforms; do
    [[ "$p" == "$DETECTED_OS" ]] && return 0
  done
  return 1
}

# 检查 App 是否已安装（通过 pkg_is_installed 或 has_cmd）
app_is_installed() {
  local app_name="$1"

  # 先尝试用包管理器检查
  local brew_var="APP_BREW_FORMULA"
  local apt_var="APP_APT_PACKAGE"
  local pkg_name=""

  # 需要临时加载 app.sh 来获取包名变量
  local app_script="$DOTFILES/apps/$app_name/app.sh"
  if [[ -f "$app_script" ]]; then
    # 用子 shell 读取变量，避免污染当前环境
    pkg_name="$(bash -c "
      DETECTED_OS='$DETECTED_OS'
      source '$app_script' >/dev/null 2>&1
      case '\$DETECTED_OS' in
        darwin) echo '\${APP_BREW_FORMULA:-}' ;;
        linux)  echo '\${APP_APT_PACKAGE:-}' ;;
      esac
    ")"
  fi

  if [[ -n "$pkg_name" ]]; then
    if pkg_is_installed "$pkg_name" 2>/dev/null; then
      return 0
    fi
  fi

  #  fallback：检查命令是否存在（根据 App 名或常见命令名映射）
  case "$app_name" in
    node) has_cmd node || has_cmd npm ;;
    python) has_cmd python3 || has_cmd python ;;
    rust) [[ -x "$HOME/.cargo/bin/rustc" ]] || has_cmd rustc ;;
    global) has_cmd gtags ;;
    rg) has_cmd rg ;;
    fd) has_cmd fd ;;
    fzf) has_cmd fzf ;;
    ctags) has_cmd ctags ;;
    clang-format) has_cmd clang-format ;;
    mihomo) has_cmd mihomo || has_cmd clash ;;
    pi) has_cmd pi || [[ -x "$HOME/.local/bin/pi" ]] || [[ -x "$HOME/bin/pi" ]] ;;
    *) has_cmd "$app_name" ;;
  esac
}

# =============================================================================
# OS 检测
# =============================================================================
detect_os() {
  case "$OSTYPE" in
    linux*)
      DETECTED_OS="linux"
      ;;
    darwin*)
      DETECTED_OS="darwin"
      ;;
    msys* | cygwin* | win32*)
      DETECTED_OS="windows"
      ;;
    *)
      die "Unsupported OS: $OSTYPE"
      ;;
  esac

  log "Detected OS: $DETECTED_OS"

  # 加载 OS 特定的库
  local os_lib="$DOTFILES/lib/${DETECTED_OS}.sh"
  if [[ -f "$os_lib" ]]; then
    # shellcheck source=/dev/null
    source "$os_lib"
  else
    die "OS library not found: $os_lib"
  fi
}

# =============================================================================
# App 调度器（复用之前的 run_app）
# =============================================================================
run_app() {
  local app_name="$1"
  local app_dir="$DOTFILES/apps/$app_name"

  if [[ ! -d "$app_dir" ]]; then
    log_warn "App '$app_name' not found in apps/, skipping"
    return 0
  fi

  # 加载 App 定义
  local app_script="$app_dir/app.sh"
  if [[ ! -f "$app_script" ]]; then
    log_warn "App '$app_name' missing app.sh, skipping"
    return 0
  fi

  # 设置当前 App 上下文变量
  export APP_DIR="$app_dir"
  export APP_NAME="$app_name"

  # shellcheck source=/dev/null
  source "$app_script"

  # 加载平台覆盖（如果存在）
  local os_override="$app_dir/${DETECTED_OS}.sh"
  if [[ -f "$os_override" ]]; then
    # shellcheck source=/dev/null
    source "$os_override"
  fi

  # OS 兼容性检查
  if [[ -n "${APP_SUPPORTED_OS:-}" ]]; then
    local supported=0
    local os
    for os in "${APP_SUPPORTED_OS[@]}"; do
      if [[ "$os" == "$DETECTED_OS" ]]; then
        supported=1
        break
      fi
    done
    if [[ "$supported" -eq 0 ]]; then
      log_info "  Skipping '$app_name' (not supported on $DETECTED_OS)"
      unset APP_DIR APP_NAME
      return 0
    fi
  fi

  log ""
  log "▶ Processing app: $app_name"

  # 执行生命周期
  if type app_install &>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [dry-run] Would run app_install()"
    else
      app_install || die "Failed to install app: $app_name"
    fi
  fi

  if type app_configure &>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [dry-run] Would run app_configure()"
    else
      app_configure || die "Failed to configure app: $app_name"
    fi
  fi

  if type app_post_install &>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      log "  [dry-run] Would run app_post_install()"
    else
      app_post_install || log_warn "Post-install failed for: $app_name"
    fi
  fi

  # 清理环境
  unset APP_DIR APP_NAME
}

apply_manifest() {
  log ""
  log "========================================"
  log "Applying manifest for: $DETECTED_OS"
  log "Apps: ${MANIFEST_APPS[*]}"
  log "========================================"

  for app in "${MANIFEST_APPS[@]}"; do
    run_app "$app"
  done

  # OS 层收尾
  local os_defaults="$DOTFILES/os/$DETECTED_OS/defaults.sh"
  if [[ -f "$os_defaults" ]]; then
    log ""
    log "▶ Applying OS defaults"
    # shellcheck source=/dev/null
    source "$os_defaults"
  fi

  log ""
  log "✓ Done!"
}

# =============================================================================
# --check 模式
# =============================================================================
check_apps() {
  log ""
  log "========================================"
  log "Checking apps for: $DETECTED_OS"
  log "========================================"

  local -a installed=()
  local -a missing=()
  local -a disabled=()
  local -a unsupported=()

  # 遍历 catalog 中所有 App
  local app_name
  for app_name in "${CATALOG_APPS[@]}"; do
    if ! app_is_supported "$app_name"; then
      unsupported+=("$app_name")
      continue
    fi

    # 检查是否在清单中启用
    local enabled=0
    local a
    for a in "${MANIFEST_APPS[@]}"; do
      if [[ "$a" == "$app_name" ]]; then
        enabled=1
        break
      fi
    done

    if [[ "$enabled" -eq 1 ]]; then
      if app_is_installed "$app_name"; then
        installed+=("$app_name")
      else
        missing+=("$app_name")
      fi
    else
      disabled+=("$app_name")
    fi
  done

  # 输出结果
  log ""
  if [[ ${#installed[@]} -gt 0 ]]; then
    log_success "✅ Already installed (${#installed[@]}):"
    for app in "${installed[@]}"; do
      printf "   %-16s %s\n" "$app" "$(_app_desc "$app")"
    done
  fi

  log ""
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf "${C_RED}❌ Not installed (%s) — enabled in manifests/%s.toml${C_RESET}\n" "${#missing[@]}" "$DETECTED_OS"
    for app in "${missing[@]}"; do
      printf "   %-16s %s\n" "$app" "$(_app_desc "$app")"
    done
  fi

  log ""
  if [[ ${#disabled[@]} -gt 0 ]]; then
    printf "${C_DIM}⏸️  Disabled in manifest (%s)${C_RESET}\n" "${#disabled[@]}"
    for app in "${disabled[@]}"; do
      printf "   %-16s %s\n" "$app" "$(_app_desc "$app")"
    done
  fi

  if [[ ${#unsupported[@]} -gt 0 ]]; then
    log ""
    printf "${C_DIM}⛔ Not supported on %s (%s)${C_RESET}\n" "$DETECTED_OS" "${#unsupported[@]}"
    for app in "${unsupported[@]}"; do
      printf "   %-16s %s\n" "$app" "$(_app_desc "$app")"
    done
  fi

  log ""
  log_info "💡 Tip: Edit manifests/${DETECTED_OS}.toml to enable/disable apps"
}

# =============================================================================
# --list-apps 模式
# =============================================================================
list_apps() {
  log ""
  log "========================================"
  log "Available apps"
  log "========================================"

  # 按 group 分组输出（使用命名空间变量模拟关联数组）
  local app_name
  for app_name in "${CATALOG_APPS[@]}"; do
    local g
    g="$(_app_group "$app_name")"
    local safe_g
    safe_g="$(_safe_var_name "$g")"
    eval "GROUP_APPS_${safe_g}=\"\${GROUP_APPS_${safe_g}:-}\$app_name \""
  done

  local group_order=("core" "editor" "tool" "search" "language" "devtool" "proxy" "other")
  local group
  for group in "${group_order[@]}"; do
    local safe_g
    safe_g="$(_safe_var_name "$group")"
    local apps
    eval "apps=\"\${GROUP_APPS_${safe_g}:-}\""
    [[ -z "$apps" ]] && continue

    log ""
    printf "${C_BOLD}[%s]${C_RESET}\n" "$group"
    local app
    for app in $apps; do
      local supported="${C_GREEN}●${C_RESET}"
      if ! app_is_supported "$app"; then
        supported="${C_DIM}○${C_RESET}"
      fi
      printf "  %s %-16s %s\n" "$supported" "$app" "$(_app_desc "$app")"
    done
  done

  log ""
  log_info "Legend: ${C_GREEN}●${C_RESET} supported on $DETECTED_OS   ${C_DIM}○${C_RESET} not supported"
}

# =============================================================================
# CLI 参数解析
# =============================================================================
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -n, --dry-run         Preview changes without applying
  -c, --check           Check installed/missing/disabled apps
  -l, --list-apps       List all available apps
  -a, --app NAME        Apply a single app or a group
  -h, --help            Show this help

Examples:
  ./init.sh                    # Install apps from manifest
  ./init.sh --dry-run          # Preview only
  ./init.sh --check            # See what's installed vs missing
  ./init.sh --list-apps        # Browse all available apps
  ./init.sh --app git          # Install single app
  ./init.sh --app core         # Install all apps in 'core' group
  ./init.sh --app proxy        # Install all apps in 'proxy' group
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n | --dry-run)
        DRY_RUN=1
        shift
        ;;
      -c | --check)
        MODE="check"
        shift
        ;;
      -l | --list-apps)
        MODE="list-apps"
        shift
        ;;
      -a | --app)
        if [[ $# -lt 2 ]]; then
          die "Option $1 requires an argument (e.g., --app git)"
        fi
        TARGET_APP="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

# =============================================================================
# 主流程
# =============================================================================
main() {
  parse_args "$@"

  detect_os
  load_catalog

  if [[ -n "$TARGET_APP" ]]; then
    # 单 App 模式
    if _app_exists "$TARGET_APP"; then
      if ! app_is_supported "$TARGET_APP"; then
        die "App '$TARGET_APP' is not supported on $DETECTED_OS"
      fi
      run_app "$TARGET_APP"
      exit 0
    fi

    # 分组模式
    if _group_exists "$TARGET_APP"; then
      log ""
      log "========================================"
      log "Installing group: $TARGET_APP"
      log "========================================"
      local group_apps=()
      while IFS= read -r app; do
        [[ -n "$app" ]] && group_apps+=("$app")
      done < <(_apps_in_group "$TARGET_APP")
      if [[ ${#group_apps[@]} -eq 0 ]]; then
        die "Group '$TARGET_APP' has no supported apps on $DETECTED_OS"
      fi
      for app in "${group_apps[@]}"; do
        run_app "$app"
      done
      exit 0
    fi

    die "Unknown app or group: '$TARGET_APP'"
  fi

  case "$MODE" in
    check)
      load_manifest
      check_apps
      ;;
    list-apps)
      list_apps
      ;;
    install)
      load_manifest
      apply_manifest
      ;;
  esac
}

main "$@"

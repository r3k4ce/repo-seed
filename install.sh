#!/usr/bin/env bash
set -euo pipefail

COMMAND_NAME="reposeed"
BIN_DIR="${HOME}/.local/bin"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/reposeed"

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Install the RepoSeed Bash scaffolder as a per-user command.

Options:
  --bin-dir PATH       Directory for the command wrapper. Defaults to ~/.local/bin.
  --data-dir PATH      Directory for managed RepoSeed files. Defaults to ~/.local/share/reposeed.
  --command NAME       Command name to install. Defaults to reposeed.
  -h, --help           Show this help.
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$1" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bin-dir)
        [[ $# -ge 2 ]] || die "--bin-dir requires a value."
        BIN_DIR="$2"
        shift 2
        ;;
      --data-dir)
        [[ $# -ge 2 ]] || die "--data-dir requires a value."
        DATA_DIR="$2"
        shift 2
        ;;
      --command)
        [[ $# -ge 2 ]] || die "--command requires a value."
        COMMAND_NAME="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

validate_args() {
  [[ -n "${COMMAND_NAME//[[:space:]]/}" ]] || die "--command must not be empty."
  [[ "$COMMAND_NAME" != */* ]] || die "--command must be a command name, not a path."
  [[ -n "${BIN_DIR//[[:space:]]/}" ]] || die "--bin-dir must not be empty."
  [[ -n "${DATA_DIR//[[:space:]]/}" ]] || die "--data-dir must not be empty."
}

absolute_path() {
  local path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s/%s\n' "$(pwd -P)" "$path" ;;
  esac
}

is_empty_dir() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  [[ -z "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" ]]
}

ensure_data_dir_can_be_replaced() {
  if [[ ! -e "$DATA_DIR" ]]; then
    return
  fi

  [[ -d "$DATA_DIR" ]] || die "Data path exists and is not a directory: $DATA_DIR"

  if [[ -f "$DATA_DIR/.reposeed-install" ]]; then
    return
  fi

  if is_empty_dir "$DATA_DIR"; then
    return
  fi

  die "Refusing to replace non-empty unmanaged data directory: $DATA_DIR"
}

copy_payload() {
  local payload="$1"

  mkdir -p "$payload"
  cp "$REPO_ROOT/new-project.sh" "$payload/new-project.sh"
  cp "$REPO_ROOT/new-project.ps1" "$payload/new-project.ps1"
  cp -R "$REPO_ROOT/templates" "$payload/templates"
  chmod +x "$payload/new-project.sh"
  printf 'managed-by=RepoSeed\ninstalled-command=%s\n' "$COMMAND_NAME" >"$payload/.reposeed-install"
}

replace_data_dir() {
  local payload="$1"
  local parent

  parent="$(dirname "$DATA_DIR")"
  mkdir -p "$parent"

  if [[ -e "$DATA_DIR" ]]; then
    rm -rf "$DATA_DIR"
  fi

  mv "$payload" "$DATA_DIR"
}

write_wrapper() {
  local wrapper="$BIN_DIR/$COMMAND_NAME"
  local installed_script="$DATA_DIR/new-project.sh"

  mkdir -p "$BIN_DIR"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n'
    printf 'exec %q "$@"\n' "$installed_script"
  } >"$wrapper"
  chmod +x "$wrapper"
}

warn_if_bin_dir_not_on_path() {
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on PATH. Add it to your shell profile before running $COMMAND_NAME by name." ;;
  esac
}

main() {
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  [[ -f "$REPO_ROOT/new-project.sh" ]] || die "Missing new-project.sh next to installer."
  [[ -f "$REPO_ROOT/new-project.ps1" ]] || die "Missing new-project.ps1 next to installer."
  [[ -d "$REPO_ROOT/templates" ]] || die "Missing templates directory next to installer."

  parse_args "$@"
  validate_args
  BIN_DIR="$(absolute_path "$BIN_DIR")"
  DATA_DIR="$(absolute_path "$DATA_DIR")"
  ensure_data_dir_can_be_replaced

  local temp_root payload
  temp_root="$(mktemp -d)"
  payload="$temp_root/reposeed"
  trap 'rm -rf '"$(printf '%q' "$temp_root")" EXIT

  copy_payload "$payload"
  replace_data_dir "$payload"
  write_wrapper
  warn_if_bin_dir_not_on_path

  printf 'Installed %s to %s\n' "$COMMAND_NAME" "$BIN_DIR/$COMMAND_NAME"
  printf 'Managed files are in %s\n' "$DATA_DIR"
}

main "$@"

#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

main() {
  local repo_path="$1"
  local base_branch="${2:-}"
  local name

  read -r -p "New branch name: " name

  # Empty input cancels the operation
  if [[ -z "$name" ]]; then
    return 0
  fi

  cd "$repo_path" || {
    printf 'yunomi: cannot cd to %s\n' "$repo_path" >&2
    return 1
  }
  if [[ -n "$base_branch" ]]; then
    hashi new -- "$name" "$base_branch" || return 1
  else
    hashi new -- "$name" || return 1
  fi

  # On success: set the exit flag to signal the popup to close
  touch "$YUNOMI_EXIT_FLAG"
}

# Apply set -euo pipefail only when executed directly.
# This prevents polluting the parent script's set options when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

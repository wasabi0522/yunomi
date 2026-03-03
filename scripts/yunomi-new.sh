#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

main() {
  local repo_path="$1"
  local name

  read_input "New branch name (esc to cancel): " || return 0
  name="$REPLY"

  # Empty input cancels the operation
  if [[ -z "$name" ]]; then
    return 0
  fi

  cd "$repo_path" || {
    printf 'yunomi: cannot cd to %s\n' "$repo_path" >&2
    return 1
  }
  hashi new -- "$name" || return 1

  # On success: set the exit flag to signal the popup to close
  touch "$YUNOMI_EXIT_FLAG"
}

# Apply set -euo pipefail only when executed directly.
# This prevents polluting the parent script's set options when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

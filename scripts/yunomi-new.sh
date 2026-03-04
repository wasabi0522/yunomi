#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

# main <repo_path> [base_branch]
#
# Helper to create a new branch. Called from fzf's execute() action.
#
# Arguments:
#   $1  repo_path   - absolute path to the target repository
#   $2  base_branch - (optional) base branch to create from
#
# Environment variables:
#   YUNOMI_EXIT_FLAG  path to the exit flag file (exported by yunomi-main.sh).
#                     Touched on success to signal the popup to close,
#                     because hashi switches to the new window automatically.
main() {
  local repo_path="$1"
  local base_branch="${2:-}"
  local name

  read_input "New branch name (esc to cancel): " || return 0
  name="$REPLY"

  # Empty input cancels the operation
  if [[ -z "$name" ]]; then
    return 0
  fi

  cd_repo "$repo_path" || return 1
  if [[ -n "$base_branch" ]]; then
    hashi new -- "$name" "$base_branch" || return $?
  else
    hashi new -- "$name" || return $?
  fi

  # On success: set the exit flag to signal the popup to close
  if validate_exit_flag_path "${YUNOMI_EXIT_FLAG:-}"; then
    touch "$YUNOMI_EXIT_FLAG"
  fi
}

# Apply set -euo pipefail only when executed directly.
# This prevents polluting the parent script's set options when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

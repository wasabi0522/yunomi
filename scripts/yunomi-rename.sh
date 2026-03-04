#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

# main <repo_path> <old_branch>
#
# Helper to rename a branch. Called from fzf's execute() action.
#
# Arguments:
#   $1  repo_path  - absolute path to the target repository
#   $2  old_branch - current name of the branch to rename
main() {
  local repo_path="$1"
  local old_branch="$2"

  local new_branch

  read_input "Rename '${old_branch}' to (esc to cancel): " || return 0
  new_branch="$REPLY"

  # Empty input cancels the operation
  if [[ -z "$new_branch" ]]; then
    return 0
  fi

  cd_repo "$repo_path" || return 1
  hashi rename -- "$old_branch" "$new_branch" || return $?
}

# Apply set -euo pipefail only when executed directly.
# This prevents polluting the parent script's set options when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

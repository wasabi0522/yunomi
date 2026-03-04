#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

# main <repo_path> <branch_name>
#
# Helper to delete a branch. Called from fzf's execute() action.
#
# Arguments:
#   $1  repo_path   - absolute path to the target repository
#   $2  branch_name - name of the branch to delete
#
# Behavior:
#   1. cd "$repo_path" && hashi remove "$branch_name"
#      (hashi shows a confirmation prompt; the user selects y/N)
#   2. After deletion, fzf reloads the branch list (popup stays open)
#
# Exit code:
#   Returns hashi remove's exit code as-is
main() {
  local repo_path="$1"
  local branch_name="$2"

  # Run hashi remove
  # hashi operates on the repository in the current directory, so cd is required
  cd_repo "$repo_path" || return 1
  hashi remove -- "$branch_name" || return $?
}

# Apply set -euo pipefail only when executed directly.
# This prevents polluting the parent script's set options when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

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
# Environment variables:
#   YUNOMI_HASHI_JSON  result of hashi list --json (already exported by yunomi-main.sh)
#   YUNOMI_EXIT_FLAG   path to the exit flag file (exported by yunomi-main.sh)
#
# Behavior:
#   1. Read the active flag for the target branch from YUNOMI_HASHI_JSON (jq)
#   2. cd "$repo_path" && hashi remove "$branch_name"
#      (hashi shows a confirmation prompt; the user selects y/N)
#   3. If deletion succeeded and the branch was active → touch "$YUNOMI_EXIT_FLAG"
#
# Exit code:
#   Returns hashi remove's exit code as-is
main() {
  local repo_path="$1"
  local branch_name="$2"

  # Treat YUNOMI_HASHI_JSON as empty JSON when it is unset (fallback)
  local hashi_json="${YUNOMI_HASHI_JSON:-[]}"

  # Check whether the target branch is currently active
  local is_active
  is_active=$(printf '%s' "$hashi_json" | jq -r --arg b "$branch_name" \
    '.[] | select(.branch == $b) | .active')

  # Run hashi remove
  # hashi operates on the repository in the current directory, so cd is required
  cd "$repo_path" || {
    printf 'yunomi: cannot cd to %s\n' "$repo_path" >&2
    return 1
  }
  local exit_code=0
  hashi remove -- "$branch_name" || exit_code=$?

  # Create the exit flag only when deletion succeeded and the deleted branch was active
  # (hashi retreats to the default branch, so the popup must be closed)
  if [[ $exit_code -eq 0 && "$is_active" == "true" ]]; then
    touch "$YUNOMI_EXIT_FLAG"
  fi

  return $exit_code
}

# Apply set -euo pipefail only when executed directly.
# This prevents polluting the parent script's set options when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

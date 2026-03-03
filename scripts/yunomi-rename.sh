#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

main() {
  local repo_path="$1"
  local old_branch="$2"

  local new_branch
  # IFS= prevents trimming leading/trailing whitespace (whitespace-only input is left to hashi for validation)
  IFS= read -r -p "Rename '${old_branch}' to (esc+enter to cancel): " new_branch

  # Empty input cancels the operation
  if [[ -z "$new_branch" ]]; then
    return 0
  fi

  cd "$repo_path" || {
    printf 'yunomi: cannot cd to %s\n' "$repo_path" >&2
    return 1
  }
  hashi rename -- "$old_branch" "$new_branch" || return $?
}

# Apply set -euo pipefail only when executed directly.
# This prevents polluting the parent script's set options when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

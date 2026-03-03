#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

# main <action> <repo_path> [branch_name]
#
# Dispatcher called from fzf's transform: binding.
# Outputs a single fzf action string to stdout based on the action type.
#
# Arguments:
#   $1  action      - one of "new" / "remove" / "rename"
#   $2  repo_path   - absolute path to the repository
#   $3  branch_name - target branch name (only for remove / rename)
#
# Environment variables:
#   YUNOMI_SCRIPTS_DIR  absolute path to the scripts directory (exported by yunomi-main.sh)
#                       falls back to CURRENT_DIR (the script's own directory) if unset
#
# Output: a single fzf action string on stdout
#
# Exit codes:
#   0  success
#   1  unknown action name
main() {
  local action="$1"
  local repo_path="$2"
  local branch_name="${3:-}"

  # Resolve the scripts directory (fall back to CURRENT_DIR when YUNOMI_SCRIPTS_DIR is unset)
  local scripts_dir="${YUNOMI_SCRIPTS_DIR:-$CURRENT_DIR}"

  # Shell-escape the paths (chawan style: store in variables via printf -v)
  local ESCAPED_SCRIPTS_DIR escaped_repo escaped_branch
  printf -v ESCAPED_SCRIPTS_DIR '%q' "$scripts_dir"
  printf -v escaped_repo '%q' "$repo_path"
  printf -v escaped_branch '%q' "$branch_name"

  # $YUNOMI_EXIT_FLAG inside transform() is expanded when fzf re-evaluates it,
  # so intentionally suppress expansion here with single quotes
  # shellcheck disable=SC2016
  local transform_check='[[ -f $YUNOMI_EXIT_FLAG ]] && echo abort'

  case "$action" in
    new)
      # execute: launch yunomi-new.sh (prompt → hashi new) with base branch
      # reload:  regenerate the branch list
      # transform: check the exit flag → if present, output abort to close fzf
      printf 'execute(%s/yunomi-new.sh %s %s)+reload(%s/yunomi-branch-list.sh %s)+transform(%s)\n' \
        "$ESCAPED_SCRIPTS_DIR" "$escaped_repo" "$escaped_branch" \
        "$ESCAPED_SCRIPTS_DIR" "$escaped_repo" \
        "$transform_check"
      ;;
    remove)
      # execute: launch yunomi-remove.sh (hashi remove + confirmation prompt)
      # reload:  regenerate the branch list
      # transform: check the exit flag → if present, output abort to close fzf
      printf 'execute(%s/yunomi-remove.sh %s %s)+reload(%s/yunomi-branch-list.sh %s)+transform(%s)\n' \
        "$ESCAPED_SCRIPTS_DIR" "$escaped_repo" "$escaped_branch" \
        "$ESCAPED_SCRIPTS_DIR" "$escaped_repo" \
        "$transform_check"
      ;;
    rename)
      # execute: launch yunomi-rename.sh (prompt → hashi rename)
      # reload:  regenerate the branch list
      # no transform: always stay in fzf after rename
      printf 'execute(%s/yunomi-rename.sh %s %s)+reload(%s/yunomi-branch-list.sh %s)\n' \
        "$ESCAPED_SCRIPTS_DIR" "$escaped_repo" "$escaped_branch" \
        "$ESCAPED_SCRIPTS_DIR" "$escaped_repo"
      ;;
    *)
      printf 'yunomi-fzf-action: unknown action: %s\n' "$action" >&2
      return 1
      ;;
  esac
}

# Apply set -euo pipefail only when executed directly.
# This prevents polluting the parent script's set options when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

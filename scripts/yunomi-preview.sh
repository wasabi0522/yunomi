#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

main() {
  local branch_name="${1:-}"
  local repo_path="${2:-}"

  if [[ -z "$branch_name" || -z "$repo_path" ]]; then
    printf 'Usage: yunomi-preview.sh <branch_name> <repo_path>\n' >&2
    exit 1
  fi

  # Treat YUNOMI_HASHI_JSON as empty JSON when it is unset (fallback)
  local hashi_json="${YUNOMI_HASHI_JSON:-[]}"

  # Get the branch's worktree path from hashi list --json
  # Returns an empty string when the worktree key is absent
  local worktree
  worktree=$(printf '%s' "$hashi_json" | jq -r --arg b "$branch_name" \
    '.[] | select(.branch == $b) | .worktree // ""')

  # ─── Branch name + separator ───
  printf '%s\n' "$branch_name"
  print_separator

  # ─── Worktree info ───
  if [[ -n "$worktree" ]]; then
    printf 'Worktree  %s\n' "$worktree"
  else
    printf 'Worktree  %s\n' "(no worktree)"
  fi

  # ─── Remote tracking status ───
  local remote_ref="origin/${branch_name}"
  local revlist
  revlist=$(git -C "$repo_path" rev-list --left-right --count \
    -- "${branch_name}...${remote_ref}" 2>/dev/null) || revlist=""
  if [[ -n "$revlist" ]]; then
    local ahead behind
    ahead="${revlist%%$'\t'*}"
    behind="${revlist##*$'\t'}"
    local remote_indicator=""
    [[ "$ahead" -gt 0 ]] && remote_indicator+="↑${ahead}"
    [[ "$behind" -gt 0 ]] && {
      [[ -n "$remote_indicator" ]] && remote_indicator+=" "
      remote_indicator+="↓${behind}"
    }
    [[ -z "$remote_indicator" ]] && remote_indicator="↑0 ↓0"
    printf 'Remote    %s\n' "$remote_indicator"
  else
    printf 'Remote    (no remote)\n'
  fi

  # ─── Status ───
  # git status --short is only available when a worktree exists
  local status_short=""
  if [[ -n "$worktree" ]]; then
    status_short=$(git -C "$worktree" status --short 2>/dev/null || true)
    local default_branch
    default_branch=$(get_default_branch "$repo_path")
    local merged_branches
    merged_branches=$(git -C "$repo_path" branch --merged "$default_branch" 2>/dev/null || true)
    local main_status
    main_status=$(get_main_status "$status_short" "$merged_branches" "$branch_name")
    printf 'Status    %s\n' "$main_status"
  fi

  printf '\n'

  # ─── Commits ───
  local commits
  commits=$(git -C "$repo_path" log --oneline -5 "$branch_name" -- 2>/dev/null || true)
  local commit_count=0
  if [[ -n "$commits" ]]; then
    local _lines
    mapfile -t _lines <<<"$commits"
    commit_count=${#_lines[@]}
  fi

  print_separator "Commits (${commit_count})"
  if [[ -n "$commits" ]]; then
    printf '%s\n' "$commits"
  fi
  printf '\n'

  # ─── Changed files (shown only when there are changes) ───
  if [[ -n "$worktree" && -n "$status_short" ]]; then
    print_separator "Changed files"
    printf '%s\n' "$status_short"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

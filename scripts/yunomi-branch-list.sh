#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

# main <repo_path>
# Outputs the branch list to stdout.
#
# Output format (per design.md L201-227):
#   first line (header): "\t   BRANCH{space}  STATUS"
#   data lines:          "{branch_name}\t {marker} {branch_name_padded}  {status_colored}"
#
# fzf's --with-nth=2.. hides field 1 (branch_name).
# --header-lines 1 separates the header row from the list.
main() {
  local quick=false
  if [[ "${1:-}" == "--quick" ]]; then
    quick=true
    shift
  fi
  local repo_path="$1"

  if [[ -z "$repo_path" ]]; then
    printf 'Usage: %s <repo_path>\n' "$(basename "$0")" >&2
    exit 1
  fi

  if [[ ! -d "$repo_path" ]]; then
    printf 'yunomi: directory not found: %s\n' "$repo_path" >&2
    exit 1
  fi

  # --- 0. Fetch the branch_sort option first (the branch retrieval command depends on it) ---
  local branch_sort
  branch_sort=$(get_option "@yunomi-branch-sort" "name")

  # --- 1. Retrieve all local branches ---
  local branches_raw
  if [[ "$branch_sort" == "mru" ]]; then
    branches_raw=$(git -C "$repo_path" for-each-ref \
      --sort=-committerdate \
      --format='%(refname:short)' refs/heads/ 2>/dev/null)
  else
    branches_raw=$(git -C "$repo_path" branch --format='%(refname:short)' 2>/dev/null)
  fi
  if [[ -z "$branches_raw" ]]; then
    printf '\t   BRANCH\n'
    return 0
  fi

  # Pin the default branch to the top of the list.
  # Moves the default branch (e.g. "main") to position 0 while preserving
  # the relative order of all other branches (from git branch or for-each-ref).
  local default_branch
  default_branch=$(get_default_branch "$repo_path")
  local _remaining=""
  local _found=false
  while IFS= read -r _line; do
    [[ -z "$_line" ]] && continue
    if [[ "$_found" == false && "$_line" == "$default_branch" ]]; then
      _found=true
    else
      _remaining+="${_line}"$'\n'
    fi
  done <<<"$branches_raw"
  if [[ "$_found" == true ]]; then
    branches_raw="${default_branch}"$'\n'"${_remaining%$'\n'}"
  fi

  if [[ "$quick" == true ]]; then
    _quick_branch_list "$branches_raw"
  else
    _full_branch_list "$repo_path" "$branches_raw"
  fi
}

# _quick_branch_list <branches_raw>
# Quick mode: branch name + active marker only (no status column).
_quick_branch_list() {
  local branches_raw="$1"
  local hashi_json="${YUNOMI_HASHI_JSON:-[]}"
  local active_branch=""
  if [[ -n "$hashi_json" ]]; then
    active_branch=$(printf '%s' "$hashi_json" | jq -r \
      '[.[] | select(.active == true) | .branch] | first // ""')
  fi

  printf '\t   BRANCH\n'

  local branch marker
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    marker=" "
    [[ "$branch" == "$active_branch" ]] && marker="*"
    printf '%s\t %s %s\n' "$branch" "$marker" "$branch"
  done <<<"$branches_raw"
}

# _full_branch_list <repo_path> <branches_raw>
# Full mode: branch name + active marker + status column with colors.
_full_branch_list() {
  local repo_path="$1"
  local branches_raw="$2"

  # --- 2. Obtain hashi list --json (reuse $YUNOMI_HASHI_JSON if available, otherwise run it) ---
  local hashi_json
  if [[ -n "${YUNOMI_HASHI_JSON:-}" ]]; then
    hashi_json="$YUNOMI_HASHI_JSON"
  else
    hashi_json=$(fetch_hashi_json "$repo_path")
  fi

  # --- 3. Expand hashi JSON into associative arrays with a single jq call ---
  declare -A hashi_active=()
  declare -A hashi_worktree=()
  local _branch _is_active _worktree_path
  while IFS=$'\t' read -r _branch _is_active _worktree_path; do
    [[ -z "$_branch" ]] && continue
    hashi_active["$_branch"]="$_is_active"
    hashi_worktree["$_branch"]="$_worktree_path"
  done < <(printf '%s' "$hashi_json" | jq -r '.[] | [.branch, (.active // false | tostring), (.worktree // "")] | @tsv')

  # --- 4. Fetch all remote tracking info in a single git for-each-ref call ---
  declare -A remote_indicators=()
  local _remote_track _remote_indicator
  while IFS=$'\t' read -r _branch _remote_track; do
    [[ -z "$_branch" ]] && continue
    _remote_indicator=""
    if [[ "$_remote_track" =~ ahead\ ([0-9]+) ]]; then
      _remote_indicator="↑${BASH_REMATCH[1]}"
    fi
    if [[ "$_remote_track" =~ behind\ ([0-9]+) ]]; then
      [[ -n "$_remote_indicator" ]] && _remote_indicator+=" "
      _remote_indicator+="↓${BASH_REMATCH[1]}"
    fi
    remote_indicators["$_branch"]="$_remote_indicator"
  done < <(git -C "$repo_path" for-each-ref --format='%(refname:short)	%(upstream:track,nobracket)' refs/heads/ 2>/dev/null)

  # --- 5. Retrieve the default branch and merged branches in bulk (outside the loop) ---
  local default_branch
  default_branch=$(get_default_branch "$repo_path")

  declare -A merged_set=()
  local _merged_line
  while IFS= read -r _merged_line; do
    _merged_line="${_merged_line#"${_merged_line%%[![:space:]]*}"}"
    [[ -n "$_merged_line" ]] && merged_set["$_merged_line"]=1
  done < <(git -C "$repo_path" branch --merged "$default_branch" 2>/dev/null)

  # --- 6. Generate data for all branches (2 passes for column width calculation) ---
  declare -a branch_names_arr=()
  declare -a status_strings_arr=()

  declare -a all_branches=()
  declare -a all_active=()
  declare -a all_remote_indicators=()
  declare -a all_main_statuses=()

  local branch active worktree remote_indicator main_status git_status is_merged
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue

    active="${hashi_active[$branch]:-false}"
    worktree="${hashi_worktree[$branch]:-}"
    remote_indicator="${remote_indicators[$branch]:-}"

    # Determine main status via get_main_status_var (no subshell)
    git_status=""
    if [[ -n "$worktree" ]]; then
      git_status=$(git -C "$worktree" status --short 2>/dev/null)
    fi
    is_merged="false"
    [[ -n "${merged_set[$branch]:-}" ]] && is_merged="true"

    # Skip get_main_status_var when no worktree and not merged (always "clean")
    if [[ -z "$worktree" && "$is_merged" == "false" ]]; then
      main_status="clean"
    else
      get_main_status_var main_status "$git_status" "$is_merged"
    fi

    all_branches+=("$branch")
    all_active+=("$active")
    all_remote_indicators+=("$remote_indicator")
    all_main_statuses+=("$main_status")

    branch_names_arr+=("$branch")
    if [[ -n "$remote_indicator" ]]; then
      status_strings_arr+=("${remote_indicator} ${main_status}")
    else
      status_strings_arr+=("$main_status")
    fi
  done <<<"$branches_raw"

  local count=${#all_branches[@]}
  if [[ $count -eq 0 ]]; then
    printf '\t   %-6s  %s\n' "BRANCH" "STATUS"
    return 0
  fi

  # --- 7. Calculate dynamic column widths ---
  local popup_cols="${YUNOMI_POPUP_COLS:-${COLUMNS:-80}}"
  if [[ ! "$popup_cols" =~ ^[0-9]+$ ]] || [[ "$popup_cols" -lt 10 ]] || [[ "$popup_cols" -gt 9999 ]]; then
    popup_cols=80
  fi
  local branch_names_list status_strings_list
  branch_names_list=$(printf '%s\n' "${branch_names_arr[@]}")
  status_strings_list=$(printf '%s\n' "${status_strings_arr[@]}")
  local widths branch_w status_w
  widths=$(calc_column_widths "$popup_cols" "$branch_names_list" "$status_strings_list")
  IFS='=' read -r _ branch_w <<<"${widths%%$'\n'*}"
  IFS='=' read -r _ status_w <<<"${widths##*$'\n'}"

  # --- 8. Output the header row ---
  printf '\t   %-*.*s  %s\n' "$branch_w" "$branch_w" "BRANCH" "STATUS"

  # --- 9. Output data rows (inlined _colorize_status to avoid subshell) ---
  local color_reset='\033[0m'
  local color_blue='\033[34m'
  local i marker main_color status_colored
  for ((i = 0; i < count; i++)); do
    branch="${all_branches[i]}"
    active="${all_active[i]}"
    remote_indicator="${all_remote_indicators[i]}"
    main_status="${all_main_statuses[i]}"

    marker=" "
    [[ "$active" == "true" ]] && marker="*"

    case "$main_status" in
      conflict) main_color='\033[31m' ;;
      changed) main_color='\033[33m' ;;
      merged) main_color='\033[32m' ;;
      clean) main_color='\033[2m' ;;
      *) main_color="" ;;
    esac

    if [[ -n "$remote_indicator" ]]; then
      printf -v status_colored '%b%s%b %b%s%b' \
        "$color_blue" "$remote_indicator" "$color_reset" \
        "$main_color" "$main_status" "$color_reset"
    else
      printf -v status_colored '%b%s%b' "$main_color" "$main_status" "$color_reset"
    fi

    printf '%s\t %s %-*.*s  %s\n' \
      "$branch" "$marker" "$branch_w" "$branch_w" "$branch" "$status_colored"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
source "$CURRENT_DIR/helpers.sh"

# show_repo_list
# Launches the screen 1 fzf UI.
# Outputs the selected ghq_path (e.g. github.com/org/repo) to stdout.
# Returns non-zero on Esc or abnormal fzf exit.
show_repo_list() {
  local repo_sort raw_list repo_list
  repo_sort=$(get_option "@yunomi-repo-sort" "name")
  raw_list=$(ghq list)

  if [[ "$repo_sort" == "mru" ]]; then
    local ghq_root
    ghq_root=$(ghq root)
    # Attach file_mtime to each ghq list entry and sort in descending order
    # sort -s (stable sort) preserves input order when mtime values are equal
    repo_list=$(while IFS= read -r entry; do
      mtime=$(file_mtime "${ghq_root}/${entry}/.git/HEAD")
      printf '%s\t%s\n' "$mtime" "$entry"
    done <<<"$raw_list" | sort -t$'\t' -k1,1rn -s | cut -f2- |
      awk '{ id=$0; $0=substr($0, index($0,"/")+1); printf "%s\t%s\n", id, $0 }')
  else
    # Default: preserve the original ghq list order (name sort)
    repo_list=$(printf '%s\n' "$raw_list" |
      awk '{ id=$0; $0=substr($0, index($0,"/")+1); printf "%s\t%s\n", id, $0 }')
  fi

  # Prepend the header row (separated by --header-lines 1)
  repo_list=$'\t'"ORG/REPO"$'\n'"$repo_list"

  local fzf_opts=()
  fzf_opts+=(--with-nth '2..')
  fzf_opts+=(--delimiter $'\t')
  fzf_opts+=(--layout reverse)
  fzf_opts+=(--header-lines 1)
  fzf_opts+=(--border rounded)
  fzf_opts+=(--border-label ' yunomi ')
  fzf_opts+=(--prompt 'Repo> ')
  fzf_opts+=(--ansi)
  fzf_opts+=(--highlight-line)
  fzf_opts+=(--info right)
  fzf_opts+=(--pointer '▍')
  fzf_opts+=(--color 'header:bold,footer:dim,pointer:bold,prompt:bold')
  fzf_opts+=(--footer '  enter:select  esc:close')
  fzf_opts+=(--print-query)
  fzf_opts+=(--bind 'enter:accept')
  fzf_opts+=(--bind 'esc:abort')

  fzf "${fzf_opts[@]}" <<<"$repo_list" |
    tail -n 1 |
    cut -f1
}

# show_branch_list <repo_path>
# Launches the screen 2 fzf UI.
# Fetches hashi list --json and exports it as YUNOMI_HASHI_JSON, then
# pipes yunomi-branch-list.sh output into fzf.
# Returns fzf's exit code as-is.
show_branch_list() {
  local repo_path="$1"

  # Fetch hashi list --json and export it as YUNOMI_HASHI_JSON
  # fzf's --preview (yunomi-preview.sh) reads this value
  export YUNOMI_HASHI_JSON
  YUNOMI_HASHI_JSON=$(fetch_hashi_json "$repo_path")

  # Shell-escape the paths (chawan style: store in variables via printf -v)
  local escaped_repo ESCAPED_SCRIPTS_DIR
  printf -v escaped_repo '%q' "$repo_path"
  printf -v ESCAPED_SCRIPTS_DIR '%q' "${YUNOMI_SCRIPTS_DIR:-$CURRENT_DIR}"

  # Fetch keybinding settings
  local bind_new bind_delete bind_rename
  bind_new=$(get_option "@yunomi-bind-new" "ctrl-o")
  validate_bind_key "$bind_new" || bind_new="ctrl-o"
  bind_delete=$(get_option "@yunomi-bind-delete" "ctrl-d")
  validate_bind_key "$bind_delete" || bind_delete="ctrl-d"
  bind_rename=$(get_option "@yunomi-bind-rename" "ctrl-r")
  validate_bind_key "$bind_rename" || bind_rename="ctrl-r"

  # Fetch preview settings
  local preview_enabled
  preview_enabled=$(get_option "@yunomi-preview" "on")

  # Build the footer string (pass already-fetched keybinding values to avoid duplicate tmux IPC calls)
  local footer
  footer=$(build_branch_footer "$bind_new" "$bind_delete" "$bind_rename")

  # fzf options array (common options)
  local fzf_opts=()
  fzf_opts+=(--with-nth '2..')
  fzf_opts+=(--delimiter $'\t')
  fzf_opts+=(--layout reverse)
  fzf_opts+=(--header-first)
  fzf_opts+=(--header-lines 1)
  fzf_opts+=(--border rounded)
  fzf_opts+=(--border-label ' yunomi ')
  fzf_opts+=(--header-border line)
  fzf_opts+=(--prompt 'Branch> ')
  fzf_opts+=(--ansi)
  fzf_opts+=(--highlight-line)
  fzf_opts+=(--info right)
  fzf_opts+=(--pointer '▍')
  fzf_opts+=(--color 'header:bold,footer:dim,pointer:bold,prompt:bold')
  fzf_opts+=(--footer "$footer")
  fzf_opts+=(--bind "enter:accept")
  fzf_opts+=(--bind "${bind_new}:transform:$ESCAPED_SCRIPTS_DIR/yunomi-fzf-action.sh new $escaped_repo")
  fzf_opts+=(--bind "${bind_delete}:transform:$ESCAPED_SCRIPTS_DIR/yunomi-fzf-action.sh remove $escaped_repo '{1}'")
  fzf_opts+=(--bind "${bind_rename}:transform:$ESCAPED_SCRIPTS_DIR/yunomi-fzf-action.sh rename $escaped_repo '{1}'")
  fzf_opts+=(--bind 'esc:abort')

  # Enable preview when @yunomi-preview is not "off"
  if [[ "$preview_enabled" != "off" ]]; then
    fzf_opts+=(--preview "$ESCAPED_SCRIPTS_DIR/yunomi-preview.sh '{1}' $escaped_repo")
    fzf_opts+=(--preview-window "right,50%,border-left")
    fzf_opts+=(--preview-label '')
    fzf_opts+=(--bind "focus:transform-preview-label:echo '{1}'")
  fi

  # Async reload of the full list on the load event (once only; unbind prevents infinite loop)
  fzf_opts+=(--bind "load:reload($ESCAPED_SCRIPTS_DIR/yunomi-branch-list.sh $escaped_repo)+unbind(load)")

  # Initial input uses --quick mode (branch name + active marker only) for immediate display
  local selected
  selected=$("${YUNOMI_SCRIPTS_DIR:-$CURRENT_DIR}/yunomi-branch-list.sh" --quick "$repo_path" |
    fzf "${fzf_opts[@]}") || return $?

  local branch_name
  branch_name=$(printf '%s' "$selected" | cut -f1)
  if [[ -n "$branch_name" ]]; then
    cd "$repo_path" && hashi switch -- "$branch_name"
  fi
}

# EXIT trap: clean up the exit flag file
_cleanup_exit_flag() {
  rm -f "$YUNOMI_EXIT_FLAG"
}

main() {
  # Verify required commands are available
  require_command hashi "https://github.com/wasabi0522/hashi" || exit 1
  require_command ghq "https://github.com/x-motemen/ghq" || exit 1
  require_command jq "https://jqlang.github.io/jq/" || exit 1

  # Create a unique exit flag file; YUNOMI_EXIT_FLAG must be in global scope for _cleanup
  YUNOMI_EXIT_FLAG=$(mktemp "${TMPDIR:-/tmp}/yunomi-exit-XXXXXXXXXX")
  rm -f "$YUNOMI_EXIT_FLAG"
  export YUNOMI_EXIT_FLAG
  trap '_cleanup_exit_flag' EXIT

  # Set YUNOMI_SCRIPTS_DIR (referenced by helper scripts inside fzf action strings)
  export YUNOMI_SCRIPTS_DIR="$CURRENT_DIR"

  # Cache ghq root once (avoid repeated subprocess calls in the loop)
  local ghq_root
  ghq_root=$(ghq root)

  # Screen transition loop
  while true; do
    # Screen 1: repository selection
    local ghq_path
    ghq_path=$(show_repo_list) || break # Esc or abnormal exit ends the loop

    # Also end the loop when ghq_path is empty (guard against show_repo_list returning a blank line)
    [[ -z "$ghq_path" ]] && break

    # Resolve the full path
    local repo_path
    repo_path="${ghq_root}/${ghq_path}"

    # Screen 2: branch operations
    local exit_code=0
    show_branch_list "$repo_path" || exit_code=$?

    # Exit the loop if the exit flag is set
    [[ -f "$YUNOMI_EXIT_FLAG" ]] && break

    # accept (hashi switch): fzf returns 0 or 1. Any exit code other than 130 ends the loop
    # Esc (return to screen 1): fzf returns 130. Continue the loop
    [[ $exit_code -ne 130 ]] && break
  done
}

# Apply set -euo pipefail only when executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

#!/usr/bin/env bash

# cd_repo <repo_path>
# Changes to the given repository directory with a standardized error message.
# Returns 1 if the directory cannot be accessed.
cd_repo() {
  local repo_path="$1"
  cd "$repo_path" || {
    printf 'yunomi: cannot cd to %s\n' "$repo_path" >&2
    return 1
  }
}

# validate_exit_flag_path <path>
# Validates that the exit flag path is a reasonable temp file path.
# Rejects empty paths, non-absolute paths, and paths containing "..".
validate_exit_flag_path() {
  local path="$1"
  if [[ -z "$path" || "$path" != /* || "$path" == *..* ]]; then
    return 1
  fi
}

# get_option <option_name> <default_value>
# Fetches a tmux user option.
# Returns the default value when tmux is unavailable (e.g. during tests).
get_option() {
  local option="$1"
  local default_value="$2"
  local value
  value=$(tmux show-option -gqv "$option" 2>/dev/null)
  if [[ -n "$value" ]]; then
    echo "$value"
  else
    echo "$default_value"
  fi
}

# version_ge <v1> <v2>
# Returns 0 if semantic version v1 >= v2.
# Compares each dot-separated field numerically.
version_ge() {
  local v1="$1" v2="$2"
  local IFS='.'
  read -ra parts1 <<<"$v1"
  read -ra parts2 <<<"$v2"

  local len=${#parts1[@]}
  [[ ${#parts2[@]} -gt $len ]] && len=${#parts2[@]}

  local i
  for ((i = 0; i < len; i++)); do
    local n1=$((10#${parts1[i]:-0}))
    local n2=$((10#${parts2[i]:-0}))
    if ((n1 > n2)); then
      return 0
    elif ((n1 < n2)); then
      return 1
    fi
  done
  return 0
}

# display_message [tmux display-message args...]
# Wrapper for tmux display-message.
display_message() {
  tmux display-message "$@"
}

# format_key_hint <key>
# Converts an fzf key name for footer display (ctrl- → C-).
# Examples: ctrl-o → C-o, ctrl-d → C-d
format_key_hint() {
  local key="$1"
  echo "${key/ctrl-/C-}"
}

# build_branch_footer [bind_new] [bind_delete] [bind_rename]
# Builds the screen 2 footer string.
# Accepts keybinding values as arguments, converts them via format_key_hint,
# and outputs the footer string to stdout.
# Passing pre-fetched values avoids duplicate tmux IPC calls.
#
# Example output (default settings):
#   "  enter:switch  C-o:new (from selected branch)  C-d:del  C-r:rename  esc:back"
build_branch_footer() {
  local bind_new="${1:-$(get_option "@yunomi-bind-new" "ctrl-o")}"
  local bind_delete="${2:-$(get_option "@yunomi-bind-delete" "ctrl-d")}"
  local bind_rename="${3:-$(get_option "@yunomi-bind-rename" "ctrl-r")}"
  printf '  enter:switch  %s:new (from selected branch)  %s:del  %s:rename  esc:back' \
    "$(format_key_hint "$bind_new")" \
    "$(format_key_hint "$bind_delete")" \
    "$(format_key_hint "$bind_rename")"
}

# calc_column_widths <popup_cols> <branch_names_newline_separated> <status_strings_newline_separated>
# Calculates dynamic column widths and outputs them to stdout.
#
# Arguments:
#   $1  popup_cols: number of columns in the popup (total available width)
#   $2  branch_names: newline-separated list of branch names
#   $3  status_strings: newline-separated list of status strings (plain display strings without ANSI codes)
#
# Output (2 lines on stdout):
#   branch_w=<number>
#   status_w=<number>
#
# Calculation method (per design.md "dynamic column widths"):
#   available = popup_cols - marker(3) - separator(2)
#   status_w  = maximum width of status strings (computed from all rows, fixed value)
#   branch_w  = min(available - status_w, max_branch_name_width)
#   Minimums: branch_w >= 1, status_w >= 1
#
# Note: branch names are ASCII-only, so ${#var} is sufficient for character width.
calc_column_widths() {
  local popup_cols="$1"
  local branch_names="$2"
  local status_strings="$3"

  # marker (3 chars: "* " or "  ") + separator (2 chars: "  ")
  local overhead=5
  local available=$((popup_cols - overhead))
  [[ $available -lt 2 ]] && available=2

  # Calculate the maximum width of status strings (ASCII-only, so ${#line} is sufficient)
  local status_w=0
  local line sw
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    sw=${#line}
    [[ $sw -gt $status_w ]] && status_w=$sw
  done <<<"$status_strings"
  [[ $status_w -lt 1 ]] && status_w=1

  # Calculate the maximum width of branch names (ASCII-only, so ${#line} is sufficient)
  local max_branch_w=0
  local bw
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    bw=${#line}
    [[ $bw -gt $max_branch_w ]] && max_branch_w=$bw
  done <<<"$branch_names"
  [[ $max_branch_w -lt 1 ]] && max_branch_w=1

  # branch_w = min(available - status_w, max_branch_name_width)
  local branch_w=$((available - status_w))
  [[ $branch_w -gt $max_branch_w ]] && branch_w=$max_branch_w
  [[ $branch_w -lt 1 ]] && branch_w=1

  printf 'branch_w=%d\n' "$branch_w"
  printf 'status_w=%d\n' "$status_w"
}

# require_bash_version <minimum_version>
# Check if the current bash version meets the minimum requirement.
# Returns 1 with an error message if the version is too old.
require_bash_version() {
  local min_version="$1"
  local current="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
  if ! version_ge "$current" "$min_version"; then
    printf 'yunomi: bash %s+ is required (current: %s). Install from https://www.gnu.org/software/bash/\n' \
      "$min_version" "$current"
    read -r -n 1 -s -p 'Press any key to close...'
    return 1
  fi
}

# require_command <cmd> <install_url>
# Check if a command exists. If not, print an error message and return 1.
require_command() {
  local cmd="$1" url="$2"
  if ! command -v "$cmd" &>/dev/null; then
    printf 'yunomi: %s command not found. Install from %s\n' "$cmd" "$url"
    read -r -n 1 -s -p 'Press any key to close...'
    return 1
  fi
}

# file_mtime <filepath>
# Outputs the file's modification time as a Unix timestamp (seconds) to stdout.
# macOS: stat -f %m
# Linux: stat -c %Y
# Outputs 0 if the file does not exist.
#
# Used by design.md "MRU sort".
# Estimates the last-used time of a repository from the mtime of its .git/HEAD file.
#
# Performance: _YUNOMI_STAT_ARGS_STR caches the platform-specific stat arguments
# after the first successful call to avoid repeated trial-and-error.
# Exported so child processes inherit the cached value.
file_mtime() {
  local filepath="$1"
  if [[ ! -e "$filepath" ]]; then
    echo 0
    return 0
  fi
  # Use cached format if available (validate against known-good values only)
  if [[ "${_YUNOMI_STAT_ARGS_STR:-}" == "-c %Y" || "${_YUNOMI_STAT_ARGS_STR:-}" == "-f %m" ]]; then
    local _stat_args
    read -ra _stat_args <<<"$_YUNOMI_STAT_ARGS_STR"
    if stat "${_stat_args[@]}" "$filepath" 2>/dev/null; then
      return 0
    fi
  fi
  # Linux stat uses -c %Y; macOS stat uses -f %m
  # Try Linux first: on GNU stat, -f means "file system status" and -f %m
  # would succeed with wrong output, so -c %Y (unambiguous) must come first.
  if stat -c %Y "$filepath" 2>/dev/null; then
    _YUNOMI_STAT_ARGS_STR="-c %Y"
    export _YUNOMI_STAT_ARGS_STR
    return 0
  fi
  if stat -f %m "$filepath" 2>/dev/null; then
    _YUNOMI_STAT_ARGS_STR="-f %m"
    export _YUNOMI_STAT_ARGS_STR
    return 0
  fi
  # Both failed (should not normally happen)
  echo 0
}

# get_default_branch <repo_path>
# Outputs the repository's default branch name to stdout.
# Falls back to "main" when origin/HEAD is not configured.
get_default_branch() {
  local repo_path="$1"
  local raw_ref
  raw_ref=$(git -C "$repo_path" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || raw_ref=""
  local default_branch="${raw_ref#origin/}"
  [[ -z "$default_branch" ]] && default_branch="main"
  echo "$default_branch"
}

# validate_bind_key <key>
# Validates that an fzf keybinding string consists only of alphanumerics and hyphens.
# Invalid keys (e.g. those containing shell metacharacters) are rejected to prevent injection.
validate_bind_key() {
  local key="$1"
  if [[ ! "$key" =~ ^[a-zA-Z0-9][-a-zA-Z0-9]*$ ]]; then
    printf 'yunomi: invalid bind key: %s\n' "$key" >&2
    return 1
  fi
}

# get_main_status <git_status_short> <merged_branches> <branch>
# Determines the main status (priority: conflict > changed > merged > clean).
# Wrapper around get_main_status_var that outputs to stdout (for callers that
# cannot use printf -v, e.g. yunomi-preview.sh).
#
# Arguments:
#   $1  git_status_short: output of `git status --short`. Empty string means no changes or no worktree
#   $2  merged_branches: output of `git branch --merged` (newline-separated)
#   $3  branch: branch name (used for merged check)
#
# Output: "conflict" | "changed" | "merged" | "clean"
get_main_status() {
  local git_status="$1"
  local merged_branches="$2"
  local branch="$3"

  # S-L2: Determine is_merged using exact-match while-read loop
  # (avoids regex metacharacter issues with branch names like "feature/test+1")
  local is_merged="false"
  local _line
  while IFS= read -r _line; do
    # Strip leading whitespace (git branch --merged indents with spaces)
    _line="${_line#"${_line%%[![:space:]]*}"}"
    if [[ "$_line" == "$branch" ]]; then
      is_merged="true"
      break
    fi
  done <<<"$merged_branches"

  local _gms_out
  get_main_status_var _gms_out "$git_status" "$is_merged"
  echo "$_gms_out"
}

# get_main_status_var <result_var> <git_status_short> <is_merged>
# Same logic as get_main_status but stores result via printf -v (no subshell).
#
# Arguments:
#   $1  result_var:       name of the caller's variable to receive the result
#   $2  git_status_short: output of `git status --short` (empty = no changes or no worktree)
#   $3  is_merged:        "true" if the branch is merged, "false" otherwise
#
# Priority (highest wins): conflict > changed > merged > clean
# Output: sets the named variable to "conflict" | "changed" | "merged" | "clean"
get_main_status_var() {
  local _result_var="$1"
  local _git_status="$2"
  local _is_merged="$3"
  local _result="clean"

  if [[ -n "$_git_status" ]]; then
    if [[ "$_git_status" =~ (^|$'\n')(U[UDA]|[DA]U|AA|DD) ]]; then
      _result="conflict"
    else
      _result="changed"
    fi
  elif [[ "$_is_merged" == "true" ]]; then
    _result="merged"
  fi

  printf -v "$_result_var" '%s' "$_result"
}

# fetch_hashi_json <repo_path>
# Runs hashi list --json in the given repo directory.
# Outputs JSON to stdout; falls back to "[]" on failure.
fetch_hashi_json() {
  local repo_path="$1"
  local result
  result=$(cd "$repo_path" 2>/dev/null && hashi list --json 2>/dev/null) || result="[]"
  printf '%s\n' "$result"
}

# print_separator [label]
# Outputs a section separator line.
# With label: "── <label> ──────..."
# Without label (or empty): "────────────..."
# The line is padded with ─ to match the terminal width (COLUMNS or 40).
print_separator() {
  local label="${1:-}"
  local width="${COLUMNS:-40}"
  if [[ -n "$label" ]]; then
    local prefix="── ${label} "
    local prefix_len=${#prefix}
    local fill_len=$((width - prefix_len - 2))
    [[ $fill_len -lt 2 ]] && fill_len=2
    local fill
    printf -v fill '%*s' "$fill_len" ''
    fill="${fill// /─}"
    printf '%s%s\n' "$prefix" "$fill"
  else
    local fill
    printf -v fill '%*s' "$width" ''
    fill="${fill// /─}"
    printf '%s\n' "$fill"
  fi
}

# read_input <prompt>
# Interactive line reader with ESC-to-cancel support.
# Reads a line character by character from stdin.
#
# Arguments:
#   $1  prompt - the prompt string to display
#
# Output:
#   Sets REPLY to the entered string.
#   Prints the prompt and echoes typed characters to stderr.
#
# Returns:
#   0 - user pressed Enter (REPLY contains the input, possibly empty)
#   1 - user pressed ESC or EOF (cancelled)
read_input() {
  local prompt="$1"
  local input=""
  local char next

  printf '%s' "$prompt" >&2
  REPLY=""

  while IFS= read -rsn1 char; do
    case "$char" in
      $'\e')
        # Distinguish standalone ESC from escape sequences (arrow keys, etc.)
        IFS= read -rsn1 -t 0.05 next || true
        if [[ -z "$next" ]]; then
          printf '\n' >&2
          return 1
        fi
        # Consume remaining escape sequence characters
        while IFS= read -rsn1 -t 0.05 _ || false; do :; done
        ;;
      '') # Enter (newline)
        printf '\n' >&2
        REPLY="$input"
        return 0
        ;;
      $'\x7f' | $'\b') # Backspace/Delete
        if [[ -n "$input" ]]; then
          input="${input%?}"
          printf '\b \b' >&2
        fi
        ;;
      *)
        input+="$char"
        printf '%s' "$char" >&2
        ;;
    esac
  done

  # EOF reached (e.g., pipe closed without newline)
  printf '\n' >&2
  return 1
}

# validate_popup_size <value>
# Validates that a popup dimension string matches the expected format.
# Accepts: digits optionally followed by "px" or "%". E.g. "80%", "120px", "80".
# Returns 0 on valid, 1 on invalid.
validate_popup_size() {
  local val="$1"
  if [[ ! "$val" =~ ^[0-9]+(px|%)?$ ]]; then
    return 1
  fi
}

#!/usr/bin/env bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bats_load_library bats-support
bats_load_library bats-assert

# shellcheck source=scripts/helpers.sh
source "$PROJECT_ROOT/scripts/helpers.sh"

# --- Mock helpers (ported from chawan) ---

# Creates MOCK_TMUX_CALLS temp file and exports it.
setup_mocks() {
  MOCK_TMUX_CALLS="$(mktemp)"
  export MOCK_TMUX_CALLS
}

# Removes all mock temp files.
teardown_mocks() {
  rm -f "${MOCK_TMUX_CALLS:-}"
}

# Installs a tmux mock that only records calls.
mock_tmux_record_only() {
  tmux() {
    printf '%s\n' "$*" >>"$MOCK_TMUX_CALLS"
  }
  export -f tmux
}

# Installs fzf and command -v mocks for testing yunomi.tmux.
# Default fzf version: 0.63.0
# NOTE: Overrides 'command' builtin to intercept 'command -v fzf'.
# Other flags (-V, -p, etc.) pass through to builtin.
#
# NOTE: This mock simulates the output of `fzf --version`.
# Adjust the output format (e.g. "0.63.0 (brew)" vs "0.63.0") to match
# the version check command implementation in yunomi.tmux.
mock_fzf_available() {
  MOCK_FZF_VERSION="${1:-0.63.0 (brew)}"
  export MOCK_FZF_VERSION

  fzf() {
    echo "$MOCK_FZF_VERSION"
  }
  export -f fzf

  command() {
    if [[ "$1" == "-v" && "$2" == "fzf" ]]; then
      return 0
    fi
    builtin command "$@"
  }
  export -f command
}

# --- yunomi-specific mocks ---

# mock_ghq: mock for ghq list / ghq root
#
# Usage:
#   mock_ghq                                             # use default repo list and root
#   mock_ghq $'github.com/a/b\ngithub.com/c/d'          # specify custom list (use $'...' for newlines)
#   MOCK_GHQ_LIST=$'github.com/a/b\ngithub.com/c/d'     # set env var first, then call
#   mock_ghq
#
# Environment variables:
#   MOCK_GHQ_LIST  output of ghq list (newline-separated). Uses default if unset
#   MOCK_GHQ_ROOT  output of ghq root. Defaults to /home/user/ghq
#
# Note: When passing strings with newlines as arguments, use the $'...' syntax.
#   Double-quoted "\n" becomes a literal backslash + n, not a newline.
#
mock_ghq() {
  MOCK_GHQ_LIST="${1:-github.com/wasabi0522/yunomi
github.com/wasabi0522/chawan
github.com/wasabi0522/hashi}"
  export MOCK_GHQ_LIST

  MOCK_GHQ_ROOT="${MOCK_GHQ_ROOT:-/home/user/ghq}"
  export MOCK_GHQ_ROOT

  ghq() {
    case "$1" in
      list)
        # printf '%s\n' appends a single newline at the end of the string,
        # but bats run trims trailing newlines so it does not affect lines[@] count
        printf '%s\n' "$MOCK_GHQ_LIST"
        ;;
      root)
        printf '%s\n' "$MOCK_GHQ_ROOT"
        ;;
      *)
        builtin command ghq "$@"
        ;;
    esac
  }
  export -f ghq
}

# mock_hashi: mock for hashi list --json / hashi switch / hashi new / hashi remove / hashi rename
#
# Usage:
#   mock_hashi                   # use default hashi list --json output
#   mock_hashi '[]'              # use empty JSON
#
# Environment variables:
#   MOCK_HASHI_JSON   output of hashi list --json. Uses the default value below if unset
#   MOCK_HASHI_CALLS  path to the call record file (expected to be a temp file created by setup_mocks)
#
# Default MOCK_HASHI_JSON:
#   main branch: active=true, is_default=true, no worktree key (assumes normal tmux window operation)
#     → per design.md spec: the key is omitted entirely when no worktree exists
#     → Note: the "delete active branch" test in yunomi-remove.sh targets the default
#       value main.
#   feature/test: has worktree, non-active (used for worktree display tests in branch list)
#
mock_hashi() {
  MOCK_HASHI_JSON="${1:-[{\"branch\":\"main\",\"window\":true,\"active\":true,\"is_default\":true,\"status\":\"ok\"},{\"branch\":\"feature/test\",\"worktree\":\"/repo/.worktrees/feature/test\",\"window\":false,\"active\":false,\"is_default\":false,\"status\":\"ok\"}]}"
  export MOCK_HASHI_JSON

  hashi() {
    if [[ -n "${MOCK_HASHI_CALLS:-}" ]]; then
      printf '%s\n' "$*" >>"$MOCK_HASHI_CALLS"
    fi
    case "$1" in
      list)
        # hashi list --json
        printf '%s\n' "$MOCK_HASHI_JSON"
        ;;
      switch | new | remove | rename)
        # exit successfully (default behavior)
        return 0
        ;;
      *)
        builtin command hashi "$@"
        ;;
    esac
  }
  export -f hashi
}

# mock_git: mock for git -C ... branch / rev-list / status / log commands
#
# Usage:
#   mock_git                     # use default git output
#
# Environment variables:
#   MOCK_GIT_BRANCHES       output of git branch (newline-separated). Default: "main\nfeature/test"
#   MOCK_GIT_MERGED         output of git branch --merged. Default: "  main"
#   MOCK_GIT_REVLIST        output of git rev-list --left-right --count. Default: "0<TAB>0" (tab-separated)
#   MOCK_GIT_STATUS_SHORT   output of git status --short. Default: empty string (no changes)
#   MOCK_GIT_LOG            output of git log --oneline. Default: 5 fixed sample commits
#   MOCK_GIT_DEFAULT_BRANCH output of git symbolic-ref. Default: "main"
#   MOCK_GIT_TRACKING   output of git for-each-ref %(upstream:track,nobracket) (tab-separated).
#                        Auto-generated from MOCK_GIT_BRANCHES with empty tracking info if unset
#   MOCK_GIT_CALLS          path to the call record file
#
mock_git() {
  MOCK_GIT_BRANCHES="${MOCK_GIT_BRANCHES:-main
feature/test}"
  export MOCK_GIT_BRANCHES

  MOCK_GIT_MERGED="${MOCK_GIT_MERGED:-  main}"
  export MOCK_GIT_MERGED

  # git rev-list --left-right --count output is tab-separated ("ahead\tbehind")
  # Default: $'0\t0' (ahead=0, behind=0)
  MOCK_GIT_REVLIST="${MOCK_GIT_REVLIST:-$(printf '0\t0')}"
  export MOCK_GIT_REVLIST

  MOCK_GIT_STATUS_SHORT="${MOCK_GIT_STATUS_SHORT:-}"
  export MOCK_GIT_STATUS_SHORT

  MOCK_GIT_LOG="${MOCK_GIT_LOG:-abc1234 feat: add login form
def5678 refactor: extract auth
ghi9012 fix: session timeout
1a2b3c4 init: scaffold page
5d6e7f8 chore: add dependencies}"
  export MOCK_GIT_LOG

  MOCK_GIT_DEFAULT_BRANCH="${MOCK_GIT_DEFAULT_BRANCH:-main}"
  export MOCK_GIT_DEFAULT_BRANCH

  git() {
    if [[ -n "${MOCK_GIT_CALLS:-}" ]]; then
      printf '%s\n' "$*" >>"$MOCK_GIT_CALLS"
    fi
    # Parse arguments and return appropriate output
    # Skip -C <path> flag to identify the subcommand
    local args=("$@")
    local subcmd=""
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
      if [[ "${args[$i]}" == "-C" ]]; then
        i=$((i + 2))
        continue
      fi
      subcmd="${args[$i]}"
      break
    done

    case "$subcmd" in
      branch)
        # Branch on 3 patterns: --merged, --format, and default
        if [[ " ${args[*]} " == *" --merged "* ]]; then
          printf '%s\n' "$MOCK_GIT_MERGED"
        elif [[ "${args[*]}" == *"--format"* ]]; then
          # no indent when --format is specified
          printf '%s\n' "$MOCK_GIT_BRANCHES"
        else
          # default git branch outputs with leading spaces
          printf '%s\n' "$MOCK_GIT_BRANCHES" | sed 's/^/  /'
        fi
        ;;
      rev-parse)
        # Used to check remote branch existence
        if [[ "${MOCK_GIT_REMOTE_EXISTS:-true}" == "false" ]]; then
          return 1
        fi
        return 0
        ;;
      rev-list)
        printf '%s\n' "$MOCK_GIT_REVLIST"
        ;;
      status)
        printf '%s\n' "$MOCK_GIT_STATUS_SHORT"
        ;;
      log)
        printf '%s\n' "$MOCK_GIT_LOG"
        ;;
      symbolic-ref)
        # Has "origin/" prefix. Callers must strip it with sed 's|^origin/||'
        printf 'origin/%s\n' "$MOCK_GIT_DEFAULT_BRANCH"
        ;;
      for-each-ref)
        if [[ "${args[*]}" == *"upstream"* ]]; then
          # Remote tracking info format (upstream:track,nobracket)
          if [[ -n "${MOCK_GIT_TRACKING:-}" ]]; then
            printf '%s\n' "$MOCK_GIT_TRACKING"
          else
            # Default: append empty tracking info to each branch
            local _line
            while IFS= read -r _line; do
              [[ -n "$_line" ]] && printf '%s\t\n' "$_line"
            done <<<"$MOCK_GIT_BRANCHES"
          fi
        else
          printf '%s\n' "$MOCK_GIT_BRANCHES"
        fi
        ;;
      *)
        builtin command git "$@"
        ;;
    esac
  }
  export -f git
}

# mock_jq: mock for jq
#
# Usage:
#   mock_jq "output_string"      # set jq output to a fixed value
#   mock_jq                      # default: returns empty string
#
# Environment variables:
#   MOCK_JQ_OUTPUT  output of jq. Empty string if unset
#
# Note: Does not emulate actual jq filter processing.
# Set MOCK_JQ_OUTPUT to the expected output for each test.
#
mock_jq() {
  MOCK_JQ_OUTPUT="${1:-}"
  export MOCK_JQ_OUTPUT

  jq() {
    printf '%s\n' "$MOCK_JQ_OUTPUT"
  }
  export -f jq
}

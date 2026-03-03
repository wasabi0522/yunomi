#!/usr/bin/env bats

load 'test_helper'

# per-test setup: source helpers.sh and yunomi-branch-list.sh
setup() {
  setup_mocks
  mock_tmux_record_only
  # shellcheck source=scripts/yunomi-branch-list.sh
  source "$PROJECT_ROOT/scripts/yunomi-branch-list.sh"
  COLUMNS=80
  export COLUMNS
  # start with jq mock unset (set individually per test)
  unset YUNOMI_HASHI_JSON
  # create a temp directory to satisfy the directory existence check
  MOCK_REPO_DIR="$(mktemp -d)"
  export MOCK_REPO_DIR
}

teardown() {
  teardown_mocks
  rm -rf "${MOCK_REPO_DIR:-}"
}

# ---------------------------------------------------------------------------
# Header line format
# ---------------------------------------------------------------------------

@test "branch-list: header line starts with tab and contains BRANCH and STATUS" {
  mock_git
  mock_hashi
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  # First line is the header
  local header="${lines[0]}"
  # Must start with "\t" (bats lines preserve leading tabs)
  [[ "$header" == $'\t'* ]]
  [[ "$header" == *"BRANCH"* ]]
  [[ "$header" == *"STATUS"* ]]
}

@test "branch-list: header field 1 (before tab) is empty string" {
  mock_git
  mock_hashi
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  local header="${lines[0]}"
  local field1
  field1=$(echo "$header" | cut -f1)
  [ "$field1" = "" ]
}

# ---------------------------------------------------------------------------
# Data line format
# ---------------------------------------------------------------------------

@test "branch-list: data line has branch name in field 1 (before tab)" {
  MOCK_GIT_BRANCHES="main"
  mock_git
  mock_hashi
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  # Second line is a data line (first line is the header)
  local data_line="${lines[1]}"
  local field1
  field1=$(echo "$data_line" | cut -f1)
  [ "$field1" = "main" ]
}

@test "branch-list: data line field 2 (display string) contains branch name" {
  MOCK_GIT_BRANCHES="main"
  mock_git
  mock_hashi
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  local data_line="${lines[1]}"
  local field2
  field2=$(echo "$data_line" | cut -f2-)
  [[ "$field2" == *"main"* ]]
}

@test "branch-list: outputs one data line per branch" {
  MOCK_GIT_BRANCHES=$'main\nfeature/test'
  mock_git
  mock_hashi
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  # 1 header line + 2 data lines = 3 lines
  [ "${#lines[@]}" -eq 3 ]
}

# ---------------------------------------------------------------------------
# Active branch marker ("*")
# ---------------------------------------------------------------------------

@test "branch-list: active branch has '*' marker in display string" {
  MOCK_GIT_BRANCHES="main"
  MOCK_GIT_MERGED="  main"
  mock_git

  export YUNOMI_HASHI_JSON='[{"branch":"main","window":true,"active":true,"is_default":true,"status":"ok"}]'
  mock_jq $'main\ttrue\t'

  run main "$MOCK_REPO_DIR"
  assert_success

  local data_line="${lines[1]}"
  local field2
  field2=$(echo "$data_line" | cut -f2-)
  [[ "$field2" == *"*"* ]]
}

@test "branch-list: inactive branch has space marker (no '*') in display string" {
  MOCK_GIT_BRANCHES="feature/test"
  mock_git

  export YUNOMI_HASHI_JSON='[{"branch":"feature/test","window":false,"active":false,"is_default":false,"status":"ok"}]'
  mock_jq $'feature/test\tfalse\t'

  run main "$MOCK_REPO_DIR"
  assert_success

  local data_line="${lines[1]}"
  local field2
  field2=$(echo "$data_line" | cut -f2-)
  [[ "$field2" != *"*"* ]]
}

# ---------------------------------------------------------------------------
# Dynamic column width accuracy
# ---------------------------------------------------------------------------

@test "branch-list: calc_column_widths is called with correct data (integration)" {
  # Integration test to verify that column widths are calculated in the main flow
  MOCK_GIT_BRANCHES=$'main\nfeature/test'
  MOCK_GIT_MERGED="  main"
  mock_git

  export YUNOMI_HASHI_JSON='[{"branch":"main","window":true,"active":true,"is_default":true,"status":"ok"},{"branch":"feature/test","window":false,"active":false,"is_default":false,"status":"ok"}]'
  mock_jq $'main\ttrue\t\nfeature/test\tfalse\t'

  export YUNOMI_POPUP_COLS=80
  run main "$MOCK_REPO_DIR"
  unset YUNOMI_POPUP_COLS
  assert_success
  # At least header + 2 data lines are output
  [ "${#lines[@]}" -ge 3 ]
  # Header contains BRANCH and STATUS
  [[ "${lines[0]}" == *"BRANCH"* ]]
  [[ "${lines[0]}" == *"STATUS"* ]]
}

# ---------------------------------------------------------------------------
# Long branch name truncation
# ---------------------------------------------------------------------------

@test "branch-list: long branch name is truncated to branch_w" {
  local long_branch="feature/very-very-very-long-branch-name"
  MOCK_GIT_BRANCHES="$long_branch"
  MOCK_GIT_MERGED=""
  mock_git
  mock_hashi '[]'
  mock_jq ""

  # Force popup width via YUNOMI_POPUP_COLS (COLUMNS may be overwritten by bash)
  export YUNOMI_POPUP_COLS=30
  run main "$MOCK_REPO_DIR"
  unset YUNOMI_POPUP_COLS
  assert_success

  local data_line="${lines[1]}"
  local field2
  field2=$(echo "$data_line" | cut -f2-)
  # Remove ANSI codes and check visible character count
  local visible_len
  visible_len=$(printf '%s' "$field2" | sed 's/\x1b\[[0-9;]*m//g' | wc -m | tr -d ' ')
  # Verify visible character count (including newline) is within YUNOMI_POPUP_COLS+2
  # field2 = " " + branch_name(branch_w) + "  " + status
  # branch_w = min(popup_cols - 5 - status_w, max_branch_w) = min(30-5-5, 38) = 20
  # visible_len = 1(marker) + 20(branch) + 2(sep) + 5(status) + 1(newline) = 29
  [ "$visible_len" -le 32 ]
}

# ---------------------------------------------------------------------------
# Error handling when no arguments given
# ---------------------------------------------------------------------------

@test "branch-list: exits with error when no repo_path given" {
  run main ""
  assert_failure
}

# ---------------------------------------------------------------------------
# YUNOMI_HASHI_JSON environment variable fallback
# ---------------------------------------------------------------------------

@test "branch-list: uses YUNOMI_HASHI_JSON when set" {
  MOCK_GIT_BRANCHES="main"
  MOCK_GIT_MERGED="  main"
  mock_git
  mock_jq $'main\ttrue\t'

  # hashi should not be called (since YUNOMI_HASHI_JSON is set)
  local hashi_called_file
  hashi_called_file=$(mktemp)
  export hashi_called_file
  hashi() {
    printf 'called' >"$hashi_called_file"
    printf '[{"branch":"main","window":true,"active":true,"is_default":true,"status":"ok"}]\n'
  }
  export -f hashi

  export YUNOMI_HASHI_JSON='[{"branch":"main","window":true,"active":true,"is_default":true,"status":"ok"}]'
  run main "$MOCK_REPO_DIR"
  assert_success

  # verify hashi was not called
  [[ ! -s "$hashi_called_file" ]]
  rm -f "$hashi_called_file"
}

# ---------------------------------------------------------------------------
# --quick mode
# ---------------------------------------------------------------------------

@test "branch-list: empty branch list outputs header only" {
  mock_git
  # Override after mock_git (${:-} treats empty string as unset and applies default)
  MOCK_GIT_BRANCHES=""
  export MOCK_GIT_BRANCHES
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"BRANCH"* ]]
}

@test "branch-list: remote ahead/behind is shown in status" {
  MOCK_GIT_BRANCHES="main"
  MOCK_GIT_MERGED=""
  MOCK_GIT_TRACKING=$'main\tahead 2, behind 3'
  mock_git

  export YUNOMI_HASHI_JSON='[{"branch":"main","worktree":"/repo","active":true,"is_default":true}]'
  mock_jq $'main\ttrue\t/repo'

  run main "$MOCK_REPO_DIR"
  assert_success

  # Data line should contain remote indicators
  local data_line="${lines[1]}"
  [[ "$data_line" == *"↑2"* ]]
  [[ "$data_line" == *"↓3"* ]]
}

# ---------------------------------------------------------------------------
# --quick mode
# ---------------------------------------------------------------------------

@test "branch-list: --quick mode outputs header with BRANCH only (no STATUS)" {
  MOCK_GIT_BRANCHES="main"
  mock_git
  mock_jq ""

  run main --quick "$MOCK_REPO_DIR"
  assert_success

  local header="${lines[0]}"
  [[ "$header" == *"BRANCH"* ]]
  [[ "$header" != *"STATUS"* ]]
}

@test "branch-list: --quick mode outputs branch names without status column" {
  MOCK_GIT_BRANCHES=$'main\nfeature/test'
  mock_git
  mock_jq ""

  run main --quick "$MOCK_REPO_DIR"
  assert_success

  # Header + 2 data lines = 3 lines
  [ "${#lines[@]}" -eq 3 ]
  # Data line contains the branch name
  local field1
  field1=$(printf '%s' "${lines[1]}" | cut -f1)
  [ "$field1" = "main" ]
  # Must not contain status strings
  [[ "${lines[1]}" != *"clean"* ]]
  [[ "${lines[1]}" != *"changed"* ]]
  [[ "${lines[1]}" != *"merged"* ]]
  [[ "${lines[1]}" != *"conflict"* ]]
}

@test "branch-list: --quick mode shows active marker" {
  MOCK_GIT_BRANCHES="main"
  mock_git

  export YUNOMI_HASHI_JSON='[{"branch":"main","active":true}]'
  mock_jq "main"

  run main --quick "$MOCK_REPO_DIR"
  assert_success

  local field2
  field2=$(printf '%s' "${lines[1]}" | cut -f2-)
  [[ "$field2" == *"*"* ]]
}

@test "branch-list: --quick mode respects branch-sort mru option" {
  tmux() {
    if [[ "$*" == *"@yunomi-branch-sort"* ]]; then
      echo "mru"
    else
      printf '%s\n' "$*" >>"$MOCK_TMUX_CALLS"
    fi
  }
  export -f tmux

  MOCK_GIT_BRANCHES=$'feature/z\nmain'
  MOCK_GIT_CALLS="$(mktemp)"
  export MOCK_GIT_CALLS
  mock_git
  mock_jq ""

  run main --quick "$MOCK_REPO_DIR"
  assert_success

  grep -q 'for-each-ref' "$MOCK_GIT_CALLS"
  rm -f "$MOCK_GIT_CALLS"
}

# ---------------------------------------------------------------------------
# Default branch pinned to top
# ---------------------------------------------------------------------------

@test "branch-list: default branch is pinned to top" {
  MOCK_GIT_BRANCHES=$'alpha\nmain\nzeta'
  mock_git
  mock_hashi '[]'
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  # First data line (lines[1]) field1 must be "main"
  local first_data
  first_data=$(printf '%s' "${lines[1]}" | cut -f1)
  [ "$first_data" = "main" ]
}

@test "branch-list: default branch pinning preserves order of remaining branches" {
  MOCK_GIT_BRANCHES=$'alpha\nmain\nzeta'
  mock_git
  mock_hashi '[]'
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  local b1 b2 b3
  b1=$(printf '%s' "${lines[1]}" | cut -f1)
  b2=$(printf '%s' "${lines[2]}" | cut -f1)
  b3=$(printf '%s' "${lines[3]}" | cut -f1)
  [ "$b1" = "main" ]
  [ "$b2" = "alpha" ]
  [ "$b3" = "zeta" ]
}

@test "branch-list: --quick mode also pins default branch to top" {
  MOCK_GIT_BRANCHES=$'alpha\nmain\nzeta'
  mock_git
  mock_jq ""

  run main --quick "$MOCK_REPO_DIR"
  assert_success

  local first_data
  first_data=$(printf '%s' "${lines[1]}" | cut -f1)
  [ "$first_data" = "main" ]
}

# ---------------------------------------------------------------------------
# branch-sort option
# ---------------------------------------------------------------------------

# default (name) uses git branch --format output order
@test "branch-sort: default (name) uses git branch --format output order" {
  # @yunomi-branch-sort unset -> mock_tmux_record_only returns empty -> get_option falls back to "name"
  # git branch --format output order (alpha, beta, gamma) is directly reflected in data line order
  MOCK_GIT_BRANCHES=$'alpha\nbeta\ngamma'
  mock_git
  mock_hashi '[]'
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  # Header line (lines[0]) + 3 data lines
  [ "${#lines[@]}" -eq 4 ]
  # Verify the order of field 1 (branch name) in data lines
  local b1 b2 b3
  b1=$(printf '%s' "${lines[1]}" | cut -f1)
  b2=$(printf '%s' "${lines[2]}" | cut -f1)
  b3=$(printf '%s' "${lines[3]}" | cut -f1)
  [ "$b1" = "alpha" ]
  [ "$b2" = "beta" ]
  [ "$b3" = "gamma" ]
}

# mru sort uses for-each-ref --sort=-committerdate
@test "branch-sort: mru uses for-each-ref --sort=-committerdate" {
  # Replace tmux mock to return @yunomi-branch-sort=mru
  tmux() {
    if [[ "$*" == *"@yunomi-branch-sort"* ]]; then
      echo "mru"
    else
      printf '%s\n' "$*" >>"$MOCK_TMUX_CALLS"
    fi
  }
  export -f tmux

  MOCK_GIT_BRANCHES=$'feature/z\nmain'
  MOCK_GIT_CALLS="$(mktemp)"
  export MOCK_GIT_CALLS
  mock_git
  mock_hashi '[]'
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  # for-each-ref must be recorded in MOCK_GIT_CALLS
  grep -q 'for-each-ref' "$MOCK_GIT_CALLS"
  rm -f "$MOCK_GIT_CALLS"
}

# mru sort preserves for-each-ref output order in data lines
@test "branch-sort: mru preserves for-each-ref output order in data lines" {
  # Replace tmux mock to return @yunomi-branch-sort=mru
  tmux() {
    if [[ "$*" == *"@yunomi-branch-sort"* ]]; then
      echo "mru"
    else
      printf '%s\n' "$*" >>"$MOCK_TMUX_CALLS"
    fi
  }
  export -f tmux

  # MRU order returned by for-each-ref (most recently used first)
  MOCK_GIT_BRANCHES=$'feature/recent\nmain\nfeature/old'
  mock_git
  mock_hashi '[]'
  mock_jq ""

  run main "$MOCK_REPO_DIR"
  assert_success

  # Header line + 3 data lines
  [ "${#lines[@]}" -eq 4 ]
  # Default branch (main) is pinned to top; remaining branches preserve MRU order
  local b1 b2 b3
  b1=$(printf '%s' "${lines[1]}" | cut -f1)
  b2=$(printf '%s' "${lines[2]}" | cut -f1)
  b3=$(printf '%s' "${lines[3]}" | cut -f1)
  [ "$b1" = "main" ]
  [ "$b2" = "feature/recent" ]
  [ "$b3" = "feature/old" ]
}

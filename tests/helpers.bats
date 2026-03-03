#!/usr/bin/env bats

load 'test_helper'

# ---------------------------------------------------------------------------
# get_option
# ---------------------------------------------------------------------------

@test "get_option: returns default when tmux option is unset" {
  # when tmux show-option -gqv returns empty string (unset)
  tmux() {
    echo ""
  }
  export -f tmux

  run get_option "@yunomi-key" "G"
  assert_success
  assert_output "G"
}

@test "get_option: returns tmux option value when set" {
  tmux() {
    printf '%s\n' "$*" >>"$MOCK_TMUX_CALLS"
    echo "R"
  }
  export -f tmux

  run get_option "@yunomi-key" "G"
  assert_success
  assert_output "R"
}

@test "get_option: returns default for popup-width when unset" {
  tmux() {
    echo ""
  }
  export -f tmux

  run get_option "@yunomi-popup-width" "80%"
  assert_success
  assert_output "80%"
}

@test "get_option: returns custom popup-width when set" {
  tmux() {
    echo "90%"
  }
  export -f tmux

  run get_option "@yunomi-popup-width" "80%"
  assert_success
  assert_output "90%"
}

# ---------------------------------------------------------------------------
# version_ge
# ---------------------------------------------------------------------------

@test "version_ge: equal versions returns 0" {
  run version_ge "3.3" "3.3"
  assert_success
}

@test "version_ge: v1 greater than v2 returns 0" {
  run version_ge "3.4" "3.3"
  assert_success
}

@test "version_ge: v1 less than v2 returns 1" {
  run version_ge "3.2" "3.3"
  assert_failure
}

@test "version_ge: major version greater returns 0" {
  run version_ge "4.0" "3.9"
  assert_success
}

@test "version_ge: major version less returns 1" {
  run version_ge "2.9" "3.0"
  assert_failure
}

@test "version_ge: three-part version equal returns 0" {
  run version_ge "0.63.0" "0.63.0"
  assert_success
}

@test "version_ge: three-part v1 greater than v2 returns 0" {
  run version_ge "0.63.1" "0.63.0"
  assert_success
}

@test "version_ge: three-part v1 less than v2 returns 1" {
  run version_ge "0.62.9" "0.63.0"
  assert_failure
}

@test "version_ge: two-part vs three-part with missing field treated as 0" {
  run version_ge "3.3" "3.3.0"
  assert_success
}

# ---------------------------------------------------------------------------
# display_message
# ---------------------------------------------------------------------------

@test "display_message: calls tmux display-message with given args" {
  setup_mocks
  mock_tmux_record_only

  display_message "hello yunomi"

  run cat "$MOCK_TMUX_CALLS"
  assert_success
  assert_output --partial "display-message hello yunomi"

  teardown_mocks
}

@test "display_message: passes multiple args to tmux" {
  setup_mocks
  mock_tmux_record_only

  display_message -d 3000 "warning"

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "display-message -d 3000 warning"

  teardown_mocks
}

# ---------------------------------------------------------------------------
# format_key_hint
# ---------------------------------------------------------------------------

@test "format_key_hint: ctrl-o converts to C-o" {
  run format_key_hint "ctrl-o"
  assert_success
  assert_output "C-o"
}

@test "format_key_hint: ctrl-d converts to C-d" {
  run format_key_hint "ctrl-d"
  assert_success
  assert_output "C-d"
}

@test "format_key_hint: ctrl-r converts to C-r" {
  run format_key_hint "ctrl-r"
  assert_success
  assert_output "C-r"
}

@test "format_key_hint: non-ctrl key is unchanged" {
  run format_key_hint "enter"
  assert_success
  assert_output "enter"
}

@test "format_key_hint: ctrl-n converts to C-n" {
  run format_key_hint "ctrl-n"
  assert_success
  assert_output "C-n"
}

# ---------------------------------------------------------------------------
# build_branch_footer
# ---------------------------------------------------------------------------

@test "build_branch_footer: default keys produce correct footer" {
  # default settings: ctrl-o, ctrl-d, ctrl-r
  tmux() {
    echo ""
  }
  export -f tmux

  run build_branch_footer
  assert_success
  assert_output "  enter:switch  C-o:new (from selected branch)  C-d:del  C-r:rename  esc:back"
}

@test "build_branch_footer: custom keys are reflected in footer" {
  # custom settings: ctrl-n, ctrl-x, ctrl-e
  tmux() {
    case "$*" in
      *"@yunomi-bind-new"*)
        echo "ctrl-n"
        ;;
      *"@yunomi-bind-delete"*)
        echo "ctrl-x"
        ;;
      *"@yunomi-bind-rename"*)
        echo "ctrl-e"
        ;;
      *)
        echo ""
        ;;
    esac
  }
  export -f tmux

  run build_branch_footer
  assert_success
  assert_output "  enter:switch  C-n:new (from selected branch)  C-x:del  C-e:rename  esc:back"
}

@test "build_branch_footer: contains enter:switch" {
  tmux() { echo ""; }
  export -f tmux

  run build_branch_footer
  assert_output --partial "enter:switch"
}

@test "build_branch_footer: contains esc:back" {
  tmux() { echo ""; }
  export -f tmux

  run build_branch_footer
  assert_output --partial "esc:back"
}

# ---------------------------------------------------------------------------
# calc_column_widths
# ---------------------------------------------------------------------------

@test "calc_column_widths: basic width distribution" {
  # popup_cols=80, branches=["main","feature/login"], statuses=["clean","changed"]
  local branch_names
  branch_names=$'main\nfeature/login'
  local status_strings
  status_strings=$'clean\nchanged'

  run calc_column_widths 80 "$branch_names" "$status_strings"
  assert_success

  # output must contain branch_w= and status_w=
  assert_output --partial "branch_w="
  assert_output --partial "status_w="
}

@test "calc_column_widths: status_w equals max status string length" {
  local branch_names="main"
  # "↑2 changed" is 10 characters
  local status_strings="↑2 changed"

  run calc_column_widths 80 "$branch_names" "$status_strings"
  assert_success

  # must contain status_w=10
  assert_output --partial "status_w=10"
}

@test "calc_column_widths: branch_w does not exceed max branch name length" {
  # longest branch name is "main" (4 characters)
  local branch_names
  branch_names=$'main\nabc'
  local status_strings="clean"

  run calc_column_widths 80 "$branch_names" "$status_strings"
  assert_success

  # branch_w <= 4
  local branch_w
  branch_w=$(echo "$output" | grep 'branch_w=' | cut -d= -f2)
  [ "$branch_w" -le 4 ]
}

@test "calc_column_widths: available width is popup_cols minus overhead(5)" {
  # popup_cols=20, overhead=5, available=15
  # max status width=5("clean"), branch_w=min(15-5, max_branch)=min(10, 4)=4
  local branch_names="main"
  local status_strings="clean"

  run calc_column_widths 20 "$branch_names" "$status_strings"
  assert_success

  local branch_w
  branch_w=$(echo "$output" | grep 'branch_w=' | cut -d= -f2)
  local status_w
  status_w=$(echo "$output" | grep 'status_w=' | cut -d= -f2)

  # status_w=5 (length of "clean")
  [ "$status_w" -eq 5 ]
  # branch_w=min(15-5, 4)=4
  [ "$branch_w" -eq 4 ]
}

@test "calc_column_widths: branch_w is at least 1" {
  # ensures minimum value of 1 even for extremely narrow widths
  local branch_names="main"
  local status_strings="very-long-status-string"

  run calc_column_widths 10 "$branch_names" "$status_strings"
  assert_success

  local branch_w
  branch_w=$(echo "$output" | grep 'branch_w=' | cut -d= -f2)
  [ "$branch_w" -ge 1 ]
}

@test "calc_column_widths: long branch name is capped at available minus status_w" {
  # available = 80 - 5 = 75, status_w = 5 ("clean")
  # max_branch_w = 51 (very-long-branch-name...)
  # branch_w = min(75 - 5, 51) = min(70, 51) = 51
  local long_branch="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"  # 51 characters
  local branch_names="$long_branch"
  local status_strings="clean"

  run calc_column_widths 80 "$branch_names" "$status_strings"
  assert_success

  local branch_w
  branch_w=$(echo "$output" | grep 'branch_w=' | cut -d= -f2)
  # branch_w = min(70, 51) = 51
  [ "$branch_w" -eq 51 ]
}

@test "calc_column_widths: uses largest branch name across multiple branches" {
  # longest branch name: "feature/very-long-branch" (24 characters)
  local branch_names
  branch_names=$'main\nfeature/very-long-branch\nfix'
  local status_strings
  status_strings=$'clean\nchanged\nmerged'

  run calc_column_widths 80 "$branch_names" "$status_strings"
  assert_success

  local branch_w
  branch_w=$(echo "$output" | grep 'branch_w=' | cut -d= -f2)
  # branch_w = min(available-status_w, 24)
  # status_w = max(5,7,6) = 7 ("changed")
  # available = 75, branch_w = min(75-7, 24) = min(68, 24) = 24
  [ "$branch_w" -eq 24 ]
}

# ---------------------------------------------------------------------------
# file_mtime
# ---------------------------------------------------------------------------

@test "file_mtime: returns 0 for non-existent file" {
  unset _YUNOMI_STAT_ARGS_STR
  run file_mtime "/tmp/yunomi-test-nonexistent-file-$$"
  assert_success
  assert_output "0"
}

@test "file_mtime: macOS stat path (stat -f %m)" {
  unset _YUNOMI_STAT_ARGS_STR
  # mock the stat command to simulate macOS stat -f %m behavior
  stat() {
    if [[ "$1" == "-f" && "$2" == "%m" ]]; then
      echo "1700000000"
      return 0
    fi
    return 1
  }
  export -f stat

  # use a temp file to pass the -e check so it is treated as an existing file
  local tmpfile
  tmpfile=$(mktemp)
  run file_mtime "$tmpfile"
  rm -f "$tmpfile"

  assert_success
  assert_output "1700000000"
}

@test "file_mtime: Linux stat path (stat -c %Y) when macOS stat fails" {
  unset _YUNOMI_STAT_ARGS_STR
  # macOS stat fails, Linux stat succeeds
  stat() {
    if [[ "$1" == "-f" && "$2" == "%m" ]]; then
      return 1
    fi
    if [[ "$1" == "-c" && "$2" == "%Y" ]]; then
      echo "1700000001"
      return 0
    fi
    return 1
  }
  export -f stat

  local tmpfile
  tmpfile=$(mktemp)
  run file_mtime "$tmpfile"
  rm -f "$tmpfile"

  assert_success
  assert_output "1700000001"
}

@test "file_mtime: returns 0 when both stat variants fail" {
  unset _YUNOMI_STAT_ARGS_STR
  stat() {
    return 1
  }
  export -f stat

  local tmpfile
  tmpfile=$(mktemp)
  run file_mtime "$tmpfile"
  rm -f "$tmpfile"

  assert_success
  assert_output "0"
}

@test "file_mtime: returns numeric timestamp for existing file" {
  unset _YUNOMI_STAT_ARGS_STR
  # verify behavior with a real file without mocking the stat command
  # confirms that either macOS or Linux stat succeeds
  local tmpfile
  tmpfile=$(mktemp)
  run file_mtime "$tmpfile"
  rm -f "$tmpfile"

  assert_success
  # output must be a numeric value (non-negative integer)
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "file_mtime: cached format avoids repeated platform detection" {
  unset _YUNOMI_STAT_ARGS_STR

  local call_count_file
  call_count_file=$(mktemp)
  echo "0" >"$call_count_file"
  export call_count_file

  stat() {
    local count
    count=$(<"$call_count_file")
    echo "$((count + 1))" >"$call_count_file"
    if [[ "$1" == "-f" && "$2" == "%m" ]]; then
      echo "1700000000"
      return 0
    fi
    return 1
  }
  export -f stat

  local tmpfile
  tmpfile=$(mktemp)

  # First call: discovers format
  file_mtime "$tmpfile" >/dev/null

  local first_count
  first_count=$(<"$call_count_file")

  # Second call: should use cached format (only 1 stat call)
  file_mtime "$tmpfile" >/dev/null

  local second_count
  second_count=$(<"$call_count_file")
  local calls_in_second=$((second_count - first_count))

  rm -f "$tmpfile" "$call_count_file"

  # Second call should make exactly 1 stat call (cached path)
  [ "$calls_in_second" -eq 1 ]
}

@test "file_mtime: unset _YUNOMI_STAT_ARGS_STR forces re-detection" {
  _YUNOMI_STAT_ARGS_STR="-f %m"

  stat() {
    if [[ "$1" == "-f" && "$2" == "%m" ]]; then
      echo "1700000000"
      return 0
    fi
    return 1
  }
  export -f stat

  local tmpfile
  tmpfile=$(mktemp)
  run file_mtime "$tmpfile"
  rm -f "$tmpfile"

  assert_success
  assert_output "1700000000"

  # After unsetting, it should re-detect
  unset _YUNOMI_STAT_ARGS_STR

  stat() {
    if [[ "$1" == "-c" && "$2" == "%Y" ]]; then
      echo "1700000002"
      return 0
    fi
    return 1
  }
  export -f stat

  tmpfile=$(mktemp)
  run file_mtime "$tmpfile"
  rm -f "$tmpfile"

  assert_success
  assert_output "1700000002"
}

# ---------------------------------------------------------------------------
# require_bash_version
# ---------------------------------------------------------------------------

@test "require_bash_version: succeeds when version meets requirement" {
  run require_bash_version "4.0" </dev/null
  assert_success
}

@test "require_bash_version: fails when version is below requirement" {
  run require_bash_version "99.0" </dev/null
  assert_failure
}

@test "require_bash_version: error message includes required version" {
  run require_bash_version "99.0" </dev/null
  assert_failure
  assert_output --partial "bash 99.0+ is required"
}

@test "require_bash_version: error message includes current version" {
  local expected="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
  run require_bash_version "99.0" </dev/null
  assert_failure
  assert_output --partial "current: $expected"
}

# ---------------------------------------------------------------------------
# require_command
# ---------------------------------------------------------------------------

@test "require_command: succeeds when command exists" {
  run require_command "bash" "https://example.com"
  assert_success
}

@test "require_command: fails when command is missing" {
  run require_command "nonexistent_cmd_xyz_$$" "https://example.com/install"
  assert_failure
}

@test "require_command: error message includes install URL" {
  run require_command "nonexistent_cmd_xyz_$$" "https://example.com/install"
  assert_failure
  assert_output --partial "https://example.com/install"
}

@test "require_command: error message includes command name" {
  run require_command "nonexistent_cmd_xyz_$$" "https://example.com/install"
  assert_failure
  assert_output --partial "nonexistent_cmd_xyz_$$"
}

# ---------------------------------------------------------------------------
# get_default_branch
# ---------------------------------------------------------------------------

@test "get_default_branch: returns branch name from symbolic-ref" {
  git() {
    if [[ "$*" == *"symbolic-ref"* ]]; then
      echo "origin/main"
      return 0
    fi
  }
  export -f git

  run get_default_branch "/repo"
  assert_success
  assert_output "main"
}

@test "get_default_branch: falls back to main when symbolic-ref fails" {
  git() {
    return 1
  }
  export -f git

  run get_default_branch "/repo"
  assert_success
  assert_output "main"
}

# ---------------------------------------------------------------------------
# validate_bind_key
# ---------------------------------------------------------------------------

@test "validate_bind_key: accepts ctrl-o" {
  run validate_bind_key "ctrl-o"
  assert_success
}

@test "validate_bind_key: accepts ctrl-d" {
  run validate_bind_key "ctrl-d"
  assert_success
}

@test "validate_bind_key: accepts single letter key" {
  run validate_bind_key "a"
  assert_success
}

@test "validate_bind_key: rejects semicolon injection" {
  run validate_bind_key "ctrl-o;rm -rf /"
  assert_failure
}

@test "validate_bind_key: rejects empty string" {
  run validate_bind_key ""
  assert_failure
}

@test "validate_bind_key: rejects space in key" {
  run validate_bind_key "ctrl o"
  assert_failure
}

@test "validate_bind_key: rejects leading hyphen" {
  run validate_bind_key "-ctrl"
  assert_failure
}

@test "validate_bind_key: prints error to stderr on invalid key" {
  run validate_bind_key "bad;key"
  assert_failure
  assert_output --partial "invalid bind key"
}

# ---------------------------------------------------------------------------
# get_main_status
# ---------------------------------------------------------------------------

@test "get_main_status: conflict status for UU unmerged marker" {
  run get_main_status "UU src/foo.go" "" "feature/conflict"
  assert_success
  assert_output "conflict"
}

@test "get_main_status: conflict status for AA unmerged marker" {
  run get_main_status "AA src/foo.go" "" "feature/conflict"
  assert_success
  assert_output "conflict"
}

@test "get_main_status: changed status when non-empty and no unmerged" {
  run get_main_status " M src/foo.go" "" "feature/test"
  assert_success
  assert_output "changed"
}

@test "get_main_status: changed status for untracked files" {
  run get_main_status "?? src/new.go" "" "feature/test"
  assert_success
  assert_output "changed"
}

@test "get_main_status: merged status when branch in merged list" {
  run get_main_status "" "  main" "main"
  assert_success
  assert_output "merged"
}

@test "get_main_status: merged status for non-default branch" {
  run get_main_status "" "  main"$'\n'"  feature/done" "feature/done"
  assert_success
  assert_output "merged"
}

@test "get_main_status: clean status when empty and not merged" {
  run get_main_status "" "  main" "feature/test"
  assert_success
  assert_output "clean"
}

@test "get_main_status: clean status for branch not in merged list" {
  run get_main_status "" "  main" "feature/wip"
  assert_success
  assert_output "clean"
}

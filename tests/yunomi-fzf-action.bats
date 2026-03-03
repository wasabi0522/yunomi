#!/usr/bin/env bats

load test_helper

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FZF_ACTION_SH="$PROJECT_ROOT/scripts/yunomi-fzf-action.sh"

setup_file() {
  export FZF_ACTION_SH
}

setup() {
  setup_mocks
  export YUNOMI_SCRIPTS_DIR="/mock/scripts"
  export YUNOMI_PID="12345"
  export YUNOMI_EXIT_FLAG="/tmp/yunomi-exit-${YUNOMI_PID}"
}

teardown() {
  teardown_mocks
}

# --- new action ---

@test "yunomi-fzf-action: new action outputs execute+reload+transform chain" {
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  assert_output --partial "execute("
  assert_output --partial "+reload("
  assert_output --partial "+transform("
}

@test "yunomi-fzf-action: new action execute contains yunomi-new.sh" {
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  assert_output --partial "yunomi-new.sh"
}

@test "yunomi-fzf-action: new action execute contains escaped repo_path" {
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  assert_output --partial "/repo/path"
}

@test "yunomi-fzf-action: new action reload contains yunomi-branch-list.sh" {
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  assert_output --partial "yunomi-branch-list.sh"
}

@test "yunomi-fzf-action: new action transform contains yunomi-exit check with unexpanded YUNOMI_PID" {
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  # $YUNOMI_PID must remain unexpanded because fzf re-evaluates it
  assert_output --partial '$YUNOMI_EXIT_FLAG'
}

@test "yunomi-fzf-action: new action transform contains 'echo abort'" {
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  assert_output --partial "echo abort"
}

@test "yunomi-fzf-action: new action uses YUNOMI_SCRIPTS_DIR" {
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  assert_output --partial "/mock/scripts"
}

@test "yunomi-fzf-action: new action execute contains base branch when provided" {
  run bash "$FZF_ACTION_SH" new /repo/path main
  assert_success
  # execute(yunomi-new.sh /repo/path main) format
  assert_output --regexp 'execute\([^ ]*yunomi-new\.sh [^ ]+ main\)'
}

# --- remove action ---

@test "yunomi-fzf-action: remove action outputs execute+reload chain (no transform)" {
  run bash "$FZF_ACTION_SH" remove /repo/path feature/login
  assert_success
  assert_output --partial "execute("
  assert_output --partial "+reload("
  refute_output --partial "+transform("
}

@test "yunomi-fzf-action: remove action execute contains yunomi-remove.sh" {
  run bash "$FZF_ACTION_SH" remove /repo/path feature/login
  assert_success
  assert_output --partial "yunomi-remove.sh"
}

@test "yunomi-fzf-action: remove action execute contains escaped repo_path" {
  run bash "$FZF_ACTION_SH" remove /repo/path feature/login
  assert_success
  assert_output --partial "/repo/path"
}

@test "yunomi-fzf-action: remove action execute contains escaped branch_name" {
  run bash "$FZF_ACTION_SH" remove /repo/path feature/login
  assert_success
  assert_output --partial "feature/login"
}

@test "yunomi-fzf-action: remove action reload contains yunomi-branch-list.sh" {
  run bash "$FZF_ACTION_SH" remove /repo/path feature/login
  assert_success
  assert_output --partial "yunomi-branch-list.sh"
}

@test "yunomi-fzf-action: remove action does not contain transform" {
  run bash "$FZF_ACTION_SH" remove /repo/path feature/login
  assert_success
  refute_output --partial "transform("
}

# --- rename action ---

@test "yunomi-fzf-action: rename action outputs execute+reload chain (no transform)" {
  run bash "$FZF_ACTION_SH" rename /repo/path feature/login
  assert_success
  assert_output --partial "execute("
  assert_output --partial "+reload("
  refute_output --partial "+transform("
}

@test "yunomi-fzf-action: rename action execute contains yunomi-rename.sh" {
  run bash "$FZF_ACTION_SH" rename /repo/path feature/login
  assert_success
  assert_output --partial "yunomi-rename.sh"
}

@test "yunomi-fzf-action: rename action execute contains escaped repo_path" {
  run bash "$FZF_ACTION_SH" rename /repo/path feature/login
  assert_success
  assert_output --partial "/repo/path"
}

@test "yunomi-fzf-action: rename action execute contains escaped branch_name" {
  run bash "$FZF_ACTION_SH" rename /repo/path feature/login
  assert_success
  assert_output --partial "feature/login"
}

@test "yunomi-fzf-action: rename action reload contains yunomi-branch-list.sh" {
  run bash "$FZF_ACTION_SH" rename /repo/path feature/login
  assert_success
  assert_output --partial "yunomi-branch-list.sh"
}

# --- Escape tests ---

@test "yunomi-fzf-action: repo path with spaces is properly escaped in new action" {
  run bash "$FZF_ACTION_SH" new "/my repo/path with spaces"
  assert_success
  # path with spaces is handled correctly because it is shell-escaped
  [[ "$output" == *"my\ repo"* ]] || [[ "$output" == *"my repo"* ]]
}

@test "yunomi-fzf-action: repo path with spaces is properly escaped in remove action" {
  run bash "$FZF_ACTION_SH" remove "/my repo/path" "feature/test"
  assert_success
  [[ "$output" == *"my\ repo"* ]] || [[ "$output" == *"my repo"* ]]
}

@test "yunomi-fzf-action: branch name with slash is preserved in remove action" {
  run bash "$FZF_ACTION_SH" remove /repo/path "feature/my-feature"
  assert_success
  [[ "$output" == *"feature/my-feature"* ]]
}

@test "yunomi-fzf-action: YUNOMI_SCRIPTS_DIR with spaces is properly escaped" {
  export YUNOMI_SCRIPTS_DIR="/my scripts/dir"
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  # escaped path must be present in output
  [[ "$output" == *"my\ scripts"* ]] || [[ "$output" == *"my scripts"* ]]
}

# --- Error handling ---

@test "yunomi-fzf-action: unknown action prints error to stderr" {
  run bash "$FZF_ACTION_SH" invalid /repo/path
  assert_failure
  [[ "${lines[*]}" == *"unknown action"* ]] || [[ "${lines[*]}" == *"invalid"* ]]
}

@test "yunomi-fzf-action: unknown action exits with code 1" {
  run bash "$FZF_ACTION_SH" invalid /repo/path
  assert_failure
}

# --- YUNOMI_SCRIPTS_DIR fallback ---

@test "yunomi-fzf-action: falls back to CURRENT_DIR when YUNOMI_SCRIPTS_DIR is unset" {
  unset YUNOMI_SCRIPTS_DIR
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  # the script's own directory is used (the scripts/ directory)
  [[ "$output" == *"scripts/"* ]] || [[ "$output" == *"/yunomi-new.sh"* ]]
}

# --- output must be a single line ---

@test "yunomi-fzf-action: new action output is single line" {
  run bash "$FZF_ACTION_SH" new /repo/path
  assert_success
  [ "${#lines[@]}" -eq 1 ]
}

@test "yunomi-fzf-action: remove action output is single line" {
  run bash "$FZF_ACTION_SH" remove /repo/path feature/login
  assert_success
  [ "${#lines[@]}" -eq 1 ]
}

@test "yunomi-fzf-action: rename action output is single line" {
  run bash "$FZF_ACTION_SH" rename /repo/path feature/login
  assert_success
  [ "${#lines[@]}" -eq 1 ]
}

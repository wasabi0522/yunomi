#!/usr/bin/env bats

load 'test_helper'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  setup_mocks
  mock_hashi

  SCRIPT="$PROJECT_ROOT/scripts/yunomi-rename.sh"
  MOCK_REPO_PATH="$(mktemp -d)"
  export MOCK_REPO_PATH
}

teardown() {
  teardown_mocks
  rm -rf "${MOCK_REPO_PATH:-}"
}

# ---------------------------------------------------------------------------
# Happy path: rename execution
# ---------------------------------------------------------------------------

@test "yunomi-rename: renames branch with correct argument order (old, new)" {
  run bash -c "echo 'new-name' | bash '$SCRIPT' '$MOCK_REPO_PATH' 'old-branch'"
  assert_success

  run grep 'rename -- old-branch new-name' "$MOCK_HASHI_CALLS"
  assert_success
}

@test "yunomi-rename: passes repo_path to cd before hashi rename" {
  # when a path that causes cd to fail is given, hashi rename is not executed
  run bash -c "echo 'new-name' | bash '$SCRIPT' '/nonexistent/path/$$' 'old-branch'"
  # cd failure causes non-zero exit code
  assert_failure

  # rename must not be recorded in MOCK_HASHI_CALLS
  run grep 'rename' "$MOCK_HASHI_CALLS"
  assert_failure
}

@test "yunomi-rename: branch names with slashes are passed correctly" {
  run bash -c "echo 'feature/new-login' | bash '$SCRIPT' '$MOCK_REPO_PATH' 'feature/old-login'"
  assert_success

  run grep 'rename -- feature/old-login feature/new-login' "$MOCK_HASHI_CALLS"
  assert_success
}

# ---------------------------------------------------------------------------
# Cancel: empty input
# ---------------------------------------------------------------------------

@test "yunomi-rename: empty input exits 0 without calling hashi" {
  # pass an empty string (Enter only) to stdin
  run bash -c "echo '' | bash '$SCRIPT' '$MOCK_REPO_PATH' 'old-branch'"
  assert_success

  # hashi must not be called (call record file must be empty)
  [ ! -s "$MOCK_HASHI_CALLS" ]
}

# ---------------------------------------------------------------------------
# Cancel: ESC key
# ---------------------------------------------------------------------------

@test "yunomi-rename: ESC key exits 0 without calling hashi" {
  run bash -c "printf '\x1b' | bash '$SCRIPT' '$MOCK_REPO_PATH' 'old-branch'"
  assert_success

  # hashi must not be called (call record file must be empty)
  [ ! -s "$MOCK_HASHI_CALLS" ]
}

# ---------------------------------------------------------------------------
# Whitespace input
# ---------------------------------------------------------------------------

@test "yunomi-rename: whitespace-only input calls hashi rename (hashi validates)" {
  # whitespace-only input passes the -z check so hashi rename is called
  # validation is hashi's responsibility
  run bash -c "printf '   \n' | bash '$SCRIPT' '$MOCK_REPO_PATH' 'old-branch'"

  run grep 'rename' "$MOCK_HASHI_CALLS"
  assert_success
}

# ---------------------------------------------------------------------------
# Explicit argument order verification
# ---------------------------------------------------------------------------

@test "yunomi-rename: argument order is old-branch then new-branch" {
  # when old is "aaa" and new is "bbb", order must be hashi rename aaa bbb
  run bash -c "echo 'bbb' | bash '$SCRIPT' '$MOCK_REPO_PATH' 'aaa'"
  assert_success

  # "rename bbb aaa" (reverse order) must not be present
  run grep 'rename -- bbb aaa' "$MOCK_HASHI_CALLS"
  assert_failure

  # "rename aaa bbb" (correct order) must be present
  run grep 'rename -- aaa bbb' "$MOCK_HASHI_CALLS"
  assert_success
}

# ---------------------------------------------------------------------------
# Verify that exit flag is not created
# ---------------------------------------------------------------------------

@test "yunomi-rename: does not create exit flag after rename" {
  export YUNOMI_PID="88888"
  run bash -c "echo 'new-name' | YUNOMI_PID='88888' bash '$SCRIPT' '$MOCK_REPO_PATH' 'old-branch'"
  assert_success

  # exit flag must not be created
  [ ! -f "${TMPDIR:-/tmp}/yunomi-exit-88888" ]
}

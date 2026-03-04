#!/usr/bin/env bats

load 'test_helper'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  setup_mocks
  mock_hashi

  MOCK_REPO_PATH="$(mktemp -d)"
  export MOCK_REPO_PATH

  # shellcheck source=scripts/yunomi-remove.sh
  source "$PROJECT_ROOT/scripts/yunomi-remove.sh"
}

teardown() {
  teardown_mocks
  rm -rf "${MOCK_REPO_PATH:-}"
}

# ---------------------------------------------------------------------------
# Happy path: hashi remove call verification
# ---------------------------------------------------------------------------

@test "remove: calls hashi remove with branch name" {
  run main "$MOCK_REPO_PATH" "feature/test"
  assert_success

  # hashi remove must be called
  run grep "remove -- feature/test" "$MOCK_HASHI_CALLS"
  assert_success
}

# ---------------------------------------------------------------------------
# hashi remove failure
# ---------------------------------------------------------------------------

@test "remove: hashi remove failure returns non-zero" {
  hashi() {
    if [[ -n "${MOCK_HASHI_CALLS:-}" ]]; then
      printf '%s\n' "$*" >>"$MOCK_HASHI_CALLS"
    fi
    case "$1" in
      remove) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f hashi

  run main "$MOCK_REPO_PATH" "main"
  assert_failure
}

# ---------------------------------------------------------------------------
# cd failure
# ---------------------------------------------------------------------------

@test "remove: cd failure returns error" {
  run main "/nonexistent/path/that/does/not/exist" "main"
  assert_failure
}

# ---------------------------------------------------------------------------
# EXIT_FLAG: remove does not create exit flag
# ---------------------------------------------------------------------------

@test "remove: does not create exit flag after successful removal" {
  export YUNOMI_EXIT_FLAG="/tmp/yunomi-exit-test-$$"
  run main "$MOCK_REPO_PATH" "feature/test"
  assert_success

  # exit flag must not be created (remove does not trigger popup exit)
  [ ! -f "$YUNOMI_EXIT_FLAG" ]
  rm -f "$YUNOMI_EXIT_FLAG"
}

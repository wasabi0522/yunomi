#!/usr/bin/env bats

load 'test_helper'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  MOCK_HASHI_CALLS="$(mktemp)"
  export MOCK_HASHI_CALLS
  mock_hashi

  export YUNOMI_PID="99999"
  export YUNOMI_EXIT_FLAG="/tmp/yunomi-exit-${YUNOMI_PID}"

  MOCK_REPO_PATH="$(mktemp -d)"
  export MOCK_REPO_PATH
}

teardown() {
  rm -f "$MOCK_HASHI_CALLS"
  rm -f "$YUNOMI_EXIT_FLAG"
  rm -rf "${MOCK_REPO_PATH:-}"
}

# ---------------------------------------------------------------------------
# Happy path: branch name input
# ---------------------------------------------------------------------------

@test "yunomi-new: valid branch name calls hashi new" {
  # simulate "feature/login" as input
  run bash -c "echo 'feature/login' | bash '$PROJECT_ROOT/scripts/yunomi-new.sh' '$MOCK_REPO_PATH'"

  assert_success
  # hashi new must be called
  run grep 'new -- feature/login' "$MOCK_HASHI_CALLS"
  assert_success
}

@test "yunomi-new: success creates exit flag" {
  run bash -c "echo 'feature/login' | YUNOMI_PID='99999' YUNOMI_EXIT_FLAG='/tmp/yunomi-exit-99999' bash '$PROJECT_ROOT/scripts/yunomi-new.sh' '$MOCK_REPO_PATH'"

  assert_success
  # exit flag must be created
  [ -f "$YUNOMI_EXIT_FLAG" ]
}

# ---------------------------------------------------------------------------
# Cancel: empty input
# ---------------------------------------------------------------------------

@test "yunomi-new: empty input exits 0 without calling hashi" {
  # simulate empty string (Enter only) as input
  run bash -c "echo '' | bash '$PROJECT_ROOT/scripts/yunomi-new.sh' '$MOCK_REPO_PATH'"

  assert_success
  # hashi must not be called (call record file must be empty)
  [ ! -s "$MOCK_HASHI_CALLS" ]
}

@test "yunomi-new: empty input does not create exit flag" {
  run bash -c "echo '' | YUNOMI_PID='99999' YUNOMI_EXIT_FLAG='/tmp/yunomi-exit-99999' bash '$PROJECT_ROOT/scripts/yunomi-new.sh' '$MOCK_REPO_PATH'"

  assert_success
  # exit flag must not be created
  [ ! -f "$YUNOMI_EXIT_FLAG" ]
}

# ---------------------------------------------------------------------------
# Cancel: ESC key
# ---------------------------------------------------------------------------

@test "yunomi-new: ESC key exits 0 without calling hashi" {
  # simulate ESC (0x1b) as input
  run bash -c "printf '\x1b' | bash '$PROJECT_ROOT/scripts/yunomi-new.sh' '$MOCK_REPO_PATH'"

  assert_success
  # hashi must not be called (call record file must be empty)
  [ ! -s "$MOCK_HASHI_CALLS" ]
}

@test "yunomi-new: ESC key does not create exit flag" {
  run bash -c "printf '\x1b' | YUNOMI_PID='99999' YUNOMI_EXIT_FLAG='/tmp/yunomi-exit-99999' bash '$PROJECT_ROOT/scripts/yunomi-new.sh' '$MOCK_REPO_PATH'"

  assert_success
  # exit flag must not be created
  [ ! -f "$YUNOMI_EXIT_FLAG" ]
}

# ---------------------------------------------------------------------------
# Error: cd failure
# ---------------------------------------------------------------------------

@test "yunomi-new: cd failure exits with error" {
  run bash -c "echo 'feature/login' | YUNOMI_EXIT_FLAG='/tmp/yunomi-exit-99999' bash '$PROJECT_ROOT/scripts/yunomi-new.sh' '/nonexistent/path/that/does/not/exist'"
  assert_failure

  # exit flag must not be created
  [ ! -f "/tmp/yunomi-exit-99999" ]
}

# ---------------------------------------------------------------------------
# Error: hashi new failure
# ---------------------------------------------------------------------------

@test "yunomi-new: hashi new failure does not create exit flag" {
  # replace mock with one where hashi new fails
  # review note: in case the real hashi does not exist in CI environment,
  # unknown subcommands return 1 instead of delegating to builtin
  hashi() {
    if [[ -n "${MOCK_HASHI_CALLS:-}" ]]; then
      printf '%s\n' "$*" >>"$MOCK_HASHI_CALLS"
    fi
    case "$1" in
      new) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f hashi

  run bash -c "echo 'feature/fail' | YUNOMI_PID='99999' YUNOMI_EXIT_FLAG='/tmp/yunomi-exit-99999' bash '$PROJECT_ROOT/scripts/yunomi-new.sh' '$MOCK_REPO_PATH'"

  # hashi new failure -> script exits with non-zero status
  assert_failure
  # exit flag must not be created
  [ ! -f "$YUNOMI_EXIT_FLAG" ]
}

#!/usr/bin/env bats

load 'test_helper'

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  MOCK_HASHI_CALLS="$(mktemp)"
  export MOCK_HASHI_CALLS
  mock_hashi

  MOCK_REPO_PATH="$(mktemp -d)"
  export MOCK_REPO_PATH

  export YUNOMI_PID="$$"
  export YUNOMI_EXIT_FLAG="${TMPDIR:-/tmp}/yunomi-exit-${YUNOMI_PID}"
  rm -f "$YUNOMI_EXIT_FLAG"

  # shellcheck source=scripts/yunomi-remove.sh
  source "$PROJECT_ROOT/scripts/yunomi-remove.sh"
}

teardown() {
  rm -f "${MOCK_HASHI_CALLS:-}"
  rm -rf "${MOCK_REPO_PATH:-}"
  rm -f "${YUNOMI_EXIT_FLAG:-}"
}

# ---------------------------------------------------------------------------
# Delete inactive branch: hashi remove call verification
# ---------------------------------------------------------------------------

@test "remove inactive branch: calls hashi remove with branch name" {
  mock_jq "false"
  export YUNOMI_HASHI_JSON="$MOCK_HASHI_JSON"

  run main "$MOCK_REPO_PATH" "feature/test"
  assert_success

  # hashi remove must be called
  run grep "remove -- feature/test" "$MOCK_HASHI_CALLS"
  assert_success
}

# ---------------------------------------------------------------------------
# Delete inactive branch: exit flag must not be created
# ---------------------------------------------------------------------------

@test "remove inactive branch: does not create exit flag" {
  mock_jq "false"
  export YUNOMI_HASHI_JSON="$MOCK_HASHI_JSON"

  run main "$MOCK_REPO_PATH" "feature/test"
  assert_success

  # exit flag must not be created
  [ ! -f "$YUNOMI_EXIT_FLAG" ]
}

# ---------------------------------------------------------------------------
# Delete active branch: exit flag must be created
# ---------------------------------------------------------------------------

@test "remove active branch: creates exit flag" {
  mock_jq "true"
  export YUNOMI_HASHI_JSON="$MOCK_HASHI_JSON"

  run main "$MOCK_REPO_PATH" "main"
  assert_success

  # exit flag must be created
  [ -f "$YUNOMI_EXIT_FLAG" ]
}

# ---------------------------------------------------------------------------
# hashi remove failure (cancel): exit flag must not be created
# ---------------------------------------------------------------------------

@test "hashi remove failure: does not create exit flag even for active branch" {
  # override hashi remove to return failure (non-zero exit code)
  # exit flag must not be created even when active=true if hashi fails
  mock_jq "true"
  export YUNOMI_HASHI_JSON='[{"branch":"main","window":true,"active":true,"is_default":true,"status":"ok"}]'

  hashi() {
    if [[ -n "${MOCK_HASHI_CALLS:-}" ]]; then
      printf '%s\n' "$*" >>"$MOCK_HASHI_CALLS"
    fi
    # remove subcommand fails (assumes user cancelled with N)
    case "$1" in
      remove)
        return 1
        ;;
      list)
        printf '%s\n' "$YUNOMI_HASHI_JSON"
        ;;
    esac
  }
  export -f hashi

  # when calling main() via source in bats run, set -euo pipefail is not applied.
  # hashi remove returning 1 records exit_code=1,
  # and main() exits non-zero via return $exit_code.
  # exit flag is not created because exit_code != 0 (if condition is false).
  run main "$MOCK_REPO_PATH" "main"
  # status is non-zero because hashi remove failed
  assert_failure

  # exit flag must not be created
  [ ! -f "$YUNOMI_EXIT_FLAG" ]
}

# ---------------------------------------------------------------------------
# Fallback when YUNOMI_HASHI_JSON is unset
# ---------------------------------------------------------------------------

@test "remove: cd failure returns error and does not create exit flag" {
  mock_jq "true"
  export YUNOMI_HASHI_JSON="$MOCK_HASHI_JSON"

  run main "/nonexistent/path/that/does/not/exist" "main"
  assert_failure

  # exit flag must not be created
  [ ! -f "$YUNOMI_EXIT_FLAG" ]
}

# ---------------------------------------------------------------------------
# Fallback when YUNOMI_HASHI_JSON is unset
# ---------------------------------------------------------------------------

@test "YUNOMI_HASHI_JSON unset: treats branch as non-active, no exit flag" {
  # unset YUNOMI_HASHI_JSON
  unset YUNOMI_HASHI_JSON

  mock_jq ""

  run main "$MOCK_REPO_PATH" "feature/test"
  assert_success

  # exit flag must not be created because branch is not active
  [ ! -f "$YUNOMI_EXIT_FLAG" ]
}

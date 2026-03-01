#!/usr/bin/env bats

load 'test_helper'

# ---------------------------------------------------------------------------
# Common setup
# ---------------------------------------------------------------------------

setup() {
  # shellcheck source=scripts/yunomi-preview.sh
  source "$PROJECT_ROOT/scripts/yunomi-preview.sh"
  # use an empty directory as repo_path for tests
  MOCK_REPO_PATH="/tmp/yunomi-test-repo-$$"
  mkdir -p "$MOCK_REPO_PATH"
  export MOCK_REPO_PATH
}

teardown() {
  rm -rf "$MOCK_REPO_PATH"
  unset YUNOMI_HASHI_JSON
  unset MOCK_GIT_LOG
  unset MOCK_GIT_STATUS_SHORT
  unset MOCK_GIT_BRANCHES
  unset MOCK_GIT_MERGED
  unset MOCK_GIT_REVLIST
  unset MOCK_GIT_DEFAULT_BRANCH
  unset MOCK_JQ_OUTPUT
}

# ---------------------------------------------------------------------------
# With worktree: all sections shown
# ---------------------------------------------------------------------------

@test "preview: with worktree - branch name is shown first" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  assert_line --index 0 "feature/login"
}

@test "preview: with worktree - Worktree line shows path" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Worktree"* && "$line" == *"/repo/.worktrees/feature/login"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: with worktree - Remote line is shown" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  MOCK_GIT_REVLIST=$(printf '2\t0')
  export MOCK_GIT_REVLIST
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Remote"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: with worktree - Status line is shown" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Status"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: with worktree - Commits section is shown" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Commits"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Without worktree: display verification
# ---------------------------------------------------------------------------

@test "preview: without worktree - Worktree line shows '(no worktree)'" {
  # no worktree key (assumes main branch)
  export YUNOMI_HASHI_JSON='[{"branch":"main","window":true,"active":true,"is_default":true,"status":"ok"}]'
  mock_git
  mock_jq ""

  run main "main" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Worktree"* && "$line" == *"(no worktree)"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: without worktree - Status line is not shown" {
  export YUNOMI_HASHI_JSON='[{"branch":"main","window":true,"active":true,"is_default":true,"status":"ok"}]'
  mock_git
  mock_jq ""

  run main "main" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Status"* ]] && found=1
  done
  [ "$found" -eq 0 ]
}

@test "preview: without worktree - Commits section is shown" {
  export YUNOMI_HASHI_JSON='[{"branch":"main","window":true,"active":true,"is_default":true,"status":"ok"}]'
  mock_git
  mock_jq ""

  run main "main" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Commits"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: without worktree - Changed files section is not shown" {
  export YUNOMI_HASHI_JSON='[{"branch":"main","window":true,"active":true,"is_default":true,"status":"ok"}]'
  mock_git
  mock_jq ""

  run main "main" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Changed files"* ]] && found=1
  done
  [ "$found" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Commit log: show up to 5 entries
# ---------------------------------------------------------------------------

@test "preview: commit log shows up to 5 entries" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  MOCK_GIT_LOG="abc1234 feat: add login form
def5678 refactor: extract auth
ghi9012 fix: session timeout
1a2b3c4 init: scaffold page
5d6e7f8 chore: add dependencies"
  export MOCK_GIT_LOG
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success

  # commit line must be included
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"abc1234"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: Commits section shows commit count" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  MOCK_GIT_LOG="abc1234 feat: add login form
def5678 refactor: extract auth
ghi9012 fix: session timeout"
  export MOCK_GIT_LOG
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Commits (3)"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Changed files list
# ---------------------------------------------------------------------------

@test "preview: when changes exist, Changed files section is shown" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  MOCK_GIT_STATUS_SHORT="M  src/auth.go
A  src/login.go"
  export MOCK_GIT_STATUS_SHORT
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Changed files"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: when changes exist, changed file contents are shown" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  MOCK_GIT_STATUS_SHORT="M  src/auth.go
A  src/login.go"
  export MOCK_GIT_STATUS_SHORT
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"src/auth.go"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: when clean (no changes), Changed files section is not shown" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  MOCK_GIT_STATUS_SHORT=""
  export MOCK_GIT_STATUS_SHORT
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Changed files"* ]] && found=1
  done
  [ "$found" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Remote tracking status
# ---------------------------------------------------------------------------

@test "preview: when no remote branch, Remote line shows '(no remote)'" {
  export YUNOMI_HASHI_JSON='[{"branch":"local-only","worktree":"/repo/.worktrees/local-only","window":false,"active":false,"is_default":false,"status":"ok"}]'
  mock_git
  mock_jq "/repo/.worktrees/local-only"

  # mock state where git rev-parse --verify cannot find the remote branch
  git() {
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
      rev-parse)
        return 1
        ;;
      log)
        printf '%s\n' "${MOCK_GIT_LOG:-}"
        ;;
      branch)
        if printf '%s\n' "${args[@]}" | grep -q -- '--merged'; then
          printf '%s\n' "${MOCK_GIT_MERGED:-  main}"
        else
          printf '%s\n' "${MOCK_GIT_BRANCHES:-main}" | sed 's/^/  /'
        fi
        ;;
      status)
        printf '%s\n' "${MOCK_GIT_STATUS_SHORT:-}"
        ;;
      symbolic-ref)
        printf 'origin/%s\n' "${MOCK_GIT_DEFAULT_BRANCH:-main}"
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f git

  run main "local-only" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Remote"* && "$line" == *"(no remote)"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: when ahead=2, Remote line contains ↑2" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  MOCK_GIT_REVLIST=$(printf '2\t0')
  export MOCK_GIT_REVLIST
  mock_git
  mock_jq "/repo/.worktrees/feature/login"

  # override git to make rev-parse --verify succeed
  git() {
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
      rev-parse) return 0 ;;
      rev-list) printf '%s\n' "${MOCK_GIT_REVLIST:-$(printf '0\t0')}" ;;
      log) printf '%s\n' "${MOCK_GIT_LOG:-}" ;;
      branch)
        if printf '%s\n' "${args[@]}" | grep -q -- '--merged'; then
          printf '%s\n' "${MOCK_GIT_MERGED:-  main}"
        else
          printf '%s\n' "${MOCK_GIT_BRANCHES:-main}" | sed 's/^/  /'
        fi
        ;;
      status) printf '%s\n' "${MOCK_GIT_STATUS_SHORT:-}" ;;
      symbolic-ref) printf 'origin/%s\n' "${MOCK_GIT_DEFAULT_BRANCH:-main}" ;;
      *) return 0 ;;
    esac
  }
  export -f git

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Remote"* && "$line" == *"↑2"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: when behind=3, Remote line contains ↓3" {
  export YUNOMI_HASHI_JSON='[{"branch":"main","worktree":"/repo/.worktrees/main","window":true,"active":true,"is_default":true,"status":"ok"}]'
  MOCK_GIT_REVLIST=$(printf '0\t3')
  export MOCK_GIT_REVLIST
  mock_git
  mock_jq "/repo/.worktrees/main"

  git() {
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
      rev-parse) return 0 ;;
      rev-list) printf '%s\n' "${MOCK_GIT_REVLIST:-$(printf '0\t0')}" ;;
      log) printf '%s\n' "${MOCK_GIT_LOG:-}" ;;
      branch)
        if printf '%s\n' "${args[@]}" | grep -q -- '--merged'; then
          printf '%s\n' "${MOCK_GIT_MERGED:-  main}"
        else
          printf '%s\n' "${MOCK_GIT_BRANCHES:-main}" | sed 's/^/  /'
        fi
        ;;
      status) printf '%s\n' "${MOCK_GIT_STATUS_SHORT:-}" ;;
      symbolic-ref) printf 'origin/%s\n' "${MOCK_GIT_DEFAULT_BRANCH:-main}" ;;
      *) return 0 ;;
    esac
  }
  export -f git

  run main "main" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Remote"* && "$line" == *"↓3"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Fallback when YUNOMI_HASHI_JSON is unset
# ---------------------------------------------------------------------------

@test "preview: when YUNOMI_HASHI_JSON is unset, treats as empty JSON [] and shows no worktree" {
  unset YUNOMI_HASHI_JSON
  mock_git
  # jq returns empty string because it cannot get worktree from empty JSON
  mock_jq ""

  run main "main" "$MOCK_REPO_PATH"
  assert_success
  # shown as no worktree: "(no worktree)" is displayed
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"(no worktree)"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

@test "preview: when YUNOMI_HASHI_JSON is unset, branch name is still shown" {
  unset YUNOMI_HASHI_JSON
  mock_git
  mock_jq ""

  run main "main" "$MOCK_REPO_PATH"
  assert_success
  assert_line --index 0 "main"
}

@test "preview: when YUNOMI_HASHI_JSON is unset, Commits section is still shown" {
  unset YUNOMI_HASHI_JSON
  mock_git
  mock_jq ""

  run main "main" "$MOCK_REPO_PATH"
  assert_success
  local found=0
  for line in "${lines[@]}"; do
    [[ "$line" == *"Commits"* ]] && found=1
  done
  [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# git log must include --
# ---------------------------------------------------------------------------

@test "preview: git log contains -- separator" {
  export YUNOMI_HASHI_JSON='[{"branch":"feature/login","worktree":"/repo/.worktrees/feature/login","window":true,"active":false,"is_default":false,"status":"ok"}]'
  mock_jq "/repo/.worktrees/feature/login"

  # mock that records git call arguments
  MOCK_GIT_CALLS="$(mktemp)"
  export MOCK_GIT_CALLS
  mock_git

  run main "feature/login" "$MOCK_REPO_PATH"
  assert_success

  # verify that git log call includes --
  # each line in MOCK_GIT_CALLS has the format "-C /path log ..."
  run grep " log " "$MOCK_GIT_CALLS"
  assert_output --partial " --"

  rm -f "$MOCK_GIT_CALLS"
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "preview: exits with code 1 when no arguments given" {
  run main
  assert_failure
}

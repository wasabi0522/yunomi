#!/usr/bin/env bats

load 'test_helper'

# Path to the script under test
SCRIPT="$PROJECT_ROOT/scripts/yunomi-main.sh"

# ---------------------------------------------------------------------------
# Dependency command existence checks
# Review note: overriding the command() builtin is unstable in subshells,
# so PATH manipulation is used instead.
# ---------------------------------------------------------------------------

@test "main: exits with error when hashi is not installed" {
  # simulate hashi not being in PATH by prepending an empty dir
  # and only providing dummy ghq and jq
  local fake_bin
  fake_bin=$(mktemp -d)

  # ghq dummy
  printf '#!/bin/sh\necho dummy\n' >"$fake_bin/ghq"
  chmod +x "$fake_bin/ghq"

  # jq dummy
  printf '#!/bin/sh\necho dummy\n' >"$fake_bin/jq"
  chmod +x "$fake_bin/jq"

  # pass /dev/null as input so read prompts don't block
  # use env to pass PATH to the subshell
  local script="$SCRIPT"
  run env PATH="$fake_bin:/usr/bin:/bin" "$BASH" -c "source '$script'; main" </dev/null
  rm -rf "$fake_bin"

  assert_failure
  assert_output --partial "hashi command not found"
}

@test "main: exits with error when ghq is not installed" {
  local fake_bin
  fake_bin=$(mktemp -d)

  # hashi dummy
  printf '#!/bin/sh\necho dummy\n' >"$fake_bin/hashi"
  chmod +x "$fake_bin/hashi"

  # jq dummy
  printf '#!/bin/sh\necho dummy\n' >"$fake_bin/jq"
  chmod +x "$fake_bin/jq"

  local script="$SCRIPT"
  run env PATH="$fake_bin:/usr/bin:/bin" "$BASH" -c "source '$script'; main" </dev/null
  rm -rf "$fake_bin"

  assert_failure
  assert_output --partial "ghq command not found"
}

@test "main: exits with error when jq is not installed" {
  local fake_bin
  fake_bin=$(mktemp -d)

  # hashi dummy
  printf '#!/bin/sh\necho dummy\n' >"$fake_bin/hashi"
  chmod +x "$fake_bin/hashi"

  # ghq dummy
  printf '#!/bin/sh\necho dummy\n' >"$fake_bin/ghq"
  chmod +x "$fake_bin/ghq"

  # override with command() to fail only jq via command -v
  # PATH includes fake_bin so hashi/ghq are found by builtin command
  local script="$SCRIPT"
  run env PATH="$fake_bin:/usr/bin:/bin" "$BASH" -c "
    command() {
      if [[ \"\$1\" == '-v' && \"\$2\" == 'jq' ]]; then
        return 1
      fi
      builtin command \"\$@\"
    }
    export -f command
    source '$script'
    main
  " </dev/null
  rm -rf "$fake_bin"

  assert_failure
  assert_output --partial "jq command not found"
}

# ---------------------------------------------------------------------------
# Bash version check
# ---------------------------------------------------------------------------

@test "main: exits with error when bash version check fails" {
  source "$SCRIPT"
  # Override require_bash_version to simulate failure
  require_bash_version() {
    printf 'yunomi: bash 4.0+ is required (current: 3.2)\n'
    return 1
  }
  run main </dev/null

  assert_failure
  assert_output --partial "bash 4.0+ is required"
}

# ---------------------------------------------------------------------------
# YUNOMI_EXIT_FLAG configuration checks
# ---------------------------------------------------------------------------

@test "main: exports YUNOMI_EXIT_FLAG as a temp file path" {
  # show_repo_list is called inside $(), so stdout is captured as ghq_path.
  # Use a tempfile to extract YUNOMI_EXIT_FLAG from outside.
  local flag_file
  flag_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
source '$SCRIPT'
require_command() { return 0; }
ghq() { echo "/tmp/ghq-root"; }
export -f ghq
show_repo_list() {
  printf '%s' "\$YUNOMI_EXIT_FLAG" >"$flag_file"
  return 1  # end loop
}
main
SCRIPT

  run bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  local recorded_flag
  recorded_flag=$(cat "$flag_file")
  rm -f "$flag_file"

  [[ -n "$recorded_flag" ]]
  [[ "$recorded_flag" == *"yunomi-exit-"* ]]
}

@test "main: trap removes EXIT_FLAG on exit" {
  # verify that EXIT_FLAG is cleaned up by the EXIT trap
  # use a tempfile to extract the flag path (stdout is captured by $())
  local path_record_file
  path_record_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
source '$SCRIPT'
require_command() { return 0; }
ghq() { echo "/tmp/ghq-root"; }
export -f ghq
show_repo_list() {
  printf '%s' "\$YUNOMI_EXIT_FLAG" >"$path_record_file"
  touch "\$YUNOMI_EXIT_FLAG"
  return 1  # end loop
}
main
SCRIPT

  run bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  local exit_flag_path
  exit_flag_path=$(cat "$path_record_file")
  rm -f "$path_record_file"

  # must have been removed by trap 'rm -f "$EXIT_FLAG"' EXIT
  [[ -n "$exit_flag_path" ]]
  [[ ! -f "$exit_flag_path" ]]
}

# ---------------------------------------------------------------------------
# YUNOMI_SCRIPTS_DIR export verification
# ---------------------------------------------------------------------------

@test "main: exports YUNOMI_SCRIPTS_DIR as absolute scripts directory path" {
  # use a tempfile to extract YUNOMI_SCRIPTS_DIR (stdout is captured by $())
  local scripts_dir_file
  scripts_dir_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
source '$SCRIPT'
require_command() { return 0; }
ghq() { echo "/tmp/ghq-root"; }
export -f ghq
show_repo_list() {
  printf '%s' "\$YUNOMI_SCRIPTS_DIR" >"$scripts_dir_file"
  return 1  # end loop
}
main
SCRIPT

  run bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  local recorded_dir
  recorded_dir=$(cat "$scripts_dir_file")
  rm -f "$scripts_dir_file"

  [[ -n "$recorded_dir" ]]
  [[ "$recorded_dir" == /* ]]
  [[ "$recorded_dir" == *"/scripts" ]]
}

# ---------------------------------------------------------------------------
# Screen transition loop: full path resolution using ghq root
# ---------------------------------------------------------------------------

@test "main: repo_path is resolved as ghq_root/ghq_path" {
  mock_ghq
  mock_hashi

  # show_repo_list returns a fixed ghq_path
  # show_branch_list records the received repo_path and returns 1 (end loop)
  local repo_path_file
  repo_path_file=$(mktemp)
  export repo_path_file

  run bash -c "
    source '$SCRIPT'
    show_repo_list() { echo 'github.com/wasabi0522/yunomi'; return 0; }
    show_branch_list() {
      echo \"\$1\" >>\"$repo_path_file\"
      return 1  # end loop with a non-Esc exit code
    }
    command() { return 0; }
    export -f command show_repo_list show_branch_list
    main
  " </dev/null

  local recorded_path
  recorded_path=$(cat "$repo_path_file")
  rm -f "$repo_path_file"

  # ghq root (/home/user/ghq) + ghq_path must be joined
  [ "$recorded_path" = "/home/user/ghq/github.com/wasabi0522/yunomi" ]
}

@test "main: loop continues on exit code 130 (Esc from show_branch_list)" {
  mock_ghq
  mock_hashi

  # show_repo_list fails on the 3rd call to end the loop
  local call_count_file
  call_count_file=$(mktemp)
  printf '0' >"$call_count_file"
  export call_count_file

  run bash -c "
    source '$SCRIPT'
    show_repo_list() {
      local count
      count=\$(cat \"$call_count_file\")
      count=\$((count + 1))
      printf '%s' \"\$count\" >\"$call_count_file\"
      if [[ \$count -le 2 ]]; then
        echo 'github.com/wasabi0522/yunomi'
        return 0
      fi
      return 1  # exit on 3rd call
    }
    show_branch_list() { return 130; }  # always Esc
    command() { return 0; }
    export -f command show_repo_list show_branch_list
    main
  " </dev/null

  # show_repo_list must be called 3 times (2 Esc presses return to screen 1, 3rd call ends loop)
  local call_count
  call_count=$(cat "$call_count_file")
  rm -f "$call_count_file"
  [ "$call_count" -eq 3 ]
}

@test "main: loop breaks on exit code other than 130 (e.g. accept/switch)" {
  mock_ghq
  mock_hashi

  local call_count_file
  call_count_file=$(mktemp)
  printf '0' >"$call_count_file"
  export call_count_file

  run bash -c "
    source '$SCRIPT'
    show_repo_list() {
      local count
      count=\$(cat \"$call_count_file\")
      count=\$((count + 1))
      printf '%s' \"\$count\" >\"$call_count_file\"
      echo 'github.com/wasabi0522/yunomi'
      return 0
    }
    show_branch_list() { return 0; }  # become (exit 0)
    command() { return 0; }
    export -f command show_repo_list show_branch_list
    main
  " </dev/null

  # show_repo_list must be called exactly once (loop ends after become)
  local call_count
  call_count=$(cat "$call_count_file")
  rm -f "$call_count_file"
  [ "$call_count" -eq 1 ]
}

@test "main: loop breaks when EXIT_FLAG is set" {
  mock_ghq
  mock_hashi

  local call_count_file
  call_count_file=$(mktemp)
  printf '0' >"$call_count_file"
  export call_count_file

  run bash -c "
    source '$SCRIPT'
    show_repo_list() {
      local count
      count=\$(cat \"$call_count_file\")
      count=\$((count + 1))
      printf '%s' \"\$count\" >\"$call_count_file\"
      echo 'github.com/wasabi0522/yunomi'
      return 0
    }
    show_branch_list() {
      # create EXIT_FLAG then return 130 (normally Esc, but EXIT_FLAG takes priority)
      touch \"\$YUNOMI_EXIT_FLAG\"
      return 130
    }
    command() { return 0; }
    export -f command show_repo_list show_branch_list
    main
  " </dev/null

  # when EXIT_FLAG is set, loop must break even on exit 130
  local call_count
  call_count=$(cat "$call_count_file")
  rm -f "$call_count_file"
  [ "$call_count" -eq 1 ]
}

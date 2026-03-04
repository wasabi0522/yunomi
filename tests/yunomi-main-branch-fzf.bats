#!/usr/bin/env bats

load 'test_helper'

# Path to the script under test
SCRIPT="$PROJECT_ROOT/scripts/yunomi-main.sh"

# ---------------------------------------------------------------------------
# fzf integration tests for show_branch_list
# ---------------------------------------------------------------------------

@test "show_branch_list: exports YUNOMI_HASHI_JSON before calling fzf" {
  # verify that hashi list --json is called and YUNOMI_HASHI_JSON is exported
  # pass an actual existing directory as repo_path so cd succeeds
  local hashi_json_file repo_path
  hashi_json_file=$(mktemp)
  repo_path=$(mktemp -d)
  export hashi_json_file repo_path

  run bash -c "
    MOCK_HASHI_JSON='[{\"branch\":\"main\",\"active\":true}]'
    export MOCK_HASHI_JSON
    hashi() {
      if [[ \"\$1\" == 'list' ]]; then
        printf '%s\n' \"\$MOCK_HASHI_JSON\"
        return 0
      fi
    }
    export -f hashi
    fzf() {
      # record YUNOMI_HASHI_JSON then abort
      printf '%s' \"\${YUNOMI_HASHI_JSON:-NOT_SET}\" >\"$hashi_json_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list \"$repo_path\" >/dev/null 2>&1 || true
  "

  local recorded
  recorded=$(cat "$hashi_json_file")
  rm -f "$hashi_json_file"
  rmdir "$repo_path" 2>/dev/null || true

  [[ "$recorded" != "NOT_SET" ]]
  [[ "$recorded" == *"main"* ]]
}

@test "show_branch_list: fzf is called with --with-nth=2.. and --delimiter tab" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--with-nth"
  assert_output --partial "2.."
  assert_output --partial "--delimiter"
}

@test "show_branch_list: fzf is called with --prompt Branch>" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--prompt"
  assert_output --partial "Branch>"
}

@test "show_branch_list: fzf is called with --header-lines 1" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--header-lines"
  assert_output --partial "1"
}

@test "show_branch_list: fzf is called with --header-border line" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--header-border"
  assert_output --partial "line"
}

@test "show_branch_list: fzf is called with --border-label yunomi" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--border-label"
  assert_output --partial "yunomi"
}

@test "show_branch_list: fzf is called without --tmux option" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  refute_output --partial "--tmux"
}

@test "show_branch_list: fzf footer contains enter:switch and esc:back" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "enter:switch"
  assert_output --partial "esc:back"
}

@test "show_branch_list: fzf is called with enter:accept binding" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "enter:accept"
}

@test "show_branch_list: fzf is called with default new key binding (ctrl-o)" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "ctrl-o"
  assert_output --partial "yunomi-fzf-action.sh"
}

@test "show_branch_list: fzf is called with default delete key binding (ctrl-d)" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "ctrl-d"
}

@test "show_branch_list: fzf is called with default rename key binding (ctrl-r)" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "ctrl-r"
}

@test "show_branch_list: fzf bind for new contains yunomi-fzf-action.sh new" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "yunomi-fzf-action.sh"
  assert_output --partial "new"
}

@test "show_branch_list: fzf bind for remove contains yunomi-fzf-action.sh remove" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "remove"
}

@test "show_branch_list: fzf bind for rename contains yunomi-fzf-action.sh rename" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "rename"
}

@test "show_branch_list: fzf is called with --preview when @yunomi-preview is on" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    # tmux returns 'on' (default)
    tmux() { echo ''; }
    export -f tmux
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--preview"
  assert_output --partial "yunomi-preview.sh"
}

@test "show_branch_list: fzf is called without --preview when @yunomi-preview is off" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    # tmux returns 'off' (preview disabled)
    tmux() {
      if [[ \"\$*\" == *'@yunomi-preview'* ]]; then
        echo 'off'
      else
        echo ''
      fi
    }
    export -f tmux
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  refute_output --partial "yunomi-preview.sh"
}

@test "show_branch_list: fzf is called with focus:transform-preview-label binding" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "focus"
  assert_output --partial "transform-preview-label"
}

@test "show_branch_list: custom new key binding is reflected in fzf bind" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    # tmux returns ctrl-n for @yunomi-bind-new
    tmux() {
      if [[ \"\$*\" == *'@yunomi-bind-new'* ]]; then
        echo 'ctrl-n'
      else
        echo ''
      fi
    }
    export -f tmux
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "ctrl-n"
}

@test "show_branch_list: invalid key binding falls back to default (ctrl-o for new)" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    # tmux returns an invalid key name for @yunomi-bind-new
    tmux() {
      if [[ \"\$*\" == *'@yunomi-bind-new'* ]]; then
        echo 'INVALID-KEY!!!'
      else
        echo ''
      fi
    }
    export -f tmux
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  # Invalid key should fall back to default ctrl-o
  assert_output --partial "ctrl-o"
  # Invalid key should not appear in the fzf args
  refute_output --partial "INVALID-KEY"
}

@test "show_branch_list: repo_path with spaces is properly escaped in action bindings" {
  local fzf_args_file
  fzf_args_file=$(mktemp)
  export fzf_args_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() {
      printf '%s\n' \"\$@\" >\"$fzf_args_file\"
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/path with spaces/repo' >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  # path with spaces must be properly escaped in fzf-action bindings
  assert_output --partial "yunomi-fzf-action.sh"
  # spaces must be escaped (raw spaces must not appear as part of the path)
  [[ "$output" != *"path with spaces"* ]] || [[ "$output" == *"path\ with\ spaces"* ]] || [[ "$output" == *"'path with spaces'"* ]]
}

@test "show_branch_list: fzf exit code is returned as-is (130 for Esc)" {
  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() { return 130; }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo'
    echo \"exit_code=\$?\"
  "

  assert_output --partial "exit_code=130"
}

@test "show_branch_list: on accept, hashi switch is called with selected branch name" {
  local hashi_calls_file
  hashi_calls_file=$(mktemp)
  export hashi_calls_file

  local repo_path
  repo_path=$(mktemp -d)
  export repo_path

  run bash -c "
    hashi() {
      printf '%s\n' \"\$*\" >>\"$hashi_calls_file\"
      if [[ \"\$1\" == 'list' ]]; then
        printf '[{\"branch\":\"main\",\"active\":true}]\n'
      fi
    }
    export -f hashi
    fzf() {
      printf 'feature/login\t * feature/login  clean\n'
      return 0
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list \"$repo_path\" >/dev/null 2>&1 || true
  "

  run grep 'switch' "$hashi_calls_file"
  assert_output --partial "switch"
  assert_output --partial "feature/login"
  rm -f "$hashi_calls_file"
  rmdir "$repo_path" 2>/dev/null || true
}

@test "show_branch_list: fzf exit code is returned as-is (0 for accept)" {
  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    fzf() { return 0; }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo'
    echo \"exit_code=\$?\"
  "

  assert_output --partial "exit_code=0"
}

@test "show_branch_list: input is piped from yunomi-branch-list.sh" {
  local branch_list_called_file
  branch_list_called_file=$(mktemp)
  export branch_list_called_file

  run bash -c "
    hashi() { printf '[]\n'; }
    export -f hashi
    YUNOMI_SCRIPTS_DIR='\$(mktemp -d)'
    # create a mock of yunomi-branch-list.sh in the scripts directory
    local scripts_dir
    scripts_dir=\$(mktemp -d)
    export YUNOMI_SCRIPTS_DIR=\"\$scripts_dir\"
    cat >\"\$scripts_dir/yunomi-branch-list.sh\" <<'MOCK'
#!/bin/sh
printf '%s' 'called' >\"$branch_list_called_file\"
printf '\tbranch header\n'
printf 'main\t * main  clean\n'
MOCK
    chmod +x \"\$scripts_dir/yunomi-branch-list.sh\"
    fzf() {
      cat >/dev/null  # consume stdin
      return 130
    }
    export -f fzf
    source '$SCRIPT'
    show_branch_list '/tmp/test-repo' >/dev/null 2>&1 || true
  "

  local called
  called=$(cat "$branch_list_called_file")
  rm -f "$branch_list_called_file"

  [[ "$called" == "called" ]]
}

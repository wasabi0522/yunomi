#!/usr/bin/env bats

load 'test_helper'

# Path to the script under test
SCRIPT="$PROJECT_ROOT/scripts/yunomi-main.sh"

# ---------------------------------------------------------------------------
# show_repo_list: formatting the output of ghq list
# ---------------------------------------------------------------------------

@test "show_repo_list: first line is header with REPO label" {
  local fzf_input_file
  fzf_input_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
ghq() {
  case "\$1" in
    list)
      printf '%s\n' 'github.com/wasabi0522/yunomi'
      printf '%s\n' 'github.com/wasabi0522/chawan'
      ;;
    root) printf '%s\n' '/home/user/ghq' ;;
  esac
}
export -f ghq
fzf() {
  cat >>"$fzf_input_file"
  return 1
}
export -f fzf
source '$SCRIPT'
show_repo_list >/dev/null 2>&1 || true
SCRIPT

  bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  # first line must be the header line (TAB + "REPO")
  local header_line
  header_line=$(head -n 1 "$fzf_input_file")
  rm -f "$fzf_input_file"

  [[ "$header_line" == $'\t'"ORG/REPO" ]]
}

@test "show_repo_list: formats ghq list output as ghq_path TAB org/repo" {
  local fzf_input_file
  fzf_input_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
ghq() {
  case "\$1" in
    list)
      printf '%s\n' 'github.com/wasabi0522/yunomi'
      printf '%s\n' 'github.com/wasabi0522/chawan'
      ;;
    root) printf '%s\n' '/home/user/ghq' ;;
  esac
}
export -f ghq
fzf() {
  cat >>"$fzf_input_file"
  return 1
}
export -f fzf
source '$SCRIPT'
show_repo_list >/dev/null 2>&1 || true
SCRIPT

  bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  # validate data lines after the header line (line 1)
  local line1 line2
  line1=$(sed -n '2p' "$fzf_input_file")
  line2=$(sed -n '3p' "$fzf_input_file")
  rm -f "$fzf_input_file"

  [[ "$line1" == "github.com/wasabi0522/yunomi"$'\t'"wasabi0522/yunomi" ]]
  [[ "$line2" == "github.com/wasabi0522/chawan"$'\t'"wasabi0522/chawan" ]]
}

@test "show_repo_list: single-level host is stripped from display name" {
  # when ghq list returns gitlab.com/myorg/myrepo, display name must be myorg/myrepo
  local fzf_input_file
  fzf_input_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
ghq() {
  case "\$1" in
    list) printf '%s\n' 'gitlab.com/myorg/myrepo' ;;
    root) printf '%s\n' '/home/user/ghq' ;;
  esac
}
export -f ghq
fzf() {
  cat >>"$fzf_input_file"
  return 1
}
export -f fzf
source '$SCRIPT'
show_repo_list >/dev/null 2>&1 || true
SCRIPT

  bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  # validate the data line on line 2 (immediately after the header line)
  local result
  result=$(sed -n '2p' "$fzf_input_file")
  rm -f "$fzf_input_file"

  # second field (display name) must be "myorg/myrepo"
  local display_name
  display_name=$(printf '%s' "$result" | cut -f2)
  [ "$display_name" = "myorg/myrepo" ]
}

@test "show_repo_list: ghq_path is preserved as first field (tab delimiter)" {
  # verify that the first field of each line is ghq_path (full path) for multiple repos
  local fzf_input_file
  fzf_input_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
ghq() {
  case "\$1" in
    list)
      printf '%s\n' 'github.com/foo/bar'
      printf '%s\n' 'github.com/baz/qux'
      ;;
    root) printf '%s\n' '/home/user/ghq' ;;
  esac
}
export -f ghq
fzf() {
  cat >>"$fzf_input_file"
  return 1
}
export -f fzf
source '$SCRIPT'
show_repo_list >/dev/null 2>&1 || true
SCRIPT

  bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  # skip the header line (line 1) and validate data lines
  local field1_line1 field1_line2
  field1_line1=$(sed -n '2p' "$fzf_input_file" | cut -f1)
  field1_line2=$(sed -n '3p' "$fzf_input_file" | cut -f1)
  rm -f "$fzf_input_file"

  [ "$field1_line1" = "github.com/foo/bar" ]
  [ "$field1_line2" = "github.com/baz/qux" ]
}

# ---------------------------------------------------------------------------
# show_repo_list: fzf option verification
# ---------------------------------------------------------------------------

@test "show_repo_list: fzf is called with --header-lines 1" {
  mock_ghq

  local fzf_args_file
  fzf_args_file=$(mktemp)

  fzf() {
    printf '%s\n' "$@" >"$fzf_args_file"
    return 1
  }
  export -f fzf
  export fzf_args_file

  bash -c "
    source '$SCRIPT'
    show_repo_list >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--header-lines"
  assert_output --partial "1"
}

@test "show_repo_list: fzf is called with --with-nth=2.. and --delimiter tab" {
  mock_ghq

  # mock that records fzf arguments
  local fzf_args_file
  fzf_args_file=$(mktemp)

  fzf() {
    printf '%s\n' "$@" >"$fzf_args_file"
    return 1  # abort
  }
  export -f fzf
  export fzf_args_file

  # source and call show_repo_list
  bash -c "
    source '$SCRIPT'
    show_repo_list >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--with-nth"
  assert_output --partial "2.."
  assert_output --partial "--delimiter"
}

@test "show_repo_list: fzf is called with --prompt Repo>" {
  mock_ghq

  local fzf_args_file
  fzf_args_file=$(mktemp)

  fzf() {
    printf '%s\n' "$@" >"$fzf_args_file"
    return 1
  }
  export -f fzf
  export fzf_args_file

  bash -c "
    source '$SCRIPT'
    show_repo_list >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--prompt"
  assert_output --partial "Repo>"
}

@test "show_repo_list: fzf is called with --border-label yunomi" {
  mock_ghq

  local fzf_args_file
  fzf_args_file=$(mktemp)

  fzf() {
    printf '%s\n' "$@" >"$fzf_args_file"
    return 1
  }
  export -f fzf
  export fzf_args_file

  bash -c "
    source '$SCRIPT'
    show_repo_list >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "--border-label"
  assert_output --partial "yunomi"
}

@test "show_repo_list: fzf is called without --tmux option" {
  mock_ghq

  local fzf_args_file
  fzf_args_file=$(mktemp)

  fzf() {
    printf '%s\n' "$@" >"$fzf_args_file"
    return 1
  }
  export -f fzf
  export fzf_args_file

  bash -c "
    source '$SCRIPT'
    show_repo_list >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  # must not contain the --tmux option
  refute_output --partial "--tmux"
}

@test "show_repo_list: fzf footer contains enter:select and esc:close" {
  mock_ghq

  local fzf_args_file
  fzf_args_file=$(mktemp)

  fzf() {
    printf '%s\n' "$@" >"$fzf_args_file"
    return 1
  }
  export -f fzf
  export fzf_args_file

  bash -c "
    source '$SCRIPT'
    show_repo_list >/dev/null 2>&1 || true
  "

  run cat "$fzf_args_file"
  rm -f "$fzf_args_file"

  assert_output --partial "enter:select"
  assert_output --partial "esc:close"
}

# ---------------------------------------------------------------------------
# repo-sort option
# ---------------------------------------------------------------------------

# default (name) preserves ghq list order
@test "show_repo_list: default sort preserves ghq list order" {
  local fzf_input_file
  fzf_input_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
ghq() {
  case "\$1" in
    list)
      printf '%s\n' 'github.com/wasabi0522/zebra'
      printf '%s\n' 'github.com/wasabi0522/alpha'
      printf '%s\n' 'github.com/wasabi0522/middle'
      ;;
    root) printf '%s\n' '/home/user/ghq' ;;
  esac
}
export -f ghq
tmux() { echo ''; }
export -f tmux
fzf() {
  cat >>"$fzf_input_file"
  return 1
}
export -f fzf
source '$SCRIPT'
show_repo_list >/dev/null 2>&1 || true
SCRIPT

  bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  # @yunomi-repo-sort unset (tmux returns '') → default "name" → preserves ghq list order
  # skip header line (line 1) and validate data lines
  local f1 f2 f3
  f1=$(sed -n '2p' "$fzf_input_file" | cut -f1)
  f2=$(sed -n '3p' "$fzf_input_file" | cut -f1)
  f3=$(sed -n '4p' "$fzf_input_file" | cut -f1)
  rm -f "$fzf_input_file"

  [ "$f1" = "github.com/wasabi0522/zebra" ]
  [ "$f2" = "github.com/wasabi0522/alpha" ]
  [ "$f3" = "github.com/wasabi0522/middle" ]
}

# mru sort places the repo with the largest file_mtime first
@test "show_repo_list: mru sort puts recently used repo first" {
  local fzf_input_file
  fzf_input_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
ghq() {
  case "\$1" in
    list)
      printf '%s\n' 'github.com/wasabi0522/older-repo'
      printf '%s\n' 'github.com/wasabi0522/newer-repo'
      ;;
    root) printf '%s\n' '/home/user/ghq' ;;
  esac
}
export -f ghq
tmux() {
  if [[ "\$*" == *"@yunomi-repo-sort"* ]]; then
    echo "mru"
  else
    echo ''
  fi
}
export -f tmux
source '$SCRIPT'
# override file_mtime after helpers.sh is sourced
file_mtime() {
  case "\$1" in
    */newer-repo/.git/HEAD) echo "2000" ;;
    */older-repo/.git/HEAD) echo "1000" ;;
    *)                      echo "0" ;;
  esac
}
export -f file_mtime
fzf() {
  cat >>"$fzf_input_file"
  return 1
}
export -f fzf
show_repo_list >/dev/null 2>&1 || true
SCRIPT

  bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  # skip header line (line 1) and validate data lines
  # newer-repo with mtime 2000 must appear first
  local f1 f2
  f1=$(sed -n '2p' "$fzf_input_file" | cut -f1)
  f2=$(sed -n '3p' "$fzf_input_file" | cut -f1)
  rm -f "$fzf_input_file"

  [ "$f1" = "github.com/wasabi0522/newer-repo" ]
  [ "$f2" = "github.com/wasabi0522/older-repo" ]
}

# when all mtimes are 0 in mru sort, preserve ghq list input order (stable sort)
@test "show_repo_list: mru sort with equal mtime preserves input order" {
  local fzf_input_file
  fzf_input_file=$(mktemp)
  local tmpscript
  tmpscript=$(mktemp)
  cat >"$tmpscript" <<SCRIPT
ghq() {
  case "\$1" in
    list)
      printf '%s\n' 'github.com/wasabi0522/repo-a'
      printf '%s\n' 'github.com/wasabi0522/repo-b'
      printf '%s\n' 'github.com/wasabi0522/repo-c'
      ;;
    root) printf '%s\n' '/home/user/ghq' ;;
  esac
}
export -f ghq
tmux() {
  if [[ "\$*" == *"@yunomi-repo-sort"* ]]; then
    echo "mru"
  else
    echo ''
  fi
}
export -f tmux
source '$SCRIPT'
# override file_mtime after helpers.sh is sourced
file_mtime() {
  echo "0"
}
export -f file_mtime
fzf() {
  cat >>"$fzf_input_file"
  return 1
}
export -f fzf
show_repo_list >/dev/null 2>&1 || true
SCRIPT

  bash "$tmpscript" </dev/null
  rm -f "$tmpscript"

  # skip header line (line 1) and validate data lines
  # all mtime=0 → sort -s (stable) preserves input order
  local f1 f2 f3
  f1=$(sed -n '2p' "$fzf_input_file" | cut -f1)
  f2=$(sed -n '3p' "$fzf_input_file" | cut -f1)
  f3=$(sed -n '4p' "$fzf_input_file" | cut -f1)
  rm -f "$fzf_input_file"

  [ "$f1" = "github.com/wasabi0522/repo-a" ]
  [ "$f2" = "github.com/wasabi0522/repo-b" ]
  [ "$f3" = "github.com/wasabi0522/repo-c" ]
}

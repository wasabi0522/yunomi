#!/usr/bin/env bats

load 'test_helper'

setup_file() {
  YUNOMI_TMUX="$PROJECT_ROOT/yunomi.tmux"
  export YUNOMI_TMUX
}

setup() {
  setup_mocks
  mock_fzf_available

  # Mock tmux: record calls and handle show-option and -V
  tmux() {
    echo "$@" >>"$MOCK_TMUX_CALLS"
    case "$1" in
      -V) echo "tmux 3.4" ;;
      show-option)
        # Default: return empty (use default values)
        echo ""
        ;;
    esac
  }
  export -f tmux
}

teardown() {
  teardown_mocks
}

# ---------------------------------------------------------------------------
# tmux version check
# ---------------------------------------------------------------------------

@test "yunomi.tmux: error when tmux version is too old (3.2)" {
  tmux() {
    echo "$@" >>"$MOCK_TMUX_CALLS"
    case "$1" in
      -V) echo "tmux 3.2" ;;
      show-option) echo "" ;;
    esac
  }
  export -f tmux

  run "$YUNOMI_TMUX"
  assert_failure

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "display-message"
  assert_output --partial "3.3"
}

@test "yunomi.tmux: error message mentions tmux version requirement" {
  tmux() {
    echo "$@" >>"$MOCK_TMUX_CALLS"
    case "$1" in
      -V) echo "tmux 3.2" ;;
      show-option) echo "" ;;
    esac
  }
  export -f tmux

  run "$YUNOMI_TMUX"
  assert_failure

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "yunomi"
}

# ---------------------------------------------------------------------------
# fzf installation check
# ---------------------------------------------------------------------------

@test "yunomi.tmux: error when fzf is not installed" {
  fzf() {
    return 1
  }
  export -f fzf

  command() {
    if [[ "$1" == "-v" && "$2" == "fzf" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  run "$YUNOMI_TMUX"
  assert_failure

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "display-message"
  assert_output --partial "fzf"
}

# ---------------------------------------------------------------------------
# fzf version check
# ---------------------------------------------------------------------------

@test "yunomi.tmux: error when fzf version is too old (0.62)" {
  mock_fzf_available "0.62.0 (brew)"

  run "$YUNOMI_TMUX"
  assert_failure

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "display-message"
  assert_output --partial "0.63"
}

@test "yunomi.tmux: error message mentions fzf version requirement" {
  mock_fzf_available "0.62.0 (brew)"

  run "$YUNOMI_TMUX"
  assert_failure

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "yunomi"
}

# ---------------------------------------------------------------------------
# bind-key registration (happy path)
# ---------------------------------------------------------------------------

@test "yunomi.tmux: bind-key is called when versions are sufficient" {
  run "$YUNOMI_TMUX"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "bind-key"
}

@test "yunomi.tmux: uses default key G when @yunomi-key is unset" {
  run "$YUNOMI_TMUX"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "bind-key G "
}

@test "yunomi.tmux: uses custom key R when @yunomi-key is set to R" {
  tmux() {
    echo "$@" >>"$MOCK_TMUX_CALLS"
    case "$1" in
      -V) echo "tmux 3.4" ;;
      show-option)
        if [[ "$3" == "@yunomi-key" ]]; then
          echo "R"
        else
          echo ""
        fi
        ;;
    esac
  }
  export -f tmux

  run "$YUNOMI_TMUX"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "bind-key R "
}

# ---------------------------------------------------------------------------
# Key binding validation
# ---------------------------------------------------------------------------

@test "yunomi.tmux: error when @yunomi-key contains invalid characters" {
  tmux() {
    echo "$@" >>"$MOCK_TMUX_CALLS"
    case "$1" in
      -V) echo "tmux 3.4" ;;
      show-option)
        if [[ "$3" == "@yunomi-key" ]]; then
          echo '!@#'
        else
          echo ""
        fi
        ;;
    esac
  }
  export -f tmux

  run "$YUNOMI_TMUX"
  assert_failure

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "display-message"
  assert_output --partial "invalid key binding"
}

# ---------------------------------------------------------------------------
# Popup width/height settings reflection
# ---------------------------------------------------------------------------

@test "yunomi.tmux: bind-key includes default popup width 80%" {
  run "$YUNOMI_TMUX"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "80%"
}

@test "yunomi.tmux: bind-key includes default popup height 70%" {
  run "$YUNOMI_TMUX"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "70%"
}

@test "yunomi.tmux: custom popup width is reflected in bind-key" {
  tmux() {
    echo "$@" >>"$MOCK_TMUX_CALLS"
    case "$1" in
      -V) echo "tmux 3.4" ;;
      show-option)
        if [[ "$3" == "@yunomi-popup-width" ]]; then
          echo "90%"
        else
          echo ""
        fi
        ;;
    esac
  }
  export -f tmux

  run "$YUNOMI_TMUX"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "90%"
}

@test "yunomi.tmux: custom popup height is reflected in bind-key" {
  tmux() {
    echo "$@" >>"$MOCK_TMUX_CALLS"
    case "$1" in
      -V) echo "tmux 3.4" ;;
      show-option)
        if [[ "$3" == "@yunomi-popup-height" ]]; then
          echo "80%"
        else
          echo ""
        fi
        ;;
    esac
  }
  export -f tmux

  run "$YUNOMI_TMUX"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "80%"
}

# ---------------------------------------------------------------------------
# display-popup -E registration check
# ---------------------------------------------------------------------------

@test "yunomi.tmux: bind-key command includes display-popup -E" {
  run "$YUNOMI_TMUX"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "display-popup"
  assert_output --partial "-E"
}

@test "yunomi.tmux: bind-key command includes yunomi-main.sh" {
  run "$YUNOMI_TMUX"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  assert_output --partial "yunomi-main.sh"
}

# ---------------------------------------------------------------------------
# Escaping check when script path contains spaces
# ---------------------------------------------------------------------------

@test "yunomi.tmux: script path with spaces is properly escaped in bind-key" {
  # run yunomi.tmux from a directory with spaces in the path to verify
  # that printf -v escaped_main '%q' escapes it correctly
  local tmpdir
  tmpdir=$(mktemp -d)
  local spaced_dir="$tmpdir/my yunomi plugin"
  mkdir -p "$spaced_dir/scripts"

  # Place copies (stubs) of yunomi.tmux, helpers.sh, and yunomi-main.sh
  cp "$PROJECT_ROOT/yunomi.tmux" "$spaced_dir/yunomi.tmux"
  cp "$PROJECT_ROOT/scripts/helpers.sh" "$spaced_dir/scripts/helpers.sh"
  touch "$spaced_dir/scripts/yunomi-main.sh"
  chmod +x "$spaced_dir/scripts/yunomi-main.sh"

  run "$spaced_dir/yunomi.tmux"
  assert_success

  run cat "$MOCK_TMUX_CALLS"
  # bind-key must be called (an error exit would indicate path escaping failure)
  assert_output --partial "bind-key"

  rm -rf "$tmpdir"
}

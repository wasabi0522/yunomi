#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$CURRENT_DIR/scripts"

# shellcheck source=scripts/helpers.sh
source "$SCRIPTS_DIR/helpers.sh"

main() {
  local tmux_version fzf_version key popup_width popup_height escaped_main

  local tmux_v_out
  tmux_v_out=$(tmux -V)
  if [[ "$tmux_v_out" =~ ([0-9]+\.[0-9]+) ]]; then
    tmux_version="${BASH_REMATCH[1]}"
  else
    tmux_version=""
  fi
  if ! version_ge "$tmux_version" "3.3"; then
    display_message "yunomi: tmux 3.3+ is required (found $tmux_version)"
    exit 1
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    display_message "yunomi: fzf is not installed"
    exit 1
  fi

  local fzf_v_out
  fzf_v_out=$(fzf --version)
  if [[ "$fzf_v_out" =~ ([0-9]+\.[0-9]+) ]]; then
    fzf_version="${BASH_REMATCH[1]}"
  else
    fzf_version=""
  fi
  if ! version_ge "$fzf_version" "0.63"; then
    display_message "yunomi: fzf 0.63+ is required (found $fzf_version)"
    exit 1
  fi

  key=$(get_option "@yunomi-key" "G")
  popup_width=$(get_option "@yunomi-popup-width" "80%")
  popup_height=$(get_option "@yunomi-popup-height" "70%")

  if ! validate_bind_key "$key"; then
    display_message "yunomi: invalid key binding: $key"
    exit 1
  fi

  if ! validate_popup_size "$popup_width"; then
    display_message "yunomi: invalid popup width: $popup_width"
    exit 1
  fi
  if ! validate_popup_size "$popup_height"; then
    display_message "yunomi: invalid popup height: $popup_height"
    exit 1
  fi

  local escaped_main escaped_width escaped_height
  printf -v escaped_main '%q' "$SCRIPTS_DIR/yunomi-main.sh"
  printf -v escaped_width '%q' "$popup_width"
  printf -v escaped_height '%q' "$popup_height"
  tmux bind-key "$key" run-shell -b \
    "tmux display-popup -E -w $escaped_width -h $escaped_height $escaped_main"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi

#!/usr/bin/env bash
# Restores the most recently minimized window to the active workspace.
#
# Sequential hyprctl calls (never backgrounded) so float/geometry/focus land
# after the workspace move. Optional widget memory at
# $XDG_STATE_HOME/omarchy/dev-herni.minimized.json covers the case where
# Hyprland dropped floating while the window sat on special:minimized.
set -euo pipefail

MEMORY="${MINIMIZED_FLOAT_MEMORY:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/dev-herni.minimized.json}"

client=$(hyprctl -j clients | jq -c '
  [.[] | select(.workspace.name == "special:minimized")]
  | sort_by(.focusHistoryID)
  | .[0] // empty
')
[ -n "$client" ] || exit 0

addr=$(jq -r '.address // empty' <<<"$client")
[ -n "$addr" ] || exit 0
key="${addr#0x}"
key="${key#0X}"
if [[ ! "$key" =~ ^[0-9a-fA-F]{1,16}$ ]]; then
  exit 0
fi
window="address:0x${key}"
key="${key,,}"

ws=$(hyprctl -j activeworkspace | jq '.id')
if [[ ! "$ws" =~ ^[1-9][0-9]*$ ]]; then
  ws=1
fi

floating=$(jq -r '.floating' <<<"$client")
at0=$(jq -r '.at[0] // empty' <<<"$client")
at1=$(jq -r '.at[1] // empty' <<<"$client")
size0=$(jq -r '.size[0] // empty' <<<"$client")
size1=$(jq -r '.size[1] // empty' <<<"$client")

if [[ -f "$MEMORY" ]]; then
  mem=$(jq -c --arg k "$key" '.[$k] // empty' "$MEMORY" 2>/dev/null || true)
  if [[ -n "$mem" && "$(jq -r '.floating' <<<"$mem")" == "true" ]]; then
    floating=true
    at0=$(jq -r '.at[0] // empty' <<<"$mem")
    at1=$(jq -r '.at[1] // empty' <<<"$mem")
    size0=$(jq -r '.size[0] // empty' <<<"$mem")
    size1=$(jq -r '.size[1] // empty' <<<"$mem")
  fi
fi

hyprctl dispatch "hl.dsp.window.move({ window = \"${window}\", workspace = ${ws}, follow = false })"

if [[ "$floating" == "true" ]]; then
  hyprctl dispatch "hl.dsp.window.float({ window = \"${window}\", action = \"enable\" })"
  if [[ -n "$size0" && -n "$size1" ]]; then
    hyprctl dispatch "hl.dsp.window.resize({ window = \"${window}\", x = ${size0}, y = ${size1}, relative = false })"
  fi
  if [[ -n "$at0" && -n "$at1" ]]; then
    hyprctl dispatch "hl.dsp.window.move({ window = \"${window}\", x = ${at0}, y = ${at1}, relative = false })"
  else
    hyprctl dispatch "hl.dsp.window.center({ window = \"${window}\" })"
  fi
fi

hyprctl dispatch "hl.dsp.focus({ window = \"${window}\" })"

open=$(hyprctl -j monitors | jq '[.[] | select(.specialWorkspace.name=="special:minimized")] | length')
if [ "${open:-0}" -gt 0 ]; then
  hyprctl dispatch 'hl.dsp.workspace.toggle_special("minimized")' >/dev/null
fi

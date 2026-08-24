#!/usr/bin/env bash
# Restores the most recently minimized window to the active workspace.
#
# The bar widget deliberately exposes no IPC; bind this script to a key
# instead (see README.md, "Optional: a restore-last keybind").
#
# Requires: hyprctl, jq (both ship with Omarchy).
set -euo pipefail

addr=$(hyprctl -j clients | jq -r '
  [.[] | select(.workspace.name == "special:minimized")]
  | sort_by(.focusHistoryID)
  | first | .address // empty')

[ -n "$addr" ] || exit 0

ws=$(hyprctl -j activeworkspace | jq '.id')
hyprctl dispatch "hl.dsp.window.move({ window = \"address:$addr\", workspace = $ws, follow = false })"
hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })"

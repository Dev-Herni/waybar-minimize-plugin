#!/usr/bin/env bash
# Restores a minimized window to the focused monitor's active workspace.
# With no argument, restores the most recently focused one. With a hex
# address, restores that window.
#
# Sequential hyprctl calls (never backgrounded) so float/geometry/focus land
# after the workspace move. Optional widget memory at
# $XDG_STATE_HOME/omarchy/dev-herni.minimized.json covers the case where
# Hyprland dropped floating while the window sat on special:minimized.
set -euo pipefail

MEMORY="${MINIMIZED_FLOAT_MEMORY:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/dev-herni.minimized.json}"

wanted="${1:-}"
wanted="${wanted#0x}"
wanted="${wanted#0X}"
wanted="${wanted,,}"
if [[ -n "$wanted" && ! "$wanted" =~ ^[0-9a-f]{1,16}$ ]]; then
  exit 0
fi

if [[ -n "$wanted" ]]; then
  client=$(hyprctl -j clients | jq -c --arg k "$wanted" '
    [.[] | select(.workspace.name == "special:minimized")]
    | map(select((.address // "" | ascii_downcase | sub("^0x"; "")) == $k))
    | .[0] // empty
  ')
else
  client=$(hyprctl -j clients | jq -c '
    [.[] | select(.workspace.name == "special:minimized")]
    | sort_by(.focusHistoryID // 999999)
    | .[0] // empty
  ')
fi
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

ws=$(hyprctl -j monitors | jq -r '[.[] | select(.focused == true)][0].activeWorkspace.id' 2>/dev/null || true)
if [[ ! "$ws" =~ ^[1-9][0-9]*$ ]]; then
  ws=1
fi

floating=$(jq -r '.floating' <<<"$client")
at=$(jq -c '.at // empty' <<<"$client")
size=$(jq -c '.size // empty' <<<"$client")

# Mirrors MinimizedModel.boundedPoint: prints "x y" as integers within
# +/-100000, or nothing when the pair is missing/malformed/out of bounds.
bounded_point() {
  jq -r '
    if (type == "array") and (length >= 2)
       and ((.[0] | type) == "number") and ((.[0] >= -100000) and (.[0] <= 100000))
       and ((.[1] | type) == "number") and ((.[1] >= -100000) and (.[1] <= 100000))
    then "\(.[0] | round) \(.[1] | round)"
    else empty end
  ' <<<"$1" 2>/dev/null || true
}

at=$(bounded_point "$at")
size=$(bounded_point "$size")

if [[ -f "$MEMORY" ]]; then
  mem=$(jq -c --arg k "$key" '.[$k] // empty' "$MEMORY" 2>/dev/null || true)
  if [[ -n "$mem" && "$(jq -r '.floating' <<<"$mem")" == "true" ]]; then
    floating=true
    mem_at=$(bounded_point "$(jq -c '.at // empty' <<<"$mem")")
    mem_size=$(bounded_point "$(jq -c '.size // empty' <<<"$mem")")
    if [[ -n "$mem_at" ]]; then
      at="$mem_at"
    fi
    if [[ -n "$mem_size" ]]; then
      size="$mem_size"
    fi
  fi
fi

if [[ "$floating" == "true" && -n "$at" ]]; then
  read -r ax ay <<<"$at"
  sx=800
  sy=600
  if [[ -n "$size" ]]; then
    read -r sx sy <<<"$size"
  fi
  clamped=$(hyprctl -j monitors | jq -c \
    --argjson x "$ax" --argjson y "$ay" \
    --argjson w "$sx" --argjson h "$sy" '
    def overlap($ax; $ay; $aw; $ah; $m):
      $ax < ($m.x + $m.width) and ($ax + $aw) > $m.x
      and $ay < ($m.y + $m.height) and ($ay + $ah) > $m.y;
    [ .[] | {x, y, width, height} | select(.width > 0 and .height > 0) ] as $mons
    | if ($mons | length) == 0 then [$x, $y]
      elif any($mons[]; overlap($x; $y; $w; $h; .)) then [$x, $y]
      else
        ($x + $w/2) as $cx | ($y + $h/2) as $cy
        | ($mons | min_by((($cx - (.x + .width/2)) * ($cx - (.x + .width/2)))
            + (($cy - (.y + .height/2)) * ($cy - (.y + .height/2))))) as $m
        | [(($m.x + ($m.width - $w)/2) | round), (($m.y + ($m.height - $h)/2) | round)]
      end
  ' 2>/dev/null || true)
  if [[ -n "$clamped" ]]; then
    at=$(jq -r 'if (type == "array") and (length >= 2) then "\(.[0]) \(.[1])" else empty end' <<<"$clamped" 2>/dev/null || true)
  fi
fi

hyprctl dispatch "hl.dsp.window.move({ window = \"${window}\", workspace = ${ws}, follow = false })"

if [[ "$floating" == "true" ]]; then
  hyprctl dispatch "hl.dsp.window.float({ window = \"${window}\", action = \"enable\" })"
  if [[ -n "$size" ]]; then
    read -r sx sy <<<"$size"
    hyprctl dispatch "hl.dsp.window.resize({ window = \"${window}\", x = ${sx}, y = ${sy}, relative = false })"
  fi
  if [[ -n "$at" ]]; then
    read -r ax ay <<<"$at"
    hyprctl dispatch "hl.dsp.window.move({ window = \"${window}\", x = ${ax}, y = ${ay}, relative = false })"
  else
    hyprctl dispatch "hl.dsp.window.center({ window = \"${window}\" })"
  fi
fi

hyprctl dispatch "hl.dsp.focus({ window = \"${window}\" })"

open=$(hyprctl -j monitors | jq '[.[] | select(.specialWorkspace.name=="special:minimized")] | length')
if [ "${open:-0}" -gt 0 ]; then
  hyprctl dispatch 'hl.dsp.workspace.toggle_special("minimized")' >/dev/null
fi

#!/usr/bin/env bash
# Get the last minimized window address
addr=$(hyprctl clients -j | jq -r '[.[] | select(.workspace.name == "special:minimized")] | last | .address')
if [ -n "$addr" ] && [ "$addr" != "null" ]; then
    active_ws=$(hyprctl activeworkspace -j | jq -r '.id')
    hyprctl dispatch movetoworkspace "$active_ws,address:$addr"
    hyprctl dispatch focuswindow "address:$addr"
fi

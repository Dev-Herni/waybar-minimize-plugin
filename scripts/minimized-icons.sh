#!/usr/bin/env bash

# Config file location for user custom icon overrides
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/minimize-icons.json"

# Default icon mappings
DEFAULTS='{
  "com.mitchellh.ghostty": "󰞷",
  "alacritty": "󰞷",
  "kitty": "󰞷",
  "foot": "󰞷",
  "chromium": "󰈹",
  "firefox": "󰈹",
  "Brave-browser": "󰈹",
  "org.gnome.Nautilus": "󰈮",
  "nautilus": "󰈮",
  "spotify": "󰓇",
  "code": "󰨞",
  "Code": "󰨞",
  "discord": "󰙯",
  "vesktop": "󰙯",
  "WebCord": "󰙯",
  "steam": "󰓓",
  "thunar": "󰈮",
  "obsidian": "󱓧",
  "telegram-desktop": "󰈹",
  "default": "󰍄"
}'

render_status() {
  if [ -f "$CONFIG_FILE" ]; then
    CUSTOM_MAP=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{}')
  else
    CUSTOM_MAP='{}'
  fi

  hyprctl clients -j | jq -c --unbuffered \
    --argjson defaults "$DEFAULTS" \
    --argjson custom "$CUSTOM_MAP" '
    ($defaults + $custom) as $map |
    ($map["default"] // "󰍄") as $default_icon |
    def get_icon($class):
      if $map[$class] then $map[$class]
      elif ($class | test("discord"; "i")) then "󰙯"
      elif ($class | test("ghostty|terminal|alacritty|kitty|foot"; "i")) then "󰞷"
      elif ($class | test("chrome|firefox|brave|browser"; "i")) then "󰈹"
      elif ($class | test("nautilus|thunar|dolphin|files"; "i")) then "󰈮"
      elif ($class | test("spotify|music"; "i")) then "󰓇"
      elif ($class | test("code|vsc|editor"; "i")) then "󰨞"
      else $default_icon
      end;
    [.[] | select(.workspace.name == "special:minimized")] as $min |
    if ($min | length) > 0 then
      (
        [
          $min[] |
          get_icon(.class)
        ] | join("  ")
      ) as $icons |
      {
        text: $icons,
        alt: "has-minimized",
        tooltip: ("Minimized (" + (($min | length) | tostring) + "):\n" + ([$min[].title | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")] | map("- " + .) | join("\n"))),
        class: "minimized"
      }
    else
      {
        text: "",
        alt: "none",
        tooltip: "",
        class: "empty"
      }
    end
  ' 2>/dev/null
}

# Output initial state immediately
render_status

# Event-driven listener using Hyprland IPC socket
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

if [ -S "$SOCK" ] && command -v socat >/dev/null 2>&1; then
  socat -u UNIX-CONNECT:"$SOCK" - | while read -r line; do
    case "$line" in
      openwindow*|closewindow*|movewindow*|workspace*|focusedwindow*)
        render_status
        ;;
    esac
  done
else
  # Fallback polling loop if socket is unavailable
  while true; do
    sleep 1
    render_status
  done
fi

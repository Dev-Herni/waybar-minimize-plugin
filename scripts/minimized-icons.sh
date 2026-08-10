#!/usr/bin/env bash
hyprctl clients -j | jq -c '
  [.[] | select(.workspace.name == "special:minimized")] as $min |
  if ($min | length) > 0 then
    (
      [
        $min[] |
        (
          if .class == "com.mitchellh.ghostty" or .class == "alacritty" or .class == "kitty" or .class == "foot" then "󰞷"
          elif .class == "chromium" or .class == "firefox" or .class == "Brave-browser" then "󰈹"
          elif .class == "org.gnome.Nautilus" or .class == "nautilus" then "󰈮"
          elif .class == "spotify" then "󰓇"
          elif .class == "code" then "󰨞"
          else "󰍄"
          end
        )
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
'

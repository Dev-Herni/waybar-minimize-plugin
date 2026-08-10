# Waybar Hyprland Minimize Plugin 📌

A light-weight, event-driven module and script suite for **Waybar** + **Hyprland** that adds dynamic window minimization and unminimization support with instant visual indicators.

## 🚀 Features

- **⚡ Event-Driven Updates**: Uses Hyprland's IPC socket for **0ms latency** status updates with zero CPU polling overhead.
- **🎨 Custom Icon Mapping**: Easily map any application class to custom Nerd Font icons via `~/.config/waybar/minimize-icons.json` (with built-in smart fuzzy fallbacks).
- **Rich Tooltips**: Hover over icons to see a formatted list of all minimized window titles.
- **Click to Restore**: Single click on the Waybar module restores the last minimized window to your current active workspace.
- **Hyprland Integration**: Uses Hyprland's `special:minimized` workspace under the hood to manage minimized state cleanly.

## 📦 Prerequisites

- **Hyprland**
- **Waybar**
- **socat** & **jq** (`sudo pacman -S socat jq`)
- **Nerd Fonts** (e.g. JetBrainsMono Nerd Font)

## 📥 Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/Dev-Herni/waybar-minimize-plugin.git
   cd waybar-minimize-plugin
   ```

2. Run the installer:
   ```bash
   ./install.sh
   ```

## 🎨 Customizing Icons

Edit `~/.config/waybar/minimize-icons.json` to add or override icons for any app:

```json
{
  "com.mitchellh.ghostty": "󰞷",
  "firefox": "󰈹",
  "discord": "󰙯",
  "spotify": "󰓇",
  "code": "󰨞",
  "default": "󰍄"
}
```

## ⚙️ Configuration

### 1. Hyprland Keybindings (`~/.config/hypr/bindings.conf`)

```ini
bindd = SUPER, M, Minimize active window, movetoworkspacesilent, special:minimized
bindd = SUPER ALT, M, Toggle minimized workspace overlay, togglespecialworkspace, minimized
bindd = SUPER SHIFT, M, Restore last minimized window, exec, ~/.config/waybar/scripts/unminimize-click.sh
```

### 2. Waybar Module (`~/.config/waybar/config.jsonc`)

Add `"custom/minimized-icons"` to your modules list (e.g., `"modules-left"`):

```json
"modules-left": ["custom/omarchy", "hyprland/workspaces", "custom/minimized-icons"]
```

Add the custom module definition:

```json
"custom/minimized-icons": {
  "exec": "~/.config/waybar/scripts/minimized-icons.sh",
  "return-type": "json",
  "on-click": "~/.config/waybar/scripts/unminimize-click.sh"
}
```

### 3. Waybar Styling (`~/.config/waybar/style.css`)

```css
#custom-minimized-icons {
  margin-left: 10px;
  color: @foreground;
}

#custom-minimized-icons.minimized {
  padding: 0 8px;
  margin: 0 4px;
  border-radius: 4px;
  background-color: rgba(255, 255, 255, 0.08);
}

#custom-minimized-icons.empty {
  padding: 0;
  margin: 0;
}
```

## 📄 License

[MIT License](LICENSE)

# Waybar Hyprland Minimize Plugin 📌

A light-weight module and script suite for **Waybar** + **Hyprland** that adds dynamic window minimization and unminimization support with visual indicators in your bar.

## 🚀 Features

- **Icon Indicators**: Shows Nerd Font icons for minimized apps directly on your Waybar.
- **Rich Tooltips**: Hover over the icons to see a formatted list of all minimized window titles.
- **Click to Restore**: Single click on the Waybar module restores the last minimized window to your current active workspace.
- **Hyprland Integration**: Uses Hyprland's `special:minimized` workspace under the hood to manage minimized state cleanly without workspace clutter.

## 📦 Prerequisites

- **Hyprland**
- **Waybar**
- **jq** (`sudo pacman -S jq` or distribution equivalent)
- **Nerd Fonts** (e.g. JetBrainsMono Nerd Font) for icons

## 📥 Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/Dev-Herni/waybar-minimize-plugin.git
   cd waybar-minimize-plugin
   ```

2. Run the install script:
   ```bash
   ./install.sh
   ```

3. Configure Waybar and Hyprland (see below).

## ⚙️ Configuration

### 1. Hyprland Keybindings (`~/.config/hypr/bindings.conf`)

Add the following keybindings:

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
  "interval": 1,
  "return-type": "json",
  "on-click": "~/.config/waybar/scripts/unminimize-click.sh"
}
```

### 3. Waybar Styling (`~/.config/waybar/style.css`)

Add CSS styles for the module:

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

## ⌨️ Shortcuts

| Keybinding | Action |
| --- | --- |
| `Super` + `M` | Minimize active window |
| `Super` + `Alt` + `M` | Toggle minimized workspace overlay |
| `Super` + `Shift` + `M` | Restore last minimized window |
| `Left Click` on Waybar module | Restore last minimized window |

## 📄 License

[MIT License](LICENSE)

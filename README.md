# Minimized windows — Omarchy bar widget 📌

A Quickshell bar widget for **Omarchy** that tracks windows minimized to
Hyprland's `special:minimized` workspace, shows their Nerd Font icons in the
bar, and restores the most recently minimized window on click.

Replaces the original Waybar module with a native Omarchy plugin: no scripts,
no polling, no `socat`/`jq` — the widget reads Quickshell's Hyprland models,
so it updates instantly on `openwindow`/`closewindow`/`movewindow`/workspace
events.

## ✨ Features

- **⚡ Event-driven**: renders straight from Quickshell's Hyprland models — no
  polling, no subprocesses.
- **🎨 Smart icons**: per-class Nerd Font glyphs with fuzzy fallbacks
  (ghostty/terminal, chrome/firefox/brave, nautilus/thunar, spotify, code, …).
- **💬 Rich tooltip**: lists every minimized window title.
- **🖱️ Click to restore**: restores the last minimized window to the currently
  focused workspace and focuses it.
- **⌨️ Keybindings**: minimize, toggle the overlay, and restore via keybinds.

## 📦 Prerequisites

- **Omarchy** (Quickshell shell + Hyprland)
- A **Nerd Font** in the bar (the default Omarchy font already is one)

## 📥 Installation

From anywhere (installs into `~/.config/omarchy/plugins/dev-herni.minimized`):

```bash
omarchy plugin add https://github.com/Dev-Herni/waybar-minimize-plugin.git --enable --yes
```

Or add the bar widget from the Omarchy settings UI (`omarchy menu` → Settings →
Bar), picking **Minimized windows** from the widget catalog.

## 🎛️ Keybindings

Add these to `~/.config/hypr/bindings.lua`:

```lua
-- Minimize / restore windows
o.bind("SUPER + M", "Minimize window", "hyprctl dispatch 'hl.dsp.window.move({ workspace = \"special:minimized\", follow = false })'")
o.bind("SUPER + ALT + M", "Toggle minimized overlay", "hyprctl dispatch 'hl.dsp.workspace.toggle_special(\"minimized\")'")
o.bind("SUPER + SHIFT + M", "Restore last minimized window", "omarchy-shell dev-herni.minimized restore")
```

The restore binding sends IPC to the widget (`IpcHandler` target
`dev-herni.minimized`), which broadcasts the restore across all bar monitors.

## 🖥️ How it works

- Minimizing moves the focused window to the special workspace
  `special:minimized` (persistent overlay, visible when toggled).
- The widget watches that workspace's toplevels and shows one icon per window.
- Clicking (or the restore keybind) moves the last one back to the active
  workspace and focuses it, using the new Lua dispatcher syntax:
  `hyprctl dispatch 'hl.dsp.window.move({ window = "address:0x...", workspace = <id>, follow = false })'`.

## 📄 License

[MIT License](LICENSE)

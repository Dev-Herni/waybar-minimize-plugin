#!/usr/bin/env bash
set -e

WAYBAR_SCRIPTS_DIR="$HOME/.config/waybar/scripts"

echo "Installing Waybar Minimize Plugin scripts to $WAYBAR_SCRIPTS_DIR..."

mkdir -p "$WAYBAR_SCRIPTS_DIR"

cp scripts/minimized-icons.sh "$WAYBAR_SCRIPTS_DIR/"
cp scripts/unminimize-click.sh "$WAYBAR_SCRIPTS_DIR/"

chmod +x "$WAYBAR_SCRIPTS_DIR/minimized-icons.sh"
chmod +x "$WAYBAR_SCRIPTS_DIR/unminimize-click.sh"

echo "Scripts installed successfully!"
echo ""
echo "Next steps:"
echo "1. Add 'custom/minimized-icons' to your Waybar modules in ~/.config/waybar/config.jsonc"
echo "2. Add module configuration from config/waybar-config.jsonc to ~/.config/waybar/config.jsonc"
echo "3. Add CSS styles from config/waybar-style.css to ~/.config/waybar/style.css"
echo "4. Add Hyprland keybindings from config/hyprland-bindings.conf to ~/.config/hypr/bindings.conf"

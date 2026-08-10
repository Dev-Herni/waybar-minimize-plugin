#!/usr/bin/env bash
set -e

WAYBAR_DIR="$HOME/.config/waybar"
WAYBAR_SCRIPTS_DIR="$WAYBAR_DIR/scripts"

echo "Installing Waybar Minimize Plugin scripts to $WAYBAR_SCRIPTS_DIR..."

mkdir -p "$WAYBAR_SCRIPTS_DIR"

cp scripts/minimized-icons.sh "$WAYBAR_SCRIPTS_DIR/"
cp scripts/unminimize-click.sh "$WAYBAR_SCRIPTS_DIR/"

chmod +x "$WAYBAR_SCRIPTS_DIR/minimized-icons.sh"
chmod +x "$WAYBAR_SCRIPTS_DIR/unminimize-click.sh"

if [ ! -f "$WAYBAR_DIR/minimize-icons.json" ]; then
    echo "Creating default custom icon mapping at $WAYBAR_DIR/minimize-icons.json..."
    cp config/minimize-icons.json "$WAYBAR_DIR/minimize-icons.json"
fi

echo "Plugin installed successfully!"
echo ""
echo "Next steps:"
echo "1. Ensure 'custom/minimized-icons' is in your Waybar modules array in ~/.config/waybar/config.jsonc"
echo "2. Check ~/.config/waybar/config.jsonc module definition:"
echo "   \"custom/minimized-icons\": {"
echo "     \"exec\": \"~/.config/waybar/scripts/minimized-icons.sh\","
echo "     \"return-type\": \"json\","
echo "     \"on-click\": \"~/.config/waybar/scripts/unminimize-click.sh\""
echo "   }"
echo "3. Customize icon mappings anytime in ~/.config/waybar/minimize-icons.json"

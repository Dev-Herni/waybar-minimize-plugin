import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Omarchy bar widget that shows windows minimized to Hyprland's
// special:minimized workspace and restores the most recent one on click.
//
// The bar hosts one widget slot per monitor; this module relays IPC and
// click actions to every live instance via broadcast, so the single
// instance that claimed the IpcHandler target (whichever screen it is)
// never acts alone while its peers stay stale.
BarWidget {
  id: root
  moduleName: "dev-herni.minimized"

  // ------------------------------------------------------------------ state

  // Collect the toplevels parked on the special:minimized workspace. Read
  // directly from Quickshell's Hyprland models so updates arrive
  // automatically on openwindow/closewindow/movewindow/workspace events.
  readonly property var minimized: root.collectMinimized()
  readonly property int count: minimized.length

  function collectMinimized() {
    var result = []
    var workspaces = Hyprland.workspaces.values
    for (var i = 0; i < workspaces.length; i++) {
      if (workspaces[i].name === "special:minimized") {
        var toplevels = workspaces[i].toplevels.values
        for (var j = 0; j < toplevels.length; j++) result.push(toplevels[j])
      }
    }
    return result
  }

  // ------------------------------------------------------------------ icons

  // class -> Nerd Font glyph, plus a fuzzy fallback chain and default.
  readonly property var iconMap: ({
    "com.mitchellh.ghostty": "\uDB81\uDFB7",
    "alacritty": "\uDB81\uDFB7",
    "kitty": "\uDB81\uDFB7",
    "foot": "\uDB81\uDFB7",
    "chromium": "\uDB80\uDE39",
    "firefox": "\uDB80\uDE39",
    "Brave-browser": "\uDB80\uDE39",
    "org.gnome.Nautilus": "\uDB80\uDE2E",
    "nautilus": "\uDB80\uDE2E",
    "spotify": "\uDB81\uDCC7",
    "code": "\uDB82\uDE1E",
    "Code": "\uDB82\uDE1E",
    "discord": "\uDB81\uDE6F",
    "vesktop": "\uDB81\uDE6F",
    "WebCord": "\uDB81\uDE6F",
    "steam": "\uDB81\uDCD3",
    "thunar": "\uDB80\uDE2E",
    "obsidian": "\uDB85\uDCE7",
    "telegram-desktop": "\uDB80\uDE39",
    "default": "\uDB80\uDF44"
  })

  function classOf(toplevel) {
    var ipc = toplevel.lastIpcObject
    if (ipc && ipc.class) return String(ipc.class)
    if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId)
    return ""
  }

  function iconFor(toplevel) {
    var klass = root.classOf(toplevel).toLowerCase()
    if (root.iconMap[klass]) return root.iconMap[klass]
    if (klass.indexOf("discord") !== -1) return root.iconMap["discord"]
    if (klass.indexOf("ghostty") !== -1 || klass.indexOf("terminal") !== -1 ||
        klass.indexOf("alacritty") !== -1 || klass.indexOf("kitty") !== -1 ||
        klass.indexOf("foot") !== -1) return root.iconMap["foot"]
    if (klass.indexOf("chrome") !== -1 || klass.indexOf("firefox") !== -1 ||
        klass.indexOf("brave") !== -1 || klass.indexOf("browser") !== -1) return root.iconMap["firefox"]
    if (klass.indexOf("nautilus") !== -1 || klass.indexOf("thunar") !== -1 ||
        klass.indexOf("dolphin") !== -1 || klass.indexOf("files") !== -1) return root.iconMap["nautilus"]
    if (klass.indexOf("spotify") !== -1 || klass.indexOf("music") !== -1) return root.iconMap["spotify"]
    if (klass.indexOf("code") !== -1 || klass.indexOf("vsc") !== -1 ||
        klass.indexOf("editor") !== -1) return root.iconMap["code"]
    return root.iconMap["default"]
  }

  readonly property string iconText: root.renderIcons()
  readonly property string tooltip: root.renderTooltip()

  function renderIcons() {
    var parts = []
    for (var i = 0; i < root.minimized.length; i++)
      parts.push(root.iconFor(root.minimized[i]))
    return parts.join("  ")
  }

  function renderTooltip() {
    var lines = ["Minimized (" + root.count + "):"]
    for (var i = 0; i < root.minimized.length; i++)
      lines.push("- " + root.minimized[i].title)
    return lines.join("\n")
  }

  // ------------------------------------------------------------------ actions

  // Move `toplevel` back to the focused workspace and give it focus.
  function restoreToplevel(toplevel) {
    if (!toplevel || !root.bar) return
    var addr = "address:0x" + toplevel.address
    var ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    root.bar.run("hyprctl dispatch " + Util.shellQuote(
      "hl.dsp.window.move({ window = \"" + addr + "\", workspace = " + ws + ", follow = false })"))
    root.bar.run("hyprctl dispatch " + Util.shellQuote(
      "hl.dsp.focus({ window = \"" + addr + "\" })"))
  }

  // Restore the most recently minimized window.
  function restoreLast() {
    if (root.count === 0) return
    root.restoreToplevel(root.minimized[root.minimized.length - 1])
  }

  // ------------------------------------------------------------------ ui

  visible: root.count > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "dev-herni.minimized"

    function restore(): string {
      root.broadcast("restoreLast")
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconText
    tooltipText: root.tooltip
    fixedWidth: root.vertical ? root.barSize : -1
    fixedHeight: root.barSize
    horizontalMargin: 6
    verticalPadding: 6
    onPressed: root.restoreLast()
  }
}
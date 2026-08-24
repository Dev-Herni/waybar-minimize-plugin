import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Omarchy bar widget that shows windows minimized to Hyprland's
// special:minimized workspace and restores the most recent one on click.
//
// Floating state + geometry are snapshotted while a window is still on a
// normal workspace, then re-applied on restore. Hyprland sometimes drops
// floating across a special-workspace round-trip (especially cross-monitor).
BarWidget {
  id: root
  moduleName: "dev-herni.minimized"

  // ------------------------------------------------------------------ state

  // address (hex, no 0x) -> { floating, at, size }
  property var floatMemory: ({})

  readonly property var minimized: {
    // Depend on workspaces/toplevels so the list refreshes on Hyprland events.
    var _ws = Hyprland.workspaces.values
    var _tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    return root.collectMinimized()
  }
  readonly property int count: minimized.length

  function collectMinimized() {
    var result = []
    var workspaces = Hyprland.workspaces.values
    for (var i = 0; i < workspaces.length; i++) {
      if (workspaces[i].name === "special:minimized") {
        var toplevels = workspaces[i].toplevels.values
        for (var j = 0; j < toplevels.length; j++)
          result.push(toplevels[j])
      }
    }
    // Most recently focused first for tooltip; restore uses last = oldest in
    // workspace order is unreliable, so sort by focusHistoryID when present.
    result.sort(function(a, b) {
      var fa = root.focusId(a)
      var fb = root.focusId(b)
      return fa - fb
    })
    return result
  }

  function focusId(toplevel) {
    var ipc = toplevel && toplevel.lastIpcObject
    if (!ipc || ipc.focusHistoryID === undefined || ipc.focusHistoryID === null)
      return 999999
    return Number(ipc.focusHistoryID)
  }

  function addressOf(toplevel) {
    if (!toplevel) return ""
    return String(toplevel.address || "")
  }

  function isSpecialMinimized(toplevel) {
    var ws = toplevel && toplevel.workspace
    if (ws && ws.name) return String(ws.name) === "special:minimized"
    var ipc = toplevel && toplevel.lastIpcObject
    if (ipc && ipc.workspace && ipc.workspace.name)
      return String(ipc.workspace.name) === "special:minimized"
    return false
  }

  // Snapshot floating/geometry for windows that are NOT minimized yet, so a
  // later restore still knows they were floating even if Hyprland clears the
  // flag while they sit on special:minimized.
  function snapshotFloatState() {
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var next = Object.assign({}, root.floatMemory)
    var changed = false
    var live = {}

    for (var i = 0; i < tops.length; i++) {
      var t = tops[i]
      var addr = root.addressOf(t)
      if (!addr) continue
      live[addr] = true

      if (root.isSpecialMinimized(t)) continue

      var ipc = t.lastIpcObject || {}
      var floating = ipc.floating === true || ipc.floating === "true" || ipc.floating === 1
      var at = ipc.at
      var size = ipc.size
      var prev = next[addr]
      if (!prev || prev.floating !== floating ||
          JSON.stringify(prev.at) !== JSON.stringify(at) ||
          JSON.stringify(prev.size) !== JSON.stringify(size)) {
        next[addr] = { floating: floating, at: at, size: size }
        changed = true
      }
    }

    for (var key in next) {
      if (!live[key]) {
        delete next[key]
        changed = true
      }
    }

    if (changed) root.floatMemory = next
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event && event.name ? String(event.name) : ""
      if (name === "openwindow" || name === "closewindow" ||
          name === "movewindow" || name === "movewindowv2" ||
          name === "changefloatingmode" || name === "fullscreen" ||
          name === "workspace" || name === "workspacev2" ||
          name === "activewindow" || name === "activewindowv2") {
        Hyprland.refreshToplevels()
        Qt.callLater(root.snapshotFloatState)
      }
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.snapshotFloatState() }
  }

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    Qt.callLater(root.snapshotFloatState)
  }

  // ------------------------------------------------------------------ icons

  // class -> Nerd Font glyph (keys lowercased; lookup is case-insensitive).
  readonly property var iconMap: ({
    "com.mitchellh.ghostty": "\uDB81\uDFB7",
    "alacritty": "\uDB81\uDFB7",
    "kitty": "\uDB81\uDFB7",
    "foot": "\uDB81\uDFB7",
    "chromium": "\uf268",
    "google-chrome": "\uf268",
    "google-chrome-stable": "\uf268",
    "chrome": "\uf268",
    "firefox": "\uf269",
    "brave-browser": "\uf13b",
    "brave": "\uf13b",
    "org.gnome.nautilus": "\uDB80\uDE2E",
    "nautilus": "\uDB80\uDE2E",
    "spotify": "\uDB81\uDCC7",
    "code": "\uDB82\uDE1E",
    "code-url-handler": "\uDB82\uDE1E",
    "discord": "\uDB81\uDE6F",
    "vesktop": "\uDB81\uDE6F",
    "webcord": "\uDB81\uDE6F",
    "steam": "\uDB81\uDCD3",
    "thunar": "\uDB80\uDE2E",
    "obsidian": "\uDB85\uDCE7",
    "telegram-desktop": "\uDB80\uDE39",
    "default": "\uDB80\uDF44"
  })

  function classOf(toplevel) {
    var ipc = toplevel.lastIpcObject
    if (ipc && ipc.class) return String(ipc.class)
    if (ipc && ipc.initialClass) return String(ipc.initialClass)
    if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId)
    return ""
  }

  function iconFor(toplevel) {
    var klass = root.classOf(toplevel).toLowerCase()
    if (root.iconMap[klass]) return root.iconMap[klass]
    if (klass.indexOf("discord") !== -1 || klass.indexOf("vesktop") !== -1 ||
        klass.indexOf("webcord") !== -1) return root.iconMap["discord"]
    if (klass.indexOf("ghostty") !== -1 || klass.indexOf("terminal") !== -1 ||
        klass.indexOf("alacritty") !== -1 || klass.indexOf("kitty") !== -1 ||
        klass.indexOf("foot") !== -1) return root.iconMap["foot"]
    // Chromium/Chrome before generic "browser" so they never inherit Firefox.
    if (klass.indexOf("chrom") !== -1) return root.iconMap["chromium"]
    if (klass.indexOf("brave") !== -1) return root.iconMap["brave"]
    if (klass.indexOf("firefox") !== -1 || klass.indexOf("browser") !== -1)
      return root.iconMap["firefox"]
    if (klass.indexOf("nautilus") !== -1 || klass.indexOf("thunar") !== -1 ||
        klass.indexOf("dolphin") !== -1 || klass.indexOf("files") !== -1)
      return root.iconMap["nautilus"]
    if (klass.indexOf("spotify") !== -1 || klass.indexOf("music") !== -1)
      return root.iconMap["spotify"]
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

  function dispatch(lua) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote(lua))
  }

  // Move `toplevel` back to the focused workspace, restore floating +
  // geometry when it was floating before minimize, then focus it.
  function restoreToplevel(toplevel) {
    if (!toplevel || !root.bar) return
    var key = root.addressOf(toplevel)
    var addr = "address:0x" + key
    var ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    var mem = root.floatMemory[key] || {}
    var ipc = toplevel.lastIpcObject || {}
    var wasFloating = mem.floating === true ||
      ipc.floating === true || ipc.floating === "true" || ipc.floating === 1
    var at = mem.at || ipc.at
    var size = mem.size || ipc.size

    root.dispatch(
      "hl.dsp.window.move({ window = \"" + addr + "\", workspace = " + ws + ", follow = false })")

    if (wasFloating) {
      root.dispatch(
        "hl.dsp.window.float({ window = \"" + addr + "\", action = \"enable\" })")
      if (size && size.length >= 2) {
        root.dispatch(
          "hl.dsp.window.resize({ window = \"" + addr + "\", x = " +
          Number(size[0]) + ", y = " + Number(size[1]) + " })")
      }
      if (at && at.length >= 2) {
        root.dispatch(
          "hl.dsp.window.move({ window = \"" + addr + "\", x = " +
          Number(at[0]) + ", y = " + Number(at[1]) + " })")
      } else {
        root.dispatch("hl.dsp.window.center({ window = \"" + addr + "\" })")
      }
    }

    root.dispatch("hl.dsp.focus({ window = \"" + addr + "\" })")

    // Hide special:minimized if it was left open as a visible overlay.
    if (root.bar) {
      root.bar.run(
        "bash -c " + Util.shellQuote(
          "open=$(hyprctl monitors -j | jq '[.[] | select(.specialWorkspace.name==\"special:minimized\")] | length'); " +
          "[ \"${open:-0}\" -gt 0 ] && hyprctl dispatch 'hl.dsp.workspace.toggle_special(\"minimized\")' >/dev/null"
        )
      )
    }
  }

  // Most recently focused minimized window (lowest focusHistoryID).
  // Single-shot — not broadcast — so multi-monitor bars do not fire N restores.
  function restoreLast() {
    if (root.count === 0) return
    root.restoreToplevel(root.minimized[0])
  }

  // ------------------------------------------------------------------ ui

  visible: root.count > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "dev-herni.minimized"

    function restore(): string {
      root.restoreLast()
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

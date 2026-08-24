import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "MinimizedModel.js" as Model

// Omarchy bar widget that shows windows minimized to Hyprland's
// special:minimized workspace, one clickable icon per window. Clicking an
// icon restores that exact window; restore-last.sh restores the most
// recently focused one for keybind workflows.
//
// Floating state + geometry are snapshotted while a window is still on a
// normal workspace, then re-applied on restore. Hyprland sometimes drops
// floating across a special-workspace round-trip (especially cross-monitor).
BarWidget {
  id: root
  moduleName: "dev-herni.minimized"

  // ------------------------------------------------------------------ state

  // address (hex, no 0x) -> { floating, at, size, pendingTiled? }
  property var floatMemory: ({})
  property bool snapshotQueued: false

  readonly property string memoryPath: {
    var xdg = Quickshell.env("XDG_STATE_HOME")
    var base = xdg && xdg.length ? xdg : (Quickshell.env("HOME") + "/.local/state")
    return base + "/omarchy/dev-herni.minimized.json"
  }

  readonly property var minimized: {
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
    result.sort(function(a, b) {
      return root.focusId(a) - root.focusId(b)
    })
    return result
  }

  function focusId(toplevel) {
    var ipc = toplevel && toplevel.lastIpcObject
    if (!ipc || ipc.focusHistoryID === undefined || ipc.focusHistoryID === null)
      return 999999
    var n = Number(ipc.focusHistoryID)
    return isFinite(n) ? n : 999999
  }

  function addressOf(toplevel) {
    if (!toplevel) return ""
    return Model.normalizeAddress(toplevel.address || (toplevel.lastIpcObject && toplevel.lastIpcObject.address) || "")
  }

  function isSpecialMinimized(toplevel) {
    var ws = toplevel && toplevel.workspace
    if (ws && ws.name) return String(ws.name) === "special:minimized"
    var ipc = toplevel && toplevel.lastIpcObject
    if (ipc && ipc.workspace && ipc.workspace.name)
      return String(ipc.workspace.name) === "special:minimized"
    return false
  }

  function snapshotWindows() {
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var list = []
    for (var i = 0; i < tops.length; i++) {
      var t = tops[i]
      var addr = root.addressOf(t)
      if (!addr) continue
      var ipc = t.lastIpcObject || {}
      var ws = t.workspace
      var hasWs = (ws && ws.name) || (ipc.workspace && ipc.workspace.name)
      var hasIpc = ipc.floating !== undefined || ipc.at !== undefined
      list.push({
        address: addr,
        special: root.isSpecialMinimized(t),
        unknown: !hasWs || !hasIpc,
        floating: ipc.floating,
        at: ipc.at,
        size: ipc.size
      })
    }
    return list
  }

  function snapshotFloatState() {
    try {
      var next = Model.nextFloatMemory(root.floatMemory, root.snapshotWindows())
      if (JSON.stringify(next) !== JSON.stringify(root.floatMemory))
        root.floatMemory = next
      persistTimer.restart()
      if (Model.hasPendingTiled(next)) confirmTiledTimer.restart()
    } catch (e) {
      console.warn(root.moduleName + " snapshot failed: " + e)
    }
  }

  function persistFloatMemory() {
    try {
      var persistable = {}
      var mem = root.floatMemory || {}
      for (var key in mem) {
        if (!Object.prototype.hasOwnProperty.call(mem, key) || !mem[key]) continue
        persistable[key] = {
          floating: mem[key].floating === true,
          at: mem[key].at || null,
          size: mem[key].size || null
        }
      }
      var slash = root.memoryPath.lastIndexOf("/")
      var dir = slash > 0 ? root.memoryPath.slice(0, slash) : "."
      Quickshell.execDetached(["bash", "-lc",
        "mkdir -p " + Model.shellQuote(dir) +
        " && printf '%s\\n' " + Model.shellQuote(JSON.stringify(persistable)) +
        " > " + Model.shellQuote(root.memoryPath)
      ])
    } catch (e) {
      console.warn(root.moduleName + " persist failed: " + e)
    }
  }

  function queueSnapshot() {
    if (root.snapshotQueued) return
    root.snapshotQueued = true
    Qt.callLater(function() {
      root.snapshotQueued = false
      root.snapshotFloatState()
    })
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
        root.queueSnapshot()
        confirmTiledTimer.restart()
      }
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.queueSnapshot() }
  }

  Timer {
    id: confirmTiledTimer
    interval: 150
    repeat: false
    onTriggered: root.snapshotFloatState()
  }

  Timer {
    id: persistTimer
    interval: 40
    repeat: false
    onTriggered: root.persistFloatMemory()
  }

  Timer {
    id: warmupTimer
    interval: 150
    repeat: true
    property int ticks: 0
    onTriggered: {
      Hyprland.refreshToplevels()
      root.snapshotFloatState()
      warmupTimer.ticks += 1
      if (warmupTimer.ticks >= 12) warmupTimer.stop()
    }
  }

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    root.queueSnapshot()
    persistTimer.restart()
    warmupTimer.start()
  }

  // ------------------------------------------------------------------ icons

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
    if (Object.prototype.hasOwnProperty.call(root.iconMap, klass))
      return root.iconMap[klass]
    if (klass.indexOf("discord") !== -1 || klass.indexOf("vesktop") !== -1 ||
        klass.indexOf("webcord") !== -1) return root.iconMap["discord"]
    if (klass.indexOf("ghostty") !== -1 || klass.indexOf("terminal") !== -1 ||
        klass.indexOf("alacritty") !== -1 || klass.indexOf("kitty") !== -1 ||
        klass.indexOf("foot") !== -1) return root.iconMap["foot"]
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

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // ------------------------------------------------------------------ actions

  function restoreToplevel(toplevel) {
    if (!toplevel || !root.bar) return
    var key = root.addressOf(toplevel)
    if (!key) {
      console.warn(root.moduleName + ": refusing restore of window with invalid address")
      return
    }
    var ipc = toplevel.lastIpcObject || {}
    var state = Model.resolveRestoreState({
      address: key,
      floating: ipc.floating,
      at: ipc.at,
      size: ipc.size
    }, root.floatMemory)
    var cmd = Model.buildRestoreCommand({
      address: key,
      workspace: Model.restoreWorkspaceId(Hyprland.focusedWorkspace, Hyprland.focusedMonitor),
      floating: state.floating,
      at: state.at,
      size: state.size
    })
    if (cmd) root.bar.run(cmd)
  }

  function restoreLast() {
    if (root.count === 0) return
    root.restoreToplevel(root.minimized[0])
  }

  // ------------------------------------------------------------------ ui

  visible: root.count > 0
  implicitWidth: grid.implicitWidth + root.trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.minimized.length
    columnSpacing: root.vertical ? 0 : Style.space(0.5)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.minimized

      WidgetButton {
        required property var modelData

        bar: root.bar
        text: root.iconFor(modelData)
        tooltipText: Model.sanitizeTitle(modelData.title) || "Minimized window"
        horizontalMargin: 4
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : -1
        fixedHeight: root.barSize
        onPressed: function() { root.restoreToplevel(modelData) }
      }
    }
  }
}

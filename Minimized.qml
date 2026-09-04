import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
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
// Snapshots persist to disk so a shell restart does not forget them, and
// FileView keeps every bar instance (one per monitor) on the same file.
BarWidget {
  id: root
  moduleName: "dev-herni.minimized"

  // ------------------------------------------------------------------ state

  // address (hex, no 0x) -> { floating, at, size, pendingTiled? }
  property var floatMemory: ({})
  property bool snapshotQueued: false
  property bool memoryHydrated: false
  property bool applyingDisk: false
  property string lastPersisted: ""

  readonly property string memoryPath: {
    var xdg = Quickshell.env("XDG_STATE_HOME")
    var base = xdg && xdg.length ? xdg : (Quickshell.env("HOME") + "/.local/state")
    return base + "/omarchy/dev-herni.minimized.json"
  }

  readonly property string memoryDir: {
    var slash = root.memoryPath.lastIndexOf("/")
    return slash > 0 ? root.memoryPath.slice(0, slash) : "."
  }

  // Plain property, refreshed explicitly (see refreshMinimized). It must not
  // be a readonly binding: collectMinimized() walks Hyprland.toplevels through
  // indexed access, which QML's binding engine does not track, so a readonly
  // binding would freeze at its initial value and never show icons when
  // windows move onto special:minimized after the widget loads.
  property var minimized: []
  readonly property int count: minimized.length

  function refreshMinimized() {
    var next = root.collectMinimized()
    if (Model.minimizedSignature(next) === Model.minimizedSignature(root.minimized))
      return
    root.minimized = next
  }

  function collectMinimized() {
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var list = []
    for (var i = 0; i < tops.length; i++) {
      var t = tops[i]
      var ipc = t.lastIpcObject || {}
      var ws = t.workspace
      list.push({
        address: root.addressOf(t),
        title: t.title || ipc.title || "",
        className: root.classOf(t),
        workspace: { name: (ws && ws.name) || (ipc.workspace && ipc.workspace.name) || "" },
        floating: ipc.floating,
        at: ipc.at,
        size: ipc.size,
        focusHistoryID: root.focusId(t)
      })
    }
    return Model.collectMinimizedEntries(list)
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
    if (ws && ws.name) return Model.isMinimizedWorkspaceName(ws.name)
    var ipc = toplevel && toplevel.lastIpcObject
    if (ipc && ipc.workspace && ipc.workspace.name)
      return Model.isMinimizedWorkspaceName(ipc.workspace.name)
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
      if (JSON.stringify(next) !== JSON.stringify(root.floatMemory)) {
        root.floatMemory = next
        if (root.memoryHydrated && !root.applyingDisk) persistTimer.restart()
      }
      if (Model.hasPendingTiled(next)) confirmTiledTimer.restart()
    } catch (e) {
      console.warn(root.moduleName + " snapshot failed: " + e)
    }
  }

  function persistFloatMemory() {
    if (!root.memoryHydrated || root.applyingDisk) return
    try {
      var persistable = Model.persistableMemory(root.floatMemory)
      var encoded = JSON.stringify(persistable)
      if (encoded === root.lastPersisted) return
      root.lastPersisted = encoded
      memoryFile.setText(encoded + "\n")
    } catch (e) {
      console.warn(root.moduleName + " persist failed: " + e)
    }
  }

  function ingestMemoryText(text) {
    var parsed = Model.parseFloatMemory(text)
    var encoded = JSON.stringify(Model.persistableMemory(parsed))
    var first = !root.memoryHydrated
    root.memoryHydrated = true
    if (encoded === root.lastPersisted) {
      if (first) root.queueSnapshot()
      return
    }
    root.applyingDisk = true
    root.floatMemory = parsed
    root.lastPersisted = encoded
    root.applyingDisk = false
    root.queueSnapshot()
  }

  function queueSnapshot() {
    if (root.snapshotQueued) return
    root.snapshotQueued = true
    Qt.callLater(function() {
      root.snapshotQueued = false
      root.snapshotFloatState()
    })
  }

  function monitorList() {
    var mons = Hyprland.monitors ? Hyprland.monitors.values : []
    var list = []
    for (var i = 0; i < mons.length; i++) {
      var m = mons[i]
      var ipc = (m && m.lastIpcObject) || {}
      list.push({
        x: m.x !== undefined ? m.x : ipc.x,
        y: m.y !== undefined ? m.y : ipc.y,
        width: m.width || ipc.width,
        height: m.height || ipc.height
      })
    }
    return list
  }

  FileView {
    id: memoryFile
    path: root.memoryPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.ingestMemoryText(text())
    onLoadFailed: {
      root.memoryHydrated = true
      root.queueSnapshot()
    }
    onFileChanged: reload()
  }

  Process {
    id: ensureMemoryDir
    command: ["mkdir", "-p", root.memoryDir]
    running: true
    onExited: memoryFile.reload()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event && event.name ? String(event.name) : ""
      if (Model.eventSnapshotsFloat(name)) {
        Hyprland.refreshToplevels()
        root.queueSnapshot()
      }
      if (Model.eventRefreshesIcons(name))
        root.refreshMinimized()
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      root.queueSnapshot()
      root.refreshMinimized()
    }
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() {
      root.queueSnapshot()
      root.refreshMinimized()
    }
  }

  Timer {
    id: confirmTiledTimer
    interval: 400
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
      root.refreshMinimized()
      warmupTimer.ticks += 1
      if (warmupTimer.ticks >= 12) warmupTimer.stop()
    }
  }

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    root.queueSnapshot()
    root.refreshMinimized()
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
    "zen": "\uf269",
    "zen-browser": "\uf269",
    "brave-browser": "\uDB82\uDCE5",
    "brave": "\uDB82\uDCE5",
    "org.gnome.nautilus": "\uDB80\uDE2E",
    "nautilus": "\uDB80\uDE2E",
    "nemo": "\uDB80\uDE2E",
    "spotify": "\uDB81\uDCC7",
    "code": "\uDB82\uDE1E",
    "code-oss": "\uDB82\uDE1E",
    "code-url-handler": "\uDB82\uDE1E",
    "codium": "\uDB82\uDE1E",
    "vscodium": "\uDB82\uDE1E",
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
    if (!toplevel) return ""
    var ipc = toplevel.lastIpcObject || {}
    if (ipc.class) return String(ipc.class)
    if (ipc.initialClass) return String(ipc.initialClass)
    if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId)
    return ""
  }

  function iconFor(entry) {
    var klass = String((entry && (entry.className || entry.class)) || "").toLowerCase()
    if (!klass) klass = root.classOf(entry).toLowerCase()
    return Model.iconForClass(klass, root.iconMap)
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  // ------------------------------------------------------------------ actions

  function restoreToplevel(entry) {
    if (!entry || !root.bar) return
    var key = Model.normalizeAddress(entry.address || root.addressOf(entry))
    if (!key) {
      console.warn(root.moduleName + ": refusing restore of window with invalid address")
      return
    }
    var state = Model.resolveRestoreState({
      address: key,
      floating: entry.floating,
      at: entry.at,
      size: entry.size
    }, root.floatMemory, root.monitorList())
    var cmd = Model.buildRestoreCommand({
      address: key,
      workspace: Model.restoreWorkspaceId(Hyprland.focusedWorkspace, Hyprland.focusedMonitor),
      floating: state.floating,
      at: state.at,
      size: state.size
    })
    if (cmd) {
      root.persistFloatMemory()
      root.bar.run(cmd)
    }
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
    columns: root.vertical ? 1 : Math.max(1, root.minimized.length)
    columnSpacing: root.vertical ? 0 : Style.space(0.5)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.minimized

      WidgetButton {
        required property var modelData

        bar: root.bar
        text: root.iconFor(modelData)
        tooltipText: Model.sanitizeTitle(modelData.title) || "Minimized window"
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : -1
        fixedHeight: root.barSize
        onPressed: function(button) {
          if (button === Qt.LeftButton) root.restoreToplevel(modelData)
        }
      }
    }
  }
}

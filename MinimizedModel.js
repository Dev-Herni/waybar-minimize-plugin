// Pure helpers shared by Minimized.qml and node tests.
// Keep this file ES5-compatible: QML's JS engine has no require/import.

function normalizeAddress(value) {
  var s = String(value === undefined || value === null ? "" : value).trim()
  if (s.indexOf("0x") === 0 || s.indexOf("0X") === 0) s = s.slice(2)
  s = s.toLowerCase()
  return /^[0-9a-f]{1,16}$/.test(s) ? s : ""
}

function boundedInt(v, min, max, fallback) {
  var n = Number(v)
  if (!isFinite(n) || n < min || n > max) return fallback
  return Math.floor(n)
}

function boundedPoint(v) {
  if (v === undefined || v === null) return null
  var x, y
  if (typeof v === "object" && v.x !== undefined && v.y !== undefined) {
    x = Number(v.x)
    y = Number(v.y)
  } else if (v && (v[0] !== undefined && v[1] !== undefined) &&
             (Array.isArray(v) || typeof v.length === "number" || typeof v === "object")) {
    x = Number(v[0])
    y = Number(v[1])
  } else {
    return null
  }
  if (!isFinite(x) || !isFinite(y)) return null
  if (Math.abs(x) > 100000 || Math.abs(y) > 100000) return null
  return [Math.round(x), Math.round(y)]
}

function restoreWorkspaceId(focusedWorkspace, focusedMonitor) {
  var id = focusedWorkspace && focusedWorkspace.id
  id = boundedInt(id, 1, 99999, 0)
  if (id > 0) return id
  var monWs = focusedMonitor && focusedMonitor.activeWorkspace
  id = boundedInt(monWs && monWs.id, 1, 99999, 0)
  if (id > 0) return id
  return 1
}

function isMinimizedWorkspaceName(name) {
  var s = String(name === undefined || name === null ? "" : name)
  return s === "special:minimized" || s === "minimized"
}

function collectMinimizedEntries(toplevels) {
  var result = []
  toplevels = toplevels || []
  for (var i = 0; i < toplevels.length; i++) {
    var t = toplevels[i] || {}
    var wsName = ""
    if (t.workspace && t.workspace.name) wsName = t.workspace.name
    else if (t.workspaceName) wsName = t.workspaceName
    if (!isMinimizedWorkspaceName(wsName)) continue
    var addr = normalizeAddress(t.address)
    if (!addr) continue
    result.push({
      address: addr,
      title: t.title || "",
      className: t.className || t.class || "",
      floating: isTruthyFloating(t.floating),
      at: boundedPoint(t.at),
      size: boundedPoint(t.size),
      focusHistoryID: boundedInt(t.focusHistoryID, 0, 999999, 999999)
    })
  }
  result.sort(function(a, b) {
    return a.focusHistoryID - b.focusHistoryID
  })
  return result
}

function monitorRect(m) {
  if (!m) return null
  var x = boundedInt(m.x, -100000, 100000, null)
  var y = boundedInt(m.y, -100000, 100000, null)
  var w = boundedInt(m.width, 1, 100000, 0)
  var h = boundedInt(m.height, 1, 100000, 0)
  if (x === null || y === null || !w || !h) return null
  return { x: x, y: y, width: w, height: h }
}

function rectsOverlap(ax, ay, aw, ah, b) {
  return ax < b.x + b.width && ax + aw > b.x &&
    ay < b.y + b.height && ay + ah > b.y
}

function clampPointToMonitors(at, size, monitors) {
  at = boundedPoint(at)
  if (!at) return null
  size = boundedPoint(size) || [800, 600]
  var w = Math.max(1, size[0])
  var h = Math.max(1, size[1])
  var list = []
  monitors = monitors || []
  for (var i = 0; i < monitors.length; i++) {
    var r = monitorRect(monitors[i])
    if (r) list.push(r)
  }
  if (!list.length) return at
  for (var j = 0; j < list.length; j++) {
    if (rectsOverlap(at[0], at[1], w, h, list[j])) return at
  }
  var cx = at[0] + w / 2
  var cy = at[1] + h / 2
  var best = list[0]
  var bestDist = Infinity
  for (var k = 0; k < list.length; k++) {
    var m = list[k]
    var dx = cx - (m.x + m.width / 2)
    var dy = cy - (m.y + m.height / 2)
    var dist = dx * dx + dy * dy
    if (dist < bestDist) {
      bestDist = dist
      best = m
    }
  }
  return [
    Math.round(best.x + (best.width - w) / 2),
    Math.round(best.y + (best.height - h) / 2)
  ]
}

function isTruthyFloating(v) {
  return v === true || v === "true" || v === 1
}

function copySnapshot(entry) {
  if (!entry) return null
  var out = {
    floating: entry.floating === true,
    at: boundedPoint(entry.at),
    size: boundedPoint(entry.size)
  }
  if (entry.pendingTiled) out.pendingTiled = true
  return out
}

function nextFloatMemory(prev, windows) {
  prev = prev || {}
  windows = windows || []
  var next = {}
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    var addr = normalizeAddress(w && w.address)
    if (!addr) continue
    var prevEntry = prev[addr]
    if (w.unknown) {
      if (prevEntry) next[addr] = copySnapshot(prevEntry)
      continue
    }
    if (w.special) {
      if (prevEntry) next[addr] = copySnapshot({
        floating: prevEntry.floating,
        at: prevEntry.at,
        size: prevEntry.size
      })
      continue
    }

    var floating = isTruthyFloating(w.floating)
    var at = boundedPoint(w.at)
    var size = boundedPoint(w.size)

    if (floating) {
      next[addr] = { floating: true, at: at, size: size }
      continue
    }

    if (prevEntry && prevEntry.floating && prevEntry.pendingTiled) {
      next[addr] = { floating: false, at: at, size: size }
      continue
    }

    if (prevEntry && prevEntry.floating) {
      next[addr] = {
        floating: true,
        at: prevEntry.at,
        size: prevEntry.size,
        pendingTiled: true
      }
      continue
    }

    next[addr] = { floating: false, at: at, size: size }
  }
  return next
}

function hasPendingTiled(mem) {
  if (!mem) return false
  for (var key in mem) {
    if (Object.prototype.hasOwnProperty.call(mem, key) && mem[key] && mem[key].pendingTiled)
      return true
  }
  return false
}

function parseFloatMemory(text) {
  var parsed
  try {
    parsed = JSON.parse(String(text === undefined || text === null ? "" : text))
  } catch (e) {
    return {}
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {}
  var out = {}
  for (var key in parsed) {
    if (!Object.prototype.hasOwnProperty.call(parsed, key)) continue
    var addr = normalizeAddress(key)
    if (!addr || !parsed[key] || typeof parsed[key] !== "object") continue
    out[addr] = {
      floating: parsed[key].floating === true,
      at: boundedPoint(parsed[key].at),
      size: boundedPoint(parsed[key].size)
    }
  }
  return out
}

function persistableMemory(mem) {
  var out = {}
  mem = mem || {}
  for (var key in mem) {
    if (!Object.prototype.hasOwnProperty.call(mem, key) || !mem[key]) continue
    var addr = normalizeAddress(key)
    if (!addr) continue
    out[addr] = {
      floating: mem[key].floating === true,
      at: boundedPoint(mem[key].at),
      size: boundedPoint(mem[key].size)
    }
  }
  return out
}

function pickIcon(iconMap, key) {
  if (iconMap && Object.prototype.hasOwnProperty.call(iconMap, key) && iconMap[key])
    return iconMap[key]
  return (iconMap && iconMap["default"]) || ""
}

function iconForClass(klass, iconMap) {
  klass = String(klass === undefined || klass === null ? "" : klass).toLowerCase()
  if (klass && Object.prototype.hasOwnProperty.call(iconMap || {}, klass) && iconMap[klass])
    return iconMap[klass]
  if (klass.indexOf("discord") !== -1 || klass.indexOf("vesktop") !== -1 ||
      klass.indexOf("webcord") !== -1) return pickIcon(iconMap, "discord")
  if (klass.indexOf("ghostty") !== -1 || klass.indexOf("alacritty") !== -1 ||
      klass.indexOf("kitty") !== -1 || klass.indexOf("foot") !== -1 ||
      klass.indexOf("terminal") !== -1) return pickIcon(iconMap, "foot")
  if (klass.indexOf("brave") !== -1) return pickIcon(iconMap, "brave")
  if (klass.indexOf("chrom") !== -1 || klass.indexOf("msedge") !== -1 ||
      klass.indexOf("microsoft-edge") !== -1) return pickIcon(iconMap, "chromium")
  if (klass.indexOf("firefox") !== -1 || klass.indexOf("zen") !== -1)
    return pickIcon(iconMap, "firefox")
  if (klass.indexOf("nautilus") !== -1 || klass.indexOf("thunar") !== -1 ||
      klass.indexOf("dolphin") !== -1 || klass.indexOf("nemo") !== -1 ||
      klass.indexOf("pcmanfm") !== -1 || klass === "files")
    return pickIcon(iconMap, "nautilus")
  if (klass.indexOf("spotify") !== -1) return pickIcon(iconMap, "spotify")
  if (klass === "code" || klass.indexOf("code-") === 0 ||
      klass.indexOf("vsc") !== -1 || klass.indexOf("codium") !== -1)
    return pickIcon(iconMap, "code")
  return pickIcon(iconMap, "default")
}

function minimizedSignature(list) {
  list = list || []
  var parts = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i] || {}
    parts.push([
      e.address || "",
      e.title || "",
      e.className || e.class || "",
      String(e.focusHistoryID === undefined || e.focusHistoryID === null ? "" : e.focusHistoryID)
    ].join("\0"))
  }
  return parts.join("\n")
}

function eventRefreshesIcons(name) {
  return name === "openwindow" || name === "closewindow" ||
    name === "movewindow" || name === "movewindowv2" ||
    name === "workspace" || name === "workspacev2"
}

function eventSnapshotsFloat(name) {
  return eventRefreshesIcons(name) ||
    name === "changefloatingmode" || name === "fullscreen" ||
    name === "activewindow" || name === "activewindowv2"
}

function shellQuote(value) {
  return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
}

function hyprDispatch(lua) {
  return "hyprctl dispatch " + shellQuote(lua)
}

function hideMinimizedOverlayCommand() {
  return "open=$(hyprctl -j monitors | jq '[.[] | select(.specialWorkspace.name==\"special:minimized\")] | length'); " +
    "if [ \"${open:-0}\" -gt 0 ]; then hyprctl dispatch 'hl.dsp.workspace.toggle_special(\"minimized\")' >/dev/null; fi"
}

function buildRestoreCommand(opts) {
  opts = opts || {}
  var addr = normalizeAddress(opts.address)
  if (!addr) return ""
  var window = "address:0x" + addr
  var ws = restoreWorkspaceId({ id: opts.workspace })
  var cmds = []
  cmds.push(hyprDispatch(
    "hl.dsp.window.move({ window = \"" + window + "\", workspace = " + ws + ", follow = false })"))
  if (opts.floating) {
    cmds.push(hyprDispatch(
      "hl.dsp.window.float({ window = \"" + window + "\", action = \"enable\" })"))
    var size = boundedPoint(opts.size)
    var at = boundedPoint(opts.at)
    if (size) {
      cmds.push(hyprDispatch(
        "hl.dsp.window.resize({ window = \"" + window + "\", x = " +
        size[0] + ", y = " + size[1] + ", relative = false })"))
    }
    if (at) {
      cmds.push(hyprDispatch(
        "hl.dsp.window.move({ window = \"" + window + "\", x = " +
        at[0] + ", y = " + at[1] + ", relative = false })"))
    } else {
      cmds.push(hyprDispatch("hl.dsp.window.center({ window = \"" + window + "\" })"))
    }
  }
  cmds.push(hyprDispatch("hl.dsp.focus({ window = \"" + window + "\" })"))
  cmds.push(hideMinimizedOverlayCommand())
  return cmds.join(" && ")
}

function sanitizeTitle(t) {
  var s = String(t === undefined || t === null ? "" : t)
  s = s.replace(/\s+/g, " ").trim()
  if (s.length > 80) s = s.slice(0, 79) + "\u2026"
  return s
}

function resolveRestoreState(client, memory, monitors) {
  client = client || {}
  var addr = normalizeAddress(client.address)
  var mem = (memory && addr && memory[addr]) || {}
  var floating = mem.floating === true || isTruthyFloating(client.floating)
  var size = boundedPoint(mem.size)
  if (!size) size = boundedPoint(client.size)
  var at = boundedPoint(mem.at)
  if (!at) at = boundedPoint(client.at)
  if (floating && at) at = clampPointToMonitors(at, size, monitors) || at
  return {
    address: addr,
    floating: floating,
    at: at,
    size: size
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeAddress: normalizeAddress,
    boundedInt: boundedInt,
    boundedPoint: boundedPoint,
    restoreWorkspaceId: restoreWorkspaceId,
    isMinimizedWorkspaceName: isMinimizedWorkspaceName,
    collectMinimizedEntries: collectMinimizedEntries,
    clampPointToMonitors: clampPointToMonitors,
    nextFloatMemory: nextFloatMemory,
    hasPendingTiled: hasPendingTiled,
    parseFloatMemory: parseFloatMemory,
    persistableMemory: persistableMemory,
    iconForClass: iconForClass,
    minimizedSignature: minimizedSignature,
    eventRefreshesIcons: eventRefreshesIcons,
    eventSnapshotsFloat: eventSnapshotsFloat,
    buildRestoreCommand: buildRestoreCommand,
    sanitizeTitle: sanitizeTitle,
    resolveRestoreState: resolveRestoreState,
    shellQuote: shellQuote
  }
}

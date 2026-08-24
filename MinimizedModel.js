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
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function resolveRestoreState(client, memory) {
  client = client || {}
  var addr = normalizeAddress(client.address)
  var mem = (memory && addr && memory[addr]) || {}
  var floating = mem.floating === true || isTruthyFloating(client.floating)
  return {
    address: addr,
    floating: floating,
    at: boundedPoint(mem.at || client.at),
    size: boundedPoint(mem.size || client.size)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeAddress: normalizeAddress,
    boundedInt: boundedInt,
    boundedPoint: boundedPoint,
    restoreWorkspaceId: restoreWorkspaceId,
    nextFloatMemory: nextFloatMemory,
    hasPendingTiled: hasPendingTiled,
    buildRestoreCommand: buildRestoreCommand,
    sanitizeTitle: sanitizeTitle,
    resolveRestoreState: resolveRestoreState,
    shellQuote: shellQuote
  }
}

const test = require("node:test");
const assert = require("node:assert/strict");

const Model = require("../MinimizedModel.js");

test("normalizeAddress strips 0x and rejects non-hex", () => {
  assert.equal(Model.normalizeAddress("55896300dc70"), "55896300dc70");
  assert.equal(Model.normalizeAddress("0x55896300dc70"), "55896300dc70");
  assert.equal(Model.normalizeAddress("0XDEADBEEF"), "deadbeef");
  assert.equal(Model.normalizeAddress("address:0xabc"), "");
  assert.equal(Model.normalizeAddress("not-hex"), "");
  assert.equal(Model.normalizeAddress(""), "");
  assert.equal(Model.normalizeAddress(null), "");
});

test("boundedPoint accepts arrays, array-likes, and {x,y}", () => {
  assert.deepEqual(Model.boundedPoint([3170, 303]), [3170, 303]);
  assert.deepEqual(Model.boundedPoint({ 0: 10.4, 1: 20.6, length: 2 }), [10, 21]);
  assert.deepEqual(Model.boundedPoint({ 0: 3170, 1: 303 }), [3170, 303]);
  assert.deepEqual(Model.boundedPoint({ x: 100, y: 200 }), [100, 200]);
  assert.equal(Model.boundedPoint(null), null);
  assert.equal(Model.boundedPoint([NaN, 1]), null);
  assert.equal(Model.boundedPoint([1e9, 0]), null);
});

test("restoreWorkspaceId ignores special (negative) workspace ids", () => {
  assert.equal(Model.restoreWorkspaceId({ id: 1 }), 1);
  assert.equal(Model.restoreWorkspaceId({ id: -98 }, { activeWorkspace: { id: 2 } }), 2);
  assert.equal(Model.restoreWorkspaceId({ id: -98 }, { activeWorkspace: { id: -98 } }), 1);
  assert.equal(Model.restoreWorkspaceId(null, null), 1);
});

test("nextFloatMemory does not drop a floating snapshot when a window unfloats as it is minimized", () => {
  const prev = {
    abc: { floating: true, at: [10, 20], size: [300, 200] }
  };

  // Race: Hyprland unfloats while the window is still on a normal workspace.
  const afterUnfloat = Model.nextFloatMemory(prev, [
    { address: "abc", special: false, floating: false, at: [0, 0], size: [1920, 1080] }
  ]);
  assert.equal(afterUnfloat.abc.floating, true);
  assert.deepEqual(afterUnfloat.abc.at, [10, 20]);
  assert.equal(afterUnfloat.abc.pendingTiled, true);

  // Then the window lands on special:minimized — keep the floating snapshot.
  const afterSpecial = Model.nextFloatMemory(afterUnfloat, [
    { address: "abc", special: true, floating: false, at: [0, 0], size: [1920, 1080] }
  ]);
  assert.equal(afterSpecial.abc.floating, true);
  assert.deepEqual(afterSpecial.abc.at, [10, 20]);
  assert.equal(afterSpecial.abc.pendingTiled, undefined);
});

test("nextFloatMemory keeps previous snapshot when Hyprland data is not ready yet", () => {
  const prev = {
    abc: { floating: true, at: [10, 20], size: [300, 200] }
  };
  const next = Model.nextFloatMemory(prev, [
    { address: "abc", special: false, unknown: true }
  ]);
  assert.equal(next.abc.floating, true);
  assert.deepEqual(next.abc.at, [10, 20]);
  assert.equal(next.abc.pendingTiled, undefined);
});

test("nextFloatMemory does not invent a tiled snapshot from empty IPC data", () => {
  const next = Model.nextFloatMemory({}, [
    { address: "abc", special: false, unknown: true }
  ]);
  assert.equal(next.abc, undefined);
});

test("nextFloatMemory commits tiled after a pending unfloat stays on a normal workspace", () => {
  const pending = Model.nextFloatMemory(
    { abc: { floating: true, at: [10, 20], size: [300, 200] } },
    [{ address: "abc", special: false, floating: false, at: [0, 0], size: [800, 600] }]
  );
  const confirmed = Model.nextFloatMemory(pending, [
    { address: "abc", special: false, floating: false, at: [0, 0], size: [800, 600] }
  ]);
  assert.equal(confirmed.abc.floating, false);
  assert.equal(confirmed.abc.pendingTiled, undefined);
});

test("buildRestoreCommand is a single sequential shell string", () => {
  const cmd = Model.buildRestoreCommand({
    address: "55896300dc70",
    workspace: 1,
    floating: true,
    at: [3170, 303],
    size: [700, 500]
  });
  assert.equal(typeof cmd, "string");
  assert.match(cmd, /hyprctl dispatch/);
  assert.match(cmd, /&&/);
  assert.doesNotMatch(cmd, /\n/);
  const floatAt = cmd.indexOf("window.float");
  const resizeAt = cmd.indexOf("window.resize");
  const moveWsAt = cmd.indexOf("workspace = 1");
  const movePosAt = cmd.lastIndexOf("x = 3170");
  assert.ok(moveWsAt >= 0 && floatAt > moveWsAt);
  assert.ok(resizeAt > floatAt);
  assert.ok(movePosAt > resizeAt);
  assert.match(cmd, /toggle_special\("minimized"\)/);
});

test("buildRestoreCommand skips float/geometry for tiled windows", () => {
  const cmd = Model.buildRestoreCommand({
    address: "abc",
    workspace: 2,
    floating: false
  });
  assert.doesNotMatch(cmd, /window\.float/);
  assert.doesNotMatch(cmd, /window\.resize/);
  assert.match(cmd, /workspace = 2/);
  assert.match(cmd, /hl\.dsp\.focus/);
});

test("sanitizeTitle does not HTML-escape (bar tooltips are plain text)", () => {
  assert.equal(Model.sanitizeTitle("Foo & Bar <baz>"), "Foo & Bar <baz>");
  assert.equal(Model.sanitizeTitle("  lots   of\tspace  "), "lots of space");
});

test("parseFloatMemory keeps valid snapshots and drops bad keys", () => {
  const mem = Model.parseFloatMemory(JSON.stringify({
    abc: { floating: true, at: [10, 20], size: [300, 200], pendingTiled: true },
    "not hex": { floating: true, at: [1, 2], size: [3, 4] },
    "": { floating: false }
  }));
  assert.equal(mem.abc.floating, true);
  assert.deepEqual(mem.abc.at, [10, 20]);
  assert.equal(mem.abc.pendingTiled, undefined);
  assert.equal(mem["not hex"], undefined);
});

test("parseFloatMemory returns empty object for junk", () => {
  assert.deepEqual(Model.parseFloatMemory("not-json"), {});
  assert.deepEqual(Model.parseFloatMemory(""), {});
  assert.deepEqual(Model.parseFloatMemory("[]"), {});
});

test("persistableMemory strips pendingTiled", () => {
  const out = Model.persistableMemory({
    abc: { floating: true, at: [1, 2], size: [3, 4], pendingTiled: true }
  });
  assert.deepEqual(out.abc, { floating: true, at: [1, 2], size: [3, 4] });
});

test("nextFloatMemory keeps a disk snapshot for windows already on special:minimized", () => {
  const loaded = Model.parseFloatMemory(JSON.stringify({
    abc: { floating: true, at: [40, 50], size: [640, 480] }
  }));
  const next = Model.nextFloatMemory(loaded, [
    { address: "abc", special: true, floating: false, at: [0, 0], size: [1920, 1080] }
  ]);
  assert.equal(next.abc.floating, true);
  assert.deepEqual(next.abc.at, [40, 50]);
});

test("iconForClass does not use generic browser/music/editor fallbacks", () => {
  const map = {
    firefox: "F",
    spotify: "S",
    code: "C",
    brave: "B",
    chromium: "G",
    default: "D"
  };
  assert.equal(Model.iconForClass("some-random-browser", map), "D");
  assert.equal(Model.iconForClass("gnome-music", map), "D");
  assert.equal(Model.iconForClass("gnome-text-editor", map), "D");
  assert.equal(Model.iconForClass("brave-browser", map), "B");
  assert.equal(Model.iconForClass("zen-browser", map), "F");
  assert.equal(Model.iconForClass("code-oss", map), "C");
});

test("minimizedSignature ignores object identity so Repeaters can stay put", () => {
  const a = [{ address: "abc", title: "x", className: "foot", focusHistoryID: 1 }];
  const b = [{ address: "abc", title: "x", className: "foot", focusHistoryID: 1 }];
  assert.equal(Model.minimizedSignature(a), Model.minimizedSignature(b));
  assert.notEqual(
    Model.minimizedSignature(a),
    Model.minimizedSignature([{ address: "abc", title: "y", className: "foot", focusHistoryID: 1 }])
  );
});

test("resolveRestoreState keeps live geometry when memory at/size are null", () => {
  const state = Model.resolveRestoreState(
    { address: "abc", floating: false, at: [120, 80], size: [800, 600] },
    { abc: { floating: true, at: null, size: null } }
  );
  assert.equal(state.floating, true);
  assert.deepEqual(state.at, [120, 80]);
  assert.deepEqual(state.size, [800, 600]);
});

test("event classification does not rebuild icons on every focus change", () => {
  assert.equal(Model.eventRefreshesIcons("activewindow"), false);
  assert.equal(Model.eventRefreshesIcons("activewindowv2"), false);
  assert.equal(Model.eventRefreshesIcons("changefloatingmode"), false);
  assert.equal(Model.eventRefreshesIcons("movewindowv2"), true);
  assert.equal(Model.eventRefreshesIcons("closewindow"), true);
  assert.equal(Model.eventSnapshotsFloat("activewindow"), true);
  assert.equal(Model.eventSnapshotsFloat("changefloatingmode"), true);
  assert.equal(Model.eventSnapshotsFloat("configreloaded"), false);
});

test("collectMinimizedEntries snapshots address/title from toplevels, not live objects", () => {
  const entries = Model.collectMinimizedEntries([
    {
      address: "0xABC",
      title: "Discord",
      className: "discord",
      workspace: { name: "1" },
      focusHistoryID: 0
    },
    {
      address: "0x55896300dc70",
      title: "foot",
      className: "foot",
      workspace: { name: "special:minimized" },
      floating: true,
      at: [40, 50],
      size: [640, 480],
      focusHistoryID: 2
    },
    {
      address: "0xdead",
      title: "older",
      class: "Alacritty",
      workspaceName: "minimized",
      focusHistoryID: 1
    }
  ]);
  assert.equal(entries.length, 2);
  assert.equal(entries[0].address, "dead");
  assert.equal(entries[0].className, "Alacritty");
  assert.equal(entries[1].address, "55896300dc70");
  assert.equal(entries[1].title, "foot");
  assert.equal(entries[1].floating, true);
  assert.deepEqual(entries[1].at, [40, 50]);
});

test("collectMinimizedEntries drops windows with invalid addresses", () => {
  const entries = Model.collectMinimizedEntries([
    { address: "not-hex", workspace: { name: "special:minimized" } },
    { address: "", workspace: { name: "special:minimized" } }
  ]);
  assert.deepEqual(entries, []);
});

test("clampPointToMonitors recenters when the saved position is off every screen", () => {
  const monitors = [
    { x: 0, y: 0, width: 2560, height: 1440 },
    { x: 2560, y: 0, width: 1920, height: 1080 }
  ];
  assert.deepEqual(Model.clampPointToMonitors([994, 392], [984, 617], monitors), [994, 392]);
  assert.deepEqual(Model.clampPointToMonitors([-1474, 240], [1028, 600], monitors), [766, 420]);
  assert.deepEqual(Model.clampPointToMonitors([9000, 10], [400, 300], monitors), [3320, 390]);
});

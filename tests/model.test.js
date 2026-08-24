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

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const SCRIPT = path.resolve(__dirname, "../restore-last.sh");

function runRestore(clients, extra) {
  extra = extra || {};
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "minimized-restore-"));
  const hyprctl = path.join(dir, "hyprctl");
  const log = path.join(dir, "dispatch.log");
  const memoryFile = extra.memoryFile || path.join(dir, "memory.json");
  const clientsJson = JSON.stringify(clients);
  const monitorsJson = JSON.stringify(extra.monitors || [
    { specialWorkspace: { name: "special:minimized" } }
  ]);
  const activeWs = JSON.stringify(extra.activeWorkspace || { id: 1 });

  fs.writeFileSync(hyprctl, `#!/usr/bin/env bash
set -euo pipefail
log=${JSON.stringify(log)}
if [[ "\${1:-}" == "-j" && "\${2:-}" == "clients" ]]; then
  cat <<'EOF'
${clientsJson}
EOF
  exit 0
fi
if [[ "\${1:-}" == "-j" && "\${2:-}" == "activeworkspace" ]]; then
  cat <<'EOF'
${activeWs}
EOF
  exit 0
fi
if [[ "\${1:-}" == "-j" && "\${2:-}" == "monitors" ]]; then
  cat <<'EOF'
${monitorsJson}
EOF
  exit 0
fi
if [[ "\${1:-}" == "dispatch" ]]; then
  printf '%s\\n' "\$2" >> "$log"
  exit 0
fi
echo "unexpected hyprctl args: $*" >&2
exit 1
`, { mode: 0o755 });

  if (extra.memory) {
    fs.writeFileSync(memoryFile, JSON.stringify(extra.memory));
  }

  const env = Object.assign({}, process.env, {
    PATH: dir + ":" + process.env.PATH,
    MINIMIZED_FLOAT_MEMORY: memoryFile
  });
  const result = spawnSync("bash", [SCRIPT].concat(extra.args || []), { env, encoding: "utf8" });
  const dispatches = fs.existsSync(log)
    ? fs.readFileSync(log, "utf8").trim().split("\n").filter(Boolean)
    : [];
  return { status: result.status, stdout: result.stdout, stderr: result.stderr, dispatches, dir };
}

test("restore-last.sh re-applies floating geometry in order after the workspace move", () => {
  const { status, stderr, dispatches } = runRestore([
    {
      address: "0x55896300dc70",
      workspace: { name: "special:minimized" },
      focusHistoryID: 0,
      floating: true,
      at: [3170, 303],
      size: [700, 500]
    }
  ]);
  assert.equal(status, 0, stderr);
  assert.ok(dispatches.length >= 4, JSON.stringify(dispatches));
  assert.match(dispatches[0], /window\.move[\s\S]*workspace = 1/);
  assert.match(dispatches[1], /window\.float[\s\S]*enable/);
  assert.match(dispatches.join("\n"), /window\.resize[\s\S]*x = 700/);
  assert.match(dispatches.join("\n"), /x = 3170/);
  assert.match(dispatches[dispatches.length - 1], /toggle_special\("minimized"\)/);
});

test("restore-last.sh uses widget float memory when Hyprland dropped floating", () => {
  const { status, stderr, dispatches } = runRestore([
    {
      address: "0xabc",
      workspace: { name: "special:minimized" },
      focusHistoryID: 0,
      floating: false,
      at: [0, 0],
      size: [1920, 1080]
    }
  ], {
    memory: {
      abc: { floating: true, at: [40, 50], size: [640, 480] }
    }
  });
  assert.equal(status, 0, stderr);
  assert.match(dispatches.join("\n"), /window\.float/);
  assert.match(dispatches.join("\n"), /x = 640/);
  assert.match(dispatches.join("\n"), /x = 40/);
});

test("restore-last.sh is a no-op when nothing is minimized", () => {
  const { status, dispatches } = runRestore([
    { address: "0x1", workspace: { name: "1" }, focusHistoryID: 0 }
  ]);
  assert.equal(status, 0);
  assert.deepEqual(dispatches, []);
});

test("restore-last.sh restores to the focused monitor's active workspace while the overlay is open", () => {
  const { status, stderr, dispatches } = runRestore([
    {
      address: "0xabc",
      workspace: { name: "special:minimized" },
      focusHistoryID: 0,
      floating: false
    }
  ], {
    activeWorkspace: { id: -98 },
    monitors: [
      { focused: true, activeWorkspace: { id: 3 }, specialWorkspace: { name: "special:minimized" } }
    ]
  });
  assert.equal(status, 0, stderr);
  assert.match(dispatches[0], /workspace = 3/, JSON.stringify(dispatches));
});

test("restore-last.sh keeps live geometry when widget memory has null at/size", () => {
  const { status, stderr, dispatches } = runRestore([
    {
      address: "0xabc",
      workspace: { name: "special:minimized" },
      focusHistoryID: 0,
      floating: true,
      at: [120, 80],
      size: [800, 600]
    }
  ], {
    memory: { abc: { floating: true, at: null, size: null } }
  });
  assert.equal(status, 0, stderr);
  const joined = dispatches.join("\n");
  assert.match(joined, /window\.resize[\s\S]*x = 800\b/);
  assert.match(joined, /y = 600\b/);
  assert.match(joined, /window\.move[\s\S]*x = 120\b/);
  assert.match(joined, /y = 80\b/);
});

test("restore-last.sh sorts windows with missing focusHistoryID last", () => {
  const { dispatches } = runRestore([
    { address: "0xbbb", workspace: { name: "special:minimized" }, focusHistoryID: 7, floating: false },
    { address: "0xaaa", workspace: { name: "special:minimized" }, floating: false }
  ]);
  assert.match(dispatches[0], /0xbbb/, JSON.stringify(dispatches));
});

test("restore-last.sh skips malformed geometry and still restores", () => {
  const { status, stderr, dispatches } = runRestore([
    {
      address: "0xabc",
      workspace: { name: "special:minimized" },
      focusHistoryID: 0,
      floating: true,
      at: ["evil", {}],
      size: [1000000000, 5]
    }
  ]);
  assert.equal(status, 0, stderr);
  const joined = dispatches.join("\n");
  assert.match(joined, /window\.float/);
  assert.doesNotMatch(joined, /window\.resize/);
  assert.match(joined, /window\.center/);
});

test("restore-last.sh restores a specific address when given as an argument", () => {
  const { status, stderr, dispatches } = runRestore([
    {
      address: "0xaaa",
      workspace: { name: "special:minimized" },
      focusHistoryID: 0,
      floating: false
    },
    {
      address: "0xbbb",
      workspace: { name: "special:minimized" },
      focusHistoryID: 1,
      floating: false
    }
  ], { args: ["bbb"] });
  assert.equal(status, 0, stderr);
  assert.match(dispatches[0], /window = "address:0xbbb"/);
});

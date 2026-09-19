import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "..");

function files(directory) {
  const result = new Map();
  function visit(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) visit(full);
      else result.set(path.relative(directory, full), fs.readFileSync(full));
    }
  }
  visit(directory);
  return result;
}

test("release build is deterministic and catalogue hashes exact bytes", () => {
  const first = fs.mkdtempSync(path.join(os.tmpdir(), "aardwolf-core-release-a-"));
  const second = fs.mkdtempSync(path.join(os.tmpdir(), "aardwolf-core-release-b-"));
  try {
    for (const output of [first, second]) {
      execFileSync("python3", ["tools/build_release.py", "--out", output], { cwd: root, stdio: "pipe" });
    }
    const packageSentinel = path.join(first, "aardwolf-core-0.2.0.mfp");
    fs.writeFileSync(packageSentinel, "native-package-sentinel");
    execFileSync("python3", ["tools/build_release.py", "--out", first], { cwd: root, stdio: "pipe" });
    assert.equal(fs.readFileSync(packageSentinel, "utf8"), "native-package-sentinel");
    const firstFiles = files(first);
    const secondFiles = files(second);
    const generatedNames = [...firstFiles.keys()].filter((name) => name !== "aardwolf-core-0.2.0.mfp").sort();
    assert.deepEqual(generatedNames, [...secondFiles.keys()].sort());
    for (const name of generatedNames) assert.deepEqual(firstFiles.get(name), secondFiles.get(name), name);

    const index = JSON.parse(firstFiles.get("plugin-repo/plugins.json").toString("utf8"));
    const packageInput = JSON.parse(firstFiles.get("native-package-input/package-input.json").toString("utf8"));
    const plugin = firstFiles.get("plugin-repo/files/aardwolf-core.lua");
    const library = firstFiles.get("plugin-repo/libs/aardwolf-core-api.lua");
    assert.equal(index.plugins[0].sha256, crypto.createHash("sha256").update(plugin).digest("hex"));
    assert.equal(index.plugins[0].size, plugin.length);
    assert.equal(index.libraries[0].sha256, crypto.createHash("sha256").update(library).digest("hex"));
    assert.equal(index.libraries[0].size, library.length);
    assert.deepEqual(plugin, fs.readFileSync(path.join(root, "src/plugins/aardwolf-core.lua")));
    assert.deepEqual(library, fs.readFileSync(path.join(root, "src/libs/aardwolf-core-api.lua")));
    assert.equal(index.plugins[0].version, "0.2.0");
    assert.equal(index.libraries[0].version, "0.2.0");
    assert.equal(packageInput.minClientVersion, "1.2.2454");
    assert.equal([...firstFiles.keys()].some((name) => name.includes("aardwolf-ui-consumer")), false);
  } finally {
    fs.rmSync(first, { recursive: true, force: true });
    fs.rmSync(second, { recursive: true, force: true });
  }
});

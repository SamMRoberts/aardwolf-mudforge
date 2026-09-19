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
    const packageSentinel = path.join(first, "aardwolf-core-0.4.1.mfp");
    fs.writeFileSync(packageSentinel, "native-package-sentinel");
    execFileSync("python3", ["tools/build_release.py", "--out", first], { cwd: root, stdio: "pipe" });
    assert.equal(fs.readFileSync(packageSentinel, "utf8"), "native-package-sentinel");
    const firstFiles = files(first);
    const secondFiles = files(second);
    const generatedNames = [...firstFiles.keys()].filter((name) => name !== "aardwolf-core-0.4.1.mfp").sort();
    assert.deepEqual(generatedNames, [...secondFiles.keys()].sort());
    for (const name of generatedNames) assert.deepEqual(firstFiles.get(name), secondFiles.get(name), name);

    const index = JSON.parse(firstFiles.get("plugin-repo/plugins.json").toString("utf8"));
    const packageInput = JSON.parse(firstFiles.get("native-package-input/package-input.json").toString("utf8"));
    const corePlugin = firstFiles.get("plugin-repo/files/aardwolf-core.lua");
    const chatPlugin = firstFiles.get("plugin-repo/files/aardwolf-chat.lua");
    const library = firstFiles.get("plugin-repo/libs/aardwolf-core-api.lua");
    assert.deepEqual(index.plugins.map((plugin) => plugin.id), ["aardwolf-core", "aardwolf-chat"]);
    const coreRecord = index.plugins.find((plugin) => plugin.id === "aardwolf-core");
    const chatRecord = index.plugins.find((plugin) => plugin.id === "aardwolf-chat");
    assert.equal(coreRecord.sha256, crypto.createHash("sha256").update(corePlugin).digest("hex"));
    assert.equal(coreRecord.size, corePlugin.length);
    assert.equal(chatRecord.sha256, crypto.createHash("sha256").update(chatPlugin).digest("hex"));
    assert.equal(chatRecord.size, chatPlugin.length);
    assert.equal(chatRecord.category, "ui-enhancement");
    assert.equal(index.libraries[0].sha256, crypto.createHash("sha256").update(library).digest("hex"));
    assert.equal(index.libraries[0].size, library.length);
    assert.deepEqual(corePlugin, fs.readFileSync(path.join(root, "src/plugins/aardwolf-core.lua")));
    assert.deepEqual(chatPlugin, fs.readFileSync(path.join(root, "src/plugins/aardwolf-chat.lua")));
    assert.deepEqual(library, fs.readFileSync(path.join(root, "src/libs/aardwolf-core-api.lua")));
    assert.equal(coreRecord.version, "0.4.1");
    assert.equal(chatRecord.version, "0.4.1");
    assert.equal(index.libraries[0].version, "0.4.1");
    assert.deepEqual(packageInput.plugins.map((plugin) => plugin.id), ["aardwolf-core", "aardwolf-chat"]);
    assert.deepEqual(packageInput.libraries.map((library) => library.name), ["aardwolf-core-api"]);
    assert.equal(packageInput.packageId, "com.samroberts.aardwolf-core");
    assert.equal(packageInput.version, "0.4.1");
    assert.equal(packageInput.minClientVersion, "1.2.2454");
    assert.equal([...firstFiles.keys()].some((name) => name.includes("aardwolf-ui-consumer")), false);
  } finally {
    fs.rmSync(first, { recursive: true, force: true });
    fs.rmSync(second, { recursive: true, force: true });
  }
});

test("native package verifier requires exact Core, Chat, and API sources", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "aardwolf-package-verify-"));
  const valid = path.join(directory, "valid.mfp");
  const invalid = path.join(directory, "invalid.mfp");
  const fixture = String.raw`
import json, pathlib, sys, zipfile
root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
extra = sys.argv[3] == "extra"
manifest = json.loads((root / "release/manifest.json").read_text())
package = {
    "formatVersion": 1,
    "packageId": manifest["packageId"],
    "name": manifest["packageName"],
    "version": manifest["version"],
    "minClientVersion": manifest["minClientVersion"],
}
with zipfile.ZipFile(output, "w") as archive:
    archive.writestr("package.json", json.dumps(package))
    for plugin in manifest["plugins"]:
        archive.write(root / plugin["source"], "plugins/" + plugin["id"] + ".lua")
    library = manifest["library"]
    archive.write(root / library["source"], "libs/" + library["name"] + ".lua")
    if extra:
        archive.writestr("plugins/unexpected.lua", "plugin = {}")
`;
  try {
    execFileSync("python3", ["-c", fixture, root, valid, "clean"], { cwd: root, stdio: "pipe" });
    execFileSync("python3", ["tools/build_release.py", "--verify-package", valid], { cwd: root, stdio: "pipe" });
    execFileSync("python3", ["-c", fixture, root, invalid, "extra"], { cwd: root, stdio: "pipe" });
    assert.throws(
      () => execFileSync("python3", ["tools/build_release.py", "--verify-package", invalid], { cwd: root, stdio: "pipe" }),
      /Command failed/,
    );
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

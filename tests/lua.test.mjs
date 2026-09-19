import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import luaparse from "luaparse";
import { lua, lauxlib, lualib, to_luastring, to_jsstring } from "fengari";

const root = path.resolve(import.meta.dirname, "..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");
const harness = read("tests/harness.lua");
const coreSource = read("src/plugins/aardwolf-core.lua");
const chatSource = read("src/plugins/aardwolf-chat.lua");
const librarySource = read("src/libs/aardwolf-core-api.lua");
const referenceSource = read("examples/aardwolf-ui-consumer.lua");

function runLua(source, label) {
  const state = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(state);
  const status = lauxlib.luaL_dostring(state, to_luastring(`rawequal = nil\n${source}`));
  if (status !== lua.LUA_OK) {
    const message = to_jsstring(lua.lua_tostring(state, -1));
    assert.fail(`${label}: ${message}`);
  }
}

function wrappedLibrary(variable) {
  return `local function ${variable}_loader()\n${librarySource}\nend\n${variable} = ${variable}_loader()`;
}

test("plugins, library, and reference consumer parse as Lua 5.1", () => {
  for (const [name, source] of [["core plugin", coreSource], ["chat plugin", chatSource], ["library", librarySource], ["reference", referenceSource]]) {
    assert.doesNotThrow(() => luaparse.parse(source, { luaVersion: "5.1" }), name);
  }
});

test("Lua function parameters avoid strict-mode JavaScript binding names", () => {
  const forbidden = new Set(["arguments", "eval"]);
  const visit = (node, label) => {
    if (!node || typeof node !== "object") return;
    if ((node.type === "FunctionDeclaration" || node.type === "FunctionExpression") && Array.isArray(node.parameters)) {
      for (const parameter of node.parameters) {
        if (parameter.type === "Identifier") {
          assert.equal(forbidden.has(parameter.name), false, `${label} parameter ${parameter.name} is invalid in strict mode`);
        }
      }
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) {
        for (const child of value) visit(child, label);
      } else if (value && typeof value === "object") {
        visit(value, label);
      }
    }
  };

  for (const [label, source] of [["core plugin", coreSource], ["chat plugin", chatSource], ["library", librarySource], ["reference", referenceSource]]) {
    visit(luaparse.parse(source, { luaVersion: "5.1" }), label);
  }
});

test("copy guards use MudForge plugin-scope builtins", () => {
  for (const [name, source] of [["core plugin", coreSource], ["chat plugin", chatSource], ["library", librarySource]]) {
    assert.doesNotMatch(source, /seen\s*\[\s*value\s*\]/, `${name} must not key a seen table by another table`);
    assert.doesNotMatch(source, /\brawequal\s*\(/, `${name} must not call the unavailable rawequal global`);
  }
});

test("Core lifecycle, negotiation, validation, widget, and reset contract", () => {
  runLua(`${harness}\n${wrappedLibrary("core_api_for_plugin")}\nfunction require(name) if name == "aardwolf-core-api" then return core_api_for_plugin end error("missing library " .. tostring(name)) end\n${coreSource}\n${read("tests/core_spec.lua")}`, "core_spec.lua");
});

test("consumer API handshake, requests, events, storage, and missing-Core behavior", () => {
  let spec = read("tests/api_spec.lua");
  spec = spec.replace("local core = __LIBRARY_MODULE__", `${wrappedLibrary("core")}\nlocal core = core`);
  spec = spec.replace("local other = __OTHER_LIBRARY_MODULE__", `${wrappedLibrary("other")}\nlocal other = other`);
  spec = spec.replace("local ui_core = __UI_LIBRARY_MODULE__", `${wrappedLibrary("ui_core")}\nlocal ui_core = ui_core`);
  spec = spec.replace("local core_missing = __NEW_LIBRARY_MODULE__", `${wrappedLibrary("core_missing")}\nlocal core_missing = core_missing`);
  runLua(`${harness}\n${spec}`, "api_spec.lua");
});

test("reference consumer exercises managed HTML and canvas lifecycle", () => {
  runLua(`${harness}\n${wrappedLibrary("reference_core")}\nfunction require(name) if name == "aardwolf-core-api" then return reference_core end error("missing library " .. tostring(name)) end\n${referenceSource}\n${read("tests/reference_spec.lua")}`, "reference_spec.lua");
});

test("Aardwolf Chat routes, configures, persists, bounds, and cleans up", () => {
  runLua(`${harness}\n${wrappedLibrary("chat_core")}\nfunction require(name) if name == "aardwolf-core-api" then return chat_core end error("missing library " .. tostring(name)) end\n${chatSource}\n${read("tests/chat_spec.lua")}`, "chat_spec.lua");
});

test("Aardwolf Chat recovers from consumer-first load order", () => {
  runLua(`${harness}\n${wrappedLibrary("missing_chat_core")}\nfunction require(name) if name == "aardwolf-core-api" then return missing_chat_core end error("missing library " .. tostring(name)) end\n${chatSource}\n${read("tests/chat_missing_core_spec.lua")}`, "chat_missing_core_spec.lua");
});

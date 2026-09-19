local core = __LIBRARY_MODULE__

on("aardwolf.core.consumer.declare", function(payload)
  emit("aardwolf.core.consumer.registration", {
    consumerId = payload.consumerId,
    ok = payload.minProtocol <= 1,
    code = payload.minProtocol <= 1 and nil or "unsupported-protocol",
    message = payload.minProtocol <= 1 and nil or "too new",
    protocol = 1,
    version = "0.1.0",
    apiVersion = "0.1.0",
  })
end)

local request_count = 0
on("aardwolf.core.request", function(payload)
  request_count = request_count + 1
  local data = nil
  if payload.kind == "status" then data = { protocol = 1, connected = true }
  elseif payload.kind == "snapshot" then data = { normalized = { hp = 99 }, raw = { hp = 99 }, fresh = true }
  elseif payload.kind == "refresh" then data = { requested = payload.packages }
  elseif payload.kind == "renegotiate" then data = { protocol = 1 } end
  emit("aardwolf.core.response", {
    consumerId = payload.consumerId,
    requestId = payload.requestId,
    ok = data ~= nil,
    data = data,
    code = data and nil or "unknown-request",
    message = data and nil or "unknown request",
    protocol = 1,
  })
end)

local ok, problem = core.init({
  pluginId = "test-consumer",
  minProtocol = 1,
  packages = { Char = true },
  on = on,
  off = off,
  emit = emit,
  getLoadedPlugins = getLoadedPlugins,
  saveTable = saveTable,
  loadTable = loadTable,
})
TEST.assert_true(ok, "API registration")
TEST.assert_nil(problem, "API registration error")

local status, status_error = core.status()
TEST.assert_nil(status_error, "status error")
TEST.assert_equal(status.protocol, 1, "status response")
local snapshot, snapshot_error = core.get("char.vitals")
TEST.assert_nil(snapshot_error, "snapshot error")
TEST.assert_equal(snapshot.normalized.hp, 99, "snapshot response")
local refreshed, refresh_error = core.refresh({ Char = true, Room = true })
TEST.assert_nil(refresh_error, "refresh error")
TEST.assert_true(refreshed.requested.Room, "refresh package forwarded")
local invalid_refresh, invalid_refresh_error = core.refresh({ Comm = true })
TEST.assert_nil(invalid_refresh, "non-refreshable package rejected")
TEST.assert_equal(invalid_refresh_error.code, "invalid-refresh-package", "refresh package error")
local renegotiated = core.renegotiate()
TEST.assert_equal(renegotiated.protocol, 1, "renegotiation response")
TEST.assert_equal(request_count, 4, "requests routed synchronously")

local observed = nil
core.on("char.vitals", function(payload)
  observed = payload
  payload.normalized.hp = 1
end)
local source = { normalized = { hp = 77 } }
emit("aardwolf.core.char.vitals", source)
TEST.assert_equal(observed.normalized.hp, 1, "consumer callback receives data")
TEST.assert_equal(source.normalized.hp, 77, "consumer receives a defensive copy")

local saved, save_error = core.storage.save("preferences", 2, { enabled = true }, "world")
TEST.assert_true(saved, "world storage save")
TEST.assert_nil(save_error, "world storage save error")
TEST.assert_true(TEST.tables.world["aardwolf:test-consumer:preferences"].data.enabled, "world key namespaced")
local loaded, load_error = core.storage.load("preferences", 2, "world")
TEST.assert_nil(load_error, "world storage load error")
TEST.assert_true(loaded.enabled, "world storage load")
local mismatch, mismatch_error = core.storage.load("preferences", 3, "world")
TEST.assert_nil(mismatch, "schema mismatch has no data")
TEST.assert_equal(mismatch_error.code, "schema-mismatch", "schema mismatch reported")
TEST.tables.world["aardwolf:test-consumer:malformed"] = { format = 1, owner = "someone-else", schema = 1, data = {} }
local malformed, malformed_error = core.storage.load("malformed", 1, "world")
TEST.assert_nil(malformed, "foreign envelope rejected")
TEST.assert_equal(malformed_error.code, "invalid-envelope", "foreign envelope error")

core.storage.save("shared", 1, { value = 42 }, "global")
TEST.assert_equal(TEST.tables.global["aardwolf:test-consumer:shared"].data.value, 42, "global key namespaced")
core.storage.delete("preferences", "world")
local deleted, deleted_error = core.storage.load("preferences", 1, "world")
TEST.assert_nil(deleted, "deleted value absent")
TEST.assert_nil(deleted_error, "deletion marker is not an error")

local invalid, invalid_error = core.storage.save("bad name", 1, {}, "world")
TEST.assert_nil(invalid, "invalid storage name rejected")
TEST.assert_equal(invalid_error.code, "invalid-storage-name", "invalid storage error")

core.cleanup()
TEST.assert_equal(#TEST.events["aardwolf.core.response"], 0, "cleanup releases response listener")

local other = __OTHER_LIBRARY_MODULE__
table.insert(TEST.loadedPlugins, { id = "other-consumer", enabled = true })
local other_ok = other.init({
  pluginId = "other-consumer", minProtocol = 1, packages = {}, on = on, off = off,
  emit = emit, getLoadedPlugins = getLoadedPlugins, saveTable = saveTable, loadTable = loadTable,
})
TEST.assert_true(other_ok, "second consumer initializes")
other.storage.save("shared", 1, { value = 7 }, "global")
TEST.assert_equal(TEST.tables.global["aardwolf:test-consumer:shared"].data.value, 42, "first consumer key preserved")
TEST.assert_equal(TEST.tables.global["aardwolf:other-consumer:shared"].data.value, 7, "second consumer key isolated")
other.cleanup()

local core_missing = __NEW_LIBRARY_MODULE__
TEST.loadedPlugins = { { id = "test-consumer", enabled = true } }
local missing_ok, missing_error = core_missing.init({
  pluginId = "test-consumer",
  minProtocol = 1,
  packages = { Char = true },
  on = on,
  off = off,
  emit = emit,
  getLoadedPlugins = getLoadedPlugins,
  saveTable = saveTable,
  loadTable = loadTable,
})
TEST.assert_nil(missing_ok, "missing Core prevents activation")
TEST.assert_equal(missing_error.code, "missing-core", "missing Core is actionable")
table.insert(TEST.loadedPlugins, { id = "aardwolf-core", enabled = true })
emit("aardwolf.core.consumer.discover", { protocol = 1 })
local recovered_status, recovered_error = core_missing.status()
TEST.assert_nil(recovered_error, "consumer-first instance recovers on discovery")
TEST.assert_equal(recovered_status.protocol, 1, "recovered instance can request status")
core_missing.cleanup()

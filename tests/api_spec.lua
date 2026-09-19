local core = __LIBRARY_MODULE__

local initial_tokens = core.ui.tokens()
initial_tokens.colors.primary = "changed"
TEST.assert_equal(core.ui.tokens().colors.primary, "#f3c969", "UI tokens are defensive copies")
local initial_document, initial_document_error = core.ui.document([[<p data-mud-bind="message">Waiting</p>]], { css = ".sample{display:block}" })
TEST.assert_nil(initial_document_error, "stateless UI document error")
TEST.assert_true(string.find(initial_document, "aw%-root") ~= nil, "stateless UI document includes shared styles")
TEST.assert_nil(core.ui.appTheme().terminalColors, "app theme does not override terminal colors")

on("aardwolf.core.consumer.declare", function(payload)
  emit("aardwolf.core.consumer.registration", {
    consumerId = payload.consumerId,
    ok = payload.minProtocol <= 1,
    code = payload.minProtocol <= 1 and nil or "unsupported-protocol",
    message = payload.minProtocol <= 1 and nil or "too new",
    protocol = 1,
    version = "0.2.1",
    apiVersion = "0.2.1",
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
local no_ui_window, no_ui_error = core.ui.create({ name = "missing", title = "Missing", type = "html" })
TEST.assert_nil(no_ui_window, "consumer without UI adapter cannot create windows")
TEST.assert_equal(no_ui_error.code, "ui-unavailable", "missing UI adapter is actionable")

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

local ui_core = __UI_LIBRARY_MODULE__
table.insert(TEST.loadedPlugins, { id = "ui-consumer", enabled = true })
local ui_declares = {}
local ui_states = {}
local ui_withdraws = {}
on("aardwolf.core.ui.window.declare", function(payload) table.insert(ui_declares, payload) end)
on("aardwolf.core.ui.window.state", function(payload) table.insert(ui_states, payload) end)
on("aardwolf.core.ui.window.withdraw", function(payload) table.insert(ui_withdraws, payload) end)
local bad_ui_ok, bad_ui_error = ui_core.init({
  pluginId = "ui-consumer", minProtocol = 1, packages = {}, on = on, off = off,
  emit = emit, getLoadedPlugins = getLoadedPlugins, saveTable = saveTable, loadTable = loadTable,
  ui = {},
})
TEST.assert_nil(bad_ui_ok, "incomplete UI adapter rejected")
TEST.assert_equal(bad_ui_error.code, "invalid-ui-adapter", "incomplete UI adapter error")
local ui_ok, ui_problem = ui_core.init({
  pluginId = "ui-consumer", minProtocol = 1, packages = {}, on = on, off = off,
  emit = emit, getLoadedPlugins = getLoadedPlugins, saveTable = saveTable, loadTable = loadTable,
  ui = {
    createWidget = createWidget, setWidgetProperty = setWidgetProperty,
    showWidget = showWidget, hideWidget = hideWidget, destroyWidget = destroyWidget,
    setBoundValues = setBoundValues, registerWidgetEvent = registerWidgetEvent,
    unregisterWidgetEvent = unregisterWidgetEvent,
    widgetInfo = widgetInfo, focusPrompt = focusPrompt,
  },
})
TEST.assert_true(ui_ok, "UI consumer initializes")
TEST.assert_nil(ui_problem, "UI consumer initialization error")
local invalid_window, invalid_window_error = ui_core.ui.create({ name = "bad", title = "Bad", type = "html", size = { width = 20, height = 20 } })
TEST.assert_nil(invalid_window, "invalid window geometry rejected")
TEST.assert_equal(invalid_window_error.code, "invalid-window", "invalid geometry error")

local html_window, html_error = ui_core.ui.create({
  name = "panel", title = "Reference Panel", type = "html",
  content = [[<button class="aw-button" data-mud-action="ping">Ping</button><span data-mud-bind="message">Waiting</span>]],
  position = { x = 50, y = 60 }, size = { width = 420, height = 240 },
})
TEST.assert_nil(html_error, "HTML window creation error")
TEST.assert_equal(html_window.widgetId, "widget-1", "HTML window returns widget id")
TEST.assert_equal(TEST.widgets["widget-1"].visible, false, "managed windows default hidden")
TEST.assert_true(string.find(TEST.widgets["widget-1"].properties.content, "aw%-button") ~= nil, "HTML content receives shared component styles")
TEST.assert_equal(TEST.widgets["widget-1"].config.appearance.titleTextColor, "#f3c969", "managed chrome uses shared palette")
TEST.assert_equal(ui_declares[#ui_declares].name, "panel", "window declares to Core")

local duplicate, duplicate_error = ui_core.ui.create({ name = "panel", title = "Duplicate", type = "html" })
TEST.assert_nil(duplicate, "duplicate window rejected")
TEST.assert_equal(duplicate_error.code, "window-exists", "duplicate window error")
local bound, bind_error = ui_core.ui.bind("panel", { message = "Bound text only" })
TEST.assert_true(bound, "HTML bindings update")
TEST.assert_nil(bind_error, "HTML binding error")
TEST.assert_equal(TEST.widgets["widget-1"].bindings.message, "Bound text only", "bound value reaches widget API")
local invalid_bound, invalid_bind_error = ui_core.ui.bind("panel", { message = { unsafe = true } })
TEST.assert_nil(invalid_bound, "non-scalar binding rejected")
TEST.assert_equal(invalid_bind_error.code, "invalid-window", "invalid binding error")
local acted = nil
ui_core.ui.on("panel", "action", function(event) acted = event.action end)
TEST.widgets["widget-1"].events.action({ action = "ping" })
TEST.assert_equal(acted, "ping", "managed action callback fires")
TEST.assert_true(TEST.focused, "managed actions return focus to prompt")

local canvas_window, canvas_error = ui_core.ui.create({ name = "canvas", title = "Reference Canvas", type = "canvas", visible = true })
TEST.assert_nil(canvas_error, "canvas window creation error")
TEST.assert_equal(canvas_window.widgetId, "widget-2", "canvas returns raw widget id")
ui_core.ui.hide("canvas")
TEST.assert_equal(TEST.widgets["widget-2"].visible, false, "hide controls managed canvas")
ui_core.ui.toggle("canvas")
TEST.assert_equal(TEST.widgets["widget-2"].visible, true, "toggle controls managed canvas")
emit("aardwolf.core.ui.window.command", { consumerId = "ui-consumer", name = "panel", action = "show" })
TEST.assert_equal(TEST.widgets["widget-1"].visible, true, "Core command shows targeted window")
emit("aardwolf.core.ui.window.command", { consumerId = "other-consumer", name = "panel", action = "hide" })
TEST.assert_equal(TEST.widgets["widget-1"].visible, true, "foreign Core command ignored")
emit("aardwolf.core.ui.window.query", {})
TEST.assert_true(#ui_states >= 2, "Core query refreshes managed window state")
local declarations_before_discovery = #ui_declares
emit("aardwolf.core.consumer.discover", { protocol = 1 })
TEST.assert_true(#ui_declares >= declarations_before_discovery + 2, "Core rediscovery re-registers surviving windows")

ui_core.ui.destroy("panel")
TEST.assert_nil(TEST.widgets["widget-1"], "destroy releases HTML widget")
local unknown, unknown_error = ui_core.ui.show("panel")
TEST.assert_nil(unknown, "destroyed window is unknown")
TEST.assert_equal(unknown_error.code, "unknown-window", "unknown window error")
ui_core.cleanup()
TEST.assert_nil(TEST.widgets["widget-2"], "cleanup destroys remaining managed windows")
TEST.assert_true(#ui_withdraws >= 2, "destroy and cleanup withdraw managed windows")

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

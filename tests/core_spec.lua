init()
TEST.assert_equal(TEST.nextWidget, 1, "one widget created")
TEST.assert_equal(TEST.widgets["widget-1"].visible, false, "widget starts hidden")
TEST.assert_true(string.find(TEST.widgets["widget-1"].properties.content, "aw%-root") ~= nil, "control center uses shared document")
TEST.assert_equal(TEST.themeCalls, 0, "app theme is not registered automatically")
TEST.assert_equal(#TEST.gmcpHandlers["Char.Vitals"], 1, "one vitals handler")
init()
TEST.assert_equal(TEST.nextWidget, 1, "duplicate init is ignored")
TEST.assert_equal(#TEST.gmcpHandlers["Char.Vitals"], 1, "duplicate init does not subscribe")

local registration = nil
on("aardwolf.core.consumer.registration", function(payload)
  if payload.consumerId == "test-consumer" then registration = payload end
end)
emit("aardwolf.core.consumer.declare", {
  consumerId = "test-consumer",
  minProtocol = 1,
  packages = { Char = true, Comm = true },
})
TEST.assert_true(registration.ok, "consumer registration succeeds")
TEST.assert_equal(registration.capabilities.ui.version, 1, "registration advertises UI contract")

local ui_commands = {}
on("aardwolf.core.ui.window.command", function(payload) table.insert(ui_commands, payload) end)
emit("aardwolf.core.ui.window.declare", {
  consumerId = "test-consumer",
  name = "inventory",
  title = "Inventory",
  type = "html",
  visible = false,
})
local ui_status = TEST.request("test-consumer", "status")
TEST.assert_equal(ui_status.data.windows["test-consumer:inventory"].title, "Inventory", "managed window appears in status")
TEST.assert_equal(TEST.widgets["widget-1"].bindings.windowTitle1, "Inventory", "managed window title uses binding")
TEST.widgets["widget-1"].events.action({ action = "window-show-1" })
TEST.assert_equal(ui_commands[#ui_commands].action, "show", "control center targets individual window")
TEST.widgets["widget-1"].events.action({ action = "windows-hide-all" })
TEST.assert_equal(ui_commands[#ui_commands].action, "hide", "control center hides all windows")
emit("aardwolf.core.ui.window.state", { consumerId = "test-consumer", name = "inventory", visible = true })
TEST.assert_equal(TEST.widgets["widget-1"].bindings.windowVisible1, "visible", "window visibility binding updates")
TEST.widgets["widget-1"].events.action({ action = "apply-theme" })
TEST.assert_equal(TEST.activeTheme, "aardwolf-dark", "theme applies only after explicit action")
TEST.assert_nil(TEST.themes["aardwolf-dark"].terminalColors, "app theme leaves terminal colors untouched")

TEST.connected = true
onConnect("session-1")
TEST.advance(150)
TEST.assert_equal(#TEST.sentGMCP, 3, "negotiation and two bootstrap requests")
TEST.assert_equal(TEST.sentGMCP[1].package, "Core.Supports.Set", "supports sent first")
TEST.assert_equal(TEST.sentGMCP[1].data[1], "Core 1", "stable package order core")
TEST.assert_equal(TEST.sentGMCP[1].data[2], "Char 1", "stable package order char")
TEST.assert_equal(TEST.sentGMCP[1].data[3], "Comm 1", "consumer package included")
TEST.assert_equal(TEST.sentGMCP[1].data[4], "Room 1", "baseline room included")
TEST.assert_equal(TEST.sentGMCP[2].package, "request char", "character refresh follows negotiation")
TEST.assert_equal(TEST.sentGMCP[3].package, "request room", "room refresh follows negotiation")

local vitals_event = nil
on("aardwolf.core.char.vitals", function(payload) vitals_event = payload end)
TEST.fireGMCP("Char.Vitals", { hp = 100, mana = 80, moves = 60, future = "kept raw" })
TEST.assert_equal(vitals_event.normalized.hp, 100, "vitals normalized")
TEST.assert_nil(vitals_event.normalized.future, "unknown value omitted from normalized data")
TEST.assert_equal(vitals_event.raw.future, "kept raw", "unknown value retained in raw data")
vitals_event.normalized.hp = 1
local snapshot = TEST.request("test-consumer", "snapshot", { path = "char.vitals" })
TEST.assert_true(snapshot.ok, "fresh snapshot succeeds")
TEST.assert_equal(snapshot.data.normalized.hp, 100, "snapshot retains accepted data")

TEST.fireGMCP("Char.Vitals", {
  hp = 101,
  future = { first = { value = 1 }, second = { value = 2 } },
})
snapshot = TEST.request("test-consumer", "snapshot", { path = "char.vitals" })
TEST.assert_equal(snapshot.data.normalized.hp, 101, "ordinary nested GMCP tables do not look cyclic")
TEST.assert_equal(snapshot.data.raw.future.second.value, 2, "nested unknown GMCP data is copied")

TEST.fireGMCP("Char.Vitals", { hp = "100" })
local rejected = TEST.request("test-consumer", "status")
TEST.assert_equal(rejected.data.counters.rejected, 1, "invalid numeric field rejected")
snapshot = TEST.request("test-consumer", "snapshot", { path = "char.vitals" })
TEST.assert_equal(snapshot.data.normalized.hp, 101, "rejection preserves prior accepted data")

TEST.fireGMCP("Char.Base", {
  name = "Tester", ["class"] = "Warrior", subclass = "Soldier", race = "Human",
  clan = "", pretitle = "", classes = "03", perlevel = 1000, tier = 1,
  remorts = 1, redos = 0, level = 10, pups = 0, totpups = 0,
})
TEST.fireGMCP("Char.Stats", { str = 10, int = 11, wis = 12, dex = 13, con = 14, luck = 15, hr = 16, dr = 17, saves = 18 })
TEST.fireGMCP("Char.MaxStats", { maxhp = 100, maxmana = 90, maxmoves = 80, maxstr = 20, maxint = 21, maxwis = 22, maxdex = 23, maxcon = 24, maxluck = 25 })
TEST.fireGMCP("Char.Status", { level = 10, tnl = 200, hunger = 80, thirst = 70, align = 0, state = 3, pos = "Standing", enemy = "", enemypct = 0 })
TEST.fireGMCP("Char.Worth", { gold = 1000, bank = 2000, qp = 30, tp = 4, trains = 5, pracs = 6, qpearned = 7 })
for _, path in ipairs({ "char.base", "char.stats", "char.maxstats", "char.status", "char.worth" }) do
  TEST.assert_true(TEST.request("test-consumer", "snapshot", { path = path }).ok, path .. " accepted")
end

TEST.fireGMCP("Char.Base", { classes = "00" })
TEST.fireGMCP("Char.Stats", { str = "10" })
TEST.fireGMCP("Char.MaxStats", { maxhp = math.huge })
TEST.fireGMCP("Char.Status", { pos = "bad\nvalue" })
TEST.fireGMCP("Char.Worth", { gold = 1.5 })
local deep = { value = "leaf" }
for _ = 1, 9 do deep = { child = deep } end
TEST.fireGMCP("Char.Vitals", { hp = 100, future = deep })
local cyclic = {}
cyclic.self = cyclic
TEST.fireGMCP("Char.Vitals", { hp = 100, future = cyclic })
local all_groups_status = TEST.request("test-consumer", "status")
TEST.assert_equal(all_groups_status.data.counters.rejected, 8, "every invalid Char schema, raw limit, and real cycle rejected")
TEST.assert_nil(TEST.tables.world["aardwolf:core:char"], "live character data is not persisted")

TEST.fireGMCP("Room.Info", {
  num = 123,
  name = "A Test Room",
  zone = "test-zone",
  terrain = "city",
  exits = { n = 124 },
  coord = { id = 1, x = 10, y = 20, cont = 0 },
})
local room = TEST.request("test-consumer", "snapshot", { path = "room.info" })
TEST.assert_true(room.ok, "room snapshot succeeds")
TEST.assert_equal(room.data.normalized.exits.n, 124, "room exit validated")
TEST.fireGMCP("Room.Info", { num = 123, exits = { n = "124" } })
room = TEST.request("test-consumer", "snapshot", { path = "room.info" })
TEST.assert_equal(room.data.normalized.name, "A Test Room", "invalid room preserves prior accepted data")

local sent_before = #TEST.sentGMCP
TEST.fireGMCP("Char.Base", { name = "Tester", classes = "03", level = 10 })
TEST.advance(2000)
TEST.assert_equal(#TEST.sentGMCP, sent_before, "character refresh response does not reopen negotiation loop")

local before_withdraw = #TEST.sentGMCP
emit("aardwolf.core.consumer.withdraw", { consumerId = "test-consumer" })
TEST.advance(150)
TEST.assert_equal(#TEST.sentGMCP, before_withdraw + 1, "withdrawal renegotiates the reduced union")
TEST.assert_equal(TEST.sentGMCP[#TEST.sentGMCP].data[1], "Core 1", "reduced union retains Core")
TEST.assert_equal(TEST.sentGMCP[#TEST.sentGMCP].data[2], "Char 1", "reduced union retains Char")
TEST.assert_equal(TEST.sentGMCP[#TEST.sentGMCP].data[3], "Room 1", "reduced union retains Room")

local invalid_registration = nil
on("aardwolf.core.consumer.registration", function(payload)
  if payload.consumerId == "test-consumer" and payload.ok == false then invalid_registration = payload end
end)
emit("aardwolf.core.consumer.declare", {
  consumerId = "test-consumer", minProtocol = 1, packages = { MadeUp = true },
})
TEST.assert_equal(invalid_registration.code, "invalid-package", "unknown package rejected")

onDisconnect("session-1")
local stale = TEST.request("test-consumer", "snapshot", { path = "char.vitals" })
TEST.assert_equal(stale.ok, false, "disconnect clears character freshness")
local status = TEST.request("test-consumer", "status")
TEST.assert_equal(status.data.connected, false, "disconnect reported")
TEST.assert_equal(status.data.freshness.room, false, "room freshness cleared")

TEST.sentGMCP = {}
TEST.sendGMCPResult = false
TEST.connected = true
onConnect("session-2")
TEST.advance(150)
TEST.advance(1000)
TEST.advance(1100)
TEST.assert_equal(#TEST.sentGMCP, 2, "failed negotiation receives exactly one retry")
TEST.assert_equal(TEST.request("test-consumer", "status").data.counters.negotiationFailures, 2, "failed sends counted")
TEST.assert_equal(TEST.request("test-consumer", "snapshot", { path = "char.vitals" }).ok, false, "new session cannot see old data")
TEST.sendGMCPResult = true
onDisconnect("session-2")

TEST.commands.awcore.callback("")
TEST.assert_equal(TEST.widgets["widget-1"].visible, true, "command shows widget")
TEST.widgets["widget-1"].events.action({ action = "hide" })
TEST.assert_equal(TEST.widgets["widget-1"].visible, false, "widget hide action")
TEST.widgets["widget-1"].events.action({ action = "log-debug" })
TEST.assert_equal(TEST.tables.world["aardwolf:core:settings"].logLevel, "debug", "log level persisted")
emit("aardwolf.core.ui.window.withdraw", { consumerId = "test-consumer", name = "inventory" })
TEST.assert_nil(TEST.request("test-consumer", "status").data.windows["test-consumer:inventory"], "window withdrawal clears registry")

cleanup()
TEST.assert_nil(TEST.widgets["widget-1"], "cleanup destroys widget")
TEST.assert_equal(#TEST.events["aardwolf.core.consumer.declare"], 0, "cleanup releases custom event")

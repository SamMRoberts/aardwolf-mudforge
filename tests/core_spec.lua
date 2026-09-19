init()
TEST.assert_equal(TEST.nextWidget, 1, "one widget created")
TEST.assert_equal(TEST.widgets["widget-1"].visible, false, "widget starts hidden")
TEST.assert_true(string.find(TEST.widgets["widget-1"].properties.content, "aw%-root") ~= nil, "control center uses shared document")
TEST.assert_equal(TEST.themeCalls, 0, "app theme is not registered automatically")
TEST.assert_equal(#TEST.gmcpHandlers["Char.Vitals"], 1, "one vitals handler")
TEST.assert_equal(#TEST.gmcpHandlers["Group"], 1, "one group handler")
for _, package_name in ipairs({ "Comm.Channel", "Comm.Tick", "Comm.Quest", "Comm.Repop" }) do
  TEST.assert_equal(#TEST.gmcpHandlers[package_name], 1, "one " .. package_name .. " handler")
end
init()
TEST.assert_equal(TEST.nextWidget, 1, "duplicate init is ignored")
TEST.assert_equal(#TEST.gmcpHandlers["Char.Vitals"], 1, "duplicate init does not subscribe")
TEST.assert_equal(#TEST.gmcpHandlers["Group"], 1, "duplicate init does not subscribe Group")
TEST.assert_equal(#TEST.gmcpHandlers["Comm.Channel"], 1, "duplicate init does not subscribe Comm")

local registration = nil
on("aardwolf.core.consumer.registration", function(payload)
  if payload.consumerId == "test-consumer" then registration = payload end
end)
emit("aardwolf.core.consumer.declare", {
  consumerId = "test-consumer",
  minProtocol = 1,
  packages = { Char = true, Comm = true, Group = true },
})
TEST.assert_true(registration.ok, "consumer registration succeeds")
TEST.assert_true(registration.capabilities.Comm, "registration advertises Comm handling")
TEST.assert_true(registration.capabilities.Group, "registration advertises Group handling")
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
TEST.assert_equal(#TEST.sentGMCP, 3, "only negotiation and two bootstrap requests are sent")
TEST.assert_equal(TEST.sentGMCP[1].package, "Core.Supports.Set", "supports sent first")
TEST.assert_equal(TEST.sentGMCP[1].data[1], "Core 1", "stable package order core")
TEST.assert_equal(TEST.sentGMCP[1].data[2], "Char 1", "stable package order char")
TEST.assert_equal(TEST.sentGMCP[1].data[3], "Comm 1", "consumer package included")
TEST.assert_equal(TEST.sentGMCP[1].data[4], "Room 1", "baseline room included")
TEST.assert_equal(TEST.sentGMCP[1].data[5], "Group 1", "consumer group package included")
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

local group_event = nil
on("aardwolf.core.group.updated", function(payload) group_event = payload end)
TEST.fireGMCP("Group", {
  groupname = "Testers", leader = "Tester", created = "19 Sep 12:00",
  status = "Private", count = 2, kills = 4, exp = 500,
  members = {
    { name = "Tester", info = { hp = 100, mhp = 100, mn = 80, mmn = 90, mv = 70, mmv = 75, align = 0, tnl = 20, qt = 0, qs = 0, lvl = 10, here = 1 } },
    { name = "Friend", info = { hp = 90, mhp = 100, mn = 70, mmn = 90, mv = 60, mmv = 75, align = 100, tnl = 30, qt = 5, qs = 1, lvl = 10, here = 0 } },
  },
  future = "retained raw",
})
TEST.assert_equal(group_event.package, "Group", "group event identifies its package")
TEST.assert_equal(group_event.normalized.members[2].name, "Friend", "group members normalized")
TEST.assert_nil(group_event.normalized.future, "unknown group field omitted from normalized data")
TEST.assert_equal(group_event.raw.future, "retained raw", "unknown group field retained in raw data")
group_event.normalized.members[1].name = "changed"
local group_snapshot = TEST.request("test-consumer", "snapshot", { path = "group" })
TEST.assert_true(group_snapshot.ok, "fresh group snapshot succeeds")
TEST.assert_equal(group_snapshot.data.normalized.members[1].name, "Tester", "group snapshot is isolated from listeners")

TEST.fireGMCP("Group", {
  groupname = "Testers", count = 1,
  members = { { name = "Tester", info = { hp = 95, mhp = 100, here = 1 } } },
})
group_snapshot = TEST.request("test-consumer", "snapshot", { path = "group" })
TEST.assert_equal(group_snapshot.data.normalized.count, 1, "new group snapshot replaces old header values")
TEST.assert_nil(group_snapshot.data.normalized.members[2], "group replacement drops departed members")
local accepted_group_sequence = group_snapshot.data.sequence
TEST.fireGMCP("Group", { members = { { name = "Tester", info = { hp = "95" } } } })
group_snapshot = TEST.request("test-consumer", "snapshot", { path = "group" })
TEST.assert_equal(group_snapshot.data.sequence, accepted_group_sequence, "invalid group leaves prior snapshot intact")

local comm_all = {}
local channel_event = nil
local tick_event = nil
local quest_event = nil
local repop_event = nil
on("aardwolf.core.comm.updated", function(payload) table.insert(comm_all, payload) end)
on("aardwolf.core.comm.channel", function(payload) channel_event = payload end)
on("aardwolf.core.comm.tick", function(payload) tick_event = payload end)
on("aardwolf.core.comm.quest", function(payload) quest_event = payload end)
on("aardwolf.core.comm.repop", function(payload) repop_event = payload end)
local colored_message = string.char(27) .. "[31mYou gossip 'Testing'"
TEST.fireGMCP("Comm.Channel", { chan = "gossip", msg = colored_message, player = "Tester", future = "kept" })
TEST.assert_equal(channel_event.normalized.chan, "gossip", "channel normalized")
TEST.assert_equal(channel_event.normalized.msg, colored_message, "ANSI channel text is preserved")
TEST.assert_equal(channel_event.raw.future, "kept", "channel raw fields retained")
TEST.assert_equal(comm_all[#comm_all].sequence, channel_event.sequence, "generic and subtype Comm events share sequence")
channel_event.normalized.chan = "changed"
TEST.assert_equal(comm_all[#comm_all].normalized.chan, "gossip", "Comm listeners receive defensive copies")
TEST.fireGMCP("Comm.Tick", {})
TEST.assert_equal(tick_event.package, "Comm.Tick", "tick event delivered")
TEST.fireGMCP("Comm.Quest", { action = "start", targ = "a swamp ape", room = "Swamp Ape Enclosure", area = "Aardwolf Zoological Park", timer = 52 })
TEST.assert_equal(quest_event.normalized.timer, 52, "quest event normalized")
TEST.fireGMCP("Comm.Repop", { zone = "aylor" })
TEST.assert_equal(repop_event.normalized.zone, "aylor", "repop event normalized")
TEST.assert_equal(#comm_all, 4, "all valid Comm packets emit the generic event")
local no_comm_snapshot = TEST.request("test-consumer", "snapshot", { path = "comm.channel" })
TEST.assert_equal(no_comm_snapshot.ok, false, "Comm packets are event-only")
local comm_count_before_invalid = #comm_all
TEST.fireGMCP("Comm.Channel", { chan = 7, msg = "bad" })
TEST.fireGMCP("Comm.Quest", { action = "fail", wait = "15" })
local comm_cycle = {}
comm_cycle.self = comm_cycle
TEST.fireGMCP("Comm.Repop", { zone = "aylor", future = comm_cycle })
TEST.assert_equal(#comm_all, comm_count_before_invalid, "invalid Comm packets do not emit events")
TEST.assert_nil(TEST.tables.world["aardwolf:core:group"], "live Group data is not persisted")
TEST.assert_nil(TEST.tables.world["aardwolf:core:comm"], "transient Comm data is not persisted")

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
TEST.assert_equal(status.data.freshness.group, false, "group freshness cleared")
TEST.assert_equal(TEST.request("test-consumer", "snapshot", { path = "group" }).ok, false, "disconnect clears group snapshot")

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
TEST.assert_equal(TEST.request("test-consumer", "snapshot", { path = "group" }).ok, false, "new session cannot see old group data")
TEST.fireGMCP("Group", { groupname = "Second Session", count = 1, members = { { name = "New Tester" } } })
local second_session_group = TEST.request("test-consumer", "snapshot", { path = "group" })
TEST.assert_equal(second_session_group.data.sessionId, "session-2", "new group snapshot is scoped to the second session")
TEST.assert_equal(second_session_group.data.normalized.members[1].name, "New Tester", "second session receives independent group data")
TEST.fireGMCP("Comm.Repop", { zone = "second-session" })
TEST.assert_equal(repop_event.sessionId, "session-2", "Comm events carry the second session id")
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

table.insert(TEST.loadedPlugins, { id = "aardwolf-chat", name = "Aardwolf Chat", version = "0.4.2", enabled = true })
TEST.connected = true

local declarations = 0
on("aardwolf.core.consumer.declare", function(payload)
  if payload.consumerId ~= "aardwolf-chat" then return end
  declarations = declarations + 1
  TEST.assert_true(payload.packages.Comm, "chat declares Comm through Core")
  emit("aardwolf.core.consumer.registration", {
    consumerId = payload.consumerId,
    ok = true,
    protocol = 1,
    version = "0.4.2",
    apiVersion = "0.4.2",
  })
end)

local connected_status = true
local current_session = 1
on("aardwolf.core.request", function(payload)
  if payload.consumerId ~= "aardwolf-chat" then return end
  local data = nil
  if payload.kind == "status" then
    data = {
      protocol = 1,
      connected = connected_status,
      sessionId = "session-" .. tostring(current_session),
      session = current_session,
    }
  end
  emit("aardwolf.core.response", {
    consumerId = payload.consumerId,
    requestId = payload.requestId,
    ok = data ~= nil,
    data = data,
    code = data and nil or "unsupported",
    message = data and nil or "unsupported request",
    protocol = 1,
  })
end)

local function contains(value, pattern, label)
  TEST.assert_true(type(value) == "string" and string.find(value, pattern, 1, true) ~= nil, label)
end

local function channel(channel, text, player, sequence)
  emit("aardwolf.core.comm.channel", {
    protocol = 1,
    package = "Comm.Channel",
    group = "channel",
    normalized = { chan = channel, msg = text, player = player },
    sessionId = "session-" .. tostring(current_session),
    session = current_session,
    sequence = sequence or 1,
  })
end

init()
init()
TEST.assert_equal(declarations, 1, "duplicate init does not redeclare chat")
TEST.assert_equal(TEST.nextWidget, 2, "chat creates two managed windows")
TEST.assert_true(TEST.widgets["widget-1"].visible, "chat window starts visible")
TEST.assert_equal(TEST.widgets["widget-2"].visible, false, "settings window starts hidden")
TEST.assert_equal(TEST.widgets["widget-1"].bindings.tabTitle1, "All", "default All tab")
TEST.assert_equal(TEST.widgets["widget-1"].bindings.tabTitle2, "Tell", "default Tell tab")
TEST.assert_equal(TEST.widgets["widget-1"].bindings.tabTitle6, "Gossip", "default Gossip tab")
TEST.assert_equal(#TEST.events["aardwolf.core.comm.channel"], 1, "one Core channel subscription")
TEST.assert_equal(#TEST.sentCommands, 0, "takeover is off by default")

channel("gossip", "<script>@Rred\27[31m ANSI", "Tester", 1)
contains(TEST.widgets["widget-1"].bindings.transcript, "<script>red ANSI", "message stays literal and color codes are stripped")
TEST.assert_true(string.find(TEST.widgets["widget-1"].properties.content, "<script>@Rred", 1, true) == nil,
  "server text is never interpolated into HTML")

TEST.widgets["widget-1"].events.action({ action = "select-tab-2" })
channel("tell", "hello", "Friend", 2)
contains(TEST.widgets["widget-1"].bindings.transcript, "[tell] Friend: hello", "Tell tab receives tell")
TEST.commands.awchat.callback("tab channels gossip tell")
channel("tell", "overlap", "Friend", 3)
TEST.assert_equal(TEST.widgets["widget-1"].bindings.tabTitle6, "Gossip (1)", "overlapping inactive tab receives unread")
channel("customchan", "unknown channel", "", 4)
contains(TEST.widgets["widget-1"].bindings.tabTitle1, "(", "All preserves unknown channels")

TEST.widgets["widget-2"].events.action({ action = "tab-name-2" })
TEST.assert_equal(TEST.promptText, "awchat tab rename tell ", "settings rename prefills validated command")
TEST.commands.awchat.callback("tab rename tell Private Messages")
TEST.assert_equal(TEST.widgets["widget-1"].bindings.tabTitle2, "Private Messages", "rename updates tab")
TEST.commands.awchat.callback("tab add Trade Talk")
TEST.assert_equal(TEST.widgets["widget-2"].bindings.rowName7, "Trade Talk [trade-talk]", "add creates stable tab id")
TEST.commands.awchat.callback("tab channels trade-talk auction, barter, market")
TEST.assert_equal(TEST.widgets["widget-2"].bindings.rowChannels7, "auction, barter, market", "custom channel list applied")
TEST.commands.awchat.callback("tab move trade-talk up")
TEST.assert_equal(TEST.widgets["widget-2"].bindings.rowName6, "Trade Talk [trade-talk]", "tab reorders")
TEST.commands.awchat.callback("tab delete all")
TEST.assert_equal(TEST.widgets["widget-2"].bindings.rowName1, "All [all]", "last wildcard tab cannot be deleted")
contains(TEST.widgets["widget-2"].bindings.settingsProblem, "At least one tab", "wildcard failure is actionable")

emit("aardwolf.core.reset", { reason = "disconnect", sessionId = "session-1", session = 1 })
TEST.commands.awchat.callback("status")
contains(TEST.echoes[#TEST.echoes], "messages=0", "session-only history clears on reset")

channel("tell", "persist me", "Friend", 5)
TEST.commands.awchat.callback("history on")
TEST.advance(2000)
local history_envelope = TEST.tables.world["aardwolf:aardwolf-chat:history"]
TEST.assert_true(type(history_envelope) == "table" and history_envelope.deleted == false, "opt-in history uses Core storage")
TEST.assert_equal(history_envelope.data.messages[1].text, "persist me", "history stores reroutable message")
TEST.assert_true(TEST.tables.world["aardwolf:aardwolf-chat:preferences"].data.historyEnabled, "history preference stored")

TEST.commands.awchat.callback("takeover on")
TEST.assert_equal(TEST.sentCommands[#TEST.sentCommands], "gmcpchannels on", "takeover opt-in dispatches on")
local sends_after_first_takeover = #TEST.sentCommands
emit("aardwolf.core.session", { connected = true, sessionId = "session-1", session = 1 })
TEST.assert_equal(#TEST.sentCommands, sends_after_first_takeover, "same session does not repeat takeover")
current_session = 2
emit("aardwolf.core.session", { connected = true, sessionId = "session-2", session = 2 })
TEST.assert_equal(TEST.sentCommands[#TEST.sentCommands], "gmcpchannels on", "new session requests takeover once")
TEST.commands.awchat.callback("takeover off")
TEST.assert_equal(TEST.sentCommands[#TEST.sentCommands], "gmcpchannels off", "disabling takeover restores channel output")

cleanup()
TEST.assert_nil(TEST.widgets["widget-1"], "cleanup destroys chat window")
TEST.assert_nil(TEST.widgets["widget-2"], "cleanup destroys settings window")
TEST.assert_equal(#TEST.events["aardwolf.core.comm.channel"], 0, "cleanup releases Core channel listener")

current_session = 3
init()
TEST.assert_equal(TEST.nextWidget, 4, "chat reload recreates managed windows once")
contains(TEST.widgets["widget-3"].bindings.transcript, "persist me", "enabled history reloads from Core storage")
TEST.commands.awchat.callback("history off")
TEST.assert_true(TEST.tables.world["aardwolf:aardwolf-chat:history"].deleted, "disabling history writes owned tombstone")
cleanup()

TEST.tables.world["aardwolf:aardwolf-chat:preferences"] = {
  format = 1,
  owner = "aardwolf-chat",
  schema = 1,
  data = { malformed = true },
  deleted = false,
}
init()
TEST.assert_equal(TEST.widgets["widget-5"].bindings.tabTitle1, "All", "malformed preferences fall back to defaults")
contains(TEST.widgets["widget-6"].bindings.settingsProblem, "malformed", "malformed preferences are reported")

for index = 1, 18 do TEST.commands.awchat.callback("tab add Extra " .. tostring(index)) end
TEST.assert_equal(TEST.widgets["widget-6"].bindings.settingsSummary, "24 tabs; overlapping channel assignments are allowed.",
  "configuration accepts the 24-tab limit")
TEST.commands.awchat.callback("tab add Too Many")
contains(TEST.widgets["widget-6"].bindings.settingsProblem, "24 tabs", "configuration rejects a 25th tab")
local too_many_channels = {}
for index = 1, 65 do too_many_channels[index] = "channel" .. tostring(index) end
TEST.commands.awchat.callback("tab channels tell " .. table.concat(too_many_channels, ","))
contains(TEST.widgets["widget-6"].bindings.settingsProblem, "1 to 64", "configuration enforces channel limit")

TEST.commands.awchat.callback("reset")
emit("aardwolf.core.comm.channel", { normalized = { chan = 7, msg = "bad" } })
TEST.commands.awchat.callback("status")
contains(TEST.echoes[#TEST.echoes], "rejected=1", "malformed Core event is rejected defensively")
for index = 1, 1005 do channel("gossip", "bounded " .. tostring(index), "Tester", index) end
TEST.commands.awchat.callback("status")
contains(TEST.echoes[#TEST.echoes], "messages=1000", "history evicts oldest messages at count bound")

TEST.commands.awchat.callback("reset")
local large = string.rep("x", 1100)
for index = 1, 520 do channel("gossip", large, "Tester", index) end
TEST.commands.awchat.callback("status")
local retained_messages, retained_bytes = string.match(TEST.echoes[#TEST.echoes], "messages=(%d+), bytes=(%d+)")
TEST.assert_true(tonumber(retained_messages) < 520, "history evicts oldest messages at byte bound")
TEST.assert_true(tonumber(retained_bytes) <= 512 * 1024, "history remains within byte bound")

TEST.commands.awchat.callback("takeover on")
cleanup()
TEST.assert_equal(TEST.sentCommands[#TEST.sentCommands], "gmcpchannels off", "cleanup restores opted-in takeover")
local timer_count = 0
for _ in pairs(TEST.timers) do timer_count = timer_count + 1 end
TEST.assert_equal(timer_count, 0, "cleanup leaves no history timers")

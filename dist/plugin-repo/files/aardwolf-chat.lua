plugin = {
  id = "aardwolf-chat",
  name = "Aardwolf Chat",
  version = "0.4.2",
  author = "Sam Roberts",
  description = "Configurable receive-only Aardwolf chat tabs powered by Aardwolf Core.",
  settings = { saveState = true },
}

local core_loaded, core = pcall(require, "aardwolf-core-api")

local PROTOCOL_VERSION = 1
local PREFERENCES_SCHEMA = 1
local HISTORY_SCHEMA = 1
local MAX_TABS = 24
local MAX_CHANNELS_PER_TAB = 64
local MAX_MESSAGES = 1000
local MAX_HISTORY_BYTES = 512 * 1024
local MAX_TRANSCRIPT_BYTES = 16384
local HISTORY_SAVE_DELAY_MS = 2000

local DEFAULT_TABS = {
  { id = "all", label = "All", channels = { "*" } },
  { id = "tell", label = "Tell", channels = { "tell" } },
  { id = "group", label = "Group", channels = { "gtell" } },
  { id = "clan", label = "Clan", channels = { "clantalk", "gclan", "claninfo" } },
  { id = "newbie", label = "Newbie", channels = { "newbie", "helper", "nobletalk", "question", "answer" } },
  { id = "gossip", label = "Gossip", channels = { "gossip" } },
}

local initialized = false
local activated = false
local listeners_registered = false
local connected = false
local session_id = nil
local session_number = 0
local takeover_session = nil
local tabs = {}
local active_tab = "all"
local unread = {}
local history = {}
local history_bytes = 0
local transcript_cache = ""
local history_enabled = false
local takeover_enabled = false
local history_timer = nil
local history_dirty = false
local accepted = 0
local rejected = 0
local last_problem = nil

local function copy(value, stack)
  if type(value) ~= "table" then return value end
  stack = stack or {}
  for index = 1, #stack do
    if stack[index] == value then error("cyclic table", 0) end
  end
  stack[#stack + 1] = value
  local result = {}
  for key, item in pairs(value) do
    if type(item) == "table" then result[key] = copy(item, stack)
    elseif item ~= nil then result[key] = item end
  end
  stack[#stack] = nil
  return result
end

local function trim(value)
  if type(value) ~= "string" then return "" end
  return (string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local function dense(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then return false end
    count = count + 1
  end
  return count == #value
end

local function valid_label(value)
  return type(value) == "string" and #value >= 1 and #value <= 80
    and not string.find(value, "[%z\1-\31\127]")
end

local function valid_identifier(value)
  return type(value) == "string" and #value >= 1 and #value <= 80
    and string.match(value, "^[%w_%-]+$") ~= nil
end

local function valid_player(value)
  return type(value) == "string" and #value <= 160
    and not string.find(value, "[%z\1-\31\127]")
end

local function valid_channel(value)
  return value == "*" or valid_identifier(value)
end

local function default_tabs()
  return copy(DEFAULT_TABS)
end

local function validate_tabs(value)
  if not dense(value) or #value < 1 or #value > MAX_TABS then
    return nil, "Chat must contain between 1 and 24 tabs"
  end
  local result = {}
  local ids = {}
  local has_wildcard = false
  for index, tab in ipairs(value) do
    if type(tab) ~= "table" or not valid_identifier(tab.id) or not valid_label(tab.label)
        or not dense(tab.channels) or #tab.channels < 1 or #tab.channels > MAX_CHANNELS_PER_TAB then
      return nil, "Invalid chat tab at position " .. tostring(index)
    end
    local id = string.lower(tab.id)
    if ids[id] then return nil, "Duplicate chat tab id: " .. id end
    ids[id] = true
    local channels = {}
    local channel_set = {}
    for _, channel in ipairs(tab.channels) do
      if type(channel) ~= "string" then return nil, "Invalid channel in " .. tab.label end
      local normalized = string.lower(channel)
      if not valid_channel(normalized) then return nil, "Invalid channel in " .. tab.label end
      if channel_set[normalized] then return nil, "Duplicate channel in " .. tab.label end
      channel_set[normalized] = true
      if normalized == "*" then has_wildcard = true end
      channels[#channels + 1] = normalized
    end
    result[#result + 1] = { id = id, label = tab.label, channels = channels }
  end
  if not has_wildcard then return nil, "At least one tab must include * so unknown channels remain visible" end
  return result, nil
end

local function find_tab(id)
  if type(id) ~= "string" then return nil, nil end
  local wanted = string.lower(id)
  for index, tab in ipairs(tabs) do
    if type(tab) == "table" and tab.id == wanted then return tab, index end
  end
  return nil, nil
end

local function reset_unread()
  unread = {}
  for _, tab in ipairs(tabs) do unread[tab.id] = 0 end
end

local function message_size(message)
  return #(message.channel or "") + #(message.text or "") + #(message.player or "") + 32
end

local function trim_history()
  while #history > MAX_MESSAGES or history_bytes > MAX_HISTORY_BYTES do
    local removed = table.remove(history, 1)
    if type(removed) == "table" then history_bytes = math.max(0, history_bytes - message_size(removed)) end
  end
end

local function strip_colors(value)
  local text = type(value) == "string" and value or ""
  text = string.gsub(text, "\27%[[0-9;]*m", "")
  text = string.gsub(text, "@x%d%d%d", "")
  text = string.gsub(text, "@X%x%x%x%x%x%x", "")
  text = string.gsub(text, "@[bBcCrRmMgGwWyYkKD%-]", "")
  text = string.gsub(text, "@@", "@")
  text = string.gsub(text, "%$x%d%d%d", "")
  text = string.gsub(text, "%$X%x%x%x%x%x%x", "")
  text = string.gsub(text, "%$[bBcCrRmMgGwWyYkKD%-]", "")
  text = string.gsub(text, "%$%$", "$")
  text = string.gsub(text, "[%z\1-\31\127]", " ")
  return text
end

local function normalize_message(payload)
  if type(payload) ~= "table" or type(payload.normalized) ~= "table" then
    return nil, "Missing normalized comm.channel payload"
  end
  local value = payload.normalized
  if not valid_identifier(value.chan) or type(value.msg) ~= "string" or #value.msg > 65536
      or string.find(value.msg, "%z") or (value.player ~= nil and not valid_player(value.player)) then
    return nil, "Malformed comm.channel payload"
  end
  local message = {
    channel = string.lower(value.chan),
    text = strip_colors(value.msg),
    player = value.player or "",
    sessionId = payload.sessionId,
    session = payload.session,
    sequence = payload.sequence,
  }
  message.bytes = message_size(message)
  return message, nil
end

local function tab_matches(tab, channel)
  for _, candidate in ipairs(tab.channels or {}) do
    if candidate == "*" or candidate == channel then return true end
  end
  return false
end

local function format_message(message)
  local prefix = "[" .. message.channel .. "] "
  if message.player ~= "" then prefix = prefix .. message.player .. ": " end
  return prefix .. message.text
end

local function display_line(message)
  local line = format_message(message)
  if #line <= MAX_TRANSCRIPT_BYTES then return line end
  return "[" .. message.channel .. "] [message omitted: exceeds display limit]"
end

local function transcript_for(tab)
  if not tab then return "No chat tab is selected." end
  local selected = {}
  local total = 0
  for index = #history, 1, -1 do
    local message = history[index]
    if type(message) == "table" and tab_matches(tab, message.channel) then
      local line = display_line(message)
      local addition = #line + (#selected > 0 and 1 or 0)
      if total + addition > MAX_TRANSCRIPT_BYTES then break end
      table.insert(selected, 1, line)
      total = total + addition
    end
  end
  if #selected == 0 then return "No chat messages for this tab." end
  return table.concat(selected, "\n")
end

local function rebuild_transcript()
  transcript_cache = transcript_for(find_tab(active_tab))
  if transcript_cache == "No chat messages for this tab." or transcript_cache == "No chat tab is selected." then
    transcript_cache = ""
  end
end

local function append_active_message(message)
  local tab = find_tab(active_tab)
  if not tab or not tab_matches(tab, message.channel) then return end
  local line = display_line(message)
  if transcript_cache == "" then transcript_cache = line else transcript_cache = transcript_cache .. "\n" .. line end
  while #transcript_cache > MAX_TRANSCRIPT_BYTES do
    local newline = string.find(transcript_cache, "\n", 1, true)
    if not newline then
      transcript_cache = string.sub(transcript_cache, #transcript_cache - MAX_TRANSCRIPT_BYTES + 1)
      break
    end
    transcript_cache = string.sub(transcript_cache, newline + 1)
  end
end

local function main_bindings()
  local bindings = {
    transcript = transcript_cache ~= "" and transcript_cache or "No chat messages for this tab.",
    connection = connected and "Connected" or "Waiting for Aardwolf Core connection",
    historyMode = history_enabled and "History: saved per world" or "History: session only",
    takeoverMode = takeover_enabled and "GMCP-only: requested" or "GMCP-only: off",
    problem = last_problem or "",
  }
  for index = 1, MAX_TABS do
    local tab = tabs[index]
    if type(tab) == "table" then
      local count = unread[tab.id] or 0
      bindings["tabTitle" .. tostring(index)] = tab.label .. (count > 0 and " (" .. tostring(count) .. ")" or "")
      bindings["tabDisplay" .. tostring(index)] = "inline-block"
      bindings["tabSelected" .. tostring(index)] = tab.id == active_tab and "true" or "false"
    else
      bindings["tabTitle" .. tostring(index)] = ""
      bindings["tabDisplay" .. tostring(index)] = "none"
      bindings["tabSelected" .. tostring(index)] = "false"
    end
  end
  return bindings
end

local function settings_bindings()
  local bindings = {
    settingsSummary = tostring(#tabs) .. " tabs; overlapping channel assignments are allowed.",
    historySetting = history_enabled and "Persistent history is ON" or "Persistent history is OFF",
    takeoverSetting = takeover_enabled and "GMCP-only takeover is ON" or "GMCP-only takeover is OFF",
    settingsProblem = last_problem or "",
  }
  for index = 1, MAX_TABS do
    local tab = tabs[index]
    if type(tab) == "table" then
      bindings["rowDisplay" .. tostring(index)] = "grid"
      bindings["rowName" .. tostring(index)] = tab.label .. " [" .. tab.id .. "]"
      bindings["rowChannels" .. tostring(index)] = table.concat(tab.channels, ", ")
    else
      bindings["rowDisplay" .. tostring(index)] = "none"
      bindings["rowName" .. tostring(index)] = ""
      bindings["rowChannels" .. tostring(index)] = ""
    end
  end
  return bindings
end

local function render_main()
  if activated then
    local ok, problem = core.ui.bind("chat", main_bindings())
    if not ok then last_problem = problem and problem.message or "Chat window update failed" end
  end
end

local function render_settings()
  if activated then
    local ok, problem = core.ui.bind("chat-settings", settings_bindings())
    if not ok then last_problem = problem and problem.message or "Settings window update failed" end
  end
end

local function render_all()
  render_main()
  render_settings()
end

local function cancel_history_timer()
  if history_timer and history_timer ~= "" then pcall(removeTimer, history_timer) end
  history_timer = nil
end

local function persisted_messages()
  local result = {}
  for _, message in ipairs(history) do
    if type(message) == "table" then
      result[#result + 1] = {
        channel = message.channel,
        text = message.text,
        player = message.player,
        sessionId = message.sessionId,
        session = message.session,
        sequence = message.sequence,
      }
    end
  end
  return result
end

local function persist_history()
  cancel_history_timer()
  if not history_enabled or not history_dirty then return true end
  local ok, problem = core.storage.save("history", HISTORY_SCHEMA, { messages = persisted_messages() }, "world")
  if not ok then
    last_problem = problem and problem.message or "Chat history could not be saved"
    return nil
  end
  history_dirty = false
  return true
end

local function schedule_history_save()
  if not history_enabled then return end
  history_dirty = true
  if history_timer and history_timer ~= "" then return end
  local ok, timer = pcall(addTimer, HISTORY_SAVE_DELAY_MS, persist_history, false)
  if ok and type(timer) == "string" and timer ~= "" then
    history_timer = timer
  else
    persist_history()
  end
end

local function save_preferences()
  local ok, problem = core.storage.save("preferences", PREFERENCES_SCHEMA, {
    tabs = copy(tabs),
    activeTab = active_tab,
    historyEnabled = history_enabled,
    takeoverEnabled = takeover_enabled,
  }, "world")
  if not ok then
    last_problem = problem and problem.message or "Chat preferences could not be saved"
    return nil
  end
  return true
end

local function parse_channels(value)
  if type(value) ~= "string" then return nil, "Channels must be comma-separated" end
  local result = {}
  local seen = {}
  for item in string.gmatch(value .. ",", "(.-),") do
    local channel = string.lower(trim(item))
    if channel ~= "" then
      if not valid_channel(channel) then return nil, "Invalid channel: " .. channel end
      if seen[channel] then return nil, "Duplicate channel: " .. channel end
      seen[channel] = true
      result[#result + 1] = channel
    end
  end
  if #result < 1 or #result > MAX_CHANNELS_PER_TAB then return nil, "A tab needs 1 to 64 channels" end
  return result, nil
end

local function unique_id(label)
  local base = string.lower(label)
  base = string.gsub(base, "[^%w_%-]", "-")
  base = string.gsub(base, "%-+", "-")
  base = string.gsub(base, "^%-", "")
  base = string.gsub(base, "%-$", "")
  if base == "" then base = "tab" end
  base = string.sub(base, 1, 64)
  local candidate = base
  local suffix = 2
  while find_tab(candidate) do
    candidate = string.sub(base, 1, 60) .. "-" .. tostring(suffix)
    suffix = suffix + 1
  end
  return candidate
end

local function apply_tabs(candidate)
  local validated, problem = validate_tabs(candidate)
  if not validated then return nil, problem end
  tabs = validated
  if not find_tab(active_tab) then active_tab = tabs[1].id end
  reset_unread()
  rebuild_transcript()
  last_problem = nil
  if not save_preferences() then
    render_all()
    return nil, last_problem
  end
  render_all()
  return true, nil
end

local function add_tab(label)
  label = trim(label)
  if not valid_label(label) then return nil, "Tab labels must contain 1 to 80 printable characters" end
  if #tabs >= MAX_TABS then return nil, "Chat already has 24 tabs" end
  local candidate = copy(tabs)
  candidate[#candidate + 1] = { id = unique_id(label), label = label, channels = { "*" } }
  return apply_tabs(candidate)
end

local function rename_tab(id, label)
  label = trim(label)
  if not valid_label(label) then return nil, "Tab labels must contain 1 to 80 printable characters" end
  local _, index = find_tab(id)
  if not index then return nil, "Unknown tab: " .. tostring(id) end
  local candidate = copy(tabs)
  candidate[index].label = label
  return apply_tabs(candidate)
end

local function set_tab_channels(id, value)
  local channels, problem = parse_channels(value)
  if not channels then return nil, problem end
  local _, index = find_tab(id)
  if not index then return nil, "Unknown tab: " .. tostring(id) end
  local candidate = copy(tabs)
  candidate[index].channels = channels
  return apply_tabs(candidate)
end

local function move_tab(id, direction)
  local _, index = find_tab(id)
  if not index then return nil, "Unknown tab: " .. tostring(id) end
  local destination = direction == "up" and index - 1 or direction == "down" and index + 1 or nil
  if not destination then return nil, "Direction must be up or down" end
  if destination < 1 or destination > #tabs then return true, nil end
  local candidate = copy(tabs)
  candidate[index], candidate[destination] = candidate[destination], candidate[index]
  return apply_tabs(candidate)
end

local function delete_tab(id)
  local _, index = find_tab(id)
  if not index then return nil, "Unknown tab: " .. tostring(id) end
  if #tabs <= 1 then return nil, "Chat must keep at least one tab" end
  local candidate = copy(tabs)
  table.remove(candidate, index)
  return apply_tabs(candidate)
end

local function session_key()
  return tostring(session_number) .. ":" .. tostring(session_id or "")
end

local function dispatch_control(command)
  local ok, result = pcall(send, command)
  if not ok or result == false then
    last_problem = "Could not dispatch " .. command
    return nil
  end
  return true
end

local function request_takeover()
  if not takeover_enabled or not connected then return end
  local key = session_key()
  if takeover_session == key then return end
  takeover_session = key
  dispatch_control("gmcpchannels on")
end

local function restore_channels()
  if connected and takeover_session ~= nil then dispatch_control("gmcpchannels off") end
  takeover_session = nil
end

local function set_history_enabled(enabled)
  if history_enabled == enabled then return true end
  last_problem = nil
  history_enabled = enabled
  if enabled then
    history_dirty = true
    schedule_history_save()
  else
    cancel_history_timer()
    history_dirty = false
    local ok, problem = core.storage.delete("history", "world")
    if not ok then last_problem = problem and problem.message or "Stored history could not be removed" end
  end
  save_preferences()
  render_all()
  return true
end

local function set_takeover_enabled(enabled)
  if takeover_enabled == enabled then return true end
  last_problem = nil
  if not enabled then restore_channels() end
  takeover_enabled = enabled
  save_preferences()
  if enabled then request_takeover() end
  render_all()
  return true
end

local function select_tab(index)
  local tab = tabs[index]
  if type(tab) ~= "table" then return end
  active_tab = tab.id
  unread[tab.id] = 0
  rebuild_transcript()
  save_preferences()
  render_main()
end

local function receive_channel(payload)
  local message, problem = normalize_message(payload)
  if not message then
    rejected = rejected + 1
    last_problem = problem
    render_all()
    return
  end
  accepted = accepted + 1
  history[#history + 1] = message
  history_bytes = history_bytes + message.bytes
  trim_history()
  append_active_message(message)
  for _, tab in ipairs(tabs) do
    if tab_matches(tab, message.channel) and tab.id ~= active_tab then
      unread[tab.id] = (unread[tab.id] or 0) + 1
    end
  end
  schedule_history_save()
  render_main()
end

local function reset_for_session()
  reset_unread()
  if not history_enabled then
    history = {}
    history_bytes = 0
  end
  rebuild_transcript()
  render_all()
end

local function handle_session(payload)
  if type(payload) ~= "table" or type(payload.connected) ~= "boolean" then return end
  connected = payload.connected
  session_id = payload.sessionId
  session_number = type(payload.session) == "number" and payload.session or session_number
  if connected then request_takeover() else takeover_session = nil end
  render_main()
end

local function valid_stored_message(value)
  return type(value) == "table" and valid_identifier(value.channel)
    and type(value.text) == "string" and #value.text <= 65536 and not string.find(value.text, "%z")
    and valid_player(value.player)
end

local function load_history()
  if not history_enabled then return end
  local stored, problem = core.storage.load("history", HISTORY_SCHEMA, "world")
  if problem then last_problem = problem.message; return end
  if stored == nil then return end
  if type(stored) ~= "table" or not dense(stored.messages) then
    last_problem = "Stored chat history is malformed"
    return
  end
  local loaded = {}
  local bytes = 0
  for _, item in ipairs(stored.messages) do
    if not valid_stored_message(item) then
      last_problem = "Stored chat history contains an invalid message"
      return
    end
    local message = copy(item)
    message.channel = string.lower(message.channel)
    message.bytes = message_size(message)
    loaded[#loaded + 1] = message
    bytes = bytes + message.bytes
  end
  history = loaded
  history_bytes = bytes
  trim_history()
  rebuild_transcript()
end

local function load_preferences()
  tabs = default_tabs()
  active_tab = "all"
  history_enabled = false
  takeover_enabled = false
  local stored, problem = core.storage.load("preferences", PREFERENCES_SCHEMA, "world")
  if problem then last_problem = problem.message; reset_unread(); return end
  if stored == nil then reset_unread(); return end
  if type(stored) ~= "table" or type(stored.historyEnabled) ~= "boolean"
      or type(stored.takeoverEnabled) ~= "boolean" then
    last_problem = "Stored chat preferences are malformed"
    reset_unread()
    return
  end
  local validated, validation_problem = validate_tabs(stored.tabs)
  if not validated then
    last_problem = validation_problem
    reset_unread()
    return
  end
  tabs = validated
  history_enabled = stored.historyEnabled
  takeover_enabled = stored.takeoverEnabled
  if type(stored.activeTab) == "string" and find_tab(stored.activeTab) then active_tab = string.lower(stored.activeTab) end
  reset_unread()
end

local function main_content()
  local buttons = {}
  for index = 1, MAX_TABS do
    buttons[#buttons + 1] = string.format(
      '<button class="aw-button aw-chat-tab" type="button" data-mud-action="select-tab-%d" data-mud-bind="tabTitle%d" data-mud-bind-style="display:tabDisplay%d" data-mud-bind-attr="aria-pressed:tabSelected%d">Tab</button>',
      index, index, index, index)
  end
  return [[
    <section class="aw-section aw-chat-shell">
      <div class="aw-chat-tabs" role="tablist" aria-label="Aardwolf chat tabs">]] .. table.concat(buttons) .. [[</div>
      <pre class="aw-chat-log" data-mud-bind="transcript">No chat messages.</pre>
      <div class="aw-chat-footer"><span data-mud-bind="connection">Waiting</span><span data-mud-bind="historyMode">History: session only</span><span data-mud-bind="takeoverMode">GMCP-only: off</span></div>
      <p class="aw-error" data-mud-bind="problem"></p>
      <div class="aw-toolbar"><button class="aw-button" type="button" data-mud-action="open-settings">Settings</button><button class="aw-button" type="button" data-mud-action="hide-chat">Hide</button></div>
    </section>
  ]]
end

local function settings_content()
  local rows = {}
  for index = 1, MAX_TABS do
    rows[#rows + 1] = string.format([[
      <div class="aw-chat-config-row" data-mud-bind-style="display:rowDisplay%d">
        <div><strong data-mud-bind="rowName%d">Tab</strong><div class="aw-muted" data-mud-bind="rowChannels%d">*</div></div>
        <div class="aw-chat-row-actions"><button class="aw-button" type="button" data-mud-action="tab-up-%d" aria-label="Move tab earlier">↑</button><button class="aw-button" type="button" data-mud-action="tab-down-%d" aria-label="Move tab later">↓</button><button class="aw-button" type="button" data-mud-action="tab-name-%d">Rename</button><button class="aw-button" type="button" data-mud-action="tab-channels-%d">Channels</button><button class="aw-button aw-button--danger" type="button" data-mud-action="tab-delete-%d">Delete</button></div>
      </div>]], index, index, index, index, index, index, index, index)
  end
  return [[
    <section class="aw-section">
      <h1 class="aw-title">Aardwolf Chat Settings</h1>
      <p data-mud-bind="settingsSummary">Configure tabs and channels.</p>
      <p class="aw-muted">Rename and channel buttons prefill a validated awchat command in the prompt. Channel lists are comma-separated; * matches every channel.</p>
      <div class="aw-toolbar"><button class="aw-button aw-button--primary" type="button" data-mud-action="tab-add">Add tab</button><button class="aw-button" type="button" data-mud-action="toggle-history" data-mud-bind="historySetting">Persistent history is OFF</button><button class="aw-button" type="button" data-mud-action="toggle-takeover" data-mud-bind="takeoverSetting">GMCP-only takeover is OFF</button><button class="aw-button aw-button--danger" type="button" data-mud-action="reset-chat">Reset</button><button class="aw-button" type="button" data-mud-action="hide-settings">Hide</button></div>
      <p class="aw-error" data-mud-bind="settingsProblem"></p>
      <div>]] .. table.concat(rows) .. [[</div>
    </section>
  ]]
end

local CHAT_CSS = [[
  .aw-chat-shell{display:flex;flex-direction:column;height:100%;min-height:0}.aw-chat-tabs{display:flex;gap:6px;overflow-x:auto;padding-bottom:8px}.aw-chat-tab{white-space:nowrap}.aw-chat-tab[aria-pressed="true"]{color:#111827;background:var(--aw-primary);border-color:var(--aw-primary)}.aw-chat-log{flex:1;min-height:180px;margin:0;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere;padding:12px;background:#050914;border:1px solid var(--aw-border);border-radius:6px;color:var(--aw-text);font:13px ui-monospace,SFMono-Regular,Menlo,monospace}.aw-chat-footer{display:flex;flex-wrap:wrap;gap:8px 16px;margin-top:8px;color:var(--aw-muted);font-size:12px}
]]

local SETTINGS_CSS = [[
  .aw-chat-config-row{grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:center;padding:10px 0;border-bottom:1px solid var(--aw-border)}.aw-chat-row-actions{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:6px}.aw-chat-row-actions .aw-button{min-height:32px;padding:5px 8px}
]]

local function create_windows()
  local chat, chat_problem = core.ui.create({
    name = "chat", title = "Aardwolf Chat", type = "html", content = main_content(), css = CHAT_CSS,
    position = { x = 120, y = 120 }, size = { width = 720, height = 520 }, visible = true,
  })
  if not chat then return nil, chat_problem end
  local settings, settings_problem = core.ui.create({
    name = "chat-settings", title = "Aardwolf Chat Settings", type = "html",
    content = settings_content(), css = SETTINGS_CSS,
    position = { x = 180, y = 150 }, size = { width = 840, height = 620 }, visible = false,
  })
  if not settings then core.ui.destroy("chat"); return nil, settings_problem end
  return true, nil
end

local function reset_chat()
  if takeover_enabled then restore_channels() end
  cancel_history_timer()
  tabs = default_tabs()
  active_tab = "all"
  history = {}
  history_bytes = 0
  transcript_cache = ""
  history_enabled = false
  takeover_enabled = false
  history_dirty = false
  accepted = 0
  rejected = 0
  last_problem = nil
  reset_unread()
  local deleted, delete_problem = core.storage.delete("history", "world")
  if not deleted then last_problem = delete_problem and delete_problem.message or "Stored history could not be removed" end
  save_preferences()
  render_all()
end

local function tab_action(action, prefix)
  local value = string.match(action, "^" .. prefix .. "(%d+)$")
  return value and tonumber(value) or nil
end

local function handle_main_action(event)
  local action = type(event) == "table" and event.action or nil
  if type(action) ~= "string" then return end
  local index = tab_action(action, "select%-tab%-")
  if index then select_tab(index)
  elseif action == "open-settings" then core.ui.show("chat-settings")
  elseif action == "hide-chat" then core.ui.hide("chat") end
end

local function report_result(ok, problem)
  if not ok then last_problem = problem; echo("Aardwolf Chat: " .. tostring(problem)) end
  render_all()
end

local function handle_settings_action(event)
  local action = type(event) == "table" and event.action or nil
  if type(action) ~= "string" then return end
  local index = tab_action(action, "tab%-up%-")
  if index and tabs[index] then report_result(move_tab(tabs[index].id, "up")); return end
  index = tab_action(action, "tab%-down%-")
  if index and tabs[index] then report_result(move_tab(tabs[index].id, "down")); return end
  index = tab_action(action, "tab%-delete%-")
  if index and tabs[index] then report_result(delete_tab(tabs[index].id)); return end
  index = tab_action(action, "tab%-name%-")
  if index and tabs[index] then focusPrompt("awchat tab rename " .. tabs[index].id .. " "); return end
  index = tab_action(action, "tab%-channels%-")
  if index and tabs[index] then focusPrompt("awchat tab channels " .. tabs[index].id .. " "); return end
  if action == "tab-add" then focusPrompt("awchat tab add ")
  elseif action == "toggle-history" then set_history_enabled(not history_enabled)
  elseif action == "toggle-takeover" then set_takeover_enabled(not takeover_enabled)
  elseif action == "reset-chat" then reset_chat()
  elseif action == "hide-settings" then core.ui.hide("chat-settings") end
end

local function core_options()
  return {
    pluginId = plugin.id,
    minProtocol = PROTOCOL_VERSION,
    packages = { Comm = true },
    on = on,
    off = off,
    emit = emit,
    getLoadedPlugins = getLoadedPlugins,
    saveTable = saveTable,
    loadTable = loadTable,
    ui = {
      createWidget = createWidget,
      setWidgetProperty = setWidgetProperty,
      showWidget = showWidget,
      hideWidget = hideWidget,
      destroyWidget = destroyWidget,
      setBoundValues = setBoundValues,
      registerWidgetEvent = registerWidgetEvent,
      unregisterWidgetEvent = unregisterWidgetEvent,
      widgetInfo = widgetInfo,
      focusPrompt = focusPrompt,
    },
  }
end

local function finish_activation()
  if activated then return true, nil end
  load_preferences()
  load_history()
  rebuild_transcript()
  local windows_ok, problem = create_windows()
  if not windows_ok then return nil, problem end
  activated = true
  core.ui.on("chat", "action", handle_main_action)
  core.ui.on("chat-settings", "action", handle_settings_action)
  local status = core.status()
  if type(status) == "table" then handle_session(status) end
  render_all()
  return true, nil
end

local function register_core_listeners()
  if listeners_registered then return end
  listeners_registered = true
  core.on("comm.channel", receive_channel)
  core.on("reset", function() reset_for_session() end)
  core.on("session", handle_session)
  core.on("ready", function()
    if not activated then
      local ok = core.init(core_options())
      if ok then
        local activated_ok, problem = finish_activation()
        if not activated_ok then last_problem = problem and problem.message or "Chat windows could not be created" end
      end
    end
  end)
end

local function activate()
  local ok, problem = core.init(core_options())
  register_core_listeners()
  if not ok then return nil, problem end
  return finish_activation()
end

local function tab_command(command_text)
  local operation, rest = string.match(command_text, "^(%S+)%s*(.-)%s*$")
  operation = operation and string.lower(operation) or ""
  if operation == "add" then return add_tab(rest) end
  local id, value = string.match(rest, "^(%S+)%s*(.-)%s*$")
  if not id or id == "" then return nil, "Tab command requires a tab id" end
  if operation == "rename" then return rename_tab(id, value) end
  if operation == "channels" then return set_tab_channels(id, value) end
  if operation == "move" then return move_tab(id, string.lower(value)) end
  if operation == "delete" then return delete_tab(id) end
  return nil, "Usage: awchat tab add <label> | rename <id> <label> | channels <id> <list> | move <id> up|down | delete <id>"
end

local function command(command_text)
  local input = trim(command_text or "")
  local action, rest = string.match(input, "^(%S+)%s*(.-)%s*$")
  action = action and string.lower(action) or ""
  local normalized_rest = string.lower(rest or "")
  if action == "" or action == "show" then
    if activated then core.ui.show("chat") else echo("Aardwolf Chat requires Aardwolf Core and aardwolf-core-api.") end
  elseif action == "hide" then
    if activated then core.ui.hide("chat") end
  elseif action == "settings" then
    if activated then core.ui.show("chat-settings") end
  elseif action == "status" then
    echo(string.format("Aardwolf Chat: %s, tabs=%d, messages=%d, bytes=%d, accepted=%d, rejected=%d, history=%s, takeover=%s",
      connected and "connected" or "disconnected", #tabs, #history, history_bytes, accepted, rejected,
      history_enabled and "on" or "off", takeover_enabled and "on" or "off"))
  elseif action == "reset" then
    if activated then reset_chat() end
  elseif action == "history" and (normalized_rest == "on" or normalized_rest == "off") then
    if activated then set_history_enabled(normalized_rest == "on") end
  elseif action == "takeover" and (normalized_rest == "on" or normalized_rest == "off") then
    if activated then set_takeover_enabled(normalized_rest == "on") end
  elseif action == "tab" then
    if activated then report_result(tab_command(rest)) end
  else
    echo("Usage: awchat [show|hide|settings|status|reset|history on|off|takeover on|off|tab ...]")
  end
end

function init()
  if initialized then return end
  initialized = true
  registerCommand("awchat", command, "Show or configure receive-only Aardwolf GMCP chat")
  if not core_loaded or type(core) ~= "table" then
    echo("Aardwolf Chat requires the aardwolf-core-api library.")
    return
  end
  local ok, problem = activate()
  if not ok then
    last_problem = problem and problem.message or "Aardwolf Core is unavailable"
    echo("Aardwolf Chat: " .. last_problem)
  end
end

function cleanup()
  if takeover_enabled then restore_channels() end
  persist_history()
  cancel_history_timer()
  if core_loaded and type(core) == "table" then core.cleanup() end
  initialized = false
  activated = false
  listeners_registered = false
  connected = false
  session_id = nil
  session_number = 0
  takeover_session = nil
  tabs = {}
  active_tab = "all"
  unread = {}
  history = {}
  history_bytes = 0
  transcript_cache = ""
  history_enabled = false
  takeover_enabled = false
  history_dirty = false
  accepted = 0
  rejected = 0
  last_problem = nil
end

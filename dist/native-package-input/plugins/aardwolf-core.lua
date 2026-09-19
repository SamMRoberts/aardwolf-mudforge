plugin = {
  id = "aardwolf-core",
  name = "Aardwolf Core",
  version = "0.2.1",
  author = "Sam Roberts",
  description = "Shared Aardwolf data, managed windows, visual design, and diagnostics.",
  settings = { saveState = true },
}

local PROTOCOL_VERSION = 1
local API_VERSION = "0.2.1"
local UI_VERSION = 1
local SETTINGS_TABLE = "aardwolf:core:settings"
local MAX_DIAGNOSTICS = 50
local NEGOTIATION_DELAY_MS = 150
local RETRY_DELAY_MS = 1000
local MIN_NEGOTIATION_GAP_MS = 1000

local EVENT_READY = "aardwolf.core.ready"
local EVENT_DISCOVER = "aardwolf.core.consumer.discover"
local EVENT_DECLARE = "aardwolf.core.consumer.declare"
local EVENT_WITHDRAW = "aardwolf.core.consumer.withdraw"
local EVENT_REGISTRATION = "aardwolf.core.consumer.registration"
local EVENT_REQUEST = "aardwolf.core.request"
local EVENT_RESPONSE = "aardwolf.core.response"
local EVENT_SESSION = "aardwolf.core.session"
local EVENT_RESET = "aardwolf.core.reset"
local EVENT_DIAGNOSTIC = "aardwolf.core.diagnostic"
local EVENT_UI_DECLARE = "aardwolf.core.ui.window.declare"
local EVENT_UI_WITHDRAW = "aardwolf.core.ui.window.withdraw"
local EVENT_UI_STATE = "aardwolf.core.ui.window.state"
local EVENT_UI_COMMAND = "aardwolf.core.ui.window.command"
local EVENT_UI_QUERY = "aardwolf.core.ui.window.query"

local ui_library_loaded, core_api = pcall(require, "aardwolf-core-api")

local PACKAGE_ORDER = { "Core", "Char", "Comm", "Room", "Group" }
local ALLOWED_PACKAGES = {
  Core = true,
  Char = true,
  Comm = true,
  Room = true,
  Group = true,
}
local BASELINE_PACKAGES = { Core = true, Char = true, Room = true }

local CHAR_GROUPS = { "base", "vitals", "stats", "maxstats", "status", "worth" }
local CHAR_PACKAGES = {
  base = "Char.Base",
  vitals = "Char.Vitals",
  stats = "Char.Stats",
  maxstats = "Char.MaxStats",
  status = "Char.Status",
  worth = "Char.Worth",
}
local CHAR_SCHEMAS = {
  base = {
    name = "string", ["class"] = "string", subclass = "string", race = "string",
    clan = "string", pretitle = "string", classes = "classes", perlevel = "integer",
    tier = "integer", remorts = "integer", redos = "integer", level = "integer",
    pups = "integer", totpups = "integer",
  },
  vitals = { hp = "integer", mana = "integer", moves = "integer" },
  stats = {
    str = "integer", int = "integer", wis = "integer", dex = "integer",
    con = "integer", luck = "integer", hr = "integer", dr = "integer",
    saves = "integer",
  },
  maxstats = {
    maxhp = "integer", maxmana = "integer", maxmoves = "integer",
    maxstr = "integer", maxint = "integer", maxwis = "integer",
    maxdex = "integer", maxcon = "integer", maxluck = "integer",
  },
  status = {
    level = "integer", tnl = "integer", hunger = "integer", thirst = "integer",
    align = "integer", state = "integer", pos = "string", enemy = "string",
    enemypct = "integer",
  },
  worth = {
    gold = "integer", bank = "integer", qp = "integer", tp = "integer",
    trains = "integer", pracs = "integer", qpearned = "integer",
  },
}

local initialized = false
local connected = false
local session_id = nil
local session_number = 0
local update_sequence = 0
local declarations = {}
local negotiated_packages = {}
local last_supports_key = nil
local last_negotiation_ms = -1000000
local negotiation_timer = nil
local retry_used = false
local bootstrapped = false
local widget = nil
local log_level = "info"
local diagnostics = {}
local subscriptions = {}
local ui_windows = {}
local ui_window_order = {}
local ui_window_actions = {}
local char_state = {}
local room_state = nil
local freshness = { char = {}, room = false }
local counters = {
  accepted = 0,
  rejected = 0,
  negotiations = 0,
  negotiationFailures = 0,
  refreshes = 0,
}

local function now_ms()
  return math.floor(os.clock() * 1000)
end

local function finite_integer(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value % 1 == 0
    and math.abs(value) <= 9007199254740991
end

local function valid_string(value, limit)
  return type(value) == "string"
    and #value <= (limit or 4096)
    and not string.find(value, "[%z\1-\31\127]")
end

local function valid_classes(value)
  if not valid_string(value, 32) or not string.match(value, "^[0-6]*$") then return false end
  local seen = {}
  for id in string.gmatch(value, ".") do
    if seen[id] then return false end
    seen[id] = true
  end
  return true
end

local function stack_contains(stack, value)
  -- MudForge tables have reference identity and no metatables. Keep ancestors
  -- in an array because plugin scope does not expose the rawequal builtin.
  for index = 1, #stack do
    if stack[index] == value then return true end
  end
  return false
end

local function copy(value, stack)
  if type(value) ~= "table" then return value end
  stack = stack or {}
  if stack_contains(stack, value) then error("cyclic table", 0) end
  stack[#stack + 1] = value
  local result = {}
  for key, item in pairs(value) do
    if type(item) == "table" then
      result[key] = copy(item, stack)
    elseif item ~= nil then
      result[key] = item
    end
  end
  stack[#stack] = nil
  return result
end

local function bounded_copy(value, depth, budget, stack)
  local kind = type(value)
  if kind == "nil" or kind == "boolean" then return value end
  if kind == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("non-finite number", 0)
    end
    return value
  end
  if kind == "string" then
    budget.bytes = budget.bytes + #value
    if #value > 16384 or budget.bytes > 65536 then error("string limit exceeded", 0) end
    return value
  end
  if kind ~= "table" then error("unsupported value type: " .. kind, 0) end
  if depth > 8 then error("nesting limit exceeded", 0) end
  if stack_contains(stack, value) then error("cyclic table", 0) end
  stack[#stack + 1] = value
  local result = {}
  for key, item in pairs(value) do
    budget.items = budget.items + 1
    if budget.items > 512 then error("item limit exceeded", 0) end
    local key_kind = type(key)
    if key_kind ~= "string" and key_kind ~= "number" then error("unsupported key type", 0) end
    if key_kind == "string" and #key > 128 then error("key limit exceeded", 0) end
    if item ~= nil then result[key] = bounded_copy(item, depth + 1, budget, stack) end
  end
  stack[#stack] = nil
  return result
end

local function safe_raw(value)
  return bounded_copy(value, 1, { items = 0, bytes = 0 }, {})
end

local function package_list_string(packages)
  local out = {}
  for _, name in ipairs(PACKAGE_ORDER) do
    if packages[name] then out[#out + 1] = name end
  end
  return table.concat(out, ", ")
end

local function emit_copy(name, payload)
  emit(name, copy(payload))
end

local function ui_window_key(consumer_id, name)
  return consumer_id .. ":" .. name
end

local function rebuild_ui_order()
  ui_window_order = {}
  for key in pairs(ui_windows) do ui_window_order[#ui_window_order + 1] = key end
  table.sort(ui_window_order)
end

local function control_center_body()
  ui_window_actions = {}
  local rows = {}
  for index, key in ipairs(ui_window_order) do
    local show_action = "window-show-" .. tostring(index)
    local hide_action = "window-hide-" .. tostring(index)
    ui_window_actions[show_action] = { key = key, action = "show" }
    ui_window_actions[hide_action] = { key = key, action = "hide" }
    rows[#rows + 1] = string.format([[
      <div class="aw-window-row">
        <div><div><strong data-mud-bind="windowTitle%d">Managed window</strong></div>
          <div class="aw-window-meta"><span data-mud-bind="windowOwner%d">consumer</span> · <span data-mud-bind="windowType%d">type</span> · <span data-mud-bind="windowVisible%d">hidden</span></div></div>
        <div class="aw-toolbar"><button class="aw-button" type="button" data-mud-action="%s">Show</button><button class="aw-button" type="button" data-mud-action="%s">Hide</button></div>
      </div>]], index, index, index, index, show_action, hide_action)
  end
  if #rows == 0 then rows[1] = [[<p class="aw-muted">No associated plugin windows are registered.</p>]] end
  return [[
    <h1 class="aw-title">Aardwolf Core</h1>
    <section class="aw-section"><div class="aw-grid">
      <div class="aw-label">Core / API</div><div class="aw-value"><span data-mud-bind="version">?</span> / <span data-mud-bind="apiVersion">?</span></div>
      <div class="aw-label">Protocol</div><div class="aw-value" data-mud-bind="protocol">?</div>
      <div class="aw-label">Connection</div><div class="aw-value"><span data-mud-bind="connection">Disconnected</span> · session <span data-mud-bind="session">none</span></div>
      <div class="aw-label">Packages</div><div class="aw-value" data-mud-bind="packages">none</div>
      <div class="aw-label">Consumers</div><div class="aw-value" data-mud-bind="consumers">none</div>
      <div class="aw-label">Fresh Char groups</div><div class="aw-value" data-mud-bind="charFresh">none</div>
      <div class="aw-label">Fresh Room</div><div class="aw-value" data-mud-bind="roomFresh">no</div>
      <div class="aw-label">Counters</div><div class="aw-value" data-mud-bind="counters">none</div>
      <div class="aw-label">Log level</div><div class="aw-value" data-mud-bind="logLevel">info</div>
    </div></section>
    <h2 class="aw-heading">Managed windows</h2>
    <section class="aw-section">]] .. table.concat(rows) .. [[
      <div class="aw-toolbar"><button class="aw-button" type="button" data-mud-action="windows-refresh">Refresh</button><button class="aw-button" type="button" data-mud-action="windows-show-all">Show all</button><button class="aw-button" type="button" data-mud-action="windows-hide-all">Hide all</button></div>
    </section>
    <h2 class="aw-heading">Appearance</h2>
    <section class="aw-section"><p class="aw-muted">Applying Aardwolf Dark changes MudForge's app-wide theme. It does not replace your terminal color palette.</p><button class="aw-button aw-button--primary" type="button" data-mud-action="apply-theme">Apply Aardwolf Dark</button></section>
    <h2 class="aw-heading">Diagnostics</h2>
    <pre class="aw-status aw-scroll" data-mud-bind="diagnostics" role="status">No diagnostics.</pre>
    <div class="aw-toolbar"><button class="aw-button" type="button" data-mud-action="refresh">Refresh GMCP</button><button class="aw-button" type="button" data-mud-action="renegotiate">Renegotiate</button><button class="aw-button" type="button" data-mud-action="clear">Clear diagnostics</button><button class="aw-button" type="button" data-mud-action="log-error">Log: errors</button><button class="aw-button" type="button" data-mud-action="log-info">Log: info</button><button class="aw-button" type="button" data-mud-action="log-debug">Log: debug</button><button class="aw-button" type="button" data-mud-action="hide">Hide</button></div>
    <p class="aw-muted">Core never enables tags, GMCP-only channels, or server debug automatically.</p>
  ]]
end

local function rebuild_core_widget()
  if not widget or not ui_library_loaded or type(core_api) ~= "table" or type(core_api.ui) ~= "table" then return false end
  local document, problem = core_api.ui.document(control_center_body())
  if not document then
    echo("Aardwolf Core UI error: " .. tostring(problem and problem.message or "could not compose document"))
    return false
  end
  setWidgetProperty(widget, "content", document)
  return true
end

local function render()
  if not widget then return end
  local consumer_parts = {}
  for consumer_id, declaration in pairs(declarations) do
    consumer_parts[#consumer_parts + 1] = consumer_id .. ": " .. package_list_string(declaration.packages)
  end
  table.sort(consumer_parts)

  local fresh_groups = {}
  for _, group in ipairs(CHAR_GROUPS) do
    if freshness.char[group] then fresh_groups[#fresh_groups + 1] = group end
  end

  local diagnostic_parts = {}
  local rank = { error = 1, info = 2, debug = 3 }
  local selected_rank = rank[log_level] or 2
  for _, item in ipairs(diagnostics) do
    if (rank[item.level] or 1) <= selected_rank then
      diagnostic_parts[#diagnostic_parts + 1] = item.level .. " " .. item.code .. ": " .. item.message
    end
  end

  local bindings = {
    version = plugin.version,
    apiVersion = API_VERSION,
    protocol = tostring(PROTOCOL_VERSION),
    connection = connected and "Connected" or "Disconnected",
    session = session_id and tostring(session_id) or "none",
    packages = package_list_string(negotiated_packages),
    consumers = #consumer_parts > 0 and table.concat(consumer_parts, " | ") or "none",
    charFresh = #fresh_groups > 0 and table.concat(fresh_groups, ", ") or "none",
    roomFresh = freshness.room and "yes" or "no",
    counters = string.format("accepted %d, rejected %d, negotiations %d, failures %d, refreshes %d",
      counters.accepted, counters.rejected, counters.negotiations,
      counters.negotiationFailures, counters.refreshes),
    diagnostics = #diagnostic_parts > 0 and table.concat(diagnostic_parts, "\n") or "No diagnostics.",
    logLevel = log_level,
  }
  for index, key in ipairs(ui_window_order) do
    local window = ui_windows[key]
    if window then
      bindings["windowTitle" .. tostring(index)] = window.title
      bindings["windowOwner" .. tostring(index)] = window.consumerId
      bindings["windowType" .. tostring(index)] = window.type
      bindings["windowVisible" .. tostring(index)] = window.visible and "visible" or "hidden"
    end
  end
  setBoundValues(widget, bindings)
end

local function add_diagnostic(level, code, message)
  local item = {
    level = tostring(level),
    code = tostring(code),
    message = tostring(message),
    sessionId = session_id,
    session = session_number,
  }
  diagnostics[#diagnostics + 1] = item
  while #diagnostics > MAX_DIAGNOSTICS do table.remove(diagnostics, 1) end
  emit_copy(EVENT_DIAGNOSTIC, item)
  render()
end

local function clear_live_state(reason)
  char_state = {}
  room_state = nil
  freshness = { char = {}, room = false }
  update_sequence = 0
  emit_copy(EVENT_RESET, {
    protocol = PROTOCOL_VERSION,
    reason = reason,
    sessionId = session_id,
    session = session_number,
  })
  render()
end

local function normalize_char(group, data)
  if type(data) ~= "table" then return nil, nil, "payload is not a table" end
  local ok_raw, raw_or_error = pcall(safe_raw, data)
  if not ok_raw then return nil, nil, tostring(raw_or_error) end
  local schema = CHAR_SCHEMAS[group]
  local normalized = {}
  for field, expected in pairs(schema) do
    local value = data[field]
    if value ~= nil then
      if expected == "integer" and not finite_integer(value) then
        return nil, nil, field .. " must be a finite exact integer"
      elseif expected == "string" and not valid_string(value) then
        return nil, nil, field .. " must be a bounded control-free string"
      elseif expected == "classes" and not valid_classes(value) then
        return nil, nil, field .. " must contain unique class ids 0 through 6"
      end
      normalized[field] = value
    end
  end
  return normalized, raw_or_error, nil
end

local function normalize_room(data)
  if type(data) ~= "table" then return nil, nil, "payload is not a table" end
  local ok_raw, raw_or_error = pcall(safe_raw, data)
  if not ok_raw then return nil, nil, tostring(raw_or_error) end
  local normalized = {}
  for _, field in ipairs({ "num" }) do
    if data[field] ~= nil then
      if not finite_integer(data[field]) then return nil, nil, field .. " must be a finite exact integer" end
      normalized[field] = data[field]
    end
  end
  for _, field in ipairs({ "name", "zone", "terrain", "details" }) do
    if data[field] ~= nil then
      if not valid_string(data[field]) then return nil, nil, field .. " must be a bounded control-free string" end
      normalized[field] = data[field]
    end
  end
  if data.exits ~= nil then
    if type(data.exits) ~= "table" then return nil, nil, "exits must be a table" end
    normalized.exits = {}
    for direction, destination in pairs(data.exits) do
      if not valid_string(direction, 64) then return nil, nil, "exit direction is invalid" end
      if not finite_integer(destination) then return nil, nil, "exit destination must be an integer" end
      normalized.exits[direction] = destination
    end
  end
  if data.coord ~= nil then
    if type(data.coord) ~= "table" then return nil, nil, "coord must be a table" end
    normalized.coord = {}
    for _, field in ipairs({ "id", "x", "y", "cont" }) do
      if data.coord[field] ~= nil then
        if not finite_integer(data.coord[field]) then return nil, nil, "coord." .. field .. " must be an integer" end
        normalized.coord[field] = data.coord[field]
      end
    end
  end
  return normalized, raw_or_error, nil
end

local function ensure_session_from_update()
  if connected then return end
  connected = true
  session_id = getSessionId()
  session_number = session_number + 1
  retry_used = false
  bootstrapped = false
  clear_live_state("gmcp-update")
  emit_copy(EVENT_SESSION, {
    protocol = PROTOCOL_VERSION,
    connected = true,
    sessionId = session_id,
    session = session_number,
    reason = "gmcp-update",
  })
end

local function handle_char(group, data)
  ensure_session_from_update()
  local normalized, raw, problem = normalize_char(group, data)
  if not normalized then
    counters.rejected = counters.rejected + 1
    add_diagnostic("error", "invalid-char-" .. group, problem)
    return
  end
  update_sequence = update_sequence + 1
  counters.accepted = counters.accepted + 1
  char_state[group] = { normalized = normalized, raw = raw, sequence = update_sequence }
  freshness.char[group] = true
  local payload = {
    protocol = PROTOCOL_VERSION,
    group = group,
    normalized = normalized,
    raw = raw,
    fresh = true,
    sessionId = session_id,
    session = session_number,
    sequence = update_sequence,
  }
  emit_copy("aardwolf.core.char.updated", payload)
  emit_copy("aardwolf.core.char." .. group, payload)
  render()
end

local function handle_room(data)
  ensure_session_from_update()
  local normalized, raw, problem = normalize_room(data)
  if not normalized then
    counters.rejected = counters.rejected + 1
    add_diagnostic("error", "invalid-room", problem)
    return
  end
  update_sequence = update_sequence + 1
  counters.accepted = counters.accepted + 1
  room_state = { normalized = normalized, raw = raw, sequence = update_sequence }
  freshness.room = true
  emit_copy("aardwolf.core.room.updated", {
    protocol = PROTOCOL_VERSION,
    normalized = normalized,
    raw = raw,
    fresh = true,
    sessionId = session_id,
    session = session_number,
    sequence = update_sequence,
  })
  render()
end

local function loaded_plugin_set()
  local loaded = {}
  local ok, plugins = pcall(getLoadedPlugins)
  if not ok or type(plugins) ~= "table" then return loaded end
  for _, item in ipairs(plugins) do
    if type(item) == "table" and valid_string(item.id, 128) and item.enabled ~= false then
      loaded[item.id] = true
    end
  end
  return loaded
end

local function remove_consumer_windows(consumer_id)
  local changed = false
  for key, window in pairs(ui_windows) do
    if window.consumerId == consumer_id then
      ui_windows[key] = nil
      changed = true
    end
  end
  if changed then
    rebuild_ui_order()
    rebuild_core_widget()
    render()
  end
end

local function reconcile_declarations()
  local loaded = loaded_plugin_set()
  for consumer_id, _ in pairs(declarations) do
    if not loaded[consumer_id] then
      declarations[consumer_id] = nil
      remove_consumer_windows(consumer_id)
    end
  end
end

local function desired_packages()
  reconcile_declarations()
  local result = copy(BASELINE_PACKAGES)
  for _, declaration in pairs(declarations) do
    if type(declaration) == "table" and type(declaration.packages) == "table" then
      for package_name, wanted in pairs(declaration.packages) do
        if wanted == true and ALLOWED_PACKAGES[package_name] then result[package_name] = true end
      end
    end
  end
  return result
end

local function supports_payload(packages)
  local values = {}
  for _, name in ipairs(PACKAGE_ORDER) do
    if packages[name] then values[#values + 1] = name .. " 1" end
  end
  return values, table.concat(values, "|")
end

local function refresh_packages(requested)
  if not connected then return false, "not connected" end
  requested = requested or { Char = true, Room = true }
  local ok = true
  if requested.Char == true then ok = sendGMCP("request char") == true and ok end
  if requested.Room == true then ok = sendGMCP("request room") == true and ok end
  if ok then
    counters.refreshes = counters.refreshes + 1
    render()
    return true, nil
  end
  add_diagnostic("error", "refresh-failed", "MudForge did not hand every refresh request to the transport")
  return false, "refresh request failed"
end

local perform_negotiation

local function cancel_negotiation_timer()
  if negotiation_timer and negotiation_timer ~= "" then removeTimer(negotiation_timer) end
  negotiation_timer = nil
end

local function schedule_negotiation(delay, force)
  if not connected then return false end
  cancel_negotiation_timer()
  negotiation_timer = addTimer(delay or NEGOTIATION_DELAY_MS, function()
    negotiation_timer = nil
    perform_negotiation(force == true)
  end, false)
  if negotiation_timer == "" then
    negotiation_timer = nil
    return false
  end
  return true
end

perform_negotiation = function(force)
  if not connected then return false, "not connected" end
  local elapsed = now_ms() - last_negotiation_ms
  if elapsed < MIN_NEGOTIATION_GAP_MS then
    schedule_negotiation(MIN_NEGOTIATION_GAP_MS - elapsed, force)
    return false, "rate limited"
  end

  local wanted = desired_packages()
  local payload, key = supports_payload(wanted)
  if not force and key == last_supports_key then return true, nil end

  last_negotiation_ms = now_ms()
  local sent = sendGMCP("Core.Supports.Set", payload)
  if sent ~= true then
    counters.negotiationFailures = counters.negotiationFailures + 1
    add_diagnostic("error", "negotiation-failed", "MudForge did not hand Core.Supports.Set to the transport")
    if not retry_used then
      retry_used = true
      schedule_negotiation(RETRY_DELAY_MS, true)
    end
    return false, "transport refused Core.Supports.Set"
  end

  counters.negotiations = counters.negotiations + 1
  negotiated_packages = wanted
  last_supports_key = key
  retry_used = false
  add_diagnostic("debug", "negotiated", "Sent package union: " .. package_list_string(wanted))

  if not bootstrapped then
    bootstrapped = true
    refresh_packages({ Char = true, Room = true })
  end
  render()
  return true, nil
end

local function validate_declaration(payload)
  if type(payload) ~= "table" then return nil, "invalid-request", "declaration must be a table" end
  if not valid_string(payload.consumerId, 128) then return nil, "invalid-consumer", "consumerId is required" end
  if not finite_integer(payload.minProtocol) or payload.minProtocol < 1 then
    return nil, "invalid-protocol", "minProtocol must be a positive integer"
  end
  if payload.minProtocol > PROTOCOL_VERSION then
    return nil, "unsupported-protocol", "Core protocol " .. PROTOCOL_VERSION .. " is older than requested protocol " .. payload.minProtocol
  end
  if type(payload.packages) ~= "table" then return nil, "invalid-packages", "packages must be a table" end
  local packages = {}
  for package_name, wanted in pairs(payload.packages) do
    if not ALLOWED_PACKAGES[package_name] then
      return nil, "invalid-package", "unsupported Aardwolf package " .. tostring(package_name)
    end
    if type(wanted) ~= "boolean" then
      return nil, "invalid-package", "package declarations must be booleans"
    end
    if wanted then packages[package_name] = true end
  end
  if not loaded_plugin_set()[payload.consumerId] then
    return nil, "consumer-not-loaded", "consumer is not enabled in this session"
  end
  return { consumerId = payload.consumerId, minProtocol = payload.minProtocol, packages = packages }, nil, nil
end

local function registration_response(consumer_id, ok, code, message)
  emit_copy(EVENT_REGISTRATION, {
    consumerId = consumer_id,
    ok = ok,
    code = code,
    message = message,
    protocol = PROTOCOL_VERSION,
    version = plugin.version,
    apiVersion = API_VERSION,
    capabilities = {
      Char = true,
      Room = true,
      negotiation = true,
      storage = true,
      ui = { version = UI_VERSION, html = true, canvas = true, windowControl = true },
    },
  })
end

local function on_declare(payload)
  local declaration, code, message = validate_declaration(payload)
  local consumer_id = type(payload) == "table" and payload.consumerId or nil
  if not declaration then
    registration_response(consumer_id, false, code, message)
    return
  end
  declarations[declaration.consumerId] = declaration
  registration_response(declaration.consumerId, true, nil, nil)
  add_diagnostic("debug", "consumer-declared", declaration.consumerId .. " declared " .. package_list_string(declaration.packages))
  schedule_negotiation(NEGOTIATION_DELAY_MS, false)
  render()
end

local function on_withdraw(payload)
  if type(payload) ~= "table" or not valid_string(payload.consumerId, 128) then return end
  if declarations[payload.consumerId] then
    declarations[payload.consumerId] = nil
    remove_consumer_windows(payload.consumerId)
    add_diagnostic("debug", "consumer-withdrew", payload.consumerId .. " withdrew its package declaration")
    schedule_negotiation(NEGOTIATION_DELAY_MS, false)
    render()
  end
end

local function valid_ui_window(payload, require_existing)
  if type(payload) ~= "table" or not valid_string(payload.consumerId, 128)
      or not valid_string(payload.name, 128) then return nil end
  if require_existing then return ui_windows[ui_window_key(payload.consumerId, payload.name)] end
  if not declarations[payload.consumerId] or not loaded_plugin_set()[payload.consumerId] then return nil end
  if not valid_string(payload.title, 128) or (payload.type ~= "html" and payload.type ~= "canvas")
      or type(payload.visible) ~= "boolean" then return nil end
  return {
    consumerId = payload.consumerId,
    name = payload.name,
    title = payload.title,
    type = payload.type,
    visible = payload.visible,
  }
end

local function on_ui_declare(payload)
  local window = valid_ui_window(payload, false)
  if not window then return end
  local key = ui_window_key(window.consumerId, window.name)
  local membership_changed = ui_windows[key] == nil
  ui_windows[key] = window
  if membership_changed then
    rebuild_ui_order()
    rebuild_core_widget()
  end
  render()
end

local function on_ui_state(payload)
  local window = valid_ui_window(payload, true)
  if not window or type(payload.visible) ~= "boolean" then return end
  window.visible = payload.visible
  render()
end

local function on_ui_withdraw(payload)
  local window = valid_ui_window(payload, true)
  if not window then return end
  ui_windows[ui_window_key(payload.consumerId, payload.name)] = nil
  rebuild_ui_order()
  rebuild_core_widget()
  render()
end

local function send_ui_command(window, action)
  if not window or (action ~= "show" and action ~= "hide") then return end
  emit_copy(EVENT_UI_COMMAND, {
    consumerId = window.consumerId,
    name = window.name,
    action = action,
  })
end

local function query_ui_windows()
  emit_copy(EVENT_UI_QUERY, {})
  render()
end

local function apply_app_theme()
  if not ui_library_loaded or type(core_api) ~= "table" or type(core_api.ui) ~= "table" then
    add_diagnostic("error", "ui-library-missing", "Install aardwolf-core-api before applying the Aardwolf theme")
    return
  end
  if type(registerTheme) ~= "function" or type(setTheme) ~= "function" then
    add_diagnostic("error", "theme-api-missing", "MudForge 1.2.2454 or newer is required for app themes")
    return
  end
  local theme = core_api.ui.appTheme()
  local ok_register, theme_id = pcall(registerTheme, theme)
  if not ok_register or type(theme_id) ~= "string" then
    add_diagnostic("error", "theme-register-failed", "MudForge could not register Aardwolf Dark")
    return
  end
  local ok_apply, applied = pcall(setTheme, theme_id)
  if not ok_apply or applied ~= true then
    add_diagnostic("error", "theme-apply-failed", "MudForge could not apply Aardwolf Dark")
    return
  end
  add_diagnostic("info", "theme-applied", "Applied the app-wide Aardwolf Dark theme")
end

local function status_snapshot()
  return {
    protocol = PROTOCOL_VERSION,
    version = plugin.version,
    apiVersion = API_VERSION,
    connected = connected,
    sessionId = session_id,
    session = session_number,
    sequence = update_sequence,
    packages = copy(negotiated_packages),
    consumers = copy(declarations),
    freshness = copy(freshness),
    counters = copy(counters),
    diagnostics = copy(diagnostics),
    logLevel = log_level,
    windows = copy(ui_windows),
  }
end

local function data_snapshot(path)
  if path == "room" or path == "room.info" then
    if not room_state then return nil, "room data is not fresh" end
    return {
      protocol = PROTOCOL_VERSION,
      normalized = copy(room_state.normalized),
      raw = copy(room_state.raw),
      fresh = freshness.room,
      sessionId = session_id,
      session = session_number,
      sequence = room_state.sequence,
    }, nil
  end
  local group = type(path) == "string" and string.match(path, "^char%.([a-z]+)$") or nil
  if not group or not CHAR_SCHEMAS[group] then return nil, "unknown snapshot path" end
  local state = char_state[group]
  if not state then return nil, "character group is not fresh" end
  return {
    protocol = PROTOCOL_VERSION,
    group = group,
    normalized = copy(state.normalized),
    raw = copy(state.raw),
    fresh = freshness.char[group] == true,
    sessionId = session_id,
    session = session_number,
    sequence = state.sequence,
  }, nil
end

local function respond(request, ok, data, code, message)
  emit_copy(EVENT_RESPONSE, {
    consumerId = request.consumerId,
    requestId = request.requestId,
    ok = ok,
    data = data,
    code = code,
    message = message,
    protocol = PROTOCOL_VERSION,
  })
end

local function on_request(request)
  if type(request) ~= "table" or not valid_string(request.consumerId, 128)
      or not valid_string(request.requestId, 128) then return end
  if request.kind == "status" then
    respond(request, true, status_snapshot())
  elseif request.kind == "snapshot" then
    local data, problem = data_snapshot(request.path)
    respond(request, data ~= nil, data, data and nil or "not-fresh", problem)
  elseif request.kind == "refresh" then
    local ok, problem = refresh_packages(request.packages)
    respond(request, ok, { requested = copy(request.packages or {}) }, ok and nil or "refresh-failed", problem)
  elseif request.kind == "renegotiate" then
    local ok, problem = perform_negotiation(true)
    respond(request, ok, status_snapshot(), ok and nil or "negotiation-pending", problem)
  elseif request.kind == "clear-diagnostics" then
    diagnostics = {}
    render()
    respond(request, true, { cleared = true })
  else
    respond(request, false, nil, "unknown-request", "unknown Core request")
  end
end

local function save_settings()
  local ok, result = pcall(saveTable, SETTINGS_TABLE, { format = 1, logLevel = log_level })
  if not ok or result ~= true then add_diagnostic("error", "settings-save-failed", "Could not persist Core settings") end
end

local function set_log_level(level)
  if level ~= "error" and level ~= "info" and level ~= "debug" then return false end
  log_level = level
  save_settings()
  render()
  return true
end

local function load_settings()
  local ok, stored = pcall(loadTable, SETTINGS_TABLE)
  if ok and type(stored) == "table" and stored.format == 1
      and (stored.logLevel == "error" or stored.logLevel == "info" or stored.logLevel == "debug") then
    log_level = stored.logLevel
  end
end

local function show_status()
  echo(string.format("Aardwolf Core %s (protocol %d): %s, session %s, packages [%s]",
    plugin.version, PROTOCOL_VERSION, connected and "connected" or "disconnected",
    session_id and tostring(session_id) or "none", package_list_string(negotiated_packages)))
end

local function show_gmcp()
  echo("Aardwolf Core GMCP: " .. package_list_string(negotiated_packages))
  for consumer_id, declaration in pairs(declarations) do
    echo("  " .. consumer_id .. ": " .. package_list_string(declaration.packages))
  end
end

local function show_diagnostics()
  if #diagnostics == 0 then echo("Aardwolf Core: no diagnostics.") return end
  for _, item in ipairs(diagnostics) do
    echo(string.format("Aardwolf Core [%s] %s: %s", item.level, item.code, item.message))
  end
end

local function create_core_widget()
  if not ui_library_loaded or type(core_api) ~= "table" or type(core_api.ui) ~= "table" then
    add_diagnostic("error", "ui-library-missing", "Install aardwolf-core-api to use the Core control center")
    return
  end
  local tokens = core_api.ui.tokens()
  widget = createWidget({
    type = "html",
    name = "aardwolf-core-diagnostics",
    title = "Aardwolf Core Control Center",
    position = { x = 120, y = 100 },
    size = { width = 680, height = 680 },
    visible = false,
    resizable = true,
    scrollable = true,
    appearance = {
      showTitleBar = true,
      autoHideSettingsCog = true,
      movable = true,
      resizable = true,
      titleTextColor = tokens.colors.primary,
      backgroundColor = tokens.colors.background,
      backgroundOpacity = 0.96,
      borderColor = tokens.colors.border,
      borderWidth = 1,
      borderRadius = tokens.radius.medium,
      borderStyle = "solid",
    },
  })
  rebuild_ui_order()
  rebuild_core_widget()
  registerWidgetEvent(widget, "action", function(event)
    if type(event) ~= "table" then return end
    if event.action == "refresh" then refresh_packages({ Char = true, Room = true })
    elseif event.action == "renegotiate" then perform_negotiation(true)
    elseif event.action == "clear" then diagnostics = {}; render()
    elseif event.action == "log-error" then set_log_level("error")
    elseif event.action == "log-info" then set_log_level("info")
    elseif event.action == "log-debug" then set_log_level("debug")
    elseif event.action == "windows-refresh" then query_ui_windows()
    elseif event.action == "windows-show-all" then
      for _, window in pairs(ui_windows) do send_ui_command(window, "show") end
    elseif event.action == "windows-hide-all" then
      for _, window in pairs(ui_windows) do send_ui_command(window, "hide") end
    elseif event.action == "apply-theme" then apply_app_theme()
    elseif event.action == "hide" then hideWidget(widget)
    elseif ui_window_actions[event.action] then
      local action = ui_window_actions[event.action]
      send_ui_command(ui_windows[action.key], action.action)
    end
    focusPrompt()
  end)
  render()
end

local function register_core_events()
  local function listen(name, callback)
    on(name, callback)
    subscriptions[#subscriptions + 1] = { name = name, callback = callback }
  end
  listen(EVENT_DECLARE, on_declare)
  listen(EVENT_WITHDRAW, on_withdraw)
  listen(EVENT_REQUEST, on_request)
  listen(EVENT_UI_DECLARE, on_ui_declare)
  listen(EVENT_UI_WITHDRAW, on_ui_withdraw)
  listen(EVENT_UI_STATE, on_ui_state)
end

local function register_gmcp()
  for _, group in ipairs(CHAR_GROUPS) do
    local current = group
    onGMCPUpdate(CHAR_PACKAGES[current], function(data) handle_char(current, data) end)
  end
  onGMCPUpdate("Room.Info", handle_room)
end

local function command(args)
  args = string.lower(args or "")
  if args == "" then
    if widget then
      showWidget(widget)
      query_ui_windows()
      render()
    else
      echo("Aardwolf Core control center is unavailable; install aardwolf-core-api.")
    end
  elseif args == "status" then show_status()
  elseif args == "gmcp" then show_gmcp()
  elseif args == "refresh" then
    local ok, problem = refresh_packages({ Char = true, Room = true })
    if not ok then echo("Aardwolf Core refresh failed: " .. tostring(problem)) end
  elseif args == "diagnostics" then show_diagnostics()
  elseif args == "renegotiate" then
    local ok, problem = perform_negotiation(true)
    if not ok then echo("Aardwolf Core renegotiation pending or failed: " .. tostring(problem)) end
  else
    echo("Usage: awcore [status|gmcp|refresh|diagnostics|renegotiate]")
  end
end

function init()
  if initialized then return end
  initialized = true
  load_settings()
  register_core_events()
  register_gmcp()
  create_core_widget()
  registerCommand("awcore", command, "Open or inspect the Aardwolf Core framework")
  emit_copy(EVENT_READY, status_snapshot())
  emit_copy(EVENT_DISCOVER, { protocol = PROTOCOL_VERSION, version = plugin.version })
end

function onConnect(incoming_session_id)
  session_id = incoming_session_id
  session_number = session_number + 1
  connected = true
  retry_used = false
  bootstrapped = false
  last_supports_key = nil
  negotiated_packages = {}
  clear_live_state("connect")
  add_diagnostic("info", "session-connected", "A new connection session started")
  emit_copy(EVENT_SESSION, {
    protocol = PROTOCOL_VERSION,
    connected = true,
    sessionId = session_id,
    session = session_number,
    reason = "connect",
  })
  emit_copy(EVENT_DISCOVER, { protocol = PROTOCOL_VERSION, version = plugin.version })
  schedule_negotiation(NEGOTIATION_DELAY_MS, true)
end

function onDisconnect(incoming_session_id)
  if session_id and incoming_session_id ~= session_id then return end
  cancel_negotiation_timer()
  clear_live_state("disconnect")
  add_diagnostic("info", "session-disconnected", "The connection session ended and live data was cleared")
  connected = false
  emit_copy(EVENT_SESSION, {
    protocol = PROTOCOL_VERSION,
    connected = false,
    sessionId = incoming_session_id,
    session = session_number,
    reason = "disconnect",
  })
  session_id = nil
  retry_used = false
  bootstrapped = false
  last_supports_key = nil
  negotiated_packages = {}
  render()
end

function cleanup()
  cancel_negotiation_timer()
  clear_live_state("cleanup")
  for _, subscription in ipairs(subscriptions) do
    off(subscription.name, subscription.callback)
  end
  subscriptions = {}
  if widget then destroyWidget(widget) end
  widget = nil
  ui_windows = {}
  ui_window_order = {}
  ui_window_actions = {}
end

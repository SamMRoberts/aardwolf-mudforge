library = {
  name = "aardwolf-core-api",
  version = "0.3.0",
  description = "Consumer data and managed-window API for the Aardwolf Core MudForge plugin.",
  author = "Sam Roberts",
  license = "MIT",
}

local M = { storage = {}, ui = {} }
local PROTOCOL_VERSION = 1
local EVENT_DISCOVER = "aardwolf.core.consumer.discover"
local EVENT_DECLARE = "aardwolf.core.consumer.declare"
local EVENT_WITHDRAW = "aardwolf.core.consumer.withdraw"
local EVENT_REGISTRATION = "aardwolf.core.consumer.registration"
local EVENT_REQUEST = "aardwolf.core.request"
local EVENT_RESPONSE = "aardwolf.core.response"
local EVENT_UI_DECLARE = "aardwolf.core.ui.window.declare"
local EVENT_UI_WITHDRAW = "aardwolf.core.ui.window.withdraw"
local EVENT_UI_STATE = "aardwolf.core.ui.window.state"
local EVENT_UI_COMMAND = "aardwolf.core.ui.window.command"
local EVENT_UI_QUERY = "aardwolf.core.ui.window.query"
local TOPICS = {
  ["ready"] = "aardwolf.core.ready",
  ["session"] = "aardwolf.core.session",
  ["reset"] = "aardwolf.core.reset",
  ["diagnostic"] = "aardwolf.core.diagnostic",
  ["char.updated"] = "aardwolf.core.char.updated",
  ["char.base"] = "aardwolf.core.char.base",
  ["char.vitals"] = "aardwolf.core.char.vitals",
  ["char.stats"] = "aardwolf.core.char.stats",
  ["char.maxstats"] = "aardwolf.core.char.maxstats",
  ["char.status"] = "aardwolf.core.char.status",
  ["char.worth"] = "aardwolf.core.char.worth",
  ["room"] = "aardwolf.core.room.updated",
  ["room.info"] = "aardwolf.core.room.updated",
  ["group"] = "aardwolf.core.group.updated",
  ["comm.updated"] = "aardwolf.core.comm.updated",
  ["comm.channel"] = "aardwolf.core.comm.channel",
  ["comm.tick"] = "aardwolf.core.comm.tick",
  ["comm.quest"] = "aardwolf.core.comm.quest",
  ["comm.repop"] = "aardwolf.core.comm.repop",
}
local ALLOWED_PACKAGES = { Core = true, Char = true, Comm = true, Room = true, Group = true }

local UI_TOKENS = {
  schema = 1,
  id = "aardwolf-dark",
  colors = {
    background = "#111827",
    surface = "#0b1020",
    elevated = "#1f2937",
    primary = "#f3c969",
    accent = "#93c5fd",
    text = "#e5e7eb",
    muted = "#9ca3af",
    border = "#374151",
    success = "#86efac",
    warning = "#fcd34d",
    error = "#fca5a5",
    button = "#374151",
    buttonHover = "#4b5563",
  },
  spacing = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 },
  typography = { family = "system-ui, sans-serif", size = 14, heading = 18, small = 12 },
  focus = { color = "#f3c969", width = 3, offset = 2 },
  radius = { small = 4, medium = 6, large = 10 },
}

local APP_THEME = {
  id = "aardwolf-dark",
  name = "Aardwolf Dark",
  colors = {
    background = "221 39% 11%",
    foreground = "220 13% 91%",
    card = "222 47% 8%",
    cardForeground = "220 13% 91%",
    popover = "222 47% 8%",
    popoverForeground = "220 13% 91%",
    primary = "43 84% 68%",
    primaryForeground = "221 39% 11%",
    secondary = "215 28% 17%",
    secondaryForeground = "220 13% 91%",
    muted = "215 28% 17%",
    mutedForeground = "218 11% 65%",
    accent = "211 96% 78%",
    accentForeground = "221 39% 11%",
    destructive = "0 72% 51%",
    destructiveForeground = "0 0% 100%",
    border = "215 20% 27%",
    input = "215 20% 27%",
    ring = "43 84% 68%",
  },
}

local UI_STYLES = [[
  :root{color-scheme:dark;--aw-bg:#111827;--aw-surface:#0b1020;--aw-elevated:#1f2937;--aw-primary:#f3c969;--aw-accent:#93c5fd;--aw-text:#e5e7eb;--aw-muted:#9ca3af;--aw-border:#374151;--aw-success:#86efac;--aw-warning:#fcd34d;--aw-error:#fca5a5;--aw-button:#374151;--aw-button-hover:#4b5563}
  *{box-sizing:border-box}body{margin:0;background:var(--aw-bg);color:var(--aw-text);font:14px system-ui,sans-serif}.aw-root{min-height:100%;padding:14px;background:var(--aw-bg);color:var(--aw-text)}
  .aw-title{margin:0 0 12px;color:var(--aw-primary);font-size:18px;line-height:1.3}.aw-heading{margin:16px 0 8px;color:var(--aw-accent);font-size:14px;line-height:1.35}.aw-section{padding:12px;background:var(--aw-surface);border:1px solid var(--aw-border);border-radius:6px}.aw-section+.aw-section{margin-top:12px}
  .aw-toolbar{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-top:12px}.aw-grid{display:grid;grid-template-columns:minmax(120px,160px) minmax(0,1fr);gap:6px 12px}.aw-label{color:var(--aw-muted)}.aw-value{min-width:0;overflow-wrap:anywhere}
  .aw-button{min-height:36px;padding:7px 11px;color:var(--aw-text);background:var(--aw-button);border:1px solid #6b7280;border-radius:4px;font:inherit;cursor:pointer}.aw-button:hover{background:var(--aw-button-hover)}.aw-button:focus-visible,.aw-field:focus-visible{outline:3px solid var(--aw-primary);outline-offset:2px}.aw-button--primary{color:#111827;background:var(--aw-primary);border-color:var(--aw-primary)}.aw-button--danger{color:#111827;background:var(--aw-error);border-color:var(--aw-error)}
  .aw-field{min-height:36px;padding:7px 9px;color:var(--aw-text);background:var(--aw-surface);border:1px solid var(--aw-border);border-radius:4px;font:inherit}.aw-status{white-space:pre-wrap;padding:9px;background:var(--aw-surface);border:1px solid var(--aw-border);border-radius:4px}.aw-muted{color:var(--aw-muted)}.aw-success{color:var(--aw-success)}.aw-warning{color:var(--aw-warning)}.aw-error{color:var(--aw-error)}.aw-scroll{max-height:180px;overflow:auto}
  .aw-window-row{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px;align-items:center;padding:8px 0;border-bottom:1px solid var(--aw-border)}.aw-window-row:last-child{border-bottom:0}.aw-window-meta{font-size:12px;color:var(--aw-muted)}
]]

local api = nil
local initialized = false
local plugin_id = nil
local min_protocol = PROTOCOL_VERSION
local packages = {}
local listeners = {}
local request_counter = 0
local responses = {}
local registration = nil
local available = false
local ui_api = nil
local windows = {}

local function stack_contains(stack, value)
  -- MudForge tables have reference identity and no metatables. Keep ancestors
  -- in an array so this matches the plugin's restricted builtin subset.
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
    if type(item) == "table" then result[key] = copy(item, stack)
    elseif item ~= nil then result[key] = item end
  end
  stack[#stack] = nil
  return result
end

local function error_value(code, message)
  return { code = code, message = message, protocol = PROTOCOL_VERSION }
end

local function plain_name(value, allow_colon)
  if type(value) ~= "string" or value == "" or #value > 128 then return false end
  for index = 1, #value do
    local ch = string.sub(value, index, index)
    local ok = (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")
      or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_"
      or ch == "." or (allow_colon and ch == ":")
    if not ok then return false end
  end
  return true
end

local function bounded_text(value, limit)
  return type(value) == "string" and #value <= limit and not string.find(value, "[%z\1-\31\127]")
end

local function finite_number(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function valid_point(value)
  return type(value) == "table" and finite_number(value.x) and finite_number(value.y)
    and math.abs(value.x) <= 10000 and math.abs(value.y) <= 10000
end

local function valid_size(value)
  return type(value) == "table" and finite_number(value.width) and finite_number(value.height)
    and value.width >= 100 and value.width <= 4096 and value.height >= 80 and value.height <= 4096
end

function M.ui.tokens()
  return copy(UI_TOKENS)
end

function M.ui.appTheme()
  return copy(APP_THEME)
end

function M.ui.document(content, options)
  if type(content) ~= "string" or #content > 131072 then
    return nil, error_value("invalid-window", "HTML content must be a bounded static string")
  end
  options = options or {}
  if type(options) ~= "table" then return nil, error_value("invalid-window", "document options must be a table") end
  local css = options.css or ""
  if type(css) ~= "string" or #css > 32768 then
    return nil, error_value("invalid-window", "additional CSS must be a bounded static string")
  end
  return "<style>" .. UI_STYLES .. css .. "</style><main class=\"aw-root\">" .. content .. "</main>", nil
end

local function ui_error(code, message)
  return nil, error_value(code, message)
end

local function current_visibility(window)
  if not ui_api then return window.visible end
  local ok, visible = pcall(ui_api.widgetInfo, window.widgetId, 7)
  if ok and type(visible) == "boolean" then window.visible = visible end
  return window.visible
end

local function window_payload(window)
  return {
    consumerId = plugin_id,
    name = window.name,
    title = window.title,
    type = window.type,
    visible = current_visibility(window),
  }
end

local function declare_window(window)
  if available and api then api.emit(EVENT_UI_DECLARE, window_payload(window)) end
end

local function declare_windows()
  for _, window in pairs(windows) do declare_window(window) end
end

local function update_window(window)
  if available and api then api.emit(EVENT_UI_STATE, window_payload(window)) end
end

local function withdraw_window(window)
  if available and api then
    api.emit(EVENT_UI_WITHDRAW, { consumerId = plugin_id, name = window.name })
  end
end

local function get_window(name)
  if not initialized then return ui_error("not-initialized", "call aardwolf-core-api.init first") end
  if not ui_api then return ui_error("ui-unavailable", "initialize Core with a MudForge UI adapter") end
  if not plain_name(name, false) then return ui_error("invalid-window", "window name must use letters, digits, dot, dash, or underscore") end
  local window = windows[name]
  if not window then return ui_error("unknown-window", "managed window " .. tostring(name) .. " does not exist") end
  return window, nil
end

local function set_window_visibility(name, visible)
  local window, problem = get_window(name)
  if not window then return nil, problem end
  local operation = visible and ui_api.showWidget or ui_api.hideWidget
  local ok = pcall(operation, window.widgetId)
  if not ok then return ui_error("window-control-failed", "MudForge could not change managed window visibility") end
  window.visible = visible
  update_window(window)
  return true, nil
end

local function loaded_core()
  local ok, loaded = pcall(api.getLoadedPlugins)
  if not ok or type(loaded) ~= "table" then return false end
  for _, item in ipairs(loaded) do
    if type(item) == "table" and item.id == "aardwolf-core" and item.enabled ~= false then return true end
  end
  return false
end

local function validate_packages(value)
  if type(value) ~= "table" then return nil, error_value("invalid-packages", "packages must be a table") end
  local result = {}
  for name, wanted in pairs(value) do
    if not ALLOWED_PACKAGES[name] then
      return nil, error_value("invalid-package", "unsupported Aardwolf package " .. tostring(name))
    end
    if type(wanted) ~= "boolean" then
      return nil, error_value("invalid-package", "package declarations must be booleans")
    end
    if wanted then result[name] = true end
  end
  return result, nil
end

local function declare()
  registration = nil
  api.emit(EVENT_DECLARE, {
    consumerId = plugin_id,
    minProtocol = min_protocol,
    packages = copy(packages),
    apiVersion = library.version,
  })
  if not registration then
    available = false
    return nil, error_value("missing-core", "Aardwolf Core did not answer the registration request")
  end
  if registration.ok ~= true then
    available = false
    return nil, error_value(registration.code or "registration-failed", registration.message or "Core registration failed")
  end
  available = true
  return true, nil
end

local function add_listener(name, callback)
  api.on(name, callback)
  listeners[#listeners + 1] = { name = name, callback = callback }
end

local function request(kind, extra)
  if not initialized then return nil, error_value("not-initialized", "call aardwolf-core-api.init first") end
  if not available and not loaded_core() then return nil, error_value("missing-core", "Aardwolf Core is not loaded") end
  request_counter = request_counter + 1
  local request_id = plugin_id .. ":" .. tostring(request_counter)
  local payload = copy(extra or {})
  payload.consumerId = plugin_id
  payload.requestId = request_id
  payload.kind = kind
  responses[request_id] = nil
  api.emit(EVENT_REQUEST, payload)
  local response = responses[request_id]
  responses[request_id] = nil
  if not response then return nil, error_value("missing-core", "Aardwolf Core did not answer the request") end
  if response.ok ~= true then
    return nil, error_value(response.code or "request-failed", response.message or "Core request failed")
  end
  return copy(response.data), nil
end

local function handle_ui_command(payload)
  if type(payload) ~= "table" or payload.consumerId ~= plugin_id then return end
  if payload.action ~= "show" and payload.action ~= "hide" then return end
  if payload.name == "*" then
    for name in pairs(windows) do set_window_visibility(name, payload.action == "show") end
  elseif type(payload.name) == "string" and windows[payload.name] then
    set_window_visibility(payload.name, payload.action == "show")
  end
end

local function handle_ui_query(payload)
  if type(payload) == "table" and payload.consumerId ~= nil and payload.consumerId ~= plugin_id then return end
  for _, window in pairs(windows) do update_window(window) end
end

function M.init(options)
  if initialized then
    if available then return true, nil end
    if loaded_core() then
      local ok, problem = declare()
      if ok then declare_windows() end
      return ok, problem
    end
    return nil, error_value("missing-core", "Aardwolf Core is not loaded or enabled")
  end
  if type(options) ~= "table" then return nil, error_value("invalid-options", "options must be a table") end
  if not plain_name(options.pluginId, true) then return nil, error_value("invalid-plugin-id", "pluginId is required") end
  if type(options.minProtocol) ~= "number" or options.minProtocol % 1 ~= 0 or options.minProtocol < 1 then
    return nil, error_value("invalid-protocol", "minProtocol must be a positive integer")
  end
  local required = { "on", "off", "emit", "getLoadedPlugins", "saveTable", "loadTable" }
  for _, name in ipairs(required) do
    if type(options[name]) ~= "function" then return nil, error_value("missing-api", name .. " must be injected") end
  end
  local declared, package_error = validate_packages(options.packages or {})
  if not declared then return nil, package_error end
  local incoming_ui = options.ui
  if incoming_ui ~= nil then
    if type(incoming_ui) ~= "table" then return nil, error_value("invalid-ui-adapter", "ui must be a table") end
    local ui_required = {
      "createWidget", "setWidgetProperty", "showWidget", "hideWidget", "destroyWidget",
      "setBoundValues", "registerWidgetEvent", "unregisterWidgetEvent",
      "widgetInfo", "focusPrompt",
    }
    for _, name in ipairs(ui_required) do
      if type(incoming_ui[name]) ~= "function" then
        return nil, error_value("invalid-ui-adapter", "ui." .. name .. " must be injected")
      end
    end
  end

  api = {
    on = options.on,
    off = options.off,
    emit = options.emit,
    getLoadedPlugins = options.getLoadedPlugins,
    saveTable = options.saveTable,
    loadTable = options.loadTable,
  }
  plugin_id = options.pluginId
  min_protocol = options.minProtocol
  packages = declared
  ui_api = incoming_ui
  initialized = true

  add_listener(EVENT_REGISTRATION, function(payload)
    if type(payload) == "table" and payload.consumerId == plugin_id then registration = copy(payload) end
  end)
  add_listener(EVENT_RESPONSE, function(payload)
    if type(payload) == "table" and payload.consumerId == plugin_id and type(payload.requestId) == "string" then
      responses[payload.requestId] = copy(payload)
    end
  end)
  add_listener(EVENT_DISCOVER, function()
    local ok = declare()
    if ok then declare_windows() end
  end)
  add_listener(EVENT_UI_COMMAND, handle_ui_command)
  add_listener(EVENT_UI_QUERY, handle_ui_query)

  if not loaded_core() then
    return nil, error_value("missing-core", "Aardwolf Core is not loaded or enabled")
  end
  local ok, problem = declare()
  if ok then declare_windows() end
  return ok, problem
end

function M.on(topic, callback)
  if not initialized then return nil, error_value("not-initialized", "call aardwolf-core-api.init first") end
  if type(callback) ~= "function" then return nil, error_value("invalid-callback", "callback must be a function") end
  local event_name = TOPICS[topic]
  if not event_name then return nil, error_value("unknown-topic", "unknown Core topic " .. tostring(topic)) end
  local wrapper = function(payload) callback(copy(payload)) end
  add_listener(event_name, wrapper)
  return true, nil
end

function M.get(path)
  if type(path) ~= "string" then return nil, error_value("invalid-path", "snapshot path must be a string") end
  return request("snapshot", { path = path })
end

function M.status()
  return request("status")
end

function M.refresh(requested)
  local declared, package_error = validate_packages(requested or { Char = true, Room = true })
  if not declared then return nil, package_error end
  for name, wanted in pairs(declared) do
    if wanted and name ~= "Char" and name ~= "Room" then
      return nil, error_value("invalid-refresh-package", "only Char and Room support refresh requests")
    end
  end
  return request("refresh", { packages = declared })
end

function M.renegotiate()
  return request("renegotiate")
end

function M.ui.create(config)
  if not initialized then return ui_error("not-initialized", "call aardwolf-core-api.init first") end
  if not ui_api then return ui_error("ui-unavailable", "initialize Core with a MudForge UI adapter") end
  if type(config) ~= "table" or not plain_name(config.name, false) then
    return ui_error("invalid-window", "window config requires a stable name")
  end
  if windows[config.name] then return ui_error("window-exists", "managed window " .. config.name .. " already exists") end
  if not bounded_text(config.title, 128) then return ui_error("invalid-window", "window title must be a bounded control-free string") end
  if config.type ~= "html" and config.type ~= "canvas" then
    return ui_error("invalid-window", "window type must be html or canvas")
  end
  if config.position ~= nil and not valid_point(config.position) then
    return ui_error("invalid-window", "window position is invalid")
  end
  if config.size ~= nil and not valid_size(config.size) then
    return ui_error("invalid-window", "window size is invalid")
  end
  for _, key in ipairs({ "visible", "resizable", "scrollable" }) do
    if config[key] ~= nil and type(config[key]) ~= "boolean" then
      return ui_error("invalid-window", key .. " must be a boolean")
    end
  end

  local count = 0
  for _ in pairs(windows) do count = count + 1 end
  local position = config.position or { x = 120 + count * 24, y = 100 + count * 24 }
  local size = config.size or (config.type == "html" and { width = 620, height = 560 } or { width = 400, height = 300 })
  local visible = config.visible == true
  local resizable = config.resizable ~= false
  local widget_config = {
    type = config.type,
    name = config.name,
    title = config.title,
    position = copy(position),
    size = copy(size),
    visible = visible,
    resizable = resizable,
    scrollable = config.scrollable == true,
    appearance = {
      showTitleBar = true,
      autoHideSettingsCog = true,
      movable = true,
      resizable = resizable,
      titleTextColor = UI_TOKENS.colors.primary,
      backgroundColor = UI_TOKENS.colors.background,
      backgroundOpacity = 0.96,
      borderColor = UI_TOKENS.colors.border,
      borderWidth = 1,
      borderRadius = UI_TOKENS.radius.medium,
      borderStyle = "solid",
    },
  }
  local ok_create, widget_id = pcall(ui_api.createWidget, widget_config)
  if not ok_create or type(widget_id) ~= "string" or widget_id == "" then
    return ui_error("window-create-failed", "MudForge could not create the managed window")
  end

  if config.type == "html" then
    local document, document_error = M.ui.document(config.content or "", { css = config.css or "" })
    if not document then
      pcall(ui_api.destroyWidget, widget_id)
      return nil, document_error
    end
    local ok_content = pcall(ui_api.setWidgetProperty, widget_id, "content", document)
    if not ok_content then
      pcall(ui_api.destroyWidget, widget_id)
      return ui_error("window-create-failed", "MudForge could not set the managed HTML content")
    end
  elseif config.content ~= nil or config.css ~= nil then
    pcall(ui_api.destroyWidget, widget_id)
    return ui_error("invalid-window", "canvas windows do not accept HTML content or CSS")
  end

  local window = {
    name = config.name,
    title = config.title,
    type = config.type,
    widgetId = widget_id,
    visible = visible,
    handlers = {},
  }
  windows[window.name] = window
  declare_window(window)
  return { name = window.name, widgetId = window.widgetId, type = window.type }, nil
end

function M.ui.show(name)
  return set_window_visibility(name, true)
end

function M.ui.hide(name)
  return set_window_visibility(name, false)
end

function M.ui.isVisible(name)
  local window, problem = get_window(name)
  if not window then return nil, problem end
  local ok, visible = pcall(ui_api.widgetInfo, window.widgetId, 7)
  if not ok or type(visible) ~= "boolean" then
    return ui_error("window-query-failed", "MudForge could not report managed window visibility")
  end
  window.visible = visible
  return visible, nil
end

function M.ui.toggle(name)
  local visible, problem = M.ui.isVisible(name)
  if visible == nil then return nil, problem end
  return set_window_visibility(name, not visible)
end

function M.ui.bind(name, values)
  local window, problem = get_window(name)
  if not window then return nil, problem end
  if window.type ~= "html" then return ui_error("invalid-window", "bindings are available only for HTML windows") end
  if type(values) ~= "table" then return ui_error("invalid-window", "bound values must be a table") end
  for key, value in pairs(values) do
    local kind = type(value)
    if not plain_name(key, false) or (kind ~= "string" and kind ~= "number" and kind ~= "boolean")
        or (kind == "string" and (#value > 16384 or string.find(value, "%z")))
        or (kind == "number" and not finite_number(value)) then
      return ui_error("invalid-window", "bound values must use named finite scalar values")
    end
  end
  local ok = pcall(ui_api.setBoundValues, window.widgetId, copy(values))
  if not ok then return ui_error("window-bind-failed", "MudForge could not update managed window bindings") end
  return true, nil
end

function M.ui.on(name, event_name, callback)
  local window, problem = get_window(name)
  if not window then return nil, problem end
  local allowed = {
    action = true, click = true, keydown = true, submit = true,
    resize = true, move = true, mousedown = true, mouseup = true, mousemove = true,
  }
  if not allowed[event_name] then return ui_error("invalid-window", "unsupported widget event " .. tostring(event_name)) end
  if type(callback) ~= "function" then return ui_error("invalid-window", "widget callback must be a function") end
  local wrapper = function(event)
    callback(copy(event or {}))
    if event_name == "action" then pcall(ui_api.focusPrompt) end
  end
  local ok = pcall(ui_api.registerWidgetEvent, window.widgetId, event_name, wrapper)
  if not ok then return ui_error("window-event-failed", "MudForge could not register the widget event") end
  window.handlers[event_name] = window.handlers[event_name] or {}
  table.insert(window.handlers[event_name], wrapper)
  return true, nil
end

function M.ui.destroy(name)
  local window, problem = get_window(name)
  if not window then return nil, problem end
  for event_name, handlers in pairs(window.handlers) do
    for _, handler in ipairs(handlers) do
      pcall(ui_api.unregisterWidgetEvent, window.widgetId, event_name, handler)
    end
  end
  local ok = pcall(ui_api.destroyWidget, window.widgetId)
  if not ok then return ui_error("window-destroy-failed", "MudForge could not destroy the managed window") end
  withdraw_window(window)
  windows[name] = nil
  return true, nil
end

local function storage_key(name)
  if not plain_name(name, false) then return nil, error_value("invalid-storage-name", "storage name must use letters, digits, dot, dash, or underscore") end
  return "aardwolf:" .. plugin_id .. ":" .. name, nil
end

local function storage_scope(scope)
  if scope == nil or scope == "world" then return nil, nil end
  if scope == "global" then return "global", nil end
  return nil, error_value("invalid-storage-scope", "scope must be world or global")
end

function M.storage.save(name, schema_version, data, scope)
  if not initialized then return nil, error_value("not-initialized", "call aardwolf-core-api.init first") end
  if type(schema_version) ~= "number" or schema_version % 1 ~= 0 or schema_version < 1 then
    return nil, error_value("invalid-schema", "schema version must be a positive integer")
  end
  if type(data) ~= "table" then return nil, error_value("invalid-data", "stored data must be a table") end
  local key, key_error = storage_key(name)
  if not key then return nil, key_error end
  local resolved_scope, scope_error = storage_scope(scope)
  if scope_error then return nil, scope_error end
  local envelope = { format = 1, owner = plugin_id, schema = schema_version, data = copy(data), deleted = false }
  local ok, saved
  if resolved_scope then ok, saved = pcall(api.saveTable, key, envelope, resolved_scope)
  else ok, saved = pcall(api.saveTable, key, envelope) end
  if not ok or saved ~= true then return nil, error_value("storage-save-failed", "MudForge did not persist the storage envelope") end
  return true, nil
end

function M.storage.load(name, expected_schema, scope)
  if not initialized then return nil, error_value("not-initialized", "call aardwolf-core-api.init first") end
  if type(expected_schema) ~= "number" or expected_schema % 1 ~= 0 or expected_schema < 1 then
    return nil, error_value("invalid-schema", "expected schema must be a positive integer")
  end
  local key, key_error = storage_key(name)
  if not key then return nil, key_error end
  local resolved_scope, scope_error = storage_scope(scope)
  if scope_error then return nil, scope_error end
  local ok, envelope
  if resolved_scope then ok, envelope = pcall(api.loadTable, key, resolved_scope)
  else ok, envelope = pcall(api.loadTable, key) end
  if not ok then return nil, error_value("storage-load-failed", "MudForge could not load the storage envelope") end
  if envelope == nil then return nil, nil end
  if type(envelope) ~= "table" or envelope.format ~= 1 or envelope.owner ~= plugin_id then
    return nil, error_value("invalid-envelope", "stored value is not an owned Aardwolf Core envelope")
  end
  if envelope.deleted == true then return nil, nil end
  if envelope.schema ~= expected_schema then
    return nil, error_value("schema-mismatch", "stored schema " .. tostring(envelope.schema) .. " does not match expected schema " .. tostring(expected_schema))
  end
  if type(envelope.data) ~= "table" then return nil, error_value("invalid-envelope", "stored envelope data is invalid") end
  return copy(envelope.data), nil
end

function M.storage.delete(name, scope)
  if not initialized then return nil, error_value("not-initialized", "call aardwolf-core-api.init first") end
  local key, key_error = storage_key(name)
  if not key then return nil, key_error end
  local resolved_scope, scope_error = storage_scope(scope)
  if scope_error then return nil, scope_error end
  local envelope = { format = 1, owner = plugin_id, schema = 1, data = {}, deleted = true }
  local ok, saved
  if resolved_scope then ok, saved = pcall(api.saveTable, key, envelope, resolved_scope)
  else ok, saved = pcall(api.saveTable, key, envelope) end
  if not ok or saved ~= true then return nil, error_value("storage-delete-failed", "MudForge did not persist the deletion marker") end
  return true, nil
end

function M.cleanup()
  if not initialized then return end
  local names = {}
  for name in pairs(windows) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do M.ui.destroy(name) end
  if available then api.emit(EVENT_WITHDRAW, { consumerId = plugin_id }) end
  for _, listener in ipairs(listeners) do api.off(listener.name, listener.callback) end
  listeners = {}
  responses = {}
  registration = nil
  available = false
  initialized = false
  api = nil
  ui_api = nil
  plugin_id = nil
  packages = {}
  windows = {}
end

return M

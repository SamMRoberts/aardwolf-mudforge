library = {
  name = "aardwolf-core-api",
  version = "0.1.0",
  description = "Consumer API for the Aardwolf Core MudForge plugin.",
  author = "Sam Roberts",
  license = "MIT",
}

local M = { storage = {} }
local PROTOCOL_VERSION = 1
local EVENT_DISCOVER = "aardwolf.core.consumer.discover"
local EVENT_DECLARE = "aardwolf.core.consumer.declare"
local EVENT_WITHDRAW = "aardwolf.core.consumer.withdraw"
local EVENT_REGISTRATION = "aardwolf.core.consumer.registration"
local EVENT_REQUEST = "aardwolf.core.request"
local EVENT_RESPONSE = "aardwolf.core.response"
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
}
local ALLOWED_PACKAGES = { Core = true, Char = true, Comm = true, Room = true, Group = true }

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

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("cyclic table", 0) end
  seen[value] = true
  local result = {}
  for key, item in pairs(value) do
    if type(item) == "table" then result[key] = copy(item, seen)
    elseif item ~= nil then result[key] = item end
  end
  seen[value] = nil
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

function M.init(options)
  if initialized then
    if available then return true, nil end
    if loaded_core() then return declare() end
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
    declare()
  end)

  if not loaded_core() then
    return nil, error_value("missing-core", "Aardwolf Core is not loaded or enabled")
  end
  return declare()
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
  if available then api.emit(EVENT_WITHDRAW, { consumerId = plugin_id }) end
  for _, listener in ipairs(listeners) do api.off(listener.name, listener.callback) end
  listeners = {}
  responses = {}
  registration = nil
  available = false
  initialized = false
  api = nil
  plugin_id = nil
  packages = {}
end

return M

TEST = {
  clock = 10,
  sessionId = "session-1",
  connected = false,
  events = {},
  gmcpHandlers = {},
  commands = {},
  timers = {},
  nextTimer = 0,
  sentGMCP = {},
  sendGMCPResult = true,
  widgets = {},
  nextWidget = 0,
  echoes = {},
  themes = {},
  activeTheme = nil,
  themeCalls = 0,
  activeWidget = nil,
  draws = {},
  tables = { world = {}, global = {} },
  loadedPlugins = {
    { id = "aardwolf-core", name = "Aardwolf Core", version = "0.2.1", enabled = true },
    { id = "test-consumer", name = "Test Consumer", version = "1.0.0", enabled = true },
  },
}

os.clock = function() return TEST.clock end

local function clone(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then error("cycle") end
  seen[value] = true
  local result = {}
  for key, item in pairs(value) do result[key] = clone(item, seen) end
  seen[value] = nil
  return result
end

function on(name, callback)
  TEST.events[name] = TEST.events[name] or {}
  table.insert(TEST.events[name], callback)
end

function off(name, callback)
  local handlers = TEST.events[name] or {}
  if callback == nil then TEST.events[name] = {}; return end
  local kept = {}
  for _, handler in ipairs(handlers) do
    if handler ~= callback then table.insert(kept, handler) end
  end
  TEST.events[name] = kept
end

function emit(name, payload)
  local handlers = TEST.events[name] or {}
  local snapshot = {}
  for _, handler in ipairs(handlers) do table.insert(snapshot, handler) end
  for _, handler in ipairs(snapshot) do handler(payload) end
end

function onGMCPUpdate(name, callback)
  TEST.gmcpHandlers[name] = TEST.gmcpHandlers[name] or {}
  table.insert(TEST.gmcpHandlers[name], callback)
end

function TEST.fireGMCP(name, payload)
  for _, callback in ipairs(TEST.gmcpHandlers[name] or {}) do callback(payload) end
end

function sendGMCP(package_name, data)
  table.insert(TEST.sentGMCP, { package = package_name, data = clone(data) })
  return TEST.sendGMCPResult
end

function getSessionId() return TEST.sessionId end
function getLoadedPlugins() return clone(TEST.loadedPlugins) end

function addTimer(delay, callback, repeating)
  if not TEST.connected then return "" end
  TEST.nextTimer = TEST.nextTimer + 1
  local id = "timer-" .. tostring(TEST.nextTimer)
  TEST.timers[id] = { due = TEST.clock * 1000 + delay, callback = callback, repeating = repeating, delay = delay }
  return id
end

function removeTimer(id) TEST.timers[id] = nil end

function TEST.advance(milliseconds)
  TEST.clock = TEST.clock + milliseconds / 1000
  local fired = true
  while fired do
    fired = false
    local due_id = nil
    local due_time = nil
    for id, timer in pairs(TEST.timers) do
      if timer.due <= TEST.clock * 1000 and (due_time == nil or timer.due < due_time) then
        due_id, due_time = id, timer.due
      end
    end
    if due_id then
      local timer = TEST.timers[due_id]
      if timer.repeating then timer.due = timer.due + timer.delay else TEST.timers[due_id] = nil end
      timer.callback()
      fired = true
    end
  end
end

function registerCommand(name, callback, description)
  TEST.commands[name] = { callback = callback, description = description }
end

function echo(message) table.insert(TEST.echoes, tostring(message)) end

function createWidget(config)
  TEST.nextWidget = TEST.nextWidget + 1
  local id = "widget-" .. tostring(TEST.nextWidget)
  TEST.widgets[id] = {
    config = clone(config), properties = {}, events = {}, visible = config.visible ~= false, bindings = {},
    x = config.position and config.position.x or 200,
    y = config.position and config.position.y or 150,
    width = config.size and config.size.width or config.width or 400,
    height = config.size and config.size.height or config.height or 300,
    appearance = clone(config.appearance or {}),
  }
  return id
end

function setWidgetProperty(id, name, value) TEST.widgets[id].properties[name] = value end
function getWidgetProperty(id, name) return TEST.widgets[id].properties[name] end
function showWidget(id) TEST.widgets[id].visible = true end
function hideWidget(id) TEST.widgets[id].visible = false end
function destroyWidget(id) TEST.widgets[id] = nil end
function setBoundValues(id, values) TEST.widgets[id].bindings = clone(values) end
function registerWidgetEvent(id, name, callback) TEST.widgets[id].events[name] = callback end
function unregisterWidgetEvent(id, name, callback)
  if TEST.widgets[id] and (callback == nil or TEST.widgets[id].events[name] == callback) then
    TEST.widgets[id].events[name] = nil
  end
end
function setWidgetAppearance(id, appearance)
  for key, value in pairs(appearance) do TEST.widgets[id].appearance[key] = clone(value) end
end
function widgetInfo(id, info_type)
  local current = TEST.widgets[id]
  if not current then return nil end
  if info_type == 3 then return current.width end
  if info_type == 4 then return current.height end
  if info_type == 7 then return current.visible end
  if info_type == 10 then return current.config.type end
  if info_type == 15 then return current.x end
  if info_type == 16 then return current.y end
  if info_type == 18 then return current.config.owner or plugin and plugin.id end
  if info_type == 19 then return current.config.title end
  if info_type == 20 then return id end
  return nil
end
function focusPrompt() TEST.focused = true end

function setActiveWidget(id) TEST.activeWidget = id end
function getWidgetFont(id) return { family = "fira-code", size = 14, weight = "normal", css = "14px fira-code" } end
function clear(color) table.insert(TEST.draws, { kind = "clear", widget = TEST.activeWidget, color = color }) end
function drawRect(x, y, width, height, color, stroke)
  table.insert(TEST.draws, { kind = "rect", widget = TEST.activeWidget, x = x, y = y, width = width, height = height, color = color, stroke = stroke })
end
function drawText(value, x, y, color, font)
  table.insert(TEST.draws, { kind = "text", widget = TEST.activeWidget, value = value, x = x, y = y, color = color, font = font })
end

function registerTheme(theme)
  TEST.themeCalls = TEST.themeCalls + 1
  TEST.themes[theme.id] = clone(theme)
  return theme.id
end

function setTheme(theme_id)
  if not TEST.themes[theme_id] then return false end
  TEST.activeTheme = theme_id
  return true
end

function saveTable(name, value, scope)
  local bucket = scope == "global" and TEST.tables.global or TEST.tables.world
  bucket[name] = clone(value)
  return true
end

function loadTable(name, scope)
  local bucket = scope == "global" and TEST.tables.global or TEST.tables.world
  return clone(bucket[name])
end

function TEST.request(consumer_id, kind, extra)
  local response = nil
  local callback = function(payload)
    if payload.consumerId == consumer_id and payload.requestId == "test-request" then response = clone(payload) end
  end
  on("aardwolf.core.response", callback)
  local request = clone(extra or {})
  request.consumerId = consumer_id
  request.requestId = "test-request"
  request.kind = kind
  emit("aardwolf.core.request", request)
  off("aardwolf.core.response", callback)
  return response
end

function TEST.assert_equal(actual, expected, label)
  if actual ~= expected then
    error((label or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 0)
  end
end

function TEST.assert_true(value, label)
  if value ~= true then error((label or "expected true") .. ": got " .. tostring(value), 0) end
end

function TEST.assert_nil(value, label)
  if value ~= nil then error((label or "expected nil") .. ": got " .. tostring(value), 0) end
end

plugin = {
  id = "aardwolf-ui-reference",
  name = "Aardwolf UI Reference",
  version = "0.2.0",
  author = "Sam Roberts",
  description = "Non-distributed HTML and canvas example for Aardwolf Core managed windows.",
  settings = { saveState = false },
}

local loaded, core = pcall(require, "aardwolf-core-api")
local canvas_id = nil

local function draw_canvas(width, height)
  if not canvas_id then return end
  local tokens = core.ui.tokens()
  local font = getWidgetFont(canvas_id)
  setActiveWidget(canvas_id)
  clear(tokens.colors.background)
  drawRect(12, 12, width - 24, height - 24, tokens.colors.surface, tokens.colors.border)
  drawText("Aardwolf canvas", 28, 44, tokens.colors.primary, font.css)
  drawText("Resize me to redraw", 28, 70, tokens.colors.muted, font.css)
end

function init()
  if not loaded then
    echo("Aardwolf UI Reference requires the aardwolf-core-api library.")
    return
  end

  local ok, problem = core.init({
    pluginId = plugin.id,
    minProtocol = 1,
    packages = {},
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
  })
  if not ok then
    echo("Aardwolf UI Reference could not start: " .. tostring(problem.message))
    return
  end

  local html, html_error = core.ui.create({
    name = "reference-html",
    title = "Aardwolf HTML Reference",
    type = "html",
    position = { x = 160, y = 120 },
    size = { width = 440, height = 260 },
    content = [[
      <h1 class="aw-title">Managed HTML</h1>
      <section class="aw-section">
        <p data-mud-bind="message">Waiting for a bound value.</p>
        <div class="aw-toolbar"><button class="aw-button aw-button--primary" type="button" data-mud-action="acknowledge">Acknowledge</button></div>
      </section>
    ]],
  })
  if not html then
    echo("HTML reference window failed: " .. tostring(html_error.message))
    core.cleanup()
    return
  end
  core.ui.bind("reference-html", { message = "Dynamic text is supplied through a binding." })
  core.ui.on("reference-html", "action", function(event)
    if event.action == "acknowledge" then
      core.ui.bind("reference-html", { message = "Acknowledged without replacing the document." })
    end
  end)

  local canvas, canvas_error = core.ui.create({
    name = "reference-canvas",
    title = "Aardwolf Canvas Reference",
    type = "canvas",
    position = { x = 620, y = 120 },
    size = { width = 360, height = 180 },
  })
  if not canvas then
    echo("Canvas reference window failed: " .. tostring(canvas_error.message))
    core.cleanup()
    return
  end
  canvas_id = canvas.widgetId
  draw_canvas(360, 180)
  core.ui.on("reference-canvas", "resize", function(event)
    draw_canvas(event.width, event.height)
  end)

  registerCommand("awui-reference", function(args)
    if string.lower(args or "") == "hide" then
      core.ui.hide("reference-html")
      core.ui.hide("reference-canvas")
    else
      core.ui.show("reference-html")
      core.ui.show("reference-canvas")
    end
  end, "Show or hide the non-distributed Aardwolf UI reference windows")
end

function cleanup()
  canvas_id = nil
  if loaded then core.cleanup() end
end

# Aardwolf for MudForge

This repository contains a clean-room Aardwolf plugin framework for
[MudForge](https://mudforge.org/). The framework consists of:

- **Aardwolf Core** (`aardwolf-core`) — the sole owner of Aardwolf
  `Core.Supports.Set`, validated `Char.*` and `Room.Info` session data, and
  the control center for associated plugin windows and framework diagnostics.
- **Aardwolf Core API** (`aardwolf-core-api`) — the shared library future
  Aardwolf plugins use for dependency checks, events, snapshots, refreshes,
  namespaced persistence, managed windows, and shared visual resources.

Version 0.2.1 requires MudForge 1.2.2454. Offline checks do not prove native
rendering, transport, or persistence; the native target remains MudForge
1.2.2454 on macOS.

## Install

### Plugin repository

Build or use the checked-in `dist/plugin-repo` directory, then add this GitHub
folder in MudForge's Plugin Manager:

```text
https://github.com/SamMRoberts/aardwolf-mudforge/tree/main/dist/plugin-repo
```

Install the `aardwolf-core-api` library from the repository's Libraries view,
then install and enable `Aardwolf Core` for each Aardwolf world.

### Atomic package

The deterministic build stages the exact plugin and library sources under
`dist/native-package-input`. The final `.mfp` must be created with MudForge's
**Settings → Packages → Create Package** workflow and verified before it is
published. This repository does not disguise a hand-built ZIP as a validated
MudForge package.

## Use from another plugin

```lua
local loaded, core = pcall(require, "aardwolf-core-api")

function init()
  if not loaded then
    echo("This plugin requires the aardwolf-core-api library.")
    return
  end

  local ok, problem = core.init({
    pluginId = plugin.id,
    minProtocol = 1,
    packages = { Char = true },
    on = on,
    off = off,
    emit = emit,
    getLoadedPlugins = getLoadedPlugins,
    saveTable = saveTable,
    loadTable = loadTable,
    -- Add the optional ui table below when this plugin owns managed windows.
  })
  if not ok then
    echo("Aardwolf Core unavailable: " .. tostring(problem.message))
    return
  end

  core.on("char.vitals", function(update)
    local hp = update.normalized.hp
    if hp ~= nil then echo("HP: " .. tostring(hp)) end
  end)
end

function cleanup()
  if loaded then core.cleanup() end
end
```

See [docs/CORE.md](docs/CORE.md) for the complete contract.

## Managed windows

Associated plugins inject MudForge's widget functions through `core.init`, then
create their own HTML or canvas widgets through `core.ui`. Core supplies the
dark navy/gold design tokens, lifecycle, visibility controls, and central
registry without taking ownership of the consumer's callbacks or saved layout.

```lua
local ok, problem = core.init({
  pluginId = plugin.id,
  minProtocol = 1,
  packages = {},
  on = on, off = off, emit = emit,
  getLoadedPlugins = getLoadedPlugins,
  saveTable = saveTable, loadTable = loadTable,
  ui = {
    createWidget = createWidget, setWidgetProperty = setWidgetProperty,
    showWidget = showWidget, hideWidget = hideWidget,
    destroyWidget = destroyWidget, setBoundValues = setBoundValues,
    registerWidgetEvent = registerWidgetEvent,
    unregisterWidgetEvent = unregisterWidgetEvent,
    widgetInfo = widgetInfo, focusPrompt = focusPrompt,
  },
})

local window = core.ui.create({
  name = "status",
  title = "Aardwolf Status",
  type = "html",
  content = [[<p data-mud-bind="message">Waiting</p>]],
})
core.ui.bind("status", { message = "Ready" })
```

Dynamic game and user values belong in bindings, not HTML or CSS strings. See
the non-distributed [reference consumer](examples/aardwolf-ui-consumer.lua) for
HTML actions, canvas drawing and resize handling, show/hide commands, and
cleanup.

## Core commands

- `awcore` — show the managed-window control center, settings, and diagnostics.
- `awcore status` — connection, session, version, and package summary.
- `awcore gmcp` — negotiated packages and consumer declarations.
- `awcore refresh` — request fresh `Char.*` and `Room.Info` data.
- `awcore diagnostics` — print bounded diagnostics.
- `awcore renegotiate` — explicitly resend the current package union.

Core never enables tags, GMCP-only channels, or server debug automatically.

## Development

```bash
env npm_config_cache=/tmp/aardwolf-core-npm-cache npm install
npm test
npm run build
npm run build:check
```

The test harness parses sources as Lua 5.1 and executes logic with injected
APIs. It does not emulate MudForge's Lua-to-JavaScript transpiler or native UI.
See [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) for the staged evidence boundary.

## License

[MIT](LICENSE)

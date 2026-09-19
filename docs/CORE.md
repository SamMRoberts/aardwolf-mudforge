# Aardwolf Core contract

## Ownership

`aardwolf-core` is the exclusive `Core.Supports.Set` owner for this framework.
Aardwolf replaces its supported-package set rather than merging separate
senders, so dependent plugins declare requirements through the API library and
must not send their own supports set.

The baseline is always `Core`, `Char`, and `Room`. Consumers may add `Comm` and
`Group`. Core sends the stable union once after connection and again only when
the union changes or the user explicitly requests renegotiation. It never
automatically enables `gmcpchannels`, tags, or server debug.

After the first successful negotiation in a connection lifetime, Core sends
one `request char` and one `request room`. The bootstrap latch is set before
those requests, preventing the returned `Char.Base` packet from reopening the
negotiation path. Transport refusal receives one delayed retry and then remains
visible as a diagnostic until a user action or declaration change retries it.

## Dependency handshake

The plugin contract version is the integer `1`; plugin and library release
versions are independently reported as `0.2.1`. Consumers initialize the
library with their stable plugin id, minimum protocol, package set, and only
the host functions the library needs.

`core.init(options)` returns `true` or `nil, error`. Errors are tables with
`code`, `message`, and `protocol`; important codes include `missing-core`,
`unsupported-protocol`, `invalid-package`, and `consumer-not-loaded`.

Core broadcasts discovery during initialization and connection. A library
instance answers discovery by repeating its idempotent declaration, covering
both Core-first and consumer-first load orders. `core.cleanup()` withdraws the
declaration and removes the library's event handlers.

## Live data

Core subscribes to:

- `Char.Base`
- `Char.Vitals`
- `Char.Stats`
- `Char.MaxStats`
- `Char.Status`
- `Char.Worth`
- `Room.Info`

Every accepted update publishes a normalized table containing documented
fields and a bounded raw table that may contain safe unknown fields. Known
numeric fields must be finite exact integers. Known strings are bounded and
must not contain control characters. Room exits and coordinates are validated
recursively.

An invalid update is rejected atomically. It increments the rejected counter,
emits a diagnostic, and leaves the prior accepted snapshot intact. Snapshots
and freshness are cleared on connect, disconnect, cleanup, or a GMCP update
that establishes a new session after a mid-session reload. They are never
stored on disk. Defensive copies track ancestor identity with a linear stack,
which accepts ordinary nested GMCP objects while still rejecting genuine
recursive tables in MudForge's JavaScript-transpiled runtime.

### Topics

`core.on(topic, callback)` accepts:

- `ready`, `session`, `reset`, `diagnostic`
- `char.updated`
- `char.base`, `char.vitals`, `char.stats`, `char.maxstats`, `char.status`,
  `char.worth`
- `room` or `room.info`

The library gives each consumer callback a defensive copy. Update payloads
include `protocol`, `sessionId`, `session`, `sequence`, `fresh`, `normalized`,
and `raw`; character updates also include `group`.

`core.get("char.vitals")` and the other character paths return the latest
fresh snapshot. `core.get("room")` and `core.get("room.info")` return the room
snapshot. Missing or stale data returns `nil, error`; it never invents zeros or
empty strings.

`core.status()` returns versions, connection and session state, negotiated
packages, declarations, freshness, counters, diagnostics, and log level.

`core.refresh({ Char = true, Room = true })` requests fresh data through Core.
`core.renegotiate()` explicitly resends the package union, subject to Core's
rate limit.

## Managed windows and visual design

Core UI contract version 1 supports HTML and canvas widgets on MudForge
1.2.2454 or newer. Each associated plugin remains the MudForge owner of its
widgets and callbacks. The API library provides consistent creation, styling,
lifecycle, visibility, and registration; Core's control center brokers only
validated show/hide commands.

Consumers that need windows add an optional `ui` adapter to `core.init`:

```lua
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
}
```

Existing consumers may omit this table. Stateful UI calls then return
`ui-unavailable`; data, events, requests, and storage remain available.

### UI functions

- `core.ui.create(config)` creates a uniquely named `html` or `canvas` window
  and returns `{ name, widgetId, type }`. Initial `position`, `size`,
  `visible`, `resizable`, and `scrollable` values are optional. Windows start
  hidden and resizable by default.
- `core.ui.show(name)`, `hide(name)`, `toggle(name)`, and `isVisible(name)`
  control and inspect a managed window without changing its geometry.
- `core.ui.bind(name, values)` updates HTML text, style, and attribute bindings
  through MudForge's binding API without rebuilding the document. Binding keys
  are stable names and values are bounded strings, finite numbers, or booleans.
- `core.ui.on(name, event, callback)` registers actions, resize/move handlers,
  and canvas pointer handlers. HTML actions return focus to the command prompt.
- `core.ui.destroy(name)` unregisters callbacks, destroys the widget, and
  withdraws it from Core. `core.cleanup()` destroys all remaining windows.
- `core.ui.tokens()` returns a defensive copy of the canonical palette,
  spacing, typography, focus, and radius values for canvas drawing or custom
  layout.
- `core.ui.document(content, { css = "..." })` wraps trusted static plugin
  markup in the shared stylesheet. It is stateless and can be used before
  `core.init`; external values must still use bindings.
- `core.ui.appTheme()` returns the app-wide `aardwolf-dark` theme definition.
  It deliberately omits `terminalColors`.

Important errors include `ui-unavailable`, `invalid-window`, `window-exists`,
and `unknown-window`. Window names use letters, digits, dots, dashes, and
underscores and are registered with Core as `<consumerId>:<name>`.

The shared HTML stylesheet exposes `.aw-root`, `.aw-title`, `.aw-heading`,
`.aw-section`, `.aw-toolbar`, `.aw-grid`, `.aw-label`, `.aw-value`,
`.aw-button` variants, `.aw-field`, `.aw-status`, `.aw-muted`, semantic status
colors, `.aw-scroll`, and window-row helpers. Plugin-specific CSS is permitted
only as trusted static source and should use these tokens and namespaced
selectors.

Core tracks window metadata only in memory. MudForge remains responsible for
per-device position and size, and Core never moves or resizes an established
window. The control center refreshes native visibility with `widgetInfo`, lists
registered windows, and offers individual and show-all/hide-all controls.

Applying the matching MudForge app theme is always an explicit control-center
action. Core never registers or applies it during initialization, enablement,
connection, or discovery. The action affects the app-wide interface and is
persisted by MudForge, but leaves the user's terminal palette alone.

## Storage

The library wraps MudForge `saveTable` and `loadTable` with keys of the form:

```text
aardwolf:<consumer-plugin-id>:<name>
```

```lua
core.storage.save("preferences", 2, value, "world")
local value, problem = core.storage.load("preferences", 2, "world")
core.storage.delete("preferences", "world")
```

Scopes are `world` (the default) and `global`. Every value is stored in an
envelope containing format, owner, schema, data, and deletion state. A schema
mismatch is returned to the consumer; the library never guesses or runs a
migration. Delete writes an owned tombstone because MudForge does not document
a table-deletion API.

Global storage is shared by every plugin and world at the host level, making
the consumer-id prefix mandatory. Live GMCP snapshots never use this storage.

## Compatibility

- Stable plugin id: `aardwolf-core`
- Stable library name: `aardwolf-core-api`
- Protocol: `1`
- UI contract: `1`
- Minimum MudForge: `1.2.2454`
- License: MIT

Changing the plugin id or library name is breaking. A future incompatible
contract requires a new protocol version while compatible additions retain
protocol 1.

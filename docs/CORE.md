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
versions are independently reported as `0.1.0`. Consumers initialize the
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
stored on disk.

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
- Minimum MudForge: `1.2.0`
- License: MIT

Changing the plugin id or library name is breaking. A future incompatible
contract requires a new protocol version while compatible additions retain
protocol 1.

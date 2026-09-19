# Aardwolf Chat

`aardwolf-chat` is a receive-only consumer of Aardwolf Core's validated
`comm.channel` topic. It never subscribes to `Comm.Channel` directly, changes
Core negotiation, sends player chat, gags terminal lines, or interprets message
text as HTML.

## Windows and commands

The plugin owns two Core-managed HTML windows: `chat` and `chat-settings`.
Both use Core's shared visual tokens, safe text bindings, visibility registry,
and lifecycle cleanup. The chat window starts visible; settings starts hidden.

```text
awchat
awchat show
awchat hide
awchat settings
awchat status
awchat reset
awchat history on|off
awchat takeover on|off
awchat tab add <label>
awchat tab rename <id> <label>
awchat tab channels <id> <comma-separated channels>
awchat tab move <id> up|down
awchat tab delete <id>
```

Settings buttons use the same mutation and validation paths. Actions needing
free text prefill the corresponding command in MudForge's prompt so the user
can review it before execution.

## Routing

The default tabs are:

| Tab | Channels |
| --- | --- |
| All | `*` |
| Tell | `tell` |
| Group | `gtell` |
| Clan | `clantalk`, `gclan`, `claninfo` |
| Newbie | `newbie`, `helper`, `nobletalk`, `question`, `answer` |
| Gossip | `gossip` |

Tabs are ordered and may overlap. Every matching tab receives the message and
inactive matches gain unread counts. At least one tab must retain `*`, ensuring
unknown or newly introduced Aardwolf channel identifiers remain visible.
Configurations allow 1–24 tabs and 1–64 lowercase alphanumeric, underscore, or
dash channel identifiers per tab.

The displayed form is `[channel] player: message`, omitting the player prefix
when absent. ANSI and Aardwolf raw color codes plus remaining control characters
are removed. The resulting external text is passed only through Core bindings;
it is never concatenated into the trusted widget document.

## History and GMCP-only delivery

History is session-only by default and clears on Core connection resets. The
shared store is capped at 1,000 messages and 512 KiB; the active transcript
shows the newest complete lines that fit Core's 16 KiB binding limit.

`awchat history on` opts into per-world persistence under Core's namespaced
`aardwolf:aardwolf-chat:history` envelope. Writes are batched for two seconds.
Disabling persistence writes Core's owned deletion tombstone immediately.

Normal Aardwolf terminal channel output is preserved by default. The separate
`awchat takeover on` opt-in dispatches `gmcpchannels on` once for each connected
session. Disabling takeover or orderly plugin cleanup dispatches
`gmcpchannels off` while connected. Dispatch is reported as a request only;
the command has no acknowledgement contract. Hiding the window does not change
reception or takeover state.

## Evidence boundary

Lua 5.1 and injected-API tests cover routing, configuration, storage envelopes,
bounds, reload, takeover dispatch, dependency recovery, widget ownership, and
cleanup. They do not establish MudForge's native HTML rendering, real form or
action payloads, disk persistence, transport negotiation, or connected Aardwolf
delivery. See [ACCEPTANCE.md](ACCEPTANCE.md) for the separate native and live
checks.

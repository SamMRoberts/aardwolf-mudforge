# Acceptance and evidence

## Offline

The repository's offline suite establishes:

- Lua 5.1 syntax parsing for both plugins and the library source.
- Injected-API execution of lifecycle, negotiation, validation, resets,
  request/response, managed HTML/canvas windows, dependency failures, and
  storage envelopes.
- Reference-consumer execution covering bindings, actions, canvas redraw,
  visibility, and cleanup.
- Chat execution covering defaults, validation, overlapping routes, unread
  state, safe bound text, bounded history, opt-in storage, takeover dispatch,
  dependency recovery, reload, and cleanup.
- Deterministic repository output with byte-exact source copies, hashes, sizes,
  identities, and versions.

Run:

```bash
npm test
npm run build
npm run build:check
```

These checks do not establish MudForge transpilation, transport, native widget
rendering, event payloads, disk persistence, or package install behavior.

## Native disposable-world acceptance

Native work requires explicit approval before controlling MudForge. Use a
named disposable world and record the selected-world baseline and backup before
any import.

1. Confirm the disposable client is MudForge 1.2.2454 or newer. Install the
   repository library and both plugins; verify displayed version 0.4.0.
2. Load the non-distributed reference consumer. Reload, disable, and re-enable
   Core and the consumer independently. Confirm one control center, two
   reference windows, and one callback per action; no stale registry rows or
   widgets remain after consumer disable.
3. Exercise every control-center and reference button with mouse and keyboard.
   Verify bound text is escaped, focus returns to the prompt, HTML stays stable,
   canvas redraws on resize, and moved/resized geometry is retained after
   hide/show and reload.
4. Verify individual and show-all/hide-all controls target only registered
   windows. Close a window with native chrome, refresh the control center, and
   confirm the reported visibility matches `widgetInfo`.
5. Confirm no theme is registered or applied automatically. Use the explicit
   action to register/apply Aardwolf Dark, verify Settings shows it as the
   app-wide theme, and confirm the terminal palette is unchanged.
6. Save world and global storage envelopes, restart the disposable world, and
   compare values and schema failures.
7. Connect two isolated loopback sessions. Verify exact `Core.Supports.Set`
   ordering, one bootstrap refresh per connection, partial and malformed
   Char/Room/Group/Comm packets, replace-on-update Group membership, event-only
   Comm delivery, disconnect resets, declaration changes, and session isolation.
8. Open Chat and its settings window. Verify mouse and keyboard tab selection,
   command-prefill actions, unread counts, horizontal tab scrolling, bound text
   escaping, focus return, resize, hide/show, and retained native geometry.
9. Verify session-only history clears on reconnect. Opt into history, receive
   fixture messages, restart the disposable world, and confirm bounded replay;
   disable history and confirm it no longer returns. Verify takeover is off by
   default and that loopback sees one on/off control command per lifecycle.
10. Create the atomic package through **Settings → Packages → Create Package**,
   including exactly `aardwolf-core`, `aardwolf-chat`, and `aardwolf-core-api`
   with package id `com.samroberts.aardwolf-core`, version 0.4.0, and minimum
   client 1.2.2454.
11. Save the export as `dist/aardwolf-core-0.4.0.mfp`, then run:

   ```bash
   python3 tools/build_release.py --verify-package dist/aardwolf-core-0.4.0.mfp
   ```

12. Import, update, and uninstall that package in the disposable world. Confirm
   unrelated worlds, data, plugins, maps, and layout remain unchanged.

## Connected Aardwolf acceptance

Connected gameplay is a separate authorization boundary. When authorized,
verify actual Aardwolf negotiation and delivery of all Char groups, Room.Info,
Group, Comm.Channel, Comm.Tick, Comm.Quest, and Comm.Repop. Do not enable
GMCP-only channels unless the takeover check is separately authorized. Do not
send test chat messages, enable tags or server debug, move, or automate gameplay.
Record live evidence separately from the offline and
disposable-native results.

Cross-platform support is structural until each platform completes equivalent
native checks.

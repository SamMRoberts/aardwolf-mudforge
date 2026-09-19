# Acceptance and evidence

## Offline

The repository's offline suite establishes:

- Lua 5.1 syntax parsing for plugin and library sources.
- Injected-API execution of lifecycle, negotiation, validation, resets,
  request/response, widget state, dependency failures, and storage envelopes.
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

1. Install the repository library and plugin; verify displayed version 0.1.0.
2. Load, reload, disable, and re-enable. Confirm one widget, one command, and
   one callback per source; no stale resources remain after disable.
3. Exercise every button with mouse and keyboard. Verify bound text is escaped,
   focus returns to the prompt, resizing works, and moved/resized geometry is
   retained after reopen.
4. Save world and global storage envelopes, restart the disposable world, and
   compare values and schema failures.
5. Connect two isolated loopback sessions. Verify exact `Core.Supports.Set`
   ordering, one bootstrap refresh per connection, partial and malformed
   packets, disconnect resets, declaration changes, and session isolation.
6. Create the atomic package through **Settings → Packages → Create Package**,
   including exactly `aardwolf-core` and `aardwolf-core-api` with package id
   `com.samroberts.aardwolf-core`, version 0.1.0, and minimum client 1.2.0.
7. Save the export as `dist/aardwolf-core-0.1.0.mfp`, then run:

   ```bash
   python3 tools/build_release.py --verify-package dist/aardwolf-core-0.1.0.mfp
   ```

8. Import, update, and uninstall that package in the disposable world. Confirm
   unrelated worlds, data, plugins, maps, and layout remain unchanged.

## Connected Aardwolf acceptance

Connected gameplay is a separate authorization boundary. When authorized,
verify actual Aardwolf negotiation and delivery of all Char groups and
Room.Info. Do not enable GMCP-only channels, tags, server debug, movement,
chat output, or gameplay automation. Record live evidence separately from the
offline and disposable-native results.

Cross-platform support is structural until each platform completes equivalent
native checks.

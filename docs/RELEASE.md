# Release process

1. Update `release/manifest.json`, both Lua metadata tables, `package.json`,
   and documentation to the same release version.
2. Run `npm test`, `npm run build`, and `npm run build:check`.
3. Review `dist/plugin-repo/plugins.json`; its hashes and sizes are generated
   from the exact published Lua bytes.
4. Confirm `examples/aardwolf-ui-consumer.lua` remains a tested,
   non-distributed reference and is absent from both generated delivery trees.
5. Complete the approved native acceptance in `docs/ACCEPTANCE.md`.
6. Create the `.mfp` with MudForge's native package creator. Do not zip the
   staging directory manually.
7. Verify the exported package with `tools/build_release.py --verify-package`.
8. Re-run the full offline suite and inspect the final Git diff before release.

The plugin repository and the `.mfp` are separate delivery paths. Repository
users install both the library and plugin. The native package supplies them
together atomically.

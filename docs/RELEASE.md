# Release process

1. Update `release/manifest.json`, every distributed plugin and library metadata
   table, `package.json`, and documentation to the same suite version.
2. Run `npm test`, `npm run build`, and `npm run build:check`.
3. Review `dist/plugin-repo/plugins.json`; its hashes and sizes are generated
   from the exact published Lua bytes.
4. Confirm `examples/aardwolf-ui-consumer.lua` remains a tested,
   non-distributed reference and is absent from both generated delivery trees.
5. Complete the approved native acceptance in `docs/ACCEPTANCE.md`.
6. Create the `.mfp` with MudForge's native package creator, selecting every
   plugin and library listed in `dist/native-package-input/package-input.json`.
   Do not zip the staging directory manually.
7. Verify the exported package with `tools/build_release.py --verify-package`.
8. Re-run the full offline suite and inspect the final Git diff before release.

The plugin repository and the `.mfp` are separate delivery paths. Repository
users install the library followed by the desired plugins. The native package
supplies the complete Core, Chat, and API suite atomically under the existing
`com.samroberts.aardwolf-core` package identity.

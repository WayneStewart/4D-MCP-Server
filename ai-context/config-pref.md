# Config defaults in code, and `MCP_Pref`

Builds on [config-location.md](config-location.md). Wayne Stewart, 2026-10-23.

## No default config file

The component used to ship its defaults as `Resources/4D-mcp-config.pref`.
Anything in a component's `Resources/` is copied to every remote client along
with the component, so every client machine held a readable copy of the
security policy's defaults. The defaults now live in code,
`MCP_ConfigDefaults`, which returns the same `{ KEY: {comment, value} }`
object the file held (generated from it; only the `_doc` comment changed, to
describe the new location). The template file is deleted.

`getConfig()`, when the host has no `<data folder>/Settings/4D-mcp-config.pref`,
copies the host's legacy `Project/Sources/` file if there is one, else writes
`MCP_ConfigDefaults`. No file is needed to start.

A side benefit: a key missing from the host's file — for example one added by
a newer version of the component — now takes its built-in default. Before,
it read as `Null`, and its gate behaved however `Null` happened to behave.

## `MCP_Pref`

```4d
$value:=MCP_Pref("REQUIRE_HTTPS")          // get
MCP_Pref("REQUIRE_HTTPS"; False)           // set; returns the value now in force
```

- **Shared**, so host code calls it (guarded by `COMPONENT LIST`, like
  `MCP_Initialize_Host`).
- **Works from a remote client**: the read or write happens in
  `MCP_Pref_Server`, executed on the server, on the server's file.
- **Complains** with `throw` rather than failing quietly:
  `1` unknown key (not in `MCP_ConfigDefaults`, or a `_` doc key);
  `2` a value whose type differs from the default's (any number type matches
  any other); `3` the server could not read or write the file, or the
  component's loader would not accept the result (the file is then put back
  as it was). The checks run in the caller's process, so the error appears
  there; whether an error raised inside an Execute-on-Server method reaches
  the calling client was not something to depend on.
- **Writes one value only**, keeping its comment, inside
  `Use (MCP_ConfigLock)` so two writers cannot interleave.
- Values are type-checked, not range-checked. Range rules (for example
  `MAX_LIMIT` against the wire-contract ceiling) belong to whatever editor is
  used; `getConfig()`'s own fail-closed check still guards the file.

## Version floor

Everything used here is available in 4D 20 R8, the component's stated
minimum: `throw` (20 R2), `Try`/`Catch` (already used throughout the
component), `New object` / `New collection` rather than the newer literal
syntax.

## Effect on a new built deployment

With no template shipped, a fresh deployment starts on the built-in defaults
(`REQUIRE_HTTPS: true`, read-only). Configure it once on that machine — with
`MCP_Pref` or an editor — and the data-folder file keeps the setting across
every redeploy.

## Note for PR #1

The settings UI in PR #1 (jdcryer) resolves the template through
`MCP_Handler._defaultConfigFile()`, which no longer exists. Its "component
template" target would read `MCP_ConfigDefaults` instead.

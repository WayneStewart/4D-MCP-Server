# Config location: the host's data folder

Proposed revision to the `4D-mcp-config.pref` location described in
[deployment-control.md](deployment-control.md). Wayne Stewart, 2026-10-23.

## The problem: built applications

`deployment-control.md` puts the live config in the host's `Project/Sources/`,
where the developer edits it, and asks that settings be changeable without
taking the server down. That works for an interpreted host. It breaks for a
**built (compiled) application**, the normal way a 4D Server is deployed:

1. In a built server, `Project/` is packed inside the `.4DZ`. The component
   resolves `Folder(fk database folder; *).file("Project/Sources/4D-mcp-config.pref")`
   to a real path beside the `.4DZ` (`…/Server Database/Project/Sources/`),
   where no file exists. The developer's configured copy, packed in the
   `.4DZ`, is never read.
2. `getConfig()` therefore copies the **component's default** there on first
   read, and the server runs on the shipped defaults, not the developer's
   policy.
3. A redeploy replaces the application bundle, so any hand edit made to that
   file on the server is lost and the default is written back on the next
   launch.

Observed on 4D Today (a 4D Server host, deployed 2026-10-21): the developer's
config had `REQUIRE_HTTPS: false` for a LAN-only endpoint; the live server
answered every request `403 CAP_DENIED "HTTPS is required"`. The live file was
byte-identical to the component's `Resources/4D-mcp-config.pref`, created at
first launch after the deploy.

The config is also per-deployment by nature: its gates (`REQUIRE_HTTPS`,
`ALLOW_WRITE`, `METHOD_WHITELIST`, table exposure) are security policy, and a
live server often wants different policy from the developer's machine. Keeping
it in the structure forces one policy onto every deployment of that structure.

## The change

The live config moves to the host's data folder:

```
<data folder>/Settings/4D-mcp-config.pref
```

`Folder(fk data folder; *)` is writable in every deployment mode
(interpreted, built single-user, 4D Server) and is not touched by a
redeploy. `Settings/` sits beside 4D's own per-data-file `settings.4DSettings`.

When that file is missing, `getConfig()` seeds it from the first of these that
exists (`MCP_Handler._seedConfigFile()`), then reads only the data-folder copy:

1. **Host `Project/Sources/4D-mcp-config.pref`** — the previous location, so
   existing interpreted installs carry their settings over unchanged. The
   file is never read again once migrated and can then be removed: 4D
   manages `Project/Sources/`, so a host file there is best avoided anyway.
2. **Component `Resources/4D-mcp-config.pref`** — the shipped default, as now.
   (Replaced by defaults held in code in the next step —
   [config-pref.md](config-pref.md).)

A fresh built deployment therefore starts on the component's default and is
configured once, on that machine; the setting then survives every redeploy.

Fail-closed behaviour is unchanged: no readable seed, or a seed that cannot be
copied, returns `Null` and every request is refused.

Unchanged: the file format, the `{comment, value}` flattening, on-demand
reading (an edit is live on the next request; `HTTP_PORT` still needs a
restart), and every gate.

## Files touched

- `Classes/MCP_Handler.4dm` — `_configFile()` returns the data-folder path;
  new `_seedConfigFile()`; `getConfig()` seeds from it and creates `Settings/`
  if needed; loader comment updated.
- `Methods/MCP_Initialize_Host.4dm` — the failure message names the path via
  `_configFile()` instead of rebuilding the old one.
- `Classes/MCP_Test.4dm` — the config-gate tests patch `_configFile()` (seeding
  it first if absent) instead of the old hard-coded path.
- `README.md`, `ai-context/README_halfB.md` — location described.

## Notes

- **PR #1 (settings UI, jdcryer)** resolves both paths through
  `_configFile()` / `_defaultConfigFile()`, so its editor follows this change
  without modification.
- **Migration on an existing interpreted host:** the first read copies the
  `Project/Sources/` file into the data folder; from then on edits belong in
  the data-folder copy. The `Project/Sources/` file is left in place (harmless;
  it is only ever a seed) and can be deleted.
- **A host with several data files** gets one config per data file, which
  matches "one policy per deployment".
- **Remote clients** never read the config: the handler runs on the server.

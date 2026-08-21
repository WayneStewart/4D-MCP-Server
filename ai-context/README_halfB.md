# 4D Data MCP — Half B (in-4D component)

The 4D-side half of the Data MCP. A single `POST /mcp` HTTP request handler
authenticates a Bearer token, gates on capabilities, routes to an ORDA
operation, and returns the wire-contract envelope. Half A (the external MCP
server) talks to this over HTTP. The wire contract is the source of truth:
`ai-context/mcp_data_wire_contract.md`.

Requires **4D 20 R8+** (HTTP request handlers). Ordered-source project.

## What's here

| File | Role |
|------|------|
| `Project/Sources/HTTPHandlers.json` | Registers `POST /mcp` → `MCP_Handler.dispatch` — **standalone only**: 4D loads this file only for the main web server, never for a component's own. Embedded, the same handler is registered programmatically by `MCP_Initialize_Host` |
| `Project/Sources/Classes/MCP_Handler.4dm` | Dispatcher: gate order, envelopes, HTTP adapter |
| `Project/Sources/Classes/MCP_Auth.4dm` | Token → capability object (swappable store) |
| `Project/Sources/Classes/MCP_Schema.4dm` | `get_schema_digest` from ORDA introspection |
| `Project/Sources/Classes/MCP_DataAccess.4dm` | ORDA CRUD + query + `call_method` registry |
| `Project/Sources/Classes/MCP_Test.4dm` | In-4D self-test of the full gate chain |
| `Project/Sources/Methods/MCP_RunHeadlessTests.4dm` | Headless test entry point |
| `Project/Sources/Methods/MCP_Initialize_Host.4dm` | Host startup entry: ensures config, starts the component's own web server on `HTTP_PORT` |
| `Project/Sources/Methods/MCP_StartServer.4dm` | Test entry: seeds fixtures, then runs `MCP_Initialize_Host` (curl) |
| `Project/Sources/Methods/MCP_Build.4dm` | Headless compile entry point for tool4d (`Compile project` from disk; see "Building the component") |
| `Project/Sources/catalog.4DCatalog` | Fixture schema: `Customer`, `Order` (+ relation) |
| `Resources/4D-mcp-config.pref` | Component's default deployment config; copied to the host's `Project/Sources/` on first read (edit it there) |
| `test/run_curl_tests.sh` | Exercises every action over real HTTP |
| `test/start_server.sh` | Launches a live headless 4D for the curl tests |

All four production classes are **shared singletons** and **stateless** — see
`design_notes_halfB.md` for why (this 4D build rejects mutable state on a shared
singleton's `This`).

## Building the component

**Compile before you build.** `Settings/buildApp.4DSettings` has
`BuildCompiled=False`, so Build Application packages whatever compiled code
already sits in `Project/DerivedData/CompiledCode/` — it does **not**
recompile. Edit source, skip Compile, and the build silently ships stale code.
In the IDE: Compile, then Build. Headless: run `MCP_Build` under tool4d
(compiles from disk; `BUILD APPLICATION` is a silent no-op under tool4d, so
packaging must be done outside 4D — swap the fresh `CompiledCode/` into the
`.4DZ`, copy `Libraries/lib4d-arm64.dylib` into the `.4dbase`, re-sign with
`codesign --force --deep -s -`).

## Installing the component

Compile this project and drop the component into the host's `Components/`
folder, then call `MCP_Initialize_Host` from the host's startup
(`On Startup` / `On Server Startup`). That method:

1. Ensures `4D-mcp-config.pref` exists in the host's `Project/Sources/`
   (copies the component's default on first read — same path `getConfig()` uses).
2. Starts the **component's own web server** (`WEB Server` object) on the
   config's `HTTP_PORT` (default 8044; set `0` to skip and serve `/mcp` from
   the host's web server instead), registering the `/mcp` handler
   **programmatically** in the `start()` settings — required because 4D only
   loads `HTTPHandlers.json` for the main web server, never for a component's
   (design_notes quirk 8). Returns `{success; port; message}`.

Known wrinkle: after closing/reopening the host project within one 4D
instance, the start can report success without the port actually being bound;
re-run `MCP_Initialize_Host` if `/mcp` refuses connections (quirk 10,
TODO.md).

The component's classes stay internal — no exposure to the host is needed;
`MCP_Initialize_Host` (shared) is the only entry point. The host's dataclasses
are reached via `ds`; the bundled `catalog.4DCatalog` (Customer/Order) is only
a fixture for the tests.

### Calling it from the host

In the host's `On Startup` (or `On Server Startup`) database method:

```4d
// On Startup
ARRAY TEXT($names; 0)
COMPONENT LIST($names)
var $mcp : Object
var $f : 4D.Function

If (Find in array($names; "4d-mcp-server")>0)
	$f:=Formula from string("MCP_Initialize_Host")
	$mcp:=$f.call()
End if 
```

The `COMPONENT LIST` guard plus `Formula from string` indirection lets the host
compile and run even when the component is not installed or has been removed —
a direct `MCP_Initialize_Host` call would fail to compile without it. Then
handle the result:

```4d
Case of
	: ($mcp=Null)
		// Component not installed — nothing to do
	: (Not(Bool($mcp.success)))
		// Config unreadable/malformed, or the web server refused to start
		// (port in use, ...). Already logged to stdout by the component;
		// decide here whether that's fatal for your app.
		ALERT("MCP server failed to start: "+String($mcp.message))

	: ($mcp.port=0)
		// HTTP_PORT<=0 in 4D-mcp-config.pref — deliberate opt-out; /mcp is
		// expected to be served by the host's own web server instead.

	Else
		// Up and listening: POST http://localhost:<$mcp.port>/mcp
End case
```

The call is idempotent — if the component's web server is already running it
returns `{success: True; message: "MCP web server already running"}` — so it's
safe to call again (e.g. from an admin "restart MCP" menu item). Every outcome
is also appended (JSONL, via the `log_worker` worker) to
`Logs/4d_mcp_server_log_YYYYMMDD` in the host's Logs folder, so failed starts
are easy to find without digging through system logs.

Alternatively, lift the pieces into your app directly: copy the five `MCP_*`
classes, merge `HTTPHandlers.json` (a JSON array — add the `/mcp` entry), and
start a web server.

## Configuring a token

A Bearer token resolves to a **capability object** covering data access only:

```
{ token_id: Text; read: []Text | "*"; write: []Text | "*" }
```

- `read`/`write` are the wildcard `"*"` (every dataclass the config exposes) or
  an explicit collection of dataclass names. Absent, or any other string,
  normalizes to no access.
- `attributes` projection is a **client convenience, not a security boundary** —
  gating is at the dataclass level only (contract §6).
- **A capability says nothing about `call_method`.** There is no `call` grant.
  `ALLOW_CALL_METHOD` + `METHOD_WHITELIST` decide what the *deployment* will
  run, and that decision binds every token identically — a token that
  authenticates at all may invoke every whitelisted action. Scope what
  `call_method` can reach by editing the whitelist, never by picking tokens.
  A `call` key left on an existing token row is ignored.

### The two stores

`TOKEN_STORE` in `4D-mcp-config.pref` selects where `MCP_Auth._lookup()` reads
from. Anything other than these two values resolves nothing:

- **`"inline"`** (the default, and the behavior when the key is absent) —
  `_loadTokens()`, an object keyed by raw bearer string, hardcoded in this
  component. Fixtures for the self-tests and a single-host demo. Editing them
  means editing a component that every host loads, and the demo bearers
  (`SECRET_FULL`, `SECRET_RO`, `SECRET_STAR`) ship into all of them.
- **`"table"`** — the HOST dataclass named by `TOKEN_TABLE`. What real
  deployments use: a component shared by several host projects cannot carry
  their tokens.

Row shape for the token dataclass:

| Attribute | Type | Holds |
|---|---|---|
| `tokenHash` | Text | SHA-256 hex of the bearer, from `MCP_Auth.hashToken()` |
| `tokenId` | Text | audit label; what the request/audit logs record |
| `grants` | Object | `{ read; write }` — the capability shape above |
| `isActive` | Boolean | `false` = revoked |

The bearer is never stored, only its digest. `hashToken()` is public precisely
so any host-side seeding routine hashes identically — were the two to drift,
every token would fail to validate with nothing to explain why.

**Fail closed.** `"table"` whose `TOKEN_TABLE` is blank, misnamed, or missing
the row shape resolves NO token and never falls back to the inline set; the
symptom is a uniform `AUTH_DENIED`. The alternative — a misconfigured
production host quietly honoring `SECRET_STAR` — is the failure this rules out.

**The token dataclass is force-excluded from the exposed set**
(`MCP_Schema.exposedDataclasses` → `_dropTokenTable`), applied *after* every
other exposure rule including `WHITELIST_TABLES`, which overrides the blacklist
and `RESPECT_4D_SCHEMA` and would otherwise be the one way to publish it by
name. Without that, a single wildcard read grant returns every other token's
hashes and grants.

### Minting and revoking

`MCP_Auth.issueToken()` / `.revokeToken()` live in the component on purpose:
the digest algorithm, the row shape, and the meaning of `isActive` are all this
class's business, and a host-side copy per project is the same method written N
times — the first edit to one of them writes a row in a shape `MCP_Auth` no
longer reads, with no error to explain why a valid-looking token stopped
validating.

Neither is reachable over the wire: `call_method` invokes host project methods
only, and the token table is excluded from exposure regardless. Run them from
the host's method editor, or wrap them in a host method that logs the result.

```4d
$res:=cs.mcp4d.MCP_Auth.me.issueToken("tok_reporting"; \
	New object("read"; New collection("Customer"; "Order"); "write"; New collection))
  // -> {success; message; token; tokenId}
  // token is "mcp_" + two dashless UUIDs, returned ONCE — only the digest is
  // stored, so a lost token is reissued under a new id, never recovered.

$res:=cs.mcp4d.MCP_Auth.me.revokeToken("tok_reporting")
  // -> {success; message}   flips isActive; the row (and the audit trail) stays
```

`issueToken` refuses rather than half-succeeding — blank id, duplicate
`tokenId`, unresolvable `TOKEN_TABLE`, or a table without the row shape each
return `success: false` with a message naming the problem.

Both resolve the table through the **ungated** `_resolveTable()`, not
`tokenTableName()`. That is deliberate: you create the first row while
`TOKEN_STORE` is still `"inline"`, then throw the switch. The other order locks
every client out until a row exists that cannot yet be created. Authentication
and exposure keep the gated resolver, so a `TOKEN_TABLE` left set beside an
inline store never quietly goes live.

### What is still missing

- **No expiry.** There is no `expiresAt` attribute and `validate()` checks none.
  A token is valid until someone revokes it.
- **No rotation, no TTL, no scope beyond `read`/`write`.** `isActive` is the
  whole lifecycle.
- **No `updateToken`.** Re-granting means editing the `grants` object on the row.

Tracked in `TODO.md`.

## Registering a callable action (`call_method`)

Exposing a HOST method to `call_method` needs **all** of:

1. The method's **"Shared by components and host database"** property set to
   true (Method Properties in the IDE, or `//%attributes = {"shared":true}`
   in the `.4dm` header — same setting, two ways to set it). Without this,
   `EXECUTE METHOD` from inside the component cannot see the host's method at
   all and fails with `INTERNAL: Project method not found`, even though the
   method genuinely exists in the host project — this crosses the
   component/host boundary, which 4D gates independently of anything in this
   component's own config.
2. `ALLOW_CALL_METHOD: true` in `4D-mcp-config.pref`.
3. An entry in `METHOD_WHITELIST` (below).
That is the whole list — **no token configuration is involved**. Once 1–3 hold,
the action is reachable by every valid token; there is nothing per-token left to
grant, and nothing per-token that can take it away.

Condition 1 is the one this component cannot check for you. `ALLOW_CALL_METHOD`
and `METHOD_WHITELIST` are config it reads; "shared" is a property of the host
method that only 4D sees at execution time. A whitelisted action that answers
`INTERNAL` with nothing in the host log is almost always an unshared method.

The client names an **action_name**, never a 4D method name. The map lives in
the deployment config (`METHOD_WHITELIST` in `4D-mcp-config.pref`) — each entry
exposes one HOST project method:

```json
"my_action": {
  "method": "UTIL_MyHostMethod",
  "args": [ { "name": "status", "type": "text", "required": false,
              "purpose": "filter to one order status" } ],
  "return": "object",
  "purpose": "What this action does — surfaced to clients via get_schema_digest"
}
```

The wire's `args` is a collection bound **positionally** to the host method's
parameters (`EXECUTE METHOD`); the spec's `name` is documentation, position is
what binds; optional args are trailing-only. The host method takes typed
positional params and returns a JSON-serializable value:

```4d
#DECLARE($status : Text) : Object
return New object("count"; ds.Order.query("status = :1"; $status).length)
```

Gate 4 validates arity and types against the spec (`BAD_PARAMS`); anything not
in the map is unreachable (`CAP_DENIED: Action not enabled in server config`);
a host method that throws → `INTERNAL` with the 4D message (never a stack).
Clients discover the whole whitelist — spec included, host method name stripped
— via `get_schema_digest.callable_actions`, which is the same list for every
token.
The bundled fixtures (`MCP_Fixture_Ping` / `MCP_Fixture_OrderCount` /
`MCP_Fixture_EchoUpper`) are ordinary host methods registered this way; drop
them (and their whitelist entries) when embedding.

## Running the tests

### Logic tests (headless, no web server) — verifies the whole gate chain

```bash
tool4d --project Project/4d-mcp-server.4DProject --opening-mode interpreted \
  --startup-method MCP_RunHeadlessTests --create-data --data /tmp/mcp/data.4DD
cat test_report.json     # { total, passed, failed, cases:[...] }
```

83 assertions cover all 8 action invocations, the full error taxonomy, capability
gating, the deployment-config verb gates (ENABLED, ALLOW_READ/WRITE/DELETE,
ALLOW_CALL_METHOD + METHOD_WHITELIST), the transport gates (REQUIRE_HTTPS,
MAX_BODY_SIZE, per-token rate limit), placeholder binding, pagination clamp,
and CRUD round-trips. dispatch()'s wire path (transport gates, rate limiting,
request/audit logs, host hooks) is additionally exercised over real HTTP by
the curl suite. This calls
the pure `MCP_Handler.handle($token; $body)` seam, so no HTTP is needed.

### HTTP tests (real wire path) — needs full 4D (not tool4d)

`tool4d` does **not** implement the web server, so the curl tests must run against
a real 4D (4D Server or 4D desktop). Start the server, then curl:

```bash
./test/start_server.sh          # full 4D with web server on :8044 (seeds fixtures)
# in another shell:
./test/run_curl_tests.sh        # 17 checks: 8 happy paths + error taxonomy
```

`run_curl_tests.sh` exercises every action with a Bearer token and JSON body and
asserts the HTTP status + response envelope for each.

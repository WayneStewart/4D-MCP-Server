# 4D Data MCP

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server for 4D databases. It lets an MCP client — Claude Code, Claude Desktop, or any other MCP-capable tool — discover a 4D application's schema, query and modify its data through ORDA, and call whitelisted project methods — data access gated by per-token capabilities, method access by the deployment config, both enforced inside 4D.

The system is built as two cooperating halves joined by a versioned HTTP wire contract:

```
MCP client (Claude Code / Claude Desktop / ...)
        │  stdio (MCP protocol)
        ▼
Half A — mcp-server/            Node.js stdio MCP server
        │  POST /mcp — JSON envelope {v:1, action, params}, Bearer token
        ▼
Half B — 4d-mcp-server/         4D component: HTTP handler + ORDA
        │
        ▼
   Host 4D application's datastore (ds)
```

## How the two halves work together

**Half A** (`mcp-server/`) is a thin Node.js translator. It speaks MCP over stdio to the client and exposes one tool per wire action (`4d_get_schema_digest`, `4d_query_entities`, `4d_get_entity`, `4d_create_entity`, `4d_update_entity`, `4d_delete_entity`, `4d_call_method`). Every tool call is wrapped in a JSON envelope and forwarded as `POST /mcp` with a Bearer token. It holds no logic of its own beyond envelope construction, response validation, and error mapping — it surfaces exactly what Half B allows.

**Half B** (`4d-mcp-server/`) is a 4D component installed in the host application. Its `POST /mcp` handler authenticates the Bearer token, resolves it to a capability object (which dataclasses it may read/write), applies the deployment-config gates (enable flags, HTTPS requirement, body-size limit, rate limiting, table exposure, callable methods), then routes to the matching ORDA operation against the host's `ds`. All security enforcement lives here, on the 4D side.

The contract between them — envelope shape, the eight actions, the error taxonomy, pagination rules — is specified in **`ai-context/mcp_data_wire_contract.md` (v1)**, which is the source of truth for both halves. Either half can be tested against it independently: Half A's unit tests run against a canned fixture standing in for 4D, and Half B's curl suite exercises the real HTTP path without any MCP client.

A typical session: the client calls `4d_get_schema_digest` to learn which dataclasses its token can see and which actions the deployment exposes, then queries/creates/updates entities or invokes whitelisted methods. Contract errors come back as typed codes (`CAP_DENIED`, `BAD_PARAMS`, `NOT_FOUND`, ...) so the model can react sensibly.

## Repository layout

| Path | What it is |
|------|-----------|
| `mcp-server/` | Half A — Node.js/TypeScript stdio MCP server ([README](mcp-server/README.md)) |
| `4d-mcp-server/` | Half B — 4D component project ([README](ai-context/README_halfB.md)) |
| `4d-mcp-server_Build/` | Built component output |
| `ai-context/` | Wire contract, design notes, per-half docs |

## Installation & setup

### Half B — the 4D component

Requires **4D 20 R8+** (HTTP request handlers).

1. **Compile, then build.** In the 4D IDE: run Compile on `4d-mcp-server`, then Build Application. The build settings have `BuildCompiled=False`, so building without compiling first silently packages stale code. (Headless alternative: run `MCP_Build` under tool4d — see the [Half B README](ai-context/README_halfB.md#building-the-component) for the packaging steps tool4d can't do itself.)

2. **Install into the host.** Drop the built component into the host application's `Components/` folder.

3. **Start it.** Call `MCP_Initialize_Host` from the host's `On Startup` / `On Server Startup` database method or manuall:

   ```4d
		ARRAY TEXT($names; 0)
		COMPONENT LIST($names)
		
		If(Find in array($names; "4d-mcp-server")>0)
		  EXECUTE METHOD("MCP_Initialize_Host")
		  EXECUTE METHOD("MCP_StartServer")
		End if
   ```

   The `COMPONENT LIST` guard plus `Formula from string` indirection means the host compiles and runs cleanly even when the component is not installed (or later removed) — a direct call to `MCP_Initialize_Host` would fail to compile without it.

   > On first run this creates the deployment config `4D-mcp-config.pref` in the host's **data folder** (`<data folder>/Settings/`), seeding it from the host's `Project/Sources/` copy if there is one (the previous location), else from the component's own default. It then starts the component's own web server on the config's `HTTP_PORT` (default **8044**; set `0` to serve `/mcp` from the host's main web server instead). The call is idempotent and safe to re-run.

4. **Configure exposure and method access.** Edit `4D-mcp-config.pref` in the host's data folder (`<data folder>/Settings/`). It lives there, not in the structure, so it stays writable and survives a redeploy of a built application; each deployment (dev, live) keeps its own policy (see [ai-context/config-location.md](ai-context/config-location.md)):
   - Table exposure and verb gates (`ENABLED`, `ALLOW_READ/WRITE/DELETE`, `ALLOW_CALL_METHOD`).
   - `METHOD_WHITELIST` — maps client-facing action names to host project methods for `4d_call_method`.

5. **Set a token.** Tokens are literals in `MCP_Auth._loadTokens()` inside the component. Replace the demo bearers with your own before the endpoint is reachable by anything you care about — see [Tokens & capabilities](#tokens--capabilities).

### Half A — the Node MCP server

Requires **Node 18.17+**.

```bash
cd mcp-server
npm install
npm run build
```

Configuration is via environment variables:

| Env var | Default | Meaning |
|---------|---------|---------|
| `FOURD_MCP_URL` | `http://localhost:8044/mcp` | Half B endpoint |
| `FOURD_MCP_TOKEN` | — (required) | Bearer token |
| `FOURD_MCP_TIMEOUT_MS` | `30000` | Per-request timeout |

Register with Claude Code:

```bash
claude mcp add 4d-data \
  --env FOURD_MCP_URL=http://localhost:8044/mcp \
  --env FOURD_MCP_TOKEN=YOUR_TOKEN \
  -- node /path/to/mcp-server/dist/index.js
```

Or in an `mcpServers` JSON block (Claude Desktop and similar):

```json
{
  "mcpServers": {
    "4d-data": {
      "command": "node",
      "args": ["/path/to/mcp-server/dist/index.js"],
      "env": {
        "FOURD_MCP_URL": "http://localhost:8044/mcp",
        "FOURD_MCP_TOKEN": "YOUR_TOKEN"
      }
    }
  }
}
```

### Verifying the setup

With the host 4D app running (Half B up on port 8044):

```bash
# Half B alone, over real HTTP:
cd 4d-mcp-server && ./test/run_curl_tests.sh

# Half A against the live Half B:
cd mcp-server
FOURD_MCP_URL=http://localhost:8044/mcp FOURD_MCP_TOKEN=SECRET_FULL \
  npm run test:integration
```

Half A's unit tests (`npm test`) and Half B's logic tests (`MCP_RunHeadlessTests` under tool4d) need no running server at all.

## Exposing 4D Methods

You can expose methods in the 4D host via the MCP server. This can be particularly useful for testing during development or as a way to provide output that is more than simple data transfer. 

To be exposed a method must:
- have the 'Shared with components and Host' property set to true
- set `ALLOW_CALL_METHOD` to `true` in `4D-mcp-config.pref`
- be listed in `METHOD_WHITELIST` in `4D-mcp-config.pref`

That is the entire permission model, and all three conditions are properties of the *deployment*, not of the caller. **No token grant is involved.** Any Bearer token that authenticates — including a read-only one — may invoke every whitelisted action. Scope what `call_method` reaches by editing the whitelist; there is no way to hand one token a narrower set of methods than another.

The first condition is the one the component cannot check for you: `ALLOW_CALL_METHOD` and `METHOD_WHITELIST` are config it reads, while 'shared' is a property of the host method that only 4D sees at execution time. A whitelisted action whose method is not shared fails at `EXECUTE METHOD` and comes back as `INTERNAL`, not `CAP_DENIED` — if an action you just added answers `INTERNAL` with nothing in the host log, check the shared property first.

Enabling methods is not quick and easy and that's a good thing. It's an incredibly powerful option and you really want to be careful when you do it. 

### Defining methods in METHOD_WHITELIST

 `4D-mcp-config.pref` is a JSON document and `METHOD_WHITELIST` is a property of it. Each method you want to expose is added as an object to this JSON file. 

As an example let's add a method built into the component: `MCP_Fixture_Ping`. The object we need to create looks like this: 

```json
{
    "method": "MCP_Fixture_Ping",
    "args": [
     {
      "name": "echo",
      "type": "text",
      "required": false,
      "purpose": "text echoed back in the response"
      }
}
```

This is added to the config json with a name to use with the AI. You can use the method name or something else, as in this case: 

```json
...
 "ALLOW_CALL_METHOD": {
  "comment": "Global gate for call_method. When false, METHOD_WHITELIST is ignored entirely.",
  "value": true
 "METHOD_WHITELIST": {
  "comment": "Map of client-visible action name ...",
  "value": {
	   "ping": {
	    "method": "MCP_Fixture_Ping",
	    "args": [
		     {
		      "name": "echo",
		      "type": "text",
		      "required": false,
		      "purpose": "text echoed back in the response"
		     }
	    ],
	    "return": "object",
	    "purpose": "Liveness check; returns {pong:true} plus the echo if given"
	   },
	   "order_count": {
	    "method": "MCP_Fixture_OrderCount",
	    "args": [
		     {
		      "name": "status",
		      "type": "text",
		      "required": false,
		      "purpose": "filter to one order status"
		     }
	    ],
	    "return": "object",
	    "purpose": "Count orders, optionally filtered by status"
	   }
   }, 
   ...
```

## Tokens & capabilities

Every request carries a Bearer token, which `MCP_Auth` resolves to a capability object:

```
{ token_id: Text; read: []Text | "*"; write: []Text | "*" }
```

- **`read`/`write`** are either the wildcard `"*"` (every dataclass the deployment config exposes) or an explicit list of dataclass names. An absent verb normalizes to no access.

**A capability covers data access only.** It says nothing about `call_method`: there is no `call` grant, and a token needs none. Which methods are reachable is settled entirely by `ALLOW_CALL_METHOD` + `METHOD_WHITELIST` (see [Exposing 4D Methods](#exposing-4d-methods)), and that answer is the same for every valid token. The one failure you can get is `CAP_DENIED: Action not enabled in server config`, which always means the deployment gate, never the caller.

### Where tokens live

In `MCP_Auth._loadTokens()`, hardcoded in the component. That is the only store.
The bearer string is the object key:

```4d
$t["SECRET_FULL"]:=New object(\
    "token_id"; "tok_full"; \
    "read";  New collection("Customer"; "Order"); \
    "write"; New collection("Order"))
```

There is no generation step, no expiry, no revocation short of editing this
method and rebuilding the component. It is a short list of shared API keys, not
session tokens, and it is meant to be read that way.

**This is deliberate.** The MCP endpoint is a large, obvious hole in the host
application. Wrapping its credentials in a table, a minting call, and a
lifecycle would make it *look* smaller than it is without making it smaller —
that machinery buys a sophisticated operator a little and everyone else nothing
but a false impression. The controls that actually matter here are blunt and
immediate:

- **Remove the component.** The host runs fine without it — the
  `COMPONENT LIST` guard in the startup snippet above means nothing breaks and
  nothing fails to compile.
- **Set `ENABLED` to `false`** in `4D-mcp-config.pref`. The component answers
  nothing from the next request onward. No restart, no redeploy.

Two consequences follow from tokens living in shared component source, and both
matter more than the store's shape:

- **Every host that installs this component gets the same bearer strings.**
  Never add a host-specific token to `_loadTokens()`.
- **The bearers that ship are demo fixtures, published in this repository.**
  `SECRET_STAR` in particular is a read/write wildcard over every exposed
  dataclass, and `ALLOW_READ` defaults to `true`. A deployment *replaces* them;
  it does not add to them.

## Documentation

- **Wire contract (source of truth):** [`ai-context/mcp_data_wire_contract.md`](ai-context/mcp_data_wire_contract.md)
- **Half A details:** [`mcp-server/README.md`](mcp-server/README.md)
- **Half B details:** [`ai-context/README_halfB.md`](ai-context/README_halfB.md)
- **Design notes:** [`ai-context/design_notes_halfB.md`](ai-context/design_notes_halfB.md)

# 4D Data MCP

An [MCP (Model Context Protocol)](https://modelcontextprotocol.io) server for 4D databases. It lets an MCP client — Claude Code, Claude Desktop, or any other MCP-capable tool — discover a 4D application's schema, query and modify its data through ORDA, and call whitelisted project methods, all gated by per-token capabilities enforced inside 4D.

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

**Half B** (`4d-mcp-server/`) is a 4D component installed in the host application. Its `POST /mcp` handler authenticates the Bearer token, resolves it to a capability object (which dataclasses it may read/write, which actions it may call), applies the deployment-config gates (enable flags, HTTPS requirement, body-size limit, rate limiting, table exposure), then routes to the matching ORDA operation against the host's `ds`. All security enforcement lives here, on the 4D side.

The contract between them — envelope shape, the eight actions, the error taxonomy, pagination rules — is specified in **`ai-context/mcp_data_wire_contract.md` (v1)**, which is the source of truth for both halves. Either half can be tested against it independently: Half A's unit tests run against a canned fixture standing in for 4D, and Half B's curl suite exercises the real HTTP path without any MCP client.

A typical session: the client calls `4d_get_schema_digest` to learn which dataclasses and callable actions its token can see, then queries/creates/updates entities or invokes whitelisted methods. Contract errors come back as typed codes (`CAP_DENIED`, `BAD_PARAMS`, `NOT_FOUND`, ...) so the model can react sensibly.

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

   > On first run this copies the default deployment config `4D-mcp-config.pref` into the host's `Project/Sources/`, then starts the component's own web server on the config's `HTTP_PORT` (default **8044**; set `0` to serve `/mcp` from the host's main web server instead). The call is idempotent and safe to re-run.

4. **Configure tokens and exposure.** Edit `4D-mcp-config.pref` in the host's `Project/Sources/`:
   - Table exposure and verb gates (`ENABLED`, `ALLOW_READ/WRITE/DELETE`, `ALLOW_CALL_METHOD`).
   - `METHOD_WHITELIST` — maps client-facing action names to host project methods for `4d_call_method`.

   Tokens map a Bearer string to a capability object (readable/writable dataclasses, callable actions); v1 defines them in `MCP_Auth._loadTokens()`, swappable for a table-backed store. See the [Half B README](ai-context/README_halfB.md) for the exact shapes.

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
- add each method to `METHOD_WHITELIST` in `4D-mcp-config.pref`
- add each method's whitelist name to the relevant token's `call` collection in `MCP_Auth._loadTokens()` — a token's own capability list is separate from `METHOD_WHITELIST` and defaults to empty, so a method can be fully whitelisted at the deployment level and still be unreachable by a given token

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
{ token_id: Text; read: []Text | "*"; write: []Text | "*"; call: []Text }
```

- **`read`/`write`** are either the wildcard `"*"` (every dataclass the deployment config exposes) or an explicit list of dataclass names. An absent verb normalizes to no access.
- **`call`** is an explicit list of client-facing action names (the keys you defined in `METHOD_WHITELIST`, not the underlying 4D method names) that this specific token is allowed to invoke.

**`call` is a second, independent gate on top of `METHOD_WHITELIST` — both must agree.** `METHOD_WHITELIST` + `ALLOW_CALL_METHOD` control what the *deployment* is willing to run for anyone; a token's own `call` list controls what *that token* is allowed to reach within that set. Whitelisting a method deployment-wide does nothing for a token whose `call` list doesn't also name it — you'll get `CAP_DENIED: Token cannot call action`, distinct from `CAP_DENIED: Action not enabled in server config` (which means the deployment-level gate failed instead). The two error messages tell you which side to fix.

### Where tokens live today

v1 defines every token inline, hardcoded, in `MCP_Auth._loadTokens()` — the bearer string itself is the object key, e.g. `"SECRET_STAR"`. There is no generation step, no expiry, no revocation short of editing and redeploying that method. This is a fixture-grade mechanism, closer to a handful of shared API keys than to session tokens, and it currently requires component source access to change.

**This means an end user of the host database — someone who only has the compiled/installed component, not its project source — cannot mint, edit, or revoke a token themselves.** Provisioning a new token, or changing what an existing one can reach, is a code change made by whoever maintains the component, not a configuration step available from the host application. If self-service token management is needed, `_loadTokens()` is designed to be swapped for a table-backed store (`TOKEN_STORE: "table"` is already stubbed in `4D-mcp-config.pref`) — but as of this writing that swap hasn't been implemented, and even once it is, it would need real generation/expiry logic added on top, not just the same static lookup moved into a table (tracked in `ai-context/TODO.md`).

## Documentation

- **Wire contract (source of truth):** [`ai-context/mcp_data_wire_contract.md`](ai-context/mcp_data_wire_contract.md)
- **Half A details:** [`mcp-server/README.md`](mcp-server/README.md)
- **Half B details:** [`ai-context/README_halfB.md`](ai-context/README_halfB.md)
- **Design notes:** [`ai-context/design_notes_halfB.md`](ai-context/design_notes_halfB.md)

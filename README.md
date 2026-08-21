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

   > On first run this copies the default deployment config `4D-mcp-config.pref` into the host's `Project/Sources/`, then starts the component's own web server on the config's `HTTP_PORT` (default **8044**; set `0` to serve `/mcp` from the host's main web server instead). The call is idempotent and safe to re-run.

4. **Configure exposure and method access.** Edit `4D-mcp-config.pref` in the host's `Project/Sources/`:
   - Table exposure and verb gates (`ENABLED`, `ALLOW_READ/WRITE/DELETE`, `ALLOW_CALL_METHOD`).
   - `METHOD_WHITELIST` — maps client-facing action names to host project methods for `4d_call_method`.

5. **Mint a token.** Add a token dataclass to the host, point `TOKEN_TABLE` at it, and mint the first credential with `cs.mcp4d.MCP_Auth.me.issueToken(...)`, then set `TOKEN_STORE` to `"table"`. Until you do, the deployment runs on the component's demo tokens — see [Tokens & capabilities](#tokens--capabilities) for the row shape and why that order matters.

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

`TOKEN_STORE` in `4D-mcp-config.pref` picks one of two stores. Any value other
than these two resolves no token at all.

| `TOKEN_STORE` | Tokens live in | Editable by |
|---|---|---|
| `"inline"` (default, and the value when the key is absent) | `MCP_Auth._loadTokens()`, hardcoded in component source | whoever can rebuild the component |
| `"table"` | the host dataclass named by `TOKEN_TABLE` | anyone who can run a method in the host |

**`"table"` is what a deployment should use.** `"inline"` exists for the
component's own self-tests and for a single-host demo; its bearer strings are
literals in source shared by every host that installs the component.

> **The shipped default is `"inline"`, which means a fresh install honors the
> demo tokens** — including `SECRET_STAR`, a read/write wildcard over every
> exposed dataclass. Set `TOKEN_STORE` to `"table"` (and mint a real token,
> below) before the endpoint is reachable by anything you care about.

#### The token table

`TOKEN_TABLE` names a host dataclass whose rows are:

| Attribute | Type | What it holds |
|---|---|---|
| `tokenHash` | Text | SHA-256 hex of the bearer, from `MCP_Auth.hashToken()` |
| `tokenId` | Text | the audit label — what the request and audit logs record |
| `grants` | Object | `{ read; write }`, the capability shape above |
| `isActive` | Boolean | `false` = revoked |

**The bearer itself is never stored.** Only its digest is, so a leaked data file
yields nothing usable and a lost token is reissued under a new id rather than
recovered.

Two safety properties are worth knowing because they change how a
misconfiguration behaves:

- **Fail closed.** `TOKEN_STORE: "table"` with a `TOKEN_TABLE` that is blank,
  misspelled, or missing the row shape validates *no* token — it never falls
  back to the inline set. A production host quietly honoring `SECRET_STAR`
  because someone fat-fingered a table name is the outcome this rules out. The
  symptom is every request returning `AUTH_DENIED`.
- **The token table is never readable through the API it guards.** It is
  removed from the exposed set after every other exposure rule, including
  `WHITELIST_TABLES` — which otherwise overrides everything and would be the
  one way to publish it by name.

#### Minting and revoking

Both live in the component, and neither is reachable over the wire —
`call_method` invokes host project methods only, and the token table is
excluded from exposure regardless. Run them from the host's method editor, or
wrap them in a host method that logs the result:

```4d
  // mint — the token is shown ONCE and never again
$res:=cs.mcp4d.MCP_Auth.me.issueToken("tok_reporting"; \
	New object("read"; New collection("Customer"; "Order"); "write"; New collection))
  // -> {success; message; token: "mcp_<64 hex>"; tokenId}

  // revoke — flips isActive, keeps the row
$res:=cs.mcp4d.MCP_Auth.me.revokeToken("tok_reporting")
```

`issueToken` refuses rather than half-succeeding: a blank id, a duplicate
`tokenId`, an unresolvable `TOKEN_TABLE`, or a table missing the row shape all
come back `success: false` with a message naming the problem. Revoking flips
`isActive` instead of deleting the row, so the record that the credential
existed survives the revocation.

Both resolve `TOKEN_TABLE` *without* checking `TOKEN_STORE`, deliberately: you
create the first row while the store is still `"inline"`, then throw the
switch. The other order locks every client out until a row exists that cannot
yet be created.

#### What token management still does not do

- **No expiry.** There is no `expiresAt` and nothing checks one. A token is
  valid until someone revokes it.
- **No rotation, no TTL, no scopes beyond `read`/`write`.** `isActive` is the
  entire lifecycle.
- **Changing what a token may reach means editing its `grants` row directly** —
  there is no `updateToken`.

Tracked in `ai-context/TODO.md`.

## Documentation

- **Wire contract (source of truth):** [`ai-context/mcp_data_wire_contract.md`](ai-context/mcp_data_wire_contract.md)
- **Half A details:** [`mcp-server/README.md`](mcp-server/README.md)
- **Half B details:** [`ai-context/README_halfB.md`](ai-context/README_halfB.md)
- **Design notes:** [`ai-context/design_notes_halfB.md`](ai-context/design_notes_halfB.md)

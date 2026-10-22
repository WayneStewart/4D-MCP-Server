//%attributes = {"invisible":true,"preemptive":"capable"}
/* Purpose: The built-in default deployment config, as code.
 ------------------
MCP_ConfigDefaults () : Object   // { KEY: {comment; value}, ... }
 Created by: Wayne Stewart, 2026-10-23

 Replaces the shipped Resources/4D-mcp-config.pref template, so no default
 config file exists anywhere on disk: a template in Resources is copied to
 every remote client along with the component. MCP_Handler.getConfig() writes
 this object to the host's data folder when the host has no config yet, and
 fills any key missing from the host's file (for example one added by a newer
 version of the component) from here. MCP_Pref uses it as the list of valid
 keys and the expected type of each value.

 The shape is exactly the file's: every key is {comment; value}, and keys
 starting with "_" are documentation only.
*/

#DECLARE : Object

var $defaults : Object
$defaults:=New object

$defaults["_doc"]:=New object("comment"; "Config for the 4D MCP Server component. Every setting is {comment, value}. This file lives in the host's data folder (Settings/4D-mcp-config.pref); the component writes it from its built-in defaults on first read if none exists. The loader reads on demand, so edits are live on the next request — no restart needed (HTTP_PORT excepted)."; "value"; Null)
$defaults["ENABLED"]:=New object("comment"; "Master switch. false = the component loads but answers nothing."; "value"; True)
$defaults["HTTP_PORT"]:=New object("comment"; "Port for the component's own web server, started by MCP_Initialize_Host. 0 = don't start one (serve /mcp from the host's web server instead). Read at startup only — changing it needs a restart, unlike the other settings."; "value"; 8044)
$defaults["ALLOW_READ"]:=New object("comment"; "Gates get_schema_digest, query_entities, get_entity."; "value"; True)
$defaults["ALLOW_WRITE"]:=New object("comment"; "Gates create_entity and update_entity."; "value"; False)
$defaults["ALLOW_DELETE"]:=New object("comment"; "Gates delete_entity."; "value"; False)
$defaults["ALLOW_CALL_METHOD"]:=New object("comment"; "Global gate for call_method. When false, METHOD_WHITELIST is ignored entirely. Together with METHOD_WHITELIST this is the WHOLE permission model for calling methods — tokens carry no per-method grant, so every valid token reaches the same set."; "value"; False)
$defaults["METHOD_WHITELIST"]:=New object("comment"; "Map of client-visible action name -> {method, args, return, purpose}. `method` is the HOST project method call_method executes (never sent to clients); `args` is the ORDERED positional parameter spec, each {name, type, required, purpose} with type one of text|number|boolean|object|collection (optional args trailing-only); `return` and `purpose` are documentation surfaced to clients via get_schema_digest. Empty = nothing callable. A whitelisted method must ALSO have 4D's \"Shared with components and host\" property set, or EXECUTE METHOD cannot reach it and the call answers INTERNAL. SECURITY: every entry here hands clients a door into host code — whoever can edit this file controls what call_method reaches, for every token."; "value"; New object)
$defaults["RESPECT_4D_SCHEMA"]:=New object("comment"; "true = honor the 'Expose as REST resource' table/field settings from the structure editor. false = all tables and fields are exposed — configure the table lists below if you use this."; "value"; True)
$defaults["WHITELIST_TABLES"]:=New object("comment"; "If non-empty, ONLY these dataclasses are exposed; overrides BLACKLIST_TABLES and RESPECT_4D_SCHEMA."; "value"; New collection)
$defaults["BLACKLIST_TABLES"]:=New object("comment"; "Dataclasses never exposed, regardless of RESPECT_4D_SCHEMA. Ignored when WHITELIST_TABLES is non-empty."; "value"; New collection)
$defaults["REQUIRE_HTTPS"]:=New object("comment"; "true = refuse requests over plain HTTP (403 CAP_DENIED). Set false only for local development. The endpoint path is set in HTTPHandlers.json, and IP filtering belongs in the web server settings or a reverse proxy — neither is configurable here."; "value"; True)
$defaults["MAX_BODY_SIZE"]:=New object("comment"; "Maximum request body size in bytes. Oversize requests are rejected with BAD_PARAMS. 0 = unlimited."; "value"; 262144)
$defaults["RATE_LIMIT"]:=New object("comment"; "Maximum requests per minute per token (fixed one-minute window). Exceeding it returns 429 RATE_LIMITED. 0 = unlimited."; "value"; 120)
$defaults["DEFAULT_LIMIT"]:=New object("comment"; "Default page size for query_entities when the client sends no limit."; "value"; 80)
$defaults["MAX_LIMIT"]:=New object("comment"; "Hard cap on page size. Wire contract v1 fixes the ceiling at 80; this may only be set lower, never higher."; "value"; 80)
$defaults["LOG_LEVEL"]:=New object("comment"; "off | error | info | debug. 'error' logs only failed requests; 'info'/'debug' log all. Applies to the request log (LOG_REQUESTS must also be true)."; "value"; "error")
$defaults["LOG_REQUESTS"]:=New object("comment"; "true = write the request log (Logs/mcp_requests.jsonl in the host): ts, action, token_id, status, error code, duration ms."; "value"; False)
$defaults["AUDIT_WRITES"]:=New object("comment"; "true = durable audit log of every successful mutation (create/update/delete/call) with token_id, to Logs/mcp_audit.jsonl in the host. Independent of LOG_LEVEL."; "value"; False)
$defaults["ON_ERROR_CALL"]:=New object("comment"; "Name of a host method to call on INTERNAL errors; receives {ts, action, code, message}. Empty = none."; "value"; "")
$defaults["ON_REQUEST_CALL"]:=New object("comment"; "Name of a host method called for each request that already carries a valid, resolved token (requests with a missing/invalid token skip this hook and get AUTH_DENIED instead) with {action, token_id}; return {deny: true, message: \"...\"} to refuse the request (CAP_DENIED). Hook errors never block traffic. Empty = none."; "value"; "")

return $defaults

// MCP_Auth — resolves a Bearer token to a capability object.
//
// TWO STORES, chosen by TOKEN_STORE in 4D-mcp-config.pref:
//   "inline" (or absent) -> _loadTokens(), the in-memory object below. Demo and
//     test fixtures live here; editing them means editing this component.
//   "table" -> TOKEN_TABLE names a HOST dataclass. Tokens and their grants
//     become DATA, so granting a project a new action is a row edit, not a
//     component change. This is the store real deployments should use: a
//     component shared by several host projects cannot carry their tokens.
//
// Capability shape (wire contract 2):
//   { token_id: Text; read: []Text | "*"; write: []Text | "*"; call: []Text }
// read/write may be the wildcard "*" — every dataclass the server config
// exposes (RESPECT_4D_SCHEMA / WHITELIST_TABLES / BLACKLIST_TABLES). Exposure
// is enforced upstream by the config gate; the wildcard never widens it.
// Absent verb entry is normalized to an empty collection (no access).
// `call` takes NO wildcard: read/write are bounded by the exposure gate, but a
// call grant is bounded only by METHOD_WHITELIST, so it is enumerated always.
//
// TABLE ROW SHAPE (the dataclass named by TOKEN_TABLE):
//   tokenHash : Text    SHA-256 of the bearer, hex. See hashToken().
//   tokenId   : Text    the audit label; what logs record.
//   grants    : Object  { read; write; call } — the capability shape above.
//   isActive  : Boolean false = revoked; refused without deleting the audit row.
// The bearer itself is NEVER stored. A host that keeps plaintext tokens in a
// table has moved the secret from source control into the data file, which is
// not an improvement; the digest means a data-file leak yields nothing usable.
//
// FAIL CLOSED. TOKEN_STORE "table" whose TOKEN_TABLE is blank, misnamed or
// missing resolves NO token — it never falls back to the inline set. The
// alternative is a misconfigured production host quietly honouring SECRET_STAR.
// Any TOKEN_STORE value other than "inline"/"table" is likewise refused.
//
// The token table must never be readable through the very API it guards; the
// exclusion is enforced in MCP_Schema.exposedDataclasses, not here.

shared singleton Class constructor()

// validate: returns the normalized capability object, or Null if the token
// is missing / unknown / revoked. Never throws.
Function validate($token : Text) : Object
	if ($token=Null)
		return Null
	end if
	if (Length(String($token))=0)
		return Null
	end if
	var $cap : Object
	$cap:=This._lookup(String($token))
	if ($cap=Null)
		return Null
	end if
	return This._normalize($cap)

// _lookup: raw (un-normalized) capability object for a bearer, or Null.
// Routes on TOKEN_STORE. A Null config fails closed like every other gate.
Function _lookup($token : Text) : Object
	var $config : Object
	$config:=cs.MCP_Handler.me.getConfig()
	if ($config=Null)
		return Null
	end if
	var $store : Text
	$store:=Lowercase(String($config.TOKEN_STORE))
	if (Length($store)=0)
		$store:="inline"
	end if
	Case of
		: ($store="inline")
			return This._loadTokens()[$token]
		: ($store="table")
			return This._tableToken($config; $token)
	End case
	return Null  // unknown store name -> no access

// _tableToken: resolve a bearer against the host token dataclass. Returns the
// capability shape or Null. Never throws: a host table whose fields are named
// differently simply yields Null grants, i.e. a token with no access.
Function _tableToken($config : Object; $token : Text) : Object
	var $dcName : Text
	$dcName:=This.tokenTableName($config)
	if (Length($dcName)=0)
		return Null
	end if
	var $e : Object
	$e:=Null
	Try
		$e:=ds[$dcName].query("tokenHash = :1"; This.hashToken($token)).first()
	Catch
		return Null  // no such dataclass, or no tokenHash attribute
	End try
	if ($e=Null)
		return Null
	end if
	if (Not(Bool($e.isActive)))
		return Null  // revoked
	end if
	var $grants : Object
	$grants:=$e.grants
	if (Value type($grants)#Is object)
		$grants:=New object
	end if
	return New object(\
		"token_id"; String($e.tokenId); \
		"read"; $grants.read; \
		"write"; $grants.write; \
		"call"; $grants.call)

// tokenTableName: TOKEN_TABLE resolved to the datastore's canonical casing, or
// "" when the store is not table-backed or the name does not resolve. Public
// because MCP_Schema must exclude this dataclass from the exposed set.
Function tokenTableName($config : Object) : Text
	if ($config=Null)
		return ""
	end if
	if (Lowercase(String($config.TOKEN_STORE))#"table")
		return ""
	end if
	var $want : Text
	$want:=Lowercase(String($config.TOKEN_TABLE))
	if (Length($want)=0)
		return ""
	end if
	var $k : Text
	For each ($k; OB Keys(ds))
		if (Lowercase($k)=$want)
			return $k
		end if
	End for each
	return ""

// hashToken: the digest stored in tokenHash. Public so a host seeding routine
// computes it the same way this class does — the two must never drift.
Function hashToken($token : Text) : Text
	return Generate digest(String($token); SHA256 digest)

// _loadTokens: the inline store. Fixtures for the component's own self-tests
// and for a single-host demo. Keys are raw bearer strings; values are
// capability objects. Real deployments use TOKEN_STORE "table" instead.
Function _loadTokens() : Object
	var $t : Object
	$t:=New object
	// Full access: read both dataclasses, write Order, call two actions.
	$t["SECRET_FULL"]:=New object(\
		"token_id"; "tok_full"; \
		"read"; New collection("Customer"; "Order"); \
		"write"; New collection("Order"); \
		"call"; New collection("ping"; "order_count"; "echo_upper"))
	// Read-only, Customer only: no write, no call.
	$t["SECRET_RO"]:=New object(\
		"token_id"; "tok_ro"; \
		"read"; New collection("Customer"); \
		"write"; New collection; \
		"call"; New collection)
	// HPC4d trial: read-only on core business tables. Deliberately excludes
	// payroll, passwords, W2 and other sensitive dataclasses.
	$t["SECRET_HPC_RO"]:=New object(\
		"token_id"; "tok_hpc_ro"; \
		"read"; New collection("customers"; "workOrder"; "lineItem"; "header"); \
		"write"; New collection; \
		"call"; New collection)
	// Wildcard: read/write everything the server config exposes. Exposure
	// (RESPECT_4D_SCHEMA / WHITELIST / BLACKLIST) is the only table filter.
	$t["SECRET_STAR"]:=New object(\
		"token_id"; "tok_star"; \
		"read"; "*"; \
		"write"; "*"; \
		"call"; New collection("ping"; "order_count"; "echo_upper"))
	return $t

Function _normalize($cap : Object) : Object
	var $out : Object
	$out:=New object
	$out.token_id:=String($cap.token_id)
	$out.read:=This._asGrant($cap.read)
	$out.write:=This._asGrant($cap.write)
	$out.call:=This._asCollection($cap.call)
	return $out

// _asGrant: a read/write grant is either the wildcard "*" or a collection of
// dataclass names. Anything else (absent, wrong type, other strings) normalizes
// to an empty collection — no access.
Function _asGrant($v : Variant) : Variant
	if (Value type($v)=Is text)
		if (This._isStar($v))
			return "*"
		end if
		return New collection
	end if
	return This._asCollection($v)

// _isStar: exact match for "*" — 4D's text `=` treats @ as a wildcard, so a
// literal comparison could be fooled by "@"; compare by length + char code.
Function _isStar($v : Text) : Boolean
	return (Length($v)=1) && (Character code($v)=42)

// grantCovers: does a normalized read/write grant cover this dataclass name?
// Exposure is NOT checked here — the config gate owns that; a wildcard grant
// covers every name and relies on the exposure gate to bound it.
Function grantCovers($grant : Variant; $name : Text) : Boolean
	if (Value type($grant)=Is text)
		return This._isStar($grant)
	end if
	if (Value type($grant)#Is collection)
		return False
	end if
	return ($grant.indexOf($name)>=0)

Function _asCollection($v : Variant) : Collection
	if ($v=Null)
		return New collection
	end if
	if (Value type($v)#Is collection)
		return New collection
	end if
	return $v

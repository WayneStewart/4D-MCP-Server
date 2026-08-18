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
	return This._resolveTable($config)

// _resolveTable: TOKEN_TABLE in canonical casing, WITHOUT the TOKEN_STORE gate.
// issueToken/revokeToken use this so a host can create the first row while the
// store is still "inline" — otherwise seeding needs the switch thrown first,
// and the switch locks every client out until a row exists that cannot be
// created yet. Authentication and exposure keep the gated tokenTableName: a
// TOKEN_TABLE left set beside an inline store must not quietly become live.
Function _resolveTable($config : Object) : Text
	if ($config=Null)
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

// hashToken: the digest stored in tokenHash. Public so a caller can look a row
// up by hash without this class having to hand out a finder.
Function hashToken($token : Text) : Text
	return Generate digest(String($token); SHA256 digest)

// issueToken: mint a bearer into the host's token table. Returns
//   { success; message; token; tokenId }
// with `token` populated ONCE — only its digest is stored, so a lost token is
// reissued under a new id, never recovered.
//
// THIS LIVES IN THE COMPONENT ON PURPOSE. Everything it has to get right is
// this class's business: the digest algorithm, the {read; write; call} row
// shape, what isActive means. A host-side copy per project is the same method
// written N times, and the first edit to one of them puts a row in a shape
// MCP_Auth no longer reads — with no error to explain why a valid-looking token
// stopped validating.
//
// Not reachable through MCP: call_method only invokes host project methods, and
// the token table is excluded from the exposed set anyway. A host runs this
// from the method editor, or wraps it in a host method to log the result.
//
//   $tokenId  audit label, unique by convention. What logs record.
//   $grants   { read; write; call }. read/write are "*" or a collection of
//             dataclass names; call is a collection of ACTION names from
//             METHOD_WHITELIST — never host method names, which never cross
//             the wire, and never "*", which `call` does not accept.
Function issueToken($tokenId : Text; $grants : Object) : Object
	var $out : Object
	$out:=New object("success"; False; "message"; ""; "token"; ""; "tokenId"; String($tokenId))

	if (Length(String($tokenId))=0)
		$out.message:="A token needs an id — it is the only label the audit log carries."
		return $out
	end if

	var $config : Object
	$config:=cs.MCP_Handler.me.getConfig()
	var $dcName : Text
	$dcName:=This._resolveTable($config)
	if (Length($dcName)=0)
		$out.message:="No token table: set TOKEN_TABLE to a dataclass that exists, then try again. TOKEN_STORE may stay \"inline\" until the row is created."
		return $out
	end if

	var $dup : Boolean
	$dup:=False
	Try
		$dup:=(ds[$dcName].query("tokenId == :1"; String($tokenId)).length>0)
	Catch
		$out.message:="["+$dcName+"] does not carry the token row shape (tokenHash, tokenId, grants, isActive)."
		return $out
	End try
	if ($dup)
		$out.message:="A token with id \""+String($tokenId)+"\" already exists. Revoke it, or choose another id."
		return $out
	end if

	// Two UUIDs of entropy, dashes stripped, prefixed so a leaked string is
	// recognisable as an MCP credential in a log or a paste.
	var $token : Text
	$token:="mcp_"+Replace string(Generate UUID; "-"; "")+Replace string(Generate UUID; "-"; "")

	var $norm : Object
	$norm:=New object("read"; New collection; "write"; New collection; "call"; New collection)
	if ($grants#Null)
		$norm.read:=$grants.read
		$norm.write:=$grants.write
		$norm.call:=$grants.call
	end if

	var $e : Object
	$e:=ds[$dcName].new()
	$e.tokenHash:=This.hashToken($token)
	$e.tokenId:=String($tokenId)
	$e.grants:=$norm
	$e.isActive:=True
	var $saved : Object
	$saved:=$e.save()
	if (Not($saved.success))
		$out.message:="The token record could not be saved."
		return $out
	end if

	$out.success:=True
	$out.token:=$token
	$out.message:="Copy the token now — it is not stored and cannot be shown again."
	return $out

// revokeToken: flip isActive off by audit label, keeping the row. Deleting it
// would take the only evidence that the credential ever existed with it.
Function revokeToken($tokenId : Text) : Object
	var $out : Object
	$out:=New object("success"; False; "message"; "")
	var $dcName : Text
	$dcName:=This._resolveTable(cs.MCP_Handler.me.getConfig())
	if (Length($dcName)=0)
		$out.message:="No token table configured (TOKEN_TABLE is blank or names nothing)."
		return $out
	end if
	var $e : Object
	$e:=Null
	Try
		$e:=ds[$dcName].query("tokenId == :1"; String($tokenId)).first()
	Catch
		$out.message:="["+$dcName+"] does not carry the token row shape."
		return $out
	End try
	if ($e=Null)
		$out.message:="No token with id \""+String($tokenId)+"\"."
		return $out
	end if
	$e.isActive:=False
	if (Not($e.save().success))
		$out.message:="The token could not be revoked."
		return $out
	end if
	$out.success:=True
	$out.message:="Token \""+String($tokenId)+"\" revoked."
	return $out

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

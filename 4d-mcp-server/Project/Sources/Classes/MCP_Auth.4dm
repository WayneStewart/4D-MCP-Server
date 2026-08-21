// MCP_Auth — resolves a Bearer token to a capability object.
//
// Tokens are literals in this component's source, in _loadTokens(). That is the
// only store: there is no table, no minting call, no expiry, no revocation
// short of editing this method and rebuilding the component. It is closer to a
// short list of shared API keys than to session tokens, and it is meant to be
// read that way.
//
// This is deliberate. The MCP endpoint is a large, obvious hole in the host
// application, and dressing its credentials up as managed infrastructure would
// make it look smaller than it is. The controls that actually matter are blunt
// and immediate: remove the component (the host runs fine without it), or set
// ENABLED to false in 4D-mcp-config.pref (the component answers nothing on the
// next request, no restart). A token store with rows and lifecycles buys a
// sophisticated operator a little and everyone else nothing but the impression
// that this is safer than it is.
//
// Consequences worth stating, since they follow from the above:
//   - Every host that installs this component gets the same bearer strings.
//     Never add a host-specific token here.
//   - The bearers below are demo/self-test fixtures published in this repo.
//     A deployment replaces them; it does not add to them.
//
// Capability shape (wire contract 2):
//   { token_id: Text; read: []Text | "*"; write: []Text | "*" }
// read/write may be the wildcard "*" — every dataclass the server config
// exposes (RESPECT_4D_SCHEMA / WHITELIST_TABLES / BLACKLIST_TABLES). Exposure
// is enforced upstream by the config gate; the wildcard never widens it.
// Absent verb entry is normalized to an empty collection (no access).
//
// A capability says NOTHING about call_method. Which methods are reachable is
// a deployment question, answered entirely by ALLOW_CALL_METHOD and
// METHOD_WHITELIST in 4D-mcp-config.pref (plus 4D's own rule that the host
// method carry "Shared with components and host"). No token carries a `call`
// grant, and no token needs one: any token that authenticates may invoke any
// whitelisted action.

shared singleton Class constructor()

// validate: returns the normalized capability object, or Null if the token is
// missing or unknown. Never throws.
Function validate($token : Text) : Object
	if ($token=Null)
		return Null
	end if
	if (Length(String($token))=0)
		return Null
	end if
	var $cap : Object
	$cap:=This._loadTokens()[String($token)]
	if ($cap=Null)
		return Null
	end if
	return This._normalize($cap)

// _loadTokens: the token store. Keys are raw bearer strings; values are
// capability objects. Demo and self-test fixtures — a deployment replaces
// these, and must never add a token belonging to one particular host.
Function _loadTokens() : Object
	var $t : Object
	$t:=New object
	// Full access: read both dataclasses, write Order.
	$t["SECRET_FULL"]:=New object(\
		"token_id"; "tok_full"; \
		"read"; New collection("Customer"; "Order"); \
		"write"; New collection("Order"))
	// Read-only, Customer only: no write.
	$t["SECRET_RO"]:=New object(\
		"token_id"; "tok_ro"; \
		"read"; New collection("Customer"); \
		"write"; New collection)
	// Wildcard: read/write everything the server config exposes. Exposure
	// (RESPECT_4D_SCHEMA / WHITELIST / BLACKLIST) is the only table filter.
	$t["SECRET_STAR"]:=New object(\
		"token_id"; "tok_star"; \
		"read"; "*"; \
		"write"; "*")
	return $t

Function _normalize($cap : Object) : Object
	var $out : Object
	$out:=New object
	$out.token_id:=String($cap.token_id)
	$out.read:=This._asGrant($cap.read)
	$out.write:=This._asGrant($cap.write)
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

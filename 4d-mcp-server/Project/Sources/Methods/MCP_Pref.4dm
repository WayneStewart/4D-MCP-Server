//%attributes = {"invisible":true,"shared":true}
/* Purpose: Get or set one deployment-config setting.
 ------------------
MCP_Pref ($key : Text {; $newValue : Variant}) : Variant
	// with one parameter: the setting's current value
	// with two: sets it, and returns the value now in force
 Created by: Wayne Stewart, 2026-10-23

 The supported way for host code to read or change a setting, instead of
 editing 4D-mcp-config.pref by hand:

	$https:=MCP_Pref("REQUIRE_HTTPS")
	MCP_Pref("REQUIRE_HTTPS"; False)

 Shared, so the host can call it (guarded by COMPONENT LIST, as for
 MCP_Initialize_Host). It works stand-alone, on the server and on a remote
 client: the file is read and written on the server (MCP_Pref_Server). A set
 is live on the next request, except HTTP_PORT, which needs a server restart.

 It complains, with throw, rather than failing quietly:
	1  an unknown key (anything not in MCP_ConfigDefaults, or a "_" doc key);
	2  a value whose type differs from the default's — Boolean for the
	   ALLOW_* gates and REQUIRE_HTTPS, a number for HTTP_PORT and the
	   limits, Text, an object for METHOD_WHITELIST, a collection for the
	   table lists (any number type matches any other);
	3  a read or write the server could not do, or a value the component's
	   loader would not accept (the file is then left as it was).
 The checks run in the caller's process, so the error surfaces there.
 Beyond the type, values are not range-checked here; the config editor
 (MCP_ConfigFile.validate) applies the full rules.
*/

#DECLARE($key : Text; $newValue : Variant) : Variant

var $defaults : Object
$defaults:=MCP_ConfigDefaults

if ((Substring($key; 1; 1)="_") || (Value type($defaults[$key])#Is object))
	throw(1; "MCP_Pref: unknown setting \""+$key+"\"")
	return Null
end if

var $set : Boolean
$set:=(Count parameters>=2)

if ($set)
	var $expected; $given : Integer
	$expected:=Value type($defaults[$key].value)
	$given:=Value type($newValue)

	// every number type stands for every other (JSON numbers come back as Real)
	if (($expected=Is longint) || ($expected=Is integer))
		$expected:=Is real
	end if
	if (($given=Is longint) || ($given=Is integer))
		$given:=Is real
	end if

	if ($given#$expected)
		var $names : Object
		$names:=New object(String(Is real); "a number"; String(Is boolean); "a Boolean"; String(Is text); "Text"; \
			String(Is object); "an object"; String(Is collection); "a collection"; String(Is null); "Null")
		throw(2; "MCP_Pref: "+$key+" expects "+String($names[String($expected)])+", not "+String($names[String($given)]))
		return Null
	end if
end if

var $result : Object
if ($set)
	$result:=MCP_Pref_Server($key; True; $newValue)
else
	$result:=MCP_Pref_Server($key; False)
end if

if (Not(Bool($result.ok)))
	throw(3; "MCP_Pref: "+$key+": "+String($result.error))
	return Null
end if

return $result.value

//%attributes = {"invisible":true,"executedOnServer":true}
/* Purpose: The server half of MCP_Pref — reads or writes one setting.
 ------------------
MCP_Pref_Server ($key : Text; $set : Boolean {; $newValue : Variant}) : Object
	// {ok: Boolean; value: Variant; error: Text}
 Created by: Wayne Stewart, 2026-10-23

 Executed on the server, so a remote client gets and sets the SERVER's config
 (MCP_Handler._configFile()); stand-alone and on the server it runs locally.
 It never throws: MCP_Pref has already checked the key and the value's type,
 and turns a failure reported here into an error in the caller's process —
 whether an error raised inside an Execute-on-Server method reaches the
 calling client is not something to rely on.

 A set rewrites only that key's value (its comment is kept, or taken from
 MCP_ConfigDefaults for a key the file lacks), inside Use (MCP_ConfigLock).
 If getConfig() would then refuse the file, the previous text is put back and
 the set is reported failed.
*/

#DECLARE($key : Text; $set : Boolean; $newValue : Variant) : Object

var $result : Object
$result:=New object("ok"; False; "value"; Null; "error"; "")

var $config : Object
$config:=cs.MCP_Handler.me.getConfig()  // also creates the file when the host has none

if ($config=Null)
	$result.error:="the config could not be read: "+cs.MCP_Handler.me._configFile().platformPath
	return $result
end if

if (Not($set))
	$result.ok:=True
	$result.value:=$config[$key]
	return $result
end if

var $lock : Object
$lock:=MCP_ConfigLock

Use ($lock)
	Try
		var $file : 4D.File
		$file:=cs.MCP_Handler.me._configFile()
		var $previous : Text
		$previous:=$file.getText()
		var $raw : Variant
		$raw:=Try(JSON Parse($previous))

		if (Value type($raw)#Is object)
			$result.error:="the config file is not a JSON object: "+$file.platformPath
		else
			if (Value type($raw[$key])=Is object)
				$raw[$key].value:=$newValue
			else
				var $defaults : Object
				$defaults:=MCP_ConfigDefaults
				$raw[$key]:=New object("comment"; String($defaults[$key].comment); "value"; $newValue)
			end if

			$file.setText(JSON Stringify($raw; *))
			$config:=cs.MCP_Handler.me.getConfig()

			if ($config=Null)
				$file.setText($previous)  // the component would refuse every request: put the old file back
				$result.error:="the component could not load the result, so the previous config was restored"
			else
				$result.ok:=True
				$result.value:=$config[$key]
			end if
		end if
	Catch
		$result.error:="the config file could not be written: "+cs.MCP_Handler.me._configFile().platformPath
	End try
End use

return $result

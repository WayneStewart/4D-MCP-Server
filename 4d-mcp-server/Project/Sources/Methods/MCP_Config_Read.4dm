//%attributes = {"invisible":true,"executedOnServer":true}
// ----------------------------------------------------
// Project Method: MCP_Config_Read --> $result_o : Object

// Returns the text of the live deployment config, for the config editor
// (MCP_ConfigFile). Executed on the server, so a remote client reads the
// SERVER's file (MCP_Handler._configFile(): <data folder>/Settings/
// 4D-mcp-config.pref), which a client cannot address itself. Stand-alone and
// on the server it simply runs locally.

// getConfig() runs first so that a missing data-folder copy is seeded exactly
// as the request path would seed it. The fingerprint (SHA-256 of the text) is
// handed back to MCP_Config_Write, which refuses to save over a file that has
// changed since it was read.

// Access: Private

// Parameters: None

// Returns:
//   $result_o : Object : {ok: Boolean; text: Text; path: Text; fingerprint: Text; error: Text}

// Created by Claude (2026-10-23)
// ----------------------------------------------------

#DECLARE->$result_o : Object

var $config_file : 4D.File
var $text_t : Text

$result_o:=New object("ok"; False; "text"; ""; "path"; ""; "fingerprint"; ""; "error"; "")

cs.MCP_Handler.me.getConfig()  // seeds the data-folder copy when it is missing

$config_file:=cs.MCP_Handler.me._configFile()
$result_o.path:=$config_file.platformPath

If ($config_file.exists)

	Try
		$text_t:=$config_file.getText()
		$result_o.text:=$text_t
		$result_o.fingerprint:=Generate digest($text_t; SHA256 digest)
		$result_o.ok:=True

	Catch
		$result_o.error:="Config could not be read: "+$result_o.path

	End try

Else
	$result_o.error:="Config not found: "+$result_o.path

End if

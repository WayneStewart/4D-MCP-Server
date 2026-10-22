//%attributes = {"invisible":true,"executedOnServer":true}
// ----------------------------------------------------
// Project Method: MCP_Config_Write ($text_t : Text; $fingerprint_t : Text) --> $result_o : Object

// Saves the config editor's document (MCP_ConfigFile.save) over the live
// deployment config. Executed on the server, so a save from a remote client
// lands in the SERVER's file (MCP_Handler._configFile()); stand-alone and on
// the server it runs locally.

// Three guards, in order:
//   1. The file must still have the fingerprint MCP_Config_Read gave the
//      editor: if anyone changed it since, nothing is written and the editor
//      is told to reload (no silent overwrite of someone else's edit).
//   2. The text must parse as a JSON object.
//   3. After writing, MCP_Handler.getConfig() must accept the file. It fails
//      closed on a malformed entry — which would refuse every request — so on
//      failure the previous text is put back and the save is reported failed.
// The whole check-and-write runs inside Use (MCP_ConfigLock), the lock
// MCP_Pref also takes, so the two cannot interleave. The new fingerprint is
// returned so the editor can save again.

// Access: Private

// Parameters:
//   $text_t        : Text : The whole config document, as JSON text
//   $fingerprint_t : Text : The fingerprint the editor's copy was read with

// Returns:
//   $result_o : Object : {ok: Boolean; path: Text; fingerprint: Text; conflict: Boolean; error: Text}

// Created by Claude (2026-10-23)
// ----------------------------------------------------

#DECLARE($text_t : Text; $fingerprint_t : Text)->$result_o : Object

var $config_file : 4D.File
var $current_t : Text

$result_o:=New object("ok"; False; "path"; ""; "fingerprint"; ""; "conflict"; False; "error"; "")

$config_file:=cs.MCP_Handler.me._configFile()
$result_o.path:=$config_file.platformPath

var $lock_o : Object
$lock_o:=MCP_ConfigLock  // the same lock MCP_Pref takes

Use ($lock_o)
	Try
		$current_t:=""

		If ($config_file.exists)
			$current_t:=$config_file.getText()
		End if

		Case of
			: (Generate digest($current_t; SHA256 digest)#$fingerprint_t)
				$result_o.conflict:=True
				$result_o.error:="The config was changed by someone else since it was loaded. Reload it, then make your changes again."

			: (Value type(Try(JSON Parse($text_t)))#Is object)
				$result_o.error:="Refused to write: the document does not parse as a JSON object."

			Else
				$config_file.parent.create()  // a fresh data folder may have no Settings/ yet
				$config_file.setText($text_t)

				If (cs.MCP_Handler.me.getConfig()=Null)
					// The component would refuse every request with this file: put the old one back
					If ($current_t#"")
						$config_file.setText($current_t)
					End if

					$result_o.error:="Refused to save: the component could not load the result, so the previous config was restored."

				Else
					$result_o.ok:=True
					$result_o.fingerprint:=Generate digest($text_t; SHA256 digest)

				End if

		End case

	Catch
		$result_o.error:="Config could not be written: "+$result_o.path

	End try
End use

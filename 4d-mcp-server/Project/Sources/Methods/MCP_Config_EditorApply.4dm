//%attributes = {"invisible":true}
// ----------------------------------------------------
// Project Method: MCP_Config_EditorApply --> $ok_b : Boolean

// Writes the config editor's current settings to the server's config file
// (the work behind both Save and Apply) and leaves the window open. Folds the
// table ticks back into the two config lists, then hands the values to
// MCP_ConfigFile.save, which validates before it writes and never touches a
// key's comment.

// On success the form is refreshed from the class (so it shows exactly what
// was written), the status line is updated and a new clean snapshot is
// taken (see MCP_Config_EditorDirty). Warnings are shown only if there are
// any, since they describe consequences rather than mistakes; a port change
// is called out separately because HTTP_PORT is read once at startup. On
// failure the errors are shown (or the server's refusal when there are no
// validation errors) and the form is left as it was.

// Operates on Form, so it must be called during a form event.

// Access: Private

// Parameters: None

// Returns:
//   $ok_b : Boolean : True if the file was written

// Created by Claude (2026-10-23)
// ----------------------------------------------------

#DECLARE->$ok_b : Boolean

$ok_b:=False

Form.config.applyTableRows(Form.values; Form.tables)

var $portWas_i : Integer:=Num(Form.config.document.HTTP_PORT.value)
var $status_o : Object:=Form.config.save(Form.values)
var $errors_c : Collection:=$status_o.issues.query("level = :1"; "error")
var $warnings_c : Collection:=$status_o.issues.query("level = :1"; "warning")

If (Not(Bool($status_o.success)))
	Form.status:=$status_o.message

	If ($errors_c.length>0)
		ALERT("Not saved:\r\r"+$errors_c.extract("message").join("\r"))

	Else
		// refused by the server (MCP_Config_Write): changed by someone else, or the result would not load
		ALERT("Not saved:\r\r"+$status_o.message)

	End if

Else
	$ok_b:=True

	// the class now holds what was written; show exactly that
	Form.values:=Form.config.values()
	Form.tables:=Form.config.tableRows(Form.values)
	Form.actions:=Form.config.actionRows(Form.values)

	Form.currentTable:=Null
	Form.currentAction:=Null
	Form.actionJSON:=""

	Form.status:="Applied — "+Form.config.path
	Form.cleanSnapshot:=Form.config.snapshot(Form.values; Form.tables)

	var $message_t : Text:=""

	If ($portWas_i#Num(Form.values.HTTP_PORT))
		$message_t:="The port changed — restart 4D for it to take effect."

	End if

	If ($warnings_c.length>0)
		If ($message_t#"")
			$message_t:=$message_t+"\r\r"
		End if

		$message_t:=$message_t+"Worth knowing:\r"+$warnings_c.extract("message").join("\r")

	End if

	If ($message_t#"")
		ALERT("Configuration saved.\r\r"+$message_t)
	End if

End if

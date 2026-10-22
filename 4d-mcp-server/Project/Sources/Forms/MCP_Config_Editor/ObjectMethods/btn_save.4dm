//  Object method — btn_save
//
//  Fires only On Clicked. Folds the table ticks back into the two config
//  lists, then hands the values to the class, which validates before it
//  writes and never touches a key's comment.
//
//  Errors keep the window open so they can be fixed; warnings are shown
//  after a successful save, since they describe consequences rather than
//  mistakes. A port change is called out separately: HTTP_PORT is read once
//  at startup, so nothing happens until 4D restarts.

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
	var $message_t : Text:="Configuration saved."

	If ($portWas_i#Num(Form.values.HTTP_PORT))
		$message_t:=$message_t+"\r\rThe port changed — restart 4D for it to take effect."

	End if

	If ($warnings_c.length>0)
		$message_t:=$message_t+"\r\rWorth knowing:\r"+$warnings_c.extract("message").join("\r")

	End if

	ALERT($message_t)
	ACCEPT

End if

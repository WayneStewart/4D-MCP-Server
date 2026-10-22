//  Object method — btn_actionRemove
//
//  Fires only On Clicked. Removing an entry closes a door into host code,
//  so it needs no ceremony beyond a confirmation.

If (Form.currentAction=Null)
	Form.status:="Select an action to remove."

Else
	var $name_t : Text:=String(Form.currentAction.name)
	CONFIRM("Remove the callable action \""+$name_t+"\"?"; "Remove"; "Keep")

	If (OK=1)
		var $whitelist_o : Object:=Form.values.METHOD_WHITELIST
		OB REMOVE($whitelist_o; $name_t)
		Form.actions:=Form.config.actionRows(Form.values)
		Form.currentAction:=Null
		Form.actionJSON:=""
		Form.status:="Removed \""+$name_t+"\" — not saved yet."

	End if

End if

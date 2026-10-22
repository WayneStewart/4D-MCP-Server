//  Object method — input_actionJSON
//
//  Fires only On Data Change. Parses the edited JSON back into the pending
//  values. Only well-formed JSON objects are applied — a half-typed entry
//  must not reach the file, where getConfig() would fail closed on it.
//
//  The full shape check (method name, argument types, optional-args-last)
//  happens in MCP_ConfigFile.validate() when Save is pressed.

If (Form.currentAction=Null)
	Form.status:="Select an action before editing its definition."

Else
	var $parsed_v : Variant:=Try(JSON Parse(Form.actionJSON))

	If (Value type($parsed_v)=Is object)
		Form.values.METHOD_WHITELIST[String(Form.currentAction.name)]:=$parsed_v
		Form.currentAction.method:=String($parsed_v.method)
		Form.status:="\""+String(Form.currentAction.name)+"\" updated — not saved yet."

	Else
		Form.status:="Not a JSON object — the change was not applied."

	End if

End if

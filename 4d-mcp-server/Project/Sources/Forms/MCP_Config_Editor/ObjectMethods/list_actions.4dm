//  Object method — list_actions
//
//  Fires only On Selection Change. Shows the selected whitelist entry as
//  JSON in the detail pane: each entry carries an ordered, typed argument
//  spec, which no reasonable arrangement of fields would edit more clearly
//  than the JSON itself.

If (Form.currentAction=Null)
	Form.actionJSON:=""

Else
	Form.actionJSON:=JSON Stringify(Form.values.METHOD_WHITELIST[String(Form.currentAction.name)]; *)

End if

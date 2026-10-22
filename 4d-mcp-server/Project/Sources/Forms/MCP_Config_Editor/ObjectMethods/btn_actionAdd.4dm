//  Object method — btn_actionAdd
//
//  Fires only On Clicked. Adds a skeleton whitelist entry for the developer
//  to fill in through the JSON pane. It is deliberately born incomplete
//  (empty "method"), so Save refuses it until it names a host method —
//  better than a plausible-looking default that quietly exposes something.

var $name_t : Text:=Request("Action name, as MCP clients will see it:"; "")

If (OK=1) && ($name_t#"")

	If (Form.values.METHOD_WHITELIST[$name_t]#Null)
		Form.status:="\""+$name_t+"\" is already in the whitelist."

	Else
		Form.values.METHOD_WHITELIST[$name_t]:=New object(\
			"method"; ""; \
			"args"; New collection; \
			"return"; ""; \
			"purpose"; "")

		Form.actions:=Form.config.actionRows(Form.values)
		Form.currentAction:=Null
		Form.actionJSON:=""
		Form.status:="Added \""+$name_t+"\" — select it and fill in the host method."

	End if

End if

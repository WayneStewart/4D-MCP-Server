//  Object method — btn_revert
//
//  Fires only On Clicked. Discards pending edits and re-reads the file.
//  The reload repeats the form method's On Load: MCP_ConfigFile does the
//  work, so it is a handful of lines rather than a shared method.

CONFIRM("Discard unsaved changes and reload the config file?"; "Discard"; "Keep editing")

If (OK=1)
	Form.config:=cs.MCP_ConfigFile.new()
	Form.values:=Form.config.values()
	Form.tables:=Form.config.tableRows(Form.values)
	Form.actions:=Form.config.actionRows(Form.values)

	Form.currentTable:=Null
	Form.currentAction:=Null
	Form.actionJSON:=""

	If (Form.config.loadError#"")
		Form.status:=Form.config.loadError

	Else
		Form.status:=Form.config.path

	End if

End if

//  Object method — btn_revert
//
//  Fires only On Clicked. Discards pending edits and re-reads the file,
//  which after an Apply holds the latest applied settings. Asks for
//  confirmation only if the form has unsaved changes. The reload repeats the
//  form method's On Load: MCP_ConfigFile does the work, so it is a handful
//  of lines rather than a shared method.
//
//  Claude, 2026-10-23 - confirm only when dirty; new clean snapshot after reverting

var $revert_b : Boolean:=True

If (MCP_Config_EditorDirty)
	CONFIRM("Discard unsaved changes and reload the config file?"; "Discard"; "Keep editing")
	$revert_b:=(OK=1)
End if

If ($revert_b)
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

	Form.cleanSnapshot:=Form.config.snapshot(Form.values; Form.tables)
End if

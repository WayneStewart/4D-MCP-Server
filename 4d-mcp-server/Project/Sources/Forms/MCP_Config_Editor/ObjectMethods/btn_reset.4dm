//  Object method — btn_reset
//
//  Fires only On Clicked. Replaces every setting in the form with the
//  built-in defaults (MCP_ConfigDefaults). Nothing is written: the form
//  becomes dirty, and Apply or Save writes the defaults out.
//
//  Claude, 2026-10-23 - created

Form.values:=Form.config.defaultValues()
Form.tables:=Form.config.tableRows(Form.values)
Form.actions:=Form.config.actionRows(Form.values)

Form.currentTable:=Null
Form.currentAction:=Null
Form.actionJSON:=""

Form.status:="Built-in defaults loaded — Apply or Save to write them"

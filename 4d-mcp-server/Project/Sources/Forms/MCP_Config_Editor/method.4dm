//  Form method — MCP_Config_Editor
//
//  Editor for the 4d-mcp-server deployment config
//  (<data folder>/Settings/4D-mcp-config.pref). MCP_ConfigFile reads and
//  writes it on the server (MCP_Config_Read / MCP_Config_Write), so the
//  editor also works on a live server and from a remote client. HTTP_PORT is
//  read once at startup, so a port change needs a server restart; every other
//  setting is live on the next request.
//
//  Every control binds straight to Form.values, which is the flat key ->
//  value view of the file. The two exceptions are the table lists and the
//  method whitelist: WHITELIST_TABLES/BLACKLIST_TABLES are edited as ticks
//  over the live dataclass list and folded back on save, and METHOD_WHITELIST
//  entries are edited as JSON in the detail pane, since each carries an
//  ordered, typed argument spec.
//
//  Form.cleanSnapshot is the comparable state at load / Apply / Revert;
//  MCP_Config_EditorDirty compares against it. On Close Box goes to
//  MCP_Config_EditorClose (asks to save) and is deliberately NOT forwarded
//  to Foundation, whose Fnd_Gen_FormMethod would close the window regardless.
//
//  Claude, 2026-10-23 - dirty tracking; close box asks to save
//

var $foundationPresent_b : Boolean
ARRAY TEXT($Components_at; 0)

COMPONENT LIST($Components_at)
$foundationPresent_b:=(Find in array($Components_at; "Foundation@")>0)

Case of 
	: (Form event code=On Load)
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
		
	: (Form event code=On Close Box)
		var $closed_b : Boolean:=MCP_Config_EditorClose
		
End case 

If ($foundationPresent_b) && (Form event code#On Close Box)
	EXECUTE METHOD("Fnd_Gen_FormMethod"; *)
End if 

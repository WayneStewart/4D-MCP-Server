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
//  MCP_Config_EditorDirty compares against it.
//
//  Closing, with Foundation present. Fnd_Gen_FormMethod closes this window
//  on the close box (Option held: Fnd_Wnd_CloseAllWindows first, closing every
//  window) and on any event while a close-all or quit is under way. It never
//  asks to save, so:
//    - On Close Box with nothing unsaved: forwarded to Fnd_Gen_FormMethod
//      unchanged, Option-click close-all included.
//    - On Close Box with unsaved changes: MCP_Config_EditorClose asks first.
//      The Option key is read BEFORE the dialog (it is usually released by
//      the time the user answers); if the window then closes and Option was
//      down, Fnd_Wnd_CloseAllWindows is called, as Fnd_Gen_FormMethod would.
//    - Any other event during a close-all or quit (Fnd_Wnd_CloseNow /
//      Fnd_Gen_QuitNow) with unsaved changes: MCP_Config_EditorClose asks,
//      as Fnd_IO_InputFormClose does for input forms; its Cancel abandons the
//      close-all / quit. Otherwise every event goes to Fnd_Gen_FormMethod.
//  Without Foundation: On Close Box goes to MCP_Config_EditorClose.
//
//  Claude, 2026-10-23 - dirty tracking; close box asks to save
//  Claude, 2026-10-23 - Fnd_Gen_FormMethod runs on the close box again (Option-click close-all); close-all and quit ask to save
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
		
End case 

var $closed_b; $optionDown_b; $closeAll_b; $quitting_b : Boolean

Case of 
	: (Form event code=On Close Box)
		$optionDown_b:=Macintosh option down  // read now: it is usually released by the time a dialog is answered
		
		Case of 
			: (Not($foundationPresent_b))
				$closed_b:=MCP_Config_EditorClose
				
			: (Not(MCP_Config_EditorDirty))
				EXECUTE METHOD("Fnd_Gen_FormMethod"; *)  // closes; Option held = close all windows
				
			Else 
				$closed_b:=MCP_Config_EditorClose  // asks to save
				
				If ($closed_b && $optionDown_b)
					EXECUTE METHOD("Fnd_Wnd_CloseAllWindows")
				End if 
				
		End case 
		
	: ($foundationPresent_b)
		// a close-all or quit reaches this window through Fnd_Gen_FormMethod, which would close it unasked
		EXECUTE METHOD("Fnd_Wnd_CloseNow"; $closeAll_b)
		EXECUTE METHOD("Fnd_Gen_QuitNow"; $quitting_b)
		
		If (($closeAll_b || $quitting_b) && MCP_Config_EditorDirty)
			$closed_b:=MCP_Config_EditorClose  // its Cancel abandons the close-all / quit
			
		Else 
			EXECUTE METHOD("Fnd_Gen_FormMethod"; *)
			
		End if 
		
End case 

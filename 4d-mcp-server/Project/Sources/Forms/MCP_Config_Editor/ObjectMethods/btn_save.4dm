//  Object method — btn_save
//
//  Fires only On Clicked. Saves through MCP_Config_EditorApply (validates,
//  writes, shows any alerts) and closes the window only if the save
//  succeeded; errors keep it open so they can be fixed.
//
//  Claude, 2026-10-23 - shared routine moved to MCP_Config_EditorApply

If (MCP_Config_EditorApply)
	ACCEPT
End if

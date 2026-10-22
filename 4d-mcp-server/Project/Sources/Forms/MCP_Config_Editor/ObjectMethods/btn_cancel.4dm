//  Object method — btn_cancel
//
//  Fires only On Clicked. Closes the window, first asking whether to save
//  if there are unsaved changes (MCP_Config_EditorClose).
//
//  Claude, 2026-10-23 - created (was the automatic cancel action)

var $closed_b : Boolean:=MCP_Config_EditorClose

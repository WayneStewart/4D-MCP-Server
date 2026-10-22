//%attributes = {"invisible":true}
// ----------------------------------------------------
// Project Method: MCP_Config_EditorDirty --> $dirty_b : Boolean

// True when the config editor's form differs from the last loaded, applied
// or reverted state. Compares MCP_ConfigFile.snapshot (settings with the
// table ticks folded in, on a copy so the live rows are undisturbed) with
// Form.cleanSnapshot, which the form method (On Load), MCP_Config_EditorApply
// and btn_revert take. Edits to the method whitelist and table ticks both
// count, since they live in Form.values and Form.tables.

// Operates on Form, so it must be called during a form event.

// Access: Private

// Parameters: None

// Returns:
//   $dirty_b : Boolean : True if there are unsaved changes

// Created by Claude (2026-10-23)
// ----------------------------------------------------

#DECLARE->$dirty_b : Boolean

$dirty_b:=(Form.config.snapshot(Form.values; Form.tables)#String(Form.cleanSnapshot))

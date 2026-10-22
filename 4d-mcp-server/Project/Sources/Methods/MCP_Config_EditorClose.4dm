//%attributes = {"invisible":true}
// ----------------------------------------------------
// Project Method: MCP_Config_EditorClose --> $closed_b : Boolean

// Closes the config editor, asking first whether to save if there are unsaved
// changes. Called by the form method (On Close Box) and by btn_cancel. The
// form method does not forward On Close Box to Foundation, whose handler
// would close the window regardless.

// With Foundation present the question is Foundation's own Save/Cancel/Don't
// Save sheet, following Fnd_IO_InputFormClose (shared methods, reached through
// EXECUTE METHOD so the component still compiles without it); otherwise a
// CONFIRM. Cancel also abandons any pending quit / close-all. The window closes only if the user
// chose not to save, or the save succeeded.

// Operates on Form, so it must be called during a form event.

// Access: Private

// Parameters: None

// Returns:
//   $closed_b : Boolean : True if the window will be closed

// Created by Claude (2026-10-23)
// ----------------------------------------------------

#DECLARE->$closed_b : Boolean

var $foundationPresent_b : Boolean
var $choice_i; $position_i : Integer
ARRAY TEXT($Components_at; 0)

$closed_b:=False

If (MCP_Config_EditorDirty)
	COMPONENT LIST($Components_at)
	$foundationPresent_b:=(Find in array($Components_at; "Foundation@")>0)

	If ($foundationPresent_b)
		// Wait until this process is frontmost.
		If (Current process#Frontmost process(*))
			BRING TO FRONT(Current process)
		End if 
		While (Current process#Frontmost process(*))
			DELAY PROCESS(Current process; 5)
		End while 

		BEEP
		EXECUTE METHOD("Fnd_Wnd_Position"; $position_i; 3)  // 3 = Fnd_Wnd_MacOSXSheet; Fnd_Wnd_Position returns a value, so it needs a result variable, not *
		EXECUTE METHOD("Fnd_Dlg_SetText"; *; "Save changes?"; "If you don't save, your changes to the MCP configuration will be lost.")
		EXECUTE METHOD("Fnd_Dlg_SetButtons"; *; "*"; "*"; "*")
		EXECUTE METHOD("Fnd_Dlg_SetIcon"; *; 2)  // 2 = Fnd_Dlg_WarnIcon
		EXECUTE METHOD("Fnd_Dlg_Display"; $choice_i)

		Case of 
			: ($choice_i=1)  // Save: close only if the save succeeded
				If (MCP_Config_EditorApply)
					$closed_b:=True
					CANCEL
				End if 

			: ($choice_i=2)  // Don't Save
				$closed_b:=True
				CANCEL

			Else   // Cancel: abandon any pending quit / close-all and stay open
				EXECUTE METHOD("Fnd_Gen_CancelQuit")
				EXECUTE METHOD("Fnd_Wnd_CancelCloseAll")
		End case 

	Else 
		CONFIRM("Save changes before closing?"; "Save"; "Don't Save")

		If (OK=1)
			If (MCP_Config_EditorApply)
				$closed_b:=True
				CANCEL
			End if 

		Else 
			$closed_b:=True
			CANCEL
		End if 
	End if 

Else 
	$closed_b:=True
	CANCEL
End if 

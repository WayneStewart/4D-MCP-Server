//%attributes = {"invisible":true,"shared":true}
// ----------------------------------------------------
// Project Method: MCP_Config_Editor ()

// Opens the editor for the 4d-mcp-server deployment config
// (<data folder>/Settings/4D-mcp-config.pref). Shared, so the host can call
// it (guarded by COMPONENT LIST, as for MCP_Initialize_Host). It works
// stand-alone, on the server and on a remote client: the file is read and
// written on the server (MCP_Config_Read / MCP_Config_Write). HTTP_PORT is
// read once at startup, so changing it needs a server restart.

// Foundation, when the host has it, supplies the menu bar and the Window
// menu entry; every call to it is guarded, so the editor runs without it.

// Created by Wayne Stewart (23/8/2026)
//  Method is an autostart type
//     waynestewart@mac.com
// Claude, 2026-10-23 - moved into the component; reads and writes the server's data-folder config
// Claude, 2026-10-23 - plain, resizable, non-modal window with a close box (was Movable form dialog box)
// ----------------------------------------------------

var $ProcessID_i; $StackSize_i; $WindowID_i : Integer
var $Form_t; $DesiredProcessName_t : Text
var $foundationPresent_b : Boolean
ARRAY TEXT($Components_at; 0)

// ----------------------------------------------------

$StackSize_i:=0

$DesiredProcessName_t:=Current method name
$Form_t:=$DesiredProcessName_t
If (Current process name=$DesiredProcessName_t)
	
	COMPONENT LIST($Components_at)
	$foundationPresent_b:=(Find in array($Components_at; "Foundation@")>0)
	
	$windowID_i:=Open form window($Form_t; Plain form window; Horizontally centered; Vertically centered; *)
	
	If ($foundationPresent_b)
		SET WINDOW TITLE("MCP Editor")
		EXECUTE METHOD("Fnd_Gen_MenuBar"; *)
		EXECUTE METHOD("Fnd_Menu_Window_Add"; *)
	End if 
	
	DIALOG("MCP_Config_Editor")
	
	If ($foundationPresent_b)
		EXECUTE METHOD("Fnd_Menu_Window_Remove"; *)
	End if 
	CLOSE WINDOW
	
	
Else 
	// This version allows for any number of processes
	// $ProcessID_i:=New Process(Current method name;$StackSize_i;$DesiredProcessName_t)
	
	// On the other hand, this version allows for one unique process
	$ProcessID_i:=New process(Current method name; $StackSize_i; $DesiredProcessName_t; *)
	
	RESUME PROCESS($ProcessID_i)
	SHOW PROCESS($ProcessID_i)
	BRING TO FRONT($ProcessID_i)
End if 




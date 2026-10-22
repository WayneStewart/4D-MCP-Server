//%attributes = {"invisible":true,"preemptive":"capable"}
/* Purpose: The shared object every writer of the config file locks.
 ------------------
MCP_ConfigLock () : Object   // a shared object; Use it around a read-modify-write
 Created by: Wayne Stewart, 2026-10-23

 MCP_Pref_Server (and any other code that rewrites the host's config file)
 does its read-modify-write inside Use (MCP_ConfigLock) ... End use, so two
 writers cannot interleave and lose one another's change. Kept in the
 component's own Storage, created on first use.
*/

#DECLARE : Object

if (Storage.mcpConfigLock=Null)
	Use (Storage)
		if (Storage.mcpConfigLock=Null)
			Storage.mcpConfigLock:=New shared object
		end if
	End use
end if

return Storage.mcpConfigLock

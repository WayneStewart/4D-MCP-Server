//  Object method — list_tables
//
//  Fires only On Data Change, i.e. when "Only" or "Never" is ticked.
//
//  The two lists are not independent: a non-empty whitelist makes the
//  blacklist irrelevant. Rather than let a row claim both and leave the
//  reader guessing which wins, "Only" clears "Never" on the same row —
//  the same precedence the component applies at request time.

var $row_o : Object:=Form.currentTable

If ($row_o#Null)

	If (Bool($row_o.inWhitelist)) && (Bool($row_o.inBlacklist))
		$row_o.inBlacklist:=False
		Form.status:="\""+String($row_o.name)+"\" is in the whitelist, so its blacklist tick was cleared."

	End if

End if

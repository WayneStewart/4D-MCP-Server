/*  MCP_ConfigFile
 Created by: Claude (2026-08-22)
 ------------------
 Read, validate and write the 4d-mcp-server deployment config
 (MCP_Handler._configFile(): <data folder>/Settings/4D-mcp-config.pref).

 Every key in that file is a {comment, value} pair, and the component's
 MCP_Handler.getConfig() fails closed on any malformed entry — so this class
 only ever replaces `value`, never a `comment`, and refuses to write a
 document that would not parse back.

 The class never touches the file itself: it reads through MCP_Config_Read
 and writes through MCP_Config_Write, both executed on the server. So the
 editor works the same stand-alone, on the server, and on a remote client,
 where it edits the SERVER's file. The fingerprint from the read travels back
 with the write, which refuses to save over a file changed in the meantime.

 Self-contained by design (FDT-171): no Foundation, nothing 4D Today
 specific.
*/

property path : Text
property fingerprint : Text
property document : Object
property loadError : Text

Class constructor()
	This.path:=""
	This.fingerprint:=""
	This.document:=New object
	This.loadError:=""
	This.load()

	//MARK:- reading

// load: read the config (on the server, via MCP_Config_Read) and parse it into
// This.document. False leaves loadError set.
Function load() : Boolean
	var $loaded_b : Boolean:=False
	var $read_o : Object:=MCP_Config_Read

	This.path:=String($read_o.path)
	This.fingerprint:=String($read_o.fingerprint)

	If (Bool($read_o.ok))
		var $raw_v : Variant
		$raw_v:=Try(JSON Parse(String($read_o.text)))

		If (Value type($raw_v)=Is object)
			This.document:=$raw_v
			This.loadError:=""
			$loaded_b:=True

		Else
			This.loadError:="Config is not valid JSON: "+This.path

		End if

	Else
		This.loadError:=String($read_o.error)

	End if

	return $loaded_b

// values: the editable settings as a flat key -> value object. The _doc block
// and any retired key are left out.
Function values() : Object
	var $values_o : Object:=New object
	var $dead_c : Collection:=This.deadKeys()
	var $key_t : Text

	For each ($key_t; This.document)
		If (Substring($key_t; 1; 1)#"_") && ($dead_c.indexOf($key_t)<0)
			$values_o[$key_t]:=This.document[$key_t].value
		End if
	End for each

	return $values_o

// comment: the documentation string 4D ships for a key, for tooltips.
Function comment($key_t : Text) : Text
	var $comment_t : Text:=""

	If (This.document[$key_t]#Null)
		$comment_t:=String(This.document[$key_t].comment)
	End if

	return $comment_t

// deadKeys: keys still present in older config copies but no longer read by
// the component — the table-backed token store was reverted (commit 6e3c383).
// They are hidden from the editor and dropped on the next save.
Function deadKeys() : Collection
	return New collection("TOKEN_STORE"; "TOKEN_TABLE")

// dataclasses: every dataclass in the host datastore, with its "Expose as REST
// resource" state, so the editor can offer a pick list instead of free text.
Function dataclasses() : Collection
	var $tables_c : Collection:=New collection
	var $name_t : Text

	For each ($name_t; OB Keys(ds))
		$tables_c.push(New object(\
			"name"; $name_t; \
			"exposed"; Bool(ds[$name_t].getInfo().exposed)))
	End for each

	return $tables_c.orderBy("name asc")

	//MARK:- editor model

// tableRows: one row per dataclass, carrying its 4D exposure and its
// membership of each list — so the editor can present ticks over a pick list
// rather than two free-text lists that can name tables which do not exist.
Function tableRows($values_o : Object) : Collection
	var $white_c : Collection:=This._nameList($values_o.WHITELIST_TABLES)
	var $black_c : Collection:=This._nameList($values_o.BLACKLIST_TABLES)
	var $rows_c : Collection:=New collection
	var $table_o : Object

	For each ($table_o; This.dataclasses())
		$rows_c.push(New object(\
			"name"; $table_o.name; \
			"exposed"; $table_o.exposed; \
			"inWhitelist"; ($white_c.indexOf($table_o.name)>=0); \
			"inBlacklist"; ($black_c.indexOf($table_o.name)>=0)))
	End for each

	// names in the config that no longer match a dataclass are still shown,
	// so a stale entry can be seen and unticked rather than silently kept
	var $name_v : Variant
	For each ($name_v; $white_c.combine($black_c))
		If ($rows_c.query("name = :1"; String($name_v)).length=0)
			$rows_c.push(New object(\
				"name"; String($name_v); \
				"exposed"; False; \
				"inWhitelist"; ($white_c.indexOf(String($name_v))>=0); \
				"inBlacklist"; ($black_c.indexOf(String($name_v))>=0)))
		End if
	End for each

	return $rows_c

// applyTableRows: fold the ticked rows back into the two config lists.
Function applyTableRows($values_o : Object; $rows_c : Collection)
	$values_o.WHITELIST_TABLES:=$rows_c.query("inWhitelist = :1"; True).extract("name")
	$values_o.BLACKLIST_TABLES:=$rows_c.query("inBlacklist = :1"; True).extract("name")

// actionRows: one row per METHOD_WHITELIST entry, for the action list.
Function actionRows($values_o : Object) : Collection
	var $rows_c : Collection:=New collection

	If (Value type($values_o.METHOD_WHITELIST)=Is object)
		var $action_t : Text

		For each ($action_t; $values_o.METHOD_WHITELIST)
			var $entry_v : Variant:=$values_o.METHOD_WHITELIST[$action_t]
			var $method_t : Text:=""

			If (Value type($entry_v)=Is object)
				$method_t:=String($entry_v.method)
			End if

			$rows_c.push(New object("name"; $action_t; "method"; $method_t))
		End for each
	End if

	return $rows_c.orderBy("name asc")

// _nameList: coerce a config table-list value to a collection of names,
// mirroring the component's own tolerance for a missing or empty setting.
Function _nameList($value_v : Variant) : Collection
	var $names_c : Collection:=New collection

	If (Value type($value_v)=Is collection)
		var $name_v : Variant

		For each ($name_v; $value_v)
			$names_c.push(String($name_v))
		End for each
	End if

	return $names_c

	//MARK:- validation

// validate: check a candidate value set. Returns a collection of
// {level; key; message} where level is "error" (blocks the save) or "warning".
Function validate($values_o : Object) : Collection
	var $issues_c : Collection:=New collection

	If ($values_o=Null)
		$issues_c.push(This._issue("error"; ""; "No values to save."))

	Else
		$issues_c:=$issues_c.combine(This._validateNumbers($values_o))
		$issues_c:=$issues_c.combine(This._validateTables($values_o))
		$issues_c:=$issues_c.combine(This._validateWhitelist($values_o))

		var $level_t : Text:=Lowercase(String($values_o.LOG_LEVEL))
		If (New collection("off"; "error"; "info"; "debug").indexOf($level_t)<0)
			$issues_c.push(This._issue("error"; "LOG_LEVEL"; \
				"Must be one of off, error, info or debug."))
		End if

		If (Not(Bool($values_o.ENABLED)))
			$issues_c.push(This._issue("warning"; "ENABLED"; \
				"Master switch is off — the endpoint will answer nothing."))
		End if
	End if

	return $issues_c

// _validateNumbers: ports, sizes and the page-size ceiling fixed by wire
// contract v1 (MAX_LIMIT may be lowered, never raised above 80).
Function _validateNumbers($values_o : Object) : Collection
	var $issues_c : Collection:=New collection

	var $port_i : Integer:=Num($values_o.HTTP_PORT)
	If ($port_i<0) || ($port_i>65535)
		$issues_c.push(This._issue("error"; "HTTP_PORT"; \
			"Must be between 0 and 65535 (0 = serve /mcp from the host's web server)."))
	End if

	If (Num($values_o.MAX_BODY_SIZE)<0)
		$issues_c.push(This._issue("error"; "MAX_BODY_SIZE"; "Cannot be negative (0 = unlimited)."))
	End if

	If (Num($values_o.RATE_LIMIT)<0)
		$issues_c.push(This._issue("error"; "RATE_LIMIT"; "Cannot be negative (0 = unlimited)."))
	End if

	var $max_i : Integer:=Num($values_o.MAX_LIMIT)
	If ($max_i<1) || ($max_i>80)
		$issues_c.push(This._issue("error"; "MAX_LIMIT"; \
			"Must be between 1 and 80 — wire contract v1 fixes the ceiling at 80."))
	End if

	var $default_i : Integer:=Num($values_o.DEFAULT_LIMIT)
	If ($default_i<1) || ($default_i>$max_i)
		$issues_c.push(This._issue("error"; "DEFAULT_LIMIT"; \
			"Must be between 1 and MAX_LIMIT ("+String($max_i)+")."))
	End if

	return $issues_c

// _validateTables: the exposure lists must name real dataclasses, and a
// non-empty whitelist silently overrides both the blacklist and the 4D schema.
Function _validateTables($values_o : Object) : Collection
	var $issues_c : Collection:=New collection
	var $known_c : Collection:=This.dataclasses().extract("name")

	var $listKey_t : Text
	For each ($listKey_t; New collection("WHITELIST_TABLES"; "BLACKLIST_TABLES"))

		If (Value type($values_o[$listKey_t])=Is collection)
			var $list_c : Collection:=$values_o[$listKey_t]
			var $name_v : Variant

			For each ($name_v; $list_c)
				If ($known_c.indexOf(String($name_v))<0)
					$issues_c.push(This._issue("warning"; $listKey_t; \
						"\""+String($name_v)+"\" is not a dataclass in this database."))
				End if
			End for each

		Else
			$issues_c.push(This._issue("error"; $listKey_t; "Must be a list of dataclass names."))

		End if
	End for each

	If (Value type($values_o.WHITELIST_TABLES)=Is collection)
		If ($values_o.WHITELIST_TABLES.length>0)
			$issues_c.push(This._issue("warning"; "WHITELIST_TABLES"; \
				"A non-empty whitelist overrides the blacklist and RESPECT_4D_SCHEMA."))
		End if
	End if

	return $issues_c

// _validateWhitelist: METHOD_WHITELIST hands clients a door into host code, so
// every entry is checked in full — args are ordered and positional, and an
// optional argument may not precede a required one.
Function _validateWhitelist($values_o : Object) : Collection
	var $issues_c : Collection:=New collection
	var $types_c : Collection:=New collection("text"; "number"; "boolean"; "object"; "collection")
	If (Value type($values_o.METHOD_WHITELIST)#Is object)
		$issues_c.push(This._issue("error"; "METHOD_WHITELIST"; "Must be an object keyed by action name."))

	Else
		var $whitelist_o : Object:=$values_o.METHOD_WHITELIST
		var $action_t : Text

		For each ($action_t; $whitelist_o)
			var $entry_v : Variant:=$whitelist_o[$action_t]

			If (Value type($entry_v)#Is object)
				$issues_c.push(This._issue("error"; "METHOD_WHITELIST"; \
					$action_t+": entry must be an object."))

			Else
				If (String($entry_v.method)="")
					$issues_c.push(This._issue("error"; "METHOD_WHITELIST"; \
						$action_t+": \"method\" (the host project method) is required."))
				End if

				$issues_c:=$issues_c.combine(This._validateArgs($action_t; $entry_v.args; $types_c))
			End if
		End for each

		If (OB Keys($whitelist_o).length>0) && (Not(Bool($values_o.ALLOW_CALL_METHOD)))
			$issues_c.push(This._issue("warning"; "METHOD_WHITELIST"; \
				"ALLOW_CALL_METHOD is off, so the whitelist is ignored entirely."))
		End if
	End if

	return $issues_c

// _validateArgs: the ordered positional parameter spec of one whitelist entry.
Function _validateArgs($action_t : Text; $args_v : Variant; $types_c : Collection) : Collection
	var $issues_c : Collection:=New collection

	If ($args_v=Null)
		// no args is a legitimate spec

	Else
		If (Value type($args_v)#Is collection)
			$issues_c.push(This._issue("error"; "METHOD_WHITELIST"; \
				$action_t+": \"args\" must be a list."))

		Else
			var $args_c : Collection:=$args_v
			var $seenOptional_b : Boolean:=False
			var $position_i : Integer:=0
			var $arg_v : Variant

			For each ($arg_v; $args_c)
				$position_i:=$position_i+1
				var $where_t : Text:=$action_t+" arg "+String($position_i)

				If (Value type($arg_v)#Is object)
					$issues_c.push(This._issue("error"; "METHOD_WHITELIST"; $where_t+": must be an object."))

				Else
					If (String($arg_v.name)="")
						$issues_c.push(This._issue("error"; "METHOD_WHITELIST"; $where_t+": \"name\" is required."))
					End if

					If ($types_c.indexOf(Lowercase(String($arg_v.type)))<0)
						$issues_c.push(This._issue("error"; "METHOD_WHITELIST"; \
							$where_t+": \"type\" must be one of "+$types_c.join(", ")+"."))
					End if

					If (Bool($arg_v.required))
						If ($seenOptional_b)
							$issues_c.push(This._issue("error"; "METHOD_WHITELIST"; \
								$where_t+": a required argument cannot follow an optional one."))
						End if

					Else
						$seenOptional_b:=True

					End if
				End if
			End for each
		End if
	End if

	return $issues_c

Function _issue($level_t : Text; $key_t : Text; $message_t : Text) : Object
	return New object("level"; $level_t; "key"; $key_t; "message"; $message_t)

	//MARK:- writing

// save: validate, then merge the values into the document and write it.
// Returns {success; issues; message}. Comments are never touched; retired keys
// are dropped; a document that would not parse back is not written.
Function save($values_o : Object) : Object
	var $issues_c : Collection:=This.validate($values_o)
	var $errors_c : Collection:=$issues_c.query("level = :1"; "error")
	var $status_o : Object:=New object("success"; False; "issues"; $issues_c; "message"; "")

	If ($errors_c.length>0)
		$status_o.message:=String($errors_c.length)+" problem(s) must be fixed before saving."

	Else
		var $key_t : Text
		For each ($key_t; $values_o)
			If (This.document[$key_t]=Null)
				This.document[$key_t]:=New object("comment"; ""; "value"; $values_o[$key_t])

			Else
				This.document[$key_t].value:=$values_o[$key_t]

			End if
		End for each

		var $document_o : Object:=This.document

		For each ($key_t; This.deadKeys())
			If ($document_o[$key_t]#Null)
				OB REMOVE($document_o; $key_t)
			End if
		End for each

		var $text_t : Text:=JSON Stringify(This.document; *)

		If (Value type(Try(JSON Parse($text_t)))=Is object)
			var $write_o : Object:=MCP_Config_Write($text_t; This.fingerprint)

			If (Bool($write_o.ok))
				This.fingerprint:=String($write_o.fingerprint)
				$status_o.success:=True
				$status_o.message:="Saved "+This.path

			Else
				$status_o.message:=String($write_o.error)

			End if

		Else
			$status_o.message:="Refused to write: the result would not parse as JSON."

		End if
	End if

	return $status_o

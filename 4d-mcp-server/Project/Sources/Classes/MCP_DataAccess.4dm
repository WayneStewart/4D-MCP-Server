// MCP_DataAccess — executes the ORDA operations behind each data action.
//
// Every public function returns a RESULT DESCRIPTOR object:
//   success -> { data: <obj|collection> }  (query_entities also adds { meta })
//   failure -> { error: { code, message } }  using the fixed taxonomy (4).
// Capability gating and param validation happen in MCP_Handler BEFORE these
// run; these functions own only gate 6 (execution + NOT_FOUND/QUERY_ERROR/
// INTERNAL).
//
// SECURITY: query_entities binds filter values positionally (:1, :2 ...) via
// ORDA placeholders. Values are NEVER string-interpolated into the query.

// limit default AND hard cap are both 80 (matches 4D internal paging).
// Shared singletons in this 4D build must stay stateless (assigning to a
// shared This property is rejected), so config is exposed via functions.

shared singleton Class constructor()
	
	// _HARD_CAP: query_entities limit default AND hard cap.
Function _HARD_CAP() : Integer
	return 80
	
	// =============================================================================
	//  query_entities  (3.2)
	// =============================================================================
Function query_entities($params : Object) : Object
	var $dc : 4D.DataClass
	$dc:=ds[String($params.dataclass)]
	If ($dc=Null)
		return This._err("QUERY_ERROR"; "Unknown dataclass: "+String($params.dataclass))
	End if 
	
	// offset
	var $offset : Integer
	$offset:=0
	If ($params.offset#Null)
		$offset:=Num($params.offset)
	End if 
	If ($offset<0)
		$offset:=0
	End if 
	
	// limit: default = hard cap; clamp anything larger.
	var $cap : Integer
	$cap:=This._HARD_CAP()
	var $limit : Integer
	var $clamped : Boolean
	$clamped:=False
	If ($params.limit=Null)
		$limit:=$cap
	Else 
		$limit:=Num($params.limit)
		If ($limit>$cap)
			$limit:=$cap
			$clamped:=True
		End if 
		If ($limit<0)
			$limit:=0
		End if 
	End if 
	
	// build selection (filter + placeholder binding + orderBy)
	var $sel : 4D.EntitySelection
	Try
		$sel:=This._query($dc; String($params.filter); $params.params)
		If ($params.orderBy#Null)
			If (Length(String($params.orderBy))>0)
				$sel:=$sel.orderBy(String($params.orderBy))
			End if 
		End if 
	Catch
		return This._err("QUERY_ERROR"; This._lastErrorText())
	End try
	
	var $total : Integer
	$total:=$sel.length
	
	var $projNames : Collection
	$projNames:=This._projectionNames(String($params.dataclass); $params.attributes)
	
	var $data : Collection
	$data:=New collection
	Try
		var $page : 4D.EntitySelection
		$page:=$sel.slice($offset; $offset+$limit)
		var $e : 4D.Entity
		For each ($e; $page)
			$data.push(This._entityObject($e; $projNames))
		End for each 
	Catch
		return This._err("QUERY_ERROR"; This._lastErrorText())
	End try
	
	var $count : Integer
	$count:=$data.length
	var $meta : Object
	$meta:=New object(\
		"count"; $count; \
		"offset"; $offset; \
		"limit"; $limit; \
		"total"; $total; \
		"truncated"; (($offset+$count)<$total); \
		"clamped"; $clamped)
	return New object("data"; $data; "meta"; $meta)
	
	// _query: bind filter values positionally to :1, :2 ... Injection-safe.
	// The explicit length branches guarantee correct positional binding regardless
	// of 4D version; >6 placeholders fall back to passing the collection (verify on
	// first run for that edge case only).
Function _query($dc : 4D.DataClass; $filter : Text; $qp : Variant) : 4D.EntitySelection
	If ($filter=Null)
		return $dc.all()
	End if 
	If (Length($filter)=0)
		return $dc.all()
	End if 
	var $c : Collection
	$c:=New collection
	If ($qp#Null)
		If (Value type($qp)=Is collection)
			$c:=$qp
		End if 
	End if 
	Case of 
		: ($c.length=0)
			return $dc.query($filter)
		: ($c.length=1)
			return $dc.query($filter; $c[0])
		: ($c.length=2)
			return $dc.query($filter; $c[0]; $c[1])
		: ($c.length=3)
			return $dc.query($filter; $c[0]; $c[1]; $c[2])
		: ($c.length=4)
			return $dc.query($filter; $c[0]; $c[1]; $c[2]; $c[3])
		: ($c.length=5)
			return $dc.query($filter; $c[0]; $c[1]; $c[2]; $c[3]; $c[4])
		: ($c.length=6)
			return $dc.query($filter; $c[0]; $c[1]; $c[2]; $c[3]; $c[4]; $c[5])
		Else 
			return $dc.query($filter; $c)
	End case 
	
	// =============================================================================
	//  get_entity  (3.3)
	// =============================================================================
Function get_entity($params : Object) : Object
	var $dc : 4D.DataClass
	$dc:=ds[String($params.dataclass)]
	If ($dc=Null)
		return This._err("QUERY_ERROR"; "Unknown dataclass: "+String($params.dataclass))
	End if 
	var $e : 4D.Entity
	Try
		$e:=$dc.get($params.key)
	Catch
		return This._err("QUERY_ERROR"; This._lastErrorText())
	End try
	If ($e=Null)
		return This._err("NOT_FOUND"; "No entity with key "+JSON Stringify($params.key))
	End if 
	var $projNames : Collection
	$projNames:=This._projectionNames(String($params.dataclass); $params.attributes)
	return New object("data"; This._entityObject($e; $projNames))
	
	// =============================================================================
	//  create_entity  (3.4)
	// =============================================================================
Function create_entity($params : Object) : Object
	var $dc : 4D.DataClass
	$dc:=ds[String($params.dataclass)]
	If ($dc=Null)
		return This._err("QUERY_ERROR"; "Unknown dataclass: "+String($params.dataclass))
	End if 
	var $e : 4D.Entity
	$e:=$dc.new()
	$e.fromObject($params.values)
	var $status : Object
	Try
		$status:=$e.save()
	Catch
		return This._err("INTERNAL"; This._lastErrorText())
	End try
	If (Not($status.success))
		return This._err("QUERY_ERROR"; This._statusText($status))
	End if 
	return New object("data"; New object("key"; $e.getKey(); "created"; True))
	
	// =============================================================================
	//  update_entity  (3.5)
	// =============================================================================
Function update_entity($params : Object) : Object
	var $dc : 4D.DataClass
	$dc:=ds[String($params.dataclass)]
	If ($dc=Null)
		return This._err("QUERY_ERROR"; "Unknown dataclass: "+String($params.dataclass))
	End if 
	var $e : 4D.Entity
	Try
		$e:=$dc.get($params.key)
	Catch
		return This._err("QUERY_ERROR"; This._lastErrorText())
	End try
	If ($e=Null)
		return This._err("NOT_FOUND"; "No entity with key "+JSON Stringify($params.key))
	End if 
	$e.fromObject($params.values)
	var $status : Object
	Try
		$status:=$e.save()
	Catch
		return This._err("INTERNAL"; This._lastErrorText())
	End try
	If (Not($status.success))
		return This._err("QUERY_ERROR"; This._statusText($status))
	End if 
	return New object("data"; New object("key"; $e.getKey(); "updated"; True))
	
	// =============================================================================
	//  delete_entity  (3.6)
	// =============================================================================
Function delete_entity($params : Object) : Object
	var $dc : 4D.DataClass
	$dc:=ds[String($params.dataclass)]
	If ($dc=Null)
		return This._err("QUERY_ERROR"; "Unknown dataclass: "+String($params.dataclass))
	End if 
	var $e : 4D.Entity
	Try
		$e:=$dc.get($params.key)
	Catch
		return This._err("QUERY_ERROR"; This._lastErrorText())
	End try
	If ($e=Null)
		return This._err("NOT_FOUND"; "No entity with key "+JSON Stringify($params.key))
	End if 
	var $key : Variant
	$key:=$e.getKey()
	var $status : Object
	Try
		$status:=$e.drop()
	Catch
		return This._err("INTERNAL"; This._lastErrorText())
	End try
	If (Not($status.success))
		return This._err("QUERY_ERROR"; This._statusText($status))
	End if 
	return New object("data"; New object("key"; $key; "deleted"; True))
	
	// =============================================================================
	//  call_method  (3.7)
	// =============================================================================
	// The action map lives in the deployment config (METHOD_WHITELIST): action
	// name -> {method, args:[{name,type,required,purpose}], return, purpose}.
	// `method` is a HOST project method invoked via EXECUTE METHOD with the
	// request's args bound POSITIONALLY (4D method params are positional; the
	// spec's arg names are documentation for the client). Anything not in the
	// map is unreachable. Arity/type validation happens in MCP_Handler gate 4;
	// this function owns only execution.
	//
	// No token is consulted here or anywhere upstream for call_method: the
	// whitelist plus ALLOW_CALL_METHOD is the whole permission model.
	// 4D imposes a third condition this code cannot inspect — the host method
	// must have "Shared with components and host" set, or EXECUTE METHOD never
	// finds it. That failure lands in the Catch below and returns INTERNAL, so
	// a whitelisted action that answers INTERNAL with nothing in the host log
	// is almost always an unshared method.
Function call_method($params : Object) : Object
	var $name : Text
	$name:=String($params.name)
	var $spec : Object
	$spec:=Null
	var $config : Object
	$config:=cs.MCP_Handler.me.getConfig()
	
	If ($config#Null)
		If (Value type($config.METHOD_WHITELIST)=Is object)
			$spec:=$config.METHOD_WHITELIST[$name]
		End if 
	End if 
	
	If ($spec=Null)
		return This._err("CAP_DENIED"; "Action not enabled in server config: "+$name)
	End if 
	
	var $method : Text
	$method:=String($spec.method)
	var $args : Collection
	$args:=New collection
	
	If (Value type($params.args)=Is collection)
		$args:=$params.args
	End if 
	var $result : Variant
	
	Try
		Case of 
			: ($args.length=0)
				EXECUTE METHOD($method; $result)
			: ($args.length=1)
				EXECUTE METHOD($method; $result; $args[0])
			: ($args.length=2)
				EXECUTE METHOD($method; $result; $args[0]; $args[1])
			: ($args.length=3)
				EXECUTE METHOD($method; $result; $args[0]; $args[1]; $args[2])
			: ($args.length=4)
				EXECUTE METHOD($method; $result; $args[0]; $args[1]; $args[2]; $args[3])
			: ($args.length=5)
				EXECUTE METHOD($method; $result; $args[0]; $args[1]; $args[2]; $args[3]; $args[4])
			: ($args.length=6)
				EXECUTE METHOD($method; $result; $args[0]; $args[1]; $args[2]; $args[3]; $args[4]; $args[5])
			Else 
				return This._err("BAD_PARAMS"; "Too many args (max 6)")
		End case 
	Catch
		return This._err("INTERNAL"; This._lastErrorText())
	End try
	return New object("data"; New object("name"; $name; "result"; $result))
	
	// --- Helpers ----------------------------------------------------------------
	
	// _projectionNames: the storage-attribute names to return for one row.
	// SCALAR-ONLY, always: relation attributes and dotted paths are never
	// projected (wire contract §6), whether or not RESPECT_4D_SCHEMA is on — this
	// is what stops attributes:["orders"] from dumping related entities. When
	// RESPECT_4D_SCHEMA is on, unexposed storage fields are additionally excluded.
	// An explicit `attributes` list is intersected with this rule (unknown names,
	// relations and unexposed fields silently dropped); an empty result means the
	// row has no returnable fields — the caller emits {} (never "all").
Function _projectionNames($dcName : Text; $attributes : Variant) : Collection
	var $respect : Boolean
	var $config : Object
	$config:=cs.MCP_Handler.me.getConfig()
	$respect:=($config#Null) && Bool($config.RESPECT_4D_SCHEMA)
	
	If (Value type($attributes)=Is collection)
		If ($attributes.length>0)
			var $kept : Collection
			$kept:=New collection
			var $req : Variant
			For each ($req; $attributes)
				var $reqAttr : Object
				$reqAttr:=ds[$dcName][String($req)]
				If ($reqAttr=Null)
					continue  // unknown name or dotted path
				End if 
				If ($reqAttr.kind#"storage")
					continue  // relation attribute — scalar-only
				End if 
				If ($respect) && (Not(Bool($reqAttr.exposed)))
					continue  // unexposed field
				End if 
				$kept.push($reqAttr.name)
			End for each 
			return $kept
		End if 
	End if 
	// default: all scalar (storage) attributes, exposure-filtered when respect.
	// Attribute objects via datastore double-bracket ds[$name][$key]; direct
	// bracket on a DataClass throws in this 4D build.
	var $names : Collection
	$names:=New collection
	var $key : Text
	For each ($key; OB Keys(ds[$dcName]))
		var $a : Object
		$a:=ds[$dcName][$key]
		If ($a#Null)
			If ($a.kind="storage")
				If ($respect) && (Not(Bool($a.exposed)))
					continue
				End if 
				$names.push($a.name)
			End if 
		End if 
	End for each 
	return $names
	
	// _entityObject: project an entity to the given storage-attribute names.
	// An empty name list yields {} — NEVER toObject(""), which ORDA treats as
	// "all attributes" and would leak the very fields the projection excluded.
Function _entityObject($e : 4D.Entity; $names : Collection) : Object
	If ($names=Null) || ($names.length=0)
		return New object
	End if 
	return $e.toObject($names.join(","))
	
Function _err($code : Text; $message : Text) : Object
	return New object("error"; New object("code"; $code; "message"; $message))
	
Function _statusText($status : Object) : Text
	If ($status.statusText#Null)
		If (Length(String($status.statusText))>0)
			return String($status.statusText)
		End if 
	End if 
	If ($status.errors#Null)
		If ($status.errors.length>0)
			var $msgs : Collection
			$msgs:=New collection
			var $er : Object
			For each ($er; $status.errors)
				$msgs.push(String($er.message))
			End for each 
			return $msgs.join("; ")
		End if 
	End if 
	return "Operation rejected by 4D"
	
Function _lastErrorText() : Text
	var $errs : Collection
	$errs:=Last errors
	If ($errs=Null)
		return "Unknown 4D error"
	End if 
	If ($errs.length=0)
		return "Unknown 4D error"
	End if 
	var $msgs : Collection
	$msgs:=New collection
	var $e : Object
	For each ($e; $errs)
		$msgs.push(String($e.message))
	End for each 
	return $msgs.join("; ")
	
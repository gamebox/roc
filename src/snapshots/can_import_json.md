# META
~~~ini
description=Import with module-qualified usage
type=file
~~~
# SOURCE
~~~roc
module []

import json.Json

main = Json.utf8
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
KwModule(1:1-1:7),OpenSquare(1:8-1:9),CloseSquare(1:9-1:10),Newline(1:1-1:1),
Newline(1:1-1:1),
KwImport(3:1-3:7),LowerIdent(3:8-3:12),NoSpaceDotUpperIdent(3:12-3:17),Newline(1:1-1:1),
Newline(1:1-1:1),
LowerIdent(5:1-5:5),OpAssign(5:6-5:7),UpperIdent(5:8-5:12),NoSpaceDotLowerIdent(5:12-5:17),EndOfFile(5:17-5:17),
~~~
# PARSE
~~~clojure
(file @1-1-5-17
	(module @1-1-1-10
		(exposes @1-8-1-10))
	(statements
		(s-import @3-1-3-17 (module ".Json") (qualifier "json"))
		(s-decl @5-1-5-17
			(p-ident @5-1-5-5 (raw "main"))
			(e-ident @5-8-5-17 (qaul "Json") (raw ".utf8")))))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(can-ir
	(d-let (id 76)
		(p-assign @5-1-5-5 (ident "main") (id 73))
		(e-lookup-external (id 75)
			(ext-decl @5-8-5-17 (qualified "json.Json.utf8") (module "json.Json") (local "utf8") (kind "value") (type-var 74))))
	(s-import @3-1-3-17 (module "json.Json") (qualifier "json") (id 72)
		(exposes)))
~~~
# TYPES
~~~clojure
(inferred-types
	(defs
		(d_assign (name "main") (def_var 76) (type "*")))
	(expressions
		(expr @5-8-5-17 (type "*"))))
~~~

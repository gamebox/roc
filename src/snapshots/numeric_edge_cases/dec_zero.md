# META
~~~ini
description=Zero as a decimal literal
type=expr
~~~
# SOURCE
~~~roc
0.0
~~~
# PROBLEMS
NIL
# TOKENS
~~~zig
Float(1:1-1:4),EndOfFile(1:4-1:4),
~~~
# PARSE
~~~clojure
(e-frac @1-1-1-4 (raw "0.0"))
~~~
# FORMATTED
~~~roc
NO CHANGE
~~~
# CANONICALIZE
~~~clojure
(e-dec-small @1-1-1-4 (numerator "0") (denominator-power-of-ten "1") (value "0.0") (id 72))
~~~
# TYPES
~~~clojure
(expr (id 72) (type "Frac(*)"))
~~~

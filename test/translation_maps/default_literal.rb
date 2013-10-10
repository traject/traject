foo = "bar"

some_hash = {
  "key1" => "value1",
  "array_key" => %w{one two three}
}
some_hash["__default__"] = "DEFAULT LITERAL"

# can be other ruby here, last line needs to evaluate as a Hash
some_hash

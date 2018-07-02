foo = "bar"

some_hash = {
  "key1" => "value1",
  "array_key" => %w{one two three},
  "key_to_be_overridden" => "value_from_ruby"
}
some_hash["also"] = "this"

# can be other ruby here, last line needs to evaluate as a Hash
some_hash

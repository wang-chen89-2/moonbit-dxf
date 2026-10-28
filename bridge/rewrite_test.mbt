///|
test "rewrite JSON boundary returns reviewable spans and rejects ambiguous values" {
  // Empty plans exercise the boundary without duplicating a native encoder.
  let empty = @bridge.apply_edits_hex("300a454f460a", "[]")
  assert_true(!empty.has_prefix("ERROR:"))
  for
    plan in [
      "{}", "[{\"index\":0,\"code\":160,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":\"1\",\"bits\":\"0\"}}]",
      "[{\"index\":0,\"code\":160,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":9007199254740993}}]",
      "[{\"index\":0,\"index\":0,\"code\":160,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":\"1\"}}]",
      "[{\"index\":0.5,\"code\":160,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":\"1\"}}]",
      "[{\"index\":1e-999,\"code\":160,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":\"1\"}}]",
      "[{\"index\":0,\"code\":160.000000000000000000001,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":\"1\"}}]",
    ] {
    assert_true(
      @bridge.apply_edits_hex(
        "3136300a393030373139393235343734303939330a300a454f460a", plan,
      ).has_prefix("ERROR:"),
    )
  }
}

///|
test "rewrite JSON Int64 strings remain exact above the JavaScript number range" {
  let answer = @bridge.apply_edits_hex(
    "3136300a393030373139393235343734303939330a300a454f460a", "[{\"index\":0e0,\"code\":160.0,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":\"9223372036854775807\"}}]",
  )
  guard @json.parse(answer) is Json::Object(object) else {
    fail("missing receipt")
  }
  guard object.get("output_hex") is Some(Json::String(output)) else {
    fail("missing output bytes")
  }
  assert_true(
    output.has_prefix("3136300a393232333337323033363835343737353830370a"),
  )
  guard object.get("changes") is Some(Json::Array(changes)) else {
    fail("missing changes")
  }
  assert_eq(changes.length(), 1)
}

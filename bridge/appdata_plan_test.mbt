///|
test "round16 explicit appdata request forms the existing typed edit plan" {
  let source = "300a4c494e450a350a41420a3130320a7b4150500a390a66697273740a390a7365636f6e640a3130320a7d0a380a6f7264696e6172790a300a454f460a"
  let request = "[{\"handle\":\"AB\",\"appdata\":\"APP\",\"code\":9,\"occurrence\":1,\"value\":{\"text\":\"reviewed\"}},{\"handle\":\"AB\",\"code\":8,\"value\":{\"text\":\"cut\"}}]"
  let plan = @bridge.make_plan_hex(source, request)
  guard @json.parse(plan) is Json::Array(edits) && edits.length() == 2 else {
    fail("missing formed application plan")
  }
  guard edits[0] is Json::Object(first) else { fail("missing first edit") }
  assert_eq(first.get("index"), Some(Json::number(4)))
  assert_eq(
    first.get("expected"),
    Some(Json::object(Map([("text_hex", Json::string("7365636f6e64"))]))),
  )
  assert_true(!@bridge.apply_edits_hex(source, plan).has_prefix("ERROR:"))
}

///|
test "round16 appdata request validates option type occurrence and duplicate targets" {
  let source = "300a4c494e450a350a41420a3130320a7b4150500a390a66697273740a390a7365636f6e640a3130320a7d0a380a6f7264696e6172790a300a454f460a"
  for
    request in [
      "[{\"handle\":\"AB\",\"appdata\":1,\"code\":9,\"value\":{\"text\":\"new\"}}]",
      "[{\"handle\":\"AB\",\"appdata\":\"MISSING\",\"code\":9,\"value\":{\"text\":\"new\"}}]",
      "[{\"handle\":\"AB\",\"appdata\":\"APP\",\"code\":9,\"occurrence\":0.5,\"value\":{\"text\":\"new\"}}]",
      "[{\"handle\":\"AB\",\"appdata\":\"APP\",\"code\":9,\"value\":{\"text\":\"new\"},\"unknown\":1}]",
      "[{\"handle\":\"AB\",\"appdata\":\"APP\",\"code\":9,\"value\":{\"text\":\"a\"}},{\"handle\":\"AB\",\"appdata\":\"APP\",\"code\":9,\"value\":{\"text\":\"b\"}}]",
    ] {
    assert_true(@bridge.make_plan_hex(source, request).has_prefix("ERROR:"))
  }
}

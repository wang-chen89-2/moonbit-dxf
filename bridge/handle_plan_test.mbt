///|
test "round09 make-plan emits exact expected values accepted by batch rewrite" {
  let source = "300a4c494e450a350a41420a380a610a31300a2d302e300a300a454f460a"
  let request = "[{\"handle\":\"ab\",\"code\":8,\"value\":{\"text\":\"cut\"}},{\"handle\":\"AB\",\"code\":10,\"value\":{\"bits\":\"0\"}}]"
  let plan = @bridge.make_plan_hex(source, request)
  guard @json.parse(plan) is Json::Array(rows) else {
    fail("missing formed plan")
  }
  guard rows[0] is Json::Object(first) &&
    first.get("expected") is Some(Json::Object(expected)) else {
    fail("missing expected")
  }
  assert_eq(expected.get("text_hex"), Some(Json::string("61")))
  guard rows[1] is Json::Object(second) &&
    second.get("expected") is Some(Json::Object(bits)) else {
    fail("missing bits")
  }
  assert_eq(bits.get("bits"), Some(Json::string("-9223372036854775808")))
  assert_true(!@bridge.apply_edits_hex(source, plan).has_prefix("ERROR:"))
}

///|
test "round09 make-plan rejects fractional requests duplicate targets and missing fields" {
  let source = "300a4c494e450a350a41420a380a610a300a454f460a"
  for
    request in [
      "{}", "[{\"handle\":\"AB\",\"code\":8,\"occurrence\":0.5,\"value\":{\"text\":\"cut\"}}]",
      "[{\"handle\":\"AB\",\"code\":8.00000000000000001,\"value\":{\"text\":\"cut\"}}]",
      "[{\"handle\":\"MISSING\",\"code\":8,\"value\":{\"text\":\"cut\"}}]", "[{\"handle\":\"AB\",\"code\":10,\"value\":{\"real\":\"1\"}}]",
      "[{\"handle\":\"AB\",\"code\":8,\"value\":{\"text\":\"a\"}},{\"handle\":\"ab\",\"code\":8,\"value\":{\"text\":\"b\"}}]",
    ] {
    assert_true(@bridge.make_plan_hex(source, request).has_prefix("ERROR:"))
  }
}

///|
fn unpacked_payload(raw : String) -> String raise {
  let decoded = @bridge.unwrap_source_plan(raw)
  guard @json.parse(decoded) is Json::Object(object) &&
    object.get("plan_json") is Some(Json::String(payload)) else {
    fail("missing decoded plan")
  }
  payload
}

///|
test "source plan legacy arrays retain their original numeric lexemes" {
  let raw = " [ {\"index\":1e-999,\"code\":160,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":\"1\"}} ] "
  assert_eq(unpacked_payload(raw), raw)
  assert_true(
    @bridge.apply_edits_hex(
      "3136300a393030373139393235343734303939330a300a454f460a",
      unpacked_payload(raw),
    ).has_prefix("ERROR:"),
  )
}

///|
test "source plan envelope keeps exact edit metadata and Int64 strings" {
  let hash = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  for index in ["0.5", "1e-999"] {
    let wrapped = "{\"format\":\"dxf-source-plan-v1\",\"source_sha256\":\"\{hash}\",\"edits\":[{\"index\":\{index},\"code\":160,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":\"1\"}}]}"
    assert_true(
      @bridge.apply_edits_hex(
        "3136300a393030373139393235343734303939330a300a454f460a",
        unpacked_payload(wrapped),
      ).has_prefix("ERROR:"),
    )
  }
  let valid = "{\"format\":\"dxf-source-plan-v1\",\"source_sha256\":\"\{hash}\",\"edits\":[{\"index\":0e0,\"code\":160.0,\"expected\":{\"integer\":\"9007199254740993\"},\"value\":{\"integer\":\"9223372036854775807\"}}]}"
  assert_true(
    !@bridge.apply_edits_hex(
      "3136300a393030373139393235343734303939330a300a454f460a",
      unpacked_payload(valid),
    ).has_prefix("ERROR:"),
  )
  guard @json.parse(@bridge.unwrap_source_plan(valid)) is Json::Object(metadata) else {
    fail("missing metadata")
  }
  assert_eq(
    metadata.get("source_sha256"),
    Some(
      Json::string(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
    ),
  )
}

///|
test "source plan malformed or ambiguous envelopes are rejected" {
  for
    raw in [
      "{}", "1", "{\"format\":\"dxf-source-plan-v2\",\"source_sha256\":\"00\",\"edits\":[]}",
      "{\"format\":\"dxf-source-plan-v1\",\"source_sha256\":\"00\",\"edits\":[]}",
      "{\"format\":\"dxf-source-plan-v1\",\"source_sha256\":\"gggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggggg\",\"edits\":[]}",
      "{\"format\":\"dxf-source-plan-v1\",\"format\":\"dxf-source-plan-v1\",\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"edits\":[]}",
      "{\"format\":\"dxf-source-plan-v1\",\"source_sha256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"edits\":{}}",
    ] {
    assert_true(@bridge.unwrap_source_plan(raw).has_prefix("ERROR:"))
  }
}

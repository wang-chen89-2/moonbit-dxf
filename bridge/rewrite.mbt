///|
fn plan_string(object : Map[String, Json], key : String) -> String raise {
  guard object.get(key) is Some(Json::String(value)) else {
    fail("\{key} must be a string")
  }
  value
}

///|
fn plan_value(json : Json) -> @dxf.TagValue raise {
  guard json is Json::Object(object) && object.length() == 1 else {
    fail("a value must contain exactly one typed string field")
  }
  if object.contains("text") {
    return @dxf.Text(@utf8.encode(plan_string(object, "text")))
  }
  if object.contains("text_hex") {
    return @dxf.Text(unhex(plan_string(object, "text_hex")))
  }
  if object.contains("integer") {
    return @dxf.Integer(
      @string.parse_int64(plan_string(object, "integer"), base=10),
    )
  }
  if object.contains("real") {
    return @dxf.RealBits(
      @string.parse_double(plan_string(object, "real")).reinterpret_as_int64(),
    )
  }
  if object.contains("bits") {
    return @dxf.RealBits(
      @string.parse_int64(plan_string(object, "bits"), base=10),
    )
  }
  if object.contains("binary_hex") {
    return @dxf.Binary(unhex(plan_string(object, "binary_hex")))
  }
  if object.contains("opaque_hex") {
    return @dxf.Opaque(unhex(plan_string(object, "opaque_hex")))
  }
  fail("unknown typed value field")
}

///|
fn required(object : Map[String, Json], key : String) -> Json raise {
  match object.get(key) {
    Some(value) => value
    None => fail("missing \{key}")
  }
}

///|
fn plan_int(object : Map[String, Json], key : String) -> Int32 raise {
  let value = required(object, key)
  guard value is Json::Number(_, ..) else {
    fail("\{key} must be an integer number")
  }
  // Retain the JSON number lexeme and reuse exact decimal Int32 parsing.
  // FromJson[Int] truncates fractions; Double also rounds near-integer values.
  let encoded = @utf8.encode("90\n" + value.stringify() + "\n0\nEOF\n")
  let doc = match
    @dxf.DxfDocument::from_bytes(encoded, mode=@dxf.ReadOnlyLint) {
    Ok(doc) => doc
    Err(error) => raise error
  }
  guard doc.is_complete() &&
    doc.tags().get(0) is Some(tag) &&
    tag.integer() is Some(integer) else {
    fail("\{key} must be an exact Int32")
  }
  integer.to_int()
}

///|
fn exact_plan_value(value : @dxf.TagValue) -> Json {
  let (key, text) = match value {
    @dxf.Text(bytes) => ("text_hex", hex(bytes))
    @dxf.Integer(integer) => ("integer", integer.to_string())
    @dxf.RealBits(bits) => ("bits", bits.to_string())
    @dxf.Binary(bytes) => ("binary_hex", hex(bytes))
    @dxf.Opaque(bytes) => ("opaque_hex", hex(bytes))
  }
  Json::object(Map([(key, Json::string(text))]))
}

///|
/// Form a validated index/old-value plan from record-handle field requests.
pub fn make_plan_hex(input : String, requests : String) -> String {
  try {
    let doc = match
      @dxf.DxfDocument::from_bytes(unhex(input), mode=@dxf.LosslessRoundTrip) {
      Ok(doc) => doc
      Err(error) => raise error
    }
    guard @json.parse(
        requests,
        reject_duplicate_keys=true,
        preserve_number_repr=true,
      )
      is Json::Array(rows) else {
      fail("requests must be an array")
    }
    let edits : Array[@dxf.ValueEdit] = []
    for row in rows {
      guard row is Json::Object(object) else {
        fail("request must be an object")
      }
      let has_occurrence = object.contains("occurrence")
      let has_appdata = object.contains("appdata")
      if object.length() !=
        3 +
        (if has_occurrence { 1 } else { 0 }) +
        (if has_appdata { 1 } else { 0 }) {
        fail(
          "each request requires handle, code, value and optional occurrence/appdata",
        )
      }
      let handle = plan_string(object, "handle")
      let code = plan_int(object, "code")
      let value = plan_value(required(object, "value"))
      let occurrence = if has_occurrence {
        plan_int(object, "occurrence")
      } else {
        0
      }
      let edit = if has_appdata {
        doc.value_edit_in_appdata(
          handle,
          plan_string(object, "appdata"),
          code,
          value,
          occurrence~,
        )
      } else {
        doc.value_edit_by_handle(handle, code, value, occurrence~)
      }
      edits.push(edit)
    }
    ignore(doc.rewrite_values(edits))
    Json::array(
      edits.map(edit => {
        Json::object(
          Map([
            ("index", Json::number(edit.index.to_double())),
            ("code", Json::number(edit.expected_code.to_double())),
            ("expected", exact_plan_value(edit.expected)),
            ("value", exact_plan_value(edit.value)),
          ]),
        )
      }),
    ).stringify()
  } catch {
    error => "ERROR:\{Repr(error)}"
  }
}

///|
/// Filesystem-independent JSON boundary. The host decides whether to write bytes.
pub fn apply_edits_hex(input : String, plan : String) -> String {
  try {
    let source = unhex(input)
    let doc = match
      @dxf.DxfDocument::from_bytes(source, mode=@dxf.LosslessRoundTrip) {
      Ok(doc) => doc
      Err(error) => raise error
    }
    guard @json.parse(
        plan,
        reject_duplicate_keys=true,
        preserve_number_repr=true,
      )
      is Json::Array(rows) else {
      fail("plan must be an array")
    }
    let edits : Array[@dxf.ValueEdit] = []
    for row in rows {
      guard row is Json::Object(object) && object.length() == 4 else {
        fail("each edit requires index, code, expected and value")
      }
      let index = plan_int(object, "index")
      let code = plan_int(object, "code")
      edits.push({
        index,
        expected_code: code,
        expected: plan_value(required(object, "expected")),
        value: plan_value(required(object, "value")),
      })
    }
    let result = doc.rewrite_values(edits)
    let changes = result.changes.map(change => {
      Json::object(
        Map([
          ("index", Json::number(change.index.to_double())),
          ("code", Json::number(change.code.to_double())),
          ("offset", Json::number(change.offset.to_double())),
          ("end_offset", Json::number(change.end_offset.to_double())),
          ("before_hex", Json::string(hex(change.before))),
          ("after_hex", Json::string(hex(change.after))),
        ]),
      )
    })
    Json::object(
      Map([
        ("output_hex", Json::string(hex(result.bytes))),
        ("source_bytes", Json::number(source.length().to_double())),
        ("output_bytes", Json::number(result.bytes.length().to_double())),
        ("changes", Json::array(changes)),
      ]),
    ).stringify()
  } catch {
    error => "ERROR:\{Repr(error)}"
  }
}

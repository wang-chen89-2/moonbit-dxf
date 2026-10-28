///|
/// Decode optional file-identity metadata without rounding edit numbers.
/// The filesystem host must verify source_sha256 before applying plan_json.
pub fn unwrap_source_plan(plan : String) -> String {
  try {
    let parsed = @json.parse(
      plan,
      reject_duplicate_keys=true,
      preserve_number_repr=true,
    )
    let (digest, payload) = match parsed {
      Json::Array(_) => (Json::null(), plan)
      Json::Object(object) => {
        if object.length() != 3 ||
          plan_string(object, "format") != "dxf-source-plan-v1" {
          fail("unsupported source-bound plan format")
        }
        let hash = plan_string(object, "source_sha256")
        if hash.length() != 64 {
          fail("source_sha256 must contain 64 hexadecimal digits")
        }
        ignore(unhex(hash))
        guard object.get("edits") is Some(Json::Array(edits)) else {
          fail("edits must be an array")
        }
        (Json::string(hash.to_lower()), Json::array(edits).stringify())
      }
      _ => fail("plan must be an edit array or source-bound envelope")
    }
    Json::object(
      Map([("source_sha256", digest), ("plan_json", Json::string(payload))]),
    ).stringify()
  } catch {
    error => "ERROR:\{Repr(error)}"
  }
}

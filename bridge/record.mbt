///|
/// File hosts add byte digests and destination protection to this native result.
pub fn export_record_hex(input : String, handle : String) -> String {
  try {
    let doc = match
      @dxf.DxfDocument::from_bytes(unhex(input), mode=@dxf.LosslessRoundTrip) {
      Ok(doc) => doc
      Err(error) => raise error
    }
    let record = doc.record_by_handle(handle)
    Json::object(
      Map([
        ("output_hex", Json::string(hex(record.bytes))),
        ("version", Json::string(doc.acad_version())),
        ("binary", Json::boolean(doc.is_binary())),
        ("offset", Json::number(record.offset.to_double())),
        (
          "end_offset",
          Json::number((record.offset + record.bytes.length()).to_double()),
        ),
      ]),
    ).stringify()
  } catch {
    error => "ERROR:\{Repr(error)}"
  }
}

///|
/// Read-only physical inventory; hosts bind it to the source byte digest.
pub fn record_spans_hex(input : String) -> String {
  try {
    let doc = match
      @dxf.DxfDocument::from_bytes(unhex(input), mode=@dxf.LosslessRoundTrip) {
      Ok(doc) => doc
      Err(error) => raise error
    }
    let records = doc
      .record_spans()
      .map(span => {
        Json::object(
          Map([
            ("ordinal", Json::number(span.ordinal.to_double())),
            ("start_tag", Json::number(span.start_tag.to_double())),
            ("end_tag", Json::number(span.end_tag.to_double())),
            ("kind_hex", Json::string(hex(span.kind))),
            (
              "handle_hex",
              match span.handle {
                Some(raw) => Json::string(hex(raw))
                None => Json::null()
              },
            ),
            ("offset", Json::number(span.offset.to_double())),
            ("end_offset", Json::number(span.end_offset.to_double())),
          ]),
        )
      })
    Json::object(
      Map([
        ("version", Json::string(doc.acad_version())),
        ("binary", Json::boolean(doc.is_binary())),
        (
          "source_bytes",
          Json::number(doc.original_bytes().length().to_double()),
        ),
        ("record_count", Json::number(records.length().to_double())),
        ("records", Json::array(records)),
      ]),
    ).stringify()
  } catch {
    error => "ERROR:\{Repr(error)}"
  }
}

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

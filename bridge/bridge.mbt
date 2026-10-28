///|
fn unhex(s : String) -> Bytes raise {
  if s.length() % 2 != 0 {
    fail("odd hex")
  }
  let a : Array[Byte] = []
  for i in 0..<(s.length() / 2) {
    let mut v = 0
    for j in 0..<2 {
      let c = s[i * 2 + j].to_int()
      let d = if c >= 48 && c <= 57 {
        c - 48
      } else if c >= 97 && c <= 102 {
        c - 87
      } else if c >= 65 && c <= 70 {
        c - 55
      } else {
        fail("invalid hex")
      }
      v = v * 16 + d
    }
    a.push(v.to_byte())
  }
  Bytes::from_array(a)
}

///|
fn hex(b : Bytes) -> String {
  let a : Array[Byte] = []
  let digits : Bytes = b"0123456789abcdef"
  for c in b {
    a.push(digits[c.to_int() >> 4])
    a.push(digits[c.to_int() & 15])
  }
  @utf8.decode_lossy(Bytes::from_array(a))
}

///|
pub fn process_hex(input : String, action : String) -> String {
  try {
    let bytes = unhex(input)
    let mode : @dxf.OperationMode = if action == "repair" ||
      action == "repair_report" {
      PermissiveRepair
    } else if action == "lint" {
      ReadOnlyLint
    } else {
      LosslessRoundTrip
    }
    let decoder = @dxf.DxfDecoder::new(mode~)
    let mut p = 0
    while p < bytes.length() {
      let end = (p + 31).min(bytes.length())
      ignore(decoder.feed(bytes[p:end].to_owned()))
      p = end
    }
    let doc = decoder.finish()
    if action == "binary" {
      return hex(doc.to_binary())
    }
    if action == "ascii" {
      return hex(doc.to_ascii_bytes())
    }
    if action == "save" {
      return hex(doc.save())
    }
    if action == "repair" {
      return hex(doc.repair().bytes)
    }
    if action == "repair_report" {
      let r = doc.repair()
      return Json::object(
        Map([
          ("output_hex", Json::string(hex(r.bytes))),
          ("discarded_bytes", Json::number(r.discarded_bytes.to_double())),
          (
            "diagnostics",
            Json::array(r.diagnostics.map(d => Json::string(d.code))),
          ),
        ]),
      ).stringify()
    }
    if action == "adapters" {
      let dxfkit = @adapters.DxfkitSink::new()
      doc.pump_geometry(dxfkit)
      let geometry = @adapters.GeometrySink::new()
      doc.pump_geometry(geometry)
      let first = dxfkit.drawing()
      let second = geometry.drawing()
      return "{\"dxfkit_entities\":\{first.entities().entities.length()},\"geometry_entities\":\{second.entity_count()}}"
    }
    let tags = doc
      .tags()
      .map(t => {
        let value : Json = match t.value {
          Text(b) => Json::string(@utf8.decode_lossy(b))
          Integer(v) => Json::string(v.to_string())
          RealBits(bits) => Json::string(bits.to_string())
          Binary(b) => Json::string(hex(b))
          Opaque(b) => Json::string(hex(b))
        }
        let kind = match t.value {
          Text(_) => "text"
          Integer(_) => "int"
          RealBits(_) => "bits"
          Binary(_) => "bytes"
          Opaque(_) => "opaque"
        }
        Json::array([
          Json::number(t.code.to_double()),
          Json::string(kind),
          value,
        ])
      })
    let issues = doc.lint().map(d => Json::string(d.code))
    let details = doc
      .lint()
      .map(d => {
        Json::object(
          Map([
            ("code", Json::string(d.code)),
            ("offset", Json::number(d.offset.to_double())),
            (
              "severity",
              Json::string(
                if d.severity == @dxf.Error {
                  "error"
                } else {
                  "warning"
                },
              ),
            ),
            ("message", Json::string(d.message)),
          ]),
        )
      })
    Json::object(
      Map([
        ("version", Json::string(doc.acad_version())),
        ("complete", Json::boolean(doc.is_complete())),
        ("tags", Json::array(tags)),
        ("diagnostics", Json::array(issues)),
        ("details", Json::array(details)),
      ]),
    ).stringify()
  } catch {
    e => "ERROR:\{Repr(e)}"
  }
}

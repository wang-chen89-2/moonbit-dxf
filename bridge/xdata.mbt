///|
/// Read original typed APPID payload through the same native scope resolver.
pub fn read_xdata_hex(
  input : String,
  handle : String,
  application : String,
) -> String {
  try {
    let doc = match
      @dxf.DxfDocument::from_bytes(unhex(input), mode=@dxf.ReadOnlyLint) {
      Ok(doc) => doc
      Err(error) => raise error
    }
    Json::array(
      doc
      .xdata_by_appid(handle, application)
      .map(tag => {
        Json::object(
          Map([
            ("code", Json::number(tag.code.to_double())),
            ("value", exact_plan_value(tag.value)),
          ]),
        )
      }),
    ).stringify()
  } catch {
    error => "ERROR:\{Repr(error)}"
  }
}

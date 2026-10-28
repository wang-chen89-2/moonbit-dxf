///|
/// Consumer-owned sink for ASCII tag chunks, not an upstream geometry API.
/// Encoding may allocate; callbacks are synchronous and may apply backpressure.
pub(open) trait DxfGeometrySink {
  fn write_ascii(Self, Bytes) -> Unit
}

///|
pub fn[S : DxfGeometrySink] DxfDocument::pump_geometry(
  self : DxfDocument,
  sink : S,
) -> Unit raise DxfError {
  self.require_convertible()
  for t in self.items {
    sink.write_ascii(write_tag(t, false, 2))
  }
}

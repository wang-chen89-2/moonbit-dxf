///|
test "deep supported geometry survives ignored legacy metadata and unsupported text" {
  let ascii = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1015\n9\n$DWGCODEPAGE\n3\nANSI_1252\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nTEXT\n1\ncaf\xe9\n0\nLINE\n8\ncaf\xe9\n10\n1.0\n20\n2.0\n11\n3.0\n21\n4.0\n0\nENDSEC\n0\nEOF\n"
  let source = @dxf.DxfDocument::from_bytes(ascii, mode=@dxf.LosslessRoundTrip).unwrap()
  let doc = @dxf.DxfDocument::from_bytes(
    source.to_binary(),
    mode=@dxf.LosslessRoundTrip,
  ).unwrap()
  let sink = @adapters.GeometrySink::new()
  doc.pump_geometry(sink)
  let geometry = sink.drawing()
  assert_eq(geometry.entity_count(), 1)
  match geometry.entities[0] {
    @dxf_io.DxfLine(start, end) => {
      assert_eq(start.x, 1.0)
      assert_eq(start.y, 2.0)
      assert_eq(end.x, 3.0)
      assert_eq(end.y, 4.0)
    }
    _ => fail("legacy metadata prevented supported LINE extraction")
  }
}

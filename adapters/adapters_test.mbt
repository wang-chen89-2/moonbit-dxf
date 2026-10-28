///|
test "native Binary decoded into two real upstream drawing types" {
  let ascii = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1.0\n20\n2.0\n11\n3.0\n21\n4.0\n0\nCIRCLE\n10\n5.0\n20\n6.0\n40\n2.5\n0\nENDSEC\n0\nEOF\n"
  let initial = @dxf.DxfDocument::from_bytes(ascii, mode=@dxf.LosslessRoundTrip).unwrap()
  let doc = @dxf.DxfDocument::from_bytes(
    initial.to_binary(),
    mode=@dxf.LosslessRoundTrip,
  ).unwrap()
  let a = @adapters.DxfkitSink::new()
  let b = @adapters.GeometrySink::new()
  doc.pump_geometry(a)
  doc.pump_geometry(b)
  assert_eq(a.drawing().entities().entities.length(), 2)
  assert_eq(b.drawing().entity_count(), 2)
  match a.drawing().entities().entities[0].geom {
    @dxfkit.Line(start~, end~) => {
      assert_eq(start.x, 1.0)
      assert_eq(start.y, 2.0)
      assert_eq(end.x, 3.0)
      assert_eq(end.y, 4.0)
    }
    _ => fail("dxfkit did not receive LINE coordinates")
  }
  match b.drawing().entities[1] {
    @dxf_io.DxfCircle(center, radius) => {
      assert_eq(center.x(), 5.0)
      assert_eq(center.y(), 6.0)
      assert_eq(radius, 2.5)
    }
    _ => fail("moon-geometry did not receive CIRCLE")
  }
}

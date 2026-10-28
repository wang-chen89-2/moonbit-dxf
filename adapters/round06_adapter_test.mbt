///|
test "round06 upstream geometry does not retain the previous LINE optional Z values" {
  let source = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1.0\n20\n2.0\n30\n7.0\n11\n3.0\n21\n4.0\n31\n8.0\n0\nLINE\n10\n5.0\n20\n6.0\n11\n7.0\n21\n8.0\n0\nENDSEC\n0\nEOF\n"
  let doc = @dxf.DxfDocument::from_bytes(source, mode=@dxf.LosslessRoundTrip).unwrap()
  let sink = @adapters.GeometrySink::new()
  doc.pump_geometry(sink)
  let drawing = sink.drawing()
  assert_eq(drawing.entity_count(), 2)
  match drawing.entities[1] {
    @dxf_io.DxfLine(start, end) => {
      assert_eq(start.x, 5.0)
      assert_eq(start.y, 6.0)
      assert_eq(start.z, 0.0)
      assert_eq(end.z, 0.0)
    }
    _ => fail("missing second LINE")
  }
}

///|
test "round06 geometry snapshots remain stable across mixed records and later pumping" {
  let first = @dxf.DxfDocument::from_bytes(
    b"0\nSECTION\n999\nsection comment\n2\nENTITIES\n0\nLINE\n10\n1.0\n20\n2.0\n11\n3.0\n21\n4.0\n0\nCIRCLE\n10\n10.0\n20\n20.0\n40\n3.0\n0\nLWPOLYLINE\n90\n2\n10\n5.0\n20\n6.0\n10\n7.0\n20\n8.0\n0\nENDSEC\n0\nEOF\n",
    mode=@dxf.LosslessRoundTrip,
  ).unwrap()
  let sink = @adapters.GeometrySink::new()
  first.pump_geometry(sink)
  let snapshot = sink.drawing()
  assert_eq(snapshot.entity_count(), 3)
  match snapshot.entities[1] {
    @dxf_io.DxfCircle(center, radius) => {
      assert_eq(center.x, 10.0)
      assert_eq(center.y, 20.0)
      assert_eq(radius, 3.0)
    }
    _ => fail("CIRCLE lost after record isolation")
  }
  match snapshot.entities[2] {
    @dxf_io.DxfPolyline(points) => {
      assert_eq(points.length(), 2)
      assert_eq(points[0].x, 5.0)
      assert_eq(points[1].y, 8.0)
    }
    _ => fail("LWPOLYLINE lost after record isolation")
  }
  assert_eq(sink.drawing().entity_count(), 3)
  let later = @dxf.DxfDocument::from_bytes(
    b"0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n0.0\n20\n0.0\n11\n1.0\n21\n1.0\n0\nENDSEC\n0\nEOF\n",
    mode=@dxf.LosslessRoundTrip,
  ).unwrap()
  later.pump_geometry(sink)
  assert_eq(sink.drawing().entity_count(), 4)
  assert_eq(sink.drawing().entity_count(), 4)
  assert_eq(snapshot.entity_count(), 3)
}

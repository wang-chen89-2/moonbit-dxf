///|
test "round07 scientific coordinates reach real LINE CIRCLE and point-list consumers" {
  let bytes = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1e-9\n20\n-2.5e20\n30\n3e-30\n11\n-4e15\n21\n5e-25\n31\n6e30\n0\nCIRCLE\n10\n7e-9\n20\n-8e25\n40\n9e-15\n0\nLWPOLYLINE\n90\n2\n10\n1e-9\n20\n2e-8\n10\n3e20\n20\n4e21\n0\nENDSEC\n0\nEOF\n"
  let source = @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip).unwrap()
  for bytes in [bytes, source.to_binary()] {
    let doc = @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip).unwrap()
    let sink = @adapters.GeometrySink::new()
    doc.pump_geometry(sink)
    let drawing = sink.drawing()
    assert_eq(drawing.entity_count(), 3)
    match drawing.entities[0] {
      @dxf_io.DxfLine(start, end) => {
        assert_eq(start.x, 1.0e-9)
        assert_eq(start.y, -2.5e20)
        assert_eq(start.z, 3.0e-30)
        assert_eq(end.x, -4.0e15)
        assert_eq(end.y, 5.0e-25)
        assert_eq(end.z, 6.0e30)
      }
      _ => fail("LINE missing")
    }
    match drawing.entities[1] {
      @dxf_io.DxfCircle(center, radius) => {
        assert_eq(center.x, 7.0e-9)
        assert_eq(center.y, -8.0e25)
        assert_eq(radius, 9.0e-15)
      }
      _ => fail("CIRCLE missing")
    }
    match drawing.entities[2] {
      @dxf_io.DxfPolyline(points) => {
        assert_eq(points.length(), 2)
        assert_eq(points[0].x, 1.0e-9)
        assert_eq(points[0].y, 2.0e-8)
        assert_eq(points[1].x, 3.0e20)
        assert_eq(points[1].y, 4.0e21)
      }
      _ => fail("point list missing")
    }
  }
}

///|
test "round07 real consumer retains finite exponent extremes and signed zero bits" {
  for
    number in [
      5.0e-324, -1.0e-300, 2.2250738585072014e-308, 1.7976931348623157e308, -0.0,
      0.125,
    ] {
    let text = if number.reinterpret_as_int64() == -9223372036854775808L {
      "-0.0"
    } else {
      "\{number}"
    }
    let bytes = @utf8.encode(
      "0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n\{text}\n20\n0\n11\n1\n21\n2\n0\nENDSEC\n0\nEOF\n",
    )
    let doc = @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip).unwrap()
    let sink = @adapters.GeometrySink::new()
    doc.pump_geometry(sink)
    match sink.drawing().entities[0] {
      @dxf_io.DxfLine(start, _) =>
        assert_eq(start.x.reinterpret_as_int64(), number.reinterpret_as_int64())
      _ => fail("LINE missing")
    }
  }
}

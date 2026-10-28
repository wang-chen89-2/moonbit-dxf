///|
fn main raise {
  let ascii = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nPOLYLINE\n70\n0\n10\n0\n20\n0\n30\n0\n0\nVERTEX\n10\n1.25\n20\n-2.5\n0\nVERTEX\n10\n4.5\n20\n8.75\n0\nVERTEX\n10\n9\n20\n3\n0\nSEQEND\n0\nENDSEC\n0\nEOF\n"
  let original = @dxf.DxfDocument::from_bytes(
    ascii,
    mode=@dxf.LosslessRoundTrip,
  ).unwrap()
  let binary = original.to_binary()
  let doc = @dxf.DxfDocument::from_bytes(binary, mode=@dxf.ReadOnlyLint).unwrap()
  let sink = @adapters.GeometrySink::new()
  doc.pump_geometry(sink)
  let drawing = sink.drawing()
  assert_eq(drawing.entity_count(), 1)
  match drawing.entities[0] {
    @dxf_io.DxfPolyline(points) => {
      println("vertices=\{points.length()}")
      for i, point in points {
        println("\{i}: \{point.x}, \{point.y}")
      }
    }
    _ => fail("expected an open 2D point list")
  }
  assert_eq(doc.save(), binary)
}

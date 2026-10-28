// Entity record generated independently with ezdxf 1.4.3; original model CC0-1.0.

///|
test "round13 APPDATA cannot add vertices to the real geometry consumer" {
  let ascii = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n  0\nLWPOLYLINE\n  5\n2F\n102\n{PRIVATE_GEOM\n 10\n1000.0\n 20\n2000.0\n 30\n3000.0\n102\n}\n330\n17\n100\nAcDbEntity\n  8\n0\n100\nAcDbPolyline\n 90\n2\n 70\n0\n 10\n1.25\n 20\n-2.5\n 10\n9.0\n 20\n12.0\n0\nENDSEC\n0\nEOF\n"
  let initial = @dxf.DxfDocument::from_bytes(ascii, mode=@dxf.LosslessRoundTrip).unwrap()
  for bytes in [ascii, initial.to_binary()] {
    let doc = @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip).unwrap()
    let sink = @adapters.GeometrySink::new()
    doc.pump_geometry(sink)
    let drawing = sink.drawing()
    assert_eq(drawing.entity_count(), 1)
    match drawing.entities[0] {
      @dxf_io.DxfPolyline(points) => {
        assert_eq(points.length(), 2)
        assert_eq(points[0].x, 1.25)
        assert_eq(points[0].y, -2.5)
        assert_eq(points[1].x, 9.0)
        assert_eq(points[1].y, 12.0)
      }
      _ => fail("LWPOLYLINE missing")
    }
    assert_eq(doc.save(), bytes)
    let full = @adapters.DxfkitSink::new()
    doc.pump_geometry(full)
    let sections = full.drawing().sections.filter(s => s.name == "ENTITIES")
    assert_eq(sections.length(), 1)
    assert_true(sections[0].records[0].common.any(t => t.code == 102))
    assert_true(sections[0].records[0].common.any(t => t.code == 10))
  }
}

///|
test "round13 nested and named APPDATA cannot replace LINE or CIRCLE scalars" {
  let ascii = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1\n20\n2\n30\n3\n11\n4\n21\n5\n31\n6\n102\n{OUTER\n10\n1000\n20\n2000\n102\n{INNER\n30\n3000\n11\n4000\n21\n5000\n31\n6000\n102\nINNER}\n102\nOUTER}\n0\nCIRCLE\n10\n7\n20\n8\n40\n9\n102\n{PRIVATE\n10\n7000\n20\n8000\n40\n9000\n102\n}\n0\nENDSEC\n0\nEOF\n"
  let initial = @dxf.DxfDocument::from_bytes(ascii, mode=@dxf.LosslessRoundTrip).unwrap()
  for bytes in [ascii, initial.to_binary()] {
    let doc = @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip).unwrap()
    let sink = @adapters.GeometrySink::new()
    doc.pump_geometry(sink)
    let drawing = sink.drawing()
    assert_eq(drawing.entity_count(), 2)
    match drawing.entities[0] {
      @dxf_io.DxfLine(start, end) => {
        assert_eq(start.x, 1.0)
        assert_eq(start.y, 2.0)
        assert_eq(start.z, 3.0)
        assert_eq(end.x, 4.0)
        assert_eq(end.y, 5.0)
        assert_eq(end.z, 6.0)
      }
      _ => fail("LINE missing")
    }
    match drawing.entities[1] {
      @dxf_io.DxfCircle(center, radius) => {
        assert_eq(center.x, 7.0)
        assert_eq(center.y, 8.0)
        assert_eq(radius, 9.0)
      }
      _ => fail("CIRCLE missing")
    }
    assert_eq(doc.save(), bytes)
  }
}

///|
test "round13 an unclosed application scope does not consume the next record" {
  let ascii = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1\n20\n2\n11\n3\n21\n4\n102\n{UNFINISHED\n10\n1000\n20\n2000\n0\nCIRCLE\n10\n5\n20\n6\n40\n7\n0\nENDSEC\n0\nEOF\n"
  let initial = @dxf.DxfDocument::from_bytes(ascii, mode=@dxf.LosslessRoundTrip).unwrap()
  for bytes in [ascii, initial.to_binary()] {
    let doc = @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip).unwrap()
    let sink = @adapters.GeometrySink::new()
    doc.pump_geometry(sink)
    let drawing = sink.drawing()
    assert_eq(drawing.entity_count(), 2)
    match drawing.entities[0] {
      @dxf_io.DxfLine(start, _) => {
        assert_eq(start.x, 1.0)
        assert_eq(start.y, 2.0)
      }
      _ => fail("LINE missing")
    }
    match drawing.entities[1] {
      @dxf_io.DxfCircle(center, radius) => {
        assert_eq(center.x, 5.0)
        assert_eq(center.y, 6.0)
        assert_eq(radius, 7.0)
      }
      _ => fail("record boundary failed to reset APPDATA scope")
    }
    assert_eq(sink.drawing().entity_count(), 2)
    assert_eq(doc.save(), bytes)
  }
}

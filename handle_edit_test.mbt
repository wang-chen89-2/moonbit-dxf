///|
test "round09 handle planning captures legacy bytes and ignores application fields" {
  let source = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1015\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLINE\n102\n{BATCH\n5\nAA\n8\npayload\n102\n}\n5\nAB\n100\nAcDbEntity\n8\ncaf\xe9\n100\nAcDbLine\n10\n1.0\n20\n2.0\n11\n3.0\n21\n4.0\n0\nENDSEC\n0\nEOF\n"
  for encoded in [source, round09_doc(source).to_binary()] {
    let doc = round09_doc(encoded)
    let edit = doc.value_edit_by_handle("000ab", 8, @dxf.Text(b"cut"))
    assert_eq(edit.expected, @dxf.Text(b"caf\xe9"))
    let rewritten = round09_doc(doc.rewrite_values([edit]).bytes)
    assert_eq(rewritten.tags()[edit.index].text(), Some("cut"))
    assert_true(
      rewritten.tags().any(t => t.code == 8 && t.text() == Some("payload")),
    )
    try doc.value_edit_by_handle("AA", 8, @dxf.Text(b"wrong")) catch {
      @dxf.Invalid(..) => ()
      _ => fail("wrong fake-handle error")
    } noraise {
      _ => fail("application payload became a record handle")
    }
    assert_eq(doc.original_bytes(), encoded)
  }
  let r12 = round09_doc(
    b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLINE\n5\nAB\n8\nold\n0\nENDSEC\n0\nEOF\n",
  )
  let binary = round09_doc(r12.to_binary())
  let edit = binary.value_edit_by_handle("ab", 8, @dxf.Text(b"cut"))
  assert_eq(
    round09_doc(binary.rewrite_values([edit]).bytes).tags()[edit.index].text(),
    Some("cut"),
  )
}

///|
test "round09 handle occurrence selects repeated ordinary fields after APPDATA" {
  let doc = round09_doc(
    b"0\nLWPOLYLINE\n5\nAC\n102\n{APP\n10\n99.0\n20\n88.0\n102\n}\n100\nAcDbEntity\n8\nold\n100\nAcDbPolyline\n90\n2\n10\n1.0\n20\n2.0\n10\n5.0\n20\n6.0\n0\nEOF\n",
  )
  let edit = doc.value_edit_by_handle(
    "ac",
    10,
    @dxf.RealBits(9.0.reinterpret_as_int64()),
    occurrence=1,
  )
  assert_eq(edit.expected, @dxf.RealBits(5.0.reinterpret_as_int64()))
  let result = round09_doc(doc.rewrite_values([edit]).bytes)
  assert_eq(result.tags()[edit.index].real(), Some(9.0))
  assert_eq(result.tags()[3].real(), Some(99.0))
  for occurrence in [-1, 2] {
    try
      doc.value_edit_by_handle("AC", 10, @dxf.RealBits(0L), occurrence~)
    catch {
      @dxf.Invalid(..) => ()
      _ => fail("wrong occurrence error")
    } noraise {
      _ => fail("invalid occurrence selected a field")
    }
  }
}

///|
test "round09 lookup respects DIMSTYLE 105 and rejects missing ambiguous handles" {
  let doc = round09_doc(
    b"0\nSECTION\n2\nHEADER\n9\n$HANDSEED\n5\nAA\n0\nENDSEC\n0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nDIMSTYLE\n0\nDIMSTYLE\n105\nAB\n100\nAcDbSymbolTableRecord\n100\nAcDbDimStyleTableRecord\n2\nSTYLE\n5\nAA\n0\nENDTAB\n0\nENDSEC\n0\nEOF\n",
  )
  let edit = doc.value_edit_by_handle("ab", 5, @dxf.Text(b"BB"))
  assert_eq(edit.expected, @dxf.Text(b"AA"))
  for handle in ["AA", "", "0xAB", "FFFFFFFFFFFFFFFFF"] {
    try doc.value_edit_by_handle(handle, 5, @dxf.Text(b"BB")) catch {
      @dxf.Invalid(..) => ()
      _ => fail("wrong handle rejection")
    } noraise {
      _ => fail("non-owning handle selected a record")
    }
  }
  let duplicate = round09_doc(
    b"0\nLINE\n5\nAB\n8\na\n0\nLINE\n5\n000ab\n8\nb\n0\nEOF\n",
  )
  try duplicate.value_edit_by_handle("AB", 8, @dxf.Text(b"cut")) catch {
    @dxf.Invalid(..) => ()
    _ => fail("wrong ambiguity rejection")
  } noraise {
    _ => fail("duplicate record handles were guessed")
  }
}

///|
test "round09 captured handle plans retain existing stale-value and structural guards" {
  let doc = round09_doc(b"0\nLINE\n5\nAB\n8\nold\n0\nEOF\n")
  let edit = doc.value_edit_by_handle("AB", 8, @dxf.Text(b"cut"))
  let changed = round09_doc(doc.rewrite_values([edit]).bytes)
  try changed.rewrite_values([edit]) catch {
    @dxf.Invalid(..) => ()
    _ => fail("wrong stale-plan error")
  } noraise {
    _ => fail("captured old value was not checked")
  }
  let structural = doc.value_edit_by_handle("AB", 0, @dxf.Text(b"CIRCLE"))
  try doc.rewrite_values([structural]) catch {
    @dxf.Unrepresentable(_) => ()
    _ => fail("wrong structural rejection")
  } noraise {
    _ => fail("handle planning bypassed the rewrite guard")
  }
}

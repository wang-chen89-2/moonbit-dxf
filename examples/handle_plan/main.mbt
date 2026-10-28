///|
fn main raise {
  let source = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n5\nAB\n102\n{APP\n8\nmetadata\n102\n}\n8\nold\n10\n1.0\n20\n2.0\n11\n3.0\n21\n4.0\n0\nLWPOLYLINE\n5\nAC\n90\n2\n10\n1.0\n20\n2.0\n10\n5.0\n20\n6.0\n0\nENDSEC\n0\nEOF\n"
  let doc = @dxf.DxfDocument::from_bytes(source, mode=@dxf.LosslessRoundTrip).unwrap()
  let edits = [
    doc.value_edit_by_handle("ab", 8, @dxf.Text(b"cut")),
    doc.value_edit_by_handle(
      "ac",
      10,
      @dxf.RealBits(9.0.reinterpret_as_int64()),
      occurrence=1,
    ),
  ]
  let result = doc.rewrite_values(edits)
  let changed = @dxf.DxfDocument::from_bytes(
    result.bytes,
    mode=@dxf.ReadOnlyLint,
  ).unwrap()
  for edit in edits {
    assert_eq(changed.tags()[edit.index].value, edit.value)
  }
  assert_eq(doc.original_bytes(), source)
  println(
    "\{result.changes.length()} handle-selected edits validated; original bytes retained outside selected spans",
  )
}

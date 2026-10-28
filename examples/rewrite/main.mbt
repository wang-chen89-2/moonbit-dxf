///|
fn main raise {
  let original = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n8\nold\n10\n1.0\n20\n2.0\n11\n3.0\n21\n4.0\n0\nENDSEC\n0\nEOF\n"
  let doc = @dxf.DxfDocument::from_bytes(original, mode=@dxf.LosslessRoundTrip).unwrap()
  let edits : Array[@dxf.ValueEdit] = []
  for index, tag in doc.tags() {
    let replacement = match tag.code {
      8 => Some(@dxf.Text(b"cut"))
      10 => Some(@dxf.RealBits(2.5.reinterpret_as_int64()))
      _ => None
    }
    if replacement is Some(value) {
      edits.push({ index, expected_code: tag.code, expected: tag.value, value, })
    }
  }
  let rewritten = doc.rewrite_values(edits)
  let result = @dxf.DxfDocument::from_bytes(
    rewritten.bytes,
    mode=@dxf.ReadOnlyLint,
  ).unwrap()
  assert_eq(result.tags()[3].text(), Some("cut"))
  assert_eq(result.tags()[4].real(), Some(2.5))
  assert_eq(doc.original_bytes(), original)
  println(
    "\{rewritten.changes.length()} validated edits; original \{original.length()} bytes, result \{rewritten.bytes.length()} bytes",
  )
  for change in rewritten.changes {
    println(
      "tag \{change.index}, code \{change.code}, original span [\{change.offset}, \{change.end_offset})",
    )
  }
}

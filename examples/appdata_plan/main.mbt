///|
fn main raise {
  let bytes = b"0\nLINE\n5\nAB\n102\n{ARCHIVE\n9\nold\n102\n}\n102\n{EDITOR\n9\nfirst\n9\nsecond\n102\n}\n102\n{EXPORT\n9\nsecond\n102\n}\n0\nEOF\n"
  let doc = @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip).unwrap()
  let edit = doc.value_edit_in_appdata(
    "AB",
    "EDITOR",
    9,
    @dxf.Text(b"reviewed"),
    occurrence=1,
  )
  let result = doc.rewrite_values([edit])
  let changed = @dxf.DxfDocument::from_bytes(
    result.bytes,
    mode=@dxf.ReadOnlyLint,
  ).unwrap()
  assert_eq(
    changed.tags().filter(t => t.code == 9).map(t => t.text().unwrap_or("")),
    ["old", "first", "reviewed", "second"],
  )
  assert_eq(doc.original_bytes(), bytes)
  println("one named application field selected; other applications retained")
}

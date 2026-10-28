///|
fn main raise {
  let input = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1.25\n20\n2.5\n11\n10.0\n21\n20.0\n0\nENDSEC\n0\nEOF\n"
  let doc = match
    @dxf.DxfDocument::from_bytes(input, mode=@dxf.LosslessRoundTrip) {
    Ok(d) => d
    Err(e) => fail("\{Repr(e)}")
  }
  let binary = doc.to_binary()
  let decoder = @dxf.DxfDecoder::new()
  for byte in binary {
    ignore(decoder.feed(Bytes::from_array([byte])))
  }
  let result = decoder.finish()
  assert_eq(result.save(), binary)
  assert_eq(result.to_ascii_bytes(), doc.to_ascii_bytes())
  println(
    "\{result.acad_version()}: \{result.tags().length()} tags, \{result.lint().length()} diagnostics, \{binary.length()} Binary bytes",
  )
}

///|
fn round06_doc(
  b : Bytes,
  mode~ : @dxf.OperationMode = @dxf.LosslessRoundTrip,
) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(b, mode~) {
    Ok(d) => d
    Err(e) => fail("\{Repr(e)}")
  }
}

///|
test "round06 opaque record variables do not impersonate HEADER version" {
  let source = b"0\nSECTION\n2\nENTITIES\n0\nVENDOR\n9\n$ACADVER\n1\nAC1009\n0\nENDSEC\n0\nEOF\n"
  let doc = round06_doc(source)
  assert_eq(doc.acad_version(), "AC1032")
  assert_true(doc.lint().any(d => d.code == "AssumedVersion"))
  let binary = doc.to_binary()
  assert_eq(binary[23], 0)
  let parsed = round06_doc(binary)
  assert_eq(parsed.acad_version(), "AC1032")
  assert_true(!parsed.lint().any(d => d.code == "WireVersionMismatch"))
  let edited = round06_doc(doc.rewrite_value(4, @dxf.Text(b"AC1015")))
  assert_eq(edited.acad_version(), "AC1032")
  assert_eq(doc.save(), source)
}

///|
test "round06 HEADER comments do not become the declared version" {
  let source = b"0\nSECTION\n999\nsection comment\n2\nHEADER\n9\n$ACADVER\n999\nthis is a comment\n1\nAC1009\n0\nENDSEC\n0\nEOF\n"
  let doc = round06_doc(source)
  assert_eq(doc.acad_version(), "AC1009")
  assert_true(
    !doc
    .lint()
    .any(d => d.code == "UnsupportedVersion" || d.code == "AssumedVersion"),
  )
  // Binary explicitly rejects comments, but must not mistake one for version text.
  assert_eq(doc.save(), source)
}

///|
test "round06 HEADER version edit remains protected across comments" {
  let source = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n999\ncomment\n1\nAC1009\n0\nENDSEC\n0\nEOF\n"
  let doc = round06_doc(source)
  try doc.rewrite_value(4, @dxf.Text(b"AC1032")) catch {
    @dxf.Unrepresentable(_) => ()
    _ => fail("wrong version edit error")
  } noraise {
    _ => fail("version changed without explicit migration")
  }
  assert_eq(doc.save(), source)
}

///|
test "round06 block references use case-insensitive table-name semantics" {
  let doc = round06_doc(
    b"0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n2\nPart\n0\nENDBLK\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nINSERT\n2\npART\n0\nENDSEC\n0\nEOF\n",
  )
  assert_true(!doc.lint().any(d => d.code == "DanglingBlock"))
  let unknown = round06_doc(
    b"0\nSECTION\n2\nENTITIES\n0\nINSERT\n2\nMissing\n0\nENDSEC\n0\nEOF\n",
  )
  assert_true(unknown.lint().any(d => d.code == "DanglingBlock"))
}

///|
test "round06 repair cannot bypass the tag budget with an invalid line pair" {
  let source = b"0\nSECTION\n2\nENTITIES\nNOT_A_CODE\n012345678901234567890123456789\n0\nENDSEC\n0\nEOF\n"
  for split in 0..<=source.length() {
    let decoder = @dxf.DxfDecoder::new(
      mode=@dxf.PermissiveRepair,
      max_tag_bytes=16,
    )
    try {
      ignore(decoder.feed(source[:split].to_owned()))
      ignore(decoder.feed(source[split:].to_owned()))
      ignore(decoder.finish())
    } catch {
      @dxf.ResourceLimit("max_tag_bytes") => ()
      _ => fail("wrong tag budget error at split \{split}")
    } noraise {
      _ => fail("oversized invalid tag bypassed budget at split \{split}")
    }
  }
}

///|
test "round06 UTF8 value BOM is content and does not create a HEADER variable" {
  let source = b"0\nSECTION\n2\nHEADER\n9\n\xef\xbb\xbf$ACADVER\n1\nAC1009\n0\nENDSEC\n0\nEOF\n"
  let doc = round06_doc(source)
  assert_eq(doc.tags()[2].text(), Some("\uFEFF$ACADVER"))
  assert_eq(doc.acad_version(), "AC1032")
  assert_true(doc.lint().any(d => d.code == "AssumedVersion"))
}

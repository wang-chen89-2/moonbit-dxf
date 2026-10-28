///|
fn load(
  s : Bytes,
  mode~ : @dxf.OperationMode = @dxf.LosslessRoundTrip,
) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(s, mode~) {
    Ok(d) => d
    Err(e) => fail("\{Repr(e)}")
  }
}

///|
test "five lint defect families and explicit repair boundary" {
  let source = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n5\nA\n0\nINSERT\n5\na\n2\nMISSING\n1001\nAPP\n1002\n{\n"
  let doc = load(source, mode=@dxf.ReadOnlyLint)
  for
    code in [
      "DuplicateHandle", "DanglingBlock", "UnbalancedXdata", "UnclosedSection", "MissingEof",
    ] {
    assert_true(doc.lint().any(d => d.code == code))
  }
  assert_eq(doc.save(), source)
  try doc.repair() catch {
    _ => ()
  } noraise {
    _ => fail("read-only mode repaired")
  }
  let repaired = load(source, mode=@dxf.PermissiveRepair).repair()
  let check = load(repaired.bytes)
  assert_true(
    !check
    .lint()
    .any(d => d.code == "MissingEof" || d.code == "UnclosedSection"),
  )
  assert_true(check.lint().any(d => d.code == "DuplicateHandle"))
  assert_eq(doc.original_bytes(), source)
}

///|
test "unknown ASCII groups preserved and never guessed as Binary" {
  let b = b"0\nSECTION\n2\nENTITIES\n0\nVENDOR_ENTITY\n700\nopaque payload\n0\nENDSEC\n0\nEOF\n"
  let doc = load(b)
  assert_eq(doc.save(), b)
  assert_true(doc.lint().any(d => d.code == "UnknownGroup"))
  try doc.to_binary() catch {
    _ => ()
  } noraise {
    _ => fail("unknown group converted")
  }
}

///|
test "Int64 extremes and raw IEEE sign survive Binary and ASCII conversions" {
  let doc = load(
    b"0\nSECTION\n2\nENTITIES\n0\nUNKNOWN\n160\n9223372036854775807\n161\n-9223372036854775808\n40\n-0.0\n1004\n00FF\n0\nENDSEC\n0\nEOF\n",
  )
  let binary = doc.to_binary()
  let parsed = load(binary)
  assert_true(
    parsed
    .tags()
    .any(t => t.code == 160 && t.integer() == Some(9223372036854775807L)),
  )
  assert_true(
    parsed
    .tags()
    .any(t => t.code == 161 && t.integer() == Some(-9223372036854775808L)),
  )
  let again = load(parsed.to_ascii_bytes())
  assert_true(
    again
    .tags()
    .any(t => t.code == 40 && t.value == @dxf.RealBits(-9223372036854775808L)),
  )
  assert_eq(parsed.save(), binary)
}

///|
test "truncated Binary repair only uses closed sections" {
  let doc = load(
    b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1.0\n0\nENDSEC\n0\nEOF\n",
  )
  let b = doc.to_binary()
  let damaged = b[:b.length() - 12].to_owned()
  let broken = load(damaged, mode=@dxf.PermissiveRepair)
  assert_true(!broken.is_complete())
  assert_eq(broken.original_bytes(), damaged)
  let repaired = broken.repair()
  assert_true(repaired.discarded_bytes > 0)
  assert_true(load(repaired.bytes).is_complete())
}

///|
test "unknown Binary type quarantines tail and cannot semantic-write" {
  let valid = load(b"0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF\n").to_binary()
  let b = valid + b"\xbc\x02\x00\x00\xff"
  let doc = load(b)
  assert_true(!doc.is_complete())
  assert_true(doc.raw_tail() is Some(_))
  assert_eq(doc.save(), b)
  try doc.to_binary() catch {
    _ => ()
  } noraise {
    _ => fail("opaque tail lost")
  }
}

///|
test "value edit preserves both original source spans" {
  let b = b"  0\r\nSECTION\r\n  2\r\nENTITIES\r\n0\r\nLINE\r\n10\r\n01.0000\r\n0\r\nENDSEC\r\n0\r\nEOF\r\n"
  let doc = load(b)
  let i = 3
  let t = doc.tags()[i]
  let edited = doc.rewrite_value(i, @dxf.RealBits(2.5.reinterpret_as_int64()))
  assert_true(edited.has_prefix(b[:t.offset]))
  assert_true(edited.has_suffix(b[t.end_offset:]))
  assert_eq(doc.original_bytes(), b)
  assert_true(load(edited).tags()[i].real() == Some(2.5))
}

///|
test "resource limits, lifecycle, truncated signature and unsupported version" {
  let decoder = @dxf.DxfDecoder::new(max_bytes=2)
  try decoder.feed(b"123") catch {
    _ => ()
  } noraise {
    _ => fail("size limit not enforced")
  }
  let d = @dxf.DxfDecoder::new()
  ignore(d.feed(b"0\nEOF\n"))
  ignore(d.finish())
  try d.feed(b"x") catch {
    _ => ()
  } noraise {
    _ => fail("feed after finish")
  }
  assert_true(!load(b"AutoCAD Binary DXF\r\n\x1a\x00").is_complete())
  let old = load(
    b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1012\n0\nENDSEC\n0\nEOF\n",
  )
  assert_true(old.lint().any(d => d.code == "UnsupportedVersion"))
  try old.to_binary() catch {
    _ => ()
  } noraise {
    _ => fail("ambiguous R13 accepted")
  }
}

///|
test "UTF8 replacement is explicit, legacy bytes remain bytes" {
  let b = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nUNKNOWN\n1\n\xff\n0\nENDSEC\n0\nEOF\n"
  let doc = load(b)
  assert_eq(doc.save(), b)
  assert_true(doc.lint().any(d => d.code == "InvalidUtf8"))
  let result = load(b, mode=@dxf.PermissiveRepair).repair()
  assert_true(result.diagnostics.any(d => d.code == "ReplacedUtf8"))
  assert_true(!load(result.bytes).lint().any(d => d.code == "InvalidUtf8"))
}

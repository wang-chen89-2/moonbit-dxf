///|
fn parse_boundary(
  b : Bytes,
  mode~ : @dxf.OperationMode = @dxf.LosslessRoundTrip,
) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(b, mode~) {
    Ok(doc) => doc
    Err(e) => fail("\{Repr(e)}")
  }
}

///|
test "ASCII repair records discarded bytes and ignores only trailing whitespace" {
  let input = b"0\nSECTION\n2\nENTITIES\nNO_CODE\njunk\n0\nENDSEC\n0\nEOF\n\r\n  \n"
  assert_true(!parse_boundary(input).is_complete())
  let doc = parse_boundary(input, mode=@dxf.PermissiveRepair)
  assert_true(doc.is_complete())
  let result = doc.repair()
  assert_eq(result.discarded_bytes, 13)
  assert_true(result.diagnostics.any(d => d.code == "DiscardedAsciiPair"))
  assert_true(parse_boundary(result.bytes).is_complete())
  assert_eq(doc.original_bytes(), input)
}

///|
test "R12 signed widths and legacy text bytes do not pass through Unicode conversion" {
  let input = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nVENDOR\n1\ncaf\xe9\n70\n-32768\n1071\n-2147483648\n0\nENDSEC\n0\nEOF\n"
  let doc = parse_boundary(input)
  let binary = doc.to_binary()
  let decoded = parse_boundary(binary)
  assert_true(decoded.tags().any(t => t.value == @dxf.Text(b"caf\xe9")))
  assert_true(decoded.tags().any(t => t.integer() == Some(-32768L)))
  assert_true(decoded.tags().any(t => t.integer() == Some(-2147483648L)))
  try decoded.to_ascii() catch {
    _ => ()
  } noraise {
    _ => fail("legacy bytes decoded as UTF8")
  }
}

///|
test "nonfinite IEEE payloads remain raw and are refused by text conversion" {
  let d = parse_boundary(
    b"0\nSECTION\n2\nENTITIES\n0\nVENDOR\n40\n1.0\n0\nENDSEC\n0\nEOF\n",
  )
  let b = d.to_binary()
  let doc = parse_boundary(b)
  let changed = doc.rewrite_value(3, @dxf.RealBits(0x7ff8000000000042L))
  let nan_doc = parse_boundary(changed)
  assert_eq(nan_doc.tags()[3].value, @dxf.RealBits(0x7ff8000000000042L))
  assert_eq(nan_doc.to_binary(), changed)
  assert_true(nan_doc.lint().any(d => d.code == "NonfiniteReal"))
  try nan_doc.to_ascii_bytes() catch {
    _ => ()
  } noraise {
    _ => fail("NaN payload silently converted")
  }
}

///|
test "DIMSTYLE code 5 is a reference; only code 105 defines its handle" {
  let d = parse_boundary(
    b"0\nSECTION\n2\nTABLES\n0\nDIMSTYLE\n105\nA\n5\nB\n0\nDIMSTYLE\n105\nC\n5\nB\n0\nENDSEC\n0\nEOF\n",
  )
  assert_true(!d.lint().any(d => d.code == "DuplicateHandle"))
}

///|
test "stream writer callback equals direct encoding and can propagate consumer errors" {
  let d = parse_boundary(b"0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF\n")
  let chunks : Array[Byte] = []
  d.write_to(binary=true, chunk => {
    for b in chunk {
      chunks.push(b)
    }
  })
  assert_eq(Bytes::from_array(chunks), d.to_binary())
  try d.write_to(binary=true, _ => fail("consumer stopped")) catch {
    _ => ()
  } noraise {
    _ => fail("consumer failure swallowed")
  }
}

///|
test "declared version profiles select the independent one-byte or two-byte wire family" {
  for
    version in [
      "AC1006", "AC1009", "AC1014", "AC1015", "AC1018", "AC1021", "AC1024", "AC1027",
      "AC1032",
    ] {
    let bytes = @utf8.encode(
      "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\n\{version}\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nVENDOR\n70\n-1\n1071\n2147483647\n0\nENDSEC\n0\nEOF\n",
    )
    let doc = parse_boundary(bytes)
    let encoded = doc.to_binary()
    assert_eq(
      encoded[23],
      if version == "AC1006" || version == "AC1009" {
        b'S'
      } else {
        0
      },
    )
    let round = parse_boundary(encoded)
    assert_eq(round.acad_version(), version)
    assert_true(round.is_complete())
    assert_true(round.tags().any(t => t.integer() == Some(-1L)))
    assert_true(round.tags().any(t => t.integer() == Some(2147483647L)))
    assert_true(!round.lint().any(d => d.code == "WireVersionMismatch"))
  }
}

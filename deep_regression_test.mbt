///|
fn deep_doc(
  b : Bytes,
  mode~ : @dxf.OperationMode = @dxf.LosslessRoundTrip,
) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(b, mode~) {
    Ok(d) => d
    Err(e) => fail("\{Repr(e)}")
  }
}

///|
test "deep structure names are protected while ordinary code 2 remains editable" {
  for
    source in [
      b"0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF\n", b"0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n0\nENDTAB\n0\nENDSEC\n0\nEOF\n",
    ] {
    let doc = deep_doc(source)
    for i, t in doc.tags() {
      if t.code == 2 {
        try doc.rewrite_value(i, @dxf.Text(b"HEADER")) catch {
          @dxf.Unrepresentable(_) => ()
          _ => fail("wrong structural edit error")
        } noraise {
          _ => fail("SECTION/TABLE name edit escaped structural guard")
        }
      }
    }
  }
  let doc = deep_doc(
    b"0\nSECTION\n2\nENTITIES\n0\nINSERT\n2\nOLD\n0\nENDSEC\n0\nEOF\n",
  )
  let edited = doc.rewrite_value(3, @dxf.Text(b"NEW"))
  assert_eq(deep_doc(edited).tags()[3].text(), Some("NEW"))
  let header = deep_doc(
    b"0\nSECTION\n2\nHEADER\n9\n$UCSNAME\n2\nOLD\n0\nENDSEC\n0\nEOF\n",
  )
  let ucs = header.rewrite_value(3, @dxf.Text(b"NEW"))
  assert_eq(deep_doc(ucs).tags()[3].text(), Some("NEW"))
}

///|
test "deep official XDATA scientific integer and exact scientific Int64" {
  let source = b"0\nSECTION\n2\nENTITIES\n0\nVENDOR\n1001\nAPP\n1071\n1.95059E+06\n160\n9.223372036854775807e18\n161\n-9.223372036854775808e18\n0\nENDSEC\n0\nEOF\n"
  let doc = deep_doc(source)
  assert_true(doc.is_complete())
  assert_true(
    doc.tags().any(t => t.code == 1071 && t.integer() == Some(1950590L)),
  )
  assert_true(
    doc
    .tags()
    .any(t => t.code == 160 && t.integer() == Some(9223372036854775807L)),
  )
  assert_true(
    doc
    .tags()
    .any(t => t.code == 161 && t.integer() == Some(-9223372036854775808L)),
  )
  let again = deep_doc(doc.to_binary())
  assert_true(
    again
    .tags()
    .any(t => t.code == 160 && t.integer() == Some(9223372036854775807L)),
  )
}

///|
test "deep repair must not migrate conflicting version and wire" {
  let source = deep_doc(
    b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n0\nEOF\n",
  ).to_binary()
  let pos = source.find(b"AC1032").unwrap()
  let bad = Bytes::makei(source.length(), i => {
    if i >= pos && i < pos + 6 {
      b"AC1009"[i - pos]
    } else {
      source[i]
    }
  })
  let doc = deep_doc(bad, mode=@dxf.PermissiveRepair)
  assert_true(doc.lint().any(d => d.code == "WireVersionMismatch"))
  try doc.repair() catch {
    @dxf.Unrepresentable(_) => ()
    _ => fail("wrong wire migration error")
  } noraise {
    _ => fail("repair silently changed Binary wire family")
  }
  assert_eq(doc.original_bytes(), bad)
}

///|
test "deep repair cannot silently discard complete records after EOF" {
  let source = b"0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF\n0\nLINE\n10\n123.0\n"
  let doc = deep_doc(source, mode=@dxf.PermissiveRepair)
  assert_true(doc.is_complete())
  assert_true(doc.lint().any(d => d.code == "AfterEof"))
  try doc.repair() catch {
    @dxf.Unrepresentable(_) => ()
    _ => fail("wrong out-of-contract recovery error")
  } noraise {
    _ => fail("repair dropped typed records with zero loss")
  }
}

///|
test "deep Binary repair cannot call a stray ENDSEC a complete section" {
  let binary = deep_doc(b"0\nENDSEC\n0\nEOF\n").to_binary() + b"\xbc\x02\xff"
  let doc = deep_doc(binary, mode=@dxf.PermissiveRepair)
  assert_true(!doc.is_complete())
  try doc.repair() catch {
    @dxf.Unrepresentable(_) => ()
    _ => fail("wrong closed-section recovery error")
  } noraise {
    _ => fail("stray ENDSEC was treated as a completed section")
  }
}

///|
test "deep every ASCII byte split covers CRLF UTF8 and typed numeric values" {
  let source = b"0\r\nSECTION\r\n2\r\nHEADER\r\n9\r\n$ACADVER\r\n1\r\nAC1032\r\n0\r\nENDSEC\r\n0\r\nSECTION\r\n2\r\nENTITIES\r\n0\r\nVENDOR\r\n1\r\n\xe6\xb5\x8b\xe8\xaf\x95\xf0\x9f\x90\x89\r\n160\r\n9223372036854775807\r\n40\r\n-0.0\r\n1004\r\n00FF80\r\n0\r\nENDSEC\r\n0\r\nEOF\r\n"
  let expected = deep_doc(source).tags()
  for split in 0..<=source.length() {
    let decoder = @dxf.DxfDecoder::new()
    let a = decoder.feed(source[:split].to_owned())
    let b = decoder.feed(source[split:].to_owned())
    let doc = decoder.finish()
    assert_eq(a.length() + b.length(), expected.length())
    assert_eq(doc.tags(), expected)
    assert_eq(doc.save(), source)
  }
}

///|
test "deep midstream callback error stops production immediately" {
  let doc = deep_doc(
    b"0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n2.0\n0\nENDSEC\n0\nEOF\n",
  )
  let count = Ref(0)
  try
    doc.write_to(binary=true, _ => {
      count.val += 1
      if count.val == 3 {
        fail("consumer failed on third chunk")
      }
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("consumer error was swallowed")
  }
  assert_eq(count.val, 3)
}

///|
test "deep opaque edits cannot inject records and literal version text is ordinary data" {
  let doc = deep_doc(
    b"0\nSECTION\n2\nENTITIES\n0\nVENDOR\n700\nsafe\n0\nENDSEC\n0\nEOF\n",
  )
  try doc.rewrite_value(3, @dxf.Opaque(b"safe\n0\nEOF")) catch {
    @dxf.Unrepresentable(_) => ()
    _ => fail("wrong opaque delimiter error")
  } noraise {
    _ => fail("opaque edit injected a record delimiter")
  }
  let ordinary = deep_doc(
    b"0\nSECTION\n2\nENTITIES\n0\nVENDOR\n1\n$ACADVER\n2\nordinary\n0\nENDSEC\n0\nEOF\n",
  )
  let edited = ordinary.rewrite_value(4, @dxf.Text(b"new value"))
  assert_eq(deep_doc(edited).tags()[4].text(), Some("new value"))
}

///|
test "deep Binary cut on a tag boundary still cannot invent an open section" {
  let full = deep_doc(
    b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1.0\n0\nENDSEC\n0\nEOF\n",
  ).to_binary()
  let parsed = deep_doc(full)
  let endsecs = parsed
    .tags()
    .filter(t => t.code == 0 && t.text() == Some("ENDSEC"))
  let truncated = full[:endsecs[1].offset].to_owned()
  let doc = deep_doc(truncated, mode=@dxf.PermissiveRepair)
  assert_true(doc.is_complete()) // complete tag coverage is not a closed section
  assert_true(doc.lint().any(d => d.code == "UnclosedSection"))
  let repaired = doc.repair()
  assert_eq(
    repaired.discarded_bytes,
    truncated.length() - endsecs[0].end_offset,
  )
  assert_true(
    !deep_doc(repaired.bytes).tags().any(t => t.text() == Some("ENTITIES")),
  )
}

///|
test "deep exact decimal integer range and fractional failure paths" {
  for
    value in [
      "9223372036854775808e0", "-9223372036854775809e0", "1.1", "1e-1", "1e999999999999999999999999",
      "1e", "1e--2",
    ] {
    let doc = deep_doc(
      @utf8.encode(
        "0\nSECTION\n2\nENTITIES\n0\nVENDOR\n160\n\{value}\n0\nENDSEC\n0\nEOF\n",
      ),
    )
    assert_true(!doc.is_complete())
    assert_true(doc.lint().any(d => d.code == "InvalidTag"))
  }
  for value in ["195059000e-2", "001950590.000", "+1.9505900e6"] {
    let doc = deep_doc(
      @utf8.encode(
        "0\nSECTION\n2\nENTITIES\n0\nVENDOR\n1071\n\{value}\n0\nENDSEC\n0\nEOF\n",
      ),
    )
    assert_true(doc.is_complete())
    assert_eq(doc.tags()[3].integer(), Some(1950590L))
  }
}

///|
test "deep Binary every cut retains raw tails and every two-chunk split agrees" {
  for version in ["AC1009", "AC1032"] {
    let ascii = @utf8.encode(
      "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\n\{version}\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nVENDOR\n1\n龙\n40\n-0.0\n1001\nAPP\n1070\n-32768\n1071\n2147483647\n1004\n00FF80\n0\nENDSEC\n0\nEOF\n",
    )
    let binary = deep_doc(ascii).to_binary()
    let expected = deep_doc(binary).tags()
    for cut in 0..<=binary.length() {
      let prefix = binary[:cut].to_owned()
      let partial = deep_doc(prefix)
      assert_eq(partial.save(), prefix)
      if !partial.is_complete() {
        guard partial.raw_tail() is Some(tail) else {
          fail("missing opaque/truncated tail")
        }
        assert_eq(tail.bytes, prefix[tail.offset:].to_owned())
        try partial.to_binary() catch {
          _ => ()
        } noraise {
          _ => fail("partial input converted")
        }
      }
      let decoder = @dxf.DxfDecoder::new()
      ignore(decoder.feed(prefix))
      ignore(decoder.feed(binary[cut:].to_owned()))
      let doc = decoder.finish()
      assert_true(doc.is_complete())
      assert_eq(doc.tags(), expected)
      assert_eq(doc.save(), binary)
    }
  }
}

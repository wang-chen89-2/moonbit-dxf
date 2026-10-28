///|
fn rewrite_doc(bytes : Bytes) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip) {
    Ok(doc) => doc
    Err(error) => fail("\{Repr(error)}")
  }
}

///|
fn edit_for(
  doc : @dxf.DxfDocument,
  code : Int32,
  value : @dxf.TagValue,
) -> @dxf.ValueEdit raise {
  for index, tag in doc.tags() {
    if tag.code == code {
      return { index, expected_code: code, expected: tag.value, value, }
    }
  }
  fail("missing field")
}

///|
test "rewrite batch preserves unselected ASCII bytes with unsorted length-changing edits" {
  let source = b"0\r\nSECTION\r\n 2\r\nENTITIES\r\n0\r\nLINE\r\n 8\r\nold\r\n10\r\n1.0\r\n20\r\n2.0\r\n777\r\nraw caf\xe9\r\n0\r\nENDSEC\r\n0\r\nEOF\r\n"
  let doc = rewrite_doc(source)
  let layer = edit_for(doc, 8, @dxf.Text(b"new-layer"))
  let x = edit_for(doc, 10, @dxf.RealBits(-9223372036854775808L))
  let edits = [x, layer]
  let result = doc.rewrite_values(edits)
  assert_eq(
    result.bytes,
    b"0\r\nSECTION\r\n 2\r\nENTITIES\r\n0\r\nLINE\r\n8\nnew-layer\n10\n-0.0\n20\r\n2.0\r\n777\r\nraw caf\xe9\r\n0\r\nENDSEC\r\n0\r\nEOF\r\n",
  )
  assert_eq(result.changes.length(), 2)
  assert_eq(result.changes[0].index, layer.index)
  assert_eq(result.changes[0].before, b" 8\r\nold\r\n")
  assert_eq(result.changes[0].after, b"8\nnew-layer\n")
  assert_eq(result.changes[1].before, b"10\r\n1.0\r\n")
  assert_eq(edits[0].index, x.index)
  assert_eq(doc.save(), source)
}

///|
test "rewrite batch covers both Binary widths legacy text and exact numeric payloads" {
  for version in ["AC1009", "AC1032"] {
    let name = if version == "AC1009" { b"caf\xe9" } else { b"caf\xc3\xa9" }
    let ascii = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\n" +
      @utf8.encode(version) +
      b"\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLINE\n8\n" +
      name +
      b"\n10\n1.0\n20\n2.0\n11\n3.0\n21\n4.0\n1001\nPATCH\n1071\n2147483647\n0\nENDSEC\n0\nEOF\n"
    let source = rewrite_doc(ascii).to_binary()
    let doc = rewrite_doc(source)
    let result = doc.rewrite_values([
      edit_for(doc, 1071, @dxf.Integer(-2147483648L)),
      edit_for(doc, 8, @dxf.Text(b"cut")),
      edit_for(doc, 10, @dxf.RealBits(-9223372036854775808L)),
    ])
    let parsed = rewrite_doc(result.bytes)
    assert_eq(parsed.acad_version(), version)
    assert_eq(parsed.tags().length(), doc.tags().length())
    for index, tag in doc.tags() {
      let after = parsed.tags()[index]
      if tag.code == 8 {
        assert_eq(after.text(), Some("cut"))
      } else if tag.code == 10 {
        assert_eq(after.value, @dxf.RealBits(-9223372036854775808L))
      } else if tag.code == 1071 {
        assert_eq(after.integer(), Some(-2147483648L))
      } else {
        assert_eq(after.value, tag.value)
        assert_eq(
          result.bytes[after.offset:after.end_offset],
          source[tag.offset:tag.end_offset],
        )
      }
    }
    assert_eq(result.bytes[:22], source[:22])
    assert_eq(doc.save(), source)
  }
}

///|
test "rewrite batch preconditions duplicates and invalid indices refuse the whole plan" {
  let source = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n8\nold\n10\n1.0\n0\nENDSEC\n0\nEOF\n"
  let doc = rewrite_doc(source)
  let layer = edit_for(doc, 8, @dxf.Text(b"cut"))
  let x = edit_for(doc, 10, @dxf.RealBits(2.5.reinterpret_as_int64()))
  for
    plan in [
      [layer, { ..x, expected: @dxf.RealBits(0L), }],
      [layer, { ..x, expected_code: 20, }],
      [layer, layer],
      [layer, { ..x, index: -1, }],
      [layer, { ..x, index: 2147483647, }],
    ] {
    try doc.rewrite_values(plan) catch {
      @dxf.Invalid(..) => ()
      _ => fail("wrong plan rejection")
    } noraise {
      _ => fail("invalid plan returned output")
    }
    assert_eq(doc.save(), source)
  }
}

///|
test "rewrite batch structural and wire rules agree with the single-value API" {
  let doc = rewrite_doc(
    b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n999\ncomment\n1\nAC1032\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1.0\n0\nENDSEC\n0\nEOF\n",
  )
  for index in [0, 1, 2, 4] {
    let tag = doc.tags()[index]
    let plan : Array[@dxf.ValueEdit] = [
      {
        index,
        expected_code: tag.code,
        expected: tag.value,
        value: @dxf.Text(b"changed"),
      },
    ]
    try doc.rewrite_values(plan) catch {
      @dxf.Unrepresentable(_) => ()
      _ => fail("wrong structural error")
    } noraise {
      _ => fail("structural edit succeeded")
    }
  }
  let x = edit_for(doc, 10, @dxf.RealBits(2.5.reinterpret_as_int64()))
  assert_eq(doc.rewrite_values([x]).bytes, doc.rewrite_value(x.index, x.value))
  for value in [@dxf.Integer(1L), @dxf.RealBits(9218868437227405312L)] {
    try doc.rewrite_values([{ ..x, value, }]) catch {
      @dxf.Unrepresentable(_) => ()
      _ => fail("wrong wire rejection")
    } noraise {
      _ => fail("invalid ASCII scalar encoded")
    }
  }
}

///|
test "rewrite batch empty plans preserve opaque tails while nonempty plans refuse them" {
  let source = b"0\nSECTION\n2\nENTITIES\n0\nLINE\n10\n1.0\n20\n"
  let doc = rewrite_doc(source)
  let empty = doc.rewrite_values([])
  assert_eq(empty.bytes, source)
  assert_eq(empty.changes.length(), 0)
  let x = edit_for(doc, 10, @dxf.RealBits(2.0.reinterpret_as_int64()))
  try doc.rewrite_values([x]) catch {
    @dxf.IncompleteDocument => ()
    _ => fail("wrong incomplete rejection")
  } noraise {
    _ => fail("partial source rewritten")
  }
}

///|
test "rewrite batch compares real payload bits and supports opaque ASCII scalar changes" {
  let doc = rewrite_doc(
    b"0\nSECTION\n2\nENTITIES\n0\nVENDOR\n10\n-0.0\n777\noriginal\n0\nENDSEC\n0\nEOF\n",
  )
  let x = edit_for(doc, 10, @dxf.RealBits(0L))
  try doc.rewrite_values([{ ..x, expected: @dxf.RealBits(0L), }]) catch {
    @dxf.Invalid(..) => ()
    _ => fail("wrong bitwise precondition failure")
  } noraise {
    _ => fail("negative-zero precondition treated as positive zero")
  }
  let raw_edit = edit_for(doc, 777, @dxf.Opaque(b"changed"))
  let result = doc.rewrite_values([raw_edit, x])
  assert_eq(rewrite_doc(result.bytes).tags()[4].value, @dxf.Opaque(b"changed"))
  try doc.rewrite_values([{ ..raw_edit, value: @dxf.Opaque(b"x\n0"), }]) catch {
    @dxf.Unrepresentable(_) => ()
    _ => fail("wrong opaque delimiter error")
  } noraise {
    _ => fail("opaque value injected a physical record")
  }
}

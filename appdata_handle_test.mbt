///|
fn appdata_target_doc(bytes : Bytes) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip) {
    Ok(doc) => doc
    Err(error) => fail("\{Repr(error)}")
  }
}

///|
test "round16 named group selects direct occurrence and exact typed old values" {
  let ascii = b"0\nLINE\n5\nAB\n102\n{ARCHIVE\n9\nsame\n102\n}\n102\n{EDITOR\n9\nfirst\n102\n{CHILD\n9\nshadow\n102\n}\n9\nsecond\n160\n9007199254740993\n102\nEDITOR}\n102\n{EXPORT\n9\nsecond\n102\n}\n8\nordinary\n0\nEOF\n"
  for bytes in [ascii, appdata_target_doc(ascii).to_binary()] {
    let doc = appdata_target_doc(bytes)
    let edit = doc.value_edit_in_appdata(
      "000ab",
      "EDITOR",
      9,
      @dxf.Text(b"reviewed"),
      occurrence=1,
    )
    let integer = doc.value_edit_in_appdata(
      "AB",
      "EDITOR",
      160,
      @dxf.Integer(-2L),
    )
    assert_eq(edit.expected, @dxf.Text(b"second"))
    assert_eq(integer.expected, @dxf.Integer(9007199254740993L))
    let changed = appdata_target_doc(doc.rewrite_values([edit, integer]).bytes)
    assert_eq(changed.tags()[integer.index].integer(), Some(-2L))
    assert_eq(
      changed.tags().filter(t => t.code == 9).map(t => t.text().unwrap_or("")),
      ["same", "first", "shadow", "reviewed", "second"],
    )
    assert_eq(
      doc.value_edit_by_handle("AB", 8, @dxf.Text(b"cut")).expected,
      @dxf.Text(b"ordinary"),
    )
    try doc.value_edit_by_handle("AB", 9, @dxf.Text(b"wrong")) catch {
      @dxf.Invalid(..) => ()
      _ => fail("wrong default lookup error")
    } noraise {
      _ => fail("default lookup entered application data")
    }
    assert_eq(doc.save(), bytes)
  }
}

///|
test "round16 named selection rejects missing ambiguous and incomplete targets" {
  let source = b"0\nLINE\n5\nAB\n102\n{EDITOR\n9\nold\n102\n}\n0\nEOF\n"
  let doc = appdata_target_doc(source)
  for
    (name, code, occurrence) in [
      ("MISSING", 9, 0),
      ("editor", 9, 0),
      ("", 9, 0),
      ("{EDITOR", 9, 0),
      ("EDITOR", 0, 0),
      ("EDITOR", 102, 0),
      ("EDITOR", 9, -1),
      ("EDITOR", 9, 1),
    ] {
    try
      doc.value_edit_in_appdata(
        "AB",
        name,
        code,
        @dxf.Text(b"new"),
        occurrence~,
      )
    catch {
      @dxf.Invalid(..) => ()
      _ => fail("wrong selector rejection")
    } noraise {
      _ => fail("invalid selector guessed a field")
    }
  }
  for
    body in [
      b"102\n{EDITOR\n9\na\n102\n}\n102\n{EDITOR\n9\nb\n102\n}\n", b"102\n{EDITOR\n9\na\n",
      b"102\n{EDITOR\n9\na\n102\nOTHER}\n", b"102\n{OUTER\n102\n{EDITOR\n9\na\n102\n}\n102\n}\n",
      b"102\n{EDITOR\n102\n}\n",
    ] {
    let bytes = b"0\nLINE\n5\nAB\n" + body + b"0\nEOF\n"
    let check = appdata_target_doc(bytes)
    try
      check.value_edit_in_appdata("AB", "EDITOR", 9, @dxf.Text(b"new"))
    catch {
      @dxf.Invalid(..) => ()
      _ => fail("wrong application group rejection")
    } noraise {
      _ => fail("ambiguous or incomplete group was selected")
    }
    assert_eq(check.save(), bytes)
  }
  assert_eq(doc.save(), source)
}

///|
test "round16 application targeting keeps DIMSTYLE ownership and legacy payload bytes" {
  let ascii = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1015\n0\nENDSEC\n0\nSECTION\n2\nTABLES\n0\nDIMSTYLE\n105\nAB\n5\nCD\n102\n{EDITOR\n5\nEF\n9\ncaf\xe9\n102\n}\n100\nAcDbSymbolTableRecord\n2\nSTYLE\n0\nENDSEC\n0\nEOF\n"
  for bytes in [ascii, appdata_target_doc(ascii).to_binary()] {
    let doc = appdata_target_doc(bytes)
    let edit = doc.value_edit_in_appdata("ab", "EDITOR", 9, @dxf.Text(b"new"))
    assert_eq(edit.expected, @dxf.Text(b"caf\xe9"))
    let changed = appdata_target_doc(doc.rewrite_values([edit]).bytes)
    assert_eq(changed.tags()[edit.index].text(), Some("new"))
    for handle in ["CD", "EF"] {
      try
        doc.value_edit_in_appdata(handle, "EDITOR", 9, @dxf.Text(b"wrong"))
      catch {
        @dxf.Invalid(..) => ()
        _ => fail("wrong owner handle rejection")
      } noraise {
        _ => fail("reference or payload handle became the owner")
      }
    }
    assert_eq(doc.save(), bytes)
  }
}

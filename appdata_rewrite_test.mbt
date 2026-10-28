// Original entity exported with ezdxf 1.4.3; CC0-1.0 model metadata.

///|
fn app_edit_doc(bytes : Bytes) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.LosslessRoundTrip) {
    Ok(doc) => doc
    Err(error) => fail("\{Repr(error)}")
  }
}

///|
fn app_edit_index(
  doc : @dxf.DxfDocument,
  code : Int32,
  text : String,
) -> Int32 raise {
  for i, tag in doc.tags() {
    if tag.code == code && tag.text() == Some(text) {
      return i
    }
  }
  fail("missing test field")
}

///|
fn app_edit_for(
  doc : @dxf.DxfDocument,
  index : Int32,
  text : Bytes,
) -> @dxf.ValueEdit {
  let tag = doc.tags()[index]
  {
    index,
    expected_code: tag.code,
    expected: tag.value,
    value: @dxf.Text(text),
  }
}

///|
test "round15 application code9 metadata edits are not HEADER migrations" {
  let ascii = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n  0\nLINE\n  5\n34\n102\n{EDITOR_META\n  9\nold-note\n  2\nshadow-name\n102\n}\n330\n17\n100\nAcDbEntity\n  8\n0\n100\nAcDbLine\n 10\n1.25\n 20\n-2.5\n 30\n0.0\n 11\n9.0\n 21\n12.0\n 31\n0.0\n1001\nDXF_TEST\n1000\nfixture\n1002\n{\n1070\n-32768\n1071\n2147483647\n1040\n-0.0\n1004\n00FF01\n1002\n}\n0\nENDSEC\n0\nEOF\n"
  for bytes in [ascii, app_edit_doc(ascii).to_binary()] {
    let doc = app_edit_doc(bytes)
    let index = app_edit_index(doc, 9, "old-note")
    let edit = app_edit_for(doc, index, b"new-note")
    let batch = doc.rewrite_values([edit])
    assert_eq(batch.bytes, doc.rewrite_value(index, edit.value))
    assert_eq(batch.changes.length(), 1)
    assert_eq(batch.changes[0].offset, doc.tags()[index].offset)
    assert_eq(app_edit_doc(batch.bytes).tags()[index].text(), Some("new-note"))
    assert_true(
      app_edit_doc(batch.bytes)
      .tags()
      .any(t => t.code == 2 && t.text() == Some("shadow-name")),
    )
    assert_eq(doc.save(), bytes)
  }
}

///|
test "round15 real structural fields stay protected beside nested private fields" {
  let ascii = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1032\n0\nENDSEC\n0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLAYER\n102\n{OUTER\n9\nold-note\n102\n{INNER\n2\nshadow-name\n102\nINNER}\n102\n}\n0\nENDTAB\n0\nENDSEC\n0\nEOF\n"
  for bytes in [ascii, app_edit_doc(ascii).to_binary()] {
    let doc = app_edit_doc(bytes)
    let metadata = app_edit_for(
      doc,
      app_edit_index(doc, 9, "old-note"),
      b"new-note",
    )
    ignore(doc.rewrite_values([metadata]))
    for i, tag in doc.tags() {
      if tag.code == 0 ||
        tag.text() == Some("$ACADVER") ||
        tag.text() == Some("AC1032") ||
        (
          tag.code == 2 &&
          ["HEADER", "TABLES", "LAYER"].contains(tag.text().unwrap_or(""))
        ) {
        let forbidden = app_edit_for(doc, i, b"changed")
        try doc.rewrite_values([metadata, forbidden]) catch {
          @dxf.Unrepresentable(_) => ()
          _ => fail("wrong structural rejection")
        } noraise {
          _ => fail("real structural edit was permitted")
        }
        try doc.rewrite_value(i, forbidden.value) catch {
          @dxf.Unrepresentable(_) => ()
          _ => fail("wrong single structural rejection")
        } noraise {
          _ => fail("single structural edit was permitted")
        }
        assert_eq(doc.save(), bytes)
      }
    }
  }
}

///|
test "round15 unfinished APPDATA cannot hide the next record structural locks" {
  let ascii = b"0\nSECTION\n2\nTABLES\n0\nLINE\n102\n{UNFINISHED\n9\nold-note\n0\nTABLE\n2\nLAYER\n0\nENDTAB\n0\nENDSEC\n0\nEOF\n"
  for bytes in [ascii, app_edit_doc(ascii).to_binary()] {
    let doc = app_edit_doc(bytes)
    let metadata = app_edit_for(
      doc,
      app_edit_index(doc, 9, "old-note"),
      b"new-note",
    )
    ignore(doc.rewrite_values([metadata]))
    for (code, text) in [(0, "TABLE"), (2, "LAYER")] {
      let forbidden = app_edit_for(
        doc,
        app_edit_index(doc, code, text),
        b"changed",
      )
      try doc.rewrite_values([metadata, forbidden]) catch {
        @dxf.Unrepresentable(_) => ()
        _ => fail("wrong record boundary rejection")
      } noraise {
        _ => fail("unfinished group hid a real structural field")
      }
      assert_eq(doc.save(), bytes)
    }
  }
}

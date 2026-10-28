///|
fn table_doc(
  bytes : Bytes,
  mode~ : @dxf.OperationMode = @dxf.LosslessRoundTrip,
) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(bytes, mode~) {
    Ok(doc) => doc
    Err(error) => fail("\{Repr(error)}")
  }
}

///|
test "round12 following TABLE cannot hide an earlier missing ENDTAB" {
  let ascii = b"0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLTYPE\n0\nTABLE\n2\nLAYER\n0\nENDTAB\n0\nENDSEC\n0\nEOF\n"
  for bytes in [ascii, table_doc(ascii).to_binary()] {
    for mode in [@dxf.LosslessRoundTrip, @dxf.ReadOnlyLint] {
      let doc = table_doc(bytes, mode~)
      let issues = doc.lint().filter(d => d.code == "UnclosedTable")
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].offset, doc.tags()[4].offset)
      assert_eq(issues[0].severity, @dxf.Error)
      assert_true(doc.is_complete())
      assert_eq(doc.save(), bytes)
      assert_eq(doc.original_bytes(), bytes)
    }
    let repaired = table_doc(bytes, mode=@dxf.PermissiveRepair).repair()
    assert_true(repaired.diagnostics.any(d => d.code == "UnclosedTable"))
    assert_true(
      table_doc(repaired.bytes).lint().any(d => d.code == "UnclosedTable"),
    )
  }
}

///|
test "round12 consecutive closed and empty tables remain valid" {
  let ascii = b"0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLTYPE\n0\nENDTAB\n0\nTABLE\n2\nLAYER\n0\nLAYER\n2\nA\n70\n0\n0\nENDTAB\n0\nENDSEC\n0\nEOF\n"
  for bytes in [ascii, table_doc(ascii).to_binary()] {
    let doc = table_doc(bytes, mode=@dxf.ReadOnlyLint)
    assert_true(!doc.lint().any(d => d.severity == @dxf.Error))
    assert_eq(doc.save(), bytes)
  }
}

///|
test "round12 each missing table boundary and terminal path stays visible" {
  let sources = [
    b"0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLTYPE\n0\nTABLE\n2\nLAYER\n0\nTABLE\n2\nSTYLE\n0\nENDTAB\n0\nENDSEC\n0\nEOF\n",
    b"0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLTYPE\n0\nENDSEC\n0\nEOF\n", b"0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLTYPE\n0\nEOF\n",
  ]
  for i, ascii in sources {
    for bytes in [ascii, table_doc(ascii).to_binary()] {
      let doc = table_doc(bytes, mode=@dxf.ReadOnlyLint)
      assert_eq(
        doc.lint().filter(d => d.code == "UnclosedTable").length(),
        if i == 0 {
          2
        } else {
          1
        },
      )
      assert_eq(doc.save(), bytes)
    }
  }
}

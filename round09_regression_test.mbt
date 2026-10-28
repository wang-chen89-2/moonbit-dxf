///|
fn round09_doc(bytes : Bytes) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.ReadOnlyLint) {
    Ok(doc) => doc
    Err(error) => fail("\{Repr(error)}")
  }
}

///|
test "round09 APPDATA cannot impersonate handles block names or XDATA controls" {
  let source = b"0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n2\nREAL\n0\nENDBLK\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLINE\n5\nA\n0\nLINE\n5\nB\n102\n{BATCH\n5\nA\n1002\n{\n102\nBATCH}\n0\nINSERT\n5\nC\n102\n{BATCH\n2\nMISSING\n102\n}\n2\nREAL\n0\nENDSEC\n0\nEOF\n"
  for encoded in [source, round09_doc(source).to_binary()] {
    let doc = round09_doc(encoded)
    for code in ["DuplicateHandle", "DanglingBlock", "UnbalancedXdata"] {
      assert_true(!doc.lint().any(d => d.code == code))
    }
    assert_eq(doc.save(), encoded)
  }
}

///|
test "round09 real defects after APPDATA remain visible" {
  let doc = round09_doc(
    b"0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n102\n{BATCH\n2\nFAKE\n102\n}\n2\nREAL\n0\nENDBLK\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nLINE\n5\nA\n102\n{BATCH\n5\nB\n102\n}\n0\nLINE\n5\na\n0\nINSERT\n2\nFAKE\n1001\nAPP\n1002\n{\n0\nENDSEC\n0\nEOF\n",
  )
  for code in ["DuplicateHandle", "DanglingBlock", "UnbalancedXdata"] {
    assert_true(doc.lint().any(d => d.code == code))
  }
}

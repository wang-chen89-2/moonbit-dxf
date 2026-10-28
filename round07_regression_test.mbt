///|
fn round07_doc(bytes : Bytes) -> @dxf.DxfDocument raise {
  match @dxf.DxfDocument::from_bytes(bytes, mode=@dxf.ReadOnlyLint) {
    Ok(doc) => doc
    Err(e) => fail("\{Repr(e)}")
  }
}

///|
test "round07 nondecimal integer prefixes are diagnosed without rewriting their raw bytes" {
  for code in [70, 90, 160] {
    for token in ["0x10", "0o10", "0b10"] {
      let bytes = @utf8.encode("\{code}\n\{token}\n0\nEOF\n")
      let doc = round07_doc(bytes)
      assert_true(!doc.is_complete())
      assert_true(doc.lint().any(d => d.code == "InvalidTag"))
      assert_eq(doc.save(), bytes)
      try doc.to_binary() catch {
        @dxf.IncompleteDocument => ()
        _ => fail("wrong conversion refusal")
      } noraise {
        _ => fail("invalid integer re-encoded as a legitimate number")
      }
    }
  }
  for token in ["01", "+01", "1.0", "1e0"] {
    let doc = round07_doc(@utf8.encode("70\n\{token}\n0\nEOF\n"))
    assert_true(doc.is_complete())
    assert_eq(doc.tags()[0].integer(), Some(1L))
  }
  assert_eq(round07_doc(b"1\n0x10\n0\nEOF\n").tags()[0].text(), Some("0x10"))
}

///|
test "round07 nondecimal group code is not silently interpreted as a decimal tag" {
  let bytes = b"0x46\n1\n0\nEOF\n"
  let doc = round07_doc(bytes)
  assert_true(!doc.is_complete())
  assert_true(doc.lint().any(d => d.code == "InvalidTag"))
  assert_eq(doc.save(), bytes)
}

///|
test "round07 distinct legacy block bytes do not collapse into one UTF8 failure" {
  let header = b"0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1015\n9\n$DWGCODEPAGE\n3\nANSI_1252\n0\nENDSEC\n"
  let source = header +
    b"0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n2\nA\xe9\n0\nENDBLK\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nINSERT\n2\nB\xe9\n0\nENDSEC\n0\nEOF\n"
  let doc = round07_doc(source)
  assert_true(doc.lint().any(d => d.code == "DanglingBlock"))
  assert_eq(doc.save(), source)
  let binary = round07_doc(doc.to_binary())
  assert_true(binary.lint().any(d => d.code == "DanglingBlock"))
  for name in [b"A\xe9", b"a\xe9"] {
    let valid = round07_doc(
      header +
      b"0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n2\nA\xe9\n0\nENDBLK\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nINSERT\n2\n" +
      name +
      b"\n0\nENDSEC\n0\nEOF\n",
    )
    assert_true(!valid.lint().any(d => d.code == "DanglingBlock"))
  }
}

///|
test "round07 Julian-date and elapsed-day header fields retain their Double values" {
  let expected = [
    4702519063966193830L, 4702519064415698944L, 4532949752942055721L, 4602678819172646912L,
  ]
  for version in ["AC1009", "AC1032"] {
    let bytes = @utf8.encode(
      "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\n\{version}\n9\n$TDCREATE\n40\n2451544.91568287\n9\n$TDUPDATE\n40\n2451545.125\n9\n$TDINDWG\n40\n1.1574074074074073e-05\n9\n$TDUSRTIMER\n40\n0.5\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nENDSEC\n0\nEOF\n",
    )
    let original = round07_doc(bytes)
    assert_eq(original.save(), bytes)
    let binary = original.to_binary()
    let ascii = round07_doc(binary).to_ascii_bytes()
    for encoded in [bytes, binary, ascii] {
      let doc = round07_doc(encoded)
      let actual : Array[Int64] = []
      for tag in doc.tags() {
        if tag.value is @dxf.RealBits(bits) {
          actual.push(bits)
        }
      }
      assert_eq(actual, expected)
      assert_eq(doc.acad_version(), version)
    }
  }
}

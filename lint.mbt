///|
/// A bounded record-level linter, not all Autodesk semantic/audit rules.
pub fn DxfDocument::lint(self : DxfDocument) -> Array[Diagnostic] {
  let result = self.issues.copy()
  let handles : Map[String, Int32] = Map([])
  let blocks : Map[Bytes, Bool] = Map([])
  let references : Array[(Bytes, Int32)] = []
  let mut section = ""
  let mut record = ""
  let mut need_section = false
  let mut eof_seen = false
  let mut xdepth = 0
  let mut app_depth = 0
  let mut pending_table = false
  let declared = header_version_tag(self.items) is Some(_)
  for t in self.items {
    let text = t.text().unwrap_or("")
    let next_app_depth = appdata_depth_after(app_depth, t)
    let in_appdata = app_depth > 0 || next_app_depth > 0
    app_depth = next_app_depth
    if t.code == 0 {
      if xdepth != 0 {
        result.push(
          diagnostic(
            "UnbalancedXdata",
            t.offset,
            "XDATA list not closed before record end",
          ),
        )
        xdepth = 0
      }
      if eof_seen {
        result.push(diagnostic("AfterEof", t.offset, "records after EOF"))
      }
      record = text
      if text == "SECTION" {
        if section != "" || need_section {
          result.push(
            diagnostic(
              "UnclosedSection",
              t.offset,
              "previous SECTION lacks ENDSEC",
            ),
          )
        }
        need_section = true
      } else if text == "ENDSEC" {
        if section == "" {
          result.push(
            diagnostic("UnexpectedEndsec", t.offset, "ENDSEC outside SECTION"),
          )
        }
        section = ""
        need_section = false
        if pending_table {
          result.push(
            diagnostic("UnclosedTable", t.offset, "TABLE lacks ENDTAB"),
          )
          pending_table = false
        }
      } else if text == "EOF" {
        eof_seen = true
        if section != "" || need_section {
          result.push(
            diagnostic("UnclosedSection", t.offset, "EOF inside SECTION"),
          )
        }
      } else if text == "TABLE" {
        if pending_table {
          result.push(
            diagnostic("UnclosedTable", t.offset, "previous TABLE lacks ENDTAB"),
          )
        }
        pending_table = true
      } else if text == "ENDTAB" {
        pending_table = false
      }
    }
    if need_section && t.code == 2 {
      section = text
      need_section = false
    }
    if (
        (t.code == 5 && record != "DIMSTYLE") ||
        (t.code == 105 && record == "DIMSTYLE")
      ) &&
      text != "" &&
      !in_appdata {
      let key = text.to_upper()
      match handles.get(key) {
        Some(_) =>
          result.push(
            diagnostic("DuplicateHandle", t.offset, "duplicate handle \{text}"),
          )
        None => handles[key] = t.offset
      }
    }
    if record == "BLOCK" && t.code == 2 && !in_appdata {
      if t.value is Text(name) {
        blocks[block_name_key(name)] = true
      }
    }
    if record == "INSERT" && t.code == 2 && !in_appdata {
      if t.value is Text(name) {
        references.push((name, t.offset))
      }
    }
    if t.code == 1001 && xdepth != 0 && !in_appdata {
      result.push(
        diagnostic(
          "UnbalancedXdata",
          t.offset,
          "new APPID inside unclosed list",
        ),
      )
      xdepth = 0
    }
    if t.code == 1002 && !in_appdata {
      if text == "{" {
        xdepth += 1
      } else if text == "}" {
        if xdepth == 0 {
          result.push(
            diagnostic(
              "UnbalancedXdata",
              t.offset,
              "unexpected XDATA closing brace",
            ),
          )
        } else {
          xdepth -= 1
        }
      } else {
        result.push(
          diagnostic(
            "InvalidXdataControl",
            t.offset,
            "XDATA control must be { or }",
          ),
        )
      }
    }
    match t.value {
      RealBits(b) => {
        let d = b.reinterpret_as_double()
        if d.is_nan() || d.is_inf() {
          result.push(
            diagnostic(
              "NonfiniteReal",
              t.offset,
              "nonfinite real preserved but not text-convertible",
              severity=Warning,
            ),
          )
        }
      }
      Text(b) => {
        if !self.binary && b.iter().any(v => v == 0 || v == 13) {
          result.push(
            diagnostic(
              "InvalidTextDelimiter",
              t.offset,
              "ASCII text contains NUL or embedded CR",
            ),
          )
        }
        if self.version >= "AC1021" {
          let valid = try {
            ignore(@utf8.decode(b))
            true
          } catch {
            _ => false
          }
          if !valid {
            result.push(
              diagnostic("InvalidUtf8", t.offset, "invalid UTF8 text"),
            )
          }
        }
      }
      Opaque(_) =>
        result.push(
          diagnostic(
            "UnknownGroup",
            t.offset,
            "unknown ASCII group retained; Binary conversion unavailable",
            severity=Warning,
          ),
        )
      _ => ()
    }
  }
  if section != "" || need_section {
    result.push(
      diagnostic(
        "UnclosedSection",
        self.original.length(),
        "SECTION lacks ENDSEC",
      ),
    )
  }
  if pending_table {
    result.push(
      diagnostic("UnclosedTable", self.original.length(), "TABLE lacks ENDTAB"),
    )
  }
  if xdepth != 0 {
    result.push(
      diagnostic(
        "UnbalancedXdata",
        self.original.length(),
        "XDATA list not closed",
      ),
    )
  }
  if !eof_seen {
    result.push(diagnostic("MissingEof", self.original.length(), "missing EOF"))
  }
  if !declared {
    result.push(
      diagnostic(
        "AssumedVersion",
        0,
        "ACADVER absent; profile inferred from wire width",
        severity=Warning,
      ),
    )
  }
  for pair in references {
    if !blocks.contains(block_name_key(pair.0)) {
      let name = @utf8.decode(pair.0) catch {
        _ => "bytes:" + @utf8.decode_lossy(hex_bytes(pair.0))
      }
      result.push(
        diagnostic("DanglingBlock", pair.1, "undefined block \{name}"),
      )
    }
  }
  result
}

///|
// Symbol identity must not collapse on a failed UTF8 decode. Fold only ASCII
// letters in the original bytes; unknown legacy codepages are never guessed.
fn block_name_key(name : Bytes) -> Bytes {
  Bytes::makei(name.length(), i => {
    let b = name[i]
    if b >= b'A' && b <= b'Z' {
      (b.to_int() + 32).to_byte()
    } else {
      b
    }
  })
}

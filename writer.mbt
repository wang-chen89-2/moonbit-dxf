///|
fn append_bytes(out : Array[Byte], b : Bytes) -> Unit {
  for v in b {
    out.push(v)
  }
}

///|
fn put_le(out : Array[Byte], v : Int64, n : Int32) -> Unit {
  for i in 0..<n {
    out.push((v >> (i * 8)).to_byte())
  }
}

///|
fn hex_bytes(b : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let digits : Bytes = b"0123456789ABCDEF"
  for v in b {
    out.push(digits[v.to_int() >> 4])
    out.push(digits[v.to_int() & 15])
  }
  Bytes::from_array(out)
}

///|
fn write_tag(tag : Tag, binary : Bool, width : Int32) -> Bytes raise DxfError {
  let out : Array[Byte] = []
  let t = group_type(tag.code)
  if binary {
    if t < 0 || tag.code == 999 {
      raise Unrepresentable(
        "unknown/comment group \{tag.code} cannot be Binary",
      )
    }
    if width == 1 {
      if tag.code >= 1000 {
        out.push(255)
        put_le(out, tag.code.to_int64(), 2)
      } else if tag.code > 254 {
        raise Unrepresentable("group code not encodable in R12")
      } else {
        out.push(tag.code.to_byte())
      }
    } else {
      put_le(out, tag.code.to_int64(), 2)
    }
  } else {
    append_bytes(out, @utf8.encode("\{tag.code}\n"))
  }
  let raw = match tag.value {
    Text(b) => {
      if t != 0 {
        raise Unrepresentable("text value does not match group code")
      }
      if b.iter().any(x => x == 0 || (!binary && (x == 10 || x == 13))) {
        raise Unrepresentable("text contains wire delimiter")
      }
      b
    }
    Opaque(b) => {
      if binary || t >= 0 {
        raise Unrepresentable("opaque tag cannot be typed/re-encoded")
      }
      if b.iter().any(x => x == 0 || x == 10 || x == 13) {
        raise Unrepresentable("opaque ASCII value contains wire delimiter")
      }
      b
    }
    Binary(b) => {
      if t != 3 || b.length() > 127 {
        raise Unrepresentable("invalid binary chunk/type")
      }
      if binary {
        out.push(b.length().to_byte())
        b
      } else {
        hex_bytes(b)
      }
    }
    Integer(v) => {
      if ![1, 2, 4, 16].contains(t) {
        raise Unrepresentable("integer type mismatch")
      }
      if (t == 1 && (v < 0L || v > 1L)) ||
        (t == 2 && (v < -32768L || v > 32767L)) ||
        (t == 4 && (v < -2147483648L || v > 2147483647L)) {
        raise Unrepresentable("integer out of wire range")
      }
      if binary {
        put_le(out, v, if t == 16 { 8 } else { t })
        b""
      } else {
        @utf8.encode(v.to_string())
      }
    }
    RealBits(bits) => {
      if t != 8 {
        raise Unrepresentable("real type mismatch")
      }
      if binary {
        put_le(out, bits, 8)
        b""
      } else {
        let d = bits.reinterpret_as_double()
        if d.is_nan() || d.is_inf() {
          raise Unrepresentable("nonfinite real cannot be text-converted")
        }
        // Preserve negative zero's sign through the ASCII representation.
        @utf8.encode(
          if bits == -9223372036854775808L {
            "-0.0"
          } else {
            d.to_string()
          },
        )
      }
    }
  }
  append_bytes(out, raw)
  if binary {
    if t == 0 {
      out.push(0)
    }
  } else {
    out.push(10)
  }
  Bytes::from_array(out)
}

///|
fn encode_tags(
  tags : Array[Tag],
  binary : Bool,
  version : String,
) -> Bytes raise DxfError {
  if !supported_version(version) {
    raise UnsupportedVersion(version)
  }
  let out : Array[Byte] = []
  if binary {
    append_bytes(out, binary_signature)
  }
  for t in tags {
    append_bytes(
      out,
      write_tag(t, binary, if old_version(version) { 1 } else { 2 }),
    )
  }
  Bytes::from_array(out)
}

///|
fn DxfDocument::require_convertible(self : DxfDocument) -> Unit raise DxfError {
  if !self.complete {
    raise IncompleteDocument
  }
  if !supported_version(self.version) {
    raise UnsupportedVersion(self.version)
  }
  if self.issues.any(d => d.code == "WireVersionMismatch") {
    raise Unrepresentable("wire/version mismatch")
  }
}

///|
/// Semantic encoding, not byte-preserving save. Unknown tails cannot be dropped.
pub fn DxfDocument::to_binary(self : DxfDocument) -> Bytes raise DxfError {
  self.require_convertible()
  encode_tags(self.items, true, self.version)
}

///|
/// Preserves encoded text bytes (including legacy codepages) across formats.
pub fn DxfDocument::to_ascii_bytes(self : DxfDocument) -> Bytes raise DxfError {
  self.require_convertible()
  encode_tags(self.items, false, self.version)
}

///|
/// String convenience API; legacy non-UTF8 text must use to_ascii_bytes.
pub fn DxfDocument::to_ascii(self : DxfDocument) -> String raise DxfError {
  utf8_string(self.to_ascii_bytes(), 0)
}

///|
/// Edit one known value in the original format; all other source spans unchanged.
/// Version/header edits must be done by an explicit whole-document migration.
pub fn DxfDocument::rewrite_value(
  self : DxfDocument,
  index : Int32,
  value : TagValue,
) -> Bytes raise DxfError {
  self.require_convertible()
  let replacement = self.checked_replacement(
    index,
    value,
    self.protected_values(),
  )
  let old = self.items[index]
  self.original[:old.offset].to_owned() +
  replacement +
  self.original[old.end_offset:].to_owned()
}

///|
pub(all) struct RepairResult {
  bytes : Bytes
  diagnostics : Array[Diagnostic]
  discarded_bytes : Int32
} derive(Debug)

///|
pub extend RepairResult with @debug.Debug::{to_repr}

///|
fn control(name : String) -> Tag {
  { code: 0, value: Text(@utf8.encode(name)), offset: 0, end_offset: 0, }
}

///|
/// Explicit repair only. Binary corruption is truncated at the last closed section.
pub fn DxfDocument::repair(self : DxfDocument) -> RepairResult raise DxfError {
  if self.mode != PermissiveRepair {
    raise Unrepresentable("repair requires PermissiveRepair mode")
  }
  if !supported_version(self.version) {
    raise UnsupportedVersion(self.version)
  }
  if self.issues.any(d => d.code == "WireVersionMismatch") {
    raise Unrepresentable("wire/version mismatch requires explicit migration")
  }
  let diagnostics = self.lint()
  for i, t in self.items {
    if t.code == 0 && t.text() == Some("EOF") && i + 1 < self.items.length() {
      raise Unrepresentable(
        "typed records after EOF require an explicit loss decision",
      )
    }
  }
  let tags : Array[Tag] = []
  let mut discarded_bytes = self.discarded
  let mut usable = self.items.length()
  if self.binary &&
    (!self.complete || diagnostics.any(d => d.code == "UnclosedSection")) {
    usable = 0
    let mut end = 22
    let mut opened = false
    let mut need_name = false
    for i, t in self.items {
      if t.code == 0 {
        let name = t.text().unwrap_or("")
        if name == "SECTION" {
          if opened {
            break
          }
          opened = true
          need_name = true
        } else if name == "ENDSEC" {
          if !opened || need_name {
            break
          }
          opened = false
          usable = i + 1
          end = t.end_offset
        } else if name == "EOF" || !opened || need_name {
          break
        }
      } else if need_name {
        if t.code != 2 || t.text().unwrap_or("") == "" {
          break
        }
        need_name = false
      } else if !opened {
        break
      }
    }
    if usable == 0 {
      raise Unrepresentable("no complete Binary section available")
    }
    discarded_bytes = self.original.length() - end
    diagnostics.push(
      diagnostic(
        "DiscardedTail",
        end,
        "Binary repair discards \{discarded_bytes} bytes; no resynchronization",
        severity=Warning,
      ),
    )
  } else if !self.complete {
    raise IncompleteDocument
  }
  let mut opened = false
  for i, t in self.items[:usable] {
    if t.code == 0 {
      let name = t.text().unwrap_or("")
      if name == "EOF" {
        if i + 1 < usable {
          raise Unrepresentable(
            "typed records after EOF require an explicit loss decision",
          )
        }
        break
      }
      if name == "SECTION" {
        if opened {
          tags.push(control("ENDSEC"))
        }
        opened = true
      } else if name == "ENDSEC" {
        opened = false
      }
    }
    match t.value {
      Text(b) => {
        if !self.binary && b.iter().any(v => v == 0 || v == 13) {
          let safe = Bytes::makei(b.length(), i => {
            if b[i] == 0 || b[i] == 13 {
              b'?'
            } else {
              b[i]
            }
          })
          let value = if self.version >= "AC1021" {
            @utf8.encode(@utf8.decode_lossy(safe))
          } else {
            safe
          }
          tags.push({ ..t, value: Text(value), })
          diagnostics.push(
            diagnostic(
              "ReplacedDelimiter",
              t.offset,
              "ASCII NUL/CR replaced in explicit repair",
              severity=Warning,
            ),
          )
          continue
        }
        if self.version >= "AC1021" {
          let valid = try {
            ignore(@utf8.decode(b))
            true
          } catch {
            _ => false
          }
          if !valid {
            tags.push({ ..t, value: Text(@utf8.encode(@utf8.decode_lossy(b))), })
            diagnostics.push(
              diagnostic(
                "ReplacedUtf8",
                t.offset,
                "invalid UTF8 replaced in explicit repair",
                severity=Warning,
              ),
            )
            continue
          }
        }
      }
      _ => ()
    }
    tags.push(t)
  }
  if opened {
    tags.push(control("ENDSEC"))
  }
  tags.push(control("EOF"))
  {
    bytes: encode_tags(tags, self.binary, self.version),
    diagnostics,
    discarded_bytes,
  }
}

///|
/// Lossless/lint save is exactly original_bytes; repair save is explicitly changed.
pub fn DxfDocument::save(self : DxfDocument) -> Bytes raise DxfError {
  if self.mode == PermissiveRepair {
    self.repair().bytes
  } else {
    self.original
  }
}

///|
/// Emit encoded tags incrementally. The callback must consume each chunk synchronously.
pub fn DxfDocument::write_to(
  self : DxfDocument,
  binary~ : Bool,
  sink : (Bytes) -> Unit raise,
) -> Unit raise {
  self.require_convertible()
  if binary {
    sink(binary_signature)
  }
  for t in self.items {
    sink(write_tag(t, binary, if old_version(self.version) { 1 } else { 2 }))
  }
}

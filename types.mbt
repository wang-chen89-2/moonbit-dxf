///|
pub(all) enum OperationMode {
  LosslessRoundTrip
  ReadOnlyLint
  PermissiveRepair
} derive(Eq, Debug)

///|
pub extend OperationMode with Eq::{equal, not_equal}

///|
pub extend OperationMode with @debug.Debug::{to_repr}

///|
pub(all) enum Severity {
  Warning
  Error
} derive(Eq, Debug)

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
pub(all) struct Diagnostic {
  code : String
  severity : Severity
  message : String
  offset : Int32
} derive(Debug)

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub(all) suberror DxfError {
  Invalid(offset~ : Int32, reason~ : String)
  UnsupportedVersion(String)
  IncompleteDocument
  Unrepresentable(String)
  ResourceLimit(String)
} derive(Debug)

///|
pub extend DxfError with @debug.Debug::{to_repr}

///|
/// Text stores the original encoded bytes; RealBits stores the IEEE payload.
pub(all) enum TagValue {
  Text(Bytes)
  Integer(Int64)
  RealBits(Int64)
  Binary(Bytes)
  Opaque(Bytes)
} derive(Eq, Debug)

///|
pub extend TagValue with Eq::{equal, not_equal}

///|
pub extend TagValue with @debug.Debug::{to_repr}

///|
pub(all) struct Tag {
  code : Int32
  value : TagValue
  offset : Int32
  end_offset : Int32
} derive(Eq, Debug)

///|
pub extend Tag with Eq::{equal, not_equal}

///|
pub extend Tag with @debug.Debug::{to_repr}

///|
pub fn Tag::text(self : Tag) -> String? {
  match self.value {
    Text(b) => Some(@utf8.decode(b)) catch { _ => None }
    _ => None
  }
}

///|
pub fn Tag::real(self : Tag) -> Double? {
  match self.value {
    RealBits(b) => Some(b.reinterpret_as_double())
    _ => None
  }
}

///|
pub fn Tag::integer(self : Tag) -> Int64? {
  match self.value {
    Integer(i) => Some(i)
    _ => None
  }
}

///|
pub(all) struct RawChunk {
  offset : Int32
  bytes : Bytes
} derive(Debug)

///|
pub extend RawChunk with @debug.Debug::{to_repr}

///|
pub struct DxfDocument {
  original : Bytes
  items : Array[Tag]
  mode : OperationMode
  binary : Bool
  width : Int32
  version : String
  complete : Bool
  tail : RawChunk?
  issues : Array[Diagnostic]
  discarded : Int32
}

///|
pub fn DxfDocument::original_bytes(self : DxfDocument) -> Bytes {
  self.original
}

///|
pub fn DxfDocument::tags(self : DxfDocument) -> Array[Tag] {
  self.items.copy()
}

///|
pub fn DxfDocument::diagnostics(self : DxfDocument) -> Array[Diagnostic] {
  self.issues.copy()
}

///|
pub fn DxfDocument::raw_tail(self : DxfDocument) -> RawChunk? {
  self.tail
}

///|
pub fn DxfDocument::is_complete(self : DxfDocument) -> Bool {
  self.complete
}

///|
pub fn DxfDocument::is_binary(self : DxfDocument) -> Bool {
  self.binary
}

///|
pub fn DxfDocument::acad_version(self : DxfDocument) -> String {
  self.version
}

///|
pub fn DxfDocument::operation_mode(self : DxfDocument) -> OperationMode {
  self.mode
}

///|
fn diagnostic(
  code : String,
  offset : Int32,
  message : String,
  severity~ : Severity = Error,
) -> Diagnostic {
  { code, severity, message, offset, }
}

///|
/// Group value wire type, including XDATA 1004's binary special case.
/// Unknown codes return -1; their Binary value length cannot be inferred.
pub fn group_type(c : Int32) -> Int32 {
  if (0 <= c && c <= 9) ||
    c == 100 ||
    c == 102 ||
    c == 105 ||
    (300 <= c && c <= 309) ||
    (320 <= c && c <= 369) ||
    (390 <= c && c <= 399) ||
    (410 <= c && c <= 419) ||
    (430 <= c && c <= 439) ||
    (470 <= c && c <= 481) ||
    c == 999 ||
    (1000 <= c && c <= 1009 && c != 1004) {
    0
  } else if (10 <= c && c <= 59) ||
    (110 <= c && c <= 149) ||
    (210 <= c && c <= 239) ||
    (460 <= c && c <= 469) ||
    (1010 <= c && c <= 1059) {
    8
  } else if (60 <= c && c <= 79) ||
    (170 <= c && c <= 179) ||
    (270 <= c && c <= 289) ||
    (370 <= c && c <= 389) ||
    (400 <= c && c <= 409) ||
    (1060 <= c && c <= 1070) {
    2
  } else if (90 <= c && c <= 99) ||
    (420 <= c && c <= 429) ||
    (440 <= c && c <= 459) ||
    c == 1071 {
    4
  } else if 160 <= c && c <= 169 {
    16
  } else if 290 <= c && c <= 299 {
    1
  } else if (310 <= c && c <= 319) || c == 1004 {
    3
  } else {
    -1
  }
}

///|
fn slice(data : Array[Byte], start : Int32, end : Int32) -> Bytes {
  Bytes::from_array(data[start:end])
}

///|
fn signed_le(data : Array[Byte], start : Int32, n : Int32) -> Int64 {
  let mut v = 0L
  for i in 0..<n {
    v = v | (data[start + i].to_int64() << (i * 8))
  }
  if n < 8 && data[start + n - 1].to_int() >= 128 {
    v - (1L << (n * 8))
  } else {
    v
  }
}

///|
fn utf8_string(b : Bytes, offset : Int32) -> String raise DxfError {
  @utf8.decode(b) catch {
    _ => raise Invalid(offset~, reason="invalid UTF-8")
  }
}

///|
fn ascii_value(
  code : Int32,
  raw : Bytes,
  offset : Int32,
) -> TagValue raise DxfError {
  let t = group_type(code)
  if t == 0 {
    return Text(raw)
  }
  if t < 0 {
    return Opaque(raw)
  }
  let text = utf8_string(raw, offset).trim().to_owned()
  if t == 3 {
    if text.length() % 2 != 0 {
      raise Invalid(offset~, reason="odd hexadecimal chunk")
    }
    let bytes : Array[Byte] = []
    for i in 0..<(text.length() / 2) {
      let h = hex_digit(text[i * 2].to_int())
      let l = hex_digit(text[i * 2 + 1].to_int())
      if h < 0 || l < 0 {
        raise Invalid(offset~, reason="invalid hexadecimal chunk")
      }
      bytes.push((h * 16 + l).to_byte())
    }
    if bytes.length() > 127 {
      raise Invalid(offset~, reason="binary chunk exceeds 127 bytes")
    }
    return Binary(Bytes::from_array(bytes))
  }
  if t == 8 {
    let d = @string.parse_double(text) catch {
      _ => raise Invalid(offset~, reason="invalid real")
    }
    return RealBits(d.reinterpret_as_int64())
  }
  let v = parse_integer_text(text, offset)
  if (t == 1 && (v < 0L || v > 1L)) ||
    (t == 2 && (v < -32768L || v > 32767L)) ||
    (t == 4 && (v < -2147483648L || v > 2147483647L)) {
    raise Invalid(offset~, reason="integer out of group-code range")
  }
  Integer(v)
}

///|
fn hex_digit(c : Int32) -> Int32 {
  if 48 <= c && c <= 57 {
    c - 48
  } else if 65 <= c && c <= 70 {
    c - 55
  } else if 97 <= c && c <= 102 {
    c - 87
  } else {
    -1
  }
}

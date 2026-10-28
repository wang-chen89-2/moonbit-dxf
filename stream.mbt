///|
let binary_signature : Bytes = b"AutoCAD Binary DXF\r\n\x1a\x00"

///|
priv enum Step {
  Next(Tag, Int32)
  NeedMore
  Broken(String)
}

///|
pub struct DxfDecoder {
  data : Array[Byte]
  items : Array[Tag]
  issues : Array[Diagnostic]
  mode : OperationMode
  max_bytes : Int32
  max_tags : Int32
  max_tag_bytes : Int32
  mut pos : Int32
  mut wire : Int32
  mut stopped : Bool
  mut finished : Bool
  mut discarded : Int32
}

///|
pub fn DxfDecoder::new(
  mode~ : OperationMode = LosslessRoundTrip,
  max_bytes~ : Int32 = 67108864,
  max_tags~ : Int32 = 1000000,
  max_tag_bytes~ : Int32 = 1048576,
) -> DxfDecoder {
  {
    data: [],
    items: [],
    issues: [],
    mode,
    max_bytes,
    max_tags,
    max_tag_bytes,
    pos: 0,
    wire: -1,
    stopped: false,
    finished: false,
    discarded: 0,
  }
}

///|
pub fn DxfDecoder::feed(
  self : DxfDecoder,
  chunk : Bytes,
) -> Array[Tag] raise DxfError {
  if self.finished {
    raise Invalid(offset=self.pos, reason="feed after finish")
  }
  if chunk.length() > self.max_bytes - self.data.length() {
    raise ResourceLimit("max_bytes")
  }
  for b in chunk {
    self.data.push(b)
  }
  self.drain(false)
}

///|
fn DxfDecoder::drain(
  self : DxfDecoder,
  at_end : Bool,
) -> Array[Tag] raise DxfError {
  let emitted : Array[Tag] = []
  if self.stopped {
    return emitted
  }
  let n = self.data.length()
  if self.wire < 0 {
    let mut prefix = true
    for i in 0..<n.min(22) {
      if self.data[i] != binary_signature[i] {
        prefix = false
        break
      }
    }
    if prefix && n < 24 {
      if !at_end {
        return emitted
      }
      self.issues.push(
        diagnostic("TruncatedSignature", 0, "incomplete Binary header"),
      )
      self.stopped = true
      return emitted
    }
    if prefix {
      self.pos = 22
      self.wire = if self.data[23] == 0 { 2 } else { 1 }
    } else {
      self.wire = 0
    }
  }
  while self.pos < n {
    if self.wire == 0 &&
      self.items
      .last()
      .map(t => t.code == 0 && t.text() == Some("EOF"))
      .unwrap_or(false) &&
      self.data[self.pos:]
      .iter()
      .all(b => b == 10 || b == 13 || b == 32 || b == 9) {
      if at_end {
        self.pos = n
      }
      break
    }
    if self.wire == 0 &&
      at_end &&
      self.data[self.pos:]
      .iter()
      .all(b => b == 10 || b == 13 || b == 32 || b == 9) {
      self.pos = n
      break
    }
    if self.items.length() >= self.max_tags {
      raise ResourceLimit("max_tags")
    }
    let step = if self.wire == 0 {
      parse_ascii(self.data, self.pos, at_end, self.max_tag_bytes)
    } else {
      parse_binary(self.data, self.pos, self.wire)
    }
    match step {
      Next(t, end) => {
        if end - self.pos > self.max_tag_bytes {
          raise ResourceLimit("max_tag_bytes")
        }
        self.pos = end
        self.items.push(t)
        emitted.push(t)
      }
      NeedMore => {
        if n - self.pos > self.max_tag_bytes {
          raise ResourceLimit("max_tag_bytes")
        }
        if at_end {
          self.issues.push(
            diagnostic("TruncatedTag", self.pos, "unfinished group/value pair"),
          )
          self.stopped = true
        }
        break
      }
      Broken(reason) => {
        self.issues.push(diagnostic("InvalidTag", self.pos, reason))
        if self.mode == PermissiveRepair && self.wire == 0 {
          // ASCII physical line-pair boundary only, never Binary byte scanning.
          match line_end(self.data, self.pos, at_end) {
            Some((_, next)) =>
              match line_end(self.data, next, at_end) {
                Some((_, end)) => {
                  self.discarded += end - self.pos
                  self.issues.push(
                    diagnostic(
                      "DiscardedAsciiPair",
                      self.pos,
                      "explicit repair skipped \{end - self.pos} bytes",
                      severity=Warning,
                    ),
                  )
                  self.pos = end
                  continue
                }
                None => ()
              }
            None => ()
          }
        }
        self.stopped = true
        break
      }
    }
  }
  emitted
}

///|
fn line_end(
  data : Array[Byte],
  start : Int32,
  at_end : Bool,
) -> (Int32, Int32)? {
  for i in start..<data.length() {
    if data[i] == 10 {
      return Some(
        (if i > start && data[i - 1] == 13 { i - 1 } else { i }, i + 1),
      )
    }
  }
  if at_end && start < data.length() {
    Some((data.length(), data.length()))
  } else {
    None
  }
}

///|
fn parse_ascii(
  data : Array[Byte],
  start : Int32,
  at_end : Bool,
  max_tag_bytes : Int32,
) -> Step raise DxfError {
  guard line_end(data, start, at_end) is Some((code_end, value_start)) else {
    return NeedMore
  }
  guard line_end(data, value_start, at_end) is Some((value_end, end)) else {
    return NeedMore
  }
  // Enforce the physical pair budget before decoding, including broken pairs
  // which PermissiveRepair may otherwise skip without reaching Next.
  if end - start > max_tag_bytes {
    raise ResourceLimit("max_tag_bytes")
  }
  let code = @string.parse_int(
    @utf8.decode(slice(data, start, code_end)).trim(),
    base=10,
  ) catch {
    _ => return Broken("invalid ASCII group code")
  }
  if code < 0 || code > 1071 {
    return Broken("group code outside DXF domain")
  }
  let value = ascii_value(code, slice(data, value_start, value_end), start) catch {
    e => return Broken("\{Repr(e)}")
  }
  Next({ code, value, offset: start, end_offset: end, }, end)
}

///|
fn parse_binary(data : Array[Byte], start : Int32, width : Int32) -> Step {
  let n = data.length()
  if n - start < width {
    return NeedMore
  }
  let mut pos = start + width
  let mut code = data[start].to_int()
  if width == 2 {
    code = code | (data[start + 1].to_int() << 8)
  } else if code == 255 {
    if n - pos < 2 {
      return NeedMore
    }
    code = data[pos].to_int() | (data[pos + 1].to_int() << 8)
    pos += 2
  }
  let t = group_type(code)
  if t < 0 || code == 999 {
    return Broken("unknown or forbidden Binary group code \{code}")
  }
  let value : TagValue = if t == 0 {
    let begin = pos
    while pos < n && data[pos] != 0 {
      pos += 1
    }
    if pos == n {
      return NeedMore
    }
    let b = slice(data, begin, pos)
    pos += 1
    Text(b)
  } else if t == 3 {
    if pos >= n {
      return NeedMore
    }
    let len = data[pos].to_int()
    pos += 1
    if len > 127 {
      return Broken("binary chunk exceeds 127 bytes")
    }
    if n - pos < len {
      return NeedMore
    }
    let b = slice(data, pos, pos + len)
    pos += len
    Binary(b)
  } else {
    let len = if t == 16 || t == 8 { 8 } else { t }
    if n - pos < len {
      return NeedMore
    }
    let v = if len == 1 {
      data[pos].to_int64()
    } else {
      signed_le(data, pos, len)
    }
    pos += len
    if t == 1 && v > 1L {
      return Broken("invalid boolean")
    }
    if t == 8 {
      RealBits(v)
    } else {
      Integer(v)
    }
  }
  Next({ code, value, offset: start, end_offset: pos, }, pos)
}

///|
pub fn DxfDecoder::finish(self : DxfDecoder) -> DxfDocument raise DxfError {
  if self.finished {
    raise Invalid(offset=self.pos, reason="finish called twice")
  }
  ignore(self.drain(true))
  self.finished = true
  let original = Bytes::from_array(self.data)
  let version = declared_version(
    self.items,
    if self.wire == 1 {
      "AC1009"
    } else {
      "AC1032"
    },
  )
  let issues = self.issues.copy()
  if !supported_version(version) {
    issues.push(
      diagnostic(
        "UnsupportedVersion",
        0,
        "unsupported/ambiguous version \{version}",
      ),
    )
  }
  if self.wire > 0 &&
    supported_version(version) &&
    (if old_version(version) { 1 } else { 2 }) != self.wire {
    issues.push(
      diagnostic(
        "WireVersionMismatch", 22, "group-code width conflicts with ACADVER",
      ),
    )
  }
  let tail = if self.stopped {
    Some({ offset: self.pos, bytes: original[self.pos:].to_owned(), })
  } else {
    None
  }
  let doc : DxfDocument = {
    original,
    items: self.items.copy(),
    mode: self.mode,
    binary: self.wire > 0,
    width: self.wire,
    version,
    complete: !self.stopped,
    tail,
    issues,
    discarded: self.discarded,
  }
  doc
}

///|
fn declared_version(tags : Array[Tag], fallback : String) -> String {
  match header_version_tag(tags) {
    Some(t) => t.text().unwrap_or(fallback)
    None => fallback
  }
}

///|
fn header_version_tag(tags : Array[Tag]) -> Tag? {
  let mut pending_section = false
  let mut in_header = false
  let mut pending_version = false
  for t in tags {
    if t.code == 999 {
      continue
    }
    if t.code == 0 {
      pending_section = t.text() == Some("SECTION")
      in_header = false
      pending_version = false
      continue
    }
    if pending_section {
      in_header = t.code == 2 && t.text() == Some("HEADER")
      pending_section = false
      continue
    }
    if in_header {
      if pending_version {
        if t.code == 1 {
          return Some(t)
        }
        pending_version = false
      }
      if t.code == 9 && t.text() == Some("$ACADVER") {
        pending_version = true
      }
    }
  }
  None
}

///|
fn old_version(v : String) -> Bool {
  v == "AC1006" || v == "AC1009"
}

///|
fn supported_version(v : String) -> Bool {
  [
    "AC1006", "AC1009", "AC1014", "AC1015", "AC1018", "AC1021", "AC1024", "AC1027",
    "AC1032",
  ].contains(v)
}

///|
// Result is intentional: the public import boundary exposes failure as data.
#warnings("-78")
pub fn DxfDocument::from_bytes(
  bytes : Bytes,
  mode~ : OperationMode,
) -> Result[DxfDocument, DxfError] {
  try {
    let d = DxfDecoder::new(mode~)
    ignore(d.feed(bytes))
    Ok(d.finish())
  } catch {
    e => Err(e)
  }
}

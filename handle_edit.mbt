///|
fn canonical_handle(text : String) -> String? {
  if text.length() == 0 || text.length() > 16 {
    return None
  }
  let digits : Array[Char] = []
  let mut started = false
  for c in text.to_upper() {
    if !((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F')) {
      return None
    }
    if c != '0' || started {
      digits.push(c)
      started = true
    }
  }
  Some(if digits.is_empty() { "0" } else { String::from_array(digits) })
}

///|
/// Resolve one record and capture an exact existing value for a batch plan.
/// Lookup skips 102 application groups. Repeated ordinary/XDATA codes use a
/// zero-based occurrence; final wire/structural approval is rewrite_values.
pub fn DxfDocument::value_edit_by_handle(
  self : DxfDocument,
  handle : String,
  code : Int32,
  value : TagValue,
  occurrence~ : Int32 = 0,
) -> ValueEdit raise DxfError {
  self.require_convertible()
  guard canonical_handle(handle) is Some(key) else {
    raise Invalid(
      offset=0,
      reason="handle must contain 1 to 16 hexadecimal digits",
    )
  }
  if occurrence < 0 {
    raise Invalid(offset=0, reason="negative field occurrence")
  }
  let mut matched_start = -1
  let mut matched_end = 0
  let mut start = 0
  while start < self.items.length() {
    if self.items[start].code != 0 {
      start += 1
      continue
    }
    let mut end = start + 1
    while end < self.items.length() && self.items[end].code != 0 {
      end += 1
    }
    let kind = self.items[start].text().unwrap_or("")
    if !["SECTION", "ENDSEC", "EOF", "ENDTAB"].contains(kind) {
      let handle_code = if kind == "DIMSTYLE" { 105 } else { 5 }
      let mut app_depth = 0
      for i in (start + 1)..<end {
        let tag = self.items[i]
        let next = appdata_depth_after(app_depth, tag)
        let in_appdata = app_depth > 0 || next > 0
        app_depth = next
        if in_appdata {
          continue
        }
        // The owning handle is common data, before subclass/XDATA fields.
        if tag.code == 100 || tag.code == 1001 {
          break
        }
        if tag.code == handle_code {
          if tag.text().map(canonical_handle).unwrap_or(None) == Some(key) {
            if matched_start >= 0 {
              raise Invalid(offset=tag.offset, reason="ambiguous record handle")
            }
            matched_start = start
            matched_end = end
          }
          break
        }
      }
    }
    start = end
  }
  if matched_start < 0 {
    raise Invalid(offset=0, reason="record handle not found")
  }
  let mut app_depth = 0
  let mut seen = 0
  for index in matched_start..<matched_end {
    let tag = self.items[index]
    let next = appdata_depth_after(app_depth, tag)
    let in_appdata = app_depth > 0 || next > 0
    app_depth = next
    if !in_appdata && tag.code == code {
      if seen == occurrence {
        return { index, expected_code: tag.code, expected: tag.value, value, }
      }
      seen += 1
    }
  }
  raise Invalid(
    offset=self.items[matched_start].offset,
    reason="field occurrence not found",
  )
}

///|
/// Capture a direct field from one uniquely named top-level 102 group.
/// Application names match exact UTF8 bytes; child groups are not searched.
/// This only selects a ValueEdit; rewrite_values still approves the rewrite.
pub fn DxfDocument::value_edit_in_appdata(
  self : DxfDocument,
  handle : String,
  application : String,
  code : Int32,
  value : TagValue,
  occurrence~ : Int32 = 0,
) -> ValueEdit raise DxfError {
  let name = @utf8.encode(application)
  if name.is_empty() ||
    name.iter().any(b => b == 0 || b == 10 || b == 13 || b == 123 || b == 125) {
    raise Invalid(offset=0, reason="invalid application group name")
  }
  if occurrence < 0 || code == 0 || code == 102 {
    raise Invalid(offset=0, reason="invalid application field selector")
  }
  // Existing handle lookup may capture code0 without approving a rewrite.
  // Use that non-writing result only to locate the owning record.
  let start = self.value_edit_by_handle(handle, 0, Text(b"")).index
  let mut end = start + 1
  while end < self.items.length() && self.items[end].code != 0 {
    end += 1
  }
  let opening = Text(b"{" + name)
  let closing = Text(name + b"}")
  let mut depth = 0
  let mut active = false
  let mut group_start = -1
  let mut group_end = -1
  for i in (start + 1)..<end {
    let tag = self.items[i]
    let next = appdata_depth_after(depth, tag)
    if depth == 0 && next == 1 && tag.value == opening {
      if group_start >= 0 {
        raise Invalid(offset=tag.offset, reason="ambiguous application group")
      }
      group_start = i + 1
      active = true
    }
    if active && depth == 1 && next == 0 {
      if tag.value != Text(b"}") && tag.value != closing {
        raise Invalid(
          offset=tag.offset,
          reason="application group close mismatch",
        )
      }
      group_end = i
      active = false
    }
    depth = next
  }
  if group_start < 0 {
    raise Invalid(
      offset=self.items[start].offset,
      reason="application group not found",
    )
  }
  if group_end < 0 {
    raise Invalid(
      offset=self.items[start].offset,
      reason="application group not closed",
    )
  }
  depth = 0
  let mut seen = 0
  for index in group_start..<group_end {
    let tag = self.items[index]
    let next = appdata_depth_after(depth, tag)
    let in_child = depth > 0 || next > 0
    depth = next
    if !in_child && tag.code != 102 && tag.code == code {
      if seen == occurrence {
        return { index, expected_code: tag.code, expected: tag.value, value, }
      }
      seen += 1
    }
  }
  raise Invalid(
    offset=self.items[group_start - 1].offset,
    reason="application field occurrence not found",
  )
}

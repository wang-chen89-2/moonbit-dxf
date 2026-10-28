///|
/// A precondition and replacement, addressed in the original ordered tag array.
pub(all) struct ValueEdit {
  index : Int32
  expected_code : Int32
  expected : TagValue
  value : TagValue
}

///|
/// Source offsets remain in the original file even when replacements differ in size.
pub(all) struct ValueChange {
  index : Int32
  code : Int32
  offset : Int32
  end_offset : Int32
  before : Bytes
  after : Bytes
}

///|
pub(all) struct RewriteResult {
  bytes : Bytes
  changes : Array[ValueChange]
}

///|
fn DxfDocument::protected_values(self : DxfDocument) -> Array[Bool] {
  let locked_flags = Array::make(self.items.length(), false)
  let version_offset = header_version_tag(self.items).map(t => t.offset)
  let mut record = ""
  let mut first_name = true
  let mut app_depth = 0
  for i, tag in self.items {
    if tag.code == 0 {
      record = tag.text().unwrap_or("")
      first_name = true
      locked_flags[i] = true
      app_depth = 0
      continue
    }
    let next = appdata_depth_after(app_depth, tag)
    let in_appdata = app_depth > 0 || next > 0
    app_depth = next
    if in_appdata {
      continue
    }
    if tag.code == 9 {
      locked_flags[i] = true
    } else if tag.code == 2 {
      if first_name && (record == "SECTION" || record == "TABLE") {
        locked_flags[i] = true
      }
      first_name = false
    }
    if version_offset == Some(tag.offset) {
      locked_flags[i] = true
    }
  }
  locked_flags
}

///|
fn DxfDocument::checked_replacement(
  self : DxfDocument,
  index : Int32,
  value : TagValue,
  locked_flags : Array[Bool],
) -> Bytes raise DxfError {
  guard self.items.get(index) is Some(old) else {
    raise Invalid(offset=index, reason="tag index out of range")
  }
  if locked_flags[index] {
    raise Unrepresentable("structural/version edit requires document migration")
  }
  write_tag({ ..old, value, }, self.binary, self.width)
}

///|
/// Pure, all-or-nothing multi-value rewrite of original byte spans.
/// Preconditions compare selected group codes and typed values, not the whole file.
pub fn DxfDocument::rewrite_values(
  self : DxfDocument,
  edits : Array[ValueEdit],
) -> RewriteResult raise DxfError {
  if edits.is_empty() {
    return { bytes: self.original, changes: [], }
  }
  self.require_convertible()
  let ordered = edits.copy()
  // Range validation precedes sorting so index subtraction cannot overflow.
  for edit in ordered {
    if edit.index < 0 || edit.index >= self.items.length() {
      raise Invalid(offset=edit.index, reason="tag index out of range")
    }
  }
  ordered.sort_by((a, b) => a.index - b.index)
  let locked_flags = self.protected_values()
  let changes : Array[ValueChange] = []
  let mut last_index = -1
  for edit in ordered {
    let old = self.items[edit.index]
    if edit.index == last_index {
      raise Invalid(offset=old.offset, reason="duplicate edit index")
    }
    if old.code != edit.expected_code || old.value != edit.expected {
      raise Invalid(offset=old.offset, reason="edit precondition failed")
    }
    let replacement = self.checked_replacement(
      edit.index,
      edit.value,
      locked_flags,
    )
    changes.push({
      index: edit.index,
      code: old.code,
      offset: old.offset,
      end_offset: old.end_offset,
      before: self.original[old.offset:old.end_offset].to_owned(),
      after: replacement,
    })
    last_index = edit.index
  }
  // Only after every edit is validated do we assemble the output, once.
  let output : Array[Byte] = []
  let mut cursor = 0
  for change in changes {
    append_bytes(output, self.original[cursor:change.offset].to_owned())
    append_bytes(output, change.after)
    cursor = change.end_offset
  }
  append_bytes(output, self.original[cursor:].to_owned())
  { bytes: Bytes::from_array(output), changes, }
}

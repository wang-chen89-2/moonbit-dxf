///|
/// One physical code-0 tag run in the original source. End indices are exclusive.
/// Raw handle candidates can be missing, invalid or duplicated; they grant no
/// edit authority. Linked records and reference closures are not assembled.
pub struct RecordSpan {
  ordinal : Int32
  start_tag : Int32
  end_tag : Int32
  kind : Bytes
  handle : Bytes?
  offset : Int32
  end_offset : Int32
}

///|
/// Inventory complete typed records without requiring owning handles. Leading
/// tags before code0 and trailing non-tag bytes remain outside the returned runs.
pub fn DxfDocument::record_spans(
  self : DxfDocument,
) -> Array[RecordSpan] raise DxfError {
  if self.mode == PermissiveRepair {
    raise Unrepresentable("record inventory requires a non-repair mode")
  }
  self.require_convertible()
  let spans : Array[RecordSpan] = []
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
    guard self.items[start].value is Text(kind) else {
      raise Unrepresentable("record marker is not text")
    }
    let handle = match record_handle_index(self.items, start, end) {
      Some(index) =>
        match self.items[index].value {
          Text(raw) => Some(raw)
          _ => None
        }
      None => None
    }
    let end_offset = if end < self.items.length() {
      self.items[end].offset
    } else {
      self.items[end - 1].end_offset
    }
    spans.push({
      ordinal: spans.length(),
      start_tag: start,
      end_tag: end,
      kind,
      handle,
      offset: self.items[start].offset,
      end_offset,
    })
    start = end
  }
  spans
}

///|
/// Return one physical record in its exact original wire representation.
/// The owning public handle follows value_edit_by_handle's lookup policy.
/// Linked records/references are not assembled. Repair-mode or unresolved
/// input cannot supply a verified original-record attachment through this API.
pub fn DxfDocument::record_by_handle(
  self : DxfDocument,
  handle : String,
) -> RawChunk raise DxfError {
  if self.mode == PermissiveRepair {
    raise Unrepresentable("record extraction requires a non-repair mode")
  }
  // A code-0 lookup captures the record marker without approving an edit.
  let start = self.value_edit_by_handle(handle, 0, Text(b"")).index
  let mut end = start + 1
  while end < self.items.length() && self.items[end].code != 0 {
    end += 1
  }
  let offset = self.items[start].offset
  let end_offset = if end < self.items.length() {
    self.items[end].offset
  } else {
    self.items[end - 1].end_offset
  }
  { offset, bytes: self.original[offset:end_offset].to_owned(), }
}

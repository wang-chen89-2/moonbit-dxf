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

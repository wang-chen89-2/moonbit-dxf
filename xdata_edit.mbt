///|
// Resolve the complete APPID scope before returning any selected payload.
fn DxfDocument::xdata_indices(
  self : DxfDocument,
  handle : String,
  application : String,
) -> Array[Int32] raise DxfError {
  let name = @utf8.encode(application)
  if name.is_empty() ||
    name.length() > 31 ||
    name.iter().any(b => b == 0 || b == 10 || b == 13) {
    raise Invalid(offset=0, reason="invalid XDATA application name")
  }
  let start = self.value_edit_by_handle(handle, 0, Text(b"")).index
  let mut end = start + 1
  while end < self.items.length() && self.items[end].code != 0 {
    end += 1
  }
  let mut private_depth = 0
  let mut group_start = -1
  let mut group_end = end
  for i in (start + 1)..<end {
    let tag = self.items[i]
    let next = appdata_depth_after(private_depth, tag)
    let private = private_depth > 0 || next > 0
    private_depth = next
    if !private && tag.code == 1001 {
      if group_start >= 0 && group_end == end {
        group_end = i
      }
      if tag.value == Text(name) {
        if group_start >= 0 {
          raise Invalid(offset=tag.offset, reason="ambiguous XDATA application")
        }
        group_start = i + 1
      }
    }
  }
  if group_start < 0 {
    raise Invalid(
      offset=self.items[start].offset,
      reason="XDATA application not found",
    )
  }
  private_depth = 0
  let mut list_depth = 0
  let indices : Array[Int32] = []
  for index in group_start..<group_end {
    let tag = self.items[index]
    let next = appdata_depth_after(private_depth, tag)
    let private = private_depth > 0 || next > 0
    private_depth = next
    if private || tag.code == 102 {
      continue
    }
    if tag.code < 1000 || tag.code > 1071 {
      raise Invalid(
        offset=tag.offset,
        reason="non-XDATA field in application group",
      )
    }
    if tag.code == 1002 {
      match tag.value {
        Text(b"{") => list_depth += 1
        Text(b"}") => {
          if list_depth == 0 {
            raise Invalid(
              offset=tag.offset,
              reason="unexpected XDATA list close",
            )
          }
          list_depth -= 1
        }
        _ =>
          raise Invalid(offset=tag.offset, reason="invalid XDATA list control")
      }
    }
    indices.push(index)
  }
  let offset = self.items[group_start - 1].offset
  if private_depth != 0 {
    raise Invalid(
      offset~,
      reason="XDATA application contains an unclosed private group",
    )
  }
  if list_depth != 0 {
    raise Invalid(offset~, reason="XDATA list not closed")
  }
  indices
}

///|
/// Read one unique public 1001 application's typed payload, including balanced
/// 1002 controls, excluding its marker and private 102 groups. Names match exact
/// UTF8 bytes. This does not validate an application schema or APPID registry.
pub fn DxfDocument::xdata_by_appid(
  self : DxfDocument,
  handle : String,
  application : String,
) -> Array[Tag] raise DxfError {
  self.xdata_indices(handle, application).map(index => self.items[index])
}

///|
/// Capture one existing payload value in a unique APPID scope. Occurrence counts
/// this code in source order, including nested 1002 lists; structural markers
/// cannot be selected. rewrite_values still approves the replacement and batch.
pub fn DxfDocument::value_edit_in_xdata(
  self : DxfDocument,
  handle : String,
  application : String,
  code : Int32,
  value : TagValue,
  occurrence~ : Int32 = 0,
) -> ValueEdit raise DxfError {
  if occurrence < 0 ||
    code < 1000 ||
    code > 1071 ||
    code == 1001 ||
    code == 1002 {
    raise Invalid(offset=0, reason="invalid XDATA field selector")
  }
  let indices = self.xdata_indices(handle, application)
  let mut seen = 0
  for index in indices {
    let tag = self.items[index]
    if tag.code == code {
      if seen == occurrence {
        return { index, expected_code: code, expected: tag.value, value, }
      }
      seen += 1
    }
  }
  raise Invalid(offset=0, reason="XDATA field occurrence not found")
}

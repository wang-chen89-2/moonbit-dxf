///|
// Control syntax is ASCII even when the surrounding text uses a legacy page.
// Closing groups may use either "}" or the application-name suffix "APP}".
fn appdata_depth_after(depth : Int32, tag : Tag) -> Int32 {
  if tag.code == 0 {
    return 0
  }
  if tag.code == 102 && tag.value is Text(raw) && raw.length() > 0 {
    if raw[0] == b'{' {
      return depth + 1
    }
    if raw[raw.length() - 1] == b'}' && depth > 0 {
      return depth - 1
    }
  }
  depth
}

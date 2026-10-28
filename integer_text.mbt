///|
/// DXF can spell integer values in scientific decimal notation (e.g. XDATA
/// 1071 in Autodesk's example). Normalize decimal digits exactly, never via
/// Double: that would round Int64 values near 2^63 before the range check.
fn parse_integer_text(text : String, offset : Int32) -> Int64 raise DxfError {
  try {
    return @string.parse_int64(text, base=10)
  } catch {
    _ => ()
  }
  let chars : Array[Char] = []
  for c in text {
    chars.push(c)
  }
  let mut pos = 0
  let mut negative = false
  if chars.get(pos) == Some('-') || chars.get(pos) == Some('+') {
    negative = chars[pos] == '-'
    pos += 1
  }
  let digits : Array[Char] = []
  let mut fraction = 0
  let mut point = false
  while pos < chars.length() && chars[pos] != 'e' && chars[pos] != 'E' {
    let c = chars[pos]
    if c == '.' && !point {
      point = true
    } else if c >= '0' && c <= '9' {
      digits.push(c)
      if point {
        fraction += 1
      }
    } else {
      raise Invalid(offset~, reason="invalid integer decimal syntax")
    }
    pos += 1
  }
  if digits.is_empty() {
    raise Invalid(offset~, reason="missing integer digits")
  }
  let mut exponent = 0
  let mut exponent_negative = false
  if pos < chars.length() {
    pos += 1
    if chars.get(pos) == Some('-') || chars.get(pos) == Some('+') {
      exponent_negative = chars[pos] == '-'
      pos += 1
    }
    if pos == chars.length() {
      raise Invalid(offset~, reason="missing integer exponent")
    }
    // Saturating at input length + 20 is sufficient to determine exact Int64
    // representability and avoids overflow/huge allocations for large exponents.
    let bound = chars.length() + 20
    while pos < chars.length() {
      let c = chars[pos]
      if c < '0' || c > '9' {
        raise Invalid(offset~, reason="invalid integer exponent")
      }
      if exponent < bound {
        exponent = (exponent * 10 + c.to_int() - 48).min(bound)
      }
      pos += 1
    }
  }
  let mut first = 0
  while first < digits.length() && digits[first] == '0' {
    first += 1
  }
  if first == digits.length() {
    return 0L
  }
  let mut scale = (if exponent_negative { -exponent } else { exponent }) -
    fraction
  let mut last = digits.length()
  if scale < 0 {
    let remove = -scale
    if remove > last - first {
      raise Invalid(offset~, reason="fractional integer")
    }
    for i in (last - remove)..<last {
      if digits[i] != '0' {
        raise Invalid(offset~, reason="fractional integer")
      }
    }
    last -= remove
    scale = 0
  }
  if last - first + scale > 19 {
    raise Invalid(offset~, reason="integer exceeds Int64")
  }
  let canonical : Array[Char] = []
  if negative {
    canonical.push('-')
  }
  for i in first..<last {
    canonical.push(digits[i])
  }
  for _ in 0..<scale {
    canonical.push('0')
  }
  @string.parse_int64(String::from_array(canonical), base=10) catch {
    _ => raise Invalid(offset~, reason="integer exceeds Int64")
  }
}

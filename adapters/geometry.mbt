///|
pub struct DxfkitSink {
  data : Array[Byte]
}

///|
pub fn DxfkitSink::new() -> DxfkitSink {
  { data: [], }
}

///|
pub impl @dxf.DxfGeometrySink for DxfkitSink with fn write_ascii(self, chunk) {
  for b in chunk {
    self.data.push(b)
  }
}

///|
pub extend DxfkitSink with @dxf.DxfGeometrySink::{write_ascii}

///|
/// Uses the actual published 0.1.1 record-to-drawing API.
pub fn DxfkitSink::drawing(self : DxfkitSink) -> @dxfkit.Drawing {
  @dxfkit.build_drawing(@dxfkit.scan_tags(Bytes::from_array(self.data)))
}

///|
pub struct GeometrySink {
  data : Array[Byte]
  records : Array[Bytes]
  mut pending_section : Bool
  mut in_entities : Bool
  mut supported_record : Bool
}

///|
pub fn GeometrySink::new() -> GeometrySink {
  {
    data: [],
    records: [],
    pending_section: false,
    in_entities: false,
    supported_record: false,
  }
}

///|
fn classic_polyline_pending(data : Array[Byte]) -> Bool {
  let prefix = b"0\nPOLYLINE\n"
  if data.length() < prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if data[i] != prefix[i] {
      return false
    }
  }
  true
}

///|
pub impl @dxf.DxfGeometrySink for GeometrySink with fn write_ascii(self, chunk) {
  // pump_geometry delivers one complete ASCII tag per callback. Project the
  // ENTITIES section: this upstream reader must not see BLOCKS' local geometry.
  if chunk.has_prefix(b"999\n") {
    return
  }
  if chunk.has_prefix(b"0\n") && self.data.length() > 0 {
    if classic_polyline_pending(self.data) &&
      [b"0\nVERTEX\n", b"0\nSEQEND\n"].contains(chunk) {
      for b in chunk {
        self.data.push(b)
      }
      if chunk == b"0\nSEQEND\n" {
        self.records.push(Bytes::from_array(self.data))
        self.data.clear()
        self.supported_record = false
      }
      return
    }
    self.records.push(Bytes::from_array(self.data))
    self.data.clear()
  }
  if chunk == b"0\nSECTION\n" {
    self.pending_section = true
    self.in_entities = false
    self.supported_record = false
  } else if self.pending_section {
    self.in_entities = chunk == b"2\nENTITIES\n"
    self.pending_section = false
  } else if chunk == b"0\nENDSEC\n" {
    self.in_entities = false
    self.supported_record = false
  } else if self.in_entities {
    if chunk.has_prefix(b"0\n") {
      self.supported_record = [
        b"0\nLINE\n", b"0\nCIRCLE\n", b"0\nLWPOLYLINE\n", b"0\nPOLYLINE\n",
      ].contains(chunk)
      if self.supported_record {
        for b in chunk {
          self.data.push(b)
        }
      }
    } else if self.supported_record &&
      (
        [
          b"10\n", b"20\n", b"30\n", b"11\n", b"21\n", b"31\n", b"40\n", b"90\n",
          b"102\n",
        ]
        .iter()
        .any(prefix => chunk.has_prefix(prefix)) ||
        (
          classic_polyline_pending(self.data) &&
          [
            b"39\n", b"41\n", b"42\n", b"70\n", b"75\n", b"210\n", b"220\n", b"230\n",
          ]
          .iter()
          .any(prefix => chunk.has_prefix(prefix))
        )
      ) {
      // The upstream model has only coordinates/radii/point lists. Do not
      // decode ignored legacy-codepage layer names or unsupported text as UTF8.
      for b in chunk {
        self.data.push(b)
      }
    }
  }
}

///|
pub extend GeometrySink with @dxf.DxfGeometrySink::{write_ascii}

///|
// Buffered records contain complete canonical ASCII tags. Retain 102 markers
// until this local projection so their private coordinates never reach either
// upstream parser. Local depth also preserves the public sink representation.
fn geometry_record_bytes(record : Bytes) -> Bytes {
  let output : Array[Byte] = []
  let mut depth = 0
  let mut pos = 0
  while pos < record.length() {
    let start = pos
    while pos < record.length() && record[pos] != 10 {
      pos += 1
    }
    if pos == record.length() {
      return record
    }
    let is_appdata = pos - start == 3 &&
      record[start] == b'1' &&
      record[start + 1] == b'0' &&
      record[start + 2] == b'2'
    if pos - start == 1 && record[start] == b'0' {
      // A classic sequence contains several records; private scope is local
      // to each one, including malformed unclosed groups.
      depth = 0
    }
    pos += 1
    let value_start = pos
    while pos < record.length() && record[pos] != 10 {
      pos += 1
    }
    if pos == record.length() {
      return record
    }
    let value_end = pos
    pos += 1
    if is_appdata {
      if value_end > value_start {
        if record[value_start] == b'{' {
          depth += 1
        } else if record[value_end - 1] == b'}' && depth > 0 {
          depth -= 1
        }
      }
    } else if depth == 0 {
      for byte in record[start:pos] {
        output.push(byte)
      }
    }
  }
  Bytes::from_array(output)
}

///|
/// This upstream supports only LINE/CIRCLE/point POLYLINE; no full DXF claim.
pub fn GeometrySink::drawing(self : GeometrySink) -> @dxf_io.DxfDocument raise {
  // The upstream parser retains optional LINE coordinates between records.
  // Give each supported record its own parse so omitted fields use defaults.
  let records = self.records.copy()
  if self.data.length() > 0 {
    records.push(Bytes::from_array(self.data))
  }
  let drawing = @dxf_io.DxfDocument::new()
  for raw_record in records {
    let record = geometry_record_bytes(raw_record)
    if record.has_prefix(b"0\nPOLYLINE\n") {
      match classic_polyline_geometry(record) {
        Some(entity) => drawing.entities.push(entity)
        None => ()
      }
      continue
    }
    // Use the upstream end-of-input record flush. A following ENDSEC would
    // clear the same point array retained by its DxfPolyline entity.
    let part = @dxf_io.dxf_parse(
      "0\nSECTION\n2\nENTITIES\n" + @utf8.decode(record),
    )
    let numeric_tags = @dxfkit.scan_tags(record).tags
    for entity in part.entities {
      drawing.entities.push(exact_geometry_values(entity, numeric_tags))
    }
  }
  drawing
}

///|
// Reuse the published multi-record assembler. The target point-list model
// cannot retain closure, bulges, widths or spatial/OCS modes, so only the
// explicit open XY subset is projected; the source document stays intact.
fn classic_polyline_geometry(record : Bytes) -> @dxf_io.DxfEntity? {
  let tags = @dxfkit.scan_tags(record).tags
  guard tags.get(tags.length() - 1) is Some(last) &&
    last.code == 0 &&
    last.value is @dxfkit.Str("SEQEND") else {
    return None
  }
  let mut polyline_header = false
  for tag in tags {
    if tag.code == 0 {
      polyline_header = tag.value is @dxfkit.Str("POLYLINE")
    }
    // Header bit128 changes only linetype generation. Vertex flags retain
    // their existing zero-only profile; no curve/spatial mode is projected.
    if tag.code == 70 &&
      tag.value.as_int() != 0 &&
      !(polyline_header && tag.value.as_int() == 128) {
      return None
    }
    if tag.code == 75 && tag.value.as_int() != 0 {
      return None
    }
    if [30, 39, 40, 41, 42, 210, 220].contains(tag.code) &&
      tag.value.as_double() != 0.0 {
      return None
    }
    if tag.code == 230 && tag.value.as_double() != 1.0 {
      return None
    }
  }
  let drawing = @dxfkit.build_drawing(
    @dxfkit.scan_tags(
      b"0\nSECTION\n2\nENTITIES\n" + record + b"0\nENDSEC\n0\nEOF\n",
    ),
  )
  let entities = drawing.entities().entities
  guard entities.length() == 1 else { return None }
  match entities[0].geom {
    @dxfkit.Polyline(vertices~, closed~) => {
      if closed || vertices.length() < 2 {
        return None
      }
      Some(
        @dxf_io.DxfPolyline(
          vertices.map(vertex => @core.Point2D::new(vertex.at.x, vertex.at.y)),
        ),
      )
    }
    _ => None
  }
}

///|
// The upstream model/parser determines entity shape, defaults and point count.
// Its numeric reader ignores exponents. Use published typed tags for scalar
// transfer into the real upstream point/entity constructors, without geometry
// calculations or a local replacement for the upstream parser.
fn exact_geometry_values(
  entity : @dxf_io.DxfEntity,
  tags : Array[@dxfkit.Tag],
) -> @dxf_io.DxfEntity {
  let values : Map[Int32, Double] = Map([])
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  for tag in tags {
    if tag.value is @dxfkit.F64(value) {
      values[tag.code] = value
      if tag.code == 10 {
        xs.push(value)
      }
      if tag.code == 20 {
        ys.push(value)
      }
    }
  }
  match entity {
    @dxf_io.DxfLine(start, end) =>
      @dxf_io.DxfLine(
        @core.Point3D::new(
          values.get(10).unwrap_or(start.x),
          values.get(20).unwrap_or(start.y),
          values.get(30).unwrap_or(start.z),
        ),
        @core.Point3D::new(
          values.get(11).unwrap_or(end.x),
          values.get(21).unwrap_or(end.y),
          values.get(31).unwrap_or(end.z),
        ),
      )
    @dxf_io.DxfCircle(center, radius) =>
      @dxf_io.DxfCircle(
        @core.Point2D::new(
          values.get(10).unwrap_or(center.x),
          values.get(20).unwrap_or(center.y),
        ),
        values.get(40).unwrap_or(radius),
      )
    @dxf_io.DxfPolyline(points) =>
      @dxf_io.DxfPolyline(
        points.mapi((i, point) => {
          @core.Point2D::new(
            xs.get(i).unwrap_or(point.x),
            ys.get(i).unwrap_or(point.y),
          )
        }),
      )
  }
}

///|
/// Count buffered ENTITIES classic POLYLINE candidates not projected by the
/// current open-XY policy. Pending/incomplete sequences count until complete.
/// This is a read-only snapshot, not a count of every unsupported entity kind.
/// It scans buffered records and may allocate through the existing assembler.
pub fn GeometrySink::unprojected_classic_count(self : GeometrySink) -> Int32 {
  let records = self.records.copy()
  if self.data.length() > 0 {
    records.push(Bytes::from_array(self.data))
  }
  let mut count = 0
  for raw_record in records {
    if raw_record.has_prefix(b"0\nPOLYLINE\n") &&
      classic_polyline_geometry(geometry_record_bytes(raw_record)) is None {
      count += 1
    }
  }
  count
}

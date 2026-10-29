"""Independent complete typed models and ASCII/Binary bytes. Data CC0; code MIT.

No product parser, writer, adapter, fixture or upstream algorithm generates an
expectation. Coordinates and projection policy are explicit application inputs.
"""
import struct

SIGNATURE=b'AutoCAD Binary DXF\r\n\x1a\0'
POINTS=[(1.25,-2.5),(4.5,8.75),(9.0,3.0)]
LINE=[(20.0,21.0,0.0),(24.0,25.0,0.0)]

def make_tags(kind):
    tags=[(0,'s','SECTION'),(2,'s','HEADER'),(9,'s','$ACADVER'),(1,'s','AC1015'),(0,'s','ENDSEC'),
          (0,'s','SECTION'),(2,'s','ENTITIES'),(0,'s','POLYLINE'),(5,'s','A0'),(100,'s','AcDbEntity'),
          (8,'s','0'),(100,'s','AcDb2dPolyline'),(66,'i',1),(10,'d',0.0),(20,'d',0.0),(30,'d',0.0)]
    flags=0 if kind=='zero-flag' else 129 if kind=='closed-129' else 128
    if kind!='default-flag':tags.append((70,'i',flags))
    tags += [(75,'i',0),(210,'d',0.0),(220,'d',0.0),(230,'d',1.0)]
    if kind=='private-flags':
        tags += [(102,'s','{VIEW_META'),(70,'i',1),(102,'s','{INNER'),(70,'i',8),
                 (102,'s','INNER}'),(102,'s','VIEW_META}')]
    for index,(x,y) in enumerate(POINTS):
        tags += [(0,'s','VERTEX'),(5,'s',f'A{index+1}'),(100,'s','AcDbEntity'),(8,'s','0'),
                 (100,'s','AcDbVertex'),(100,'s','AcDb2dVertex'),(10,'d',x),(20,'d',y),(30,'d',0.0),
                 (70,'i',128 if kind=='vertex-128' and index==1 else 0),
                 (40,'d',0.5 if kind=='wide-128' and index==1 else 0.0),(41,'d',0.0),(42,'d',0.0)]
        if kind=='private-flags' and index==1:
            tags += [(102,'s','{PRIVATE_VERTEX'),(70,'i',128),(102,'s','}')]
    tags += [(0,'s','SEQEND'),(5,'s','A4'),(100,'s','AcDbEntity'),(8,'s','0'),
             (0,'s','LINE'),(5,'s','B0'),(100,'s','AcDbEntity'),(8,'s','0'),(100,'s','AcDbLine'),
             (10,'d',LINE[0][0]),(20,'d',LINE[0][1]),(30,'d',LINE[0][2]),
             (11,'d',LINE[1][0]),(21,'d',LINE[1][1]),(31,'d',LINE[1][2]),(0,'s','ENDSEC'),(0,'s','EOF')]
    return tags

def wire(tags,binary):
    out=bytearray(SIGNATURE if binary else b'')
    for code,kind,value in tags:
        if binary:
            out.extend(struct.pack('<H',code))
            out.extend(value.encode('ascii')+b'\0' if kind=='s' else struct.pack('<h',value) if kind=='i' else struct.pack('<d',value))
        else:
            text=value if kind=='s' else str(value) if kind=='i' else format(value,'.17g')
            out.extend(f'{code}\n{text}\n'.encode('ascii'))
    return bytes(out)

def typed(tags):
    return [[code,'text' if kind=='s' else 'int' if kind=='i' else 'bits',
             value if kind=='s' else str(value) if kind=='i' else str(struct.unpack('<q',struct.pack('<d',value))[0])]
            for code,kind,value in tags]

def cases():
    result=[]
    for kind in ('linetype-128','zero-flag','default-flag','private-flags','closed-129','vertex-128','wide-128'):
        tags=make_tags(kind)
        projected=kind in ('linetype-128','zero-flag','default-flag','private-flags')
        for binary in (False,True):
            source=wire(tags,binary)
            result.append({'name':kind+('-binary' if binary else '-ascii'),'kind':kind,'binary':binary,'source':source,
                'expectedTags':typed(tags),'expectedPointList':POINTS if projected else None,'expectedLine':LINE,
                'expectedGeometryEntities':2 if projected else 1,'expectedDxfkitEntities':2,
                'expectedUnprojectedClassic':0 if projected else 1,
                'expectedAdapterReport':{'dxfkit_entities':2,'geometry_entities':2 if projected else 1},
                'expectedCoreReport':{'version':'AC1015','complete':True,'tag_count':len(tags),'tags':typed(tags),'diagnostics':[],'details':[]}})
    return result

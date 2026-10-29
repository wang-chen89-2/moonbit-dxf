"""Hand-specified original XDATA workflow models: data CC0-1.0, code MIT.

Only Python bytes/struct and explicit tag labels define source spans/outputs.
No product writer, parser or previous model generator is imported.
"""
import struct

SIGNATURE=b'AutoCAD Binary DXF\r\n\x1a\x00'


def tag(code,kind,value,label=None): return (code,kind,value,label)
def text(code,value,label=None): return tag(code,'text',value if isinstance(value,bytes) else value.encode('utf-8'),label)
def integer(code,value,label=None): return tag(code,'integer',value,label)
def real(code,value,label=None): return tag(code,'real',value,label)


def wire(item,binary=False,old=False):
    code,kind,value,_=item
    if binary:
        prefix=(b'\xff'+struct.pack('<H',code) if code>=1000 else struct.pack('<B',code)) if old else struct.pack('<H',code)
        if kind=='text': return prefix+value+b'\0'
        if kind=='real': return prefix+struct.pack('<d',float(value))
        if kind=='binary': return prefix+bytes([len(value)])+value
        return prefix+struct.pack('<i' if code==1071 else '<h',value)
    if kind=='text': payload=value
    elif kind=='binary': payload=value.hex().encode('ascii')
    else: payload=str(value).encode('ascii')
    return str(code).encode('ascii')+b'\n'+payload+b'\n'


def source_tags(version):
    old=version=='AC1009'
    items=[text(0,'SECTION'),text(2,'HEADER'),text(9,'$ACADVER'),text(1,version),text(0,'ENDSEC'),
           text(0,'SECTION'),text(2,'TABLES'),text(0,'TABLE'),text(2,'APPID')]
    if not old: items += [text(5,'A0'),text(330,'0'),text(100,'AcDbSymbolTable')]
    items += [integer(70,2)]
    for name,handle in [('APP_A','A1'),('APP_B','A2')]:
        items += [text(0,'APPID')]
        if not old:
            items += [text(5,handle),text(330,'A0'),text(100,'AcDbSymbolTableRecord'),text(100,'AcDbRegAppTableRecord')]
        items += [text(2,name),integer(70,0)]
    items += [text(0,'ENDTAB'),text(0,'ENDSEC'),text(0,'SECTION'),text(2,'ENTITIES'),text(0,'LINE'),text(5,'F1')]
    if not old:
        items += [text(102,'{AUDIT'),text(1001,'APP_B'),text(1000,'private-old'),text(1002,'}'),text(102,'}'),text(100,'AcDbEntity')]
    items += [text(8,'0')]
    if not old: items += [text(100,'AcDbLine')]
    items += [real(10,'0.0'),real(20,'1.0'),real(11,'10.0'),real(21,'11.0'),text(1001,'APP_A'),
              text(1000,'café'.encode('utf-8') if version=='AC1032' else b'caf\xe9'),integer(1071,17),text(1000,'keep-A'),
              text(1001,'APP_B','b_marker'),text(1000,'head-B'),text(1002,'{','b_open'),
              text(1000,'nested-old','b_text'),integer(1071,123,'b_integer'),text(1002,'}','b_close'),
              text(1000,'tail-B'),tag(1004,'binary',b'\x00\x80\xff'),text(0,'CIRCLE','next_record'),text(5,'F2','next_handle')]
    if not old: items += [text(100,'AcDbEntity')]
    items += [text(8,'0')]
    if not old: items += [text(100,'AcDbCircle')]
    return items+[real(10,'9.0'),real(20,'10.0'),real(40,'2.0'),text(1001,'APP_B'),text(1000,'neighbor-B'),text(0,'ENDSEC'),text(0,'EOF')]


def requests():
    return [{'handle':'f1','xdata':'APP_B','code':1000,'occurrence':1,'value':{'text':'reviewed-beta'}},
            {'handle':'F1','xdata':'APP_B','code':1071,'value':{'integer':'2000000001'}}]


def typed(item):
    _,kind,value,_=item
    if kind=='text': return {'text_hex':value.hex()}
    if kind=='binary': return {'binary_hex':value.hex()}
    if kind=='real': return {'bits':str(struct.unpack('<q',struct.pack('<d',float(value)))[0])}
    return {'integer':str(value)}


def model(version,binary):
    old=version=='AC1009'; tags=source_tags(version)
    chunks=[wire(item,binary,old) for item in tags]
    positions={item[3]:index for index,item in enumerate(tags) if item[3]}
    indices=[positions['b_text'],positions['b_integer']]
    assert indices==([34,35] if old else [52,53]),indices
    source=(SIGNATURE if binary else b'')+b''.join(chunks)
    prefix=len(SIGNATURE) if binary else 0
    offsets=[prefix]
    for chunk in chunks: offsets.append(offsets[-1]+len(chunk))
    replacements=[text(1000,'reviewed-beta'),integer(1071,2000000001)]
    changes=[]; edits=[]; output=bytearray(); cursor=0
    for index,replacement in zip(indices,replacements):
        after=wire(replacement,binary,old); start,end=offsets[index:index+2]
        output.extend(source[cursor:start]+after); cursor=end
        changes.append({'index':index,'code':tags[index][0],'offset':start,'end_offset':end,
                        'before_hex':chunks[index].hex(),'after_hex':after.hex()})
        edits.append({'index':index,'code':tags[index][0],'expected':typed(tags[index]),'value':typed(replacement)})
    output.extend(source[cursor:]); expected=bytes(output)
    patched_tags=tags.copy()
    for index,replacement in zip(indices,replacements): patched_tags[index]=replacement
    assert expected==(SIGNATURE if binary else b'')+b''.join(wire(item,binary,old) for item in patched_tags)
    data_start=positions['b_marker']+1; data_end=positions['next_record']
    return {'name':version.lower()+('-binary' if binary else '-ascii'),'version':version,'binary':binary,
            'source':source,'expected':expected,'indices':indices,'plan':edits,'requests':requests(),
            'receipt':{'source_bytes':len(source),'output_bytes':len(expected),'changes':changes},
            'expectedData':[{'code':item[0],'value':typed(item)} for item in patched_tags[data_start:data_end]],
            'tags':tags,'positions':positions}


def cases(): return [model(version,binary) for version in ('AC1009','AC1015','AC1032') for binary in (False,True)]


def refusal_sources():
    tags=source_tags('AC1015'); positions={item[3]:index for index,item in enumerate(tags) if item[3]}
    def raw(values): return b''.join(wire(item) for item in values)
    variants=[]
    values=tags.copy(); values[positions['b_marker']]=text(1001,'APP_C')
    variants.append({'name':'private-only-appid','source':raw(values),'error':'XDATA application not found'})
    values=tags[:positions['next_record']]+[text(1001,'APP_B'),text(1000,'second-B')]+tags[positions['next_record']:]
    variants.append({'name':'duplicate-appid','source':raw(values),'error':'ambiguous XDATA application'})
    values=tags.copy(); del values[positions['b_close']]
    variants.append({'name':'unclosed-target-list','source':raw(values),'error':'XDATA list not closed'})
    values=tags.copy(); values[positions['b_open']]=text(1002,'}')
    variants.append({'name':'unexpected-target-close','source':raw(values),'error':'unexpected XDATA list close'})
    values=tags.copy(); values[positions['b_open']]=text(1002,'broken')
    variants.append({'name':'invalid-target-control','source':raw(values),'error':'invalid XDATA list control'})
    values=tags.copy(); values[positions['b_close']+1]=text(8,'bad-normal-field')
    variants.append({'name':'non-xdata-target-field','source':raw(values),'error':'non-XDATA field in application group'})
    values=tags.copy(); values[positions['next_handle']]=text(5,'00f1')
    variants.append({'name':'duplicate-owning-handle','source':raw(values),'error':'ambiguous record handle'})
    return variants

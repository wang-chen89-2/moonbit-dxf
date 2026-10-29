"""Original complete XRECORD guard models: data CC0-1.0, code MIT.

Independent tags, bytes/struct and explicit span splices define all expectations.
No product parser/writer or older fixture generator is imported.
"""
import struct

SIGNATURE=b'AutoCAD Binary DXF\r\n\x1a\x00'
def text(code,value,label=None):return (code,'text',value if isinstance(value,bytes) else value.encode('ascii'),label)
def integer(code,value,label=None):return (code,'integer',value,label)
def real(code,value,label=None):return (code,'real',value,label)


def wire(tag,binary=False):
    code,kind,value,_=tag
    if not binary:return str(code).encode()+b'\n'+(value if kind=='text' else str(value).encode())+b'\n'
    prefix=struct.pack('<H',code)
    if kind=='text':return prefix+value+b'\0'
    if kind=='real':return prefix+struct.pack('<d',float(value))
    return prefix+struct.pack('<i' if code==90 else '<h',value)


def base_tags():
    return [text(0,'SECTION','header_start'),text(2,'HEADER','header_name'),text(9,'$ACADVER','version_key'),text(1,'AC1015','version'),
      text(9,'$UCSNAME','ucs_key'),text(2,'BASE_UCS'),text(0,'ENDSEC'),text(0,'SECTION'),text(2,'ENTITIES'),
      text(0,'LINE'),text(5,'A1'),text(100,'AcDbEntity'),text(8,'0'),text(100,'AcDbLine'),
      real(10,'1.0'),real(20,'2.0'),real(30,'0.0'),real(11,'3.0'),real(21,'4.0'),real(31,'0.0'),text(0,'ENDSEC'),
      text(0,'SECTION'),text(2,'OBJECTS'),text(0,'DICTIONARY'),text(5,'D0'),text(330,'0'),text(100,'AcDbDictionary'),
      integer(281,1),text(3,'APP_META'),text(350,'B1'),text(0,'XRECORD','xrecord_start'),text(5,'B1'),text(330,'D0'),
      text(100,'AcDbXrecord','marker'),integer(280,1),text(9,'user-key','target'),text(1,'unchanged-note'),integer(90,123),
      text(0,'ENDSEC'),text(0,'EOF')]


def serialize(tags,binary=False):return (SIGNATURE if binary else b'')+b''.join(wire(t,binary) for t in tags)
def tagged(tags):return {t[3]:i for i,t in enumerate(tags) if t[3]}
def rendered(tags):
    rows=[]
    for code,kind,value,_ in tags:
        if kind=='text':rows.append([code,'text',value.decode('ascii')])
        elif kind=='real':rows.append([code,'bits',str(struct.unpack('<q',struct.pack('<d',float(value)))[0])])
        else:rows.append([code,'int',str(value)])
    return rows


def positive(name,tags,binary=False,occurrence=0,replacement=b'reviewed-key'):
    labels=tagged(tags);index=labels['target'];source=serialize(tags,binary)
    before=wire(tags[index],binary);after=wire(text(9,replacement),binary)
    offset=(len(SIGNATURE) if binary else 0)+sum(len(wire(t,binary)) for t in tags[:index]);end=offset+len(before)
    expected=source[:offset]+after+source[end:]
    patched=tags.copy();patched[index]=text(9,replacement,'target')
    assert expected==serialize(patched,binary)
    request={'handle':'B1','code':9,'value':{'text':replacement.decode('ascii')}}
    if occurrence:request['occurrence']=occurrence
    plan=[{'index':index,'code':9,'expected':{'text_hex':tags[index][2].hex()},'value':{'text_hex':replacement.hex()}}]
    receipt={'source_bytes':len(source),'output_bytes':len(expected),'changes':[{'index':index,'code':9,'offset':offset,'end_offset':end,
             'before_hex':before.hex(),'after_hex':after.hex()}]}
    return {'name':name,'binary':binary,'source':source,'expected':expected,'index':index,'occurrence':occurrence,
            'old':tags[index][2],'replacement':replacement,'requests':[request],'plan':plan,'receipt':receipt,'tags':tags,
            'expectedTags':rendered(patched),'labels':labels}


def positive_cases():
    tags=base_tags();assert len(tags)==40 and tagged(tags)['target']==35
    result=[positive('primary-ascii',tags),positive('primary-binary',tags,True)]
    repeated=tags.copy();repeated[35]=text(9,'user-key','first_payload');repeated.insert(37,text(9,'second-key','target'))
    result.append(positive('repeated-payload-ascii',repeated,occurrence=1))
    named=tags.copy();named[35]=text(9,'$ACADVER','target');result.append(positive('header-spelling-binary',named,True))
    result.append(positive('binary-newline-payload',tags,True,replacement=b'line1\nline2'))
    assert result[0]['receipt']['changes'][0]['before_hex']=='390a757365722d6b65790a'
    assert result[0]['receipt']['changes'][0]['after_hex']=='390a72657669657765642d6b65790a'
    assert result[1]['receipt']['changes'][0]['before_hex']=='0900757365722d6b657900'
    assert result[1]['receipt']['changes'][0]['after_hex']=='090072657669657765642d6b657900'
    return result


def refusal_cases():
    tags=base_tags();models=[]
    before=tags.copy();item=before.pop(35);before.insert(33,item)
    models.append(('premarker',before,'B1'))
    private=tags.copy();private[33:34]=[text(102,'{PRIVATE'),text(100,'AcDbXrecord'),text(102,'}'),text(100,'OtherMarker')]
    models.append(('private-fake-marker',private,'B1'))
    unrelated=tags.copy();unrelated[30]=text(0,'VENDOR_RECORD','xrecord_start');models.append(('unrelated-record',unrelated,'B1'))
    reset=tags.copy();reset[35]=text(9,'user-key','first_payload')
    reset[-2:-2]=[text(0,'XRECORD'),text(5,'B2'),text(330,'D0'),text(9,'second-key','target')]
    models.append(('record-reset',reset,'B2'))
    result=[]
    for name,values,handle in models:
        index=tagged(values)['target'];result.append({'name':name,'source':serialize(values),'index':index,'old':values[index][2],
          'handle':handle,'requests':[{'handle':handle,'code':9,'value':{'text':'reviewed-key'}}],
          'plan':[{'index':index,'code':9,'expected':{'text_hex':values[index][2].hex()},'value':{'text_hex':b'reviewed-key'.hex()}}],
          'tags':values,'error':'structural/version edit requires document migration',
          'boundary':'Conservative typed but unclassified/malformed context control; not a legal external CAD acceptance claim.'})
    return result


def table_case():
    tags=base_tags()
    section=[text(0,'SECTION'),text(2,'TABLES'),text(0,'TABLE'),text(2,'LAYER','table_name'),text(5,'C0'),text(330,'0'),
             text(100,'AcDbSymbolTable'),integer(70,1),text(0,'LAYER'),text(5,'C1'),text(330,'C0'),
             text(100,'AcDbSymbolTableRecord'),text(100,'AcDbLayerTableRecord'),text(2,'0'),integer(70,0),integer(62,7),
             text(6,'CONTINUOUS'),text(0,'ENDTAB'),text(0,'ENDSEC')]
    tags[7:7]=section
    return {'name':'table-structural-control','source':serialize(tags),'tags':tags,'labels':tagged(tags)}

"""Original independently annotated records/bytes/splices. Data CC0; code MIT.

Record ownership and physical partitions are declared by the model. No product
parser/writer or third-party algorithm produces any expected field or byte.
"""
import copy,hashlib,struct
SIG=b'AutoCAD Binary DXF\r\n\x1a\0'
def s(code,value):return (code,'s',value.encode('ascii') if isinstance(value,str) else value)
def i(code,value):return (code,'i',value)
def d(code,value):return (code,'d',value)
def rec(kind,body=(),handle=None):
    return {'kind':kind.encode('ascii'),'handle':None if handle is None else handle.encode('ascii') if isinstance(handle,str) else handle,
            'tags':[s(0,kind),*body]}
def modern(kind='modern',binary=False):
    handle=b'\xff' if kind=='raw-handle' else b'A1'
    line=rec('LINE',[s(102,'{PRIVATE'),s(5,'DEAD'),s(102,'}'),s(5,handle),s(330,'0'),
        s(100,'AcDbEntity'),s(8,'0'),s(100,'AcDbLine'),d(10,2.25),d(20,-3.5),d(30,0.0),d(11,7.0),d(21,11.0),d(31,0.0),
        s(1 if binary else 999,'line tail')],handle)
    rows=[rec('SECTION',[s(2,'HEADER'),s(9,'$ACADVER'),s(1,'AC1015'),s(9,'$DWGCODEPAGE'),s(3,'ANSI_1252'),s(9,'$HANDSEED'),s(5,'F00')]),
        rec('ENDSEC'),rec('SECTION',[s(2,'TABLES')]),rec('TABLE',[s(2,'DIMSTYLE'),s(5,'D0'),s(100,'AcDbSymbolTable'),i(70,1)],'D0'),
        rec('DIMSTYLE',[s(105,'003a'),s(330,'D0'),s(100,'AcDbSymbolTableRecord'),s(100,'AcDbDimStyleTableRecord'),s(2,'STANDARD'),s(5,'F00')],'003a'),
        rec('ENDTAB'),rec('ENDSEC'),rec('SECTION',[s(2,'ENTITIES')]),line,
        rec('ACME_DATA',[s(5,'B2'),s(100,'AcDbEntity'),s(100,'AcmeData'),s(5,'CC'),s(1,b'caf\xe9')],'B2'),
        rec('ACME_NO_ID',[s(100,'AcmeData'),s(5,'BEEF'),s(1,'payload handle is not an owner')]),rec('ENDSEC'),rec('EOF')]
    if kind=='duplicate':
        duplicate=rec('LINE',[s(5,'000a1'),s(100,'AcDbEntity'),s(8,'0'),s(100,'AcDbLine'),d(10,12.0),d(20,13.0),d(11,14.0),d(21,15.0)],'000a1')
        rows.insert(9,duplicate)
    return rows
def legacy():
    return [rec('SECTION',[s(2,'HEADER'),s(9,'$ACADVER'),s(1,'AC1009')]),rec('ENDSEC'),
            rec('SECTION',[s(2,'ENTITIES')]),rec('LINE',[s(8,'0'),d(10,2.25),d(20,-3.5),d(30,0.0),d(11,7.0),d(21,11.0),d(31,0.0)]),
            rec('ENDSEC'),rec('EOF')]
def empty_entities():
    return [rec('SECTION',[s(2,'HEADER'),s(9,'$ACADVER'),s(1,'AC1009')]),rec('ENDSEC'),
            rec('SECTION',[s(2,'ENTITIES')]),rec('ENDSEC'),rec('EOF')]
def frame(tag,binary,version,canonical=False):
    code,kind,value=tag
    if binary:
        width=1 if version=='AC1009' else 2
        group=bytes([code]) if width==1 and code<255 else b'\xff'+struct.pack('<H',code) if width==1 else struct.pack('<H',code)
        return group+(value+b'\0' if kind=='s' else struct.pack('<h',value) if kind=='i' else struct.pack('<d',value))
    text=value if kind=='s' else str(value).encode() if kind=='i' else format(value,'.17g').encode()
    return str(code).encode()+b'\n'+text+b'\n' if canonical else f'{code:3d}'.encode()+b'\r\n'+text+b'\r\n'
def typed(tags):
    return [[code,'text' if kind=='s' else 'int' if kind=='i' else 'bits',
        value.decode('utf-8',errors='replace') if kind=='s' else str(value) if kind=='i' else str(struct.unpack('<q',struct.pack('<d',value))[0])]
        for code,kind,value in tags]
def build(kind,binary,*,original_binary999=False):
    # ASCII retains code999 comments. Binary uses a declared ordinary Text
    # payload (code1); existing Binary decoding forbids code999. The original
    # illegal representation remains independently reproduced as controls.
    version='AC1009' if kind in ('legacy','empty-entities') else 'AC1015'
    records=empty_entities() if kind=='empty-entities' else legacy() if kind=='legacy' else modern(kind,binary=binary and not original_binary999)
    prefix=[] if binary else [s(999,'inventory preamble')]
    original=bytearray(SIG if binary else b'');all_tags=[];spans=[];tag_spans=[]
    for tag in prefix:
        start=len(original);raw=frame(tag,binary,version);original.extend(raw);tag_spans.append((start,len(original),raw));all_tags.append(tag)
    record_bytes=[]
    for ordinal,record in enumerate(records):
        start=len(original);start_tag=len(all_tags)
        for tag in record['tags']:
            offset=len(original);raw=frame(tag,binary,version);original.extend(raw);tag_spans.append((offset,len(original),raw));all_tags.append(tag)
        record_bytes.append(bytes(original[start:]))
        spans.append({'ordinal':ordinal,'start_tag':start_tag,'end_tag':len(all_tags),'kind_hex':record['kind'].hex(),
            'handle_hex':None if record['handle'] is None else record['handle'].hex(),'offset':start,'end_offset':len(original)})
    if not binary:original.extend(b'\r\n  \r\n')  # outside the last typed tag, retained in source/save
    source=bytes(original)
    report={'version':version,'binary':binary,'source_bytes':len(source),'record_count':len(spans),'records':spans,'source_sha256':hashlib.sha256(source).hexdigest()}
    result={'name':kind+('-binary' if binary else '-ascii'),'kind':kind,'binary':binary,'version':version,'source':source,
        'report':report,'recordBytes':[raw.hex() for raw in record_bytes],'typedTags':typed(all_tags),
        'complete':True,'bodyTags':all_tags,'tagSpans':tag_spans}
    if kind=='legacy':
        line=spans[3];target=line['start_tag']+2  # declared layer8 then x10 in this complete record
        assert all_tags[target][0]==10
        offset,end,before=tag_spans[target];after=frame(d(10,4.25),binary,version,canonical=True)
        output=source[:offset]+after+source[end:];delta=len(after)-len(before)
        expected_report=copy.deepcopy(report);expected_report['source_bytes']=len(output);expected_report['source_sha256']=hashlib.sha256(output).hexdigest()
        for row in expected_report['records']:
            if row['offset']>=end:row['offset']+=delta
            if row['end_offset']>=end:row['end_offset']+=delta
        output_tags=copy.deepcopy(all_tags);output_tags[target]=d(10,4.25)
        old_bits=str(struct.unpack('<q',struct.pack('<d',2.25))[0]);new_bits=str(struct.unpack('<q',struct.pack('<d',4.25))[0])
        plan=[{'index':target,'code':10,'expected':{'bits':old_bits},'value':{'bits':new_bits}}]
        receipt={'source_bytes':len(source),'output_bytes':len(output),'changes':[{'index':target,'code':10,'offset':offset,'end_offset':end,'before_hex':before.hex(),'after_hex':after.hex()}],
                 'source_sha256':hashlib.sha256(source).hexdigest()}
        result.update({'edited':output,'plan':plan,'boundPlan':{'format':'dxf-source-plan-v1','source_sha256':report['source_sha256'],'edits':plan},
            'receipt':receipt,'editedTypedTags':typed(output_tags),'editedReport':expected_report,'targetIndex':target})
    return result
def cases():
    return [build(kind,binary) for kind in ('modern','legacy','duplicate','raw-handle','empty-entities') for binary in (False,True)]
def refusal_cases():
    result=[]
    def control(name,source,error,code,offset,message,prefix,*,complete=False,isolated=False,old_name=None):
        result.append({'name':name,'source':source,'error':error,'complete':complete,
            'primaryDiagnostic':{'code':code,'offset':offset,'message':message},'decodedTypedTags':typed(prefix),
            'isolatedReason':isolated,'originalFrozenCase':old_name})
    # Original three failed positive Binary vectors remain byte-for-byte controls.
    originals={kind:build(kind,True,original_binary999=True) for kind in ('modern','duplicate','raw-handle')}
    for kind,case in originals.items():
        index=next(i for i,t in enumerate(case['bodyTags']) if t[0]==999)
        control('original-'+kind+'-binary999',case['source'],'IncompleteDocument','InvalidTag',case['tagSpans'][index][0],
                'unknown or forbidden Binary group code 999',case['bodyTags'][:index],old_name=kind+'-binary')
    control('original-zero-bytes',b'','IncompleteDocument','TruncatedSignature',0,'incomplete Binary header',[],old_name='empty-ascii')
    old=originals['modern'];bad_index=next(i for i,t in enumerate(old['bodyTags']) if t[0]==999);bad_offset=old['tagSpans'][bad_index][0]
    control('original-compound-truncation',old['source'][:-1],'IncompleteDocument','InvalidTag',bad_offset,
            'unknown or forbidden Binary group code 999',old['bodyTags'][:bad_index],old_name='truncated-binary')
    compound_tags=copy.deepcopy(old['bodyTags']);compound_tags[3]=s(1,'AC1009')
    control('original-compound-wire',old['source'].replace(b'AC1015',b'AC1009'),'IncompleteDocument','InvalidTag',bad_offset,
            'unknown or forbidden Binary group code 999',compound_tags[:bad_index],old_name='wire-version-mismatch')
    primary=build('modern',False);unsupported=copy.deepcopy(primary['bodyTags']);unsupported[4]=s(1,'AC1012')
    control('unsupported-r13',primary['source'].replace(b'AC1015',b'AC1012'),'UnsupportedVersion','UnsupportedVersion',0,
            'unsupported/ambiguous version AC1012',unsupported,complete=True,isolated=True,old_name='unsupported-r13')
    legal=build('modern',True)
    control('isolated-truncated-binary',legal['source'][:-1],'IncompleteDocument','TruncatedTag',legal['tagSpans'][-1][0],
            'unfinished group/value pair',legal['bodyTags'][:-1],isolated=True)
    wire_tags=copy.deepcopy(legal['bodyTags']);wire_tags[3]=s(1,'AC1009')
    control('isolated-wire-mismatch',legal['source'].replace(b'AC1015',b'AC1009'),'wire/version mismatch','WireVersionMismatch',22,
            'group-code width conflicts with ACADVER',wire_tags,complete=True,isolated=True)
    return result

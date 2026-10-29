"""Independent original complete tag/wire models. Data CC0-1.0; code MIT.

Only bytes, struct and explicit duplicate indices define expected lint results.
No product parser/writer, canonical helper or previous fixture producer is used.
"""
import struct

SIGNATURE=b'AutoCAD Binary DXF\r\n\x1a\x00'


def text(code,value):return (code,'text',value.encode('ascii'))
def real(code,value):return (code,'real',value)
def integer(code,value):return (code,'integer',value)


def encode(tag,binary):
    code,kind,value=tag
    if not binary:
        return str(code).encode()+b'\n'+(value if kind=='text' else str(value).encode())+b'\n'
    prefix=struct.pack('<H',code)
    if kind=='text':return prefix+value+b'\0'
    if kind=='real':return prefix+struct.pack('<d',float(value))
    return prefix+struct.pack('<h',value)


def header():return [text(0,'SECTION'),text(2,'HEADER'),text(9,'$ACADVER'),text(1,'AC1032'),text(0,'ENDSEC')]


def entities(handles,private=False):
    tags=header()+[text(0,'SECTION'),text(2,'ENTITIES')];owned=[]
    for n,handle in enumerate(handles):
        tags+=[text(0,'LINE')]
        if private and n==0:tags+=[text(102,'{NOTE'),text(5,'2A'),text(102,'}')]
        owned.append(len(tags));tags+=[text(5,handle),text(100,'AcDbEntity'),text(8,'0'),text(100,'AcDbLine'),
                                     real(10,f'{n}.0'),real(20,'0.0'),real(30,'0.0'),real(11,f'{n+1}.0'),real(21,'1.0'),real(31,'0.0')]
    return tags+[text(0,'ENDSEC'),text(0,'EOF')],owned


def dimstyles():
    tags=header()+[text(0,'SECTION'),text(2,'TABLES'),text(0,'TABLE'),text(2,'DIMSTYLE'),text(5,'80'),text(330,'0'),text(100,'AcDbSymbolTable'),integer(70,2)]
    owned=[]
    for n,handle in enumerate(['B0','000b0']):
        tags+=[text(0,'DIMSTYLE')];owned.append(len(tags))
        tags+=[text(105,handle),text(330,'80'),text(100,'AcDbSymbolTableRecord'),text(100,'AcDbDimStyleTableRecord'),text(2,f'STYLE_{n}'),integer(70,0),text(5,'SHARED_REFERENCE')]
    return tags+[text(0,'ENDTAB'),text(0,'ENDSEC'),text(0,'EOF')],owned


def make(name,tags,owned,duplicates,binary=False,description=''):
    chunks=[encode(t,binary) for t in tags];cursor=len(SIGNATURE) if binary else 0;offsets=[]
    for raw in chunks:offsets.append(cursor);cursor+=len(raw)
    details=[{'code':'DuplicateHandle','severity':'error','offset':offsets[owned[n]],
              'message':'duplicate handle '+tags[owned[n]][2].decode('ascii')} for n in duplicates]
    return {'name':name,'binary':binary,'source':(SIGNATURE if binary else b'')+b''.join(chunks),
            'tags':tags,'tagCount':len(tags),'ownedIndices':owned,'duplicateOwnedOrdinals':duplicates,
            'details':details,'diagnostics':['DuplicateHandle']*len(details),'exitCode':1 if details else 0,'description':description}


def cases():
    tags,owned=entities(['2A','00002a'])
    result=[make('alias-ascii',tags,owned,[1],description='Same hexadecimal identity, different leading-zero spelling'),
            make('alias-binary',tags,owned,[1],True,description='Same exact identity mismatch in supported modern binary wire')]
    tags,owned=entities(['2A','02a','0002A']);result.append(make('three-aliases',tags,owned,[1,2]))
    tags,owned=entities(['0002A','02B'],private=True);result.append(make('distinct-private-control',tags,owned,[],description='Distinct values; private fake owning handle ignored'))
    tags,owned=dimstyles();result.append(make('dimstyle-105',tags,owned,[1],description='105 owns DIMSTYLE; repeated code5 references do not own it'))
    tags,owned=entities(['FFFFFFFFFFFFFFFF','ffffffffffffffff']);result.append(make('unsigned-16digit-control',tags,owned,[1],description='Existing case folding above signed Int64 maximum remains valid without numeric casts'))
    tags,owned=entities(['BAD-G','bad-g']);result.append(make('malformed-legacy-control',tags,owned,[1],description='Malformed strings retain old uppercase duplicate comparison; no new validity or CAD acceptance claim'))
    assert len(result)==7
    # Independent numeric evidence only for valid hexadecimal owner spellings.
    assert int('2A',16)==int('00002a',16)==42
    assert int('2A',16)==int('02a',16)==int('0002A',16)
    assert int('0002A',16)!=int('02B',16)
    assert int('B0',16)==int('000b0',16)==176
    assert int('FFFFFFFFFFFFFFFF',16)==2**64-1
    return result

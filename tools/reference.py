"""Independent ezdxf model/typed-tag oracle. Use an isolated PYTHONPATH for ezdxf.
Generated drawings are original parameterized fixtures, licensed CC0-1.0.
This program never copies the MoonBit codec algorithm into an oracle.
"""
from pathlib import Path
import io, json, sys, hashlib, struct
import ezdxf
from ezdxf.lldxf.tagger import binary_tags_loader

ROOT=Path(__file__).resolve().parents[1]

def tag_json(t):
    v=t.value
    if isinstance(v, bytes): return [t.code,'bytes',v.hex()]
    if isinstance(v, float): return [t.code,'double',struct.pack('<d',v).hex()]
    if isinstance(v, int): return [t.code,'int',str(v)]
    return [t.code,'text',v]

def generate():
    ezdxf.options.write_fixed_meta_data_for_testing=True
    folder=ROOT/'fixtures'; folder.mkdir(exist_ok=True)
    manifest=[]
    for ver in ['R12','R2000','R2018']:
        doc=ezdxf.new(ver)
        doc.appids.new('DXF_TEST')
        block=doc.blocks.new('PART', base_point=(2,3,0))
        block.add_line((0,0,0),(5,10,0))
        m=doc.modelspace()
        line=m.add_line((1.25,-2.5,0),(9,12,0))
        line.set_xdata('DXF_TEST',[(1000,'fixture'),(1002,'{'),(1070,-32768),(1071,2147483647),(1040,-0.0),(1004,b'\x00\xff\x01'),(1002,'}')])
        m.add_circle((4,5),2.5)
        m.add_arc((1,1),3,15,160)
        m.add_blockref('PART',(12,15))
        if ver!='R12': m.add_lwpolyline([(0,0),(5,0),(5,4)],close=True)
        text=io.StringIO(); doc.write(text)
        binary=io.BytesIO(); doc.write(binary,fmt='bin')
        for ext,data in [('ascii',text.getvalue().encode(doc.output_encoding)),('binary',binary.getvalue())]:
            name=f'{ver.lower()}-{ext}.dxf'
            (folder/name).write_bytes(data)
            manifest.append({'path':name,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'source':'original generated model using ezdxf '+ezdxf.__version__,'license':'CC0-1.0','version':doc.dxfversion,'kind':ext,'modelspace_entities':len(m)})
        tags=list(binary_tags_loader(binary.getvalue()))
        (folder/f'{ver.lower()}-tags.json').write_text(json.dumps([tag_json(t) for t in tags],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (folder/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'ezdxf':ezdxf.__version__,'generated':len(manifest),'license':'CC0-1.0'}))

def verify(path):
    inp=Path(path); doc=ezdxf.readfile(inp)
    audit=doc.audit()
    return {'file':str(inp),'version':doc.dxfversion,'entities':len(doc.modelspace()),'errors':len(audit.errors),'fixes':len(audit.fixes)}

if __name__=='__main__':
    if sys.argv[1:] == ['generate']: generate()
    else: print(json.dumps([verify(p) for p in sys.argv[1:]],ensure_ascii=False,indent=2))

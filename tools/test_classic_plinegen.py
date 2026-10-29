"""Actual file receiving for the bounded classic POLYLINE linetype profile.

Original complete inputs/typed expected tags/coordinates come from the separate
Python bytes/struct producer, never a product parser, writer or adapter.
"""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys
from classic_plinegen_cases import cases

ROOT=Path(__file__).resolve().parents[1]
def sha(raw):return hashlib.sha256(raw).hexdigest()
def encoded(obj):return (json.dumps(obj,indent=2)+'\n').encode()
def snapshot(folder):return {p.name:p.read_bytes() for p in folder.iterdir() if p.is_file()}

def verify(output):
    output.mkdir(parents=True)
    logs=output/'logs';logs.mkdir();commands=[];observations=[]
    node=shutil.which('node');assert node
    def run(label,args):
        command=[node,str(ROOT/'tools/dxf.mjs'),*map(str,args)]
        proc=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=30)
        number=len(commands);out,err=logs/f'{number:02d}.stdout',logs/f'{number:02d}.stderr'
        out.write_bytes(proc.stdout);err.write_bytes(proc.stderr)
        commands.append({'case':label,'command':command,'exitCode':proc.returncode,'expectedExitCode':0,'stdout':str(out),'stderr':str(err)})
        (output/'COMMANDS.json').write_bytes(encoded(commands))
        assert proc.returncode==0,(label,proc.returncode,proc.stdout,proc.stderr)
        return proc
    for index,case in enumerate(cases()):
        folder=output/case['name'];folder.mkdir();source=folder/'source.dxf';target=folder/'received-save.dxf'
        source.write_bytes(case['source']);(folder/'sentinel.bin').write_bytes(b'original-input-and-neighbors\0\xff')
        expected={key:value for key,value in case.items() if key!='source'}
        (folder/'expected.json').write_bytes(encoded(expected))
        if index%2:target.write_bytes(b'preexisting-independent-output\0\xff')
        before=snapshot(folder)
        tags=run(case['name']+'-full-tags',['tags',source])
        assert tags.stderr==b'' and json.loads(tags.stdout)==case['expectedCoreReport'] and snapshot(folder)==before
        report=run(case['name']+'-actual-upstream-adapters',['adapters',source])
        assert report.stderr==b'' and json.loads(report.stdout)==case['expectedAdapterReport'] and snapshot(folder)==before
        saved=run(case['name']+'-exact-original-save',['save',source,target])
        assert saved.stderr==saved.stdout==b'' and target.read_bytes()==case['source']
        after=snapshot(folder);assert set(after)==set(before)|{target.name}
        assert all(after[name]==raw for name,raw in before.items() if name!=target.name)
        (folder/'received-tags.json').write_bytes(tags.stdout);(folder/'received-adapters.json').write_bytes(report.stdout)
        observations.append({'case':case['name'],'binary':case['binary'],'sourceSHA256':sha(case['source']),
            'savedSHA256':sha(target.read_bytes()),'sourceBytes':len(case['source']),'fullTypedTags':json.loads(tags.stdout),
            'actualAdapterReport':json.loads(report.stdout),'expectedPointList':case['expectedPointList'],
            'expectedLine':case['expectedLine'],'inputAndNeighborsUnchanged':True,'exactOriginalSaved':True,
            'replacedIndependentExistingTarget':bool(index%2)})
    result={'status':'PASS','realFileHostProcesses':len(commands),'completeIndependentSourceModels':len(observations),
        'fullReadAdapterSaveChains':observations,'productParserWriterUsedToGenerateExpected':False,
        'actualNativeCoordinatesVerifiedSeparately':'examples/classic_plinegen and adapters/classic_plinegen_test.mbt',
        'boundary':'Actual whole-file typed receiving, real upstream entity counts and exact save bytes; no vendor-CAD, rendering or file-durability certification.'}
    (output/'RESULT.json').write_bytes(encoded(result));return result

if __name__=='__main__':
    assert len(sys.argv)==2,'Provide a new output directory'
    result=verify(Path(sys.argv[1]).resolve())
    print(json.dumps({'status':result['status'],'realFileHostProcesses':result['realFileHostProcesses'],'sourceModels':result['completeIndependentSourceModels']}))

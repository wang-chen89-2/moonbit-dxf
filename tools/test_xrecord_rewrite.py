"""Real XRECORD plan/preview/patch/receiving against independent full wire models.

No product parser or writer creates expected values/bytes. Original data CC0-1.0.
"""
from pathlib import Path
import copy
import hashlib
import json
import shutil
import subprocess
import sys
from xrecord_cases import positive_cases, refusal_cases, table_case

ROOT=Path(__file__).resolve().parents[1]
CLI=ROOT/'tools/dxf.mjs'


def sha(raw):return hashlib.sha256(raw).hexdigest()
def encoded(obj):return (json.dumps(obj,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
def snapshot(folder):return {p.name:p.read_bytes() for p in folder.iterdir() if p.is_file()}


def verify(output):
    node=shutil.which('node');assert node
    output.mkdir(parents=True)  # Preserve previous evidence and caller files.
    logs=output/'logs';logs.mkdir();rows=[];observations=[]
    def run(label,args,status,error=None):
        command=[node,str(CLI),*map(str,args)]
        proc=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=30)
        number=len(rows);stdout,stderr=logs/f'{number:02}.stdout',logs/f'{number:02}.stderr'
        stdout.write_bytes(proc.stdout);stderr.write_bytes(proc.stderr)
        rows.append({'case':label,'command':command,'exitCode':proc.returncode,'expectedExitCode':status,'stdout':str(stdout),'stderr':str(stderr)})
        (output/'COMMANDS.json').write_bytes(encoded(rows))
        assert proc.returncode==status,(label,proc.returncode,proc.stdout,proc.stderr)
        if error:assert proc.stdout==b'' and error.encode() in proc.stderr,(label,proc.stderr)
        return proc

    models=positive_cases()
    for index,case in enumerate(models):
        folder=output/case['name'];folder.mkdir()
        source,request,plan,target=[folder/n for n in ('source.dxf','requests.json','plan.json','patched.dxf')]
        source.write_bytes(case['source']);request.write_bytes(encoded(case['requests']))
        (folder/'sentinel.bin').write_bytes(b'preserve-source-and-inputs\0\xff')
        if index%2:target.write_bytes(b'existing-independent-output\0\xff')
        before=snapshot(folder);digest=sha(case['source'])
        proc=run(case['name']+'-bound-plan',['make-bound-plan',source,request],0)
        assert proc.stderr==b'' and json.loads(proc.stdout)=={'format':'dxf-source-plan-v1','source_sha256':digest,'edits':case['plan']}
        assert snapshot(folder)==before;plan.write_bytes(proc.stdout);ready=snapshot(folder)
        receipt=case['receipt']|{'source_sha256':digest}
        proc=run(case['name']+'-preview',['patch-plan',source,plan],0)
        assert proc.stderr==b'' and json.loads(proc.stdout)==receipt and snapshot(folder)==ready
        proc=run(case['name']+'-patch',['patch',source,target,plan],0)
        assert proc.stdout==b'' and json.loads(proc.stderr)==receipt and target.read_bytes()==case['expected']
        after=snapshot(folder)
        assert set(after)==set(ready)|{target.name} and all(after[n]==b for n,b in ready.items() if n!=target.name)
        proc=run(case['name']+'-actual-file-receive',['tags',target],0)
        expected={'version':'AC1015','complete':True,'tag_count':len(case['expectedTags']),'tags':case['expectedTags'],'diagnostics':[],'details':[]}
        assert proc.stderr==b'' and json.loads(proc.stdout)==expected and snapshot(folder)==after
        (folder/'received.json').write_bytes(proc.stdout);(folder/'expected.dxf').write_bytes(case['expected'])
        observations.append({'case':case['name'],'sourceSHA256':digest,'outputSHA256':sha(case['expected']),
          'boundPlan':True,'receipt':receipt,'receivedFullTags':case['expectedTags'],'exactIndependentWholeOutput':True,
          'inputsAndNonTargetBytesUnchanged':True,'existingTargetReplaced':bool(index%2)})

    for case in refusal_cases():
        folder=output/case['name'];folder.mkdir()
        source,request,plan,target=[folder/n for n in ('source.dxf','requests.json','plan.json','target.dxf')]
        source.write_bytes(case['source']);request.write_bytes(encoded(case['requests']));plan.write_bytes(encoded(case['plan']))
        target.write_bytes(b'preserve-existing-target\0\xff');before=snapshot(folder)
        run(case['name']+'-make-plan',['make-plan',source,request],2,case['error']);assert snapshot(folder)==before
        run(case['name']+'-patch',['patch',source,target,plan],2,case['error']);assert snapshot(folder)==before

    # Frozen independent source tags identify real protected fields. Include a
    # later ENDSEC so a validated allowed edit still cannot produce partial output.
    primary=models[0];table=table_case()
    structural=[(primary,i) for i in [0,1,2,3,4,38]]+[(table,table['labels']['table_name'])]
    for number,(case,index) in enumerate(structural):
        folder=output/f'structural-{number}';folder.mkdir()
        source,plan,target=[folder/n for n in ('source.dxf','plan.json','target.dxf')]
        source.write_bytes(case['source']);target.write_bytes(b'unchanged-output\0\xff')
        allowed=copy.deepcopy(primary['plan'][0]);allowed['index']=case['labels']['target']
        tag=case['tags'][index];assert tag[1]=='text'
        bad={'index':index,'code':tag[0],'expected':{'text_hex':tag[2].hex()},'value':{'text':'changed'}}
        plan.write_bytes(encoded([allowed,bad]));before=snapshot(folder)
        run('mixed-protected-'+str(number),['patch',source,target,plan],2,'structural/version edit requires document migration')
        assert snapshot(folder)==before

    guard_specs=[('stale-expected',models[0],'stale','edit precondition failed'),
                 ('wrong-type',models[0],{'integer':'7'},'integer type mismatch'),
                 ('ascii-newline',models[0],{'text':'bad\nkey'},'text contains wire delimiter'),
                 ('ascii-nul',models[0],{'text':'bad\0key'},'text contains wire delimiter'),
                 ('binary-nul',models[1],{'text':'bad\0key'},'text contains wire delimiter')]
    for name,case,value,error in guard_specs:
        folder=output/name;folder.mkdir()
        source,plan,target=[folder/n for n in ('source.dxf','plan.json','target.dxf')]
        source.write_bytes(case['source']);target.write_bytes(b'keep\0\xff');edits=copy.deepcopy(case['plan'])
        if value=='stale':edits[0]['expected']={'text_hex':b'wrong'.hex()}
        else:edits[0]['value']=value
        plan.write_bytes(encoded(edits));before=snapshot(folder)
        run(name,['patch',source,target,plan],2,error);assert snapshot(folder)==before

    folder=output/'bound-source-hash';folder.mkdir()
    source,plan,target=[folder/n for n in ('source.dxf','plan.json','target.dxf')]
    source.write_bytes(primary['source']);target.write_bytes(b'keep\0\xff')
    plan.write_bytes(encoded({'format':'dxf-source-plan-v1','source_sha256':'0'*64,'edits':primary['plan']}))
    before=snapshot(folder)
    run('bound-source-hash',['patch',source,target,plan],2,'Input SHA-256 does not match the source-bound plan');assert snapshot(folder)==before

    result={'status':'PASS','realFileHostProcesses':len(rows),'positiveProcesses':sum(r['expectedExitCode']==0 for r in rows),
            'negativeProcesses':sum(r['expectedExitCode']==2 for r in rows),'fullBoundFileChains':observations,
            'conservativeContextCases':4,'mixedProtectedCases':len(structural),'typeExpectedWireCases':len(guard_specs),'wrongBoundHashCases':1,
            'productParserOrWriterUsedForExpectations':False,'newProtocolOrReceiverAPI':False,
            'receiverBoundary':'Actual written file read with existing tags command; complete typed values and every output byte checked. No external CAD/schema certification.',
            'preservationObservation':'Exact bytes and directory entries; no mtime/inode/atomic-write durability claim.'}
    (output/'RESULT.json').write_bytes(encoded(result))
    print(json.dumps({'status':'PASS','realFileHostProcesses':len(rows),'positiveProcesses':result['positiveProcesses'],
                      'negativeProcesses':result['negativeProcesses'],'fullBoundFileChains':len(observations)}))
    return result


if __name__=='__main__':
    if len(sys.argv)!=2:raise SystemExit('Usage: python tools/test_xrecord_rewrite.py NEW_EVIDENCE_DIRECTORY')
    verify(Path(sys.argv[1]).resolve())

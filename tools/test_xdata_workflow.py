"""Actual APPID file workflow against independently specified bytes/struct models.

The producer defines original wire inputs, exact plans, replacements and receipts;
neither the product decoder nor writer supplies an expected result. Data CC0-1.0.
"""
from pathlib import Path
import copy
import hashlib
import json
import shutil
import subprocess
import sys
from xdata_cases import cases, refusal_sources
from xdata_extra_cases import extra_cases

ROOT=Path(__file__).resolve().parents[1]
CLI=ROOT/'tools/dxf.mjs'
RECEIVER=ROOT/'examples/xdata_plan/receive.mjs'


def encoded(obj): return (json.dumps(obj,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
def sha(raw): return hashlib.sha256(raw).hexdigest()
def snapshot(folder): return {p.name:p.read_bytes() for p in folder.iterdir() if p.is_file()}


def verify(output):
    node=shutil.which('node'); assert node
    output.mkdir(parents=True)  # Preserve every previous run and caller file.
    logs=output/'logs';logs.mkdir()
    rows=[];positives=[]

    def run(label,command,exit_code,error=None):
        proc=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=30)
        number=len(rows)
        stdout,stderr=logs/f'{number:02}.stdout',logs/f'{number:02}.stderr'
        stdout.write_bytes(proc.stdout);stderr.write_bytes(proc.stderr)
        rows.append({'case':label,'command':command,'exitCode':proc.returncode,'expectedExitCode':exit_code,
                     'stdout':str(stdout),'stderr':str(stderr)})
        (output/'COMMANDS.json').write_bytes(encoded(rows))
        assert proc.returncode==exit_code,(label,proc.returncode,proc.stdout,proc.stderr)
        if error is not None:
            assert proc.stdout==b'' and error.encode() in proc.stderr,(label,proc.stderr)
        return proc

    for index,case in enumerate(cases()):
        folder=output/case['name'];folder.mkdir()
        source,requests,plan,target=[folder/n for n in ('source.dxf','requests.json','plan.json','patched.dxf')]
        source.write_bytes(case['source']);requests.write_bytes(encoded(case['requests']))
        (folder/'sentinel.bin').write_bytes(b'untouched\0\xff')
        if index%2: target.write_bytes(b'previous-separate-output\0\xff')
        before=snapshot(folder)
        bound=index%2==1
        action='make-bound-plan' if bound else 'make-plan'
        formed=run(case['name']+'-'+action,[node,str(CLI),action,str(source),str(requests)],0)
        expected_plan={'format':'dxf-source-plan-v1','source_sha256':sha(case['source']),'edits':case['plan']} if bound else case['plan']
        assert formed.stderr==b'' and json.loads(formed.stdout)==expected_plan
        assert snapshot(folder)==before
        plan.write_bytes(formed.stdout)
        ready=snapshot(folder)
        expected_receipt=dict(case['receipt'])
        if bound: expected_receipt['source_sha256']=sha(case['source'])
        preview=run(case['name']+'-preview',[node,str(CLI),'patch-plan',str(source),str(plan)],0)
        assert preview.stderr==b'' and json.loads(preview.stdout)==expected_receipt
        assert snapshot(folder)==ready
        patched=run(case['name']+'-patch',[node,str(CLI),'patch',str(source),str(target),str(plan)],0)
        assert patched.stdout==b'' and json.loads(patched.stderr)==expected_receipt
        assert target.read_bytes()==case['expected']
        after=snapshot(folder)
        assert set(after)==set(ready)|{target.name}
        assert all(after[name]==raw for name,raw in ready.items() if name!=target.name)
        received=run(case['name']+'-receive',[node,str(RECEIVER),str(target),'F1','APP_B'],0)
        assert received.stderr==b''
        expected_payload={'handle':'F1','application':'APP_B','data':case['expectedData']}
        assert json.loads(received.stdout)==expected_payload
        assert snapshot(folder)==after
        (folder/'expected.dxf').write_bytes(case['expected'])
        (folder/'received.json').write_bytes(received.stdout)
        positives.append({'case':case['name'],'version':case['version'],'binary':case['binary'],
                          'boundPlan':bound,'selectedIndices':case['indices'],'sourceSHA256':sha(case['source']),
                          'outputSHA256':sha(case['expected']),'wholeOutputEqualsIndependentBytes':True,
                          'expectedReceipt':expected_receipt,'received':expected_payload,
                          'sourceRequestsPlanAndSentinelUnchanged':True,'existingTargetReplaced':bool(index%2)})

    malformed=refusal_sources()+[c for c in extra_cases() if c['error']]
    for index,case in enumerate(malformed):
        folder=output/case['name'];folder.mkdir()
        source,request,target=[folder/n for n in ('source.dxf','requests.json','preserved-output.dxf')]
        source.write_bytes(case['source']);request.write_bytes(encoded(cases()[2]['requests']))
        if index%2: target.write_bytes(b'preserve-existing-output\0\xff')
        before=snapshot(folder)
        run(case['name']+'-make-plan',[node,str(CLI),'make-plan',str(source),str(request)],2,case['error'])
        assert snapshot(folder)==before
        run(case['name']+'-receive',[node,str(RECEIVER),str(source),'F1','APP_B'],2,case['error'])
        assert snapshot(folder)==before

    for case in [c for c in extra_cases() if not c['error']]:
        folder=output/case['name'];folder.mkdir()
        source=folder/'source.dxf';source.write_bytes(case['source'])
        before=snapshot(folder)
        received=run(case['name']+'-receive',[node,str(RECEIVER),str(source),'F1','APP_B'],0)
        assert received.stderr==b'' and json.loads(received.stdout)=={'handle':'F1','application':'APP_B','data':case['expectedData']}
        assert snapshot(folder)==before
        request=folder/'requests.json';request.write_bytes(encoded([cases()[2]['requests'][0]]))
        before=snapshot(folder)
        if case['expectedSelectedIndex'] is None:
            run(case['name']+'-make-plan',[node,str(CLI),'make-plan',str(source),str(request)],2,'XDATA field occurrence not found')
        else:
            formed=run(case['name']+'-make-plan',[node,str(CLI),'make-plan',str(source),str(request)],0)
            expected=copy.deepcopy(cases()[2]['plan'][:1]);expected[0]['index']=case['expectedSelectedIndex']
            assert formed.stderr==b'' and json.loads(formed.stdout)==expected
        assert snapshot(folder)==before

    base=cases()[2]
    original=base['requests'][0]
    guards=[]
    for name,change,error in [
        ('empty-name',{'xdata':''},'invalid XDATA application name'),
        ('long-name',{'xdata':'é'*16},'invalid XDATA application name'),
        ('delimiter-name',{'xdata':'APP_B\n'},'invalid XDATA application name'),
        ('case-sensitive',{'xdata':'app_b'},'XDATA application not found'),
        ('appid-marker',{'code':1001},'invalid XDATA field selector'),
        ('list-marker',{'code':1002},'invalid XDATA field selector'),
        ('ordinary-code',{'code':8},'invalid XDATA field selector'),
        ('code-overflow',{'code':2147483648},'exact Int32'),
        ('fractional-occurrence',{'occurrence':0.5},'exact Int32'),
        ('negative-occurrence',{'occurrence':-1},'invalid XDATA field selector'),
        ('missing-occurrence',{'occurrence':3},'XDATA field occurrence not found'),
        ('replacement-type',{'value':{'integer':'7'}},'ERROR:'),
        ('integer-overflow',{'code':1071,'occurrence':0,'value':{'integer':'2147483648'}},'ERROR:'),
        ('conflicting-scope',{'appdata':'AUDIT'},'mutually exclusive'),
        ('unknown-option',{'unknown':True},'each XDATA request'),
        ('option-type',{'xdata':3},'xdata must be a string'),
    ]:
        row=copy.deepcopy(original);row.update(change);guards.append((name,[row],error))
    guards.append(('duplicate-target',[original,original],'duplicate edit index'))
    for name,requests,error in guards:
        folder=output/name;folder.mkdir()
        source,request,target=[folder/n for n in ('source.dxf','requests.json','preserved-output.dxf')]
        source.write_bytes(base['source']);request.write_bytes(encoded(requests));target.write_bytes(b'preserve\0\xff')
        before=snapshot(folder)
        run(name,[node,str(CLI),'make-plan',str(source),str(request)],2,error)
        assert snapshot(folder)==before

    result={'status':'PASS','realFileHostProcesses':len(rows),'positiveProcesses':sum(r['expectedExitCode']==0 for r in rows),
            'negativeProcesses':sum(r['expectedExitCode']==2 for r in rows),'positiveFullFileChains':positives,
            'malformedSourceCases':len(malformed),'requestGuardCases':len(guards),'additionalScopeModels':2,
            'productWriterUsedForExpectations':False,'oldUTF8AliasRecordSuitesRepeatedHere':False,
            'receivingBoundary':'Project-owned real DXF file receiver using public native APPID scope; no third-party acceptance or registration/schema validation.'}
    (output/'RESULT.json').write_bytes(encoded(result))
    print(json.dumps({'status':'PASS','realFileHostProcesses':len(rows),'fullFileChains':len(positives),
                      'positiveProcesses':result['positiveProcesses'],'negativeProcesses':result['negativeProcesses']}))
    return result


if __name__=='__main__':
    if len(sys.argv)!=2: raise SystemExit('Usage: python tools/test_xdata_workflow.py NEW_EVIDENCE_DIRECTORY')
    verify(Path(sys.argv[1]).resolve())

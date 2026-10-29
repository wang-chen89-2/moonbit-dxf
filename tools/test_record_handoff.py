"""Real producer/receiver file workflow with independent bytes/struct models.

This uses the public Node executables, not mocked exports. Expected records,
spans, hashes and typed values come from record_cases, without a product writer.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
from record_cases import cases, refusal_sources

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'tools/dxf.mjs'
RECEIVER = ROOT / 'examples/record_handoff/receive.mjs'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def encoded(obj): return (json.dumps(obj, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def snapshot(folder):
    result = {}
    for file in folder.iterdir():
        assert file.is_file() and not file.is_symlink(), str(file)
        info = file.stat()
        result[file.name] = {'sha256':sha(file.read_bytes()), 'bytes':info.st_size,
                             'device':str(info.st_dev), 'inode':str(info.st_ino), 'links':info.st_nlink}
    return result


def expected_tags(tags):
    rows=[]
    for code,kind,value in tags:
        if kind == 'text': rows.append([code,'text',value.decode('utf-8',errors='replace')])
        elif kind == 'real': rows.append([code,'bits',str(struct.unpack('<q',struct.pack('<d',float(value)))[0])])
        else: rows.append([code,'int',str(value)])
    return rows


def receipt_for(case):
    return {'requested_handle':case['query'], 'source_sha256':sha(case['source']), 'record_sha256':sha(case['record']),
            'version':case['version'], 'binary':case['binary'], 'offset':case['offset'], 'end_offset':case['end_offset']}


def verify(output):
    node=shutil.which('node'); assert node
    output.mkdir(parents=True)  # Never overwrite old evidence or caller files.
    logs=output/'logs'; logs.mkdir()
    rows, positives, hardlinks=[],[],[]

    def run(label,command,exit_code,error=None):
        proc=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=30)
        number=len(rows)
        stdout,stderr=logs/f'{number:02}.stdout',logs/f'{number:02}.stderr'
        stdout.write_bytes(proc.stdout); stderr.write_bytes(proc.stderr)
        rows.append({'case':label,'command':command,'exitCode':proc.returncode,'expectedExitCode':exit_code,
                     'stdout':str(stdout),'stderr':str(stderr)})
        (output/'COMMANDS.json').write_bytes(encoded(rows))
        assert proc.returncode==exit_code,(label,proc.returncode,proc.stdout,proc.stderr)
        if error is not None:
            assert proc.stdout==b'' and error.encode() in proc.stderr,(label,proc.stderr)
        return proc

    models=cases()
    for index,case in enumerate(models):
        folder=output/case['name']; folder.mkdir()
        source,target,receipt=[folder/name for name in ('source.dxf','attachment.record','receipt.json')]
        source.write_bytes(case['source'])
        (folder/'sentinel.bin').write_bytes(b'preserve\0\xff')
        if index % 2: target.write_bytes(b'independent-old-target\0\xff')
        before=snapshot(folder)
        proc=run(case['name']+'-export',[node,str(CLI),'record',str(source),str(target),case['query']],0)
        expected=receipt_for(case)
        assert proc.stdout==b'' and json.loads(proc.stderr)==expected
        assert target.read_bytes()==case['record']
        assert case['source'][expected['offset']:expected['end_offset']]==target.read_bytes()
        after=snapshot(folder)
        assert set(after)==set(before)|{target.name}
        assert all(after[name]==value for name,value in before.items() if name!=target.name)
        receipt.write_bytes(proc.stderr)
        (output/(case['name']+'-expected.record')).write_bytes(case['record'])
        before_receive=snapshot(folder)
        received=run(case['name']+'-receive',[node,str(RECEIVER),str(source),str(target),str(receipt)],0)
        index_entry=json.loads(received.stdout)
        assert received.stderr==b'' and snapshot(folder)==before_receive
        assert index_entry=={'verified':True,**expected,'record_kind':case['tags'][0][2].decode('ascii'),
                             'tag_count':case['tag_count'],'tags':expected_tags(case['tags'])},index_entry
        (output/(case['name']+'-index.json')).write_bytes(received.stdout)
        positives.append({'case':case['name'],'receipt':expected,'sourceBytes':len(case['source']),
                          'recordBytes':len(case['record']),'typedTags':expected_tags(case['tags']),
                          'exactBytesAndSpan':True,'realReceivingFileIndex':True,'sourceAndReceiptUnchanged':True,
                          'structurallyCompleteDrawing':case['structurallyCompleteDrawing']})

    for index,case in enumerate(refusal_sources()):
        folder=output/case['name']; folder.mkdir()
        source,target=folder/'source.dxf',folder/'target.record'
        source.write_bytes(case['source'])
        if index % 2: target.write_bytes(b'preserve-existing-target\0\xff')
        before=snapshot(folder)
        run(case['name'],[node,str(CLI),'record',str(source),str(target),case['query']],2,case['error'])
        assert snapshot(folder)==before

    base=models[0]
    for mode in ('same-path','hardlink'):
        folder=output/('alias-'+mode); folder.mkdir()
        source=folder/'source.dxf'; source.write_bytes(base['source'])
        target=source if mode=='same-path' else folder/'alias.record'
        if mode=='hardlink':
            os.link(source,target)
            assert os.path.samefile(source,target) and target.stat().st_ino!=0 and target.stat().st_nlink>=2
            hardlinks.append({'source':str(source),'target':str(target),'samefile':True,
                              'inode':str(target.stat().st_ino),'links':target.stat().st_nlink})
            (output/'HARDLINKS.json').write_bytes(encoded(hardlinks))
        before=snapshot(folder)
        run('alias-'+mode,[node,str(CLI),'record',str(source),str(target),'AB'],2,'Choose a separate output path')
        assert snapshot(folder)==before

    folder=output/'late-io-missing-parent'; folder.mkdir()
    source=folder/'source.dxf'; source.write_bytes(base['source'])
    before=snapshot(folder)
    run('late-io-missing-parent',[node,str(CLI),'record',str(source),str(folder/'absent'/'target.record'),'AB'],2,'ENOENT')
    assert snapshot(folder)==before

    negatives=[
        ('stale-source','Source hash mismatch'),('corrupt-record','Record hash mismatch'),
        ('wrong-record-hash','Record hash mismatch'),('rehashed-nonmember','Record is not the source span'),
        ('negative-span','Invalid record receipt span'),('fractional-span','Invalid record receipt span'),
        ('inconsistent-length','Invalid record receipt span'),('out-of-range','Invalid record receipt span'),
        ('wrong-identity','Record does not match the requested owning handle'),('wrong-profile','Source profile mismatch'),
        ('invalid-receipt-utf8','Record receipt must be valid UTF-8'),('missing-receipt-field','Invalid record receipt fields'),
    ]
    for name,error in negatives:
        folder=output/('receiver-'+name); folder.mkdir()
        source,target,receipt=[folder/file for file in ('source.dxf','attachment.record','receipt.json')]
        data=receipt_for(base); source_raw=base['source']; record_raw=base['record']
        if name=='stale-source': source_raw+=b'\n'
        if name in ('corrupt-record','rehashed-nonmember'):
            record_raw=record_raw.replace(b'LINE',b'LINA',1)
            if name=='rehashed-nonmember': data['record_sha256']=sha(record_raw)
        if name=='wrong-record-hash': data['record_sha256']='0'*64
        if name=='negative-span': data['offset']=-1
        if name=='fractional-span': data['offset']=69.5
        if name=='inconsistent-length': data['end_offset']-=1
        if name=='out-of-range': data['end_offset']=len(source_raw)+1
        if name=='wrong-identity': data['requested_handle']='AC'
        if name=='wrong-profile': data['version']='AC1032'
        if name=='missing-receipt-field': del data['record_sha256']
        source.write_bytes(source_raw); target.write_bytes(record_raw)
        receipt.write_bytes(b'\xff' if name=='invalid-receipt-utf8' else encoded(data))
        before=snapshot(folder)
        run('receiver-'+name,[node,str(RECEIVER),str(source),str(target),str(receipt)],2,error)
        assert snapshot(folder)==before

    assert len(rows)==41 and len(positives)==9 and len(hardlinks)==1
    result={'status':'PASS','platform':sys.platform,'pythonVersion':sys.version.split()[0],
            'nodeVersion':subprocess.check_output([node,'--version'],text=True).strip(),
            'realFileHostProcesses':len(rows),'positiveProcesses':18,'negativeProcesses':23,
            'positiveModels':positives,'realHardlinksVerified':len(hardlinks),
            'newAndExistingTargets':True,'receiverRejectsStaleCorruptSpanAndIdentity':True,
            'sourceAndReceivingInputsUnchanged':True,
            'oracle':'Explicit frozen tag/byte lists; Python struct for Binary/IEEE754, independently specified ranges and SHA256',
            'productWriterUsedForExpectations':False,
            'scope':'Physical-record/source-membership handoff, not complete logical entities or standalone CAD acceptance. Missing-parent IO refusal is checked; no general atomicity/rollback promise.'}
    (output/'RESULT.json').write_bytes(encoded(result))
    print(json.dumps({'status':'PASS','realFileHostProcesses':41,'positiveProcesses':18,'negativeProcesses':23,
                      'positiveModels':9,'realHardlinksVerified':1}))


if __name__=='__main__':
    if len(sys.argv)!=2: raise SystemExit('Usage: python -B tools/test_record_handoff.py NEW_OUTPUT_DIRECTORY')
    verify(Path(sys.argv[1]).resolve())

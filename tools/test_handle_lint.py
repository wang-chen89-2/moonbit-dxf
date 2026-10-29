"""File-intake regression for the existing DuplicateHandle diagnostic contract.

Frozen original bytes/struct inputs and explicit expected offsets are independent
of the product. Run only against a newly built native bridge; keep all raw streams.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
from handle_lint_cases import cases

ROOT=Path(__file__).resolve().parents[1]
CLI=ROOT/'tools/dxf.mjs'


def sha(raw):return hashlib.sha256(raw).hexdigest()
def encoded(obj):return (json.dumps(obj,indent=2)+'\n').encode('utf-8')


def verify(output):
    node=shutil.which('node');assert node
    output.mkdir(parents=True)  # Never overwrite previous evidence or caller data.
    logs=output/'logs';logs.mkdir();rows=[];observations=[]
    for case in cases():
        folder=output/case['name'];folder.mkdir()
        source=folder/'source.dxf';source.write_bytes(case['source'])
        sentinel=folder/'sentinel.bin';sentinel.write_bytes(b'read-only-intake\0\xff')
        before={p.name:p.read_bytes() for p in folder.iterdir()}
        command=[node,str(CLI),'lint',str(source)]
        proc=subprocess.run(command,cwd=ROOT,capture_output=True,timeout=30)
        stdout,stderr=logs/(case['name']+'.stdout'),logs/(case['name']+'.stderr')
        stdout.write_bytes(proc.stdout);stderr.write_bytes(proc.stderr)
        row={'case':case['name'],'command':command,'exitCode':proc.returncode,'expectedExitCode':case['exitCode'],
             'stdout':str(stdout),'stderr':str(stderr)}
        rows.append(row);(output/'COMMANDS.json').write_bytes(encoded(rows))
        assert proc.returncode==case['exitCode'] and proc.stderr==b'',(row,proc.stdout,proc.stderr)
        report=json.loads(proc.stdout)
        assert set(report)=={'version','complete','tag_count','diagnostics','details'},report
        assert report=={'version':'AC1032','complete':True,'tag_count':case['tagCount'],
                        'diagnostics':case['diagnostics'],'details':case['details']},(case['name'],report)
        assert {p.name:p.read_bytes() for p in folder.iterdir()}==before
        # An intake's actual process result now blocks colliding owners; it still
        # accepts the distinct/private control without changing CLI JSON or flags.
        observations.append({'case':case['name'],'decision':'reject' if proc.returncode==1 else 'accept',
                             'sourceSHA256':sha(source.read_bytes()),'sourceBytes':source.stat().st_size,
                             'originalInputAndDirectoryUnchanged':True,'rawReportSHA256':sha(proc.stdout),
                             'diagnosticOffsets':[d['offset'] for d in report['details']]})
    result={'status':'PASS','realFileHostProcesses':len(rows),'rejectedInputs':sum(r['exitCode']==1 for r in rows),
            'acceptedControls':sum(r['exitCode']==0 for r in rows),'actualFileIntake':observations,
            'productParserOrWriterUsedForExpectations':False,'newPublicApiOrReportFormat':False,
            'noThirdPartyCADAcceptanceClaim':True,'timestampOrFileIdPreservationClaimed':False}
    (output/'RESULT.json').write_bytes(encoded(result))
    print(json.dumps({'status':'PASS','realFileHostProcesses':len(rows),
                      'rejectedInputs':result['rejectedInputs'],'acceptedControls':result['acceptedControls']}))
    return result


if __name__=='__main__':
    if len(sys.argv)!=2:raise SystemExit('Usage: python tools/test_handle_lint.py NEW_EVIDENCE_DIRECTORY')
    verify(Path(sys.argv[1]).resolve())

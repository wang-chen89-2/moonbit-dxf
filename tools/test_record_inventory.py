"""Receive real inventory/index-edit files against independent full byte models.

Expected fields and splice bytes are declared in record_inventory_cases; no
product decoder/writer or third-party implementation generates expectations.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
from record_inventory_cases import cases, refusal_cases

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'tools/dxf.mjs'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def encoded(value): return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()
def snapshot(folder):
    return {p.name: {'sha256': sha(p.read_bytes()), 'bytes': p.stat().st_size,
                     'inode': str(p.stat().st_ino), 'links': p.stat().st_nlink}
            for p in folder.iterdir() if p.is_file()}


def expected_core(case):
    details = []
    if case['kind'] == 'duplicate':
        index = case['report']['records'][9]['start_tag'] + 1
        assert case['bodyTags'][index][0] == 5
        details = [{'code': 'DuplicateHandle', 'offset': case['tagSpans'][index][0],
                    'severity': 'error', 'message': 'duplicate handle 000a1'}]
    return {'version': case['version'], 'complete': True, 'tags': case['typedTags'],
            'diagnostics': [d['code'] for d in details], 'details': details,
            'tag_count': len(case['typedTags'])}


def verify(output):
    node = shutil.which('node'); assert node
    output.mkdir(parents=True)  # Evidence directories must be fresh.
    logs = output / 'logs'; logs.mkdir()
    rows, observed, receiving = [], [], []

    def run(label, args, expected_exit=0, error=None):
        command = [node, str(CLI), *map(str, args)]
        proc = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
        number = len(rows)
        stdout, stderr = logs / f'{number:02d}.stdout', logs / f'{number:02d}.stderr'
        stdout.write_bytes(proc.stdout); stderr.write_bytes(proc.stderr)
        rows.append({'case': label, 'command': command, 'exitCode': proc.returncode,
                     'expectedExitCode': expected_exit, 'stdout': str(stdout), 'stderr': str(stderr)})
        (output / 'COMMANDS.json').write_bytes(encoded(rows))
        assert proc.returncode == expected_exit, (label, proc.returncode, proc.stdout, proc.stderr)
        if error is not None:
            assert proc.stdout == b'' and error.encode() in proc.stderr, (label, proc.stderr)
        return proc

    for case in cases():
        folder = output / case['name']; folder.mkdir()
        source, saved = folder / 'source.dxf', folder / 'saved.dxf'
        source.write_bytes(case['source'])
        (folder / 'sentinel.bin').write_bytes(b'keep-original\0\xff')
        before = snapshot(folder)
        report = run(case['name'] + '-records', ['records', source])
        assert report.stderr == b'' and json.loads(report.stdout) == case['report']
        assert snapshot(folder) == before
        tags_proc = run(case['name'] + '-tags', ['tags', source])
        expected_tags = expected_core(case)
        assert tags_proc.stderr == b'' and json.loads(tags_proc.stdout) == expected_tags
        assert snapshot(folder) == before
        saved_proc = run(case['name'] + '-save', ['save', source, saved])
        assert saved_proc.stdout == saved_proc.stderr == b'' and saved.read_bytes() == case['source']
        after = snapshot(folder)
        assert set(after) == set(before) | {'saved.dxf'}
        assert all(after[name] == value for name, value in before.items())
        observed.append({'case': case['name'], 'actualReport': json.loads(report.stdout),
                         'actualCoreReport': json.loads(tags_proc.stdout),
                         'fullSourceSHA256': sha(source.read_bytes()), 'saveExact': True,
                         'readOnlyInventory': True, 'allDeclaredRawSlicesExact':
                         [source.read_bytes()[r['offset']:r['end_offset']].hex() for r in case['report']['records']] == case['recordBytes']})
        if case['kind'] == 'duplicate':
            before = snapshot(folder)
            run(case['name'] + '-old-ambiguous-record', ['record', source, folder / 'refused.record', 'A1'], 2, 'ambiguous record handle')
            assert snapshot(folder) == before
        if case['kind'] != 'legacy':
            continue

        before = snapshot(folder)
        inventory, tags = json.loads(report.stdout), json.loads(tags_proc.stdout)['tags']
        line = [r for r in inventory['records'] if r['kind_hex'] == b'LINE'.hex()]
        assert len(line) == 1 and line[0]['handle_hex'] is None
        indices = [i for i in range(line[0]['start_tag'], line[0]['end_tag']) if tags[i][0] == 10]
        assert indices == [case['targetIndex']]
        assert snapshot(folder) == before
        run(case['name'] + '-old-missing-record', ['record', source, folder / 'refused.record', 'A1'], 2, 'record handle not found')
        assert snapshot(folder) == before

        plan, bound, edited = folder / 'plan.json', folder / 'bound.json', folder / 'edited.dxf'
        # The new inventory supplies the index; the existing typed plan format
        # supplies exact expected/value bits from the independent specification.
        plan_value = [{'index': indices[0], **{k: v for k, v in case['plan'][0].items() if k != 'index'}}]
        assert plan_value == case['plan']
        plan.write_bytes(encoded(plan_value))
        before = snapshot(folder)
        bind = run(case['name'] + '-bind', ['bind-plan', source, plan])
        assert bind.stderr == b'' and json.loads(bind.stdout) == case['boundPlan']
        assert snapshot(folder) == before
        bound.write_bytes(bind.stdout)
        before = snapshot(folder)
        preview = run(case['name'] + '-preview', ['patch-plan', source, bound])
        assert preview.stderr == b'' and json.loads(preview.stdout) == case['receipt']
        assert snapshot(folder) == before
        run(case['name'] + '-source-destination-refusal', ['patch', source, source, bound], 2, 'Choose a separate output path')
        assert snapshot(folder) == before
        run(case['name'] + '-plan-destination-refusal', ['patch', source, bound, bound], 2, 'Choose a separate output path')
        assert snapshot(folder) == before
        patch = run(case['name'] + '-patch', ['patch', source, edited, bound])
        assert patch.stdout == b'' and json.loads(patch.stderr) == case['receipt']
        assert edited.read_bytes() == case['edited']
        after = snapshot(folder)
        assert set(after) == set(before) | {'edited.dxf'}
        assert all(after[name] == value for name, value in before.items())
        before = snapshot(folder)
        received = run(case['name'] + '-receive-tags', ['tags', edited])
        assert received.stderr == b''
        assert json.loads(received.stdout) == {**expected_tags, 'tags': case['editedTypedTags']}
        received_inventory = run(case['name'] + '-receive-records', ['records', edited])
        assert received_inventory.stderr == b'' and json.loads(received_inventory.stdout) == case['editedReport']
        assert snapshot(folder) == before
        receiving.append({'case': case['name'], 'selectedIndex': indices[0], 'plan': plan_value,
                          'boundPlan': json.loads(bind.stdout), 'receipt': json.loads(patch.stderr),
                          'fullExpectedOutputSHA256': sha(case['edited']), 'fullOutputEqual': True,
                          'receivedTypedTags': json.loads(received.stdout),
                          'receivedInventory': json.loads(received_inventory.stdout),
                          'sourcePlanAndSentinelUnchanged': True})

    for case in refusal_cases():
        folder = output / case['name']; folder.mkdir()
        source, saved = folder / 'source.dxf', folder / 'saved.dxf'
        source.write_bytes(case['source']); (folder / 'sentinel.bin').write_bytes(b'keep\0\xff')
        before = snapshot(folder)
        run(case['name'] + '-records-refusal', ['records', source], 2, case['error'])
        assert snapshot(folder) == before
        tags = run(case['name'] + '-typed-refusal-reason', ['tags', source])
        data = json.loads(tags.stdout)
        assert tags.stderr == b'' and data['complete'] == case['complete']
        assert data['tags'] == case['decodedTypedTags']
        assert any(all(d[key] == value for key, value in case['primaryDiagnostic'].items()) for d in data['details'])
        if case['isolatedReason']:
            assert 'InvalidTag' not in data['diagnostics']
        if case['name'] == 'original-compound-wire':
            assert 'WireVersionMismatch' in data['diagnostics']
        assert snapshot(folder) == before
        proc = run(case['name'] + '-old-save', ['save', source, saved])
        assert proc.stdout == proc.stderr == b'' and saved.read_bytes() == case['source']
        after = snapshot(folder)
        assert set(after) == set(before) | {'saved.dxf'}
        assert all(after[name] == value for name, value in before.items())

    folder = output / 'usage'; folder.mkdir()
    source = folder / 'source.dxf'; source.write_bytes(cases()[0]['source'])
    before = snapshot(folder)
    run('records-extra-argument', ['records', source, folder / 'must-not-exist'], 2, 'node tools/dxf.mjs')
    assert snapshot(folder) == before
    assert len(rows) == 76 and len(observed) == 10 and len(receiving) == 2
    result = {'status': 'PASS', 'realFileHostProcesses': len(rows), 'independentSourceModels': len(observed),
              'fullInventoryAndSaveChecks': observed, 'completeHandleFreeReceivingChains': receiving,
              'allSourceGuardsAndUsageRefuseWithoutWrites': True, 'oldDuplicateLookupStillAmbiguous': True,
              'allOriginalIllegalVectorsRetained': True, 'isolatedWireAndTruncationReachedExpectedReason': True,
              'sourceAndPlanDestinationProtections': True, 'independentRefusalControls': 9,
              'expectedDataFromProductWriter': False,
              'scope': 'Physical decoded record inventory and existing index-edit receiving; no CAD semantic validation or unique identity claim.'}
    (output / 'RESULT.json').write_bytes(encoded(result))
    print(json.dumps({'status': 'PASS', 'realFileHostProcesses': len(rows), 'independentSourceModels': 10,
                      'completeHandleFreeReceivingChains': 2}))


if __name__ == '__main__':
    if len(sys.argv) != 2: raise SystemExit('Usage: python -B tools/test_record_inventory.py NEW_OUTPUT_DIRECTORY')
    verify(Path(sys.argv[1]).resolve())

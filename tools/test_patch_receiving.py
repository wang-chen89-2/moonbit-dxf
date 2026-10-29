"""Real whole-file producer/receiver chains with independently declared bytes.

No product parser/writer creates expected output or receipt data. The product
writer is exercised as an actual producer, then compared against complete frozen
bytes before the new public read-only receiving command is invoked.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys
from patch_receiving_cases import cases, identity_cases, refusal_cases, encoded

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'tools/dxf.mjs'
def sha(raw): return hashlib.sha256(raw).hexdigest()
def snapshot(folder):
    return {p.name: {'bytes': p.stat().st_size, 'sha256': sha(p.read_bytes()),
                     'inode': str(p.stat().st_ino), 'device': str(p.stat().st_dev), 'links': p.stat().st_nlink}
            for p in folder.iterdir() if p.is_file()}


def verify(output):
    node = shutil.which('node'); assert node
    output.mkdir(parents=True)
    logs = output / 'logs'; logs.mkdir()
    rows, chains, identities, rejected, aliases = [], [], [], [], []

    def run(label, args, expected_exit=0, error=None):
        command = [node, str(CLI), *map(str, args)]
        proc = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
        stdout, stderr = logs / f'{len(rows):02d}.stdout', logs / f'{len(rows):02d}.stderr'
        stdout.write_bytes(proc.stdout); stderr.write_bytes(proc.stderr)
        rows.append({'case': label, 'command': command, 'exitCode': proc.returncode, 'expectedExitCode': expected_exit,
                     'stdout': str(stdout), 'stderr': str(stderr)})
        (output / 'COMMANDS.json').write_bytes(encoded(rows))
        assert proc.returncode == expected_exit, (label, proc.returncode, proc.stdout, proc.stderr)
        if error is not None:
            assert proc.stdout == b'' and error.encode() in proc.stderr, (label, proc.stdout, proc.stderr)
        return proc

    for case in cases():
        folder = output / case['name']; folder.mkdir()
        source, plan, bound, received, saved = [folder / name for name in ('source.dxf', 'plan.json', 'bound.json', 'received.dxf', 'saved.dxf')]
        source.write_bytes(case['source']); plan.write_bytes(encoded(case['plan']))
        (folder / 'sentinel.bin').write_bytes(b'keep\0\xff')
        before = snapshot(folder)
        bind = run(case['name'] + '-bind', ['bind-plan', source, plan])
        assert bind.stderr == b'' and json.loads(bind.stdout) == case['boundPlan'] and snapshot(folder) == before
        bound.write_bytes(bind.stdout); before = snapshot(folder)
        preview = run(case['name'] + '-preview', ['patch-plan', source, bound])
        assert preview.stderr == b'' and json.loads(preview.stdout) == case['receipt'] and snapshot(folder) == before
        write = run(case['name'] + '-write', ['patch', source, received, bound])
        assert write.stdout == b'' and json.loads(write.stderr) == case['receipt'] and received.read_bytes() == case['output']
        after = snapshot(folder)
        assert set(after) == set(before) | {received.name} and all(after[k] == v for k, v in before.items())
        before = snapshot(folder)
        verify_result = run(case['name'] + '-receive', ['verify-patch', source, received, bound])
        assert verify_result.stderr == b'' and json.loads(verify_result.stdout) == case['verification'] and snapshot(folder) == before
        tags = run(case['name'] + '-received-tags', ['tags', received])
        assert tags.stderr == b'' and json.loads(tags.stdout) == case['outputCore'] and snapshot(folder) == before
        save = run(case['name'] + '-save-original', ['save', source, saved])
        assert save.stdout == save.stderr == b'' and saved.read_bytes() == case['source']
        chains.append({'case': case['name'], 'sourceSHA256': sha(source.read_bytes()), 'outputSHA256': sha(received.read_bytes()),
                       'boundPlan': json.loads(bind.stdout), 'preview': json.loads(preview.stdout), 'writeReceipt': json.loads(write.stderr),
                       'verification': json.loads(verify_result.stdout), 'receivedTags': json.loads(tags.stdout),
                       'wholeIndependentOutputEqual': True, 'originalSaveExact': True, 'verificationInputsUnchanged': True})

    for binary in (False, True):
        case = next(c for c in cases() if c['version'] == 'AC1015' and c['binary'] == binary)
        folder = output / ('old-array-' + case['name']); folder.mkdir()
        source, plan, bound, received = [folder / name for name in ('source.dxf', 'plan.json', 'bound.json', 'received.dxf')]
        source.write_bytes(case['source']); plan.write_bytes(encoded(case['plan'])); bound.write_bytes(encoded(case['boundPlan']))
        proc = run(case['name'] + '-old-array-write', ['patch', source, received, plan])
        expected_receipt = {k: v for k, v in case['receipt'].items() if k != 'source_sha256'}
        assert proc.stdout == b'' and json.loads(proc.stderr) == expected_receipt and received.read_bytes() == case['output']
        before = snapshot(folder)
        proc = run(case['name'] + '-old-array-output-receive', ['verify-patch', source, received, bound])
        assert proc.stderr == b'' and json.loads(proc.stdout) == case['verification'] and snapshot(folder) == before
        for target, label in ((source, 'source'), (bound, 'plan')):
            run(case['name'] + '-old-' + label + '-destination', ['patch', source, target, bound], 2, 'Choose a separate output path')
            assert snapshot(folder) == before
        altered = folder / 'altered-source.dxf'; altered.write_bytes(case['source'].replace(b'untouched', b'Untouched', 1))
        assert altered.read_bytes() != source.read_bytes(); before = snapshot(folder)
        run(case['name'] + '-changed-unselected-source', ['verify-patch', altered, received, bound], 2, 'Input SHA-256 does not match the source-bound plan')
        assert snapshot(folder) == before

    for case in identity_cases():
        folder = output / case['name']; folder.mkdir()
        source, bound = folder / 'source.dxf', folder / 'bound.json'
        source.write_bytes(case['source']); bound.write_bytes(encoded(case['boundPlan'])); before = snapshot(folder)
        # Same-file read-only verification is intentional for an empty plan.
        proc = run(case['name'], ['verify-patch', source, source, bound])
        assert proc.stderr == b'' and json.loads(proc.stdout) == case['verification'] and snapshot(folder) == before
        identities.append({'case': case['name'], 'report': json.loads(proc.stdout), 'onlyByteIdentityClaimed': True})
        if case['name'] in ('noop-ascii', 'noop-binary'):
            linked = folder / 'received-hardlink.dxf'; os.link(source, linked)
            assert os.path.samefile(source, linked) and source.stat().st_nlink >= 2
            before = snapshot(folder)
            proc = run(case['name'] + '-hardlink', ['verify-patch', source, linked, bound])
            assert proc.stderr == b'' and json.loads(proc.stdout) == case['verification'] and snapshot(folder) == before
            aliases.append({'case': case['name'], 'samefile': True, 'links': source.stat().st_nlink, 'noWrites': True})

    for case in refusal_cases():
        folder = output / case['name']; folder.mkdir()
        source, received, plan = [folder / name for name in ('source.dxf', 'received.dxf', 'plan.json')]
        source.write_bytes(case['source']); received.write_bytes(case['received']); plan.write_bytes(case['planBytes'])
        (folder / 'sentinel.bin').write_bytes(b'keep\0\xff'); before = snapshot(folder)
        run(case['name'], ['verify-patch', source, received, plan], 2, case['error'])
        assert snapshot(folder) == before
        rejected.append({'case': case['name'], 'sourceSHA256': sha(source.read_bytes()), 'receivedSHA256': sha(received.read_bytes()),
                         'planSHA256': sha(plan.read_bytes()), 'error': case['error'], 'noWritesOrSuccessStdout': True})

    case = cases()[0]; folder = output / 'io-and-usage'; folder.mkdir()
    source, received, plan = [folder / name for name in ('source.dxf', 'received.dxf', 'bound.json')]
    source.write_bytes(case['source']); received.write_bytes(case['output']); plan.write_bytes(encoded(case['boundPlan'])); before = snapshot(folder)
    for position, name in ((0, 'source'), (1, 'received'), (2, 'plan')):
        args = [source, received, plan]; args[position] = folder / 'missing-file'
        run('missing-' + name, ['verify-patch', *args], 2, 'ENOENT'); assert snapshot(folder) == before
    run('missing-verify-arguments', ['verify-patch', source], 2, 'node tools/dxf.mjs'); assert snapshot(folder) == before
    run('extra-verify-argument', ['verify-patch', source, received, plan, folder / 'must-not-exist'], 2, 'node tools/dxf.mjs'); assert snapshot(folder) == before
    assert len(rows) == 77 and len(chains) == 6 and len(identities) == 4 and len(rejected) == 20 and len(aliases) == 2
    result = {'status': 'PASS', 'realFileHostProcesses': len(rows), 'wholeFileReceivingChains': chains, 'emptyPlanIdentityControls': identities,
              'refusals': rejected, 'readOnlyHardlinks': aliases, 'oldArrayAndBoundProtocolsAndDestinationProtectionsPreserved': True,
              'productUsedForExpectedData': False, 'allActualReceivedAndOriginalBytesComparedWithoutNormalization': True,
              'scope': 'Whole-file equality to existing source-bound edit result; not CAD semantics, writer-independent runtime proof, signature or durability.'}
    (output / 'RESULT.json').write_bytes(encoded(result))
    print(json.dumps({'status': 'PASS', 'realFileHostProcesses': len(rows), 'wholeFileReceivingChains': 6, 'emptyPlanIdentityControls': 4, 'refusalControls': 20, 'realReadOnlyHardlinks': 2}))


if __name__ == '__main__':
    if len(sys.argv) != 2: raise SystemExit('Usage: python -B tools/test_patch_receiving.py NEW_OUTPUT_DIRECTORY')
    verify(Path(sys.argv[1]).resolve())

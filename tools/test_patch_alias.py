"""Exercise patch's input-identity protection using real files and hardlinks.

All links point only to fixture/plan copies inside new case directories. Python's
native samefile/stat calls establish identity independently of the Node CLI.
Unsupported hardlink creation is a failure, never a skipped or simulated test.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'examples' / 'handle_plan' / 'input.dxf'
CLI = ROOT / 'tools' / 'dxf.mjs'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2) + '\n').encode('utf-8')


def snapshot(folder):
    result = {}
    for path in folder.iterdir():
        assert path.is_file() and not path.is_symlink(), str(path)
        info = path.stat()
        assert stat.S_ISREG(info.st_mode)
        result[path.name] = {'bytesHex': path.read_bytes().hex(), 'device': str(info.st_dev),
                             'inode': str(info.st_ino), 'links': info.st_nlink}
    return result


def verify(output):
    original = FIXTURE.read_bytes()
    old_tag, new_tag = b'8\nold\n', b'8\nalias-safe\n'
    assert original.count(old_tag) == 1
    offset = original.index(old_tag)
    expected = original[:offset] + new_tag + original[offset + len(old_tag):]
    source_hash = digest(original)
    edits = [{'index': 12, 'code': 8, 'expected': {'text': 'old'}, 'value': {'text': 'alias-safe'}}]
    expected_receipt = {'source_bytes': len(original), 'output_bytes': len(expected), 'changes': [{
        'index': 12, 'code': 8, 'offset': offset, 'end_offset': offset + len(old_tag),
        'before_hex': old_tag.hex(), 'after_hex': new_tag.hex()}]}
    node = shutil.which('node')
    assert node, 'Node is required'
    output.mkdir(parents=True)  # Never overwrite earlier evidence or user files.
    (output / 'logs').mkdir()
    (output / 'original.dxf').write_bytes(original)
    (output / 'expected-patched.dxf').write_bytes(expected)
    commands, hardlinks = [], []
    for form in ('array', 'bound'):
        plan_data = edits if form == 'array' else {'format': 'dxf-source-plan-v1', 'source_sha256': source_hash, 'edits': edits}
        for mode in ('source-same-path', 'plan-same-path', 'source-hardlink', 'plan-hardlink', 'new-target', 'existing-target'):
            label = form + '-' + mode
            folder = output / label
            folder.mkdir()
            source, plan = folder / 'input.dxf', folder / 'plan.json'
            source.write_bytes(original)
            plan.write_bytes(encoded(plan_data))
            assert not os.path.samefile(source, FIXTURE), 'Never link the project fixture'
            assert not os.path.samefile(source, plan)
            target = folder / 'output.dxf'
            negative = mode not in ('new-target', 'existing-target')
            if mode.endswith('same-path'):
                target = source if mode.startswith('source-') else plan
                assert os.path.samefile(target, source if mode.startswith('source-') else plan)
            elif mode.endswith('hardlink'):
                linked_input = source if mode.startswith('source-') else plan
                os.link(linked_input, target)
                assert target.resolve() != linked_input.resolve(), 'Hardlinks must have different pathnames'
                assert os.path.samefile(linked_input, target)
                assert linked_input.stat().st_nlink >= 2 and target.stat().st_nlink >= 2
                assert target.stat().st_ino != 0, 'A nonzero actual file identity is required'
                hardlinks.append({'case': label, 'input': str(linked_input), 'output': str(target),
                                  'samefile': True, 'differentPathnames': True,
                                  'device': str(target.stat().st_dev), 'inode': str(target.stat().st_ino),
                                  'links': target.stat().st_nlink})
            elif mode == 'existing-target':
                target.write_bytes(b'independent-existing-output\x00\xff')
                assert not os.path.samefile(source, target) and not os.path.samefile(plan, target)
            else:
                assert not target.exists()
            before = snapshot(folder)
            # Store the real hardlink preconditions before invoking a possible writer.
            (output / 'HARDLINKS.json').write_bytes(encoded(hardlinks))
            command = [node, str(CLI), 'patch', str(source), str(target), str(plan)]
            proc = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
            number = len(commands)
            stdout, stderr = output / 'logs' / f'{number:02d}.stdout', output / 'logs' / f'{number:02d}.stderr'
            stdout.write_bytes(proc.stdout)
            stderr.write_bytes(proc.stderr)
            after = snapshot(folder)
            checks = {'exitCode': proc.returncode == (2 if negative else 0), 'stdoutEmpty': proc.stdout == b''}
            if negative:
                checks.update(identityError=b'Choose a separate output path' in proc.stderr,
                              directoryEntriesBytesAndIdentitiesUnchanged=after == before)
            else:
                names = set(before) | {target.name}
                checks['onlyExpectedDirectoryEntries'] = set(after) == names
                checks['allInputsUnchanged'] = all(after[name] == value for name, value in before.items() if name != target.name)
                checks['exactIndependentOutputBytes'] = target.read_bytes() == expected
                checks['outputIndependentOfBothInputs'] = not os.path.samefile(target, source) and not os.path.samefile(target, plan)
                receipt = {**expected_receipt, **({'source_sha256': source_hash} if form == 'bound' else {})}
                checks['exactIndependentReceipt'] = json.loads(proc.stderr) == receipt if proc.returncode == 0 else False
            commands.append({'case': label, 'command': command, 'exitCode': proc.returncode,
                             'expectedExitCode': 2 if negative else 0, 'stdout': str(stdout), 'stderr': str(stderr),
                             'before': before, 'after': after, 'checks': checks})
            (output / 'COMMANDS.json').write_bytes(encoded(commands))
            assert all(checks.values()), (label, checks, proc.stderr.decode('utf-8', errors='replace'))
    assert len(commands) == 12 and len(hardlinks) == 4
    assert digest(FIXTURE.read_bytes()) == source_hash
    summary = {'status': 'PASS', 'platform': sys.platform, 'osName': os.name,
               'nodeVersion': subprocess.check_output([node, '--version'], text=True).strip(),
               'pythonVersion': sys.version.split()[0], 'fixture': str(FIXTURE.relative_to(ROOT)), 'fixtureSha256': source_hash,
               'negativeProcesses': 8, 'positiveProcesses': 4, 'realHardlinksCreatedAndVerified': len(hardlinks),
               'hardlinksWereRequiredNotSkipped': True, 'bothInputIdentitiesProtected': True,
               'samePathAndDifferentPathSameFileChecked': True, 'independentNewAndExistingOutputsSucceeded': True,
               'expectedOutputSha256': digest(expected), 'projectFixtureUnchanged': True,
               'oracle': 'Native os.link/os.path.samefile/stat plus fixed single-span bytes and known tag index12',
               'scope': 'Directory entries, file bytes, identities and link counts; read-access timestamps are not asserted'}
    (output / 'RESULT.json').write_bytes(encoded(summary))
    print(json.dumps(summary))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python -B tools/test_patch_alias.py NEW_OUTPUT_DIRECTORY')
    verify(Path(sys.argv[1]).resolve())

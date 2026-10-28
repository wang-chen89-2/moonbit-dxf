"""Consume repair-preview through real files and the public Node CLI.

The small ASCII/Binary models, retained sections, repaired bytes and byte-loss
counts are specified here with Python bytes/struct, independently of MoonBit.
No native writer or repair report is used to generate an expected output.
"""
from pathlib import Path
import hashlib
import json
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'tools/dxf.mjs'
SIGNATURE = b'AutoCAD Binary DXF\r\n\x1a\x00'


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def ascii_bytes(tags):
    return b''.join(str(code).encode('ascii') + b'\n' + value + b'\n' for code, value in tags)


def binary_body(tags):
    # These models deliberately contain only text tags in the modern 2-byte wire.
    assert all(code in (0, 1, 2, 8, 9) and b'\0' not in value for code, value in tags)
    return b''.join(struct.pack('<H', code) + value + b'\0' for code, value in tags)


def read_tags(raw, binary):
    if not binary:
        lines = raw.split(b'\n')
        assert lines.pop() == b'' and len(lines) % 2 == 0
        return [(int(lines[i]), lines[i + 1]) for i in range(0, len(lines), 2)]
    assert raw.startswith(SIGNATURE)
    offset, tags = len(SIGNATURE), []
    while offset < len(raw):
        code, = struct.unpack_from('<H', raw, offset)
        assert code in (0, 1, 2, 8, 9)
        start = offset + 2
        end = raw.index(b'\0', start)
        tags.append((code, raw[start:end]))
        offset = end + 1
    assert offset == len(raw)
    return tags


def header(version, name):
    return [(0, b'SECTION'), (2, b'HEADER'), (9, b'$ACADVER'), (1, version),
            (9, b'$PROJECTNAME'), (1, name), (0, b'ENDSEC')]


def snapshot(folder):
    result = {}
    for path in folder.iterdir():
        assert path.is_file() and not path.is_symlink(), str(path)
        info = path.stat()
        result[path.name] = {'sha256': digest(path.read_bytes()), 'bytes': info.st_size,
                             'device': str(info.st_dev), 'inode': str(info.st_ino), 'links': info.st_nlink}
    return result


def verify(output):
    node = shutil.which('node')
    assert node, 'Node is required'
    output.mkdir(parents=True)  # Refuse to overwrite earlier evidence or user files.
    logs = output / 'logs'
    logs.mkdir()
    commands, cases = [], []

    def run(label, arguments, expected_exit):
        command = [node, str(CLI), *map(str, arguments)]
        proc = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
        number = len(commands)
        stdout, stderr = logs / f'{number:02d}.stdout', logs / f'{number:02d}.stderr'
        stdout.write_bytes(proc.stdout)
        stderr.write_bytes(proc.stderr)
        commands.append({'case': label, 'command': command, 'exitCode': proc.returncode,
                         'expectedExitCode': expected_exit, 'stdout': str(stdout), 'stderr': str(stderr)})
        (output / 'COMMANDS.json').write_bytes(encoded(commands))
        assert proc.returncode == expected_exit, (label, proc.returncode, proc.stdout, proc.stderr)
        return proc

    name = '修復é😀�'.encode('utf-8')
    entity_start = [(0, b'SECTION'), (2, b'ENTITIES')]
    ending = [(0, b'ENDSEC'), (0, b'EOF')]
    incomplete_ascii = header(b'AC1032', name) + entity_start
    retained = header(b'AC1032', name) + entity_start + [(0, b'ENDSEC')]
    tail = binary_body([(0, b'SECTION'), (2, b'OBJECTS'), (0, b'XRECORD'), (1, b'discard-me')]) + b'\x01'
    legacy = header(b'AC1009', b'caf\xe9-\xff') + entity_start + ending
    delimited = header(b'AC1032', b'before\x00after') + entity_start + ending
    replaced = header(b'AC1032', b'before?after') + entity_start + ending
    models = [
        ('ascii-close-section', False, ascii_bytes(incomplete_ascii),
         ascii_bytes(incomplete_ascii + ending), incomplete_ascii + ending, 0, {'MissingEof', 'UnclosedSection'}),
        ('binary-discard-open-tail', True, SIGNATURE + binary_body(retained) + tail,
         SIGNATURE + binary_body(retained + [(0, b'EOF')]), retained + [(0, b'EOF')], len(tail), {'DiscardedTail'}),
        ('ascii-legacy-bytes', False, ascii_bytes(legacy), ascii_bytes(legacy), legacy, 0, set()),
        ('ascii-replace-nul', False, ascii_bytes(delimited), ascii_bytes(replaced), replaced, 0, {'ReplacedDelimiter'}),
    ]
    for index, (label, binary, original, expected, tags, discarded, diagnostic_codes) in enumerate(models):
        folder = output / label
        folder.mkdir()
        source, target = folder / 'input.dxf', folder / 'repaired.dxf'
        source.write_bytes(original)
        (folder / 'sentinel.bin').write_bytes(b'preserve-me\x00\xff')
        if index % 2:
            target.write_bytes(b'independent-existing-output\x00\xff')
        before = snapshot(folder)
        preview = run(label + '-preview', ['repair-preview', source], 0)
        receipt = json.loads(preview.stdout)
        assert set(receipt) == {'discarded_bytes', 'diagnostics'} and preview.stderr == b''
        assert receipt['discarded_bytes'] == discarded
        assert diagnostic_codes <= set(receipt['diagnostics'])
        if label == 'ascii-legacy-bytes':
            assert receipt['diagnostics'] == [], receipt
        assert snapshot(folder) == before, 'Preview changed files or file identities'
        (output / (label + '-expected.dxf')).write_bytes(expected)
        repaired = run(label + '-repair', ['repair', source, target], 0)
        assert repaired.stdout == b'' and json.loads(repaired.stderr) == receipt
        assert target.read_bytes() == expected, label
        assert read_tags(target.read_bytes(), binary) == tags, label
        after = snapshot(folder)
        assert set(after) == set(before) | {target.name}
        assert all(after[key] == value for key, value in before.items() if key != target.name)
        cases.append({'case': label, 'sourceSHA256': digest(original), 'sourceBytes': len(original),
                      'expectedOutputSHA256': digest(expected), 'outputBytes': len(expected),
                      'expectedDiscardedBytes': discarded, 'receipt': receipt,
                      'previewDirectorySnapshotUnchanged': True, 'repairReceiptMatchesPreview': True,
                      'exactIndependentOutputBytes': True, 'independentTagPairs': len(tags),
                      'newOrExistingOutput': 'existing' if index % 2 else 'new'})

    unsupported = header(b'AC1012', b'unsupported') + entity_start + ending
    extra = retained + [(0, b'EOF'), (1, b'after-eof')]
    refusals = [
        ('binary-no-closed-section', SIGNATURE + binary_body(entity_start) + b'\x01', b'no complete Binary section'),
        ('unsupported-r13', ascii_bytes(unsupported), b'UnsupportedVersion'),
        ('typed-data-after-eof', ascii_bytes(extra), b'after EOF'),
    ]
    for label, original, error in refusals:
        folder = output / label
        folder.mkdir()
        source, target = folder / 'input.dxf', folder / 'existing.dxf'
        source.write_bytes(original)
        target.write_bytes(b'preserve-existing-output\x00\xff')
        before = snapshot(folder)
        for action in ('repair-preview', 'repair'):
            args = [action, source] + ([target] if action == 'repair' else [])
            proc = run(label + '-' + action, args, 2)
            assert proc.stdout == b'' and error in proc.stderr, (label, proc.stderr)
            assert snapshot(folder) == before
        cases.append({'case': label, 'previewAndRepairRefuse': True,
                      'directoryEntriesBytesAndIdentitiesUnchanged': True})

    folder = output / 'argument-and-file-errors'
    folder.mkdir()
    source, sentinel = folder / 'input.dxf', folder / 'sentinel.dxf'
    source.write_bytes(ascii_bytes(legacy))
    sentinel.write_bytes(b'preserve-argument-output\x00\xff')
    before = snapshot(folder)
    for label, args in [
        ('preview-extra-existing-target', ['repair-preview', source, sentinel]),
        ('preview-extra-source-alias', ['repair-preview', source, source]),
        ('preview-extra-new-target', ['repair-preview', source, folder / 'must-not-exist.dxf']),
        ('preview-missing-file', ['repair-preview', folder / 'missing.dxf']),
        ('preview-missing-input', ['repair-preview']),
    ]:
        proc = run(label, args, 2)
        assert proc.stdout == b'' and proc.stderr and snapshot(folder) == before

    assert len(commands) == 19
    summary = {'status': 'PASS', 'platform': sys.platform, 'pythonVersion': sys.version.split()[0],
               'nodeVersion': subprocess.check_output([node, '--version'], text=True).strip(),
               'positiveProcesses': 8, 'negativeProcesses': 11, 'models': cases,
               'readOnlyPreviewOnSuccessAndFailure': True, 'allRepairReceiptsMatchPreviews': True,
               'oracle': 'Hand-specified bytes/tag lists; Python struct Binary encoder/reader and line-pair ASCII reader',
               'nativeWriterUsedForExpectedBytes': False,
               'scope': 'Repair availability and loss receipt, byte output and source preservation; no whole-drawing semantic certification'}
    (output / 'RESULT.json').write_bytes(encoded(summary))
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python -B tools/test_repair_preview.py NEW_OUTPUT_DIRECTORY')
    verify(Path(sys.argv[1]).resolve())

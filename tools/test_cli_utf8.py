"""Real file-host UTF-8 contracts. Run after a JS build, with a new output directory.

Python's strict decoder supplies malformed-byte expectations independently of the
Node host. Expected DXF bytes are one literal replacement in our existing fixture,
not values obtained by parsing or rewriting with the implementation under test.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'tools' / 'dxf.mjs'
FIXTURE = ROOT / 'examples' / 'handle_plan' / 'input.dxf'
UNICODE = '中文-é-😀-�'
MARKER = 'UTF8_PAYLOAD_MARKER'
INVALID = {'single-invalid-byte': b'\xff', 'overlong-sequence': b'\xc0\xaf', 'truncated-sequence': b'\xe2\x82'}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def snapshot(folder):
    return {p.name: p.read_bytes() for p in folder.iterdir() if p.is_file()}


class Consumer:
    def __init__(self, output):
        self.output = output
        self.node = shutil.which('node')
        assert self.node, 'Node is required'
        self.rows = []
        (output / 'logs').mkdir()

    def run(self, label, folder, args, *, invalid=False, written=None):
        before = snapshot(folder)
        command = [self.node, str(CLI), *map(str, args)]
        proc = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=30)
        number = len(self.rows)
        stdout = self.output / 'logs' / f'{number:02d}.stdout'
        stderr = self.output / 'logs' / f'{number:02d}.stderr'
        stdout.write_bytes(proc.stdout)
        stderr.write_bytes(proc.stderr)
        expected_after = before.copy()
        if written is not None:
            name, raw = written
            expected_after[name] = raw
        checks = {'exit_code': proc.returncode == (2 if invalid else 0),
                  'exact_file_effects': snapshot(folder) == expected_after}
        if invalid:
            checks.update(stdout_empty=proc.stdout == b'',
                          encoding_error=b'JSON input must be valid UTF-8' in proc.stderr)
        self.rows.append({'label': label, 'command': command, 'exitCode': proc.returncode,
                          'stdout': str(stdout), 'stderr': str(stderr), 'checks': checks,
                          'beforeFileSha256': {name: digest(raw) for name, raw in before.items()}})
        (self.output / 'COMMANDS.json').write_bytes(encoded(self.rows))
        assert all(checks.values()), (label, checks, proc.stderr.decode('utf-8', errors='replace'))
        return proc


def verify(output):
    original = FIXTURE.read_bytes()
    # This fixture has public LINE handle AB and private 102-group code8 metadata.
    # Its public layer tag is the independently fixed tag index12 below.
    old_tag = b'8\nold\n'
    assert original.count(old_tag) == 1
    offset = original.index(old_tag)
    new_tag = b'8\n' + UNICODE.encode('utf-8') + b'\n'
    expected_output = original[:offset] + new_tag + original[offset + len(old_tag):]
    source_hash = digest(original)
    expected_edits = [{'index': 12, 'code': 8, 'expected': {'text_hex': '6f6c64'},
                       'value': {'text_hex': UNICODE.encode('utf-8').hex()}}]
    literal_edits = [{'index': 12, 'code': 8, 'expected': {'text': 'old'}, 'value': {'text': UNICODE}}]
    requests = [{'handle': 'AB', 'code': 8, 'value': {'text': UNICODE}}]
    expected_changes = [{'index': 12, 'code': 8, 'offset': offset, 'end_offset': offset + len(old_tag),
                         'before_hex': old_tag.hex(), 'after_hex': new_tag.hex()}]
    expected_receipt = {'source_bytes': len(original), 'output_bytes': len(expected_output), 'changes': expected_changes}
    output.mkdir(parents=True)  # Refuse to overwrite evidence from an earlier run.
    (output / 'original.dxf').write_bytes(original)
    (output / 'expected-unicode.dxf').write_bytes(expected_output)
    consumer = Consumer(output)
    oracle = []

    def case(name, payload):
        folder = output / name
        folder.mkdir()
        source, plan = folder / 'input.dxf', folder / 'payload.json'
        source.write_bytes(original)
        plan.write_bytes(payload)
        return folder, source, plan

    marker_requests = [{'handle': 'AB', 'code': 8, 'value': {'text': MARKER}}]
    marker_edits = [{'index': 12, 'code': 8, 'expected': {'text': 'old'}, 'value': {'text': MARKER}}]
    templates = {'requests': marker_requests, 'array': marker_edits,
                 'bound': {'format': 'dxf-source-plan-v1', 'source_sha256': source_hash, 'edits': marker_edits}}
    for kind, bad_bytes in INVALID.items():
        for form, template in templates.items():
            raw = encoded(template)
            assert raw.count(MARKER.encode()) == 1
            raw = raw.replace(MARKER.encode(), bad_bytes)
            try:
                raw.decode('utf-8', errors='strict')
            except UnicodeDecodeError as error:
                oracle.append({'kind': kind, 'form': form, 'payloadHex': bad_bytes.hex(),
                               'rawSha256': digest(raw), 'strictDecoderRejected': True,
                               'offset': error.start, 'reason': error.reason})
            else:
                raise AssertionError('Counterexample is not invalid UTF-8')
            # Replacement decoding would yield structurally valid JSON; an unrelated
            # JSON syntax error must not stand in for the file-host encoding refusal.
            json.loads(raw.decode('utf-8', errors='replace'))
            actions = [('make-plan', None), ('make-bound-plan', None)] if form == 'requests' else [
                ('bind-plan', None), ('patch-plan', None), ('patch', 'new'), ('patch', 'existing')]
            for action, destination in actions:
                label = '-'.join(filter(None, [kind, form, action, destination]))
                folder, source, plan = case(label, raw)
                if action == 'patch':
                    target = folder / 'output.dxf'
                    if destination == 'existing':
                        target.write_bytes(b'existing-target\x00\xffmust-remain')
                    args = [action, source, target, plan]
                else:
                    args = [action, source, plan]
                consumer.run(label, folder, args, invalid=True)

    # Real request -> plan -> preview -> write chains for both supported containers.
    for bound in (False, True):
        folder, source, request = case('unicode-bound' if bound else 'unicode-array', encoded(requests))
        proc = consumer.run('unicode-request', folder, ['make-bound-plan' if bound else 'make-plan', source, request])
        plan = folder / 'plan.json'
        expected_plan = {'format': 'dxf-source-plan-v1', 'source_sha256': source_hash, 'edits': expected_edits} if bound else expected_edits
        assert json.loads(proc.stdout) == expected_plan
        plan.write_bytes(proc.stdout)
        preview = consumer.run('unicode-preview', folder, ['patch-plan', source, plan])
        receipt = {**expected_receipt, **({'source_sha256': source_hash} if bound else {})}
        assert json.loads(preview.stdout) == receipt
        target = folder / 'output.dxf'
        if bound:
            target.write_bytes(b'replace-this-existing-target')
        written = consumer.run('unicode-write', folder, ['patch', source, target, plan], written=(target.name, expected_output))
        assert written.stdout == b'' and json.loads(written.stderr) == receipt

    # Literal Unicode in edit-plan JSON, including explicit U+FFFD, is accepted too.
    folder, source, literal = case('unicode-literal-plan', encoded(literal_edits))
    preview = consumer.run('literal-array-preview', folder, ['patch-plan', source, literal])
    assert json.loads(preview.stdout) == expected_receipt
    target = folder / 'array-output.dxf'
    written = consumer.run('literal-array-write', folder, ['patch', source, target, literal], written=(target.name, expected_output))
    assert written.stdout == b'' and json.loads(written.stderr) == expected_receipt
    bound = consumer.run('literal-bind-plan', folder, ['bind-plan', source, literal])
    assert json.loads(bound.stdout) == {'format': 'dxf-source-plan-v1', 'source_sha256': source_hash, 'edits': literal_edits}
    bound_plan = folder / 'bound.json'
    bound_plan.write_bytes(bound.stdout)
    bound_receipt = {**expected_receipt, 'source_sha256': source_hash}
    preview = consumer.run('literal-bound-preview', folder, ['patch-plan', source, bound_plan])
    assert json.loads(preview.stdout) == bound_receipt
    target = folder / 'bound-output.dxf'
    written = consumer.run('literal-bound-write', folder, ['patch', source, target, bound_plan], written=(target.name, expected_output))
    assert written.stdout == b'' and json.loads(written.stderr) == bound_receipt

    summary = {'status': 'PASS', 'fixture': str(FIXTURE.relative_to(ROOT)), 'fixtureSha256': source_hash,
               'independentOracle': 'Python strict UTF-8 decoder and a known single literal byte-span replacement',
               'invalidByteKinds': list(INVALID), 'negativeProcesses': 30, 'positiveProcesses': 11,
               'allInputAndUnselectedBytesPreserved': True, 'existingTargetRefusalsAndSuccessfulOverwriteChecked': True,
               'unicodeOutputSha256': digest(expected_output), 'literalReplacementCharacterAccepted': True,
               'commands': len(consumer.rows), 'malformedByteOracle': oracle,
               'nodeVersion': subprocess.check_output([consumer.node, '--version'], text=True).strip(),
               'pythonVersion': sys.version.split()[0]}
    assert len(consumer.rows) == summary['negativeProcesses'] + summary['positiveProcesses']
    (output / 'RESULT.json').write_bytes(encoded(summary))
    print(json.dumps({key: value for key, value in summary.items() if key != 'malformedByteOracle'}))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python -B tools/test_cli_utf8.py NEW_OUTPUT_DIRECTORY')
    verify(Path(sys.argv[1]).resolve())

"""Original independent whole-file edit/receiving data. Data CC0; code MIT.

All source/tag bytes, spans, typed values and full expected output are declared
here. No product decoder/writer or external fixture creates expected data.
"""
import copy
import hashlib
import struct

SIG = b'AutoCAD Binary DXF\r\n\x1a\0'
def sha(raw): return hashlib.sha256(raw).hexdigest()
def text(code, value): return (code, 'text', value.encode() if isinstance(value, str) else value)
def real(code, value): return (code, 'bits', value)
def bits(value): return str(struct.unpack('<q', struct.pack('<d', value))[0])
def encoded(value):
    import json
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def frame(tag, binary, version, canonical=False):
    code, kind, value = tag
    if binary:
        group = bytes([code]) if version == 'AC1009' and code < 255 else b'\xff' + struct.pack('<H', code) if version == 'AC1009' else struct.pack('<H', code)
        return group + (value + b'\0' if kind == 'text' else struct.pack('<d', value))
    payload = value if kind == 'text' else (b'2.2500' if code == 10 and value == 2.25 and not canonical else format(value, '.17g').encode())
    return str(code).encode() + b'\n' + payload + b'\n' if canonical else f'{code:3d}'.encode() + b'\r\n' + payload + b'\r\n'


def typed(tags):
    return [[c, k, v.decode('utf-8', errors='replace') if k == 'text' else bits(v)] for c, k, v in tags]


def raw_typed(tags):
    return [{'code': c, 'type': k, 'value': v.hex() if k == 'text' else bits(v)} for c, k, v in tags]


def build(version, binary):
    label = {'AC1009': 'r12', 'AC1015': 'r2000', 'AC1032': 'r2018'}[version] + ('-binary' if binary else '-ascii')
    old_layer = '层-é'.encode() if version == 'AC1032' else b'caf\xe9'
    new_layer = '层-已验'.encode() if version == 'AC1032' else b'caf\xe9-reviewed'
    payload = 'untouched-元数据-é'.encode() if version == 'AC1032' else b'untouched-caf\xe9'
    tags = ([] if binary else [text(999, 'receiving preface')]) + [
        text(0, 'SECTION'), text(2, 'HEADER'), text(9, '$ACADVER'), text(1, version),
        text(9, '$DWGCODEPAGE'), text(3, 'ANSI_1252'), text(0, 'ENDSEC'),
        text(0, 'SECTION'), text(2, 'ENTITIES'), text(0, 'LINE'), text(5, 'A5')]
    if version != 'AC1009': tags.append(text(100, 'AcDbEntity'))
    layer_index = len(tags); tags.append(text(8, old_layer))
    if version != 'AC1009': tags.append(text(100, 'AcDbLine'))
    x_index = len(tags); tags.extend([real(10, 2.25), real(20, -3.5), real(30, 0.0), real(11, 7.0), real(21, 11.0), real(31, 0.0),
        text(0, 'ACME_PAYLOAD'), text(1, payload), text(0, 'ENDSEC'), text(0, 'EOF')])
    source = bytearray(SIG if binary else b''); spans = []
    for tag in tags:
        offset = len(source); part = frame(tag, binary, version); source.extend(part)
        spans.append({'offset': offset, 'end_offset': len(source), 'raw_hex': part.hex()})
    if not binary: source.extend(b'\r\n \t\r\n')
    source = bytes(source)
    # Deliberately unsorted multi-edit input; receipt is in original source order.
    plan = [{'index': x_index, 'code': 10, 'expected': {'bits': bits(2.25)}, 'value': {'bits': bits(4.25)}},
            {'index': layer_index, 'code': 8, 'expected': {'text_hex': old_layer.hex()}, 'value': {'text_hex': new_layer.hex()}}]
    modified = copy.deepcopy(tags); modified[layer_index] = text(8, new_layer); modified[x_index] = real(10, 4.25)
    cursor = 0; output = bytearray(); changes = []
    for index in (layer_index, x_index):
        span = spans[index]; after = frame(modified[index], binary, version, canonical=True)
        output.extend(source[cursor:span['offset']]); output.extend(after); cursor = span['end_offset']
        changes.append({'index': index, 'code': tags[index][0], 'offset': span['offset'], 'end_offset': span['end_offset'], 'before_hex': span['raw_hex'], 'after_hex': after.hex()})
    output.extend(source[cursor:]); output = bytes(output)
    bound = {'format': 'dxf-source-plan-v1', 'source_sha256': sha(source), 'edits': plan}
    receipt = {'source_bytes': len(source), 'output_bytes': len(output), 'changes': changes, 'source_sha256': sha(source)}
    core = lambda values: {'version': version, 'complete': True, 'tags': typed(values), 'diagnostics': [], 'details': [], 'tag_count': len(values)}
    return {'name': label, 'version': version, 'binary': binary, 'source': source, 'output': output,
            'tags': tags, 'modifiedTags': modified, 'rawTypedValues': raw_typed(tags), 'modifiedRawTypedValues': raw_typed(modified),
            'tagSpans': spans, 'plan': plan, 'boundPlan': bound, 'receipt': receipt,
            'verification': {'verified': True, **receipt, 'output_sha256': sha(output)},
            'sourceCore': core(tags), 'outputCore': core(modified), 'layerIndex': layer_index, 'xIndex': x_index}


def cases():
    return [build(version, binary) for version in ('AC1009', 'AC1015', 'AC1032') for binary in (False, True)]


def identity_cases():
    # Existing empty-plan semantics perform no edit/convertibility approval.
    # These controls prove only bound source/candidate byte identity, not CAD validity.
    ascii_case = build('AC1009', False); binary_case = build('AC1015', True)
    sources = [('noop-ascii', ascii_case['source']), ('noop-binary', binary_case['source']),
               ('noop-unsupported-version-identity', binary_case['source'].replace(b'AC1015', b'AC1012')),
               ('noop-zero-byte-identity', b'')]
    return [{'name': name, 'source': raw, 'boundPlan': {'format': 'dxf-source-plan-v1', 'source_sha256': sha(raw), 'edits': []},
             'verification': {'verified': True, 'source_bytes': len(raw), 'output_bytes': len(raw), 'changes': [],
                              'source_sha256': sha(raw), 'output_sha256': sha(raw)}} for name, raw in sources]


def refusal_cases():
    result = []
    base = build('AC1015', True)
    def add(name, source, plan, reason, received=None, raw_plan=None):
        result.append({'name': name, 'source': source, 'received': base['output'] if received is None else received,
                       'planBytes': encoded({'format': 'dxf-source-plan-v1', 'source_sha256': sha(source), 'edits': plan}) if raw_plan is None else raw_plan,
                       'error': reason})
    stale = copy.deepcopy(base['plan']); stale[0]['expected']['bits'] = bits(6.25)
    add('stale-typed-precondition', base['source'], stale, 'edit precondition failed')
    add('protected-record-marker', base['source'], [{'index': len(base['tags']) - 1, 'code': 0, 'expected': {'text': 'EOF'}, 'value': {'text': 'ENDSEC'}}], 'structural/version edit requires document migration')
    add('unsupported-source', base['source'].replace(b'AC1015', b'AC1012'), base['plan'], 'UnsupportedVersion')
    add('truncated-source', base['source'][:-1], base['plan'], 'IncompleteDocument')
    add('wire-source', base['source'].replace(b'AC1015', b'AC1009'), base['plan'], 'wire/version mismatch')
    fractional = encoded(base['boundPlan']).replace(('"index": ' + str(base['xIndex'])).encode(), ('"index": ' + str(base['xIndex']) + '.0000000000000000001').encode(), 1)
    add('fractional-index-lexeme', base['source'], base['plan'], 'index must be an exact Int32', raw_plan=fractional)
    wrong_hash = copy.deepcopy(base['boundPlan']); wrong_hash['source_sha256'] = '0' * 64
    add('stale-source-binding', base['source'], base['plan'], 'Input SHA-256 does not match the source-bound plan', raw_plan=encoded(wrong_hash))
    malformed = copy.deepcopy(base['boundPlan']); malformed['format'] = 'dxf-source-plan-v2'
    add('unsupported-envelope', base['source'], base['plan'], 'unsupported source-bound plan format', raw_plan=encoded(malformed))
    add('invalid-plan-utf8', base['source'], base['plan'], 'JSON input must be valid UTF-8', raw_plan=b'\xff')
    for binary in (False, True):
        case = build('AC1015', binary); suffix = 'binary' if binary else 'ascii'
        variants = {'changed-selected-value': case['output'].replace(struct.pack('<d', 4.25), struct.pack('<d', 5.25), 1) if binary else case['output'].replace(b'10\n4.25\n', b'10\n5.25\n', 1),
                    'changed-unselected-payload': case['output'].replace(b'untouched', b'Untouched', 1),
                    'truncated-received-file': case['output'][:-1], 'extra-received-bytes': case['output'] + b'\n'}
        if not binary: variants['equivalent-number-lexeme'] = case['output'].replace(b'10\n4.25\n', b'10\n4.2500\n', 1)
        for name, received in variants.items():
            assert received != case['output']
            add(name + '-' + suffix, case['source'], case['plan'], 'Received file does not match the source-bound edit result', received=received)
        add('unbound-array-' + suffix, case['source'], case['plan'], 'verify-patch requires a source-bound plan', received=case['output'], raw_plan=encoded(case['plan']))
    return result

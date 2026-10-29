"""Independent project-owned record handoff models (data CC0-1.0, code MIT).

Expected byte spans come from explicit tag lists and Python bytes/struct, never
from the product decoder/writer. This module does not import the DXF product.
"""
import struct

SIGNATURE = b'AutoCAD Binary DXF\r\n\x1a\x00'


def text(code, value):
    return code, 'text', value if isinstance(value, bytes) else value.encode('ascii')


def real(code, value):
    return code, 'real', value


def integer(code, value):
    return code, 'integer', value


def encode(tags, binary=False, old=False, crlf=False, lexical=False):
    result = bytearray()
    newline = b'\r\n' if crlf else b'\n'
    for code, kind, value in tags:
        if binary:
            result.extend(struct.pack('<B' if old else '<H', code))
            if kind == 'text':
                result.extend(value + b'\0')
            elif kind == 'real':
                result.extend(struct.pack('<d', float(value)))
            else:
                result.extend(struct.pack('<h', value))
        else:
            code_text = str(code).encode('ascii')
            if lexical and code == 10 and value == '1.25':
                code_text, value = b'  10', '1.250e+0'
            payload = value if kind == 'text' else str(value).encode('ascii')
            result.extend(code_text + newline + payload + newline)
    return bytes(result)


def header(version):
    return [text(0, 'SECTION'), text(2, 'HEADER'), text(9, '$ACADVER'), text(1, version), text(0, 'ENDSEC')]


def line(old=False):
    tags = [text(0, 'LINE'), text(5, 'AB')]
    if not old:
        tags += [text(102, '{AUDIT'), text(5, 'DEAD'), text(8, 'private'), text(102, '}'), text(100, 'AcDbEntity')]
    tags += [text(8, b'caf\xe9')]
    if not old:
        tags += [text(100, 'AcDbLine')]
    return tags + [real(10, '1.25'), real(20, '-2.5'), real(11, '4.5'), real(21, '8.75')]


def circle(old=False, handle='AC'):
    tags = [text(0, 'CIRCLE'), text(5, handle)]
    if not old:
        tags += [text(100, 'AcDbEntity')]
    tags += [text(8, '0')]
    if not old:
        tags += [text(100, 'AcDbCircle')]
    return tags + [real(10, '9.0'), real(20, '10.0'), real(40, '2.0')]


def model(name, version, tags, prefix, suffix, *, binary=False, old=False, crlf=False, lexical=False, query='000ab', drawing=True):
    options = dict(binary=binary, old=old, crlf=crlf, lexical=lexical)
    before = (SIGNATURE if binary else b'') + encode(prefix, **options)
    record = encode(tags, **options)
    return {'name': name, 'source': before + record + encode(suffix, **options), 'record': record,
            'offset': len(before), 'end_offset': len(before) + len(record), 'tag_count': len(tags),
            'version': version, 'binary': binary, 'query': query, 'tags': tags,
            'structurallyCompleteDrawing': drawing}


def cases():
    end = [text(0, 'ENDSEC'), text(0, 'EOF')]
    output = []
    for name, version, binary, old, crlf, lexical in [
        ('modern-ascii', 'AC1015', False, False, False, False),
        ('modern-binary', 'AC1015', True, False, False, False),
        ('r12-ascii', 'AC1009', False, True, False, False),
        ('r12-binary', 'AC1009', True, True, False, False),
        ('crlf-lexical', 'AC1015', False, False, True, True),
    ]:
        prefix = header(version) + [text(0, 'SECTION'), text(2, 'ENTITIES')]
        output.append(model(name, version, line(old), prefix, circle(old) + end,
                            binary=binary, old=old, crlf=crlf, lexical=lexical))
    dim = [text(0, 'DIMSTYLE'), text(105, '00B0'), text(100, 'AcDbSymbolTableRecord'),
           text(100, 'AcDbDimStyleTableRecord'), text(2, 'ReviewStyle'), integer(70, 0)]
    prefix = header('AC1015') + [text(0, 'SECTION'), text(2, 'TABLES'), text(0, 'TABLE'), text(2, 'DIMSTYLE'), integer(70, 1)]
    output.append(model('dimstyle-105', 'AC1015', dim, prefix, [text(0, 'ENDTAB')] + end, query='b0'))
    prefix = header('AC1015') + [text(0, 'SECTION'), text(2, 'ENTITIES')]
    unknown = [text(0, 'REVIEW_UNKNOWN'), text(5, 'F1'), text(300, b'raw\xe9')]
    output.append(model('unknown-record', 'AC1015', unknown, prefix, end, query='f1'))
    poly = [text(0, 'POLYLINE'), text(5, 'A1'), integer(66, 1), integer(70, 0)]
    children = [text(0, 'VERTEX'), text(5, 'A2'), real(10, '1.0'), real(20, '2.0'),
                text(0, 'VERTEX'), text(5, 'A3'), real(10, '3.0'), real(20, '4.0'), text(0, 'SEQEND'), text(5, 'A4')]
    output.append(model('physical-polyline-header', 'AC1015', poly, prefix, children + end, query='a1'))
    output.append(model('final-typed-record', 'AC1015', line(), prefix, [], drawing=False))
    expected_literal = b'0\nLINE\n5\nAB\n102\n{AUDIT\n5\nDEAD\n8\nprivate\n102\n}\n100\nAcDbEntity\n8\ncaf\xe9\n100\nAcDbLine\n10\n1.25\n20\n-2.5\n11\n4.5\n21\n8.75\n'
    assert output[0]['record'] == expected_literal
    assert [(row['offset'], len(row['record']), row['end_offset'], row['tag_count']) for row in output[:5]] == [
        (69, 112, 181, 13), (91, 113, 204, 13), (69, 50, 119, 7), (84, 52, 136, 7), (83, 144, 227, 13)]
    return output


def refusal_sources():
    valid = cases()[0]['source']
    prefix = header('AC1015') + [text(0, 'SECTION'), text(2, 'ENTITIES')]
    end = [text(0, 'ENDSEC'), text(0, 'EOF')]
    duplicate = encode(prefix + line() + circle(handle='00aB') + end)
    handseed = encode(header('AC1015')[:-1] + [text(9, '$HANDSEED'), text(5, 'AB'), text(0, 'ENDSEC'),
                       text(0, 'SECTION'), text(2, 'ENTITIES')] + circle() + end)
    mismatch = cases()[1]['source'].replace(b'AC1015', b'AC1009', 1)
    return [
        {'name': 'invalid-handle', 'source': valid, 'query': 'not-hex', 'error': 'handle must contain'},
        {'name': 'missing-handle', 'source': valid, 'query': 'FF', 'error': 'record handle not found'},
        {'name': 'private-only-handle', 'source': valid, 'query': 'DEAD', 'error': 'record handle not found'},
        {'name': 'duplicate-public-handle', 'source': duplicate, 'query': 'AB', 'error': 'ambiguous record handle'},
        {'name': 'header-handseed', 'source': handseed, 'query': 'AB', 'error': 'record handle not found'},
        {'name': 'unresolved-raw-tail', 'source': cases()[1]['source'][:-2], 'query': 'AB', 'error': 'IncompleteDocument'},
        {'name': 'unsupported-r13', 'source': valid.replace(b'AC1015', b'AC1012', 1), 'query': 'AB', 'error': 'UnsupportedVersion'},
        {'name': 'wire-version-mismatch', 'source': mismatch, 'query': 'AB', 'error': 'wire/version mismatch'},
    ]

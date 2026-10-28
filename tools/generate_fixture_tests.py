"""Embed independently generated reference files in backend-independent tests."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
lines=['// Generated from ezdxf fixtures; regenerate with tools/generate_fixture_tests.py.']
for ver in ['r12','r2000','r2018']:
    b=(root/'fixtures'/f'{ver}-binary.dxf').read_bytes()
    tags=json.loads((root/'fixtures'/f'{ver}-tags.json').read_text())
    lines += ['///|',f'let {ver}_fixture : Bytes = b"'+''.join(f'\\x{x:02x}' for x in b)+'"',
    '///|',f'test "{ver} independent fixture and every-byte chunking" {{',
    f'  for size in [1, 2, 7, 31, 4096] {{',
    '    let decoder = @dxf.DxfDecoder::new()',
    '    let mut p = 0',f'    let bytes = {ver}_fixture',
    '    while p < bytes.length() {',
    '      let end = (p + size).min(bytes.length())',
    '      ignore(decoder.feed(bytes[p:end].to_owned()))', '      p = end', '    }',
    '    let doc = decoder.finish()', '    assert_true(doc.is_complete())',
    f'    assert_eq(doc.tags().length(), {len(tags)})',
    '    assert_eq(doc.save(), bytes)',
    '    assert_true(doc.tags().any(t => t.code == 1070 && t.integer() == Some(-32768L)))',
    '    assert_true(doc.tags().any(t => t.code == 1040 && t.real().map(d => d.reinterpret_as_int64()) == Some(-9223372036854775808L)))',
    '    assert_true(!doc.lint().any(d => d.severity == @dxf.Error))',
    '  }','}']
(root/'fixtures_test.mbt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Embedded 3 independent binary models in MoonBit tests')

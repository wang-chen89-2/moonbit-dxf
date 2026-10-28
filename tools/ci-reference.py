"""Fail CI if any of the six independent conversion audits is missing or nonzero."""
from pathlib import Path
import json
import sys

from reference import verify

folder = Path(sys.argv[1])
expected = {
    f'{version}-moon-{wire}.dxf': (acadver, entities)
    for version, acadver, entities in [('r12', 'AC1009', 4), ('r2000', 'AC1015', 5), ('r2018', 'AC1032', 5)]
    for wire in ['ascii', 'binary']
}
assert {p.name for p in folder.glob('*-moon-*.dxf')} == set(expected), 'Expected all six conversion outputs'
rows = []
for name, (version, entities) in expected.items():
    row = verify(folder / name)
    assert row['version'] == version and row['entities'] == entities, row
    assert row['errors'] == row['fixes'] == 0, row
    rows.append(row)
print(json.dumps({'status': 'PASS', 'independent_audits': rows}, indent=2))

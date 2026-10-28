// Cross-implementation typed-tag comparisons against independently saved ezdxf tags.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath,pathToFileURL} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const output=path.resolve(process.argv[2]??path.join(root,'verification-output'));
fs.mkdirSync(output,{recursive:true});
const built=['release','debug'].map(m=>path.join(root,`_build/js/${m}/build/bridge/bridge.js`)).find(fs.existsSync);
const {process_hex}=await import(pathToFileURL(built));
const call=(b,a)=>{const s=process_hex(b.toString('hex'),a);assert.ok(!s.startsWith('ERROR:'),s);return s};
const rows=[];
for(const ver of ['r12','r2000','r2018']) {
 const original=fs.readFileSync(path.join(root,`fixtures/${ver}-binary.dxf`));
 const expected=JSON.parse(fs.readFileSync(path.join(root,`fixtures/${ver}-tags.json`))).map(([code,type,value])=>
  type==='double'?[code,'bits',Buffer.from(value,'hex').readBigInt64LE().toString()]:[code,type,value]);
 const decoded=JSON.parse(call(original,'lint'));
 assert.equal(decoded.complete,true); assert.deepEqual(decoded.tags,expected);
 assert.deepEqual(Buffer.from(call(original,'save'),'hex'),original);
 const asciiSource=fs.readFileSync(path.join(root,`fixtures/${ver}-ascii.dxf`));
 const binary=Buffer.from(call(asciiSource,'binary'),'hex');
 const ascii=Buffer.from(call(original,'ascii'),'hex');
 assert.deepEqual(JSON.parse(call(binary,'lint')).tags,expected);
 assert.deepEqual(JSON.parse(call(ascii,'lint')).tags,expected);
 fs.writeFileSync(path.join(output,`${ver}-moon-binary.dxf`),binary);
 fs.writeFileSync(path.join(output,`${ver}-moon-ascii.dxf`),ascii);
 const adapters=JSON.parse(call(original,'adapters'));
 assert.equal(adapters.dxfkit_entities,ver==='r12'?4:5);
 assert.equal(adapters.geometry_entities,ver==='r12'?2:3);
 rows.push({version:ver,tags_compared:expected.length,byte_preserve:true,ascii_to_binary_tags_equal:true,binary_to_ascii_tags_equal:true,adapters});
}
const malformed=Buffer.from('0\nSECTION\n2\nENTITIES\n0\nLINE\n5\nA\n0\nINSERT\n5\na\n2\nMISSING\n1001\nAPP\n1002\n{\n');
const lint=JSON.parse(call(malformed,'lint'));
for(const c of ['DuplicateHandle','DanglingBlock','UnclosedSection','MissingEof','UnbalancedXdata']) assert.ok(lint.diagnostics.includes(c));
const repaired=Buffer.from(call(malformed,'repair'),'hex');
const repairedLint=JSON.parse(call(repaired,'lint'));
assert.ok(!repairedLint.diagnostics.includes('UnclosedSection'));assert.ok(!repairedLint.diagnostics.includes('MissingEof'));
assert.ok(repairedLint.diagnostics.includes('DuplicateHandle'));
fs.writeFileSync(path.join(output,'five-defects-ascii.dxf'),malformed);
const rawUnknown=Buffer.concat([fs.readFileSync(path.join(root,'fixtures/r2018-binary.dxf')),Buffer.from([0xbc,0x02,0,255])]);
assert.equal(JSON.parse(call(rawUnknown,'lint')).complete,false);
assert.deepEqual(Buffer.from(call(rawUnknown,'save'),'hex'),rawUnknown);
assert.ok(process_hex(rawUnknown.toString('hex'),'binary').startsWith('ERROR:'));
rows.push({case:'five_defect_categories',diagnostics:lint.diagnostics,repair_retains_ambiguous_handle_and_xdata:true,opaque_binary_tail_preserved:true,opaque_conversion_rejected:true});
const report={kind:'independent ezdxf typed-tag differential and actual upstream consumers',rows,product_source_language:'MoonBit'};
fs.writeFileSync(path.join(output,'node-differential.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));

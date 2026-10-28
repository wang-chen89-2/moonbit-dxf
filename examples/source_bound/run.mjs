import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const directory=process.argv[2];
if(!directory) throw Error('Usage: node examples/source_bound/run.mjs NEW_OUTPUT_DIRECTORY');
const destination=path.resolve(directory);
fs.mkdirSync(destination); // A fresh directory keeps existing files untouched.
function cli(args,expected=0) {
 const p=spawnSync(process.execPath,[path.join(root,'tools/dxf.mjs'),...args],{encoding:'utf8'});
 if(p.status!==expected) throw Error(`${p.status}: ${p.stderr}`);
 return p;
}
const original=fs.readFileSync(path.join(root,'examples/handle_plan/input.dxf'));
const input=path.join(destination,'input.dxf');fs.writeFileSync(input,original);
const requests=path.join(root,'examples/handle_plan/requests.json');
const planFile=path.join(destination,'bound-plan.json');
const plan=cli(['make-bound-plan',input,requests]);fs.writeFileSync(planFile,plan.stdout);
const preview=JSON.parse(cli(['patch-plan',input,planFile]).stdout);
const output=path.join(destination,'patched.dxf');cli(['patch',input,output,planFile]);
const altered=path.join(destination,'altered.dxf');
const alteredBytes=Buffer.from(original.toString('utf8').replace('8\nmetadata\n','8\nmetadata-revised\n'),'utf8');
if(alteredBytes.equals(original)) throw Error('Example mutation was not applied');
fs.writeFileSync(altered,alteredBytes);
const refused=path.join(destination,'must-not-be-created.dxf');
cli(['patch',altered,refused,planFile],2);
if(fs.existsSync(refused)||!fs.readFileSync(input).equals(original)) throw Error('File preservation failed');
console.log(JSON.stringify({output,source_sha256:preview.source_sha256,edits:preview.changes.length,changed_source_rejected:true},null,2));

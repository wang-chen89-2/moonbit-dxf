#!/usr/bin/env node
// Thin filesystem host; all decoding/encoding/diagnostics live in MoonBit.
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { isUtf8 } from 'node:buffer';
import { pathToFileURL } from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const candidates=['_build/js/release/build/bridge/bridge.js','_build/js/debug/build/bridge/bridge.js'];
const moduleFile=candidates.map(p=>path.join(root,p)).find(p=>fs.existsSync(p));
if(!moduleFile) throw Error('Build first: moon build --target js');
const {process_hex,apply_edits_hex,make_plan_hex,unwrap_source_plan}=await import(pathToFileURL(moduleFile));
const [action,input,output,planFile]=process.argv.slice(2);
if(!['lint','binary','ascii','save','repair','adapters','tags','make-plan','make-bound-plan','bind-plan','patch-plan','patch'].includes(action)||!input || (action==='patch'&&(!output||!planFile)) || (['make-plan','make-bound-plan','bind-plan','patch-plan'].includes(action)&&!output)) {
  console.error('node tools/dxf.mjs lint|tags|binary|ascii|save|repair|adapters INPUT [OUTPUT]\nnode tools/dxf.mjs make-plan|make-bound-plan INPUT REQUESTS.json\nnode tools/dxf.mjs bind-plan INPUT PLAN.json\nnode tools/dxf.mjs patch-plan INPUT PLAN.json\nnode tools/dxf.mjs patch INPUT OUTPUT PLAN.json'); process.exit(2);
}
function separateOutput(input,output) {
 if(!output) throw Error('An output path is required');
 if(path.resolve(input)===path.resolve(output)) throw Error('Choose a separate output path');
 if(fs.existsSync(output)) {
   const source=fs.statSync(input,{bigint:true}), destination=fs.statSync(output,{bigint:true});
   if(source.dev===destination.dev && source.ino===destination.ino) throw Error('Choose a separate output path');
 }
}
function readJsonInput(file) {
 const bytes=fs.readFileSync(file);
 if(!isUtf8(bytes)) throw Error('JSON input must be valid UTF-8');
 return bytes.toString('utf8');
}
try {
 const sourceBytes=fs.readFileSync(input), source=sourceBytes.toString('hex');
 let result, verifiedSource=null;
 if(['bind-plan','patch-plan','patch'].includes(action)) {
   const decoded=unwrap_source_plan(readJsonInput(action==='patch'?planFile:output));
   if(decoded.startsWith('ERROR:')) throw Error(decoded);
   const metadata=JSON.parse(decoded);
   if(metadata.source_sha256!==null) {
     const digest=createHash('sha256').update(sourceBytes).digest('hex');
     if(digest!==metadata.source_sha256) throw Error('Input SHA-256 does not match the source-bound plan');
     verifiedSource=digest;
   }
   result=apply_edits_hex(source,metadata.plan_json);
   if(action==='bind-plan'&&!result.startsWith('ERROR:')) {
     const digest=verifiedSource??createHash('sha256').update(sourceBytes).digest('hex');
     // Keep native-validated edit number lexemes; never round them through JS Number.
     result=`{"format":"dxf-source-plan-v1","source_sha256":"${digest}","edits":${metadata.plan_json}}`;
   }
 } else if(['make-plan','make-bound-plan'].includes(action)) {
   result=make_plan_hex(source,readJsonInput(output));
   if(action==='make-bound-plan'&&!result.startsWith('ERROR:')) {
     // Native plans contain only Int32 indices/codes and typed string payloads.
     result=JSON.stringify({format:'dxf-source-plan-v1',source_sha256:createHash('sha256').update(sourceBytes).digest('hex'),edits:JSON.parse(result)});
   }
 } else result=process_hex(source,action==='repair'?'repair_report':action);
 if(result.startsWith('ERROR:')) throw Error(result);
 if(action==='bind-plan') console.log(result);
 else if(['lint','adapters','tags','make-plan','make-bound-plan','patch-plan'].includes(action)) {
   const data=JSON.parse(result);
   if(data.tags) {data.tag_count=data.tags.length;if(action!=='tags') delete data.tags;}
   delete data.output_hex;
   if(verifiedSource!==null) data.source_sha256=verifiedSource;
   console.log(JSON.stringify(data,null,2));
   if(action==='lint'&&data.diagnostics.some(c=>!['AssumedVersion','UnknownGroup','NonfiniteReal'].includes(c))) process.exitCode=1;
 } else {
   separateOutput(input,output);
   if(action==='patch') separateOutput(planFile,output);
   if(['repair','patch'].includes(action)) {
     const report=JSON.parse(result);
     if(verifiedSource!==null) report.source_sha256=verifiedSource;
     fs.writeFileSync(output,Buffer.from(report.output_hex,'hex'));
     delete report.output_hex;
     console.error(JSON.stringify(report));
   } else fs.writeFileSync(output,Buffer.from(result,'hex'));
 }
} catch(e) { console.error(String(e)); process.exitCode=2; }

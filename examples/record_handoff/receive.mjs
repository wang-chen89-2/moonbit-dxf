#!/usr/bin/env node
// Project-owned file receiver; native MoonBit owns record identity and decoding.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { isUtf8 } from 'node:buffer';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const signature=Buffer.from('AutoCAD Binary DXF\r\n\x1a\x00','latin1');
const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const fields=['requested_handle','source_sha256','record_sha256','version','binary','offset','end_offset'].sort();
const supported=new Set(['AC1006','AC1009','AC1014','AC1015','AC1018','AC1021','AC1024','AC1027','AC1032']);

function nativeJSON(result) {
  if(result.startsWith('ERROR:')) throw Error(result);
  return JSON.parse(result);
}

// Only control framing is encoded here. The record payload is never rewritten.
function controls(tags,version,binary) {
  if(!binary) return Buffer.from(tags.map(([code,value])=>`${code}\n${value}\n`).join(''),'ascii');
  const width=['AC1006','AC1009'].includes(version)?1:2;
  return Buffer.concat(tags.map(([code,value])=>{
    const bytes=Buffer.alloc(width);
    if(width===1) bytes.writeUInt8(code); else bytes.writeUInt16LE(code);
    return Buffer.concat([bytes,Buffer.from(value,'ascii'),Buffer.from([0])]);
  }));
}

export async function receive(source,record,receipt) {
  if(receipt===null || Array.isArray(receipt) || typeof receipt!=='object' ||
     JSON.stringify(Object.keys(receipt).sort())!==JSON.stringify(fields)) throw Error('Invalid record receipt fields');
  if(typeof receipt.requested_handle!=='string' || typeof receipt.version!=='string' ||
     !supported.has(receipt.version) || typeof receipt.binary!=='boolean') throw Error('Invalid record receipt profile');
  for(const field of ['source_sha256','record_sha256']) {
    if(typeof receipt[field]!=='string' || !/^[0-9a-f]{64}$/.test(receipt[field])) throw Error('Invalid record receipt hash');
  }
  const {offset,end_offset}=receipt;
  if(!Number.isSafeInteger(offset) || !Number.isSafeInteger(end_offset) || offset<0 || end_offset<offset ||
     end_offset>source.length || end_offset-offset!==record.length) throw Error('Invalid record receipt span');
  if(digest(source)!==receipt.source_sha256) throw Error('Source hash mismatch');
  if(digest(record)!==receipt.record_sha256) throw Error('Record hash mismatch');
  if(!source.subarray(offset,end_offset).equals(record)) throw Error('Record is not the source span');
  const candidates=['_build/js/release/build/bridge/bridge.js','_build/js/debug/build/bridge/bridge.js'];
  const moduleFile=candidates.map(name=>path.join(root,name)).find(name=>fs.existsSync(name));
  if(!moduleFile) throw Error('Build first: moon build --target js');
  const {process_hex,export_record_hex}=await import(pathToFileURL(moduleFile));
  const selected=nativeJSON(export_record_hex(source.toString('hex'),receipt.requested_handle));
  if(selected.offset!==offset || selected.end_offset!==end_offset ||
     !Buffer.from(selected.output_hex,'hex').equals(record)) throw Error('Record does not match the requested owning handle');
  if(selected.version!==receipt.version || selected.binary!==receipt.binary ||
     receipt.binary!==source.subarray(0,signature.length).equals(signature)) throw Error('Source profile mismatch');
  const prefix=Buffer.concat([
    receipt.binary?signature:Buffer.alloc(0),
    controls([[0,'SECTION'],[2,'HEADER'],[9,'$ACADVER'],[1,receipt.version],[0,'ENDSEC'],[0,'SECTION'],[2,'ENTITIES']],receipt.version,receipt.binary),
  ]);
  const suffix=controls([[0,'ENDSEC'],[0,'EOF']],receipt.version,receipt.binary);
  const framed=Buffer.concat([prefix,record,suffix]);
  const decoded=nativeJSON(process_hex(framed.toString('hex'),'tags'));
  const identity=nativeJSON(export_record_hex(framed.toString('hex'),receipt.requested_handle));
  if(!decoded.complete || identity.offset!==prefix.length || identity.end_offset!==prefix.length+record.length ||
     !Buffer.from(identity.output_hex,'hex').equals(record)) throw Error('Receiving parse did not identify exactly one physical record');
  const tags=decoded.tags.slice(7,-2);
  if(tags.length===0 || tags[0][0]!==0 || tags.filter(tag=>tag[0]===0).length!==1) throw Error('Receiving parse contains multiple physical records');
  return {verified:true,...receipt,record_kind:tags[0][2],tag_count:tags.length,tags};
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    if(process.argv.length!==5) throw Error('Usage: node examples/record_handoff/receive.mjs SOURCE RECORD RECEIPT');
    const [sourceFile,recordFile,receiptFile]=process.argv.slice(2);
    const bytes=fs.readFileSync(receiptFile);
    if(!isUtf8(bytes)) throw Error('Record receipt must be valid UTF-8');
    const result=await receive(fs.readFileSync(sourceFile),fs.readFileSync(recordFile),JSON.parse(bytes.toString('utf8')));
    console.log(JSON.stringify(result,null,2));
  } catch(error) { console.error(String(error)); process.exitCode=2; }
}

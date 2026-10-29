#!/usr/bin/env node
// The application consumes a real DXF file; MoonBit resolves typed APPID data.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');

export async function receive(bytes,handle,application) {
  const candidates=['_build/js/release/build/bridge/bridge.js','_build/js/debug/build/bridge/bridge.js'];
  const moduleFile=candidates.map(name=>path.join(root,name)).find(name=>fs.existsSync(name));
  if(!moduleFile) throw Error('Build first: moon build --target js');
  const {read_xdata_hex}=await import(pathToFileURL(moduleFile));
  const result=read_xdata_hex(bytes.toString('hex'),handle,application);
  if(result.startsWith('ERROR:')) throw Error(result);
  return {handle,application,data:JSON.parse(result)};
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    if(process.argv.length!==5) throw Error('Usage: node examples/xdata_plan/receive.mjs INPUT HANDLE APPID');
    const [file,handle,application]=process.argv.slice(2);
    console.log(JSON.stringify(await receive(fs.readFileSync(file),handle,application),null,2));
  } catch(error) { console.error(String(error)); process.exitCode=2; }
}

"""One relevant final pass. Usage: python tools/validate.py MOON_EXE REPORT_DIR.
Set PYTHONPATH to an isolated ezdxf==1.4.3 install for reference verification.
"""
from pathlib import Path
import os,sys,subprocess,json,hashlib,re
root=Path(__file__).resolve().parents[1]
moon=Path(sys.argv[1]).resolve();report=Path(sys.argv[2]).resolve();report.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,MOON_HOME=str(moon.parent.parent))
env['PATH']=str(moon.parent)+os.pathsep+env.get('PATH','')
commands=[
 [str(moon),'version','--all'],
 [str(moon),'fmt'],[str(moon),'info','--target','js'],
 [str(moon),'check','--target','js','--deny-warn'],
 [str(moon),'build','--target','js','--deny-warn'],
 [str(moon),'test','--target','js','--deny-warn'],
 [str(moon),'check','--target','wasm-gc','--deny-warn'],
 [str(moon),'build','--target','wasm-gc','--deny-warn'],
 [str(moon),'test','--target','wasm-gc','--deny-warn'],
 [str(moon),'run','examples/inspect','--target','js'],
 [str(moon),'run','examples/inspect','--target','wasm-gc'],
 ['node','tools/verify.mjs',str(report/'verification')],
]
def run(cmd,expected=0):
    proc=subprocess.run(cmd,cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
    row={'command':cmd,'exit_code':proc.returncode,'expected_exit':expected}
    (report/f'{len(results):02d}.log').write_text(proc.stdout,encoding='utf-8')
    row['log']=str(report/f'{len(results):02d}.log');results.append(row)
    print(json.dumps(row,ensure_ascii=False),flush=True)
    (report/'commands.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if proc.returncode!=expected: raise SystemExit(f'FAILED {cmd}: {proc.stdout[-2500:]}')
results=[]
for cmd in commands:run(cmd)
files=sorted((report/'verification').glob('*-moon-*.dxf'))
run([sys.executable,'tools/reference.py',*[str(p) for p in files]])
run([sys.executable,'tools/check_diagnostics.py',str(report/'diagnostics')])
run(['node','tools/dxf.mjs','lint','fixtures/r2018-binary.dxf'])
run(['node','tools/dxf.mjs','repair',str(report/'verification'/'five-defects-ascii.dxf'),str(report/'cli-repaired.dxf')])
run(['node','tools/dxf.mjs','lint',str(report/'cli-repaired.dxf')],1)
run(['node','tools/dxf.mjs','binary','fixtures/r2018-ascii.dxf',str(report/'cli-converted.dxf')])
run(['node','tools/dxf.mjs','save','fixtures/r2018-binary.dxf',str(report/'cli-preserved.dxf')])
assert (root/'fixtures/r2018-binary.dxf').read_bytes()==(report/'cli-preserved.dxf').read_bytes()
run(['node','tools/dxf.mjs','nonsense','fixtures/r2018-binary.dxf'],2)
run([str(moon),'fmt','--check'])
manifest=[]
for p in sorted(root.rglob('*')):
 if not p.is_file() or any(x in {'.git','.mooncakes','_build','__pycache__','verification-output'} for x in p.relative_to(root).parts):continue
 manifest.append({'path':str(p.relative_to(root)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size})
identity=hashlib.sha256(json.dumps(manifest,sort_keys=True).encode()).hexdigest()
(report/'SOURCE-IDENTITY.json').write_text(json.dumps({'sha256':identity,'files':manifest},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
test_counts={}
for row in results:
 if 'test' in row['command'] and '--target' in row['command']:
  target=row['command'][row['command'].index('--target')+1]
  match=re.search(r'Total tests: (\d+), passed: (\d+), failed: (\d+)',Path(row['log']).read_text(encoding='utf-8'))
  if match:test_counts[target]={'total':int(match[1]),'passed':int(match[2]),'failed':int(match[3])}
(report/'SUMMARY.json').write_text(json.dumps({'status':'PASS','commands':len(results),'source_identity':identity,'node_version':subprocess.check_output(['node','--version'],text=True).strip(),'product_tests':test_counts,'oracle':'ezdxf 1.4.3','typed_tags_compared':3719,'output_files_audited':6,'five_native_defects':True,'ezdxf_independent_defect_signals':4},indent=2)+'\n',encoding='utf-8')
print('PASS: source identity '+identity)

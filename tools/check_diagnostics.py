"""Compare native defect categories to independent ezdxf loading/audit evidence.
Loader repair and audit are separate stages; counts/order are not equated.
"""
import io,json,logging,subprocess,sys
from pathlib import Path
import ezdxf
from ezdxf.lldxf.tagger import ascii_tags_loader
ROOT=Path(__file__).resolve().parents[1]
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
ezdxf.options.write_fixed_meta_data_for_testing=True
doc=ezdxf.new('R2018');m=doc.modelspace()
one=m.add_line((0,0),(1,1));two=m.add_line((2,2),(3,3))
doc.appids.new('TEST');one.set_xdata('TEST',[(1002,'{'),(1000,'content'),(1002,'}')])
s=io.StringIO();doc.write(s)
tags=[(t.code,t.value) for t in ascii_tags_loader(io.StringIO(s.getvalue()))]
def txt(ts):return ''.join(f'{c}\n{v}\n' for c,v in ts)
cases={
 'DuplicateHandle':txt([(c,one.dxf.handle if c==5 and v==two.dxf.handle else v) for c,v in tags]),
 'MissingEof':txt(tags[:-1]),
 'UnclosedSection':txt(tags[:-2]+tags[-1:]),
 'UnbalancedXdata':txt([(c,v) for c,v in tags if not(c==1002 and v=='}')]),
}
missing=ezdxf.new('R2018');missing.modelspace().add_blockref('NONEXISTENT',(0,0))
s=io.StringIO();missing.write(s);cases['DanglingBlock']=s.getvalue()
rows=[]
for expected,text in cases.items():
 p=out/(expected+'.dxf');p.write_text(text,encoding='utf-8',newline='')
 proc=subprocess.run(['node',str(ROOT/'tools'/'dxf.mjs'),'lint',str(p)],capture_output=True,text=True,encoding='utf-8')
 assert proc.returncode==1,(expected,proc.stdout,proc.stderr)
 native=json.loads(proc.stdout);assert expected in native['diagnostics'],native
 record={'case':expected,'native_exit':proc.returncode,'native_codes':native['diagnostics']}
 log=io.StringIO();handler=logging.StreamHandler(log);logger=logging.getLogger('ezdxf');logger.addHandler(handler)
 try:
  ref=ezdxf.read(io.StringIO(text));auditor=ref.audit()
  record['audit_errors']=[{'code':int(x.code),'message':x.message} for x in auditor.errors]
  record['audit_fixes']=[{'code':int(x.code),'message':x.message} for x in auditor.fixes]
 except Exception as e:record['load_error']=type(e).__name__+': '+str(e)
 finally:logger.removeHandler(handler)
 record['loader_warnings']=log.getvalue()
 if expected=='DanglingBlock':
  assert any(x['code']==103 for x in record.get('audit_fixes',[])+record.get('audit_errors',[])),record
 record['comparison']='native category plus independent load/audit signals; no assertion of equal counts'
 rows.append(record)
report={'ezdxf':ezdxf.__version__,'rows':rows}
(out/'diagnostic-comparison.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))

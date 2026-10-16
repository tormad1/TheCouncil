"""No inference: prove the installed Codex OS sandbox confines write access."""
import json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
inside=ROOT/'.local/sandbox-probe/workspace';outside=ROOT/'.local/sandbox-probe/protected'
inside.mkdir(parents=True,exist_ok=True);outside.mkdir(parents=True,exist_ok=True)
target=outside/'historical-fixture.txt';target.write_text('unchanged')
program='''import pathlib,sys
pathlib.Path("inside.txt").write_text("allowed")
try:
 pathlib.Path(sys.argv[1]).write_text("forbidden")
except PermissionError:
 print("OUTSIDE_WRITE_DENIED");sys.exit(0)
sys.exit(9)
'''
cmd=['codex','sandbox','--permission-profile',':workspace','-C',str(inside),'--',sys.executable,'-c',program,str(target)]
result=subprocess.run(cmd,capture_output=True,text=True,timeout=60)
ok=result.returncode==0 and 'OUTSIDE_WRITE_DENIED'in result.stdout and target.read_text()=='unchanged'
report={'ok':ok,'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr,'model_calls':0}
(ROOT/'docs/sandbox-results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
if ok:(ROOT/'.local/SANDBOX_PASSED').write_text(json.dumps(report))
sys.exit(not ok)

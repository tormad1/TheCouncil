"""No inference: verify Windows builder writes and protected-path denial."""
import argparse,json,os,subprocess,sys,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def check(codex,workspace,sandbox='mxc'):
    workspace=Path(workspace).resolve()
    roots=ROOT/'.local/workspaces'
    if roots.resolve() not in workspace.parents:raise ValueError('Preflight requires an assigned staging workspace')
    protected=ROOT/'.local/sandbox-probe/protected'
    protected.mkdir(parents=True,exist_ok=True)
    target=protected/('gateway-'+uuid.uuid4().hex+'.txt');target.write_text('unchanged')
    marker='.council-preflight-'+uuid.uuid4().hex
    program='''from pathlib import Path
import sys
p=Path(sys.argv[1]);p.write_text("allowed");p.unlink()
try:Path(sys.argv[2]).write_text("forbidden")
except PermissionError:print("BUILDER_WRITE_ALLOWED_OUTSIDE_DENIED");sys.exit(0)
sys.exit(9)
'''
    command=[str(codex),'-c',f'windows.sandbox="{sandbox}"','sandbox','--include-managed-config','--permission-profile',':workspace','-C',str(workspace),'--',sys.executable,'-c',program,marker,str(target)]
    try:
        result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=45,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt'else 0)
        ok=result.returncode==0 and 'BUILDER_WRITE_ALLOWED_OUTSIDE_DENIED'in result.stdout and target.read_text()=='unchanged'
        return dict(ok=ok,model_calls=0,sandbox=sandbox,exit_code=result.returncode,stdout=result.stdout,stderr=result.stderr)
    finally:
        target.unlink(missing_ok=True)
        (workspace/marker).unlink(missing_ok=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--codex',required=True);parser.add_argument('--workspace',required=True);parser.add_argument('--sandbox',default='mxc');a=parser.parse_args()
    try:report=check(a.codex,a.workspace,a.sandbox)
    except Exception as error:report=dict(ok=False,model_calls=0,error=str(error))
    print(json.dumps(report));sys.exit(not report['ok'])

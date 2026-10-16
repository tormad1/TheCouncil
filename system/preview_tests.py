"""Real offline MXC client -> trusted verifier roundtrip, with no model call."""
from pathlib import Path
import json,os,shutil,subprocess,sys,threading,uuid
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'system'))
import preview_service
os.chdir(ROOT)
workspace=ROOT/'.local/workspaces'/('broker-test-'+uuid.uuid4().hex)
artifact=workspace/'artifact';shutil.copytree(ROOT/'shared/defold-template',artifact)
manifest=dict(id=9002,title='Broker fixture?',slug='broker-fixture',date='2000-01-01',member='fixture',form='defold-2d',summary='Infrastructure fixture.',observation='File-only preview.',concepts=['fixture'],mechanisms=['fixture'],interactions=['keyboard'],toolchain={},production={},entry='game.project')
(artifact/'manifest.json').write_text(json.dumps(manifest),encoding='utf-8')
project=artifact/'game.project';project.write_text(project.read_text(encoding='utf-8').replace('title = Collective studio','title = Broker fixture?'),encoding='utf-8')
stop=threading.Event();worker=threading.Thread(target=preview_service.serve,args=(workspace,stop),daemon=True);worker.start()
paths=json.loads((ROOT/'.local/toolchain/paths.json').read_text(encoding='utf-8'))
command=[paths['codex'],'-c','windows.sandbox="mxc"','sandbox','--include-managed-config','--permission-profile',':workspace','-C',str(workspace),'--',sys.executable,str(ROOT/'system/preview_client.py'),str(workspace)]
try:
    result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',timeout=60)
    response=json.loads(result.stdout)if result.stdout.strip()else {}
    report=dict(ok=result.returncode==0 and response.get('ok',False),model_calls=0,exit_code=result.returncode,stderr=result.stderr,response=response)
finally:stop.set();worker.join(timeout=2)
(ROOT/'docs/preview-broker-results.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2));sys.exit(not report['ok'])

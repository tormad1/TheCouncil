"""Builder-side file request; never opens network connections."""
from pathlib import Path
import json,sys,time,uuid
ROOT=Path(__file__).resolve().parents[1]

def request(workspace,timeout=240):
    workspace=Path(workspace).resolve();roots=(ROOT/'.local/workspaces').resolve()
    if roots not in workspace.parents:raise ValueError('Assigned workspace required')
    channel=workspace/'.preview';channel.mkdir(exist_ok=True)
    request_id=uuid.uuid4().hex;message=channel/'request.json';temporary=channel/(request_id+'.tmp')
    temporary.write_text(json.dumps({'id':request_id,'operation':'preview'}),encoding='utf-8');temporary.replace(message)
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        response=channel/'response.json'
        if response.exists():
            try:
                result=json.loads(response.read_text(encoding='utf-8'))
                if result.get('id')==request_id:return result['report']
            except (OSError,ValueError):pass
        time.sleep(.2)
    return {'ok':False,'errors':['Trusted preview service did not respond before timeout.'],'classification':'infrastructure'}

if __name__=='__main__':
    try:report=request(sys.argv[1])
    except Exception as error:report={'ok':False,'errors':[str(error)]}
    print(json.dumps(report,ensure_ascii=True));sys.exit(not report['ok'])

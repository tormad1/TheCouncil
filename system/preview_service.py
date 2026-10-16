"""Trusted stage-bound verifier. Accepts only a fixed preview operation via files."""
from pathlib import Path
import argparse,json,os,re,subprocess,sys,threading,time
ROOT=Path(__file__).resolve().parents[1]

def serve(workspace,stop,owner_pid=None,lifetime=1800):
    import host
    workspace=Path(workspace).resolve();roots=(ROOT/'.local/workspaces').resolve()
    if roots not in workspace.parents:raise ValueError('Assigned workspace required')
    channel=workspace/'.preview';channel.mkdir(exist_ok=True);seen=set();deadline=time.monotonic()+lifetime
    installed=json.loads((ROOT/'.local/toolchain/paths.json').read_text(encoding='utf-8'))
    python=installed.get('python',sys.executable)
    while not stop.is_set()and time.monotonic()<deadline:
        if owner_pid and not host.alive(owner_pid):break
        path=channel/'request.json'
        try:
            message=json.loads(path.read_text(encoding='utf-8'));identifier=message.get('id','')
            if not re.fullmatch('[0-9a-f]{32}',identifier)or message.get('operation')!='preview'or identifier in seen:
                stop.wait(.2);continue
        except (OSError,ValueError):stop.wait(.2);continue
        seen.add(identifier)
        try:
            process=host.execute(dict(argv=[python,str(ROOT/'system/run.py'),'preview',str(workspace/'artifact')],cwd=str(ROOT),timeout=210))
            lines=process['stdout'].splitlines();report=None
            for line in reversed(lines):
                try:
                    candidate=json.loads(line)
                    if isinstance(candidate,dict)and 'ok'in candidate:report=candidate;break
                except ValueError:pass
            if report is None:report={'ok':False,'errors':[process['stderr']or process['stdout']],'classification':'infrastructure'}
        except Exception as error:report={'ok':False,'errors':[str(error)],'classification':'infrastructure'}
        host.atomic(channel/'response.json',json.dumps({'id':identifier,'report':report}))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--workspace',required=True);parser.add_argument('--owner-pid',type=int);parser.add_argument('--lifetime',type=int,default=1800);a=parser.parse_args()
    serve(a.workspace,threading.Event(),a.owner_pid,a.lifetime)

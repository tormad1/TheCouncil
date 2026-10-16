"""OS boundary for the Lua orchestrator. No model invocation policy lives here."""
import contextlib
import datetime as dt
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local/python'))
OWNER_PID = os.getpid()

def native_owner():
    """Find the Lua caller across os.execute's optional command-shell process."""
    parent=os.getppid()
    if os.name=='nt':
        import ctypes
        from ctypes import wintypes as w
        class Entry(ctypes.Structure):
            _fields_=[('size',w.DWORD),('usage',w.DWORD),('pid',w.DWORD),('heap',ctypes.c_size_t),('module',w.DWORD),('threads',w.DWORD),('parent',w.DWORD),('priority',w.LONG),('flags',w.DWORD),('name',w.WCHAR*260)]
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.CreateToolhelp32Snapshot.restype=w.HANDLE
        kernel.Process32FirstW.argtypes=[w.HANDLE,ctypes.POINTER(Entry)]
        kernel.Process32NextW.argtypes=[w.HANDLE,ctypes.POINTER(Entry)]
        kernel.CloseHandle.argtypes=[w.HANDLE]
        snap=kernel.CreateToolhelp32Snapshot(2,0);entry=Entry();entry.size=ctypes.sizeof(entry)
        try:
            present=kernel.Process32FirstW(snap,ctypes.byref(entry))
            while present:
                if entry.pid==parent:
                    return entry.parent if entry.name.lower()in ('cmd.exe','powershell.exe','pwsh.exe')else parent
                present=kernel.Process32NextW(snap,ctypes.byref(entry))
        finally:kernel.CloseHandle(snap)
    else:
        try:
            name=Path(f'/proc/{parent}/comm').read_text().strip()
            if name in ('sh','bash','dash','zsh'):
                return int(Path(f'/proc/{parent}/stat').read_text().rsplit(')',1)[1].split()[1])
        except OSError:pass
    return parent

def atomic(path, data):
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=path.name+'.', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as f:
            f.write(data); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, path)
        if os.name != 'nt':
            fd = os.open(path.parent, os.O_RDONLY)
            try: os.fsync(fd)
            finally: os.close(fd)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def alive(pid):
    if pid <= 0: return True  # unknown PID must never be treated as dead
    if os.name == 'nt':
        import ctypes
        kernel = ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.OpenProcess.restype=ctypes.c_void_p
        kernel.OpenProcess.argtypes=[ctypes.c_ulong,ctypes.c_int,ctypes.c_ulong]
        kernel.CloseHandle.argtypes=[ctypes.c_void_p]
        kernel.GetExitCodeProcess.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_ulong)]
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle: return ctypes.get_last_error() != 87
        code = ctypes.c_ulong()
        try:
            if not kernel.GetExitCodeProcess(handle, ctypes.byref(code)): return True
            return code.value == 259
        finally: kernel.CloseHandle(handle)
    try: os.kill(pid, 0); return True
    except ProcessLookupError: return False
    except PermissionError: return True

def path_safe(root, path):
    root, path = Path(root).resolve(), Path(path).resolve()
    if path != root and root not in path.parents: raise ValueError('Path outside assigned root')
    return path

def inventory(path):
    out = {}
    for p in sorted(Path(path).rglob('*')):
        if p.is_symlink() or (hasattr(p, 'is_junction') and p.is_junction()): raise ValueError('Links are forbidden: '+str(p))
        if p.is_file(): out[p.relative_to(path).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out

def execute(a):
    env = {k:v for k,v in os.environ.items() if k.upper() in {
        'PATH','SYSTEMROOT','WINDIR','COMSPEC','PATHEXT','TEMP','TMP','HOME','USERPROFILE',
        'LOCALAPPDATA','APPDATA','CODEX_HOME','JAVA_HOME','LANG','LC_ALL',
        'SYSTEMDRIVE','PROGRAMDATA','ALLUSERSPROFILE','PROGRAMFILES','PROGRAMFILES(X86)',
        'PROGRAMW6432','COMMONPROGRAMFILES','COMMONPROGRAMFILES(X86)','COMMONPROGRAMW6432',
        'HOMEDRIVE','HOMEPATH','OS','PROCESSOR_ARCHITECTURE','NUMBER_OF_PROCESSORS',
        'CODEX_WINDOWS_SANDBOX_PACKAGE_FAMILY'}}
    started = time.monotonic()
    kwargs = dict(cwd=a.get('cwd',str(ROOT)),env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                  stderr=subprocess.PIPE,text=True,encoding='utf-8',errors='replace')
    if os.name == 'nt': kwargs['creationflags'] = subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP
    else: kwargs['start_new_session'] = True
    argv=list(a['argv'])
    # Windows CreateProcess does not resolve executables as an interactive shell does.
    # Resolve PATH entries before launch; the configured Codex path may be absolute.
    argv[0]=shutil.which(argv[0]) or argv[0]
    preview_stop=None;preview_thread=None
    if a.get('preview_workspace'):
        from preview_service import serve
        preview_stop=threading.Event()
        preview_thread=threading.Thread(target=serve,args=(a['preview_workspace'],preview_stop),daemon=True)
        preview_thread.start()
    try:
        p = subprocess.Popen(argv,**kwargs)
    except OSError as error:
        if preview_stop:preview_stop.set()
        result=dict(exit_code=127,started=False,stdout='',stderr=f'Could not start {argv[0]}: {error}',duration_seconds=0)
        for key in ('stdout','stderr'):
            if a.get(key):atomic(a[key],result[key])
        return result
    try:
        stdout,stderr = p.communicate(a.get('input',''),timeout=a.get('timeout',1800)); code=p.returncode
    except subprocess.TimeoutExpired:
        if os.name == 'nt': subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True,creationflags=subprocess.CREATE_NO_WINDOW)
        else: os.killpg(p.pid,signal.SIGKILL)
        stdout,stderr=p.communicate(); code=124
    for key,text in [('stdout',stdout),('stderr',stderr)]:
        if a.get(key): atomic(a[key],text)
    if preview_stop:preview_stop.set()
    return dict(exit_code=code,started=True,stdout=stdout[-16000:],stderr=stderr[-16000:],duration_seconds=time.monotonic()-started)

def smoke(a):
    from playwright.sync_api import sync_playwright
    from importlib.metadata import PackageNotFoundError, version
    directory=Path(a['path']).resolve()
    html=list(directory.rglob('*.html'))
    if not html: raise ValueError('No bundled HTML5 entry point')
    handler=lambda *args,**kw:http.server.SimpleHTTPRequestHandler(*args,directory=str(directory),**kw)
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    errors=[]; logs=[];warnings=[];infrastructure=False;browser_info={'python':sys.executable}
    try:browser_info['playwright']=version('playwright')
    except PackageNotFoundError:browser_info['playwright']='unknown'
    try:
        with sync_playwright() as pw:
            browser_type=pw.chromium
            executable=Path(browser_type.executable_path)
            browser_info.update(executable=str(executable),exists=executable.is_file(),local_app_data=os.environ.get('LOCALAPPDATA'))
            browser=None;launch_errors=[]
            # Pin the verified full Chromium executable. Playwright's implicit
            # headless-shell selection can point at a different cache entry in
            # scheduled/background launches, even when the pinned browser exists.
            if executable.is_file():
                try:browser=browser_type.launch(headless=True,executable_path=str(executable))
                except Exception as error:launch_errors.append(f'pinned executable: {error}')
            if browser is None:
                try:
                    browser=browser_type.launch(headless=True)
                    if launch_errors:warnings.extend(launch_errors)
                except Exception as error:
                    launch_errors.append(f'default executable: {error}')
                    infrastructure=True
                    errors.append('Browser launch failed; '+ ' | '.join(launch_errors))
            if browser is not None:
                try:
                    page=browser.new_page(viewport={'width':960,'height':640})
                    page.on('pageerror',lambda e:errors.append(str(e)))
                    page.on('console',lambda m:(logs.append(m.text),errors.append(m.text) if m.type=='error' or any(x in m.text.lower() for x in ['lua error','shader error','failed to load']) else None))
                    page.route('**/*',lambda r:r.continue_() if r.request.url.startswith(('http://127.0.0.1:','data:','blob:')) else r.abort())
                    page.goto(f'http://127.0.0.1:{server.server_port}/'+html[0].relative_to(directory).as_posix(),wait_until='networkidle',timeout=45000)
                    page.wait_for_function('window.Module && window.Module.calledRun === true',timeout=30000)
                    page.wait_for_timeout(4000)
                    normal=page.screenshot(path=a['output'])
                    if a.get('check_identity'):
                        page.locator('#canvas').click(position={'x':10,'y':10})
                        page.keyboard.down('F1');page.wait_for_timeout(150);page.keyboard.up('F1');page.wait_for_timeout(250)
                        identity=page.screenshot(path=str(Path(a['output']).with_name('preview-identity.png')))
                        if identity==normal:errors.append('F1 identity overlay did not change the frame')
                        page.keyboard.press('Escape')
                finally:browser.close()
    finally: server.shutdown();server.server_close()
    atomic(a['log'],'\n'.join(logs+errors))
    return {'ok':not errors,'errors':errors,'warnings':warnings,'infrastructure':infrastructure,'browser':browser_info,'log':a['log']}

def dispatch(a):
    op=a['op'];p=Path(a.get('path','.'))
    if op=='uuid':return uuid.uuid4().hex
    if op=='read': return p.read_text(encoding='utf-8-sig') if p.exists() else None
    if op=='exists': return p.exists()
    if op=='write': atomic(p,a['data']);return True
    if op=='mkdir': p.mkdir(parents=True,exist_ok=True);return True
    if op=='remove':
        path_safe(ROOT/'.local',p)
        if p.is_dir(): shutil.rmtree(p)
        elif p.exists():p.unlink()
        return True
    if op=='copy':
        source=Path(a['source']); dest=p
        inventory(source)
        if dest.exists(): raise ValueError('Copy destination already exists')
        shutil.copytree(source,dest);return True
    if op=='tree':return inventory(p)
    if op=='sha256':return hashlib.sha256(p.read_bytes()).hexdigest()
    if op=='files':return [{'path':x.relative_to(p).as_posix(),'size':x.stat().st_size} for x in sorted(p.rglob('*')) if x.is_file()]
    if op=='clock':
        timestamp=a.get('timestamp',time.time()); z=dt.datetime.fromtimestamp(timestamp,ZoneInfo(a['zone']))
        iso=z.isocalendar()
        return {'timestamp':int(timestamp),'date':z.date().isoformat(),'weekday':z.isoweekday(),'week':f'{iso.year}-W{iso.week:02d}','iso':z.isoformat()}
    if op=='date':
        d=dt.date.fromisoformat(a['date']);z=dt.datetime.combine(d,dt.time(12),ZoneInfo(a['zone']));return dispatch({'op':'clock','zone':a['zone'],'timestamp':z.timestamp()})
    if op=='lock':
        p.parent.mkdir(parents=True,exist_ok=True)
        try:p.mkdir()
        except FileExistsError:
            owner=p/'owner.json'
            try: info=json.loads(owner.read_text());old= time.time()-info['timestamp']>a['timeout'] and not alive(info['pid'])
            except Exception:old=False
            if not old:return None
            # Serialize stale recovery so competing reclaimers cannot remove a new lock.
            claim=p/'reclaim'
            try: fd=os.open(claim,os.O_CREAT|os.O_EXCL|os.O_WRONLY);os.close(fd)
            except FileExistsError:return None
            try:
                current=json.loads(owner.read_text())
                if current!=info or alive(current['pid']):return None
                owner.unlink();claim.unlink();p.rmdir()
            finally:
                if claim.exists():claim.unlink()
            try:p.mkdir()
            except FileExistsError:return None
        token=uuid.uuid4().hex
        atomic(p/'owner.json',json.dumps(dict(pid=a.get('pid',os.getpid()),timestamp=time.time(),state=a.get('state','unknown'),work=a.get('work',0),token=token)))
        return token
    if op=='unlock':
        info=json.loads((p/'owner.json').read_text())
        if info['token']!=a['token']:raise ValueError('Lock ownership changed')
        (p/'owner.json').unlink();p.rmdir();return True
    if op=='pid':return OWNER_PID
    if op=='resolve':return str(p.resolve())
    if op=='exec':return execute(a)
    if op=='smoke':return smoke(a)
    if op=='static':
        suffix=p.suffix.lower()
        if suffix not in ('.json','.svg','.csv','.txt'):
            if not p.stat().st_size:raise ValueError('Empty artefact')
            return True
        data=p.read_text(encoding='utf-8')
        if suffix=='.json':json.loads(data)
        elif suffix=='.svg':
            if '<!DOCTYPE' in data.upper() or '<!ENTITY' in data.upper():raise ValueError('SVG entities are forbidden')
            doc=ET.fromstring(data)
            if doc.tag.split('}')[-1]!='svg':raise ValueError('Not SVG')
            for node in doc.iter():
                if node.tag.split('}')[-1] in ('script','foreignObject'):raise ValueError('Active SVG content')
                for key,value in node.attrib.items():
                    if key.lower().startswith('on') or ('href' in key and not value.startswith('#')):raise ValueError('External or executable SVG reference')
        elif suffix=='.csv':
            import csv,io
            rows=list(csv.reader(io.StringIO(data),strict=True))
            if not rows or any(len(r)!=len(rows[0]) for r in rows):raise ValueError('Nonrectangular CSV')
        if not data.strip():raise ValueError('Empty artefact')
        return True
    if op=='seal':
        # Read-only bits supplement sandbox and hash enforcement; owner can intentionally amend.
        for f in p.rglob('*'):
            if f.is_file():f.chmod(0o444)
        return True
    if op=='publish-copy':
        src=Path(a['source']); target=p
        if target.exists():return inventory(target)
        tmp=target.with_name('.'+target.name+'.publishing')
        if tmp.exists():shutil.rmtree(tmp)
        shutil.copytree(src,tmp)
        os.replace(tmp,target)
        return inventory(target)
    raise ValueError('Unknown host operation '+op)

if __name__=='__main__':
    OWNER_PID=native_owner()
    req,out=sys.argv[1:3]
    try:result={'ok':True,'value':dispatch(json.loads(Path(req).read_text(encoding='utf-8')))}
    except Exception as e:result={'ok':False,'error':str(e)}
    atomic(out,json.dumps(result,ensure_ascii=False))

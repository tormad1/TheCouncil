"""Explicit, pinned infrastructure installation. Never called by a daily job."""
import argparse,hashlib,json,os,platform,shutil,subprocess,sys,tarfile,urllib.request,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'.local/toolchain'
def fetch(url,path):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists():
        print('Downloading',url,flush=True)
        req=urllib.request.Request(url,headers={'User-Agent':'Computational-art-studio-setup'})
        with urllib.request.urlopen(req,timeout=90) as source,open(str(path)+'.part','wb') as out:shutil.copyfileobj(source,out)
        os.replace(str(path)+'.part',path)
    return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--install',action='store_true');a=parser.parse_args()
    if not a.install:parser.error('Pass --install to install the pinned local toolchain (no scheduling or model calls).')
    os.chdir(ROOT);DEST.mkdir(parents=True,exist_ok=True)
    lock=json.loads((ROOT/'toolchain.lock').read_text())
    hashes={}
    hashes['bob.jar']=fetch('https://github.com/defold/defold/releases/download/1.13.2/bob.jar',DEST/'bob.jar')
    win=platform.system()=='Windows'
    if win:
        name='OpenJDK25U-jre_x64_windows_hotspot_25.0.1_8.zip'
        url='https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.1%2B8/'+name
        hashes[name]=fetch(url,DEST/name)
        with zipfile.ZipFile(DEST/name) as z:z.extractall(DEST/'java')
        resvg='resvg-win64.zip'
    else:resvg='resvg-linux-x86_64.tar.gz'
    hashes[resvg]=fetch('https://github.com/linebender/resvg/releases/download/v0.45.1/'+resvg,DEST/resvg)
    if win:
        with zipfile.ZipFile(DEST/resvg)as z:z.extractall(DEST/'resvg')
        exe=next((DEST/'resvg').rglob('resvg.exe'));shutil.copy2(exe,DEST/'resvg.exe')
    else:
        with tarfile.open(DEST/resvg)as t:t.extractall(DEST/'resvg',filter='data')
        exe=next((DEST/'resvg').rglob('resvg'));exe.chmod(0o755)
    for filename,digest in hashes.items():
        expected=lock.get('sha256',{}).get(filename)
        if expected and expected!=digest:raise RuntimeError('Checksum mismatch: '+filename)
    # Official source assets only. Exact version, small Regular subset, upstream licence.
    base='https://unpkg.com/@phosphor-icons/core@2.1.1/'
    for icon in ['arrow-left','arrow-right','play','pause','speaker-high','speaker-slash','arrow-counter-clockwise','x','magnifying-glass','file','folder','eye','check','warning']:
        fetch(base+'assets/regular/'+icon+'.svg',ROOT/'shared/icons/phosphor'/f'{icon}.svg')
    fetch(base+'LICENSE',ROOT/'shared/licences/Phosphor-LICENSE')
    subprocess.run([sys.executable,'-m','pip','install','--target',str(ROOT/'.local/python'),'lupa==2.6','tzdata==2026.2','playwright==1.55.0'],check=True)
    env=dict(os.environ,PYTHONPATH=str(ROOT/'.local/python'))
    subprocess.run([sys.executable,'-m','playwright','install','chromium'],env=env,check=True)
    java=next((DEST/'java').rglob('java.exe')) if win else Path(shutil.which('java')or 'java')
    subprocess.run([str(java),'-jar',str(DEST/'bob.jar'),'--version'],check=True)
    lock['sha256']=hashes
    (ROOT/'toolchain.lock').write_text(json.dumps(lock,indent=2)+'\n')
    (DEST/'paths.json').write_text(json.dumps({'java':str(java),'resvg':str(DEST/'resvg.exe')if win else str(exe)}))
    print('Pinned tools installed. Live mode and scheduling remain disabled.')
if __name__=='__main__':main()

"""Real Bob, browser, rasterizer integration checks; no creative model calls."""
import json,os,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local/python'));sys.path.insert(0,str(ROOT/'system'))
import host
from lupa.lua54 import LuaRuntime
os.chdir(ROOT)
lua=LuaRuntime(unpack_returned_tuples=True)
def bridge(raw):
    try:return json.dumps({'ok':True,'value':host.dispatch(json.loads(raw))})
    except Exception as e:return json.dumps({'ok':False,'error':str(e)})
lua.globals().HOST=bridge
base=ROOT/'.local/integration'
if base.exists():shutil.rmtree(base)
base.mkdir(parents=True)
shutil.copytree(ROOT/'shared/defold-template',base/'artifact')
manifest={'id':9001,'title':'Technical fixture','slug':'technical-fixture','date':'2000-01-01','member':'fixture','form':'defold-2d','summary':'Infrastructure verification only.','observation':'Technical fixture.','concepts':['fixture'],'mechanisms':['fixture'],'interactions':['keyboard'],'toolchain':json.loads((ROOT/'toolchain.lock').read_text()),'production':{},'entry':'game.project'}
(base/'artifact/manifest.json').write_text(json.dumps(manifest))
result=json.loads(lua.execute("F=require('system.fs');J=require('system.json');c=dofile('config.lua');return J.encode(require('system.verify').run(c,'.local/integration/artifact'))"))
svg=base/'fixture.svg';svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect x="8" y="8" width="48" height="48" fill="#111"/></svg>')
raster=json.loads(lua.execute("return J.encode(require('system.verify').rasterize(c,'.local/integration/fixture.svg','.local/integration/fixture.png',64,64))"))
report={'defold_verification':result,'rasterizer':raster,'live_model_calls':0,'ok':result['ok']and raster['exit_code']==0}
(ROOT/'docs/toolchain-results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
if report['ok']:(ROOT/'.local/TOOLCHAIN_PASSED').write_text(json.dumps({'ok':True}))
sys.exit(not report['ok'])

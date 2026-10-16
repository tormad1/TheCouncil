"""Optional Lua 5.4 launcher when no native lua executable is installed."""
import json,os,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local/python'))
sys.path.insert(0,str(Path(__file__).parent))
try:from lupa.lua54 import LuaRuntime
except ImportError:raise SystemExit('Install Lua 5.4, or: python -m pip install --target .local/python lupa==2.6 tzdata==2026.2')
import host
os.chdir(ROOT)
lua=LuaRuntime(unpack_returned_tuples=True)
def bridge(raw):
    try:return json.dumps({'ok':True,'value':host.dispatch(json.loads(raw))},ensure_ascii=False)
    except Exception as e:return json.dumps({'ok':False,'error':str(e)})
lua.globals().HOST=bridge
lua.globals().arg=lua.table_from({i:v for i,v in enumerate(['system/council.lua']+sys.argv[1:])})
try:lua.execute((ROOT/'system/council.lua').read_text(encoding='utf-8'))
except Exception as e:raise SystemExit(str(e))

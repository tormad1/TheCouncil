local J=require('system.json');local M={}
local function quote(s)
 if package.config:sub(1,1)=='\\' then assert(not s:find('["%%\r\n]'),'unsafe shell path');return '"'..s..'"' end
 return "'"..s:gsub("'","'\\''").."'"
end
function M.call(a)
 local raw
 if HOST then raw=HOST(J.encode(a)) else
  local req=os.tmpname();local out=req..'.json';local f=assert(io.open(req,'wb'));f:write(J.encode(a));f:close()
  local python=os.getenv('COUNCIL_PYTHON') or 'python'
  local ok=os.execute(quote(python)..' '..quote('system/host.py')..' '..quote(req)..' '..quote(out))
  assert(ok,'OS bridge failed');f=assert(io.open(out,'rb'));raw=f:read('*a');f:close();os.remove(req);os.remove(out)
 end
 local r=J.decode(raw);assert(r.ok,r.error);if r.value==J.null then return nil end;return r.value
end
function M.read(p)return M.call{op='read',path=p}end
function M.exists(p)return M.call{op='exists',path=p}end
function M.write(p,s)return M.call{op='write',path=p,data=s}end
function M.load(p,default)local s=M.read(p);return s and J.decode(s) or default end
function M.save(p,v)return M.write(p,J.encode(v)..'\n')end
function M.mkdir(p)return M.call{op='mkdir',path=p}end
function M.lines(p)local t=J.array();for line in (M.read(p) or ''):gmatch('[^\r\n]+')do t[#t+1]=J.decode(line)end;return t end
function M.append(p,v)local t=M.lines(p);t[#t+1]=v;local out={};for _,r in ipairs(t)do out[#out+1]=J.encode(r)end;M.write(p,table.concat(out,'\n')..'\n')end
function M.exec(argv,cwd,timeout,input)return M.call{op='exec',argv=J.array(argv),cwd=cwd,timeout=timeout,input=input or ''}end
return M

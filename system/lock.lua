local F=require('system.fs');local M={}
function M.with(c,fn)
 local s=F.load('.local/current.json',{})
 local token=F.call{op='lock',path='.local/locks/heartbeat',timeout=c.process.lock_timeout_seconds,pid=F.call{op='pid'},state=s.state,work=s.id}
 if not token then return {state='LOCKED',message='Another heartbeat owns the lock.'} end
 local ok,result=xpcall(fn,debug.traceback)
 F.call{op='unlock',path='.local/locks/heartbeat',token=token}
 if not ok then error(result)end;return result
end
return M

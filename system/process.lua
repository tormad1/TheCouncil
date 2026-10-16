local F=require('system.fs');local M={}
function M.run(c,argv,cwd,prompt,dir)
 -- Ignore inherited user configuration (plugins/MCP/hooks) and strip child secrets.
 -- The OS sandbox, not prompt instructions, enforces write boundaries.
 return F.call{op='exec',argv=argv,cwd=cwd,input=prompt,timeout=c.process.timeout_seconds,stdout=dir..'/events.jsonl',stderr=dir..'/stderr.log'}
end
return M

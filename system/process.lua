local F=require('system.fs');local M={}
function M.preflight(c,cwd,dir)
 if package.config:sub(1,1)~='\\'then return true end
 local result=F.exec({c.process.python,'system/preflight.py','--codex',c.process.codex,'--workspace',cwd,'--sandbox',c.process.windows_sandbox or 'mxc'},'.',60)
 F.save(dir..'/preflight.json',result)
 return result.exit_code==0,result.stdout..'\n'..result.stderr
end
function M.run(c,argv,cwd,prompt,dir)
 -- Ignore inherited user configuration (plugins/MCP/hooks) and strip child secrets.
 -- The OS sandbox, not prompt instructions, enforces write boundaries.
 return F.call{op='exec',argv=argv,cwd=cwd,input=prompt,timeout=c.process.timeout_seconds,stdout=dir..'/events.jsonl',stderr=dir..'/stderr.log',preview_workspace=cwd:find('workspaces/',1,true) and cwd or nil}
end
return M

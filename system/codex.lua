-- Sole model gateway. No other module can launch a Codex job.
local F=require('system.fs');local J=require('system.json');local Budget=require('system.budget');local Workspace=require('system.workspace');local M={}
function M.paths(s,route)
 local dir='.local/runs/'..s.date..'/'..route
 if (s.build_attempt or 0)>0 and route~='ideate' and route~='ideate_retry' then dir=dir..'-attempt-'..s.build_attempt end
 return dir,dir..'/stage.requested.json',dir..'/stage.completed.json'
end
function M.command(c,s,route,cwd,dir)
 local r=c.routing[route];local ideate=route=='ideate' or route=='ideate_retry'
 local command=J.array{c.process.codex,'exec','--ignore-user-config','--ignore-rules','--ephemeral','--skip-git-repo-check','--model',c.models[r.model],
 '--sandbox',ideate and 'read-only'or 'workspace-write','-c','approval_policy="never"','-c','model_reasoning_effort="'..r.effort..'"',
 -- The trusted host supplies only its explicit non-secret environment allowlist.
 '-c','sandbox_workspace_write.network_access=false','-c','shell_environment_policy.inherit="all"',
 '-c','web_search="disabled"',
 '--cd',cwd,'--output-schema',dir..'/schema.json','--output-last-message',dir..'/answer.json','--json','-'}
 if package.config:sub(1,1)=='\\' then
  command[#command+1]='-c';command[#command+1]='windows.sandbox="'..(c.process.windows_sandbox or 'mxc')..'"'
 end
 return command
end
local function mock(c,s,route)
 if route=='ideate' or route=='ideate_retry' then
  local p=F.load('system/fixtures/valid-proposal.json')
  if not (s.scenario=='duplicate' and route=='ideate')then
   p.title='Fixture '..s.id;p.premise='Record fixture '..s.id..' width.';p.mechanisms=J.array{'literal-width-'..s.id}
  end
  p.member_move=require('system.creative').vocabulary.moves[s.member][1]
  return p
 end
 local artifact=Workspace.path(s)..'/artifact'
 local manifest=Workspace.manifest(c,s)
 if s.proposal.form=='svg' then manifest.entry='work.svg';F.write(artifact..'/work.svg','<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="40" height="40"/></svg>')
 elseif require('system.novelty').static(s.proposal.form)then F.write(artifact..'/work.txt','Fixture '..s.id..': width 40.\n')end
 if s.scenario=='broken' and route:find('build')then F.write(artifact..'/work.txt','TODO unfinished\n')end
 if s.scenario=='repair-fails' then F.write(artifact..'/work.txt','TODO unfinished\n')end
 F.save(artifact..'/manifest.json',manifest)
 local result=F.load('system/fixtures/successful-build.json')
 local exhibition=F.load('memory/exhibition.json',{works=J.array()}).works
 if #exhibition>=c.exhibition.maximum then result.retire_id=exhibition[1]end
 return result
end
function M.invoke(c,s,route,clock,prompt,dry,manual)
 local dir,requested,completed=M.paths(s,route)
 if dry then
  local r=c.routing[route];local ideation=route=='ideate' or route=='ideate_retry'
  local allowed,reason=Budget.authorize(c,s,route,clock,manual)
  return {stage=route,model=c.models[r.model],effort=r.effort,context_bytes=#prompt,sandbox=ideation and 'read-only'or 'workspace-write',command=M.command(c,s,route,ideation and dir..'/context'or Workspace.path(s),dir),budget_allowed=allowed,budget_reason=reason,budget_effect=s.mode=='live'and (r.model..'_'..r.effort..' +1')or 'zero: mock'}
 end
 if F.exists(completed)then local receipt=F.load(completed);assert(receipt.mode==s.mode,'Receipt mode mismatch');return receipt.result end
 local allowed,reason=Budget.authorize(c,s,route,clock,manual)
 if not allowed then return nil,'budget',reason end
 local cwd=(route=='ideate' or route=='ideate_retry')and dir..'/context' or Workspace.path(s)
 local r=c.routing[route];local command=M.command(c,s,route,cwd,dir)
 if F.exists(requested)then return nil,'uncertain','Requested stage has no completed receipt. Inspect logs and answer; never automatically repeat.'end
 F.mkdir(cwd);F.mkdir(dir)
 local schema=assert(F.read('system/schemas/'..((route=='ideate' or route=='ideate_retry')and 'proposal'or 'build')..'.json'))
 if route=='ideate' or route=='ideate_retry'then schema=J.encode(require('system.creative').schema(s.member))end
 F.write(dir..'/schema.json',schema);F.write(dir..'/prompt.txt',prompt)
 -- All output paths must be absolute because Codex executes inside an isolated cwd.
 local root=F.exec({c.process.python,'-c','import os; print(os.getcwd())'},'.',20).stdout:gsub('%s+$','')
 command=M.command(c,s,route,root..'/'..cwd,root..'/'..dir)
 if c.live_ai and route~='ideate' and route~='ideate_retry' then
  local ready,evidence=require('system.process').preflight(c,cwd,dir)
  if not ready then return nil,'failed','Builder permission preflight failed before inference: '..evidence end
 end
 local id=s.date..'-'..s.id..'-'..route..'-'..F.call{op='uuid'}
 F.save(requested,{invocation_id=id,timestamp=clock.timestamp,mode=s.mode,route=route,command=command})
 -- Reservation and event are one journal row. Unknown outcomes remain charged.
 F.append('.local/logs/model-usage.jsonl',{invocation_id=id,timestamp=clock.timestamp,work=s.id,stage=route,model=c.models[r.model],alias=r.model,effort=r.effort,prompt_bytes=#prompt,mode=s.mode,outcome='requested'})
 local before=F.call{op='tree',path='works'}
 local ok,result=pcall(function()
  if not c.live_ai then return mock(c,s,route)end
  local process=require('system.process').run(c,command,cwd,prompt,dir)
  F.save(dir..'/process.json',process)
  assert(process.exit_code==0,'Codex exited '..process.exit_code..': '..process.stderr)
  return assert(F.load(dir..'/answer.json'),'Missing structured output')
 end)
 assert(J.encode(before)==J.encode(F.call{op='tree',path='works'}),'Published work changed: stop and inspect sandbox')
 if not ok then
  F.save(dir..'/stage.failed.json',{error=tostring(result)})
  local rows={};local proc=F.load(dir..'/process.json')
  for _,event in ipairs(F.lines('.local/logs/model-usage.jsonl'))do
   if event.invocation_id==id then event.outcome=proc and proc.started==false and 'not_started' or 'failed';event.exit_code=proc and proc.exit_code or -1;event.duration_seconds=proc and proc.duration_seconds or 0;event.output_bytes=proc and #proc.stdout or 0 end
   rows[#rows+1]=J.encode(event)
  end
  F.write('.local/logs/model-usage.jsonl',table.concat(rows,'\n')..'\n')
  return nil,'failed',tostring(result)
 end
 if route=='ideate' or route=='ideate_retry'then
  -- Invalid proposals are retained for the deterministic gate and its one retry.
  if type(result)~='table'then return nil,'failed','Not a proposal object'end
 else
  if type(result.exhibit)~='boolean' or (result.retire_id~=J.null and type(result.retire_id)~='number')or type(result.curation_note)~='string'then return nil,'failed','Invalid build summary'end
 end
 F.save(completed,{invocation_id=id,mode=s.mode,result=result,timestamp=clock.timestamp})
 local ledger=F.lines('.local/logs/model-usage.jsonl')
 for _,event in ipairs(ledger)do if event.invocation_id==id then
  event.outcome='completed';event.output_bytes=#J.encode(result)
  local proc=F.load(dir..'/process.json');if proc then event.duration_seconds=proc.duration_seconds;event.exit_code=proc.exit_code else event.duration_seconds=0;event.exit_code=0 end
 end end
 local rows={};for _,event in ipairs(ledger)do rows[#rows+1]=J.encode(event)end;F.write('.local/logs/model-usage.jsonl',table.concat(rows,'\n')..'\n')
 return result
end
return M

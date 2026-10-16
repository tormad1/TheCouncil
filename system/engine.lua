local F=require('system.fs');local J=require('system.json');local State=require('system.state');local Clock=require('system.clock');local Gateway=require('system.codex');local Workspace=require('system.workspace');local Context=require('system.context');local M={}
local routes={IDEATE='ideate',IDEATE_RETRY='ideate_retry',REPAIR_SIMPLE='simple_repair',REPAIR_COMPLEX='complex_repair'}
function M.route(s)
 if s.state=='BUILD'then return require('system.novelty').static(s.proposal.form)and 'static_build'or 'defold_build'end
 return routes[s.state]
end
function M.prompt(c,s,route)
 if route=='ideate' or route=='ideate_retry'then return Context.ideate(c,s)end
 return Context.build(c,s,route~='static_build' and route~='defold_build')
end
function M.invoke(c,s,clock,route,manual)
 local result,kind,reason=Gateway.invoke(c,s,route,clock,M.prompt(c,s,route),false,manual)
 if not result then
  s.reason=reason
  if kind=='budget'then s.resume_state=s.state;return State.transition(s,'PAUSED_BUDGET')end
  return State.transition(s,'NEEDS_ATTENTION')
 end
 if route=='ideate' or route=='ideate_retry'then s.proposal=result;return State.transition(s,'PROPOSAL_GATE')end
 s.decision=result
 if route=='static_build' or route=='defold_build'then return State.transition(s,'VERIFY')end
 s.repairs=s.repairs+1;return State.transition(s,'VERIFY_AFTER_REPAIR')
end
function M.advance(c,clock,manual_run)
 if F.exists('.local/PAUSE')then return {state='PAUSED',message='Global PAUSE prevents inference.'}end
 local s=State.get()
 if not s or (s.date~=clock.date and not s.recovery)then s=State.prepare(c,clock)end
 if s.state=='PREPARE'then
  s.words=require('system.words').get(s.week).words
  if s.member=='human'then Workspace.prepare(c,s);return State.transition(s,'WAITING_FOR_HUMAN')end
  return State.transition(s,'IDEATE')
 end
 if s.state=='PAUSED_BUDGET'then
  local prior=s.state;s.state=s.resume_state
  local route=M.route(s)
  local allowed,reason=require('system.budget').authorize(c,s,route,clock,false)
  if not allowed then s.state=prior;s.reason=reason;return State.save(s)end
  return State.save(s)
 end
 if State.terminal[s.state]then return s end
 if s.state=='PROPOSAL_GATE'then
  local ok,issues,warnings=require('system.novelty').gate(s.proposal,s.member);s.warnings=warnings
  if not ok then
   s.rejection=J.encode(issues)
   if s.retry<c.budget.max_creative_retries then s.retry=s.retry+1;return State.transition(s,'IDEATE_RETRY')end
   return State.transition(s,'NEEDS_ATTENTION')
  end
  Workspace.prepare(c,s);return State.transition(s,'BUILD')
 end
 if s.state=='VERIFY' or s.state=='VERIFY_AFTER_REPAIR'then
  if s.member~='human' then
   local path=Workspace.path(s)..'/artifact/manifest.json';local ok,m=pcall(F.load,path)
   if ok and m then
    local provenance={repairs=J.array()}
    for _,event in ipairs(F.lines('.local/logs/model-usage.jsonl'))do if event.work==s.id and event.outcome=='completed'then
     if event.stage=='ideate' or event.stage=='ideate_retry'then provenance.ideation_model=event.model;provenance.ideation_effort=event.effort
     elseif event.stage=='static_build' or event.stage=='defold_build'then provenance.build_model=event.model;provenance.build_effort=event.effort
     else provenance.repairs[#provenance.repairs+1]={model=event.model,effort=event.effort,stage=event.stage}end
    end end
    m.production=provenance;m.toolchain=F.load('toolchain.lock');F.save(path,m)
   end
  end
  s.verification=require('system.verify').run(c,Workspace.path(s)..'/artifact',s)
  F.save('.local/runs/'..s.date..'/verification.json',s.verification)
  if s.verification.ok then s.infrastructure_retries=0;s.reason=nil;return State.transition(s,'PUBLISH')end
  if s.verification.classification=='infrastructure' then
   s.infrastructure_retries=(s.infrastructure_retries or 0)+1
   local maximum=c.budget.max_infrastructure_retries or 2
   if s.infrastructure_retries<maximum then
    s.reason='Verification infrastructure failed; retrying without a model call ('..s.infrastructure_retries..'/'..maximum..')'
    return State.transition(s,s.state)
   end
   s.reason='Verification infrastructure remained unavailable after '..s.infrastructure_retries..' checks: '..table.concat(s.verification.errors or {},'; ')
   return State.transition(s,'NEEDS_ATTENTION')
  end
  if s.member=='human'then return State.transition(s,'WAITING_FOR_HUMAN')end
  if s.repairs<c.budget.max_automatic_repairs then return State.transition(s,s.verification.classification=='complex' and 'REPAIR_COMPLEX'or 'REPAIR_SIMPLE')end
  return State.transition(s,'RESCUE_PENDING')
 end
 if s.state=='PUBLISH'then
  local ok,err=pcall(require('system.publish').run,c,s)
  if not ok then s.reason=tostring(err);return State.save(s)end
  s.recovery=nil;return State.transition(s,'COMPLETE')
 end
 local route=M.route(s)
 if route then
  if c.live_ai and not manual_run and not c.first_live_manual_done then s.reason='First live day must be manually observed';return State.save(s)end
  return M.invoke(c,s,clock,route,false)
 end
 error('Unknown persistent state '..tostring(s.state))
end
function M.run(c,clock)
 -- Continue deterministic work; stop immediately after at most one inference.
 for _=1,12 do
  local before=State.get();local s=M.advance(c,clock,true)
  if before and M.route(before)then return s end
  if not s.date or State.terminal[s.state]or s.state=='PAUSED_BUDGET' or s.state=='PUBLISH'then return s end
 end
 error('Unexpected deterministic transition cycle')
end
return M

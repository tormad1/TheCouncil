local F=require('system.fs');local J=require('system.json');local Clock=require('system.clock');local M={}
function M.view(c,now)
 local counts={luna_high=0,sol_low=0,sol_medium=0,astra_low=0,astra_medium=0};local five=0;local last=0
 for _,r in ipairs(F.lines('.local/logs/model-usage.jsonl'))do
  if r.mode=='live' and r.outcome~='not_started' and r.timestamp<=now then
   if now-r.timestamp<7*86400 then local key=r.alias..'_'..r.effort;counts[key]=(counts[key]or 0)+1 end
   if now-r.timestamp<5*3600 then five=five+1 end
   if not r.cooldown_exempt then last=math.max(last,r.timestamp)end
  end
 end
 return {rolling_7d=counts,five_hour=five,last=last}
end
function M.authorize(c,s,route,clock,manual)
 assert(c.routing[route],'Unknown stage route');local r=c.routing[route]
 if s.member=='human' then return false,'Human-authored work never invokes a model' end
 if F.exists('.local/PAUSE')then return false,'Global PAUSE'end
 if s.mode~=(c.live_ai and 'live' or 'mock')then return false,'Cannot change mode during a work'end
 if r.model=='astra' then
  if not manual then return false,'Astra requires explicit rescue command'end
  if s.state~='RESCUE_PENDING' and s.state~='PAUSED_BUDGET'then return false,'Rescue only from RESCUE_PENDING'end
 end
 if not c.live_ai then return true,'mock: no plan usage'end
 if not c.live_ready then return false,'Live readiness not confirmed in config'end
 if not F.exists('.local/ACCEPTANCE_PASSED') or not F.exists('.local/SANDBOX_PASSED') or not F.exists('.local/TOOLCHAIN_PASSED') then return false,'Run offline acceptance, OS sandbox probe and real toolchain checks first'end
 local view=M.view(c,clock.timestamp);local key=r.model..'_'..r.effort;local cap=c.budget.rolling_7d[key..'_hard'] or c.budget.rolling_7d[key..'_soft'] or 0
 if manual and r.model=='astra' then cap=math.huge end
 if (view.rolling_7d[key]or 0)>=cap then return false,'Rolling seven-day cap: '..key end
 if view.five_hour>=c.budget.five_hour_hard then return false,'Rolling five-hour cap'end
 if view.last>0 and clock.timestamp-view.last<c.budget.cooldown_minutes*60 then return false,'Cooldown'end
 local optional=route=='ideate_retry' or route=='simple_repair' or route=='complex_repair' or r.model=='astra'
 if optional then
  local future=#Clock.remaining(clock)
  if view.rolling_7d.luna_high+(r.model=='luna' and 1 or 0)+future>c.budget.rolling_7d.luna_high_soft then return false,'Future Luna capacity reserved'end
  if view.rolling_7d.sol_low+(r.model=='sol' and r.effort=='low' and 1 or 0)+future>c.budget.rolling_7d.sol_low_hard then return false,'Future Sol capacity reserved'end
 end
 return true,'Authorized'
end
return M

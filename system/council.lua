package.path='./?.lua;./?/init.lua;'..package.path
local F=require('system.fs');local J=require('system.json');local c=dofile('config.lua')
local State=require('system.state');local Clock=require('system.clock');local Engine=require('system.engine')
local cmd=arg[1]or 'status'
local function current()return assert(State.get(),'No active day. Run today first.')end
local function main()
 local clock=Clock.now(c)
 if cmd=='heartbeat'then return Engine.advance(c,clock,false)
 elseif cmd=='run'then return Engine.run(c,clock)
 elseif cmd=='today'then local s=State.get();if not s or s.date~=clock.date then s=State.prepare(c,clock)end;return s
 elseif cmd=='status'then return {date=clock.date,chair=Clock.members[clock.weekday],current=State.get()or J.null,weekly_words=F.load('words/weeks/'..clock.week..'.json')or J.null,usage=require('system.budget').view(c,clock.timestamp),remaining_artificial_days=Clock.remaining(clock),reserved_capacity={luna_high=#Clock.remaining(clock),sol_low=#Clock.remaining(clock)},automatic_astra='disabled',paused=F.exists('.local/PAUSE')}
 elseif cmd=='pause'then F.write('.local/PAUSE','Manual pause\n');return {state='PAUSED'}
 elseif cmd=='resume'then if F.exists('.local/PAUSE')then F.call{op='remove',path='.local/PAUSE'}end;return {state='RESUMED'}
 elseif cmd=='usage'then return {internal=require('system.budget').view(c,clock.timestamp),note='Local limits are not OpenAI plan limits. Compare with the supported Codex usage display.'}
 elseif cmd=='words'then return require('system.words').get(clock.week)
 elseif cmd=='human-path'then local s=current();assert(s.member=='human','Not a human day');return {path=require('system.workspace').path(s)..'/artifact'}
 elseif cmd=='validate' or cmd=='preview'then
  local path=assert(arg[2],'Usage: validate <id-or-path>')
  if tonumber(path)then for _,r in ipairs(require('system.memory').all())do if r.id==tonumber(path)then path='works/'..r.path;break end end end
  local canonical=F.call{op='resolve',path=path};local works=F.call{op='resolve',path='works'}
  if cmd=='preview'then
   local workspace=F.call{op='resolve',path='.local/workspaces'}
   assert(canonical:sub(1,#workspace+1)==workspace..'/' or canonical:sub(1,#workspace+1)==workspace..'\\','Preview must stay inside a staging workspace')
  end
  if canonical:sub(1,#works)==works then
   local copy='.local/cache/validation';if F.exists(copy)then F.call{op='remove',path=copy}end
   F.call{op='copy',source=path,path=copy};path=copy
  end
  local report=require('system.verify').run(c,path);print(J.encode(report));if not report.ok then error('Validation failed')end;return nil
 elseif cmd=='build-workspace'then return require('system.verify').bob(c,assert(arg[2]))
 elseif cmd=='submit-human'then
  local s=current();assert(s.member=='human' and s.state=='WAITING_FOR_HUMAN','Only a waiting human day can be submitted')
  local source=assert(arg[2],'submit-human <path>');local path=require('system.workspace').path(s)..'/artifact'
  local submitted=assert(F.load(source..'/manifest.json'),'Human manifest required');assert(submitted.member=='human','Human authorship required')
  s.decision=assert(F.load(source..'/curation.json'),'Human curation.json required: exhibit, retire_id, curation_note')
  assert(type(s.decision.exhibit)=='boolean','Human must choose exhibit')
  if F.call{op='resolve',path=source}~=F.call{op='resolve',path=path} then
   -- Validate before replacing the empty staging area.
   local report=require('system.verify').run(c,source,s);assert(report.ok,J.encode(report))
   F.call{op='remove',path=path};F.call{op='copy',source=source,path=path}
  end
  if s.date~=clock.date then s.recovery=true end
  State.transition(s,'VERIFY');return Engine.advance(c,clock,true)
 elseif cmd=='dry-run'then
  local s=State.get()or {id=0,date=clock.date,week=clock.week,weekday=clock.weekday,member=Clock.members[clock.weekday],state='IDEATE',mode=c.live_ai and 'live'or 'mock'}
  if s.member=='human'then return {state='WAITING_FOR_HUMAN',model='none'}end
  local route=Engine.route(s)or 'ideate'
  local result,kind,reason=require('system.codex').invoke(c,s,route,clock,Engine.prompt(c,s,route),true,false)
  return result or {state=kind,reason=reason}
 elseif cmd=='recover'then
  local date=assert(arg[2],'recover YYYY-MM-DD');assert(date<=clock.date,'Cannot recover a future date')
  local old=F.load('.local/runs/'..date..'/state.json')or State.prepare(c,Clock.date(c,date));old.recovery=true;return State.save(old)
 elseif cmd=='rescue'then
  local s=current();assert(s.id==tonumber(arg[2]),'Work id mismatch');assert(s.state=='RESCUE_PENDING','Not awaiting rescue')
  local route=({['astra-low']='astra_low',['astra-medium']='astra_medium'})[arg[3]];assert(route,'rescue <id> astra-low|astra-medium')
  return Engine.invoke(c,s,clock,route,true)
 elseif cmd=='readme'then require('system.publish').readme(c);return {ok=true}
 else error('Unknown command '..cmd)end
end
-- Preview runs inside the builder already protected by the heartbeat lock.
-- Status and the atomic kill switch must remain available during a long build.
local independent={preview=true,status=true,usage=true,pause=true}
local result
if independent[cmd]then result=main()else result=require('system.lock').with(c,main)end
if result and cmd=='status' and result.current then
 local s=result.current~=J.null and result.current or {}
 print('COLLECTIVE STATUS\n\nDate: '..result.date..'\nChair: '..result.chair..'\nWork: '..(s.id and string.format('%04d',s.id)or 'unallocated')..'\nState: '..(s.state or 'IDLE'))
 if result.weekly_words~=J.null then print('\nWeekly words: '..table.concat(result.weekly_words.words,' / '))end
 if s.reason then print('\nCurrent stage: '..s.reason)end
 print('\nRolling 7-day live model activity:')
 for _,key in ipairs{'luna_high','sol_low','sol_medium','astra_low','astra_medium'}do print(string.format('%-15s %d',key,result.usage.rolling_7d[key]))end
 print('\nFive-hour activity: '..result.usage.five_hour..'\nReserved future Luna High / Sol Low: '..result.reserved_capacity.luna_high..' / '..result.reserved_capacity.sol_low..'\nAutomatic Astra: disabled\nGlobal pause: '..tostring(result.paused))
elseif result then print(J.encode(result))end

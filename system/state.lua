local F=require('system.fs');local Clock=require('system.clock');local M={}
M.terminal={COMPLETE=true,FAILED=true,NEEDS_ATTENTION=true,RESCUE_PENDING=true,WAITING_FOR_HUMAN=true}
function M.save(s)
 F.save('.local/runs/'..s.date..'/state.json',s)
 F.save('.local/current.json',s)
 return s
end
function M.get()return F.load('.local/current.json')end
function M.prepare(c,clock)
 -- Sequence is consumed first: a crash before the allocation receipt may skip an ID.
 local path='.local/runs/'..clock.date..'/allocation.json'
 local allocation=F.load(path)
 if not allocation then
  local sequence=assert(tonumber(F.read('memory/sequence.txt') or '0'))
  allocation={id=sequence+1,date=clock.date};F.write('memory/sequence.txt',tostring(allocation.id)..'\n');F.save(path,allocation)
 end
 local seq=tonumber(F.read('memory/sequence.txt') or '0');F.write('memory/sequence.txt',tostring(math.max(seq,allocation.id))..'\n')
 local existing=F.load('.local/runs/'..clock.date..'/state.json')
 if existing then return M.save(existing)end
 return M.save{id=allocation.id,date=clock.date,week=clock.week,weekday=clock.weekday,member=Clock.members[clock.weekday],state='PREPARE',retry=0,repairs=0,mode=c.live_ai and 'live' or 'mock',created=clock.timestamp}
end
function M.transition(s,next_state)s.state=next_state;return M.save(s)end
return M

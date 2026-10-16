local F=require('system.fs');local M={}
function M.now(c,timestamp)return F.call{op='clock',zone=c.timezone,timestamp=timestamp}end
function M.date(c,date)return F.call{op='date',zone=c.timezone,date=date}end
function M.remaining(clock)
 local days={};for i=clock.weekday+1,7 do days[#days+1]=i end;return days
end
M.members={'vellum','moss','morrow','knurl','sable','pica','oriel'}
M.days={'monday','tuesday','wednesday','thursday','friday','saturday','sunday'}
return M

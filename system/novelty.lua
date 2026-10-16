local M={};local Mem=require('system.memory');local J=require('system.json')
M.forms={['defold-2d']=true,['defold-3d']=true,['defold-audio']=true,['defold-textual']=true,['defold-simulation']=true,['defold-game']=true,shader=true,svg=true,text=true,json=true,csv=true,['other-static']=true}
function M.static(form)return form=='svg' or form=='text' or form=='json' or form=='csv' or form=='other-static'end
function M.gate(p)
 local issues=J.array();local warnings=J.array()
 if type(p)~='table' then return false,{'Expected proposal object'},warnings end
 for _,key in ipairs{'title','observation','premise','mechanism','experience','scope','specificity'}do
  if type(p[key])~='string' or #p[key]<1 or #p[key]>1500 then issues[#issues+1]='Invalid '..key end
 end
 if not M.forms[p.form]then issues[#issues+1]='Invalid form'end
 for _,key in ipairs{'concepts','mechanisms','interactions'}do
  if type(p[key])~='table' or #p[key]<1 or #p[key]>8 then issues[#issues+1]='Invalid '..key
  else for _,v in ipairs(p[key])do if type(v)~='string' or #v<1 or #v>80 then issues[#issues+1]='Invalid tag in '..key end end end
 end
 if #issues>0 then return false,issues,warnings end
 if #p.title>150 then issues[#issues+1]='Title exceeds 150 characters'end
 local scope=(p.scope..' '..p.mechanism):lower()
 for _,bad in ipairs{'authentication','cloud service','dashboard','settings page','plugin system','remote api'}do if scope:find(bad,1,true)then issues[#issues+1]='Product scope: '..bad end end
 local all=Mem.all()
 for i=math.max(1,#all-29),#all do local r=all[i]
  local mechanism=Mem.overlap(p.mechanisms,r.mechanisms);local concept=Mem.overlap(p.concepts,r.concepts)
  local interaction=Mem.overlap(p.interactions,r.interactions);local title=Mem.overlap(Mem.keywords(p.title),Mem.keywords(r.title))
  local summary=Mem.overlap(Mem.keywords(p.premise),Mem.keywords(r.summary or ''))
  local score=.5*mechanism+.2*concept+.1*interaction+.1*title+.1*summary
  if mechanism>=.9 and score>=.85 then issues[#issues+1]='Structural collision with work '..r.id..': '..table.concat(r.mechanisms,', ')..'; score '..string.format('%.2f',score)
  elseif mechanism>=.5 or interaction==1 then warnings[#warnings+1]='Tendency shared with work '..r.id end
 end
 return #issues==0,issues,warnings
end
return M

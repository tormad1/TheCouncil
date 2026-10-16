local F=require('system.fs');local J=require('system.json');local M={}
function M.all()return F.lines('memory/catalogue.jsonl')end
local function tokens(s)local t={};for w in s:lower():gmatch('[%w]+')do if #w>2 then t[w]=true end end;return t end
function M.overlap(a,b)
 local left,right={},{};for _,v in ipairs(a or {})do left[v:lower()]=true end;for _,v in ipairs(b or {})do right[v:lower()]=true end
 local both,total=0,0;for v in pairs(left)do total=total+1;if right[v]then both=both+1 end end
 for v in pairs(right)do if not left[v]then total=total+1 end end
 return total==0 and 0 or both/total
end
function M.keywords(s)local out=J.array();for w in pairs(tokens(s))do out[#out+1]=w end;table.sort(out);return out end
function M.packet(c,member,query)
 local all=M.all();local recent,same,related=J.array(),J.array(),J.array();local seen={};local counts={mechanisms={},interactions={}}
 for i=#all,math.max(1,#all-c.context.recent_works+1),-1 do recent[#recent+1]=all[i];seen[all[i].id]=true end
 local count=0
 for i=#all,1,-1 do if all[i].member==member then count=count+1;if count<=c.context.same_member_works and not seen[all[i].id]then same[#same+1]=all[i];seen[all[i].id]=true end end end
 local scored={};local q=M.keywords(query or member)
 for _,r in ipairs(all)do if not seen[r.id]then scored[#scored+1]={r=r,score=M.overlap(q,M.keywords((r.title or '')..' '..(r.summary or '')..' '..table.concat(r.concepts or {},' ')..' '..table.concat(r.mechanisms or {},' ')))}end end
 table.sort(scored,function(a,b)if a.score==b.score then return a.r.id>b.r.id end;return a.score>b.score end)
 for i=1,math.min(c.context.related_works,#scored)do if scored[i].score>0 then related[#related+1]=scored[i].r end end
 for i=math.max(1,#all-c.context.tendency_window+1),#all do for _,key in ipairs{'mechanisms','interactions'}do for _,v in ipairs(all[i][key] or {})do counts[key][v]=(counts[key][v]or 0)+1 end end end
 return {recent=recent,same_member=same,related=related,tendencies=counts}
end
return M

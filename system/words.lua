local F=require('system.fs');local J=require('system.json');local M={}
function M.get(week)
 local p='words/weeks/'..week..'.json';local old=F.load(p);if old then return old end
 local bank={};for word,class,cluster in assert(F.read('words/bank.tsv')):gmatch('([^\t\r\n]+)\t([^\t\r\n]+)\t([^\t\r\n]+)')do
  if word~='word' then bank[#bank+1]={word=word,class=class,cluster=cluster} end
 end
 assert(#bank>=3,'Word bank too small')
 local seed=0;for i=1,#week do seed=(seed*31+week:byte(i))%2147483647 end
 for i=#bank,2,-1 do seed=(seed*48271)%2147483647;local k=seed%i+1;bank[i],bank[k]=bank[k],bank[i] end
 local chosen=J.array();local classes,clusters={},{}
 for _,r in ipairs(bank)do if not classes[r.class] and not clusters[r.cluster] then
  chosen[#chosen+1]=r.word;classes[r.class]=true;clusters[r.cluster]=true;if #chosen==3 then break end
 end end
 assert(#chosen==3,'Need three independent classes and clusters')
 local result={week=week,words=chosen};F.save(p,result);return result
end
return M

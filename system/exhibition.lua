local F=require('system.fs');local J=require('system.json');local M={}
function M.plan(c,id,decision)
 local exhibition=F.load('memory/exhibition.json',{works=J.array(),applied=J.array()});exhibition.applied=exhibition.applied or J.array()
 for _,old in ipairs(exhibition.applied)do if old==id then return exhibition end end
 assert(type(decision)=='table' and type(decision.exhibit)=='boolean','Curation requires a boolean exhibit decision')
 assert(type(decision.curation_note)=='string','Curation requires a note')
 local next_ids=J.array();local retired=false
 for _,old in ipairs(exhibition.works)do
  if decision.retire_id==old and decision.exhibit then retired=true else next_ids[#next_ids+1]=old end
 end
 if decision.exhibit then
  assert(#next_ids<c.exhibition.maximum,'Full exhibition: select an existing retire_id')
  if decision.retire_id~=J.null and decision.retire_id~=nil then assert(retired,'retire_id is not exhibited')end
  next_ids[#next_ids+1]=id
 else assert(decision.retire_id==J.null or decision.retire_id==nil,'Nonexhibited work cannot retire another work')end
 exhibition.works=next_ids;exhibition.applied[#exhibition.applied+1]=id;return exhibition
end
function M.update(c,id,decision)
 local exhibition=M.plan(c,id,decision)
 F.save('memory/exhibition.json',exhibition);return exhibition
end
return M

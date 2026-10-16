local F=require('system.fs');local J=require('system.json');local M={}
M.vocabulary=F.load('system/schemas/creative-vocabulary.json')
M.fields={'member_move','creative_form','source_domain','sensory_mode','dimensionality','temporal_mode','agency','randomness'}
local function contains(values,value)
 for _,v in ipairs(values or {})do if v==value then return true end end;return false
end
function M.validate(p,member,required)
 local errors=J.array();local present=p.metadata_version~=nil
 for _,key in ipairs(M.fields)do if p[key]~=nil then present=true end end
 if not required and not present then return errors end
 if p.metadata_version~=nil and p.metadata_version~=1 then errors[#errors+1]='Unsupported metadata_version'end
 if not contains(M.vocabulary.moves[member],p.member_move)then errors[#errors+1]='Invalid member_move for '..tostring(member)end
 for key,values in pairs(M.vocabulary.fields)do
  if not contains(values,p[key])then errors[#errors+1]='Invalid creative metadata: '..key end
 end
 table.sort(errors);return errors
end
function M.copy(source,target)
 if source.member_move~=nil then target.metadata_version=1 end
 for _,key in ipairs(M.fields)do target[key]=source[key]end
 return target
end
function M.schema(member)
 local schema=F.load('system/schemas/proposal.json')
 schema.properties.member_move.enum=assert(M.vocabulary.moves[member],'Unknown creative member')
 return schema
end
function M.summary(records,member)
 local counts={};local fields={'creative_form','sensory_mode','dimensionality','temporal_mode','agency','source_domain','randomness'}
 for _,key in ipairs(fields)do counts[key]={}end
 local window=math.min(14,#records)
 for i=math.max(1,#records-13),#records do
  for _,key in ipairs(fields)do
   local value=records[i][key]
   if not contains(M.vocabulary.fields[key],value)then value='unknown'end
   counts[key][value]=(counts[key][value]or 0)+1
  end
 end
 local forms,moves=J.array(),J.array()
 for i=#records,1,-1 do local r=records[i]
  if r.member==member then
   if #forms<3 then forms[#forms+1]=r.creative_form or ('unknown (technical form: '..tostring(r.form or 'unknown')..')')end
   if #moves<5 then moves[#moves+1]=r.member_move or 'unknown'end
   if #forms==3 and #moves==5 then break end
  end
 end
 return {window=window,counts=counts,member_forms=forms,member_moves=moves}
end
function M.context(records,member)
 local s=M.summary(records,member);local lines={'RECENT COLLECTIVE SHAPE ('..s.window..' works; unknown means unrecorded)',
 'Descriptive history only. Repetition is allowed. Choose an idea before its metadata; no category is owed a turn.'}
 for _,key in ipairs{'creative_form','sensory_mode','dimensionality','temporal_mode','agency','source_domain','randomness'}do
  lines[#lines+1]='';lines[#lines+1]=key..':'
  local keys={};for k in pairs(s.counts[key])do keys[#keys+1]=k end;table.sort(keys)
  for _,k in ipairs(keys)do lines[#lines+1]=k..'  '..s.counts[key][k]end
 end
 lines[#lines+1]='';lines[#lines+1]=member:upper().."'S RECENT WORK (newest first)"
 lines[#lines+1]='forms: '..(#s.member_forms>0 and table.concat(s.member_forms,', ')or 'none yet')
 lines[#lines+1]='moves: '..(#s.member_moves>0 and table.concat(s.member_moves,', ')or 'none yet')
 return table.concat(lines,'\n')
end
return M

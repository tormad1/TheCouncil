local F=require('system.fs');local J=require('system.json');local Mem=require('system.memory');local Clock=require('system.clock');local M={}
function M.ideate(c,s)
 local persona=assert(F.read('members/'..Clock.days[s.weekday]..'-'..s.member..'.md'))
 local words=require('system.words').get(s.week)
 return table.concat({assert(F.read('system/prompts/ideate.txt')),assert(F.read('culture/PRINCIPLES.md')),persona,
 'Today: '..s.date..' / work '..s.id,'Weekly words (optional): '..table.concat(words.words,' / '),
 J.encode(Mem.packet(c,s.member,persona..' '..table.concat(words.words,' '))),s.rejection or ''},'\n\n')
end
function M.build(c,s,repair)
 local records={};local byid={};for _,r in ipairs(Mem.all())do byid[r.id]=r end
 for _,id in ipairs(F.load('memory/exhibition.json',{works=J.array()}).works)do records[#records+1]=byid[id]or {id=id}end
 return table.concat({assert(F.read(repair and 'system/prompts/repair.txt' or 'system/prompts/build.txt')),
 J.encode(s.proposal),assert(F.read('culture/STYLE.md')),assert(F.read('culture/MEDIUM.md')),
 'Identity: '..J.encode{id=s.id,date=s.date,member=s.member},
  'Current exhibition (maximum '..c.exhibition.maximum..'): '..J.encode(J.array(records)),
 'Write manifest.json and the artefact in artifact/. Keep work id, date, member and proposal unchanged. Set manifest.entry to the relative primary artefact path. tools/preview runs trusted checks. Write only inside this workspace. All shared material needed at runtime must be copied inside artifact/.',
 repair and ('Demonstrated failure: '..J.encode(s.verification)) or '',
 'Return only exhibit, retire_id, curation_note. If exhibition is full, retire one existing id when exhibiting.'},'\n\n')
end
return M

local F=require('system.fs');local J=require('system.json');local Exhibition=require('system.exhibition');local M={}
function M.readme(c)
 local all=require('system.memory').all();local byid={};for _,r in ipairs(all)do byid[r.id]=r end
 local lines={'# '..c.project_name,'','Seven recurring authors sharing one small computational studio. One small complete thing each active day.','',
 'Monday Vellum · Tuesday Moss · Wednesday Morrow · Thursday Knurl · Friday Sable · Saturday Pica · Sunday Oriel',''}
 for _,id in ipairs(F.load('memory/exhibition.json',{works=J.array()}).works)do local r=assert(byid[id],'Exhibition id missing from catalogue')
  lines[#lines+1]=string.format('- [%04d · %s](works/%s/) — %s, %s. %s',r.id,r.title:gsub('([%[%]])','\\%1'),r.path,r.member,r.date,r.summary)
 end
 if #all==0 then lines[#lines+1]='The studio is prepared. No works have been published.'end
 lines[#lines+1]='';lines[#lines+1]='[Archive / catalogue](memory/catalogue.jsonl) · [Studio operation](docs/OPERATIONS.md)'
 F.write('README.md',table.concat(lines,'\n')..'\n')
end
function M.run(c,s)
 assert(s.verification and s.verification.ok,'Cannot publish unverified work')
 local run='.local/runs/'..s.date;local journal=F.load(run..'/publication.json')
 local source=require('system.workspace').path(s)..'/artifact';local manifest=assert(F.load(source..'/manifest.json'))
 assert(J.encode(F.call{op='tree',path=source})==J.encode(s.verification.hashes),'Staging changed after successful verification')
 -- Validate the entire editorial transaction before any public files are written.
 Exhibition.plan(c,s.id,s.decision)
 if not journal then
  -- Check curation before copying or updating public memory.
  local existing=F.load('memory/exhibition.json',{works=J.array()}).works
  if s.decision.exhibit and #existing>=c.exhibition.maximum then local found=false;for _,id in ipairs(existing)do if id==s.decision.retire_id then found=true end end;assert(found,'Choose a work to retire')end
  local path=string.format('%04d-%s',s.id,manifest.slug)
  assert(not F.exists('works/'..path),'Published destination exists without publication journal')
  journal={id=s.id,path=path,hashes=F.call{op='tree',path=source},phase='prepared'};F.save(run..'/publication.json',journal)
 end
 local target='works/'..journal.path
 assert(J.encode(F.call{op='tree',path=source})==J.encode(journal.hashes),'Staging changed after verification/publication started')
 local hashes=F.call{op='publish-copy',source=source,path=target}
 assert(J.encode(hashes)==J.encode(journal.hashes),'Published work integrity mismatch')
 local all=require('system.memory').all();local exists=false
 for _,r in ipairs(all)do if r.id==s.id then assert(r.path==journal.path,'Catalogue collision');exists=true end end
 if not exists then
  local record={path=journal.path};for _,k in ipairs{'id','date','member','title','summary','observation','concepts','mechanisms','interactions','form'}do record[k]=manifest[k]end
  require('system.creative').copy(manifest,record)
  F.append('memory/catalogue.jsonl',record)
 end
 Exhibition.update(c,s.id,s.decision);M.readme(c)
 F.call{op='seal',path=target}
 if c.publication.git_commit then
  -- Require a clean, dedicated repository. Never include unrelated staged changes.
  local staged=F.exec({'git','diff','--cached','--name-only'},'.',20);assert(staged.exit_code==0,'Initialize Git before publication')
  local allowed={['memory/catalogue.jsonl']=true,['memory/exhibition.json']=true,['memory/sequence.txt']=true,['README.md']=true,['words/weeks/'..s.week..'.json']=true}
  for name in staged.stdout:gmatch('[^\r\n]+')do assert(allowed[name] or name:sub(1,#target+1)==target..'/','Unrelated staged change: '..name)end
  local message=string.format('work %04d: %s — %s',s.id,manifest.title,s.member)
  local log=F.exec({'git','log','HEAD','--format=%B','--grep','^Council-Work: '..s.date..'/'..s.id..'$'},'.',20)
  if log.exit_code~=0 or not log.stdout:find('Council-Work: '..s.date..'/'..s.id,1,true)then
   local add=F.exec({'git','add','--',target,'memory/catalogue.jsonl','memory/exhibition.json','memory/sequence.txt','README.md','words/weeks/'..s.week..'.json'},'.',20);assert(add.exit_code==0,add.stderr)
   F.write(run..'/commit-message.txt',message..'\n\nCouncil-Work: '..s.date..'/'..s.id..'\n')
   local commit=F.exec({'git','commit','--file',run..'/commit-message.txt'},'.',30);assert(commit.exit_code==0,commit.stderr)
  end
 end
 journal.phase='complete';F.save(run..'/publication.json',journal)
 return true
end
return M

local F=require('system.fs');local J=require('system.json');local M={}
function M.path(s)return string.format('.local/workspaces/%04d',s.id)end
function M.prepare(c,s)
 local path=M.path(s);F.mkdir(path)
 local artifact=path..'/artifact';F.mkdir(artifact)
 if s.member~='human' and not require('system.novelty').static(s.proposal.form) and not F.exists(artifact..'/game.project')then
  local tmp=path..'/template-copy';F.call{op='copy',source='shared/defold-template',path=tmp}
  for _,f in ipairs(F.call{op='files',path=tmp})do F.write(artifact..'/'..f.path,assert(F.read(tmp..'/'..f.path)))end
  F.call{op='remove',path=tmp}
  for _,f in ipairs(F.call{op='files',path='shared/lua'})do F.write(artifact..'/shared/'..f.path,assert(F.read('shared/lua/'..f.path)))end
  F.save(artifact..'/identity/work.json',{id=s.id,date=s.date,title=s.proposal.title,member=s.member})
 end
 F.write(path..'/AGENTS.md','Write only inside this workspace. Published works are immutable. Do not publish or install dependencies. Do not access network services or external assets. Run tools/preview before finishing.\n')
 if s.proposal then F.save(path..'/proposal.json',s.proposal)end
 F.write(path..'/STYLE.md',assert(F.read('culture/STYLE.md')))
 F.write(path..'/MEDIUM.md',assert(F.read('culture/MEDIUM.md')))
 F.save(path..'/exhibition.json',F.load('memory/exhibition.json',{works=J.array()}))
 local root=F.exec({c.process.python,'-c','import os; print(os.getcwd())'},'.',20).stdout:gsub('%s+$','')
 F.write(path..'/tools/preview.py','import subprocess,sys\nraise SystemExit(subprocess.call([sys.executable,'..string.format('%q',root..'/system/run.py')..',"preview",'..string.format('%q',root..'/'..artifact)..']))\n')
 F.write(path..'/tools/preview.cmd','@echo off\r\n"'..c.process.python..'" "%~dp0preview.py"\r\n')
 F.write(path..'/tools/preview','#!/bin/sh\nexec '..c.process.python..' "$(dirname "$0")/preview.py"\n')
 return path
end
function M.manifest(c,s)
 local p=s.proposal;return {id=s.id,title=p.title,slug=p.title:lower():gsub('[^%w]+','-'):gsub('^%-',''):gsub('%-$',''),date=s.date,member=s.member,form=p.form,summary=p.premise,observation=p.observation,concepts=p.concepts,mechanisms=p.mechanisms,interactions=p.interactions,entry='work.txt',toolchain=F.load('toolchain.lock'),production={ideation_model=c.models.luna,ideation_effort='high',build_model=c.models[require('system.novelty').static(p.form)and 'luna'or 'sol'],build_effort=require('system.novelty').static(p.form)and 'high'or 'low',repairs=J.array()}}
end
return M

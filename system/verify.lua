local F=require('system.fs');local J=require('system.json');local Novelty=require('system.novelty');local M={}
local function issue(report,text,complex)report.errors[#report.errors+1]=text;if complex then report.classification='complex'end end
function M.run(c,path,s)
 local report={ok=false,classification='simple',errors=J.array(),warnings=J.array(),commands=J.array()}
 local ok,manifest=pcall(F.load,path..'/manifest.json')
 if not ok or not manifest then issue(report,'Invalid or missing manifest.json');return report end
 for _,k in ipairs{'id','title','slug','date','member','form','summary','observation','concepts','mechanisms','interactions','toolchain','production','entry'}do if manifest[k]==nil then issue(report,'Missing manifest field '..k)end end
 for _,e in ipairs(require('system.creative').validate(manifest,manifest.member,s and s.proposal and s.proposal.member_move~=nil))do issue(report,e)end
 if s and s.proposal and s.proposal.member_move then
  if manifest.metadata_version~=1 then issue(report,'Missing metadata_version 1')end
  for _,k in ipairs(require('system.creative').fields)do if manifest[k]~=s.proposal[k]then issue(report,'Accepted creative metadata changed: '..k)end end
 end
 if s then for _,k in ipairs{'id','date','member'}do if manifest[k]~=s[k]then issue(report,'Manifest identity mismatch: '..k)end end end
 if s and s.proposal then
  for _,k in ipairs{'title','observation','concepts','mechanisms','interactions','form'}do if J.encode(manifest[k])~=J.encode(s.proposal[k])then issue(report,'Accepted proposal changed: '..k)end end
  if manifest.summary~=s.proposal.premise then issue(report,'Accepted premise changed')end
 end
 if type(manifest.id)~='number' or manifest.id%1~=0 or manifest.id<1 then issue(report,'Invalid id')end
 if type(manifest.slug)~='string' or not manifest.slug:match('^[a-z0-9][a-z0-9%-]*$')or #manifest.slug>100 then issue(report,'Invalid slug')end
 if not Novelty.forms[manifest.form]then issue(report,'Invalid form')end
 if type(manifest.title)~='string' or #manifest.title>150 or manifest.title:find('[\r\n]')then issue(report,'Invalid title')end
 if manifest.words_used~=nil then issue(report,'Do not store word compliance')end
 local entry=manifest.entry
 if type(entry)~='string' or entry:find('..',1,true)or entry:find('[:\\]')or entry:sub(1,1)=='/'then issue(report,'Unsafe entry path');entry=nil end
 local files_ok,files=pcall(F.call,{op='files',path=path})
 if not files_ok then issue(report,tostring(files));return report end
 local tree_ok=pcall(F.call,{op='tree',path=path});if not tree_ok then issue(report,'Symlink or junction in workspace');return report end
 local source_lines=0
 for _,file in ipairs(files)do
  local name=file.path
  if name:find('[<>:"|?*]')or name:match('^%.')or name:find('/%.')then issue(report,'Unsafe filename '..name)end
  if file.size>20*1024*1024 then issue(report,'Oversize file '..name)end
  if not name:match('^build/') and (name:match('%.lua$')or name:match('%.script$')or name:match('%.gui_script$')or name:match('%.project$')or name:match('%.svg$')or name:match('%.txt$')or name:match('%.json$')or name:match('%.csv$')or name:match('%.material$')or name:match('%.fp$')or name:match('%.vp$'))then
   local text=F.read(path..'/'..name)or ''
   if name~='manifest.json' and not name:match('^identity/')then
    if text:find('TODO',1,true)or text:find('FIXME',1,true)or text:lower():find('placeholder',1,true)then issue(report,'Unfinished marker in '..name)end
   end
   local stripped=text:gsub('http://www%.w3%.org/2000/svg',''):gsub('http://www%.w3%.org/1999/xlink','')
   if stripped:find('https?://')or stripped:find('wss?://')or text:find('http.request',1,true)or text:find('socket.connect',1,true)then issue(report,'Network dependency in '..name)end
   if name:match('%.project$') and (text:find('dependencies',1,true)or text:find('native_extension',1,true))then issue(report,'Unapproved dependency in game.project')end
   if name:match('%.lua$')or name:match('%.script$')then local _,n=text:gsub('\n','');source_lines=source_lines+n+1 end
  end
 end
 if source_lines>2500 then report.warnings[#report.warnings+1]='Scope warning: '..source_lines..' source lines'end
 if entry and not F.exists(path..'/'..entry)then issue(report,'Missing entry '..entry)end
 if #report.errors>0 then return report end
 if Novelty.static(manifest.form)then
  local valid,err=pcall(F.call,{op='static',path=path..'/'..entry});if not valid then issue(report,tostring(err))end
  if manifest.form=='svg' and #report.errors==0 then
   local r=M.rasterize(c,path..'/'..entry,path..'/preview.png',960,640);report.commands[#report.commands+1]=r
   if r.exit_code~=0 then issue(report,'SVG preview failed: '..r.stderr)end
  end
 else
  if not F.exists(path..'/game.project')then issue(report,'Missing game.project')else
   local build=M.bob(c,path);report.commands[#report.commands+1]=build
   if build.exit_code~=0 then issue(report,'Bob build failed: '..build.stderr..'\n'..build.stdout)
   else
    local smoke_ok,smoke=pcall(F.call,{op='smoke',path=path..'-bundle',output=path..'/preview.png',log=path..'-reports/runtime.log',check_identity=true})
    if not smoke_ok or not smoke.ok then
     local infrastructure=not smoke_ok or (type(smoke)=='table' and smoke.infrastructure==true)
     issue(report,'Runtime smoke failed: '..(smoke_ok and J.encode(smoke)or tostring(smoke)),not infrastructure)
     if infrastructure then report.classification='infrastructure'end
    end
    if F.exists(path..'/build')then F.call{op='remove',path=path..'/build'}end
   end
  end
 end
 report.ok=#report.errors==0
 if report.ok then report.hashes=F.call{op='tree',path=path}end
 return report
end
function M.bob(c,path)
 local lock=F.load('toolchain.lock')
 if not lock or not F.exists(c.toolchain.bob)then return {exit_code=127,stderr='Pinned Bob not installed. Run system/setup.py.',stdout=''}end
 local absolute=F.call{op='resolve',path=path}
 F.mkdir(path..'-reports')
 local expected=lock.sha256 and lock.sha256['bob.jar']
 if expected and F.call{op='sha256',path=c.toolchain.bob}~=expected then return {exit_code=126,stderr='Bob checksum differs from toolchain.lock',stdout=''}end
 local argv={c.toolchain.java,'-jar',c.toolchain.bob,'--root',absolute,'--platform','wasm-web','--archive','--variant','debug','--bundle-output',absolute..'-bundle','--build-report-json',absolute..'-reports/bob-resources.json'}
 local title=(F.read(path..'/game.project')or ''):match('\ntitle%s*=%s*([^\r\n]+)')
 if title and title:find('[<>:"/\\|?*]')then
  -- Bob uses project.title as a directory name. Keep the authored title in the
  -- source/manifest, but override only the build's platform directory label.
  local manifest=F.load(path..'/manifest.json',{})
  local safe=manifest.slug or title:gsub('[<>:"/\\|?*]',''):gsub('%s+$','')
  assert(safe:match('^[%w%s%-_]+$')and #safe>0,'No safe bundle label')
  local settings=absolute..'-reports/platform.project'
  F.write(settings,'[project]\ntitle = '..safe..'\n')
  argv[#argv+1]='--settings';argv[#argv+1]=settings
 end
 argv[#argv+1]='build';argv[#argv+1]='bundle'
 local result=F.exec(argv,'.',300);F.save(path..'-reports/bob-report.json',result);return result
end
function M.rasterize(c,input,output,w,h)
 return F.exec({c.toolchain.resvg,'--width',tostring(w),'--height',tostring(h),input,output},'.',60)
end
return M

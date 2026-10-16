-- Small strict JSON codec, Lua 5.4. Object keys are sorted for stable output.
local M={};M.null=setmetatable({},{__tostring=function()return 'null' end})
local array_mt={};function M.array(t)return setmetatable(t or {},array_mt)end
local function quote(s)
 return '"'..s:gsub('[%z\1-\31\\"]',function(c)
  local escapes={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
  return escapes[c] or string.format('\\u%04x',c:byte())
 end)..'"'
end
function M.encode(v,seen)
 local t=type(v)
 if v==M.null or v==nil then return 'null' end
 if t=='boolean' then return tostring(v) end
 if t=='number' then assert(v==v and math.abs(v)~=math.huge,'nonfinite JSON');return tostring(v) end
 if t=='string' then return quote(v) end
 assert(t=='table','unsupported JSON type');seen=seen or {};assert(not seen[v],'cycle');seen[v]=true
 local a=getmetatable(v)==array_mt or (#v>0 and v[1]~=nil);local out={}
 if a then for i=1,#v do out[i]=M.encode(v[i],seen) end
 else local keys={};for k in pairs(v)do assert(type(k)=='string','object keys must be strings');keys[#keys+1]=k end
 table.sort(keys);for _,k in ipairs(keys)do out[#out+1]=quote(k)..':'..M.encode(v[k],seen) end end
 seen[v]=nil;return (a and '[' or '{')..table.concat(out,',')..(a and ']' or '}')
end
function M.decode(s)
 local i,n=1,#s
 local function ws()local _,j=s:find('^[ \n\r\t]*',i);i=(j or i-1)+1 end
 local parse
 local function str()
  assert(s:sub(i,i)=='"','expected string');i=i+1;local out={}
  while i<=n do
   local c=s:sub(i,i);i=i+1
   if c=='"' then return table.concat(out) end
   if c=='\\' then
    c=s:sub(i,i);i=i+1
    local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
    if c=='u' then
     local h=s:sub(i,i+3);assert(h:match('^%x%x%x%x$'),'bad unicode');i=i+4;local u=tonumber(h,16)
     if u>=0xD800 and u<=0xDBFF then
      assert(s:sub(i,i+1)=='\\u','unpaired surrogate');i=i+2
      local low=tonumber(s:sub(i,i+3),16);i=i+4;assert(low and low>=0xDC00 and low<=0xDFFF,'bad surrogate');u=0x10000+(u-0xD800)*1024+low-0xDC00
     else assert(u<0xDC00 or u>0xDFFF,'unpaired surrogate') end
     out[#out+1]=utf8.char(u)
    else assert(map[c],'bad escape');out[#out+1]=map[c] end
   else assert(c:byte()>=32,'control character');out[#out+1]=c end
  end
  error('unterminated string')
 end
 parse=function(depth)
  assert(depth<100,'JSON nesting');ws();local c=s:sub(i,i)
  if c=='"' then return str() end
  if c=='{' or c=='[' then
   i=i+1;ws();local obj=c=='{' and {} or M.array();local close=c=='{' and '}' or ']'
   if s:sub(i,i)==close then i=i+1;return obj end
   while true do
    if c=='{' then local key=str();ws();assert(s:sub(i,i)==':','expected colon');i=i+1;assert(obj[key]==nil,'duplicate key');obj[key]=parse(depth+1)
    else obj[#obj+1]=parse(depth+1) end
    ws();local sep=s:sub(i,i);i=i+1;if sep==close then return obj end
    assert(sep==',','expected comma');ws()
   end
  end
  for token,value in pairs({['true']=true,['false']=false,['null']=M.null})do
   if s:sub(i,i+#token-1)==token then i=i+#token;return value end
  end
  local num=s:sub(i):match('^-?%d+%.?%d*[eE][+-]?%d+') or s:sub(i):match('^-?%d+%.%d+') or s:sub(i):match('^-?%d+')
  assert(num and not num:match('^-?0%d'),'invalid JSON value at '..i);i=i+#num;return assert(tonumber(num))
 end
 local value=parse(0);ws();assert(i>n,'trailing JSON data');return value
end
return M

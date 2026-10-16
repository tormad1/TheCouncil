local c=dofile('config.lua');local F=require('system.fs');local J=require('system.json')
assert(arg[1]=='rasterize','rasterize input.svg output.png width height')
local r=require('system.verify').rasterize(c,assert(arg[2]),assert(arg[3]),assert(tonumber(arg[4])),assert(tonumber(arg[5])))
print(J.encode(r));if r.exit_code~=0 then os.exit(r.exit_code)end

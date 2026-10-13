local root=assert(arg[1],"repository root required")
local run=assert(loadfile(root.."/tools/tests/skin_registry_cases.lua"))()
for _,mode in ipairs({"full","token"}) do for fault=0,3 do run(root,mode,fault) end end
run(root,"combat",0)
print("Skin registry: nine independent isolation and combat cases passed")

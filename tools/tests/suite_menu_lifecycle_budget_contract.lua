-- Extend the real skin/motion world; baseline files are read from an overlay.
local root = assert(arg[1]):gsub("\\", "/")
arg[1] = root
local baseline = os.getenv("SUITE_A7_BASELINE")
local originalLoad = loadfile
if baseline then
    loadfile = function(path)
        local relative = path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2)
        local candidate = relative and baseline .. "/" .. relative
        local handle = candidate and io.open(candidate, "rb")
        if handle then handle:close(); return originalLoad(candidate) end
        return originalLoad(path)
    end
end
local function Read(path)
    local file = assert(io.open(root .. "/tools/tests/" .. path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
local source = Read("suite_skin_motion_contract.lua")
source = source:gsub('Load%("Core/PublicAPI.lua"%)', 'Load("Core/SuiteOwnership.lua")\nLoad("Core/PublicAPI.lua")', 1)
source = source:gsub("    return region\nend", [[
    function region:SetTexture(asset) self.asset = asset end
    function region:SetGradient(direction, first, last)
        self.direction, self.first, self.last = direction, first, last
    end
    if nativePass then B.Methods(region, native) end
    return region
end]], 1)
source = source:gsub("            return animation", [[
            if nativePass then B.Methods(animation, native) end
            return animation]], 1)
source = source:gsub("        return group", [[
        if nativePass then B.Methods(group, native) end
        return group]], 1)
source = source:gsub("    return target\nend", [[
    function target:GetChildren() return unpack(self.children or noChildren) end
    if nativePass then B.Methods(target, native) end
    return target
end]], 1)
local preamble = [[
local B = dofile(arg[1] .. "/tools/tests/skin_surface_bench.lua")
local native, nativePass = {}, false
local noChildren = {}
local function SetNativePass(value) nativePass = value end
]]
assert(loadstring(preamble .. source .. "\n" .. Read("menu_lifecycle_cases.lua"), "@menu-lifecycle-world"))()

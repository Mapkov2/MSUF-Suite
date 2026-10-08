-- Reuse the mature fixtures while keeping the additional regression cases separate.
local root = assert(arg[1])
local Support = {}
function Support.Run(harness, checks, cutoff)
    local f = assert(io.open(root .. "/tools/tests/" .. harness, "rb"))
    local code = f:read("*a"); f:close()
    if cutoff then code = code:sub(1, assert(code:find(cutoff, 1, true)) - 1) end
    local selected = os.getenv("BH3_CASE")
    local prefix = "function BH3(id, callback) if " .. string.format("%q", selected or "") .. " == '' or "
        .. string.format("%q", selected or "") .. " == id then callback(); print('BH3 PASS ' .. id) end end\n"
    local realLoad = loadfile
    local baseline, file = os.getenv("BH3_BASELINE"), os.getenv("BH3_FILE")
    if baseline and file then
        loadfile = function(path)
            local clean = path:gsub("\\", "/")
            if clean:sub(-#file) == file then return realLoad(baseline .. "/" .. file) end
            return realLoad(path)
        end
    end
    local ok, why = xpcall(assert(loadstring(prefix .. code .. "\n" .. checks, "@" .. harness .. ":bh3")), debug.traceback)
    loadfile = realLoad
    assert(ok, why)
end
return Support

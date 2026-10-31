-- Bounded cold chrome discovery: preserve native field lookup semantics while
-- avoiding a repeated Lua wrapper and type check for every absent field.
local root = assert(arg[1], "repository root required")
local NS = { IsCombatLocked = function() return false end }
for _, file in ipairs({ "Core/Safety.lua", "Adapters/AdapterKit.lua", "Adapters/GenericWindows.lua" }) do
    local override = os.getenv("SUITE_CHROME_SCAN_SOURCE")
    local path = file == "Adapters/GenericWindows.lua" and override or root .. "/MSUF_Suite_Skin/" .. file
    if file == "Adapters/GenericWindows.lua" then print("Chrome scan source: " .. path) end
    assert(loadfile(path))("MSUF_Suite_Skin", NS)
end
local HasChrome = NS.GenericWindowsShared.HasChrome
local checks = 0
local function Check(ok, message)
    checks = checks + 1
    assert(ok, message)
end

-- Classification retains false, zero and empty strings as present values.
for _, key in ipairs({ "Bg", "PortraitOverlay", "NineSlice", "BackgroundNineSlice" }) do
    for _, value in ipairs({ false, 0, "", {} }) do
        local frame = { [key] = value }
        Check(HasChrome(frame), key .. " lost a present field")
        frame[key] = nil
        Check(not HasChrome(frame), key .. " retained a stale classification")
        frame[key] = value
        Check(HasChrome(frame), key .. " failed to discover a newly restored field")
    end
end
Check(not HasChrome(nil), "nil object must fail closed")
for _, object in ipairs({ false, true, 0, "frame", function() end, newproxy(true) }) do
    Check(not HasChrome(object), "non-table object must fail closed")
end

-- Metatable fields must remain visible and ordered. A later lookup may change
-- what the next key returns; neither rawget nor an identity cache is equivalent.
local reads, present = {}, false
local dynamic = setmetatable({}, { __index = function(_, key)
    reads[#reads + 1] = key
    if key == "Bg" then present = true return nil end
    if key == "BG" and present then return false end
    error("lookup continued after a present field: " .. tostring(key))
end })
Check(HasChrome(dynamic), "dynamic fields must be discovered")
Check(#reads == 2 and reads[1] == "Bg" and reads[2] == "BG", "field order or early exit changed")
local lookupCount = 0
local inherited = setmetatable({}, { __index = function(_, key)
    lookupCount = lookupCount + 1
    if key == "PortraitOverlay" then return 0 end
end })
Check(HasChrome(inherited) and lookupCount > 1, "late inherited chrome was missed")
local firstReads = lookupCount
Check(HasChrome(inherited) and lookupCount == firstReads * 2, "classification must re-read on every pass")
local nativeCalls = 0
local function NativeForbidden() nativeCalls = nativeCalls + 1 return false end
local function NativeType() nativeCalls = nativeCalls + 1 return "Texture" end
local nativeFrame = {}
local function NativeParent() nativeCalls = nativeCalls + 1 return nativeFrame end
-- Dialog-border detection still visits native texture/parent APIs after the
-- public member scan. The optimization must not remove these fresh checks.
nativeFrame.layoutType = "Dialog"
for _, key in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
    nativeFrame[key] = { IsForbidden = NativeForbidden, GetObjectType = NativeType, GetParent = NativeParent }
end
Check(HasChrome(nativeFrame), "dialog border detection changed")
local firstNative = nativeCalls
Check(firstNative > 0, "fixture must exercise native border checks")
Check(HasChrome(nativeFrame) and nativeCalls == firstNative * 2, "native border checks were cached")
nativeFrame.BottomEdge.GetObjectType = function() nativeCalls = nativeCalls + 1 return "FontString" end
Check(not HasChrome(nativeFrame), "changed native region type must invalidate chrome")

-- Model the measured first-open scan's many nodes with absent/late chrome.
-- This is a deterministic work budget, not a WoW time/FPS or full-tree claim.
local empty, late = {}, { PortraitOverlay = false }
-- These methods exist on the hosts, so an accidental native query during a
-- field-only scan is counted. This budget covers these fixture methods only.
for _, frame in ipairs({ empty, late }) do
    frame.IsForbidden, frame.IsProtected = NativeForbidden, NativeForbidden
    frame.GetObjectType, frame.GetParent = NativeType, NativeParent
end
local nativeBeforeScan = nativeCalls
local function Scan()
    for _ = 1, 100 do
        assert(not HasChrome(empty))
        assert(HasChrome(late))
    end
end
Scan()
local vm = 0
local function Instruction() vm = vm + 1 end
debug.sethook(Instruction, "", 1)
Scan()
debug.sethook()
local typeCalls, fieldCalls = 0, 0
local field = NS.Safety.Field
local function Called()
    local fn = debug.getinfo(2, "f").func
    if fn == type then typeCalls = typeCalls + 1 end
    if fn == field then fieldCalls = fieldCalls + 1 end
end
debug.sethook(Called, "c")
Scan()
debug.sethook()
local function Allocation()
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    Scan()
    local result = collectgarbage("count") - before
    collectgarbage("restart")
    return result
end
local allocation = math.min(Allocation(), Allocation())
print(string.format("chrome scan: vm=%d typeCalls=%d fieldCalls=%d nativeCalls=%d allocationKiB=%.6f",
    vm, typeCalls, fieldCalls, nativeCalls - nativeBeforeScan, allocation))
Check(vm <= 60000, "chrome scan exceeds its VM work budget")
Check(typeCalls <= 900, "chrome scan repeats table type checks per key")
Check(fieldCalls <= 200, "chrome scan repeats the field wrapper per key")
Check(nativeCalls == nativeBeforeScan, "plain chrome scan introduced native work")
Check(allocation <= 0.01, "chrome scan allocated storage per pass")
print("Suite skin chrome scan: " .. checks .. " checks passed")

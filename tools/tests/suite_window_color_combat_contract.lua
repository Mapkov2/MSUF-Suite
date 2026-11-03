-- Exact target refreshes must survive native combat resets without global work.
local root = assert(arg[1], "Suite root required")
local combat, checks, writes = false, 0, 0
local secret = {}
issecretvalue = function(value) return value == secret end
InCombatLockdown = function() return false end -- PLAYER_REGEN_DISABLED edge
securecallfunction = function(callback, ...) return callback(...) end
local NS = { DB = { enabled = true }, IsCombatLocked = function() return combat end,
    Theme = { GetColor = function() return .2, .4, .7, 1 end },
    Registry = { AddListener = function() end }, BlizzardFontNames = {},
    WindowActionSkin = { HasOwnedStates = function() return false end,
        IsApplied = function() return false end, Track = function() end },
    CombatGate = { RunOrDefer = function() error("target refresh queued global work") end } }
local function Load(name) return assert(loadfile(root .. "/MSUF_Suite_Skin/" .. name .. ".lua"))("MSUF_Suite_Skin", NS) end
NS.Safety = Load("Core/Safety")
local yellow, checksArt = Load("Core/BlizzardYellow"), Load("Core/Checkmarks")
local function Check(value, message) assert(value, message); checks = checks + 1 end
local function Target(kind)
    local object = { color = {1, .82, 0, 1}, vertex = {1, 1, 1, 1}, kind = kind }
    function object:IsProtected() return self.protected, self.explicit end
    function object:IsForbidden() return self.forbidden == true end
    function object:GetObjectType() return self.kind end
    function object:GetTextColor() if self.secretColor then return secret end; return unpack(self.color) end
    function object:SetTextColor(r,g,b,a) writes = writes + 1; self.color[1],self.color[2],self.color[3],self.color[4]=r,g,b,a end
    function object:GetVertexColor() if self.secretColor then return secret end; return unpack(self.vertex) end
    function object:SetVertexColor(r,g,b,a) writes = writes + 1; self.vertex[1],self.vertex[2],self.vertex[3],self.vertex[4]=r,g,b,a end
    function object:IsDesaturated() return self.desaturated end
    function object:SetDesaturated(value) self.desaturated = value end
    function object:GetAtlas() return "common-dropdown-icon-checkmark-yellow" end
    return object
end
local label, mark = Target("FontString"), Target("Texture")
local frame = Target("Frame")
function frame:GetRegions() return label end
function frame:GetNumRegions() return 1 end
function frame:GetNormalTexture() return mark end
local frames = {frame}
yellow.TrackFrame(frame); checksArt.TrackTexture(mark, "test", "checkmark")
combat = true
local function NativeReset()
    label.color[1],label.color[2],label.color[3]=1,.82,0
    mark.vertex[1],mark.vertex[2],mark.vertex[3]=1,1,1
    mark.desaturated = false
end
NativeReset()
Check(yellow.TrackFrame(frame) == 1 and label.color[1] == .2, "combat native text reset lost configured yellow color")
Check(checksArt.TrackTexture(mark, "test", "checkmark") and mark.vertex[1] == .2 and mark.desaturated,
    "combat native texture reset lost configured checkmark color")
NativeReset(); yellow.TrackFrames(frames,1)
Check(label.color[1] == .2, "cached row traversal skipped combat text")
NativeReset(); checksArt.TrackButton(frame,"test")
Check(mark.vertex[1] == .2, "combat button traversal skipped native art")
for _, object in ipairs({label, mark}) do
    object.protected = true
    NativeReset(); local before = writes
    if object == label then yellow.TrackFrame(frame) else checksArt.TrackTexture(mark,"test","checkmark") end
    Check(writes == before, "implicit protected target written at combat event edge")
    object.explicit = true
    if object == label then yellow.TrackFrame(frame) else checksArt.TrackTexture(mark,"test","checkmark") end
    Check(writes == before, "explicit protected target written")
    object.protected, object.explicit, object.forbidden = nil,nil,true
    if object == label then yellow.TrackFrame(frame) else checksArt.TrackTexture(mark,"test","checkmark") end
    Check(writes == before, "forbidden target written")
    object.forbidden, object.secretColor = nil,true
    if object == label then yellow.TrackFrame(frame) else checksArt.TrackTexture(mark,"test","checkmark") end
    Check(writes == before, "secret color target written")
    object.secretColor = nil
end
NativeReset(); yellow.TrackFrames(frames,1); checksArt.TrackTexture(mark,"test","checkmark")
local function Warm()
    NativeReset(); yellow.TrackFrames(frames,1); checksArt.TrackTexture(mark,"test","checkmark")
end
Warm()
collectgarbage("collect"); collectgarbage("stop")
local before = collectgarbage("count")
for _=1,1000 do Warm() end
local growth=collectgarbage("count")-before
collectgarbage("restart")
Check(growth < 2, "warm target recolor allocated: " .. growth .. " KiB")
NS.DB.enabled=false
NativeReset(); before=writes
yellow.TrackFrames(frames,1); checksArt.TrackFrame(frame,"test")
Check(writes==before,"disabled skin still recolored native targets")
print("Combat target coloring: " .. checks .. " checks; " .. growth .. " KiB/1000 warm refreshes")

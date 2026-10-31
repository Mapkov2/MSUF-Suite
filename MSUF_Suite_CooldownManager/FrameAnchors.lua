local _, P = ...
local NS, S = P.NS, P.Suite
local C = P.CDM
-- The frames a bar follows without anchoring to them: MSUF's player and
-- target frames, Blizzard's Essential bar and, for "Other frame", any global
-- frame by name. Such a frame may be protected, and a bar in its anchor
-- family could not reflow in combat, so the bar reads the frame's rectangle
-- and sits against UIParent at that spot instead. Two probes stretched from
-- UIParent's corner to the frame's corners report every move or resize
-- through OnSizeChanged: no polling, no hooks. Between two reports the
-- rectangle is read once and kept, so relayouts of bars on these frames make
-- no geometry reads. Layout.lua asks; it is the only caller.
local Public = S.Public
local Frames = { gen = 0 }
C.Frames = Frames
local WEAK = { __mode = "k" }
local watched, rects = setmetatable({}, WEAK), setmetatable({}, WEAK)
-- Something waits for the combat end: a frame that appeared (it is probed and
-- judged then) or an add-on loaded in the fight.
local pending = false
local follow

-- Layout's walk over the bars that sit on frames (bars on any frame wake).
function Frames.OnMoved(callback) follow = callback end
-- Bumped whenever a watched frame may have moved or the pixel scale changed:
-- cached rectangles older than this generation are read again. Also the
-- OnSizeChanged script of the probes.
function Frames.Moved()
    Frames.gen = Frames.gen + 1
    if follow then follow() end
    if C.state.assistIcon and C.state.assistIconAnchor == 3 then C.Effects.RecommendationPlace() end
end
local function Probe(frame, relPoint)
    local probe = S.CreateFrame("Frame", nil, UIParent)
    probe:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    probe:SetPoint("TOPRIGHT", frame, relPoint, 0, 0)
    probe:SetScript("OnSizeChanged", Frames.Moved)
    return probe
end
local function Num(v) return Public(v) and type(v) == "number" and v == v end

-- Rectangle of a frame in UIParent units: left, bottom, right, top; nil when
-- it is missing or unreadable. A watched frame's readable rectangle is kept
-- until its probes (or a scale change) bump the generation; a frame without
-- probes yet (it appeared in combat) is read on every call.
function Frames.Rect(frame)
    local kept = rects[frame]
    if kept and kept.gen == Frames.gen then return kept[1], kept[2], kept[3], kept[4] end
    if type(frame) ~= "table" or NS.Safety.IsForbidden(frame) then return nil end
    if not watched[frame] then
        if NS.IsCombatLocked() then
            pending = true
        else
            watched[frame] = true
            Probe(frame, "BOTTOMLEFT")
            Probe(frame, "TOPRIGHT")
        end
    end
    local left, bottom, width, height = frame:GetRect()
    local scale, ui = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (Num(left) and Num(bottom) and Num(width) and Num(height) and Num(scale) and Num(ui)) or ui <= 0 then
        return nil
    end
    local k = scale / ui
    local right, top = (left + width) * k, (bottom + height) * k
    left, bottom = left * k, bottom * k
    if watched[frame] then
        if not kept then
            kept = {}
            rects[frame] = kept
        end
        kept.gen = Frames.gen
        kept[1], kept[2], kept[3], kept[4] = left, bottom, right, top
    end
    return left, bottom, right, top
end

------------------------------------------------------------------ other frames
-- Whether `frame` is one of our bars, a child of one or anchored (a few links
-- deep) to such a frame: following it would make the bar chase itself.
local function IsBar(frame)
    for _, bar in pairs(C.bars) do
        if bar.frame == frame then return true end
    end
    return false
end
local function Hangs(frame, depth)
    local cursor = frame
    for _ = 1, 16 do
        if IsBar(cursor) then return true end
        cursor = cursor:GetParent()
        if not Public(cursor) or type(cursor) ~= "table" then break end
    end
    if depth <= 0 then return false end
    local count = frame:GetNumPoints()
    if not (Public(count) and type(count) == "number") then return false end
    for i = 1, count do
        local _, relative = frame:GetPoint(i)
        if Public(relative) and type(relative) == "table" and Hangs(relative, depth - 1) then return true end
    end
    return false
end
local function Judge(frame)
    if type(frame) ~= "table" or type(frame.GetRect) ~= "function" or NS.Safety.IsForbidden(frame) then return false end
    return not Hangs(frame, 3)
end

-- The global frame a "Frame name" names, or nil: a frame object that is not
-- one of our bars, a child of one or hanging from one. Judged once per frame
-- and generation, and only out of combat: a frame met in a fight is judged at
-- its end (a protected frame's anchors are never read in a fight). slot: the
-- bar that waits while the frame does not exist (Wait, below).
local named = {}
function Frames.Named(name, slot)
    if type(name) ~= "string" then return nil end
    local frame = rawget(_G, name)
    if slot then Frames.Wait(slot, frame == nil and name ~= "" and name or nil) end
    if frame == nil then return nil end
    local entry = named[name]
    if entry and entry.frame == frame and (entry.gen == Frames.gen or NS.IsCombatLocked()) then
        return entry.ok and frame or nil
    end
    if NS.IsCombatLocked() then
        pending = true
        return nil
    end
    if not entry then
        entry = {}
        named[name] = entry
    end
    entry.frame, entry.gen, entry.ok = frame, Frames.gen, Judge(frame)
    return entry.ok and frame or nil
end

-- A bar on a frame that does not exist yet (its add-on has not loaded) sits
-- where its own x/y put it and waits: ADDON_LOADED (and a loading screen's end,
-- for frames made later) is listened to only while some bar waits, and a load
-- outside combat tries again.
local missing, listener = {}, nil
local function Listen(on)
    if on then
        listener:RegisterEvent("ADDON_LOADED")
        listener:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        listener:UnregisterEvent("ADDON_LOADED")
        listener:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end
local function OnAddon()
    if NS.IsCombatLocked() then
        pending = true
        return
    end
    local found = false
    for slot, name in pairs(missing) do
        if rawget(_G, name) ~= nil then
            missing[slot], found = nil, true
        end
    end
    if not found then return end
    if next(missing) == nil then Listen(false) end
    Frames.Moved()
end
function Frames.Wait(slot, name)
    if missing[slot] == name then return end
    local was = next(missing) ~= nil
    missing[slot] = name
    local now = next(missing) ~= nil
    if now == was then return end
    if not listener then
        listener = S.CreateFrame("Frame")
        listener:SetScript("OnEvent", OnAddon)
    end
    Listen(now)
end
-- The module goes: nothing waits any more.
function Frames.Clear()
    if next(missing) == nil then return end
    for slot in pairs(missing) do missing[slot] = nil end
    Listen(false)
end

-- Combat end: watch the frames that appeared during combat.
function Frames.CombatEnded()
    if not pending then return end
    pending = false
    Frames.Moved()
end

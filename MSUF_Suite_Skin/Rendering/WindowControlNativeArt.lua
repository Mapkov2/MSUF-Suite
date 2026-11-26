local _, NS = ...
local Safety = NS.Safety
local Art = {}
NS.WindowControlNativeArt = Art

-- A native button or texture can acquire a secret alpha even after its public
-- alpha was captured. Keep its native value until its owner supplies a public one.
local nativeAlphas = setmetatable({}, { __mode = "k" })
local fadeOwners = setmetatable({}, { __mode = "k" }) -- false after release while the hook remains
function Art.IsFaded(region) return nativeAlphas[region] ~= nil end

local function FadePublicAlpha(region)
    local alpha = Safety.Read(region, "GetAlpha")
    if alpha == nil then nativeAlphas[region] = nil return end
    nativeAlphas[region] = nativeAlphas[region] or alpha
    if alpha ~= 0 then region:SetAlpha(0) end
end
local function KeepFaded(region, alpha)
    if not fadeOwners[region] then return end
    if not Safety.Public(alpha) then nativeAlphas[region] = nil
    elseif alpha ~= 0 or nativeAlphas[region] == nil then FadePublicAlpha(region) end
end

local SIZE_BUTTONS = { "MaximizeButton", "MinimizeButton" }
local released = setmetatable({}, { __mode = "k" })
local yieldOwners = setmetatable({}, { __mode = "k" })

local function SetYield(parts, button, claim)
    if claim then
        if yieldOwners[button] ~= parts then
            NS.WindowActionSkin.Yield(button, true)
            yieldOwners[button] = parts
        end
    elseif yieldOwners[button] == parts then
        NS.WindowActionSkin.Yield(button, false)
        yieldOwners[button] = nil
    end
end

local function ReleasePart(parts, region)
    if fadeOwners[region] ~= parts then return end
    local alpha = nativeAlphas[region]
    fadeOwners[region], nativeAlphas[region] = false, nil
    if alpha ~= nil and Safety.Read(region, "GetAlpha") == 0 then region:SetAlpha(alpha) end
end

local function FadePart(parts, region)
    if not Safety.Public(region) or region == nil or Safety.IsForbidden(region) then
        parts.complete = false
        return
    end
    if type(region) == "table" and Safety.ReadableMethod(region, "SetAlpha") then
        if fadeOwners[region] == nil then hooksecurefunc(region, "SetAlpha", KeepFaded) end
        fadeOwners[region] = parts
        parts.regions[region] = parts.pass
        FadePublicAlpha(region)
    end
    return true
end

local function FadeRegions(parts, ...)
    for index = 1, select("#", ...) do
        FadePart(parts, (select(index, ...)))
    end
end

local function FadeButton(parts, button)
    if not FadePart(parts, button) then return end
    if Safety.HasMethod(button, "GetRegions") then
        parts.sources[button] = true
        FadeRegions(parts, button:GetRegions())
    elseif parts.sources[button] then
        parts.complete = false
    end
end

-- Read current native art every time: templates and pooled buttons can replace it.
-- The per-root ownership set also releases any removed region before it is reused.
local function FadeNative(state, target)
    if not Safety.Public(target) or type(target) ~= "table" or Safety.IsForbidden(target) then return false end
    local canYield = Safety.CanDecorate(target, not NS.IsCombatLocked())
    state.nativeRoots = state.nativeRoots or setmetatable({}, { __mode = "k" })
    local parts = state.nativeRoots[target]
    if not parts then
        parts = released[target] or {
            regions = setmetatable({}, { __mode = "k" }),
            sources = setmetatable({}, { __mode = "k" }),
            pass = 0,
        }
        released[target] = nil
        state.nativeRoots[target] = parts
    end
    parts.pass, parts.complete = parts.pass + 1, true
    if canYield then SetYield(parts, target, true) end
    FadeButton(parts, target)
    for _, key in ipairs(SIZE_BUTTONS) do
        local child = Safety.Field(target, key)
        if not Safety.Public(child) or Safety.IsForbidden(child) then
            parts.complete = false
        else
            if canYield then
                local previous = parts[key]
                if previous and previous ~= child then SetYield(parts, previous, false) end
                if child then SetYield(parts, child, true) end
                parts[key] = child
            end
            if child then FadeButton(parts, child) end
        end
    end
    -- A forbidden child or secret region slot hides its identity. Retain its
    -- previous snapshot until a complete pass can prove it left the tree.
    if not parts.complete then return true end
    for region, pass in pairs(parts.regions) do
        if pass ~= parts.pass then
            parts.regions[region] = nil
            ReleasePart(parts, region)
        end
    end
    return true
end

local function RestoreNative(state, target)
    local parts = state.nativeRoots and state.nativeRoots[target]
    if not parts or not Safety.CanDecorate(target, not NS.IsCombatLocked()) then return end
    state.nativeRoots[target] = nil
    if state.sockets then state.sockets[target] = nil end
    state.restores = (state.restores or 0) + 1
    SetYield(parts, target, false)
    for _, key in ipairs(SIZE_BUTTONS) do
        if parts[key] then SetYield(parts, parts[key], false) end
        parts[key] = nil
    end
    for region in pairs(parts.regions) do
        ReleasePart(parts, region)
        parts.regions[region] = nil
    end
    released[target] = parts
    return true
end

local function FadeSocket(state, owner, right, top)
    if not Safety.Public(owner) or not owner or Safety.IsForbidden(owner) then
        state.socketsComplete = false
        return
    end
    local nine = Safety.Field(owner, "NineSlice")
    if not Safety.Public(nine) or (nine and Safety.IsForbidden(nine)) then
        state.socketsComplete = false
        return
    end
    if not nine then return end
    local corner = Safety.Field(nine, "TopRightCorner")
    if not Safety.Public(corner) or (corner and Safety.IsForbidden(corner)) then
        state.socketsComplete = false
        return
    end
    if not corner then return end
    local shown = Safety.Read(owner, "IsShown")
    if shown == nil then
        state.socketsComplete = false
        return
    end
    if not shown then return end
    if owner ~= state.frame then
        local x, y = Safety.Read(owner, "GetRight"), Safety.Read(owner, "GetTop")
        if not x or not y then
            state.socketsComplete = false
            return
        end
        if math.abs(x - right) >= 6 or math.abs(y - top) >= 6 then return end
    end
    if FadeNative(state, corner) then
        state.sockets = state.sockets or {}
        state.sockets[corner] = state.socketPass
    end
end

local function FadeChildSockets(state, right, top, ...)
    for index = 1, select("#", ...) do FadeSocket(state, (select(index, ...)), right, top) end
end

local function FadeSockets(state)
    local frame = state.frame
    local right, top = Safety.Read(frame, "GetRight"), Safety.Read(frame, "GetTop")
    if not right or not top then return end
    state.socketPass, state.socketsComplete = (state.socketPass or 0) + 1, true
    FadeSocket(state, frame, right, top)
    if Safety.HasMethod(frame, "GetChildren") then
        FadeChildSockets(state, right, top, frame:GetChildren())
    elseif state.sockets then
        state.socketsComplete = false
    end
    if state.sockets and state.socketsComplete then
        for corner, pass in pairs(state.sockets) do
            if pass ~= state.socketPass then RestoreNative(state, corner) end
        end
    end
end

Art.Fade, Art.Restore, Art.FadeSockets = FadeNative, RestoreNative, FadeSockets

-- Native opening layout can reveal artwork without using the Lua setter.
-- Forever's Group Finder did so in 15 frames of trace 44. A report below
-- records that the same behavior was actually observed for another root.
local checkOpeningAlpha = {
    GuildFrame = true, CommunitiesFrame = true, AddonList = true, SettingsPanel = true,
    LFGParentFrame = true, WorldMapFrame = true,
}
function Art.NeedsOpeningWatch(state)
    return checkOpeningAlpha[state.name] or state.reported
end

function Art.Shown(state)
    if (Safety.Read(state.close, "GetAlpha") or 0) ~= 0 then return true end
    if state.nativeRoots then
        for target in pairs(state.nativeRoots) do
            if target ~= state.close and (Safety.Read(target, "GetAlpha") or 0) ~= 0 then return true end
        end
    end
    return false
end

-- Field report: one chat line per window when Blizzard's X or size toggle
-- shows under our cells, before the caption fades it again.
function Art.Report(state, moment)
    local close, cell = state.close, state.closeCell
    if state.reported or not cell or not cell:IsShown() then return end
    local native = Safety.Read(close, "GetAlpha") == 0 and state.sizeToggle or close
    local alpha = Safety.Read(native, "GetAlpha")
    if not alpha or alpha == 0 or not Safety.Read(native, "IsShown") then return end
    state.reported = true
    NS.Print(("caption check: %s %s, %s alpha %.2f, faded %s, owned %s, path %s, restores %d"):format(state.name,
        tostring(moment or "next frame"), native == close and "X" or "toggle", alpha, tostring(Art.IsFaded(native)),
        tostring(state.nativeRoots and state.nativeRoots[native] ~= nil), tostring(state.captionPath), state.restores or 0))
end

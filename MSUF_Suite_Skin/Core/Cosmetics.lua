local _, NS = ...

-- Reversible alpha suppression of native decoration. Each region remembers
-- its original value and is restored only while it still shows our value.
local Cosmetics = {
    states = setmetatable({}, { __mode = "k" }),
    owners = {},
}
NS.Cosmetics = Cosmetics

local nineSlicePieces = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center",
}

local function AccessibleAlpha(region)
    return tonumber(NS.Safety.Read(region, "GetAlpha"))
end

local function Track(region, state, owner)
    Cosmetics.states[region] = state
    if owner == nil then return end
    local set = Cosmetics.owners[owner]
    if not set then
        set = setmetatable({}, { __mode = "k" })
        Cosmetics.owners[owner] = set
    end
    set[region] = true
end

-- Ordinary fades never install hooks. Permanent method hooks on explicitly
-- opted-in textures dispatch only while that exact alpha ledger is active.
local decorationHooks = setmetatable({}, { __mode = "k" })
local function WriteAlpha(region, state, value)
    if state.decoration then
        state.writingAlpha = true
        NS.Safety.Dispatch(region.SetAlpha, region, value)
        state.writingAlpha = nil
    else
        region:SetAlpha(value)
    end
end

function Cosmetics.Fade(region, owner)
    if not NS.Safety.Public(region) or not NS.Safety.CanDecorate(region, true)
        or type(region.SetAlpha) ~= "function" then
        return false
    end
    local state = Cosmetics.states[region]
    if not state then
        local alpha = AccessibleAlpha(region)
        if alpha == nil then
            return false
        end
        state = { kind = "alpha", alpha = alpha, owner = owner }
    elseif state.kind ~= "alpha" or state.owner ~= owner then
        return false
    end
    if state.decoration then state.decoration.keepFade = true end
    Track(region, state, owner)
    WriteAlpha(region, state, 0)
    return true
end

-- Call only after a known native alpha writer. A native zero is meaningful
-- too; a general repaint cannot distinguish it from our own suppression.
function Cosmetics.CaptureNativeAlpha(region, owner)
    if type(region) ~= "table" or NS.Safety.IsForbidden(region) then return false end
    local state = Cosmetics.states[region]
    if not state or state.kind ~= "alpha" or state.owner ~= owner or state.decoration then return false end
    local alpha = AccessibleAlpha(region)
    if alpha == nil then return false end
    state.alpha = alpha
    return true
end

-- Blizzard can repaint these fixed interaction-window textures during a
-- fight. Check the current parent chain, including protection inherited
-- from a frame when the texture itself has no IsProtected method.
local function CanPaintInteractionArt(region, decoration)
    if decoration.otherWindow then return false end
    local target = region
    for _ = 1, 12 do
        if target == UIParent then
            decoration.otherWindow = true
            return false
        end
        if not NS.Safety.CanDecorate(target) then return false end
        if target == QuestFrame or target == GossipFrame or target == MailFrame or target == OpenMailFrame then return true end
        target = NS.Safety.Read(target, "GetParent")
    end
    return false
end

local function Conceal(region, state, settled)
    local decoration = state.decoration
    if not decoration or Cosmetics.states[region] ~= state then return end
    if NS.IsCombatLocked() then
        if not decoration.resume then
            decoration.resume = function()
                decoration.scheduled = nil
                if state.decoration == decoration then Conceal(region, state, true) end
            end
        end
        if not CanPaintInteractionArt(region, decoration) then
            NS.CombatGate.RunOrDefer(decoration.resume, decoration.resume)
            return
        end
        -- Leave the native Show/SetAlpha stack first. In particular, the
        -- mailbox still has its protected reading emote to run.
        if not settled then
            if not decoration.scheduled then
                decoration.scheduled = true
                C_Timer.After(0, decoration.resume)
            end
            return
        end
    end
    if not NS.Safety.CanDecorate(region, true) then return end
    local alpha = state.kind == "alpha" and AccessibleAlpha(region)
    if alpha and alpha > 0 then
        state.alpha = alpha
        WriteAlpha(region, state, 0)
    end
    if NS.Safety.Read(region, "IsShown") == true then
        decoration.hiding = true
        NS.Safety.Dispatch(region.Hide, region)
        decoration.hiding = nil
    end
end

local function NativeAlpha(region, value)
    local state = Cosmetics.states[region]
    if not state or state.kind ~= "alpha" or not state.decoration or state.writingAlpha or not NS.Safety.Public(value) then return end
    local alpha = AccessibleAlpha(region)
    if alpha == nil then return end
    state.alpha = alpha
    if alpha > 0 then Conceal(region, state) end
end

-- In the client vertex color and region alpha share the texture's opacity.
-- This observes a native retint, leaving its RGB channels entirely intact.
local function NativeTint(region, _, _, _, alpha)
    NativeAlpha(region, alpha)
end

local function NativeShown(region, shown)
    local state = Cosmetics.states[region]
    local decoration = state and state.decoration
    if not decoration or decoration.hiding or not NS.Safety.Public(shown) then return end
    decoration.shown = shown == true
    if decoration.shown then Conceal(region, state) end
end
local function OnShow(region) NativeShown(region, true) end
local function OnHide(region) NativeShown(region, false) end

-- Only for fixed native decorative textures. A caller may borrow the
-- existing owner's fade under its own claim and relinquish just that claim.
local function SuppressDecoration(region, owner, claim, kind)
    if not owner or not NS.Safety.Public(region) or not NS.Safety.CanDecorate(region, true) then return false end
    local state = Cosmetics.states[region]
    if state and (state.kind ~= kind or state.owner ~= owner) then return false end
    if not state or not state.decoration then
        if NS.Safety.Read(region, "GetObjectType") ~= "Texture" then return false end
        local shown = NS.Safety.Read(region, "IsShown")
        if type(shown) ~= "boolean" then return false end
        local alpha
        if kind == "alpha" then
            alpha = AccessibleAlpha(region)
            if alpha == nil then return false end
        end
        local hadFade = state ~= nil
        state = state or { kind = kind, alpha = alpha, owner = owner }
        state.decoration = { shown = shown, claims = {}, keepFade = hadFade }
        Track(region, state, owner)
        if not decorationHooks[region] then
            hooksecurefunc(region, "Show", OnShow)
            hooksecurefunc(region, "Hide", OnHide)
            hooksecurefunc(region, "SetShown", NativeShown)
            decorationHooks[region] = "visibility"
        end
        if kind == "alpha" and decorationHooks[region] ~= "alpha" then
            hooksecurefunc(region, "SetAlpha", NativeAlpha)
            hooksecurefunc(region, "SetVertexColor", NativeTint)
            decorationHooks[region] = "alpha"
        end
    end
    state.decoration.claims[claim or owner] = true
    state.decoration.otherWindow = nil
    Conceal(region, state)
    return true
end

function Cosmetics.FadeDecoration(region, owner, claim)
    return SuppressDecoration(region, owner, claim, "alpha")
end

-- ControlSkin already owns the alpha of these button textures. Only observe
-- visibility here so either owner can release first and retain its own state.
function Cosmetics.HideDecoration(region, owner)
    return SuppressDecoration(region, owner, owner, "visibility")
end

local function ReleaseVisibility(region, state)
    local decoration = state.decoration
    state.decoration = nil
    if decoration.resume then NS.CombatGate.Cancel(decoration.resume) end
    if decoration.shown and NS.Safety.CanDecorate(region, true) and NS.Safety.Read(region, "IsShown") == false then
        NS.Safety.Dispatch(region.Show, region)
    end
end

function Cosmetics.ReleaseDecoration(region, owner, claim)
    local state = Cosmetics.states[region]
    local decoration = state and state.decoration
    if not decoration or state.owner ~= owner then return end
    decoration.claims[claim or owner] = nil
    if next(decoration.claims) then return end
    if decoration.keepFade then ReleaseVisibility(region, state)
    else Cosmetics.Restore(region, owner) end
end

function Cosmetics.SuppressVertexAlpha(region, owner)
    if type(region) ~= "table" or type(region.SetVertexColor) ~= "function"
        or NS.Safety.IsForbidden(region) then
        return false
    end
    local state = Cosmetics.states[region]
    if not state then
        local r, g, b, a = NS.Safety.ReadColor(region, "GetVertexColor")
        if not r then return false end
        state = { kind = "vertex", vertex = { r, g, b, a }, owner = owner }
    elseif state.kind ~= "vertex" or state.owner ~= owner then
        return false
    end
    Track(region, state, owner)
    region:SetVertexColor(state.vertex[1], state.vertex[2], state.vertex[3], 0)
    return true
end

local function VisitPieces(frame, pieces, visit, owner, canPaint)
    if type(frame) ~= "table" then return end
    for index = 1, #pieces do
        local region = frame[pieces[index]]
        if not canPaint or canPaint(region) then visit(region, owner) end
    end
end

local dialogHeaderPieces = { "LeftBG", "CenterBG", "RightBG" }

function Cosmetics.VisitNineSlice(nineSlice, visit, owner)
    VisitPieces(nineSlice, nineSlicePieces, visit, owner)
end

function Cosmetics.FadeNineSlice(nineSlice, owner, canPaint)
    VisitPieces(nineSlice, nineSlicePieces, Cosmetics.Fade, owner, canPaint)
end

function Cosmetics.FadeDialogHeader(header, owner)
    VisitPieces(header, dialogHeaderPieces, Cosmetics.Fade, owner)
end

-- Restores the original value only while the region still shows ours;
-- a value installed later by Blizzard or another addon wins.
local function RestoreRegion(region, state)
    if state.decoration then ReleaseVisibility(region, state) end
    if not NS.Safety.CanDecorate(region, true) then
        Cosmetics.states[region] = nil
        return
    end
    if state.kind == "vertex" then
        local vertex = state.vertex
        local Safety = NS.Safety
        local r, g, b, a = Safety.ReadColor(region, "GetVertexColor")
        if Safety.SameColor(r, g, b, a, vertex[1], vertex[2], vertex[3], 0, Safety.COLOR_OWN) then
            region:SetVertexColor(vertex[1], vertex[2], vertex[3], vertex[4])
        end
    elseif state.kind == "alpha" and AccessibleAlpha(region) == 0 then
        WriteAlpha(region, state, state.alpha)
    end
    Cosmetics.states[region] = nil
end

-- A pooled part may already belong to a different frame. Relinquish the
-- ledger without writing into its new owner's visual state.
function Cosmetics.Forget(region, owner)
    local state = Cosmetics.states[region]
    if not state or state.owner ~= owner then return end
    if state.decoration and state.decoration.resume then NS.CombatGate.Cancel(state.decoration.resume) end
    Cosmetics.states[region] = nil
    local set = Cosmetics.owners[owner]
    if set then
        set[region] = nil
        if not next(set) then Cosmetics.owners[owner] = nil end
    end
end

function Cosmetics.Restore(region, owner)
    local state = region and Cosmetics.states[region]
    if not state or state.owner ~= owner then return false end
    RestoreRegion(region, state)
    local set = Cosmetics.owners[owner]
    if set then set[region] = nil end
    return true
end

function Cosmetics.RestoreOwner(owner)
    local set = Cosmetics.owners[owner]
    if not set then
        return
    end
    for region in pairs(set) do
        local state = Cosmetics.states[region]
        if state and state.owner == owner then
            RestoreRegion(region, state)
        end
    end
    Cosmetics.owners[owner] = nil
end

function Cosmetics.GetOwner(region)
    local state = Cosmetics.states[region]
    return state and state.owner or nil
end

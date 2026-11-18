local _, NS = ...

-- RXP V2 paints its own rxpBackground/rxpBorder texture groups rather than a
-- BackdropTemplate. Keep quest/action icons and secure item buttons native.
local Skin = {}
NS.RestedXPSkin = Skin
local Safety, Visuals = NS.Safety, NS.AddonSkinVisuals
local known, pending = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local collected = setmetatable({}, { __mode = "k" })
local generation = 1
local PaintNewWidgets
local leafMode = { rootSurface = false, allowImplicitProtected = true, maxDepth = 4, maxNodes = 96 }
local rootTypes = { RXPV2GuideWindow = true, RXPV2ActiveStepsFrame = true,
    RXPV2ActivePartyStepsFrame = true, RXPV2Popup = true }

local function CatchUpWidgets(widget)
    if not Safety.Public(widget) or type(widget) ~= "table" or collected[widget] == generation then return end
    collected[widget] = generation
    -- Existing guides can predate skin enable. AceGUI publishes these widget
    -- collections, including rows beyond the bounded initial frame walk.
    local steps = Safety.Field(widget, "guideSteps")
    if steps then Skin.Acquired(steps) CatchUpWidgets(steps) end
    for _, key in ipairs({ "children", "items" }) do
        local list = Safety.Field(widget, key)
        if type(list) == "table" then
            for _, child in pairs(list) do Skin.Acquired(child) end
        end
    end
end

local function FadeGroup(frame, key, owner)
    local group = Safety.Field(frame, key)
    if not Visuals.Safe(group, true) then return end
    local textures = Safety.Field(group, "textures")
    if type(textures) ~= "table" then return end
    for index = 1, math.min(#textures, 12) do Visuals.Fade(textures[index], owner, true) end
end

local function Visit(frame, owner, remaining, depth)
    if remaining <= 0 then return 0 end
    remaining = remaining - 1
    if depth > 12 or not Visuals.Safe(frame, true) then return remaining end
    local kind = Safety.Read(frame, "GetObjectType")
    if (kind == "Frame" or kind == "Button") and Safety.Field(frame, "rxpBackground") then
        FadeGroup(frame, "rxpBackground", owner)
        FadeGroup(frame, "rxpBorder", owner)
        Visuals.Surface(frame, owner, depth == 0 and "shell" or "panel", true)
    end
    local widget = Safety.Field(frame, "obj")
    CatchUpWidgets(widget)
    local widgetType = Safety.Field(widget, "type")
    if Safety.Public(widgetType) and widgetType == "RXPV2GuideWindow" then
        Visuals.Fade(Safety.Field(widget, "banner"), owner, true)
        Visuals.Fade(Safety.Field(widget, "footerBackground"), owner, true)
        local close = Safety.Field(widget, "closebutton")
        if Visuals.Safe(close, true) then NS.WindowActionSkin.ApplyExplicit(close, owner, "close") end
    end
    for _, child in ipairs({ Safety.Call(frame, "GetChildren") }) do
        if remaining <= 0 then break end
        remaining = Visit(child, owner, remaining, depth + 1)
    end
    return remaining
end

function Skin.Paint(frame, owner)
    -- GetGuideWindow publishes its global only after AceGUI's OnAcquire.
    NS.AddonSkins.ObserveRestedXP()
    Visit(frame, owner, 640, 0)
    if next(pending) then NS.Registry.QueueJob(PaintNewWidgets) end
end

function Skin.Invalidate() generation = generation + 1 end

PaintNewWidgets = function()
    if not NS.AddonSkins.IsEnabled("restedXP") or NS.AddonSkins.cooperative.restedXP then wipe(pending) return end
    if NS.IsCombatLocked() then NS.CombatGate.RunOrDefer(pending, PaintNewWidgets) return end
    for frame, kind in pairs(pending) do
        if kind ~= true then
            pending[frame] = nil
            if NS.AddonSkins.Watch(frame, "restedXP") then NS.AddonSkins.RefreshFrame(frame) end
        elseif known[frame] ~= generation then
            local parent, waiting = frame, false
            for _ = 1, 16 do
                if not Safety.Public(parent) or not parent then break end
                local state = NS.AddonSkins.roots[parent]
                if state then
                    if state.id == "restedXP" then
                        if state.applied then
                            if NS.GenericWindows.ApplyDescendant(frame, state.owner, leafMode) then
                                Visuals.Tree(frame, state.owner, 96, true)
                                Visit(frame, state.owner, 96, 0)
                                known[frame] = generation -- All leaf passes, including fonts/controls, completed.
                            end
                        else waiting = true end
                    end
                    break
                end
                if pending[parent] and pending[parent] ~= true then waiting = true end
                parent = Safety.Read(parent, "GetParent")
            end
            if not waiting then pending[frame] = nil end
        else
            pending[frame] = nil
        end
    end
end

function Skin.Acquired(widget)
    if not NS.AddonSkins.IsEnabled("restedXP") or NS.AddonSkins.cooperative.restedXP then return end
    local frame, kind = Safety.Field(widget, "frame"), Safety.Field(widget, "type")
    if not Safety.Public(kind) or not Safety.Public(frame) or not frame
        or Safety.IsForbidden(frame) or Safety.IsCompositorManaged(frame) then return end
    local _, explicit = Safety.GetProtection(frame)
    if explicit then return end
    if NS.IsCombatLocked() then
        pending[frame] = rootTypes[kind] and kind or true
        NS.Registry.QueueJob(PaintNewWidgets)
        return
    end
    if not Visuals.Safe(frame, true) then return end
    if rootTypes[kind] then
        if NS.AddonSkins.Watch(frame, "restedXP") then NS.AddonSkins.RefreshFrame(frame) end
    elseif known[frame] ~= generation then
        pending[frame] = true
        NS.Registry.QueueJob(PaintNewWidgets)
    end
end

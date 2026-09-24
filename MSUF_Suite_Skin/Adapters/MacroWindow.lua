local _, NS = ...

-- Blizzard owns the macro selector, icon data and command editor. This adapter
-- replaces only its verified slot art and decorative frame textures.
local MacroWindow = { states = setmetatable({}, { __mode = "k" }) }
NS.MacroWindow = MacroWindow

local slotBackdrop = "interface\\buttons\\ui-emptyslot-disabled"
local divider = "interface\\classtrainerframe\\ui-classtrainer-horizontalbar"

local function TexturePath(region)
    if not region or type(region.GetTexture) ~= "function" then return nil end
    local path = region:GetTexture()
    if type(path) ~= "string" then return nil end
    return path:gsub("/", "\\"):lower()
end

local function FadeMatching(owner, wanted, ...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if TexturePath(region) == wanted then NS.Cosmetics.Fade(region, owner) end
    end
end

local function Selected(button)
    local texture = button and button.SelectedTexture
    if not texture or type(texture.IsShown) ~= "function" then return false end
    local shown = texture:IsShown()
    if type(issecretvalue) == "function" and issecretvalue(shown) then return false end
    return shown == true
end

local function RefreshVisibleSelection(state)
    if not state.active or NS.IsCombatLocked() then return end
    local scrollBox = state.scrollBox
    if not scrollBox or type(scrollBox.ForEachFrame) ~= "function" then return end
    scrollBox:ForEachFrame(function(button)
        if state.buttons[button] then NS.Surface.SetActive(button, Selected(button)) end
    end)
end

local function StyleSlot(state, button)
    if not state.active or NS.IsCombatLocked() or not button
        or not NS.Safety.CanCreateRegions(button, true)
        or not button.Icon or not button.SelectedTexture then return false end
    if type(button.GetRegions) == "function" then
        FadeMatching(state.owner, slotBackdrop, button:GetRegions())
    end
    NS.Cosmetics.Fade(button.SelectedTexture, state.owner)
    NS.Cosmetics.Fade(button.Highlight, state.owner)
    local surface = NS.Surface.Attach(button, {
        role = "button", activeRole = "navigationActive",
        shape = "continuous", radius = 4, inset = 0,
        forceEdge = true, activeEdge = true, interactive = true,
        allowImplicitProtected = true,
    })
    if not surface then return false end
    -- The icon is native ARTWORK. Put the transparent edge above it while
    -- retaining Blizzard's normal icon, name, drag and click behavior.
    surface.edge:SetDrawLayer("OVERLAY", 2)
    state.buttons[button] = true
    NS.Surface.SetActive(button, Selected(button))
    if not state.clickHooks[button] and type(button.HookScript) == "function" then
        button:HookScript("OnClick", function() RefreshVisibleSelection(state) end)
        state.clickHooks[button] = true
    end
    return true
end

local function StyleFrame(state, frame)
    local owner = state.owner
    NS.Cosmetics.Fade(_G.MacroFramePortrait, owner)
    NS.Cosmetics.Fade(_G.MacroFrameSelectedMacroBackground, owner)
    if type(frame.GetRegions) == "function" then
        FadeMatching(owner, divider, frame:GetRegions())
    end
    local background = _G.MacroFrameTextBackground
    if background and NS.Safety.CanCreateRegions(background, true) then
        NS.Cosmetics.FadeNineSlice(background.NineSlice, owner)
        if NS.Surface.Attach(background, {
            role = "input", shape = "continuous", radius = 6,
            inset = 0, allowImplicitProtected = true,
        }) then state.textBackground = background end
    end
    StyleSlot(state, frame.SelectedMacroButton)
end

function MacroWindow.Apply(frame, owner)
    if not frame or NS.IsCombatLocked() or not NS.Safety.CanCreateRegions(frame, true) then
        return false
    end
    local selector = frame.MacroSelector
    local scrollBox = selector and selector.ScrollBox
    -- Older Classic macro windows use a different template. The generic
    -- window skin remains their supported path.
    if not scrollBox or type(scrollBox.ForEachFrame) ~= "function" then return true end
    local state = MacroWindow.states[frame]
    if not state then
        state = {
            buttons = setmetatable({}, { __mode = "k" }),
            clickHooks = setmetatable({}, { __mode = "k" }),
        }
        MacroWindow.states[frame] = state
    end
    state.active, state.owner, state.scrollBox = true, owner, scrollBox
    StyleFrame(state, frame)
    local event = ScrollBoxListMixin and ScrollBoxListMixin.Event
        and ScrollBoxListMixin.Event.OnInitializedFrame
    if event and not state.registered and type(scrollBox.RegisterCallback) == "function" then
        scrollBox:RegisterCallback(event, function(_, button)
            if state.active then StyleSlot(state, button) end
        end, state)
        state.registered, state.event = true, event
    end
    scrollBox:ForEachFrame(function(button) StyleSlot(state, button) end)
    return true
end

function MacroWindow.Disable(owner)
    if NS.IsCombatLocked() then return false end
    for _, state in pairs(MacroWindow.states) do
        if state.owner == owner and state.active then
            state.active = false
            if state.registered and state.scrollBox
                and type(state.scrollBox.UnregisterCallback) == "function" then
                state.scrollBox:UnregisterCallback(state.event, state)
            end
            state.registered = false
            for button in pairs(state.buttons) do NS.Surface.SetVisible(button, false) end
            if state.textBackground then NS.Surface.SetVisible(state.textBackground, false) end
        end
    end
    return true
end

return MacroWindow

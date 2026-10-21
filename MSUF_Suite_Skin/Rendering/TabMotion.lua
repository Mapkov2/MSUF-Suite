local _, NS = ...

local Tabs = { hooked = setmetatable({}, { __mode = "k" }) }
NS.TabMotion = Tabs
local Safety = NS.Safety
local methods = { "SetTabSelected", "SetSelected" }

local function Update(tab, selected)
    local state = NS.ControlSkin.states[tab]
    if not state or not state.enabled or not Safety.Public(selected) or type(selected) ~= "boolean"
        or Safety.IsForbidden(tab) or Safety.GetProtection(tab) or NS.IsCombatLocked() or NS.Motion.combat then return end
    NS.ControlSkin.Refresh(tab, selected)
    if selected then NS.MenuMotion.SelectionChanged(tab) end
end
local function Selected(tab) Update(tab, true) end
local function Deselected(tab) Update(tab, false) end

function Tabs.Track(tab)
    if Tabs.hooked[tab] then return end
    Tabs.hooked[tab] = true
    for index = 1, #methods do
        local method = methods[index]
        if Safety.HasMethod(tab, method) then hooksecurefunc(tab, method, Update) end
    end
end
NS.ControlSkin.SetTabMotionProvider(Tabs.Track)
-- SharedXML's legacy updater reaches these for mouse, keyboard and code paths.
hooksecurefunc("PanelTemplates_SelectTab", Selected)
hooksecurefunc("PanelTemplates_DeselectTab", Deselected)

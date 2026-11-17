local _, NS = ...

local Tabs = { hooked = setmetatable({}, { __mode = "k" }) }
NS.TabMotion = Tabs
local Safety = NS.Safety
local methods = { "SetTabSelected", "SetSelected" }
local mailTabs = {}

local function PaintSelection(tab, selected)
    local state = NS.ControlSkin.states[tab]
    if not state or not state.enabled or Safety.IsForbidden(tab) or Safety.GetProtection(tab) then return end
    NS.ControlSkin.Refresh(tab, selected)
    if selected then NS.MenuMotion.SelectionChanged(tab) end
end

local function PaintMailTabs()
    for tab, selected in pairs(mailTabs) do
        mailTabs[tab] = nil
        if Safety.Read(tab, "IsVisible") == true then PaintSelection(tab, selected) end
    end
end

local function Update(tab, selected)
    if not Safety.Public(tab) or not Safety.Public(selected) or type(selected) ~= "boolean" then return end
    if NS.Client.isForever and tab ~= nil
        and (tab == Safety.Field(_G, "MailFrameTab1") or tab == Safety.Field(_G, "MailFrameTab2")) then
        -- MailFrame_Show selects the Inbox tab before its protected reading emote.
        local state = NS.ControlSkin.states[tab]
        if state and state.enabled then
            mailTabs[tab] = selected
            NS.Registry.QueueJob(PaintMailTabs)
        end
    else
        PaintSelection(tab, selected)
    end
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

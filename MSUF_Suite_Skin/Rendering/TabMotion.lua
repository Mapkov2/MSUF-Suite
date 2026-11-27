local _, NS = ...

local Tabs = { hooked = setmetatable({}, { __mode = "k" }) }
NS.TabMotion = Tabs
local Safety = NS.Safety
local methods = { "SetTabSelected", "SetSelected" }
local mailTabs = {}
-- TabSystem broadcasts SetTabSelected to every sibling, several times per
-- switch. GetTime() is frame-stable: a selection this frame already painted
-- (and a surface that still shows it) only repairs what native code rewrites.
-- A new frame, a flipped selection or a settings write paints again.
local paintedAt = setmetatable({}, { __mode = "k" })
local paintedSelected = setmetatable({}, { __mode = "k" })

local function PaintSelection(tab, selected)
    local state = NS.ControlSkin.states[tab]
    if not state or not state.enabled or Safety.IsForbidden(tab) or Safety.GetProtection(tab) then return end
    local now = GetTime()
    if paintedAt[tab] == now and paintedSelected[tab] == selected then
        local surface = NS.Registry.GetSurface(tab)
        if surface and surface.active == selected and surface.visible ~= false
            and NS.ControlSkin.RepairBindings(tab) then return end
    end
    paintedAt[tab] = NS.ControlSkin.Refresh(tab, selected, true) and now or nil
    paintedSelected[tab] = selected
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
NS.Registry.AddListener(Tabs, function() wipe(paintedAt) end)
-- SharedXML's legacy updater reaches these for mouse, keyboard and code paths.
hooksecurefunc("PanelTemplates_SelectTab", Selected)
hooksecurefunc("PanelTemplates_DeselectTab", Deselected)

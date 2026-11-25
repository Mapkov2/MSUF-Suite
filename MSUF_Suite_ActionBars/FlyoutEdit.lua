local _, Private = ...
local NS, S = Private.NS, Private.Suite
local AB, Host = Private.ActionBars, NS.HostBridge
local API = S.ActionBarFlyouts
local Edit = {}
AB.FlyoutEdit = Edit

local CURSOR_TYPES = { spell = true, item = true, macro = true, toy = true, mount = true }
local RENAME, ADD_ID, DELETE = "suite-flyout-rename", "suite-flyout-id", "suite-flyout-delete"
local STYLE_CHANGED = "MSUFSuite.ActionBars.StyleChanged"
local overlays, needsPaint = {}, true
local showing, listener, paintedStyle, openBox, dropBadge
local accent, background, border

local function Report(ok, problem)
    if ok then return true end
    S.Print(problem or S.Text("This change could not be made."))
end

function Edit.AcceptsCursor(kind, id)
    if not S.Public(kind) or not CURSOR_TYPES[kind] then return false end
    return kind ~= "macro" or S.Finite(id) and not AB.Flyouts.IsFlyoutMacro(id)
end

local function CursorBusy()
    local kind = GetCursorInfo()
    return not S.Public(kind) or kind ~= nil
end

local function HideTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function Tip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(S.Text("Add to flyout"))
    GameTooltip:Show()
end

local function NewBadge(parent, drop)
    local button = S.CreateFrame("Button", nil, parent)
    button:SetSize(14, 14)
    button:SetIgnoreParentAlpha(true)
    button.hover = S.CreateTexture(button, nil, "HIGHLIGHT")
    button.hover:SetAllPoints()
    button.border = S.CreateTexture(button, nil, "ARTWORK")
    button.border:SetAllPoints()
    button.fill = S.CreateTexture(button, nil, "ARTWORK", nil, 1)
    button.fill:SetSize(12, 12)
    button.fill:SetPoint("CENTER")
    button.strokes = {}
    for i = 1, 2 do
        local stroke = S.CreateTexture(button, nil, "OVERLAY")
        stroke:SetPoint("CENTER")
        stroke:SetSize(i == 1 and 8 or 2, i == 1 and 2 or 8)
        button.strokes[i] = stroke
    end
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", drop)
    button:SetScript("OnReceiveDrag", drop)
    button:SetScript("OnEnter", Tip)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnHide", HideTooltip)
    return button
end

local function PaintBadge(button)
    button.fill:SetColorTexture(background[1], background[2], background[3], .94)
    button.border:SetColorTexture(border[1], border[2], border[3], 1)
    for _, stroke in ipairs(button.strokes) do stroke:SetColorTexture(accent[1], accent[2], accent[3], 1) end
    button.hover:SetColorTexture(accent[1], accent[2], accent[3], .22)
end

function Edit.DropIn(box, before)
    if not box:IsShown() or NS.InCombat() or not Edit.AcceptsCursor(GetCursorInfo()) then return end
    Report(API.AddCursor(box.flyoutID, before))
    Edit.CursorChanged(GetCursorInfo())
end

local function DropIntoOpen()
    if openBox then Edit.DropIn(openBox) end
end

local function ShowDropBadge()
    if not openBox then return end
    if not dropBadge then
        dropBadge = NewBadge(UIParent, DropIntoOpen)
        dropBadge:SetFrameStrata("DIALOG")
        dropBadge:SetClampedToScreen(true)
        PaintBadge(dropBadge)
    end
    if dropBadge:GetParent() ~= openBox then
        dropBadge:SetParent(openBox)
        dropBadge:ClearAllPoints()
        dropBadge:SetPoint("BOTTOMRIGHT", openBox, "TOPRIGHT", -2, 2)
    end
    dropBadge:Show()
end

function Edit.FlyoutOpened(box)
    openBox = box
    if showing then ShowDropBadge() end
end

function Edit.FlyoutClosed(box)
    if openBox ~= box then return end
    openBox = nil
    if dropBadge then dropBadge:Hide() end
end

local function PaintMode()
    if not showing then
        needsPaint = true
        return
    end
    local style = AB.style or AB.BuildStyle()
    accent = Host.MenuColor("accent", "text") or { style.kr, style.kg, style.kb }
    background = Host.MenuColor("panel", "bg") or { style.sr, style.sg, style.sb }
    border = Host.MenuColor("borderSoft", "border") or { style.br, style.bg, style.bb }
    for _, badge in ipairs(overlays) do PaintBadge(badge) end
    if dropBadge then PaintBadge(dropBadge) end
    needsPaint, paintedStyle = false, AB.styleGen
end

local function Stop()
    if not showing then return end
    showing, AB.flyoutDrag = false, nil
    if dropBadge then dropBadge:Hide() end
    for _, badge in ipairs(overlays) do badge:Hide() end
    listener:UnregisterAllEvents()
    EventRegistry:UnregisterCallback(STYLE_CHANGED, listener)
end
Edit.Stop = Stop

local function DropOnBar(badge)
    if not showing or not badge:IsVisible() or NS.InCombat() or not Edit.AcceptsCursor(GetCursorInfo()) then return end
    Report(API.DropOnButton(badge.record))
    Edit.CursorChanged(GetCursorInfo())
end

local function BuildBadges()
    listener = S.CreateFrame("Frame")
    listener:SetScript("OnEvent", Stop)
    Host.WatchMenuAppearance(listener, PaintMode)
    for _, record in ipairs(AB.owned) do
        local badge = NewBadge(record.button, DropOnBar)
        badge.record = record
        badge:SetPoint("TOPLEFT", record.button, "TOPLEFT", 1, -1)
        badge:SetFrameStrata("HIGH")
        overlays[#overlays + 1] = badge
    end
end

-- Feed the same cursor sample that already controls the action-bar grid.
function Edit.CursorChanged(kind, id)
    local wanted = Edit.AcceptsCursor(kind, id) and AB.M.active == true and not NS.InCombat()
    if not wanted then
        if showing then Stop() end
        return
    end
    if showing then return end
    showing, AB.flyoutDrag = true, true
    if not listener then BuildBadges() end
    if needsPaint or paintedStyle ~= AB.styleGen then PaintMode() end
    listener:RegisterEvent("PLAYER_REGEN_DISABLED")
    EventRegistry:RegisterCallback(STYLE_CHANGED, PaintMode, listener)
    for _, badge in ipairs(overlays) do badge:Show() end
    ShowDropBadge()
end

local function Pickup(id)
    if NS.InCombat() or CursorBusy() then return end
    if Report(API.Pickup(id)) then S.Print(S.Text("Drop the flyout on any action button.")) end
end

local function Ask(key, text, callback, limit)
    if NS.InCombat() then return end
    S.AskText(key, { text = "%s", text_arg1 = text, callback = callback, maxLetters = limit })
end

local function SavedOptions(root, flyout)
    local id = flyout.id
    local item = root:CreateButton(flyout.name)
    item:CreateButton(S.Text("Pick up"), function() Pickup(id) end)
    item:CreateButton(S.Text("Rename"), function()
        Ask(RENAME, S.Text("New name for %s"):format(flyout.name), function(name) Report(API.Rename(id, name)) end,
            NS.ActionBarFlyouts.MAX_NAME)
    end)
    item:CreateCheckbox(S.Text("Only show what I carry or know"), function() return flyout.owned end, function()
        Report(API.SetOwned(id, not flyout.owned))
    end)
    item:CreateButton(S.Text("Add by ID"), function()
        Ask(ADD_ID, S.Text("Item or spell ID, for example item:4540 or spell:8690"), function(text) Report(API.AddText(id, text)) end, 64)
    end)
    item:CreateButton(S.Text("Delete flyout"), function()
        if NS.InCombat() then return end
        S.Confirm(DELETE, {
            text = "%s", text_arg1 = S.Text("Delete the flyout %s? Its macro leaves every action bar."):format(flyout.name),
            callback = function() Report(API.Delete(id)) end,
        })
    end)
end

local function PresetOptions(root)
    local categories = {}
    for _, preset in ipairs(API.Presets()) do
        local menu = root
        if preset.category then
            local category = preset.category
            if not categories[category] then
                local label = category == "dungeons" and S.Text("Dungeon teleports") or S.Text("Raid teleports")
                categories[category] = root:CreateButton(label)
            end
            menu = categories[category]
        end
        local option = menu:CreateButton(preset.label, function()
            if NS.InCombat() or CursorBusy() then return end
            local id, failure = API.AddPreset(preset.key, preset.flyoutName)
            if Report(id, failure) then Pickup(id) end
        end)
        if preset.description then
            option:SetTooltip(function(tooltip)
                tooltip:SetText(preset.label)
                tooltip:AddLine(preset.description, .85, .85, .85, true)
            end)
        end
    end
end

local function OpenList(owner, saved)
    local ok, problem = API.Ready()
    if not Report(ok, problem) or CursorBusy() then return end
    S.ContextMenu(owner, function(_, root)
        if saved then
            local list = AB.Flyouts.Store().list
            if #list == 0 then root:CreateTitle(S.Text("No flyouts yet")) end
            for _, flyout in ipairs(list) do SavedOptions(root, flyout) end
            return
        end
        PresetOptions(root)
    end)
end

function API.OpenPresets(owner)
    OpenList(owner, false)
end

function API.OpenSaved(owner)
    OpenList(owner, true)
end

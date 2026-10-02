local _, P = ...
local NS, S = P.NS, P.Suite
local Sources = P.DataTextSources
local NO_VALUE = P.NO_VALUE

-- What clicks, the mouse wheel and tooltips of the additional DataText
-- sources do. DataText places are ordinary buttons, so bars may move and
-- resize in combat. A protected click runs on a secure button the Suite
-- never lays out in combat:
--   * Hearthstone and Specialization places borrow one secure overlay while
--     the pointer rests on them out of combat. It lives in UIParent above the
--     place, never inside a bar, and runs its SecureActionButtonTemplate click
--     (item, toy or a click on Blizzard's talent micro button); the Suite only
--     adds PostClick.
--   * The built-in Durability, Coordinates and Zone places borrow it too: it
--     clicks the Blizzard button that opens their window (S.PanelButton), so
--     the character window and the world map open from secure code. Without
--     that button the place opens the window itself (Standard.Click).
--   * Dungeon portals and the micro menu open a popup of secure rows.
-- PLAYER_REGEN_DISABLED runs before lockdown starts: DataTexts.lua releases
-- both there, so no protected frame depends on a bar during combat. A
-- "[combat] hide" state driver backs that up.
local Actions = {}
P.DataTextActions = Actions

local OVERLAY_KINDS = { hearth = true, specialization = true }
-- Built-in places whose window a Blizzard button opens (S.PanelButton).
local PANEL_SOURCES = { durability = "character", coordinates = "worldMap", location = "worldMap" }
local SPEC_BUTTON = NS.Client.isForever and "TalentMicroButton" or "PlayerSpellsMicroButton"
local ROW_LIMIT = 100
local overlay, popup, leaveTimer

local function Locked()
    return NS.IsCombatLocked()
end

------------------------------------------------------------------ secure overlay
-- The left-button action of a place: type, item, toy and click target.
local function SecureAction(button)
    local binding = button.extra
    if not binding then
        local target = S.PanelButton(PANEL_SOURCES[button.source])
        if target then return "click", nil, nil, target end
        return nil
    end
    if binding.kind == "hearth" then
        local item = binding.hearth
        if not item then return nil end
        if item.toy then return "toy", nil, item.id end
        return "item", "item:" .. item.id
    end
    local native = _G[SPEC_BUTTON]
    if native then return "click", nil, nil, native end
end

local function OverlayEnter(self)
    if self.owner then Actions.enter(self.owner) end
end

local function OverlayLeave(self)
    local owner = self.owner
    Actions.Detach()
    if owner then Actions.leave(owner) end
end

-- The next random Hearthstone variant after a use.
local function OverlayPostClick(self)
    local binding = self.owner and self.owner.extra
    if binding and binding.kind == "hearth" then Sources.PrepareHearths() end
end

local function Overlay()
    if overlay then return overlay end
    overlay = S.CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("AnyUp")
    overlay:SetAttribute("useOnKeyDown", false)
    overlay:SetScript("OnEnter", OverlayEnter)
    overlay:SetScript("OnLeave", OverlayLeave)
    overlay:SetScript("PostClick", OverlayPostClick)
    overlay:Hide()
    RegisterStateDriver(overlay, "visibility", "[combat] hide")
    Actions.overlay = overlay
    return overlay
end

local function Overlaid(button)
    local binding = button.extra
    if binding then return OVERLAY_KINDS[binding.kind] == true end
    return PANEL_SOURCES[button.source] ~= nil
end

-- Puts the secure overlay over a Hearthstone, Specialization or window
-- place; force writes the action again for the place that already has it.
function Actions.Attach(button, force)
    if Locked() or S.editMode or not Overlaid(button) then return false end
    if not force and overlay and overlay.owner == button and overlay:IsShown() then return true end
    local kind, item, toy, target = SecureAction(button)
    if not kind then return false end
    local frame = Overlay()
    frame.owner = button
    frame:SetAttribute("type1", kind)
    frame:SetAttribute("item1", item)
    frame:SetAttribute("toy1", toy)
    frame:SetAttribute("clickbutton1", target)
    -- Every mouse button of a Specialization or window place opens its
    -- window, as the place did and Blizzard's buttons do (their OnClick
    -- ignores the button); the unsuffixed attributes cover the others.
    local any = kind == "click" and target or nil
    frame:SetAttribute("type", any and kind)
    frame:SetAttribute("clickbutton", any)
    frame:SetFrameStrata(button:GetFrameStrata())
    frame:SetFrameLevel(button:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    frame:SetAllPoints(button)
    frame:Show()
    return true
end

-- In combat only the bookkeeping changes; the overlay is hidden already and
-- its points are released after combat (Actions.Resume).
function Actions.Detach()
    if not overlay then return end
    overlay.owner = nil
    if Locked() then return end
    overlay:Hide()
    overlay:ClearAllPoints()
end

function Actions.Owner()
    return overlay and overlay.owner
end

-- Whether the overlay over this place now holds the pointer.
function Actions.Covers(button)
    return overlay ~= nil and overlay.owner == button and overlay:IsShown() and overlay:IsMouseOver()
end

-- Settings or a new Hearthstone choice changed the attached place.
function Actions.Refresh()
    local button = overlay and overlay.owner
    if not button or Locked() then return end
    if not Actions.Attach(button, true) then Actions.Detach() end
end

------------------------------------------------------------------ secure popup
local function ClosePopup()
    if not popup or Locked() then return end
    popup.owner = nil
    popup:Hide()
    popup:ClearAllPoints()
end
Actions.ClosePopup = ClosePopup

-- Leaving the popup, one of its rows or its place closes it once the pointer
-- rests on none of them: rows and the gaps between them belong to the popup.
local function CheckLeave()
    leaveTimer = nil
    if not popup or not popup:IsShown() or Locked() then return end
    if popup:IsMouseOver() or popup.owner and popup.owner:IsMouseOver() then return end
    ClosePopup()
end

local function WatchLeave()
    if leaveTimer then leaveTimer:Cancel() end
    leaveTimer = C_Timer.NewTimer(.15, CheckLeave)
end

-- A used entry closes the popup (out of combat, right after its action). A
-- plain row (the game menu, S.MicroMenuEntries) has no secure action: its
-- own action runs here, after the popup closed.
local function RowPostClick(row)
    local action = row.action
    ClosePopup()
    if action then action() end
end

local function Popup()
    if popup then return popup end
    popup = S.CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:EnableMouse(true)
    popup.rows = {}
    local fill = S.CreateTexture(popup, nil, "BACKGROUND")
    fill:SetAllPoints(popup)
    fill:SetColorTexture(.04, .05, .07, .97)
    popup:SetScript("OnLeave", WatchLeave)
    popup:Hide()
    RegisterStateDriver(popup, "visibility", "[combat] hide")
    Actions.popup = popup
    return popup
end

local function Row(index)
    local row = popup.rows[index]
    if row then return row end
    row = S.CreateFrame("Button", nil, popup, "SecureActionButtonTemplate")
    row:RegisterForClicks("AnyUp")
    row:SetAttribute("useOnKeyDown", false)
    row:SetScript("OnLeave", WatchLeave)
    row:SetScript("PostClick", RowPostClick)
    row:SetSize(232, 24)
    row:SetPoint("TOPLEFT", popup, "TOPLEFT", 4, -4 - (index - 1) * 26)
    row.icon = S.CreateTexture(row, nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetSize(22, 22)
    row.label = S.CreateFontString(row, nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetWidth(204)
    row.label:SetWordWrap(false)
    row.cooldown = S.CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cooldown:SetAllPoints(row.icon)
    popup.rows[index] = row
    return row
end

-- Opens the popup above a place; fill(row, index) sets up each entry.
local function OpenPopup(button, count, fill)
    if Locked() then return end
    count = math.min(count, ROW_LIMIT)
    if count == 0 then
        ClosePopup()
        return
    end
    local frame = Popup()
    frame.owner = button
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 3)
    frame:SetSize(240, math.max(1, count) * 26 + 8)
    for i = 1, count do
        local row = Row(i)
        fill(row, i)
        row:Show()
    end
    for i = count + 1, #frame.rows do frame.rows[i]:Hide() end
    frame:Show()
end

local portals
local function FillPortal(row, index)
    local spell = portals[index]
    row:SetAttribute("type", "spell")
    row:SetAttribute("spell", spell.id)
    row:SetAttribute("clickbutton", nil)
    row.action = nil
    -- A micro menu row may have shown a disabled micro button before.
    row:SetEnabled(true)
    row.icon:SetTexture(spell.icon)
    row.label:SetText(spell.name)
    row.label:SetTextColor(1, 1, 1)
    local duration = C_Spell.GetSpellCooldownDuration(spell.id)
    if duration then row.cooldown:SetCooldownFromDurationObject(duration) else row.cooldown:Clear() end
end

function Actions.PortalMenu(button)
    if Locked() or not NS.Client.modernEquipment then return end
    -- LearnedDungeonPortals belongs to the optional QualityOfLife addon.
    if not S.LearnedDungeonPortals then C_AddOns.LoadAddOn("MSUF_Suite_QualityOfLife") end
    if not S.LearnedDungeonPortals then return end
    portals = S.LearnedDungeonPortals()
    OpenPopup(button, #portals, FillPortal)
end

local micro = {}
local function FillMicro(row, index)
    local entry = micro[index]
    row:SetAttribute("type", entry.button and "click" or nil)
    row:SetAttribute("clickbutton", entry.button)
    row:SetAttribute("spell", nil)
    row.action = entry.action
    row:SetEnabled(entry.enabled)
    row.icon:SetTexture(nil)
    row.cooldown:Clear()
    row.label:SetText(entry.label)
    local shade = entry.enabled and 1 or .5
    row.label:SetTextColor(shade, shade, shade)
end

-- The Suite's micro menu (S.MicroMenuEntries, the same entries as the
-- Minimap's middle-click flyout), clicked by the secure rows, plus the plain
-- game menu row.
function Actions.MicroMenu(button)
    if Locked() then return end
    OpenPopup(button, S.MicroMenuEntries(micro, true), FillMicro)
end

------------------------------------------------------------------ combat
-- PLAYER_REGEN_DISABLED, before lockdown starts: release every secure frame.
function Actions.Release()
    if overlay then
        overlay.owner = nil
        overlay:Hide()
        overlay:ClearAllPoints()
    end
    ClosePopup()
end

-- PLAYER_REGEN_ENABLED: drop points kept by a late release and offer the
-- overlay again to the place the pointer rests on.
function Actions.Resume()
    if overlay and not overlay.owner then overlay:ClearAllPoints() end
    local button = Actions.hovered
    if button and button:IsVisible() and button:IsMouseOver() then Actions.Attach(button) end
end

------------------------------------------------------------------ interactions
function Actions.Wheel(button, delta)
    local binding = button.extra
    if not binding or binding.kind ~= "audio" then return end
    local key = Sources.AUDIO[S.Config("dataTexts").audioChannel or 1]
    local value = tonumber(C_CVar.GetCVar(key))
    if S.Finite(value) then C_CVar.SetCVar(key, math.max(0, math.min(1, value + delta * .05))) end
end

-- Broker plugins and the volume react at any time; places that open
-- Blizzard windows or secure popups wait until combat ends.
function Actions.Click(button, mouse)
    local binding = button.extra
    local kind = binding.kind
    if kind == "broker" then
        local object = Sources.BrokerObject(binding)
        if object and type(object.OnClick) == "function" then S.Dispatch(NS.Finish, object.OnClick, button, mouse) end
    elseif kind == "audio" then
        Actions.Wheel(button, mouse == "RightButton" and -1 or 1)
    elseif Locked() then
        return
    elseif OVERLAY_KINDS[kind] then
        -- The overlay performs this click; a click that reaches the place
        -- found it detached, so attach it for the next one.
        Actions.Attach(button)
    elseif kind == "professions" then
        C_AddOns.LoadAddOn("Blizzard_ProfessionsBook")
        if _G.ProfessionsBookFrame then ToggleFrame(ProfessionsBookFrame) end
    elseif kind == "currency" or kind == "crests" then
        ToggleCharacter("TokenFrame")
    elseif kind == "portals" then
        Actions.PortalMenu(button)
    elseif kind == "microMenu" then
        Actions.MicroMenu(button)
    end
end

-- An OnTooltipShow plugin fills the Suite's tooltip below the source name
-- and the place's text. A plugin with its own OnEnter draws its own tooltip;
-- the Suite adds none beside it.
local function BrokerTooltip(button, binding, title)
    local object = Sources.BrokerObject(binding)
    if object and type(object.OnTooltipShow) == "function" then
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(title, 1, .82, .36)
        GameTooltip:AddLine(button.text or NO_VALUE, 1, 1, 1)
        S.Dispatch(NS.Finish, object.OnTooltipShow, GameTooltip)
        GameTooltip:Show()
        return true
    end
    if object and type(object.OnEnter) == "function" then
        S.Dispatch(NS.Finish, object.OnEnter, button)
        return true
    end
end

local function CrestLines(config)
    GameTooltip:AddLine(S.Text("Seasonal upgrade resources observed this login"), 1, 1, 1)
    if config.crestMode ~= 2 and Sources.seasonItem then GameTooltip:AddLine(Sources.seasonItem, .7, .7, .7) end
    for _, cost in ipairs(Sources.SeasonSelection()) do
        local name, quantity = Sources.SeasonValue(cost)
        if name then GameTooltip:AddDoubleLine(tostring(cost.order) .. ": " .. name, tostring(quantity)) end
    end
end

-- The whole tooltip of an additional source; title is its source name.
function Actions.Tooltip(button, title)
    local binding = button.extra
    local kind = binding.kind
    if kind == "portals" then
        Actions.PortalMenu(button)
        return
    end
    if kind == "broker" and BrokerTooltip(button, binding, title) then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    if kind == "currency" and binding.currency > 0 then
        GameTooltip:SetCurrencyByID(binding.currency)
    elseif kind == "hearth" and binding.hearth then
        GameTooltip:SetItemByID(binding.hearth.id)
    else
        GameTooltip:ClearLines()
        GameTooltip:AddLine(title, 1, .82, .36)
        GameTooltip:AddLine(button.text or NO_VALUE, 1, 1, 1)
        if kind == "crests" then
            CrestLines(S.Config("dataTexts"))
        elseif kind == "audio" then
            GameTooltip:AddLine(S.Text("Mouse wheel or left/right click changes volume by 5%."), 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

function Actions.Leave(button)
    local binding = button.extra
    if not binding then return end
    if binding.kind == "broker" then
        local object = Sources.BrokerObject(binding)
        if object and type(object.OnLeave) == "function" then S.Dispatch(NS.Finish, object.OnLeave, button) end
    end
    if popup and popup.owner == button then WatchLeave() end
end

function Actions.GoldTooltip(tooltip)
    local config = S.Config("dataTexts")
    if not config.showTokenPrice or not NS.Client.modernEquipment then return end
    local price = C_WowTokenPublic.GetCurrentMarketPrice()
    if S.Finite(price) then tooltip:AddDoubleLine(S.Text("WoW Token"), S.MoneyText(price)) end
end

function Actions.Disable()
    if leaveTimer then
        leaveTimer:Cancel()
        leaveTimer = nil
    end
    Actions.hovered = nil
    Actions.Detach()
    ClosePopup()
end

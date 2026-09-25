local _, P = ...
local S = P.Suite
local ID = "afkScreen"

-- A cinematic screen while the player is AFK: the character model between
-- the equipped items, the regular UI faded out and a slow camera orbit.
-- It never opens or does work in combat.
local M = {}
local FONT = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf"
local GOLD = { .88, .69, .42 }
local WHITE = { .96, .95, .91 }
local MUTED = { .67, .72, .76 }
local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }
local SLOT_NAMES = {
    "Head", "Neck", "Shoulders", "Back", "Chest", "Shirt", "Tabard", "Wrists", "Hands",
    "Waist", "Legs", "Feet", "Ring", "Ring", "Trinket", "Trinket", "Main Hand", "Off Hand",
}

local function PublicText(value)
    return S.Public(value) and type(value) == "string" and value ~= "" and value or nil
end

local function ReadText(fn, ...)
    if type(fn) ~= "function" then return nil end
    return PublicText((fn(...)))
end

local function Fill(parent, layer, r, g, b, a)
    local texture = S.CreateTexture(parent, nil, layer)
    texture:SetColorTexture(r, g, b, a)
    return texture
end

local function Label(parent, size, color, text)
    local label = S.CreateFontString(parent, nil, "OVERLAY")
    S.SetFont(label, FONT, size, "OUTLINE")
    label:SetTextColor(color[1], color[2], color[3])
    label:SetText(text)
    label:SetJustifyH("LEFT")
    return label
end

local function Rule(parent, x, y, width, alpha)
    local line = Fill(parent, "ARTWORK", GOLD[1], GOLD[2], GOLD[3], alpha)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    line:SetSize(width, 1)
end

local function CreateSlot(parent, index, left)
    local slot = S.CreateFrame("Frame", nil, parent)
    slot:SetPoint("TOPLEFT", parent, "TOPLEFT", left and 68 or 1540, (left and -224 or -336) - (index - 1) * 77)
    slot:SetSize(418, 62)
    local border = Fill(slot, "BACKGROUND", .64, .51, .34, .75)
    border:SetSize(57, 57)
    border:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
    local inset = Fill(slot, "ARTWORK", .025, .029, .038, 1)
    inset:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -2)
    inset:SetSize(53, 53)
    local icon = S.CreateTexture(slot, nil, "OVERLAY")
    icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 4, -4)
    icon:SetSize(49, 49)
    icon:SetTexture(nil)
    icon:SetTexCoord(.07, .93, .07, .93)
    local name = Label(slot, 17, WHITE, "")
    name:SetPoint("TOPLEFT", slot, "TOPLEFT", 72, -8)
    name:SetWidth(330)
    name:SetWordWrap(false)
    local caption = Label(slot, 12, MUTED, "")
    caption:SetPoint("TOPLEFT", slot, "TOPLEFT", 73, -35)
    return icon, name, caption
end

-- Blizzard's character sheet setup and the NonInteractableModelSceneMixinTemplate
-- both come with SharedXML; clients without the setup keep the portrait.
local function CreateModel(stage)
    if type(ModelSceneUtil) ~= "table" or type(ModelSceneUtil.SetUpCharacterSheetScene) ~= "function" then
        return nil
    end
    local model = S.CreateFrame("ModelScene", nil, stage, "NonInteractableModelSceneMixinTemplate")
    model:SetPoint("TOPLEFT", stage, "TOPLEFT", 575, -34)
    model:SetSize(900, 1020)
    model:EnableMouse(false)
    return model
end

local function Create(self)
    if self.host then return end
    -- Keep the AFK scene outside UIParent so the regular UI can fade away.
    local host = S.CreateFrame("Frame", "MSUFSuiteAFKScreen", WorldFrame or UIParent)
    host:SetAllPoints(UIParent)
    host:SetFrameStrata("TOOLTIP")
    host:SetFrameLevel(1000)
    host:EnableMouse(false)
    local shade = Fill(host, "BACKGROUND", .009, .014, .023, .68)
    shade:SetAllPoints(host)

    local panel = S.CreateFrame("Frame", nil, host)
    panel:SetPoint("CENTER", host, "CENTER", 0, 0)
    panel:SetSize(2040, 1120)
    panel:EnableMouse(false)

    -- Equipment and text need a quiet surface even when the camera faces a busy town.
    local leftBackdrop = Fill(panel, "BACKGROUND", .004, .008, .014, .92)
    leftBackdrop:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    leftBackdrop:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    leftBackdrop:SetWidth(530)
    local rightBackdrop = Fill(panel, "BACKGROUND", .004, .008, .014, .92)
    rightBackdrop:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    rightBackdrop:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    rightBackdrop:SetWidth(540)

    local stage = S.CreateFrame("Frame", nil, panel)
    stage:SetAllPoints(panel)
    stage:EnableMouse(false)
    local model = CreateModel(stage)
    local fallback = S.CreateTexture(stage, nil, "ARTWORK")
    fallback:SetPoint("CENTER", stage, "CENTER", 0, -10)
    fallback:SetSize(160, 160)
    fallback:SetTexture(EMPTY_ICON)
    local fallbackNote = Label(stage, 19, MUTED, "CHARACTER PREVIEW")
    fallbackNote:SetPoint("CENTER", stage, "CENTER", 0, -115)
    local icons, itemNames, captions = {}, {}, {}
    for n = 1, #SLOTS do
        icons[n], itemNames[n], captions[n] = CreateSlot(stage, n <= 9 and n or n - 9, n <= 9)
    end

    local brand = Label(panel, 16, GOLD, "MSUF  /  SUITE")
    brand:SetPoint("TOPLEFT", panel, "TOPLEFT", 68, -52)
    local name = Label(panel, 48, WHITE, "")
    name:SetPoint("TOPLEFT", panel, "TOPLEFT", 62, -86)
    name:SetWidth(425)
    name:SetWordWrap(false)
    local class = Label(panel, 20, GOLD, "")
    class:SetPoint("TOPLEFT", panel, "TOPLEFT", 68, -152)
    class:SetWidth(415)
    class:SetWordWrap(false)
    Rule(panel, 68, -203, 414, .72)

    local afk = Label(panel, 92, WHITE, "AFK")
    afk:SetPoint("TOPLEFT", panel, "TOPLEFT", 1532, -48)
    local subtitle = Label(panel, 20, GOLD, "AWAY FROM KEYBOARD")
    subtitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 1540, -168)
    local zoneLabel = Label(panel, 13, MUTED, "CURRENT LOCATION")
    zoneLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 1540, -222)
    local zone = Label(panel, 23, WHITE, "")
    zone:SetPoint("TOPLEFT", panel, "TOPLEFT", 1538, -245)
    zone:SetWidth(424)
    zone:SetWordWrap(false)
    Rule(panel, 1540, -314, 418, .72)

    local hint = Label(panel, 18, MUTED, "MOVE OR USE /AFK TO RETURN")
    hint:SetPoint("BOTTOM", panel, "BOTTOM", 0, 30)

    self.host, self.panel, self.model = host, panel, model
    self.fallback, self.fallbackNote, self.icons = fallback, fallbackNote, icons
    self.itemNames, self.captions = itemNames, captions
    self.name, self.class, self.zone = name, class, zone
    host:Hide()
end

-- The portrait stays visible until the 3D actor has loaded.
local function RefreshPortrait(self)
    self.fallback:SetTexture(EMPTY_ICON)
    self.fallback:SetTexCoord(0, 1, 0, 1)
    if type(SetPortraitTexture) == "function" then SetPortraitTexture(self.fallback, "player") end
end

local function CheckModel(self, actor)
    if not self.host or not self.host:IsShown() or actor ~= self.modelActor then return end
    local fileID = actor:GetModelFileID()
    if S.Public(fileID) and type(fileID) == "number" and fileID > 0 then
        self.fallback:Hide()
        self.fallbackNote:Hide()
    end
end

-- Blizzard's sheet setup may pick a separate animal-form actor for a druid in
-- flight or travel form; that actor is used when it is the only one.
local function FormActor(model)
    if type(GetShapeshiftFormID) ~= "function" or type(ANIMAL_FORMS) ~= "table" then return nil end
    local form = GetShapeshiftFormID()
    if not S.Public(form) or type(form) ~= "number" then return nil end
    local formData = ANIMAL_FORMS[form]
    local tag = formData and formData.actorTag
    if type(tag) ~= "string" then return nil end
    return model:GetPlayerActor(tag)
end

local function SceneActor(model)
    local actor = model:GetPlayerActor()
    local formActor = FormActor(model)
    actor = actor or formActor
    if not actor and type(model.EnumerateActiveActors) == "function" then
        local iterator, state, initial = model:EnumerateActiveActors()
        if type(iterator) == "function" then actor = iterator(state, initial) end
    end
    return actor, formActor
end

local function RefreshModel(self)
    self.fallback:Show()
    self.fallbackNote:Show()
    local model = self.model
    if not model then return end
    ModelSceneUtil.SetUpCharacterSheetScene(model)
    local actor, formActor = SceneActor(model)
    if not actor then return end
    -- Show the equipped character: dress the available actor from the
    -- player's native model and clear a separate animal-form actor.
    if formActor and formActor ~= actor and type(formActor.ClearModel) == "function" then formActor:ClearModel() end
    if type(actor.UseUnitSheatheCategory) == "function" then actor:UseUnitSheatheCategory(true) end
    if type(actor.SetModelByUnit) == "function" then actor:SetModelByUnit("player", true, true, false, true) end
    if actor ~= self.modelActor and type(actor.HookScript) == "function" then
        actor:HookScript("OnModelLoaded", function() CheckModel(self, actor) end)
    end
    self.modelActor = actor
    CheckModel(self, actor)
end

local function RefreshEquipment(self)
    local getTexture = type(GetInventoryItemTexture) == "function" and GetInventoryItemTexture
    local getLink = type(GetInventoryItemLink) == "function" and GetInventoryItemLink
    for index, slot in ipairs(SLOTS) do
        local texture = getTexture and getTexture("player", slot)
        local usable = S.Public(texture) and (type(texture) == "number" or type(texture) == "string")
        self.icons[index]:SetTexture(usable and texture or nil)
        local itemName
        local red, green, blue = WHITE[1], WHITE[2], WHITE[3]
        local link = getLink and PublicText(getLink("player", slot))
        if link then
            itemName = link:match("|h%[(.-)%]|h")
            local r, g, b = link:match("^|cff(%x%x)(%x%x)(%x%x)")
            if r then red, green, blue = tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 end
        end
        self.itemNames[index]:SetText(itemName or SLOT_NAMES[index])
        self.itemNames[index]:SetTextColor(red, green, blue)
        self.captions[index]:SetText(itemName and SLOT_NAMES[index] or "")
    end
end

local function StartCamera(self)
    if self.cameraSpinning or type(MoveViewLeftStart) ~= "function" then return end
    MoveViewLeftStart(.035)
    self.cameraSpinning = true
end

local function StopCamera(self)
    if not self.cameraSpinning or type(MoveViewLeftStop) ~= "function" then return end
    MoveViewLeftStop()
    self.cameraSpinning = false
end

local function FadeUI(self)
    if self.uiAlpha ~= nil or not WorldFrame then return end
    if type(UIParent.GetAlpha) ~= "function" or type(UIParent.SetAlpha) ~= "function" then return end
    local alpha = UIParent:GetAlpha()
    if not S.Public(alpha) or type(alpha) ~= "number" then return end
    UIParent:SetAlpha(0)
    self.uiAlpha = alpha
end

local function RestoreUI(self)
    if self.uiAlpha == nil then return end
    local current = UIParent:GetAlpha()
    if S.Public(current) and type(current) == "number" and current ~= 0 then
        -- Another addon changed the UI while AFK; keep its newer value.
        self.uiAlpha = nil
        return
    end
    UIParent:SetAlpha(self.uiAlpha)
    self.uiAlpha = nil
end

local function HideMinimap(self)
    -- Native POI markers ignore alpha fading, so hide their drawing widget.
    if self.minimapWasShown or not Minimap then return end
    if type(Minimap.IsShown) ~= "function" or type(Minimap.Hide) ~= "function" then return end
    local shown = Minimap:IsShown()
    if S.Public(shown) and shown == true then
        Minimap:Hide()
        self.minimapWasShown = true
    end
end

local function RestoreMinimap(self)
    if not self.minimapWasShown or not Minimap then return end
    local shown = Minimap:IsShown()
    if not S.Public(shown) then return end
    if shown == false then
        if type(Minimap.Show) ~= "function" then return end
        Minimap:Show()
    end
    -- Shown again by someone else, or by us: either way it is not ours anymore.
    self.minimapWasShown = nil
end

local function Hide(self)
    StopCamera(self)
    if self.model then self.model:Hide() end
    if self.host then self.host:Hide() end
    RestoreMinimap(self)
    RestoreUI(self)
end

local function CombatActive()
    if type(InCombatLockdown) ~= "function" then return false end
    local value = InCombatLockdown()
    -- An unreadable combat state must never open the AFK scene.
    return not S.Public(value) or value ~= false
end

local OnEvent

-- The status events fire often in groups; they are registered only outside
-- combat, and unit flags only for the player.
local function StartStatusEvents(self)
    self.context:Event("PLAYER_FLAGS_CHANGED", OnEvent, true)
    self.context:Event("UNIT_FLAGS", OnEvent, true, "player")
end

local function EnterCombat(self)
    if self.inCombat then return end
    self.inCombat = true
    self.recheckToken = (self.recheckToken or 0) + 1
    self.recheckScheduled = false
    self.context:RemoveEvent("PLAYER_FLAGS_CHANGED")
    self.context:RemoveEvent("UNIT_FLAGS")
    Hide(self)
end

local function PanelScale(self)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return nil end
    local scale = math.min(1, width / 2120, height / 1180)
    -- The host lives under WorldFrame; keep the UIParent visual scale.
    if WorldFrame and type(UIParent.GetEffectiveScale) == "function"
        and type(self.host.GetEffectiveScale) == "function" then
        local uiScale, hostScale = UIParent:GetEffectiveScale(), self.host:GetEffectiveScale()
        if type(uiScale) == "number" and type(hostScale) == "number" and hostScale > 0 then
            scale = scale * uiScale / hostScale
        end
    end
    return scale
end

local function Show(self)
    Create(self)
    self.name:SetText(ReadText(UnitName, "player") or "ADVENTURER")
    local class = ReadText(UnitClass, "player") or ""
    local level = type(UnitLevel) == "function" and UnitLevel("player")
    if S.Public(level) and type(level) == "number" and level > 0 then
        class = "LEVEL " .. level .. (class ~= "" and "  /  " .. class or "")
    end
    self.class:SetText(class)
    self.zone:SetText(ReadText(GetZoneText) or "")
    RefreshPortrait(self)
    RefreshEquipment(self)
    local scale = PanelScale(self)
    if scale then self.panel:SetScale(scale) end
    self.host:Show()
    if self.model then self.model:Show() end
    FadeUI(self)
    HideMinimap(self)
    RefreshModel(self)
    StartCamera(self)
end

local Update

local function ScheduleRecheck(self)
    if self.recheckScheduled or not C_Timer or type(C_Timer.After) ~= "function" then return end
    self.recheckScheduled = true
    local token = self.recheckToken or 0
    C_Timer.After(0, function()
        if token ~= (self.recheckToken or 0) then return end
        self.recheckScheduled = false
        if self.active and not self.inCombat then Update(self, true) end
    end)
end

Update = function(self, deferred)
    if self.inCombat then return end
    if CombatActive() then
        EnterCombat(self)
        return
    end
    if type(UnitIsAFK) ~= "function" then return end
    local value = UnitIsAFK("player")
    -- Chat lockdown after /afk can make the result secret. Keep the last
    -- visible state and retry once after the command has finished.
    if not S.Public(value) or type(value) ~= "boolean" then
        if not deferred then ScheduleRecheck(self) end
        return
    end
    if value then
        if not self.host or not self.host:IsShown() then Show(self) end
        StartCamera(self)
    else
        Hide(self)
    end
end

OnEvent = function(self, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        EnterCombat(self)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
        self.inCombat = false
        StopCamera(self)
        RestoreMinimap(self)
        RestoreUI(self)
        if CombatActive() then
            EnterCombat(self)
            return
        end
        StartStatusEvents(self)
        Update(self)
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then
        Hide(self)
        return
    end
    if self.inCombat then return end
    if event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_FLAGS" then
        if not S.Public(unit) then
            Update(self)
            return
        end
        if unit ~= nil and unit ~= "player" then return end
    end
    Update(self)
end

function M:Enable()
    self.inCombat = false
    self.context:Event("PLAYER_ENTERING_WORLD", OnEvent, true)
    self.context:Event("PLAYER_LEAVING_WORLD", OnEvent, true)
    self.context:Event("PLAYER_REGEN_DISABLED", OnEvent, true)
    self.context:Event("PLAYER_REGEN_ENABLED", OnEvent, true)
    if CombatActive() then
        EnterCombat(self)
        return
    end
    StartStatusEvents(self)
    Update(self)
end

function M:Refresh()
    Update(self)
end

function M:Disable()
    self.recheckToken = (self.recheckToken or 0) + 1
    self.recheckScheduled = false
    Hide(self)
end

S.Install(ID, M)

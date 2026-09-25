local _, P = ...
local S = P.Suite
local ID = "afkScreen"
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

local function SafeText(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    return ok and PublicText(value) or nil
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
    slot:SetPoint("TOPLEFT", parent, "TOPLEFT", left and 68 or 1540,
        (left and -224 or -336) - (index - 1) * 77)
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
    local model
    if type(ModelSceneUtil) == "table" and type(ModelSceneUtil.SetUpCharacterSheetScene) == "function" then
        local ok, scene = pcall(S.CreateFrame, "ModelScene", nil, stage, "NonInteractableModelSceneMixinTemplate")
        if ok and scene then
            model = scene
            model:SetPoint("TOPLEFT", stage, "TOPLEFT", 575, -34)
            model:SetSize(900, 1020)
            model:EnableMouse(false)
        end
    end
    local fallback = S.CreateTexture(stage, nil, "ARTWORK")
    fallback:SetPoint("CENTER", stage, "CENTER", 0, -10)
    fallback:SetSize(160, 160)
    fallback:SetTexture(EMPTY_ICON)
    local fallbackNote = Label(stage, 19, MUTED, "CHARACTER PREVIEW")
    fallbackNote:SetPoint("CENTER", stage, "CENTER", 0, -115)
    local icons, itemNames, captions = {}, {}, {}
    for n = 1, #SLOTS do
        icons[n], itemNames[n], captions[n] = CreateSlot(stage,
            n <= 9 and n or n - 9, n <= 9)
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

local function RefreshPortrait(self)
    local ok, result = false, nil
    if type(SetPortraitTexture) == "function" then
        ok, result = pcall(SetPortraitTexture, self.fallback, "player")
    end
    if not ok or result == false then
        self.fallback:SetTexture(EMPTY_ICON)
        self.fallback:SetTexCoord(0, 1, 0, 1)
    end
end

local function CheckModel(self, actor)
    if not self.host or not self.host:IsShown() or actor ~= self.modelActor then return end
    local ok, fileID = pcall(actor.GetModelFileID, actor)
    if ok and S.Public(fileID) and type(fileID) == "number" and fileID > 0 then
        self.fallback:Hide()
        self.fallbackNote:Hide()
    end
end

local function RefreshModel(self)
    self.fallback:Show()
    self.fallbackNote:Show()
    if not self.model then return end
    local ok = pcall(ModelSceneUtil.SetUpCharacterSheetScene, self.model)
    if not ok then return end
    local actor
    if type(self.model.GetPlayerActor) == "function" then
        local actorOK, result = pcall(self.model.GetPlayerActor, self.model)
        if actorOK then actor = result end
    end
    local formActor
    if type(GetShapeshiftFormID) == "function" and type(ANIMAL_FORMS) == "table"
        and type(self.model.GetPlayerActor) == "function" then
        local formOK, form = pcall(GetShapeshiftFormID)
        if formOK and S.Public(form) and type(form) == "number" then
            local formData = ANIMAL_FORMS[form]
            local tag = formData and formData.actorTag
            if type(tag) == "string" then
                local actorOK, result = pcall(self.model.GetPlayerActor, self.model, tag)
                if actorOK then formActor = result end
            end
        end
    end
    actor = actor or formActor
    if not actor and type(self.model.EnumerateActiveActors) == "function" then
        local actorsOK, iterator, state, initial = pcall(self.model.EnumerateActiveActors, self.model)
        if actorsOK and type(iterator) == "function" then
            local iterateOK, result = pcall(iterator, state, initial)
            if iterateOK then actor = result end
        end
    end
    if not actor then return end
    -- A druid in flight or travel form should still show their equipped character.
    -- Blizzard's sheet setup may select a separate animal-form actor, so dress
    -- the available actor from the player's native model instead.
    if formActor and formActor ~= actor and type(formActor.ClearModel) == "function" then
        pcall(formActor.ClearModel, formActor)
    end
    if type(actor.UseUnitSheatheCategory) == "function" then
        pcall(actor.UseUnitSheatheCategory, actor, true)
    end
    if type(actor.SetModelByUnit) == "function" then
        pcall(actor.SetModelByUnit, actor, "player", true, true, false, true)
    end
    if actor ~= self.modelActor and type(actor.HookScript) == "function" then
        self.modelActor = actor
        pcall(actor.HookScript, actor, "OnModelLoaded", function() CheckModel(self, actor) end)
    end
    self.modelActor = actor
    CheckModel(self, actor)
end

local function RefreshEquipment(self)
    for index, slot in ipairs(SLOTS) do
        local ok, texture = false, nil
        if type(GetInventoryItemTexture) == "function" then
            ok, texture = pcall(GetInventoryItemTexture, "player", slot)
        end
        local usable = ok and S.Public(texture) and (type(texture) == "number" or type(texture) == "string")
        self.icons[index]:SetTexture(usable and texture or nil)
        local itemName
        local red, green, blue = WHITE[1], WHITE[2], WHITE[3]
        if type(GetInventoryItemLink) == "function" then
            local linkOK, link = pcall(GetInventoryItemLink, "player", slot)
            if linkOK and PublicText(link) then
                itemName = link:match("|h%[(.-)%]|h")
                local r, g, b = link:match("^|cff(%x%x)(%x%x)(%x%x)")
                if r then
                    red, green, blue = tonumber(r, 16) / 255,
                        tonumber(g, 16) / 255, tonumber(b, 16) / 255
                end
            end
        end
        self.itemNames[index]:SetText(itemName or SLOT_NAMES[index])
        self.itemNames[index]:SetTextColor(red, green, blue)
        self.captions[index]:SetText(itemName and SLOT_NAMES[index] or "")
    end
end

local function StartCamera(self)
    if self.cameraSpinning or type(MoveViewLeftStart) ~= "function" then return end
    local ok = pcall(MoveViewLeftStart, .035)
    if ok then self.cameraSpinning = true end
end

local function StopCamera(self)
    if not self.cameraSpinning then return end
    if type(MoveViewLeftStop) == "function" and pcall(MoveViewLeftStop) then
        self.cameraSpinning = false
    end
end

local function FadeUI(self)
    if self.uiAlpha ~= nil or not WorldFrame then return end
    if type(UIParent.GetAlpha) ~= "function" or type(UIParent.SetAlpha) ~= "function" then return end
    local ok, alpha = pcall(UIParent.GetAlpha, UIParent)
    if not ok or type(alpha) ~= "number" then return end
    if pcall(UIParent.SetAlpha, UIParent, 0) then self.uiAlpha = alpha end
end

local function RestoreUI(self)
    if self.uiAlpha == nil then return end
    local currentOK, current = pcall(UIParent.GetAlpha, UIParent)
    if currentOK and type(current) == "number" and current ~= 0 then
        -- Another addon changed the UI while AFK; keep its newer value.
        self.uiAlpha = nil
        return
    end
    local alpha = self.uiAlpha
    if pcall(UIParent.SetAlpha, UIParent, alpha) then self.uiAlpha = nil end
end

local function HideMinimap(self)
    -- Native POI markers ignore alpha fading, so hide their drawing widget.
    if self.minimapWasShown or not Minimap then return end
    if type(Minimap.IsShown) ~= "function" or type(Minimap.Hide) ~= "function" then return end
    local ok, shown = pcall(Minimap.IsShown, Minimap)
    if ok and S.Public(shown) and shown == true and pcall(Minimap.Hide, Minimap) then
        self.minimapWasShown = true
    end
end

local function RestoreMinimap(self)
    if not self.minimapWasShown or not Minimap then return end
    local ok, shown = pcall(Minimap.IsShown, Minimap)
    if ok and S.Public(shown) and shown == true then
        self.minimapWasShown = nil
        return
    end
    if ok and S.Public(shown) and shown == false
        and type(Minimap.Show) == "function" and pcall(Minimap.Show, Minimap) then
        self.minimapWasShown = nil
    end
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
    local ok, value = pcall(InCombatLockdown)
    -- An unreadable combat state must never open the AFK scene.
    return not ok or not S.Public(value) or value ~= false
end

local OnEvent

local function StartStatusEvents(self)
    self.context:Event("PLAYER_FLAGS_CHANGED", OnEvent, true)
    self.context:Event("UNIT_FLAGS", OnEvent, true)
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

local function Show(self)
    Create(self)
    self.name:SetText(SafeText(UnitName, "player") or "ADVENTURER")
    local class = SafeText(UnitClass, "player") or ""
    local levelOK, level = false, nil
    if type(UnitLevel) == "function" then
        levelOK, level = pcall(UnitLevel, "player")
    end
    if levelOK and S.Public(level) and type(level) == "number" and level > 0 then
        class = "LEVEL " .. level .. (class ~= "" and "  /  " .. class or "")
    end
    self.class:SetText(class)
    self.zone:SetText(SafeText(GetZoneText) or "")
    RefreshPortrait(self)
    RefreshEquipment(self)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        local scale = math.min(1, width / 2120, height / 1180)
        if WorldFrame and type(UIParent.GetEffectiveScale) == "function"
            and type(self.host.GetEffectiveScale) == "function" then
            local uiOK, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
            local hostOK, hostScale = pcall(self.host.GetEffectiveScale, self.host)
            if uiOK and hostOK and type(uiScale) == "number"
                and type(hostScale) == "number" and hostScale > 0 then
                scale = scale * uiScale / hostScale
            end
        end
        self.panel:SetScale(scale)
    end
    self.host:Show()
    if self.model then self.model:Show() end
    FadeUI(self)
    HideMinimap(self)
    RefreshModel(self)
    StartCamera(self)
end

local function Update(self, deferred)
    if self.inCombat then return end
    if CombatActive() then EnterCombat(self); return end
    if type(UnitIsAFK) ~= "function" then return end
    local ok, value = pcall(UnitIsAFK, "player")
    -- Chat lockdown after /afk can make the result secret. Keep the last
    -- visible state and retry once after the command has finished.
    if not ok or not S.Public(value) or type(value) ~= "boolean" then
        if not deferred and not self.recheckScheduled and C_Timer and type(C_Timer.After) == "function" then
            self.recheckScheduled = true
            local token = self.recheckToken or 0
            C_Timer.After(0, function()
                if token ~= (self.recheckToken or 0) then return end
                self.recheckScheduled = false
                if self.active and not self.inCombat then Update(self, true) end
            end)
        end
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
    if event == "PLAYER_REGEN_DISABLED" then EnterCombat(self); return end
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
        self.inCombat = false
        StopCamera(self)
        RestoreMinimap(self)
        RestoreUI(self)
        if CombatActive() then EnterCombat(self); return end
        StartStatusEvents(self)
        Update(self)
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then Hide(self); return end
    if self.inCombat then return end
    if event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_FLAGS" then
        if not S.Public(unit) then Update(self); return end
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
    if CombatActive() then EnterCombat(self); return end
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

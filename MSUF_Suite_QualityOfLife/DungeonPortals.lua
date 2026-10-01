local _, P = ...
local NS, S = P.NS, P.Suite
if NS.Client.isForever then return end
local ID, M = "dungeonPortals", { buttons = {} }
local Public, Finite, Text = S.Public, S.Finite, S.PublicText
-- Public spell records identify these dungeon teleport flyouts. The client
-- supplies their complete learned contents, localized labels and spell data.
-- Source: nether.wowhead.com/tooltip/spell/<id>, verified 2026-09-30.
local SEEDS = { [131204] = true, [159898] = true, [354464] = true,
    [393273] = true, [410071] = true, [410078] = true, [410080] = true,
    [424142] = true, [424153] = true, [424163] = true, [424167] = true,
    [445269] = true, [445418] = true, [1254400] = true, [1254572] = true,
    [1254555] = true, [1254551] = true }

-- Destination facts verified against public spell tooltips and Raider.IO
-- /api/v1/mythic-plus/static-data. Native GetMapUIInfo resolves game map IDs.
local CHALLENGES = {
    [159896] = 169, -- Iron Docks
    [159898] = 161, -- Skyreach
    [159899] = 165, -- Shadowmoon Burial Grounds
    [159900] = 166, -- Grimrail Depot
    [159901] = 168, -- The Everbloom
    [354462] = 376, -- The Necrotic Wake
    [354463] = 379, -- Plaguefall
    [354464] = 375, -- Mists of Tirna Scithe
    [354465] = 378, -- Halls of Atonement
    [354466] = 381, -- Spires of Ascension
    [354467] = 382, -- Theater of Pain
    [354468] = 377, -- De Other Side
    [354469] = 380, -- Sanguine Depths
    [393256] = 399, -- Ruby Life Pools
    [393262] = 400, -- The Nokhud Offensive
    [393267] = 405, -- Brackenhide Hollow
    [393273] = 402, -- Algeth'ar Academy
    [393276] = 404, -- Neltharus
    [393279] = 401, -- The Azure Vault
    [393283] = 406, -- Halls of Infusion
    [393222] = 403, -- Uldaman: Legacy of Tyr
    [410071] = 245, -- Freehold
    [410078] = 206, -- Neltharion's Lair
    [410080] = 438, -- The Vortex Pinnacle
    [424142] = 456, -- Throne of the Tides
    [424153] = 199, -- Black Rook Hold
    [424163] = 198, -- Darkheart Thicket
    [424167] = 248, -- Waycrest Manor
    [445269] = 501, -- The Stonevault
    [445418] = 353, -- Siege of Boralus
    [445416] = 502, -- City of Threads
    [445414] = 505, -- The Dawnbreaker
    [445424] = 507, -- Grim Batol
    [445443] = 500, -- The Rookery
    [445444] = 499, -- Priory of the Sacred Flame
    [445440] = 506, -- Cinderbrew Meadery
    [445441] = 504, -- Darkflame Cleft
    [1254400] = 557, -- Windrunner Spire
    [1254572] = 558, -- Magisters' Terrace
    [1254555] = 556, -- Pit of Saron
    [1254551] = 239, -- Seat of the Triumvirate
    [1254557] = 161, -- Skyreach
    [1254559] = 560, -- Maisara Caverns
    [1254563] = 559, -- Nexus-Point Xenas
    [1286801] = 584, -- The Blinding Vale
    [1286804] = 585, -- Voidscar Arena
    [1286807] = 586, -- Den of Nalorakk
    [1286809] = 587, -- Murder Row
    [1286812] = 588, -- Altar of Fangs
    [1286828] = 250, -- Temple of Sethraliss
    [1286831] = 249, -- Kings' Rest
}
for spell in pairs(CHALLENGES) do SEEDS[spell] = true end

local function Field(data, key)
    if Public(data) and type(data) == "table" and Public(data[key]) then return data[key] end
end

local function AddSpell(spells, spellID)
    if not Finite(spellID) or spells[spellID] then return end
    local known = C_SpellBook.IsSpellKnown(spellID)
    if not Public(known) or known ~= true then return end
    local info = C_Spell.GetSpellInfo(spellID)
    local name = Text(Field(info, "name"))
    if not name then return end
    local destination, mapID
    if CHALLENGES[spellID] then
        local dungeon, _, _, _, _, gameMap = C_ChallengeMode.GetMapUIInfo(CHALLENGES[spellID])
        destination = Text(dungeon)
        if Finite(gameMap) and gameMap > 0 then mapID = gameMap end
    end
    spells[spellID] = { id = spellID, name = name, icon = Field(info, "iconID"), mapID = mapID,
        destination = destination or Text(C_Spell.GetSpellSubtext(spellID)) }
end

local function ReadFlyout(spells, id)
    if not Finite(id) then return end
    local _, _, count = GetFlyoutInfo(id)
    if not Finite(count) or count < 1 or count > 100 then return end
    local slots, recognized = {}, false
    for i = 1, count do
        local spell, override = GetFlyoutSlotInfo(id, i)
        if Finite(spell) then
            recognized = recognized or SEEDS[spell] == true
            slots[#slots + 1] = Finite(override) and override > 0 and override or spell
        end
    end
    if recognized then for _, spell in ipairs(slots) do AddSpell(spells, spell) end end
end

local function LearnedPortals()
    local spells = {}
    for spell in pairs(SEEDS) do AddSpell(spells, spell) end
    local lines = C_SpellBook.GetNumSpellBookSkillLines()
    if Finite(lines) then
        for i = 1, math.min(lines, 20) do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            local offset, count = Field(line, "itemIndexOffset"), Field(line, "numSpellBookItems")
            if Finite(offset) and Finite(count) then
                for slot = offset + 1, offset + math.min(count, 500) do
                    local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
                    if Field(item, "itemType") == Enum.SpellBookItemType.Flyout then ReadFlyout(spells, Field(item, "actionID")) end
                end
            end
        end
    end
    local ordered = {}
    for _, spell in pairs(spells) do ordered[#ordered + 1] = spell end
    table.sort(ordered, function(a, b) return a.name < b.name end)
    return ordered
end

-- The Suite's portal menu (DataTexts) reads the list this module keeps
-- current through SPELLS_CHANGED; a switched-off module scans on request.
function S.LearnedDungeonPortals()
    if M.active and M.spells and not M.dirty then return M.spells end
    return LearnedPortals()
end

local function Tooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetSpellByID(button.spellID)
    GameTooltip:Show()
end

local function SpellButton(self, parent)
    local button = S.CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button:SetAttribute("type", "spell"); button:SetAttribute("useOnKeyDown", false)
    button:RegisterForClicks("AnyUp")
    button.icon = S.CreateTexture(button, nil, "ARTWORK"); button.icon:SetAllPoints()
    button.cooldown = S.CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    button.cooldown:SetDrawEdge(false)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function SetCooldown(button)
    local duration = C_Spell.GetSpellCooldownDuration(button.spellID)
    if Public(duration) and duration == nil then button.cooldown:Clear()
    else button.cooldown:SetCooldownFromDurationObject(duration) end
end

local function Cooldowns(self)
    if not self.active then return end
    if self.flyout:IsVisible() then
        for _, button in ipairs(self.buttons) do
            if button.spellID and button:IsShown() then SetCooldown(button) end
        end
    end
    if self.popup and self.popup:IsVisible() then SetCooldown(self.popup.cast) end
end

-- Cooldown updates (every global cooldown in combat) are read only while the
-- flyout or the suggestion is on screen.
local function WatchCooldowns(self)
    local open = self.flyout:IsVisible() or self.popup and self.popup:IsVisible()
    if open and self.active then
        self.context:Event("SPELL_UPDATE_COOLDOWN", Cooldowns, true)
        Cooldowns(self)
    else
        self.context:RemoveEvent("SPELL_UPDATE_COOLDOWN")
    end
end

-- The toggle belongs to a protected family (secure handler templates), so it
-- never anchors to Minimap, which other addons move and resize: a Suite proxy
-- copies the minimap's bottom-right corner, and a separate watcher anchored to
-- Minimap reports moves. The proxy moves only outside combat.
local function CopyMinimap(self)
    if NS.IsCombatLocked() then self.placePending = true; return end
    self.placePending = nil
    local right, bottom = Minimap:GetRight(), Minimap:GetBottom()
    local scale, own = Minimap:GetEffectiveScale(), self.proxy:GetEffectiveScale()
    if not (Finite(right) and Finite(bottom) and Finite(scale) and Finite(own) and own > 0) then return end
    self.proxy:ClearAllPoints()
    self.proxy:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", right * scale / own, bottom * scale / own)
end

local function Create(self)
    if self.host then return end
    self.host = S.CreateFrame("Frame", "MSUFSuiteDungeonPortalOwner", UIParent, "SecureHandlerStateTemplate")
    self.host:SetAllPoints(UIParent)
    self.proxy = S.CreateFrame("Frame", nil, UIParent)
    self.proxy:SetSize(1, 1)
    local watcher = S.CreateFrame("Frame", nil, UIParent)
    self.watcher = watcher
    watcher:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT")
    watcher:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT")
    watcher:SetScript("OnSizeChanged", function() if self.active then CopyMinimap(self) end end)
    -- The bottom-right corner keeps clear of the expansion landing button.
    local toggle = S.CreateFrame("Button", "MSUFSuiteDungeonPortalButton", self.host, "SecureHandlerClickTemplate")
    toggle:SetSize(26, 26); toggle:SetPoint("BOTTOMRIGHT", self.proxy, "BOTTOMRIGHT", 0, 0)
    local icon = S.CreateTexture(toggle, nil, "ARTWORK"); icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_TeleportStormWind")
    local flyout = S.CreateFrame("Frame", nil, self.host, "SecureHandlerBaseTemplate")
    flyout:SetPoint("TOPRIGHT", toggle, "BOTTOMRIGHT", 0, -5)
    flyout:SetClampedToScreen(true)
    local back = S.CreateTexture(flyout, nil, "BACKGROUND"); back:SetAllPoints(); back:SetColorTexture(.04, .05, .07, .96)
    flyout:Hide()
    flyout:SetScript("OnShow", function() WatchCooldowns(self) end)
    flyout:SetScript("OnHide", function() WatchCooldowns(self) end)
    toggle:SetFrameRef("flyout", flyout)
    toggle:SetAttribute("_onclick", [[local f = self:GetFrameRef("flyout"); if f:IsShown() then f:Hide() else f:Show() end]])
    toggle:SetScript("OnEnter", function()
        GameTooltip:SetOwner(toggle, "ANCHOR_LEFT"); GameTooltip:SetText(S.Text("Dungeon portals")); GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.toggle, self.flyout = toggle, flyout
end

local function Popup(self, spell)
    if not self.popup then
        local frame = S.CreateFrame("Frame", nil, self.host, "SecureHandlerBaseTemplate")
        frame:SetSize(300, 74); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 170)
        local back = S.CreateTexture(frame, nil, "BACKGROUND"); back:SetAllPoints(); back:SetColorTexture(.04, .05, .07, .96)
        frame.cast = SpellButton(self, frame); frame.cast:SetSize(42, 42); frame.cast:SetPoint("LEFT", 12, 0)
        frame.label = S.CreateFontString(frame, nil, "OVERLAY")
        frame.label:SetPoint("LEFT", frame.cast, "RIGHT", 10, 0); frame.label:SetWidth(204)
        S.SetStyledFont(frame.label, S.GlobalFontPath(), 13, "OUTLINE", 1, true, 70, 1)
        local close = S.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0); close:SetScript("OnClick", function() frame:Hide() end)
        frame:Hide()
        frame:SetScript("OnShow", function() WatchCooldowns(self) end)
        frame:SetScript("OnHide", function() WatchCooldowns(self) end)
        self.popup = frame
    end
    self.popup.cast.spellID = spell.id
    self.popup.cast:SetAttribute("spell", spell.id); self.popup.cast.icon:SetTexture(spell.icon)
    self.popup.label:SetText(spell.destination or spell.name)
    self.popup:SetScale((self.config.popupScale or 100) / 100)
    if self.popup:IsShown() then Cooldowns(self) else self.popup:Show() end
end

local function Joined(self, _, resultID)
    if not self.config.joinPopup or NS.IsCombatLocked() or not Finite(resultID) then return end
    local inside = IsInInstance()
    if not Public(inside) or inside == true then return end
    local result = C_LFGList.GetSearchResultInfo(resultID)
    local activities = Field(result, "activityIDs")
    if type(activities) ~= "table" or #activities ~= 1 or not Finite(activities[1]) then return end
    local activity = C_LFGList.GetActivityInfoTable(activities[1])
    if Field(activity, "categoryID") ~= 2 then return end
    local mapID = Field(activity, "mapID")
    local mapped
    if Finite(mapID) and mapID > 0 then
        for _, spell in ipairs(self.spells or {}) do
            if spell.mapID == mapID and (not mapped or spell.id > mapped.id) then mapped = spell end
        end
    end
    if mapped then Popup(self, mapped); return end
    local destination = Text(Field(activity, "shortName"))
    local matched
    for _, spell in ipairs(self.spells or {}) do
        -- Only exact localized destination matches qualify; no substring or
        -- inferred map-ID matching, and an ambiguous match shows no suggestion.
        if destination and spell.destination == destination then
            if matched then return end
            matched = spell
        end
    end
    if matched then Popup(self, matched) end
end

-- A spell-book change in combat only marks the list; it is read again once
-- after combat instead of after every pull.
local function State(self, event)
    if event == "PLAYER_REGEN_DISABLED" then self.clearPopup = true; return end
    if NS.IsCombatLocked() then
        if event == "SPELLS_CHANGED" then self.dirty = true end
        return
    end
    local grouped = IsInGroup()
    if self.popup and (self.clearPopup or event == "PLAYER_ENTERING_WORLD"
        or Public(grouped) and grouped == false) then self.popup:Hide() end
    self.clearPopup = nil
    if event == "SPELLS_CHANGED" or self.dirty then self:Refresh()
    elseif self.placePending then CopyMinimap(self) end
end

function M:Enable()
    Create(self)
    RegisterStateDriver(self.host, "visibility", "[combat] hide; show")
    for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE" }) do self.context:Event(event, State, true) end
    self.context:Event("LFG_LIST_JOINED_GROUP", Joined, true)
    self:Refresh()
end

function M:Refresh()
    if NS.IsCombatLocked() then self.dirty = true; return end
    Create(self)
    CopyMinimap(self)
    self.spells, self.dirty = LearnedPortals(), nil
    local count = math.min(#self.spells, 100)
    self.flyout:SetSize(6 * 36 + 8, math.max(1, math.ceil(count / 6)) * 36 + 8)
    self.flyout:SetScale((self.config.flyoutScale or 100) / 100)
    for i = 1, count do
        local spell = self.spells[i]
        local button = self.buttons[i] or SpellButton(self, self.flyout); self.buttons[i] = button
        button:SetSize(32, 32); button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 6 + ((i - 1) % 6) * 36, -6 - math.floor((i - 1) / 6) * 36)
        button.spellID = spell.id; button:SetAttribute("spell", spell.id)
        button.icon:SetTexture(spell.icon); button:Show()
    end
    for i = count + 1, #self.buttons do self.buttons[i]:Hide() end
    self.toggle:SetShown(self.config.showMinimap ~= false and count > 0)
    if self.config.showMinimap == false or count == 0 then self.flyout:Hide() end
    if self.popup and not self.config.joinPopup then self.popup:Hide() end
    WatchCooldowns(self)
end

-- The controller stops a module only outside combat lockdown (S.Apply).
function M:Disable()
    if self.host then
        UnregisterStateDriver(self.host, "visibility")
        self.host:Hide()
    end
end

S.Install(ID, M)

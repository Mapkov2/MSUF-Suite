local _, NS = ...
local Learning = {}
NS.SpellLearning = Learning
if not NS.Client.isForever then return end

local Safety = NS.Safety
local Public, Read = Safety.Public, Safety.Read
local ROWS, WIDTH, HEIGHT, ROW_HEIGHT = 10, 390, 420, 27
local OWNER = "spellLearning"
local SHELL = { role = "shell", inset = 0 }
local BUTTON = { role = "button", ownedArt = true }
local PRIMARY = { role = "buttonPrimary", pillHeight = 28, ownedArt = true }
local SEARCH = { role = "input", pillHeight = 25 }
local PLAYER_BANK = Enum.SpellBookSpellBank.Player
local SPELL_ITEM = Enum.SpellBookItemType.Spell
local SOURCE = { automatic = 0, trainer = 1, quest = 2, unconfirmed = 3, talent = 4, item = 5, portal = 6 }
local lastCombatNotice
local ROMAN_VALUES = { I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000 }

local function FamilyName(name, rank)
    local suffix = rank > 0 and name:match(" ([IVXLCDM]+)$")
    if not suffix then return name end
    local total, previous = 0, 0
    for index = #suffix, 1, -1 do
        local value = ROMAN_VALUES[suffix:sub(index, index)]
        total = total + (value < previous and -value or value)
        previous = math.max(previous, value)
    end
    return total == rank and name:sub(1, -#suffix - 2) or name
end

local function NoteRank(learned, name, rank)
    local family = FamilyName(name, rank)
    learned[family] = math.max(learned[family] or 0, rank)
end

local function LearnedRanks(panel, learned)
    local count = C_SpellBook.GetNumSpellBookSkillLines()
    if not Public(count) or type(count) ~= "number" then return learned end
    for line = 1, count do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if Public(info) and type(info) == "table" then
            local offset, items = info.itemIndexOffset, info.numSpellBookItems
            if Public(offset) and Public(items) and type(offset) == "number" and type(items) == "number" then
                for slot = offset + 1, offset + items do
                    local item = C_SpellBook.GetSpellBookItemInfo(slot, PLAYER_BANK)
                    if Public(item) and type(item) == "table" and Public(item.itemType) and item.itemType == SPELL_ITEM then
                        local id = item.spellID
                        if Public(id) and type(id) == "number" and id > 0 then panel.bookIDs[id] = true end
                        local name, subName = item.name, item.subName
                        if Public(name) and type(name) == "string" and name ~= "" and Public(subName) then
                            local rank = type(subName) == "string" and tonumber(subName:match("%d+"))
                            if not rank then
                                if Public(id) and type(id) == "number" then rank = panel.ranksByID[id] end
                                if rank == nil then rank = panel.ranksByName[name] end
                            end
                            NoteRank(learned, name, rank or 0)
                        end
                    end
                end
            end
        end
    end
end

local function AvailabilityColor(entry, level)
    if not Public(level) or type(level) ~= "number" or level < 1 then return NS.Theme.GetColor("muted") end
    if entry.requiresTalent or entry.requiresQuest or entry.pendingQuest or entry.source == SOURCE.unconfirmed then
        return RED_FONT_COLOR:GetRGB()
    end
    if entry.level <= level then return GREEN_FONT_COLOR:GetRGB() end
    if entry.level <= level + 2 then return YELLOW_FONT_COLOR:GetRGB() end
    return RED_FONT_COLOR:GetRGB()
end

local function Label(parent, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function Button(parent, text, minWidth, callback, primary)
    local button = Safety.CreateChildFrame("Button", parent)
    local label = Label(button, primary and "GameFontHighlight" or nil)
    label:SetPoint("CENTER")
    label:SetJustifyH("CENTER")
    label:SetText(text)
    label:SetShadowColor(0, 0, 0, .9)
    label:SetShadowOffset(0, -1)
    local width = Read(label, "GetStringWidth") or 0
    button:SetSize(math.max(minWidth, math.ceil(width) + (primary and 32 or 18)), primary and 28 or 24)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", callback)
    button.label = label
    NS.ControlSkin.ApplyButton(button, OWNER, primary and PRIMARY or BUTTON)
    return button
end

local function Rule(parent, point, y, inset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint(point .. "LEFT", parent, point .. "LEFT", inset, y)
    line:SetPoint(point .. "RIGHT", parent, point .. "RIGHT", -inset, y)
    line:SetHeight(1)
    return line
end

local function AllowedRace(race, low, high)
    low, high = tonumber(low) or 0, tonumber(high) or 0
    if low == 0 and high == 0 then return true end
    if not Public(race) or type(race) ~= "number" then return false end
    local raceBit = NS.ForeverSpellLearningRaceBits[race]
    if not raceBit then return false end
    return bit.band(raceBit < 32 and low or high, bit.lshift(1, raceBit % 32)) ~= 0
end

local function ReadIndex()
    local _, _, class = UnitClass("player")
    local _, _, race = UnitRace("player")
    local data = Public(class) and NS.ForeverSpellLearningData[class]
    local entries = {}
    if not data then return entries end
    local costs = {}
    local prices = NS.ForeverSpellLearningCosts[class]
    if prices then
        for id, copper in prices:gmatch("(%d+):(%d+) ") do costs[tonumber(id)] = tonumber(copper) end
    end
    local pending = {}
    local pendingData = NS.ForeverSpellLearningPendingQuests[class]
    if pendingData then
        for id, quest in pendingData:gmatch("(%d+):(%d+) ") do pending[tonumber(id)] = tonumber(quest) end
    end
    local quests, variants = {}, NS.ForeverSpellLearningQuestSources[class]
    if variants and Public(race) and type(race) == "number" then
        for id, variantRace, level in variants:gmatch("(%d+):(%d+):(%d+) ") do
            if tonumber(variantRace) == race then quests[tonumber(id)] = tonumber(level) end
        end
    end
    local pattern = "(%d+):(%d+):(%d+):(%d+):?(%d*):?(%d*):?(%d*):?(%d*) "
    for id, level, rank, source, low, high, talent, quest in data:gmatch(pattern) do
        if AllowedRace(race, low, high) then
            local spell = tonumber(id)
            entries[#entries + 1] = { id = spell, level = quests[spell] or tonumber(level), rank = tonumber(rank),
                source = quests[spell] and SOURCE.quest or tonumber(source), cost = costs[spell],
                requiredTalent = tonumber(talent), requiredQuest = tonumber(quest), pendingQuest = pending[spell] }
        end
    end
    return entries
end

local function TrainingCost(row)
    if not row.isTraining then return end
    local red, green, blue = NS.Theme.GetColor("muted")
    if row.cost ~= nil then
        local money = C_CurrencyInfo.GetCoinTextureString(row.cost)
        if Public(money) and type(money) == "string" then
            GameTooltip:AddDoubleLine(NS.L["Training cost (before discounts)"], money, red, green, blue, 1, 1, 1)
        end
    else
        GameTooltip:AddLine(NS.L["Training cost not recorded"], red, green, blue)
    end
end

local function ToolTip(row)
    if not row.spellID or NS.IsCombatLocked() or Safety.IsForbidden(GameTooltip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(row.spellID)
    local source = row.source
    if source == SOURCE.trainer then
        GameTooltip:AddLine(NS.L["Class trainer"], NS.Theme.GetColor("accentBright"))
    elseif source == SOURCE.quest then
        local hint = row.pendingQuest and NS.L["Class quest #%d (availability unconfirmed)"]:format(row.pendingQuest)
            or NS.L["Class quest"]
        GameTooltip:AddLine(hint, NS.Theme.GetColor("accentBright"))
    elseif source == SOURCE.portal then
        GameTooltip:AddLine(NS.L["Portal trainer"], NS.Theme.GetColor("accentBright"))
    elseif source == SOURCE.item then
        GameTooltip:AddLine(NS.L["Tome or item"], NS.Theme.GetColor("accentBright"))
    elseif source == SOURCE.unconfirmed then
        GameTooltip:AddLine(NS.L["Learning source not confirmed"], NS.Theme.GetColor("accentBright"))
    elseif source == SOURCE.automatic then
        GameTooltip:AddLine(NS.L["Learned automatically"], NS.Theme.GetColor("accentBright"))
    end
    if row.requiresTalent then
        GameTooltip:AddLine(NS.L["Requires a talent"], NS.Theme.GetColor("accentBright"))
    end
    if row.requiresQuest then GameTooltip:AddLine(NS.L["Requires a class quest"], NS.Theme.GetColor("accentBright")) end
    TrainingCost(row)
    GameTooltip:Show()
end

local function HideTooltip(row)
    if not Safety.IsForbidden(GameTooltip) and Read(GameTooltip, "IsOwned", row) == true then GameTooltip:Hide() end
end

local function MakeRow(panel, index)
    local row = CreateFrame("Frame", nil, panel)
    local y = -99 - (index - 1) * ROW_HEIGHT
    row:SetPoint("TOPLEFT", 16, y)
    row:SetPoint("TOPRIGHT", -16, y)
    row:SetHeight(ROW_HEIGHT)
    if index < ROWS then row.divider = Rule(row, "BOTTOM", 0, 0) end
    row:EnableMouse(true)
    row:SetScript("OnEnter", ToolTip)
    row:SetScript("OnLeave", HideTooltip)
    row:SetScript("OnHide", HideTooltip)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(19, 19)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = Label(row)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.level = Label(row)
    row.level:SetPoint("RIGHT", -2, 0)
    row.level:SetWidth(86)
    row.level:SetJustifyH("RIGHT")
    row.rank = Label(row)
    row.rank:SetPoint("RIGHT", row.level, "LEFT", -12, 0)
    row.rank:SetWidth(64)
    row.rank:SetJustifyH("RIGHT")
    row.name:SetPoint("RIGHT", row.rank, "LEFT", -10, 0)
    return row
end

local function Paint(panel)
    local shown = panel.filtered
    local maxPage = math.max(1, math.ceil(#shown / ROWS))
    panel.page = math.min(maxPage, math.max(1, panel.page))
    local level = UnitLevel("player")
    for index = 1, ROWS do
        local row = panel.rows[index]
        local entry = shown[(panel.page - 1) * ROWS + index]
        if entry then
            local red, green, blue, alpha = AvailabilityColor(entry, level)
            row.spellID, row.source = entry.id, entry.source
            row.requiresTalent, row.requiresQuest = entry.requiresTalent, entry.requiresQuest
            row.pendingQuest = entry.pendingQuest
            row.cost = entry.cost
            row.isTraining = entry.source == SOURCE.trainer or entry.source == SOURCE.portal
            row.icon:SetTexture(entry.icon)
            row.name:SetText(entry.name)
            row.name:SetTextColor(red, green, blue, alpha or 1)
            row.rank:SetText(entry.rank > 0 and NS.L["Rank %d"]:format(entry.rank) or "")
            row.rank:SetTextColor(red, green, blue, alpha or 1)
            row.level:SetText(NS.L["Level %d"]:format(entry.level))
            row.level:SetTextColor(red, green, blue, alpha or 1)
            row:Show()
            if row:IsMouseOver() and Read(GameTooltip, "IsOwned", row) == true then ToolTip(row) end
        else
            row:Hide()
            row.spellID = nil
        end
    end
    panel.status:SetText(#shown > 0 and ("%d / %d"):format(panel.page, maxPage) or NS.L["No spells to show"])
    local canGoBack, canGoForward = panel.page > 1, panel.page < maxPage
    panel.previous:SetEnabled(canGoBack)
    panel.next:SetEnabled(canGoForward)
    panel.previous.label:SetTextColor(NS.Theme.GetColor(canGoBack and "text" or "dim"))
    panel.next.label:SetTextColor(NS.Theme.GetColor(canGoForward and "text" or "dim"))
end

local function Filter(panel)
    local query = panel.search:GetText()
    query = Public(query) and type(query) == "string" and query:lower() or ""
    local matches = panel.filtered
    local count = 0
    for _, entry in ipairs(panel.available) do
        if query == "" or entry.searchName:find(query, 1, true) then
            count = count + 1
            matches[count] = entry
        end
    end
    for index = #matches, count + 1, -1 do matches[index] = nil end
    Paint(panel)
end

local function KnowsUnlock(panel, learned, id)
    if not id or id == 0 then return true end
    local cached = panel.unlocks[id]
    if cached ~= nil then return cached end
    local entry = panel.byID[id]
    local known = panel.bookIDs[id] or entry and entry.learned
    if not entry then
        known = C_SpellBook.IsSpellKnownOrInSpellBook(id, PLAYER_BANK, false)
        known = Public(known) and known == true
    end
    local unlocked = known == true or entry and learned[entry.family] ~= nil or false
    panel.unlocks[id] = unlocked
    return unlocked
end

local function Refresh(panel)
    if not panel:IsShown() or NS.IsCombatLocked() then return end
    panel.entries = panel.entries or ReadIndex()
    local learned = {}
    panel.ranksByID, panel.ranksByName, panel.byID, panel.unlocks, panel.bookIDs = {}, {}, {}, {}, {}
    for _, entry in ipairs(panel.entries) do
        local known = C_SpellBook.IsSpellKnownOrInSpellBook(entry.id, PLAYER_BANK, false)
        entry.known = not Public(known) or known ~= false
        entry.learned = Public(known) and known == true
        panel.byID[entry.id] = entry
        local name = entry.name or C_Spell.GetSpellName(entry.id)
        if Public(name) and type(name) == "string" and name ~= "" then
            if not entry.name then
                local icon = C_Spell.GetSpellTexture(entry.id)
                entry.name, entry.searchName = name, name:lower()
                entry.icon = Public(icon) and icon or nil
                entry.family = FamilyName(name, entry.rank)
            end
            panel.ranksByID[entry.id] = entry.rank
            local rank = panel.ranksByName[name]
            panel.ranksByName[name] = rank == nil and entry.rank or rank == entry.rank and rank or false
            if Public(known) and known == true then NoteRank(learned, name, entry.rank) end
        end
    end
    LearnedRanks(panel, learned)
    local count = 0
    for _, entry in ipairs(panel.entries) do
        if entry.name and not entry.known and not panel.bookIDs[entry.id] then
            local rank = learned[entry.family]
            local talent = entry.requiredTalent or (entry.source == SOURCE.talent and entry.id)
            entry.requiresTalent = not KnowsUnlock(panel, learned, talent)
            local quest = entry.requiredQuest and panel.byID[entry.requiredQuest]
            entry.requiresQuest = quest and quest.source == SOURCE.quest
                and not KnowsUnlock(panel, learned, entry.requiredQuest) or false
            -- An unranked spell can be a separate appearance (Polymorph),
            -- so only numbered ranks may be replaced by a same-name rank.
            if rank == nil or entry.rank == 0 or entry.rank > rank then
                count = count + 1
                panel.available[count] = entry
            end
        end
    end
    for index = #panel.available, count + 1, -1 do panel.available[index] = nil end
    Filter(panel)
end

local function Advance(panel, delta)
    panel.page = panel.page + delta
    Paint(panel)
end

local function Position(panel)
    local controls = NS.WindowControls.states[panel]
    if controls and controls.customPosition then return end
    local book = panel.book
    local edge, left = Read(book, "GetRight"), Read(book, "GetLeft")
    local scale = Read(book, "GetEffectiveScale")
    local panelScale = Read(panel, "GetEffectiveScale")
    local uiScale = Read(UIParent, "GetEffectiveScale")
    if type(panelScale) ~= "number" or type(uiScale) ~= "number" or uiScale <= 0 then return end
    local width = WIDTH * panelScale / uiScale
    panel:ClearAllPoints()
    if type(edge) == "number" and type(scale) == "number"
        and edge * scale / uiScale + width + 8 <= UIParent:GetWidth() then
        panel:SetPoint("TOPLEFT", book, "TOPRIGHT", 8, 0)
    elseif type(left) == "number" and type(scale) == "number" and left * scale / uiScale >= width + 8 then
        panel:SetPoint("TOPRIGHT", book, "TOPLEFT", -8, 0)
    else
        panel:SetPoint("TOP", book, "TOP", 0, -49)
    end
end

local function OnPanelEvent(panel, event)
    if event == "PLAYER_REGEN_DISABLED" then
        panel:Hide()
    elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if not NS.IsCombatLocked() then Position(panel) end
    else
        NS.Registry.QueueJob(panel.refresh)
    end
end

local function PaintPanelTheme(panel)
    NS.Surface.Ensure(panel, SHELL)
    panel.title:SetTextColor(NS.Theme.GetColor("title"))
    panel.caption:SetTextColor(NS.Theme.GetColor("muted"))
    panel.status:SetTextColor(NS.Theme.GetColor("muted"))
    panel.close.label:SetTextColor(NS.Theme.GetColor("text"))
    panel.search:SetTextColor(NS.Theme.GetColor("text"))
    local hint = Safety.Field(panel.search, "Instructions")
    if type(hint) == "table" then hint:SetTextColor(NS.Theme.GetColor("muted")) end
    panel.headerRule:SetColorTexture(NS.Theme.GetColor("border"))
    panel.footerRule:SetColorTexture(NS.Theme.GetColor("border"))
    for index = 1, ROWS - 1 do
        panel.rows[index].divider:SetColorTexture(NS.Theme.GetColor("borderSoft"))
    end
end

local function OnPanelShow(panel)
    panel:RegisterEvent("SPELLS_CHANGED")
    panel:RegisterEvent("SPELL_TEXT_UPDATE")
    panel:RegisterEvent("PLAYER_LEVEL_UP")
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:RegisterEvent("UI_SCALE_CHANGED")
    panel:RegisterEvent("DISPLAY_SIZE_CHANGED")
    NS.WindowControls.Attach(panel, OWNER)
    Position(panel)
    PaintPanelTheme(panel)
    Refresh(panel)
end

local function OnPanelHide(panel)
    panel:UnregisterAllEvents()
    panel.search:ClearFocus()
end

local function CreatePanel(book)
    local panel = CreateFrame("Frame", "MSUFSuiteSpellLearningFrame", UIParent)
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:Hide()
    panel.book, panel.page, panel.rows, panel.available, panel.filtered = book, 1, {}, {}, {}
    panel.refresh = function() Refresh(panel) end
    panel.close = Button(panel, CLOSE, 74, function() panel:Hide() end)
    panel.close:SetPoint("TOPRIGHT", -12, -10)
    panel.title = Label(panel, "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 16, -14)
    panel.title:SetPoint("RIGHT", panel.close, "LEFT", -10, 0)
    panel.title:SetText(NS.L["Spells to Learn"])
    function panel:GetTitleText() return self.title end
    panel.caption = Label(panel)
    panel.caption:SetPoint("TOPLEFT", 16, -40)
    panel.caption:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    panel.caption:SetText(NS.L["Unlearned spells and ranks by required level"])
    panel.search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    panel.search:SetHeight(25)
    panel.search:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -61)
    panel.search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -61)
    panel.search:SetAutoFocus(false)
    NS.ControlSkin.ApplySearchBox(panel.search, OWNER, SEARCH)
    panel.headerRule = Rule(panel, "TOP", -93, 16)
    panel.footerRule = Rule(panel, "BOTTOM", 44, 16)
    panel.search:HookScript("OnTextChanged", function()
        panel.page = 1
        if panel:IsShown() then Filter(panel) end
    end)
    panel.search:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    for index = 1, ROWS do panel.rows[index] = MakeRow(panel, index) end
    panel.previous = Button(panel, "<", 29, function() Advance(panel, -1) end)
    panel.previous:SetPoint("BOTTOMLEFT", 16, 10)
    panel.next = Button(panel, ">", 29, function() Advance(panel, 1) end)
    panel.next:SetPoint("BOTTOMRIGHT", -36, 10)
    panel.status = Label(panel)
    panel.status:SetPoint("BOTTOM", 0, 16)
    panel:SetScript("OnMouseWheel", function(_, delta) Advance(panel, delta < 0 and 1 or -1) end)
    panel:SetScript("OnEvent", OnPanelEvent)
    panel:SetScript("OnShow", OnPanelShow)
    panel:SetScript("OnHide", OnPanelHide)
    Position(panel)
    return panel
end

function Learning.Hide(state)
    if state.learningButton then state.learningButton:Hide() end
    if state.learningPanel then state.learningPanel:Hide() end
end

local function Enabled()
    return NS.DB.enabled ~= false and NS.DB.blizzardWindowsEnabled ~= false
        and NS.DB.skins.playerSpells ~= false and NS.DB.foreverSpellLearning ~= false
        and not NS.Client.IsGamepadUI()
end

local function CreateLearningButton(book, paged, onClick)
    -- A sibling of the rank toggle follows the book's own stacking and focus.
    local button = Button(book, NS.L["Spells to Learn"], 170, onClick, true)
    button:SetFrameLevel((Read(paged, "GetFrameLevel") or 1) + 10)
    button:SetPoint("TOPRIGHT", paged, "TOPRIGHT", -24, -10)
    return button
end

local function RefuseCombatOpen()
    -- Click refusals include the combat edge and the early-startup window;
    -- the skin's protected-write guard intentionally differs in that window.
    if not NS.SuiteCore().InCombat() then return false end
    local now = GetTime()
    if not lastCombatNotice or now - lastCombatNotice >= 1.25 then
        lastCombatNotice = now
        local message = NS.L["Finish combat first."]
        if not Safety.IsForbidden(UIErrorsFrame) then UIErrorsFrame:AddMessage(message, 1, .82, .1) end
        NS.Print(message)
    end
    return true
end

function Learning.Attach(state, book, paged)
    if not Enabled() or NS.IsCombatLocked() or Safety.IsForbidden(book) or Safety.IsForbidden(paged) then return end
    if not state.learningButton then
        local function Toggle()
            if not Enabled() or Read(book, "IsVisible") ~= true or RefuseCombatOpen() then return end
            local panel = state.learningPanel
            if not panel then
                panel = CreatePanel(book)
                state.learningPanel = panel
            end
            panel:SetShown(not panel:IsShown())
        end
        local button = CreateLearningButton(book, paged, Toggle)
        state.learningButton = button
        book:HookScript("OnShow", Safety.Isolated(function()
            if state.active and Enabled() then button:Show() end
        end))
        book:HookScript("OnHide", Safety.Isolated(function() Learning.Hide(state) end))
    end
    local button = state.learningButton
    local red, green, blue = NS.Theme.GetColor("accentBright")
    button.label:SetTextColor(red, green, blue, 1)
    button:SetShown(Read(book, "IsVisible") == true)
end

function Learning.RefreshSetting()
    local state = NS.PlayerSpellsSkin.activeState
    if not state then return end
    if not Enabled() then return Learning.Hide(state) end
    local book = Safety.Field(state.frame, "SpellBookFrame")
    local paged = Safety.Field(book, "PagedSpellsFrame")
    if book and paged and not NS.IsCombatLocked() then Learning.Attach(state, book, paged) end
    if state.learningPanel and state.learningPanel:IsShown() then
        PaintPanelTheme(state.learningPanel)
        Paint(state.learningPanel)
    end
end

function Learning.SetEnabled(value)
    NS.DB.foreverSpellLearning = value == true
    Learning.RefreshSetting()
    return true
end

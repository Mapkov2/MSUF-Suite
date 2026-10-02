local root = assert(arg[1], "repository root required")
local module, mover, hooks, fonts, levelCalls, requests = nil, nil, {}, {}, 0, {}
local infoCalls = 0
local movers = {}
local combat, queued = false, 0
local nativeLayouts, enumerations = 0, 0
local bagMode = "0"
local money = 100000
local cursorX, cursorY = 500, 500
GetMoney = function() return money end
GetCursorPosition = function() return cursorX, cursorY end
IsShiftKeyDown = function() return false end
UnitGUID = function() return "Player-test" end
local levels = { ["gear-a"] = 640, ["gear-b"] = 651 }
local items = {
    [1] = { hyperlink = "gear-a", itemID = 101, quality = 4 },
    [2] = { hyperlink = "food", itemID = 102, quality = 1 },
}
local function Font()
    local font = { shown = false }
    for _, key in ipairs({ "SetDrawLayer", "SetJustifyH" }) do
        font[key] = function() end
    end
    function font:SetShadowOffset(...) self.shadowOffset = { ... } end
    function font:SetShadowColor(...) self.shadowColor = { ... } end
    function font:SetPoint(...) self.point = { ... } end
    function font:SetWidth(value) self.width = value end
    function font:SetWordWrap(value) self.wordWrap = value end
    function font:SetTextColor(...) self.color = { ... } end
    function font:SetText(value) self.text = value end
    function font:Show() self.shown = true end
    function font:Hide() self.shown = false; self.hideCalls = (self.hideCalls or 0) + 1 end
    fonts[#fonts + 1] = font
    return font
end
local textures = {}
local function Texture(parent)
    local texture = { parent = parent, shown = true }
    function texture:SetPoint(...) self.points = self.points or {}; self.points[#self.points + 1] = { ... } end
    function texture:SetHeight(value) self.height = value end
    function texture:SetWidth(value) self.width = value end
    function texture:SetAllPoints(value) self.allPoints = value end
    function texture:SetShown(value) self.shown = value end
    function texture:Show() self.shown = true; self.showCalls = (self.showCalls or 0) + 1 end
    function texture:Hide() self.shown = false end
    function texture:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function texture:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
    textures[#textures + 1] = texture
    return texture
end
local createdFrames = {}
local function VisualFrame(parent)
    local frame = { parent = parent, shown = true, level = 0, alpha = 1, mouseEnabled = true }
    function frame:SetPoint(...)
        local point = { ... }
        self.points = self.points or {}
        for i = 1, #self.points do
            if self.points[i][1] == point[1] then self.points[i] = point; return end
        end
        self.points[#self.points + 1] = point
    end
    function frame:GetPoint(index) return unpack(self.points[index]) end
    function frame:GetNumPoints() return self.points and #self.points or 0 end
    function frame:ClearAllPoints() self.points = {} end
    function frame:GetFrameLevel() return self.level end
    function frame:SetFrameLevel(value) self.level = value end
    function frame:SetAllPoints(target) self.allPoints = target end
    function frame:RegisterForClicks(value) self.clicks = value end
    function frame:RegisterForDrag(value) self.drags = value end
    function frame:SetScript(name, callback) self.scripts = self.scripts or {}; self.scripts[name] = callback end
    function frame:RegisterEvent(name) self.events = self.events or {}; self.events[name] = true end
    function frame:RegisterUnitEvent(name, unit) self.events = self.events or {}; self.events[name] = unit end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(value) self.alpha = value end
    function frame:IsMouseEnabled() return self.mouseEnabled end
    function frame:EnableMouse(value) self.mouseEnabled = value end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetShown(value) if value then self:Show() else self:Hide() end end
    createdFrames[#createdFrames + 1] = frame
    return frame
end
local function PortraitButton()
    local button = VisualFrame()
    button.Highlight = VisualFrame(button)
    button.SetupMenu = function() end
    button.IsMenuOpen = function(self) return self.menuOpen == true end
    button.SetMenuOpen = function(self, value) self.menuOpen = value end
    return button
end
local buttons = {}
for i = 1, 3 do
    buttons[i] = {
        emptyBackgroundAtlas = "bags-item-slot64",
        ItemSlotBackground = VisualFrame(),
        GetBagID = function() return 0 end,
        GetID = function() return i end,
        HasItem = function() return items[i] and true or nil end,
        SetItemButtonTexture = function(self, texture)
            self.emptyIcon = texture or (self.emptyBackgroundAtlas or nil)
            self.textureCalls = (self.textureCalls or 0) + 1
        end,
    }
end
local reagentButton = {
    emptyBackgroundAtlas = "bags-item-slot64",
    GetBagID = function() return 5 end,
    GetID = function() return 1 end,
    HasItem = function() return nil end,
    SetItemButtonTexture = buttons[1].SetItemButtonTexture,
}
UIParent = { GetScaledRect = function() return 0, 0, 1000, 800 end }
-- Screen rect of a bag anchored by its BOTTOMRIGHT to UIParent's BOTTOMRIGHT
-- or to another bag's BOTTOMLEFT (Blizzard's next bag column).
local function BagRect(frame, width, height)
    local scale, point = frame.scale, frame.point
    local right, bottom = 1000 + point[4] * scale, point[5] * scale
    if point[2] ~= UIParent then
        local relativeLeft, relativeBottom = point[2]:GetScaledRect()
        right, bottom = relativeLeft + point[4] * scale, relativeBottom + point[5] * scale
    end
    return right - width * scale, bottom, width * scale, height * scale
end
ContainerFrameCombinedBags = {
    Bg = VisualFrame(), NineSlice = VisualFrame(), MoneyFrame = VisualFrame(),
    PortraitContainer = VisualFrame(), PortraitButton = PortraitButton(),
    shown = true,
    scale = 0.9,
    point = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 32 },
    IsShown = function(self) return self.shown end,
    GetScale = function(self) return self.scale end,
    SetScale = function(self, value) self.scale = value end,
    GetEffectiveScale = function(self) return self.scale end,
    GetScaledRect = function(self) return BagRect(self, 430, 700) end,
    IsMovable = function() return true end,
    StartMoving = function(self) self.moving = true end,
    StopMovingOrSizing = function(self) self.moving = false end,
    GetPoint = function(self) return unpack(self.point) end,
    SetPoint = function(self, ...) self.point = { ... } end,
    ClearAllPoints = function(self) self.point = {} end,
    EnumerateValidItems = function() enumerations = enumerations + 1; return ipairs(buttons) end,
    UpdateItems = function() end,
    HookScript = function(self, name, callback) hooks[name] = callback end,
}
ContainerFrame6 = {
    Bg = VisualFrame(), NineSlice = VisualFrame(), shown = false,
    PortraitContainer = VisualFrame(), PortraitButton = PortraitButton(),
    scale = 0.9,
    point = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -500, 32 },
    IsShown = function(self) return self.shown end,
    GetEffectiveScale = function(self) return self.scale end,
    GetScaledRect = function(self) return BagRect(self, 180, 400) end,
    IsMovable = function() return true end,
    GetPoint = function(self) return unpack(self.point) end,
    SetPoint = function(self, ...) self.point = { ... } end,
    ClearAllPoints = function(self) self.point = {} end,
    StartMoving = function(self) self.moving = true end,
    StopMovingOrSizing = function(self) self.moving = false end,
    EnumerateValidItems = function() return ipairs({ reagentButton }) end,
    UpdateItems = function() end,
    HookScript = function(self, name, callback) hooks["Reagent" .. name] = callback end,
}
for _, frame in ipairs({ ContainerFrameCombinedBags, ContainerFrame6 }) do
    frame.TitleContainer = VisualFrame(frame)
    frame.TitleContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 35, -1)
    frame.TitleContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -1)
    frame.SetTitleOffsets = function(self, left, right)
        self.TitleContainer:SetPoint("TOPLEFT", self, "TOPLEFT", left, -1)
        self.TitleContainer:SetPoint("TOPRIGHT", self, "TOPRIGHT", right or -24, -1)
    end
end
-- The open-bag list of ContainerFrameSettingsManager:GetBagsShown, already
-- built (a stale list is nil; suite_bags_view_client_contract covers it).
ContainerFrameSettingsManager = { bagsShown = {} }
UpdateContainerFrameAnchors = function()
    nativeLayouts = nativeLayouts + 1
    ContainerFrameCombinedBags.scale = 0.9
    ContainerFrameCombinedBags.point = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 32 }
    ContainerFrame6.point = { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -500, 32 }
    if hooks.NativeAnchors then hooks.NativeAnchors() end
end
hooksecurefunc = function(frame, name, callback)
    if frame == "UpdateContainerFrameAnchors" then
        hooks.NativeAnchors = name
    else
        assert(name == "UpdateItems")
        hooks[frame == ContainerFrame6 and "ReagentItems" or name] = callback
    end
end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, field in pairs(value) do copy[key] = field end
    return copy
end
C_Container = {
    GetContainerItemInfo = function(_, slot)
        infoCalls = infoCalls + 1
        return Copy(items[slot])
    end,
    GetContainerNumSlots = function(bag) return bag == 0 and #buttons or 0 end,
    GetContainerItemQuestInfo = function() return { isQuestItem = false } end,
}
Constants = { InventoryConstants = { NumBagSlots = 4 } }
-- ItemConstantsDocumentation.lua (Retail and Forever).
Enum = { ItemBind = { None = 0, OnAcquire = 1, OnEquip = 2, OnUse = 3, Quest = 4, Unused1 = 5, Unused2 = 6,
    ToWoWAccount = 7, ToBnetAccount = 8, ToBnetAccountUntilEquipped = 9 } }
-- WoW Forever has no global GetItemQualityColor (Retail keeps it only as a
-- deprecated alias): quality colours come from C_Item on both clients.
C_Item = {
    IsEquippableItem = function(link) return link ~= "food" end,
    GetDetailedItemLevelInfo = function(link) levelCalls = levelCalls + 1; return levels[link] end,
    RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end,
    GetItemQualityColor = function(quality) return quality == 4 and 0.7 or 1, 0.5, 1, "ffb380ff" end,
    GetItemInfo = function(link)
        local bind = { ["gear-a"] = 2, ["gear-b"] = 9, food = 1, ["gear-warbound"] = 8, ["gear-account"] = 7 }
        return unpack({ [14] = bind[link] }, 1, 14)
    end,
}
C_CVar = { GetCVar = function(name)
    assert(name == "combinedBags")
    return bagMode
end }
-- Blizzard_GameTooltip builds GameTooltip at startup on both clients.
local tooltip = { lines = {} }
GameTooltip = tooltip
function tooltip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
function tooltip:SetText(text) self.lines[1] = text end
function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function tooltip:Show() self.shown = true end
function tooltip:Hide() self.shown = false end

local deferred, setManyCalls = {}, 0
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }
local function RunDeferred()
    local list = deferred
    deferred = {}
    for _, callback in ipairs(list) do callback() end
end
-- The session label translates as one format string (a German client).
local translations = { ["Session %s"] = "Sitzung %s" }
local S = {
    Public = function(value) return value ~= "secret" end,
    Text = function(value) return translations[value] or value end,
    CreateFontString = function(parent) local font = Font(); font.parent = parent; return font end,
    CreateFrame = function(_, _, parent) return VisualFrame(parent) end,
    CreateTexture = function(parent, _, layer, _, sublevel)
        local texture = Texture(parent)
        texture.layer, texture.sublevel = layer, sublevel
        return texture
    end,
    RGB = function(hex)
        return tonumber(hex:sub(1, 2), 16) / 255,
            tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255
    end,
    ResolveFont = function() return nil end,
    GlobalFontPath = function() return "Interface\\AddOns\\Test\\Media\\MSUF.ttf" end,
    SetFont = function(font, path, size)
        font.path, font.size = path or "Interface\\AddOns\\Test\\Media\\MSUF.ttf", size
    end,
    Queue = function(id) assert(id == "bags"); queued = queued + 1 end,
    Install = function(id, instance) assert(id == "bags"); module = instance end,
    RegisterOwnedMover = function(id, element, spec)
        assert(id == "bags" and (element == "combined" or element == "reagent"))
        movers[element] = spec
        if element == "combined" then mover = spec end
    end,
    RefreshOwnedMovers = function() end,
    Config = function() return module.config end,
    Set = function(_, key, value)
        module.config[key] = value
        module:Refresh()
        return true
    end,
    SetMany = function(_, values)
        setManyCalls = setManyCalls + 1
        for key, value in pairs(values) do module.config[key] = value end
        module:Refresh()
        return true
    end,
    editMode = false,
}
-- Readable-number helpers as defined by MSUF_Suite_Modules/Runtime.lua.
S.Number = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Finite = function(value) return S.Number(value) and value > -math.huge and value < math.huge end
S.SetStyledFont = function(font, _, size, flags, rendering, shadow, opacity, distance)
    font.size = size
    font.flags = rendering == 3 and (flags == "" and "SLUG" or "OUTLINE,SLUG") or flags
    local shown = shadow and rendering ~= 3
    font:SetShadowColor(0, 0, 0, shown and (opacity or 100) / 100 or 0)
    font:SetShadowOffset(shown and (distance or 1) or 0, shown and -(distance or 1) or 0)
end
-- Blizzard builds its shared font objects at startup on every client.
GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
-- Money text comes from the shared helper in MSUF_Suite_Modules/Surfaces.lua.
local shared = { Suite = {} }
MSUFSuite = shared
GOLD_AMOUNT_SYMBOL, SILVER_AMOUNT_SYMBOL, COPPER_AMOUNT_SYMBOL = "g", "s", "c"
assert(loadfile(root .. "/MSUF_Suite_Modules/Surfaces.lua"))("MSUF_Suite_Modules", {})
MSUFSuite = nil
local moneyTexts = 0
S.MoneyText = function(amount)
    moneyTexts = moneyTexts + 1
    return shared.Suite.MoneyText(amount)
end
local state = { IsCombatLocked = function() return combat end,
    Client = { isForever = false },
    RootDB = { suiteGold = { ["Player-test"] = 100000 } }, loginKind = "login",
    goldSessionCaptured = true, MSUFMedia = { font = "Interface\\AddOns\\Test\\Media\\MSUF.ttf" } }
-- The session gold baseline is owned by the core (MSUF_Suite/Core/SessionGold.lua).
state.Finite = S.Finite
state.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
assert(loadfile(root .. "/MSUF_Suite/Core/SessionGold.lua"))("MSUF_Suite", state)
local bagsPrivate = { NS = state, Suite = S }
-- The Bags catalog (always loaded): its sections, the gold ledger and the
-- session gold baseline (MSUF_Suite/Core/Catalog/Bags.lua).
state.Text = function(text) return text end
for _, file in ipairs({ "SuiteCatalog", "Catalog/Bags" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", state)
end
for _, file in ipairs({ "SlotCache", "ItemLoads", "Bags" }) do
    assert(loadfile(root .. "/MSUF_Suite_Bags/" .. file .. ".lua"))("MSUF_Suite_Bags", bagsPrivate)
end
-- The sub-modules (their own files, not loaded here) run in Bags.lua's list
-- order after its own refresh and stop; record each call.
local submoduleCalls = {}
for _, entry in ipairs(module.SUBMODULES) do
    local methods = {}
    for slot = 2, 3 do
        local method = entry[slot]
        if method then methods[method] = function() submoduleCalls[#submoduleCalls + 1] = entry[1] .. "." .. method end end
    end
    bagsPrivate[entry[1]] = methods
end
-- BAG_UPDATE(bag) reaches the shared slot cache before Blizzard's UpdateItems.
local function BagChanged()
    local cache = bagsPrivate.SlotCache
    assert(cache.events and cache.events.events.BAG_UPDATE, "the slot cache does not listen for BAG_UPDATE")
    cache.events.scripts.OnEvent(cache.events, "BAG_UPDATE", 0)
end
for _, file in ipairs({ "BagWindow", "BankItemLevel" }) do
    assert(loadfile(root .. "/MSUF_Suite_Bags/" .. file .. ".lua"))("MSUF_Suite_Bags", {
        NS = state, Suite = S, BagsModule = module, ItemLoads = bagsPrivate.ItemLoads,
    })
end
assert(module and #fonts == 0 and #textures == 0 and not next(hooks) and infoCalls == 0,
    "dormant module did work before enable")
local catalogNS = { Client = { isForever = false } }
for _, file in ipairs({ "SuiteCatalog", "Catalog/Bags" }) do
    assert(loadfile(root .. "/MSUF_Suite/Core/" .. file .. ".lua"))("MSUF_Suite", catalogNS)
end
assert(catalogNS.SuiteCatalog.bags.cvars and catalogNS.SuiteCatalog.bags.cvars.combinedBags,
    "combinedBags is not declared, so disabling Bags would never restore it")
assert(catalogNS.SuiteCatalog.bags.rules.showBankItemLevel.default == true,
    "Retail bank item levels are not enabled by default")

local context = { events = {} }
function context:CVar(key, value)
    assert(key == "combinedBags" and value == 1)
    self.before = self.before or bagMode
    bagMode = "1"
    return true
end
function context:Event(name, callback) self.events[name] = callback end
function context:RemoveEvent(name) self.events[name] = nil end
function context:Alpha(frame, value)
    self.alphas = self.alphas or {}
    if self.alphas[frame] == nil then self.alphas[frame] = frame:GetAlpha() end
    frame:SetAlpha(value)
end
function context:HideControl(frame, hidden)
    if not hidden then return end
    self.mouse = self.mouse or {}
    if self.mouse[frame] == nil then self.mouse[frame] = frame:IsMouseEnabled() end
    self:Alpha(frame, 0)
    frame:EnableMouse(false)
end
function context:Field(frame, key, value, refresh)
    self.fields = self.fields or {}
    local record = self.fields[frame]
    if not record then
        record = { key = key, before = frame[key], applied = value, refresh = refresh }
        self.fields[frame] = record
    end
    local changed = frame[key] ~= value
    frame[key] = value
    return changed
end
function context:Release()
    for frame, value in pairs(self.alphas or {}) do
        if frame:GetAlpha() == 0 then frame:SetAlpha(value) end
    end
    for frame, value in pairs(self.mouse or {}) do
        if not frame:IsMouseEnabled() then frame:EnableMouse(value) end
    end
    for frame, record in pairs(self.fields or {}) do
        if frame[record.key] == record.applied then
            frame[record.key] = record.before
            record.refresh(frame)
        end
    end
    self.alphas, self.mouse, self.fields = {}, {}, {}
end
function context:Scale(frame, value) frame:SetScale(value) end
function context:Position(frame, point, x, y)
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, point, x, y)
end
module.config = { showItemLevel = true, itemLevelSize = 12, font = "",
    fontOutline = 1, fontRendering = 3, fontShadow = false,
    fontShadowOpacity = 100, fontShadowDistance = 1, qualityColor = true,
    showSessionGold = true,
    windowScale = 1, windowMoved = false, windowX = 0, windowY = 0,
    styleWindows = false, backgroundColor = "14181b", backgroundOpacity = 98, accentColor = "9f8960",
    reagentWindowMoved = false, reagentWindowX = 0, reagentWindowY = 0 }
module.context, module.active = context, true
module:Enable()
assert(bagMode == "1" and hooks.UpdateItems and hooks.OnShow, "combined bag or hooks missing")
-- The explicit sub-module list replaces the files' post-hooks on the module.
local REFRESH_ORDER = { "InventoryView.Refresh", "BankInventory.Refresh", "BagFinance.Enable",
    "StackSplitter.Refresh", "SortDirection.Refresh" }
local STOP_ORDER = { "InventoryView.Disable", "BankInventory.Disable", "BagFinance.Disable", "AutoSplit.Stop",
    "StackSplitter.Close", "SortDirection.Restore" }
local function Ran(order)
    if #submoduleCalls ~= #order then return false end
    for i = 1, #order do if submoduleCalls[i] ~= order[i] then return false end end
    return true
end
assert(Ran(REFRESH_ORDER), "a refresh did not run the sub-modules in Bags.lua's order: "
    .. table.concat(submoduleCalls, ", "))
for _, file in ipairs({ "InventoryView", "BankInventory", "Finance", "AutoSplit", "StackSplitter", "SortDirection" }) do
    local handle = assert(io.open(root .. "/MSUF_Suite_Bags/" .. file .. ".lua", "rb"))
    local source = handle:read("*a")
    handle:close()
    assert(not source:find("hooksecurefunc%(%s*M%s*,"), file .. ".lua hooks the Bags module instead of joining its list")
end
assert(#textures == 23 and module.windows[ContainerFrameCombinedBags]
    and module.windows[ContainerFrame6] and textures[2].color[4] == 0.98,
    "combined and reagent bag backgrounds were not styled on enable")
local combinedStyle, reagentStyle = module.windows[ContainerFrameCombinedBags], module.windows[ContainerFrame6]
assert(combinedStyle.goldLabel and combinedStyle.goldLabel.text == "Sitzung 0c"
    and combinedStyle.goldLabel.width == 210
    and combinedStyle.goldLabel.parent == ContainerFrameCombinedBags.MoneyFrame
    and combinedStyle.goldLabel.point[2] == ContainerFrameCombinedBags.MoneyFrame
    and context.events.PLAYER_MONEY and context.events.PLAYER_ENTERING_WORLD,
    "the combined bag did not show the login gold baseline")
money = 112345
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Sitzung +1g 23s 45c"
    and combinedStyle.goldLabel.color[2] > combinedStyle.goldLabel.color[1],
    "gold gains did not update from the money event")
money = 90000
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Sitzung -1g"
    and combinedStyle.goldLabel.color[1] > combinedStyle.goldLabel.color[2],
    "gold losses did not update from the money event")
assert(moneyTexts > 0 and combinedStyle.goldLabel.path == state.MSUFMedia.font,
    "session gold did not use the shared S.MoneyText and MSUF media font")
money = "secret"
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Sitzung —", "unknown money showed a stale gain or loss")
money = 100000
module.config.showSessionGold = false
module:Refresh()
assert(not combinedStyle.goldLabel.shown and not context.events.PLAYER_MONEY,
    "disabled session gold kept its label or event")
module.config.showSessionGold = true
module:Refresh()
assert(combinedStyle.goldLabel.shown and context.events.PLAYER_MONEY
    and combinedStyle.goldLabel.text == "Sitzung 0c", "session gold did not return when enabled")
state.goldSessionCaptured = false
state.RootDB.suiteGold["Player-test"] = 999999
money = 120000
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Sitzung 0c"
    and state.RootDB.suiteGold["Player-test"] == 120000 and state.goldSessionCaptured,
    "an unreadable login baseline leaked a stale session change")
money = 130000
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Sitzung +1g",
    "the first public login baseline did not track subsequent gains")
assert(combinedStyle.shell.parent == ContainerFrameCombinedBags
    and reagentStyle.shell.parent == ContainerFrame6
    and combinedStyle.shell.level == 0 and reagentStyle.shell.level == 0
    and not combinedStyle.shell.mouseEnabled and not reagentStyle.shell.mouseEnabled
    and textures[2].parent == combinedStyle.shell and textures[3].parent == combinedStyle.shell
    and textures[11].parent == reagentStyle.shell and textures[12].parent == reagentStyle.shell,
    "Suite bag surface must be above native Bg and below item buttons without mouse capture")
assert(ContainerFrameCombinedBags.Bg.alpha == 0 and ContainerFrameCombinedBags.NineSlice.alpha == 0
    and ContainerFrame6.Bg.alpha == 0 and ContainerFrame6.NineSlice.alpha == 0,
    "native bag art still covers the Suite window surface")
for _, frame in ipairs({ ContainerFrameCombinedBags, ContainerFrame6 }) do
    assert(frame.PortraitContainer.alpha == 0 and frame.PortraitButton.alpha == 0
        and not frame.PortraitButton.mouseEnabled
        and select(4, frame.TitleContainer:GetPoint(1)) == 8,
        "empty portrait plate remained visible or the title did not reclaim its space")
end
-- Blizzard reads emptyBackgroundAtlas on every refresh (ItemButtonTemplate
-- SetItemButtonTexture): the Suite never writes it. An empty slot's Suite
-- surface covers the native icon (BORDER sublevel 0) instead.
local function OverIcon(record)
    return record.slotOuter.layer == "BORDER" and record.slotOuter.sublevel == 1
        and record.slotInner.layer == "BORDER" and record.slotInner.sublevel == 2
        and record.slotOuter.color[4] == 1 and record.slotInner.color[4] == 1
end
local function BelowIcon(record)
    return record.slotOuter.layer == "BACKGROUND" and record.slotOuter.sublevel == -5
        and record.slotInner.layer == "BACKGROUND" and record.slotInner.sublevel == -4
end
assert(buttons[3].emptyBackgroundAtlas == "bags-item-slot64" and buttons[3].textureCalls == nil,
    "the Suite wrote Blizzard's empty-slot field or replaced the native icon")
assert(buttons[3].ItemSlotBackground.alpha == 0 and OverIcon(module.overlays[buttons[3]]),
    "empty combined slots still draw Blizzard's embossed bag artwork")
assert(buttons[1].emptyBackgroundAtlas == "bags-item-slot64" and buttons[1].textureCalls == nil
    and BelowIcon(module.overlays[buttons[1]]),
    "styling replaced or covered a loaded item icon")
ContainerFrame6.shown = true
hooks.ReagentOnShow()
assert(#textures == 25 and reagentButton.emptyBackgroundAtlas == "bags-item-slot64"
    and reagentButton.textureCalls == nil and module.overlays[reagentButton].slotOuter.shown
    and OverIcon(module.overlays[reagentButton]),
    "reagent bag slots did not receive the Suite background")
local initialTextureCount = #textures
hooks.UpdateItems()
hooks.ReagentItems()
assert(#textures == initialTextureCount,
    "native bag refresh allocated another set of slot textures")
assert(textures[3].height == 62 and textures[12].height == 40
    and textures[4].points[1][2] == textures[3]
    and textures[13].points[1][2] == textures[12],
    "bag header and accent line are not anchored to the visible panel")
module.config.backgroundOpacity = 90
local layoutInfoCalls, layoutEnumerations = infoCalls, enumerations
module:Refresh()
assert(textures[2].color[4] == 0.9 and textures[11].color[4] == 0.9,
    "background opacity did not refresh both bag windows")
assert(infoCalls == layoutInfoCalls and enumerations == layoutEnumerations,
    "window opacity refreshed item levels or restyled item slots")
module.config.backgroundOpacity = 0
module:Refresh()
assert(textures[1].color[4] == 0 and textures[2].color[4] == 0
    and textures[3].color[4] == 0 and textures[5].color[4] == 0
    and textures[10].color[4] == 0 and textures[11].color[4] == 0
    and textures[12].color[4] == 0
    and module.overlays[buttons[3]].slotOuter.color[4] == 1
    and module.overlays[buttons[3]].slotInner.color[4] == 1,
    "transparent windows also hid item slots or left a tinted panel")
module.config.backgroundOpacity = 90
module:Refresh()
assert(combinedStyle.shell.shown and reagentStyle.shell.shown,
    "legacy disabled styling hid the new default bag window")
-- Blizzard's anchor is module state: no settings write, now or after combat.
local nativeWrites = setManyCalls
RunDeferred()
UpdateContainerFrameAnchors()
combat = true
UpdateContainerFrameAnchors()
combat = false
context.events.PLAYER_REGEN_ENABLED(module)
RunDeferred()
assert(setManyCalls == nativeWrites and #deferred == 0
    and module.config.windowX == 0 and module.config.windowY == 0,
    "Blizzard's native bag anchor was written into the profile")
assert(hooks.NativeAnchors and nativeLayouts > 0 and ContainerFrameCombinedBags.point[4] == -40
    and ContainerFrameCombinedBags.scale == 0.9,
    "the Suite bag window did not preserve Blizzard's initial placement")
module:RegisterMovers()
local function Near(value, expected) return math.abs(value - expected) < 0.001 end
-- An Edit Mode drag of the unmoved window starts from Blizzard's anchor.
local captured = { windowX = module.config.windowX, windowY = module.config.windowY }
mover.capture(captured)
assert(Near(captured.windowX, -40) and Near(captured.windowY, 32),
    "Edit Mode did not start the unmoved bag drag at Blizzard's anchor")
-- Blizzard chains a bag opened after another one into that bag's column, so
-- the drag start is read from the live window, whatever its anchor.
ContainerFrameCombinedBags.point = { "BOTTOMRIGHT", ContainerFrame6, "BOTTOMLEFT", -11, 0 }
hooks.NativeAnchors()
captured = { windowX = module.config.windowX, windowY = module.config.windowY }
mover.capture(captured)
assert(Near(captured.windowX, -691) and Near(captured.windowY, 32),
    "Edit Mode started the drag of a chained bag window from a stale anchor")
UpdateContainerFrameAnchors()
-- The same holds for the reagent bag: a never-moved one must not jump to the
-- saved (unused) offsets in the screen corner when its drag starts.
assert(type(movers.reagent.capture) == "function",
    "the reagent bag Edit Mode drag does not start from its live position")
local reagentStart = { reagentWindowX = 0, reagentWindowY = 0 }
movers.reagent.capture(reagentStart)
assert(Near(reagentStart.reagentWindowX, -500) and Near(reagentStart.reagentWindowY, 32),
    "Edit Mode did not start the unmoved reagent bag drag at Blizzard's anchor")
module.config.reagentWindowMoved = true
reagentStart = { reagentWindowX = -300, reagentWindowY = 90 }
movers.reagent.capture(reagentStart)
assert(reagentStart.reagentWindowX == -300 and reagentStart.reagentWindowY == 90,
    "a moved reagent bag drag did not start from its saved position")
module.config.reagentWindowMoved = false
assert(mover and mover.moveValues.windowMoved and mover.resetKeys[1] == "windowMoved"
    and mover.extraControls[1].id == "size" and mover.isEnabled(),
    "combined bag Edit Mode popup lacks size and position controls")
assert(movers.reagent and movers.reagent.moveValues.reagentWindowMoved
    and movers.reagent.resetKeys[1] == "reagentWindowMoved"
    and movers.reagent.isEnabled(),
    "open reagent bag has no independent Edit Mode mover")
local combinedHandle, reagentHandle = combinedStyle.dragHandle, reagentStyle.dragHandle
assert(combinedHandle and reagentHandle and combinedHandle.shown and reagentHandle.shown
    and combinedHandle.allPoints == ContainerFrameCombinedBags.TitleContainer
    and reagentHandle.allPoints == ContainerFrame6.TitleContainer
    and combinedHandle.drags == "LeftButton" and reagentHandle.drags == "LeftButton",
    "open bag titles are not draggable")
-- The title explains both of its actions: drag to move, click for the menu.
combinedHandle.scripts.OnEnter(combinedHandle)
assert(tooltip.shown and tooltip.owner == combinedHandle and tooltip.anchor == "ANCHOR_TOP"
    and tooltip.lines[1] == "Drag to move" and tooltip.lines[2] == "Click for bag options",
    "the bag title did not explain dragging and its menu")
combinedHandle.scripts.OnLeave(combinedHandle)
assert(not tooltip.shown, "leaving the bag title kept its tooltip")
combinedHandle.scripts.OnMouseDown(combinedHandle)
combinedHandle.scripts.OnClick(combinedHandle, "LeftButton")
assert(ContainerFrameCombinedBags.PortraitButton.menuOpen,
    "clicking the combined bag title lost Blizzard's bag menu")
combinedHandle.scripts.OnMouseDown(combinedHandle)
combinedHandle.scripts.OnClick(combinedHandle, "LeftButton")
assert(not ContainerFrameCombinedBags.PortraitButton.menuOpen,
    "second title click did not close Blizzard's bag menu")
combinedHandle.scripts.OnDragStart(combinedHandle)
assert(ContainerFrameCombinedBags.moving, "combined bag did not start moving")
layoutInfoCalls, layoutEnumerations = infoCalls, enumerations
cursorX, cursorY = 590, 455
combinedHandle.scripts.OnDragStop(combinedHandle)
combinedHandle.scripts.OnClick(combinedHandle, "LeftButton")
assert(not ContainerFrameCombinedBags.moving and not ContainerFrameCombinedBags.PortraitButton.menuOpen
    and module.config.windowMoved and module.config.windowX == 60 and module.config.windowY == -18
    and ContainerFrameCombinedBags.point[4] == 60 and ContainerFrameCombinedBags.point[5] == -18
    and infoCalls == layoutInfoCalls and enumerations == layoutEnumerations,
    "combined bag drag did not persist its scaled position or opened the menu")
module.config.windowMoved = false
module:Refresh()
cursorX, cursorY = 500, 500
reagentHandle.scripts.OnDragStart(reagentHandle)
assert(ContainerFrame6.moving, "reagent bag did not start moving")
layoutInfoCalls, layoutEnumerations = infoCalls, enumerations
cursorX, cursorY = 545, 545
reagentHandle.scripts.OnDragStop(reagentHandle)
assert(not ContainerFrame6.moving and module.config.reagentWindowMoved
    and module.config.reagentWindowX == -450 and module.config.reagentWindowY == 82
    and ContainerFrame6.point[4] == -450 and ContainerFrame6.point[5] == 82
    and infoCalls == layoutInfoCalls and enumerations == layoutEnumerations,
    "reagent bag drag did not persist its independent position")
ContainerFrameCombinedBags.shown = false
UpdateContainerFrameAnchors()
assert(ContainerFrame6.point[4] == -450 and ContainerFrame6.point[5] == 82,
    "reagent position was lost when the combined bag was closed")
ContainerFrameCombinedBags.shown = true
module.config.reagentWindowMoved = false
module:Refresh()
combat = true
combinedHandle.scripts.OnDragStart(combinedHandle)
assert(not ContainerFrameCombinedBags.moving and not module.dragWindow,
    "bag header started a protected drag in combat")
combat = false
S.editMode = true
module:Refresh()
assert(not combinedHandle.shown and not reagentHandle.shown,
    "normal bag drag handles blocked MSUF Edit Mode")
S.editMode = false
module:Refresh()
assert(combinedHandle.shown and reagentHandle.shown,
    "bag drag handles did not return after Edit Mode")
ContainerFrameCombinedBags.shown = false
hooks.OnHide()
assert(not mover.isEnabled(), "closed combined bags left a selectable Edit Mode mover")
ContainerFrameCombinedBags.shown = true
hooks.OnShow()
assert(mover.isEnabled(), "opening combined bags did not restore the Edit Mode mover")
assert(mover.extraControls[1].set(110) and mover.extraControls[1].get() == 110
    and math.abs(ContainerFrameCombinedBags.scale - 0.99) < 0.001,
    "combined bag popup Size did not update the live window")
module.config.windowScale, module.config.windowMoved = 1.2, true
module.config.windowX, module.config.windowY = -200, 150
module:Refresh()
assert(ContainerFrameCombinedBags.scale == 1.08
    and ContainerFrameCombinedBags.point[4] == -200
    and ContainerFrameCombinedBags.point[5] == 150,
    "combined bag size or position did not reach the runtime")
UpdateContainerFrameAnchors()
assert(ContainerFrameCombinedBags.point[4] == -200 and ContainerFrameCombinedBags.scale == 1.08,
    "Blizzard's next bag layout displaced the Suite placement")
combat = true
UpdateContainerFrameAnchors()
assert(ContainerFrameCombinedBags.point[4] == -40 and ContainerFrameCombinedBags.scale == 0.9,
    "Suite moved Blizzard's combined bag during combat")
combat = false
context.events.PLAYER_REGEN_ENABLED(module)
assert(ContainerFrameCombinedBags.point[4] == -200 and ContainerFrameCombinedBags.scale == 1.08,
    "combined bag placement was not restored after combat")
module.config.windowMoved, module.config.windowScale = false, 1
module:Refresh()
assert(ContainerFrameCombinedBags.point[4] == -40 and ContainerFrameCombinedBags.scale == 0.9,
    "reset did not restore Blizzard's native bag anchor and size")
bagMode = "0"
context.events.USE_COMBINED_BAGS_CHANGED(module, "USE_COMBINED_BAGS_CHANGED", false)
assert(bagMode == "1", "native split mode was not restored while the module is active")
assert(#fonts == 2 and module.overlays[buttons[1]].label.text == "640"
    and module.overlays[buttons[1]].label.shown, "equipment item level not visible on first open")
assert(module.overlays[buttons[1]].label.flags == "OUTLINE,SLUG"
    and module.overlays[buttons[1]].label.shadowColor[4] == 0,
    "default item level text did not use shadow-free Slug")
local qualityColor = module.overlays[buttons[1]].label.color
assert(qualityColor[1] == 0.7 and qualityColor[2] == 0.5 and qualityColor[3] == 1,
    "item level text lost its quality colour where the deprecated global is missing")
assert(module.overlays[buttons[2]].label == nil, "non-equipment allocated a font")
local firstCalls = levelCalls
local pendingBefore = module.pending
local enumerationsBefore = enumerations
local outerShows = module.overlays[buttons[3]].slotOuter.showCalls
local infoBefore = infoCalls
hooks.UpdateItems()
assert(levelCalls == firstCalls and module.pending == pendingBefore,
    "unchanged bag slots re-read item levels or allocated a new pending set")
assert(enumerations == enumerationsBefore + 1
    and module.overlays[buttons[3]].slotOuter.showCalls == outerShows
    and infoCalls == infoBefore,
    "a native bag refresh without a bag change read its slots again")
infoBefore = infoCalls
module:UpdateVisible()
assert(infoCalls == infoBefore, "repainting an unchanged open bag read its slots again")
local originalHasItem = buttons[1].HasItem
buttons[1].HasItem = function() return "secret" end
infoBefore = infoCalls
BagChanged()
hooks.UpdateItems()
assert(infoCalls == infoBefore + 3,
    "a changed bag must read each of its slots exactly once, occupied, empty or unknown")
buttons[1].HasItem = originalHasItem

items[1] = { hyperlink = "gear-b", itemID = 103, quality = 4 }
BagChanged()
hooks.UpdateItems()
assert(module.overlays[buttons[1]].label.text == "651", "changed slot kept its old item level")
items[3] = { hyperlink = "gear-loading", itemID = 104, quality = 2 }
BagChanged()
hooks.UpdateItems()
assert(requests[104] == 1 and context.events.GET_ITEM_INFO_RECEIVED
    and not module.overlays[buttons[3]].label.shown, "missing item data was not deferred")
hooks.UpdateItems()
assert(requests[104] == 1, "pending item data was requested repeatedly")
items[2] = { hyperlink = "gear-loading", itemID = 104, quality = 2 }
BagChanged()
hooks.UpdateItems()
assert(requests[104] == 1 and #module.pending[104] == 2,
    "duplicate pending items were not grouped under one item request")
levels["gear-loading"] = 599
infoBefore, enumerationsBefore = infoCalls, enumerations
context.events.GET_ITEM_INFO_RECEIVED(module, "GET_ITEM_INFO_RECEIVED", 104, true)
assert(module.overlays[buttons[3]].label.text == "599"
    and module.overlays[buttons[3]].label.shown
    and module.overlays[buttons[2]].label.text == "599"
    and module.overlays[buttons[2]].label.shown
    and not context.events.GET_ITEM_INFO_RECEIVED
    and infoCalls == infoBefore and enumerations == enumerationsBefore,
    "item data completion read slots again, rescanned the bag or missed a duplicate item")
items[2] = { hyperlink = "food", itemID = 102, quality = 1 }
BagChanged()
hooks.UpdateItems()
items[3] = { hyperlink = "gear-vanished", itemID = 105, quality = 2 }
BagChanged()
hooks.UpdateItems()
assert(requests[105] == 1 and bagsPrivate.ItemLoads.Loading(module.loads, 105), "new missing item data was not requested")
items[3] = nil
BagChanged()
hooks.UpdateItems()
assert(not bagsPrivate.ItemLoads.Loading(module.loads, 105) and not context.events.GET_ITEM_INFO_RECEIVED,
    "a removed item left a stale request or item event")
items[3] = { hyperlink = "gear-vanished", itemID = 105, quality = 2 }
BagChanged()
hooks.UpdateItems()
assert(requests[105] == 2, "a returning item could not request its missing data again")
items[3] = nil
BagChanged()
hooks.UpdateItems()
-- A failed load (success false) is not asked again at once: the client
-- would answer each request with another failure. The next opening retries.
items[3] = { hyperlink = "gear-broken", itemID = 106, quality = 2 }
BagChanged()
hooks.UpdateItems()
assert(requests[106] == 1 and module.pending[106], "missing item data was not requested")
context.events.GET_ITEM_INFO_RECEIVED(module, "GET_ITEM_INFO_RECEIVED", 106, false)
assert(requests[106] == 1 and not module.pending[106], "a failed item load was requested again at once")
hooks.UpdateItems()
BagChanged()
hooks.UpdateItems()
assert(requests[106] == 1 and not context.events.GET_ITEM_INFO_RECEIVED,
    "a bag refresh retried a failed item load")
hooks.OnShow()
assert(requests[106] == 2, "opening the bag did not retry a failed item load")
items[3] = nil
BagChanged()
hooks.UpdateItems()

module.config.itemLevelSize = 15
module:Refresh()
assert(module.overlays[buttons[1]].label.size == 15, "font setting did not refresh")
-- Every text setting of the catalog's item level section repaints the
-- labels, without a hand-kept key list.
do
    local switches = { showItemLevel = true, showBindBadge = true, showBankItemLevel = true }
    local checked = 0
    for _, rule in ipairs(state.SuiteCatalog.bags.controls) do
        if rule.section == "itemLevels" and not switches[rule.key] then
            local previous, style = module.config[rule.key], module.labelStyle
            local kind, changed = type(rule.default), "changed"
            if kind == "number" then changed = (previous or rule.default) + 1
            elseif kind == "boolean" then changed = not previous end
            module.config[rule.key] = changed
            module:Refresh()
            assert(module.labelStyle == style + 1, rule.key .. " did not repaint the item level text")
            module.config[rule.key] = previous
            module:Refresh()
            checked = checked + 1
        end
    end
    assert(checked >= 8, "the item level section lost its text settings")
end
module.config.fontOutline, module.config.fontRendering = 2, 2
module.config.fontShadow, module.config.fontShadowOpacity, module.config.fontShadowDistance = true, 70, 2
module:Refresh()
local levelLabel = module.overlays[buttons[1]].label
assert(levelLabel.flags == "THICKOUTLINE" and levelLabel.shadowColor[4] == 0.7
    and levelLabel.shadowOffset[1] == 2, "item level text effects did not refresh")
module.config.fontRendering = 3
module:Refresh()
assert(levelLabel.flags == "OUTLINE,SLUG" and levelLabel.shadowColor[4] == 0,
    "Slug item level text retained a shadow")
module.config.showItemLevel = false
module:Refresh()
assert(not module.overlays[buttons[1]].label.shown, "turning labels off left text visible")
local hideCalls = module.overlays[buttons[1]].label.hideCalls
local disabledOverlayInfoCalls = infoCalls
hooks.UpdateItems()
assert(module.overlays[buttons[1]].label.hideCalls == hideCalls,
    "disabled item levels kept repainting hidden labels on bag updates")
assert(infoCalls == disabledOverlayInfoCalls,
    "bag updates fetched item data with both overlays disabled")
module.config.showItemLevel = true
module:Refresh()
assert(module.overlays[buttons[1]].label.shown, "turning labels on did not repaint")
items[1] = { hyperlink = "gear-a", itemID = 101, quality = 4, isBound = false }
BagChanged()
module.config.showBindBadge = true
module:Refresh()
assert(module.overlays[buttons[1]].bindBadge and module.overlays[buttons[1]].bindBadge.text == "BoE"
    and module.overlays[buttons[1]].bindBadge.shown
    and not module.overlays[buttons[2]].bindBadge,
    "bind badges did not distinguish equipment from other items")
items[1].isBound = true
BagChanged()
hooks.UpdateItems()
assert(not module.overlays[buttons[1]].bindBadge.shown,
    "already-bound BoE item kept a misleading BoE badge")
items[1].isBound = false
BagChanged()
hooks.UpdateItems()
assert(module.overlays[buttons[1]].bindBadge.shown,
    "unbound BoE badge did not return")
module.config.showItemLevel = false
module:Refresh()
assert(module.overlays[buttons[1]].bindBadge.shown
    and not module.overlays[buttons[1]].label.shown,
    "the bind badge depended on the item-level switch")
module.config.showBindBadge = false
module:Refresh()
assert(not module.overlays[buttons[1]].bindBadge.shown,
    "turning bind badges off left the badge visible")
disabledOverlayInfoCalls = infoCalls
hooks.UpdateItems()
assert(infoCalls == disabledOverlayInfoCalls,
    "disabling both overlays did not restore the item-free bag update path")
module.config.showBindBadge = true
module:Refresh()
assert(module.overlays[buttons[1]].bindBadge.shown,
    "re-enabling bind badges did not repaint")
items[1] = { hyperlink = "gear-b", itemID = 101, quality = 4, isBound = false }
BagChanged()
hooks.UpdateItems()
assert(module.overlays[buttons[1]].bindBadge.text == "WuE",
    "reused bag button kept a stale binding badge")
-- Both account bindings (ToWoWAccount, ToBnetAccount) are Warbound, bound or not.
for _, link in ipairs({ "gear-warbound", "gear-account" }) do
    items[1] = { hyperlink = link, itemID = 101, quality = 4, isBound = true }
    BagChanged()
    hooks.UpdateItems()
    assert(module.overlays[buttons[1]].bindBadge.text == "WB" and module.overlays[buttons[1]].bindBadge.shown,
        link .. " showed no Warbound badge")
end
items[1] = { hyperlink = "gear-a", itemID = 101, quality = 4, isBound = false }
BagChanged()
module.config.showItemLevel = true
module:Refresh()
buttons[4] = {
    emptyBackgroundAtlas = "bags-item-slot64",
    ItemSlotBackground = VisualFrame(),
    GetBagID = function() return 0 end,
    GetID = function() return 4 end,
    HasItem = function() return true end,
    SetItemButtonTexture = buttons[1].SetItemButtonTexture,
}
items[4] = { hyperlink = "gear-a", itemID = 101, quality = 4 }
BagChanged()
combat = true
hooks.UpdateItems()
assert(queued > 0 and not module.overlays[buttons[4]].label, "combat created a new label on a native button")
combat = false
module:Refresh()
assert(module.overlays[buttons[4]].label.shown, "queued label was not created after combat")
-- A slot emptied in combat (a used potion): the Suite surface lifts over
-- Blizzard's empty-slot atlas at once, its own textures only; an item that
-- arrives puts it back below the icon.
local food = items[2]
items[2] = nil
BagChanged()
combat = true
hooks.UpdateItems()
local foodSlot = module.overlays[buttons[2]]
assert(OverIcon(foodSlot) and buttons[2].emptyBackgroundAtlas == "bags-item-slot64",
    "a slot emptied in combat kept showing Blizzard's empty-slot artwork")
combat = false
items[2] = food
BagChanged()
hooks.UpdateItems()
assert(BelowIcon(foodSlot), "an item that arrived stayed under the Suite surface")
items[3] = nil
BagChanged()
module.active = false
for i = #submoduleCalls, 1, -1 do submoduleCalls[i] = nil end
module:Disable()
assert(Ran(STOP_ORDER), "a stop did not run the sub-modules in Bags.lua's order: " .. table.concat(submoduleCalls, ", "))
bagMode = context.before
assert(not combinedStyle.shell.shown and not reagentStyle.shell.shown
    and not textures[1].shown and not textures[10].shown
    and not combinedHandle.shown and not reagentHandle.shown,
    "disabling bags left the Suite window surfaces visible")
context:Release()
assert(ContainerFrameCombinedBags.Bg.alpha == 1 and ContainerFrameCombinedBags.NineSlice.alpha == 1
    and ContainerFrame6.Bg.alpha == 1 and ContainerFrame6.NineSlice.alpha == 1,
    "disabling bags did not restore native bag art")
for _, frame in ipairs({ ContainerFrameCombinedBags, ContainerFrame6 }) do
    assert(frame.PortraitContainer.alpha == 1 and frame.PortraitButton.alpha == 1
        and frame.PortraitButton.mouseEnabled
        and select(4, frame.TitleContainer:GetPoint(1)) == 35,
        "disabling bags did not restore Blizzard's bag portraits and title position")
end
assert(buttons[3].emptyBackgroundAtlas == "bags-item-slot64"
    and buttons[3].textureCalls == nil
    and buttons[3].ItemSlotBackground.alpha == 1
    and reagentButton.emptyBackgroundAtlas == "bags-item-slot64"
    and not module.overlays[buttons[3]].slotOuter.shown
    and not module.overlays[reagentButton].slotOuter.shown,
    "disabling bags did not restore the native empty-slot visuals")
assert(bagMode == "0" and not module.overlays[buttons[1]].label.shown
    and not module.overlays[buttons[3]].label.shown, "disable left bag labels visible")
assert(ContainerFrameCombinedBags.point[4] == -40 and ContainerFrameCombinedBags.scale == 0.9,
    "disabling the module did not leave Blizzard's native bag layout")
hooks.UpdateItems()
assert(not module.overlays[buttons[1]].label.shown, "inactive hook repainted labels")
local textureCountBeforeReenable = #textures
module.active = true
module:Enable()
assert(#textures == textureCountBeforeReenable
    and buttons[3].emptyBackgroundAtlas == "bags-item-slot64"
    and buttons[3].ItemSlotBackground.alpha == 0
    and module.overlays[buttons[3]].slotOuter.shown and OverIcon(module.overlays[buttons[3]]),
    "re-enabling bags did not reapply the slot styling without new textures")
module.active = false
module:Disable()
context:Release()

-- The shared Suite Edit Mode bridge must commit custom placement and let
-- Reset position return this window to Blizzard's own container anchor.
do
    local registered
    MSUF_EditModeAPI = {
        RegisterElement = function(_, element) registered = element; return true end,
        IsActive = function() return false end,
    }
    local values = { windowX = -40, windowY = 32, windowMoved = false, windowScale = 1 }
    local bridge = {
        states = { bags = { active = true } },
        catalog = { bags = { rules = {
            windowX = { default = 0, min = -4000, max = 4000 },
            windowY = { default = 0, min = -3000, max = 3000 },
            windowMoved = { default = false }, windowScale = { default = 1 },
        } } },
        Public = function() return true end,
        Text = function(value) return value end,
        Config = function() return values end,
        SetMany = function(_, changes)
            for key, value in pairs(changes) do values[key] = value end
            return true
        end,
        Set = function(_, key, value) values[key] = value; return true end,
    }
    -- Readable-number helpers as defined by MSUF_Suite_Modules/Runtime.lua.
    bridge.Number = function(value) return bridge.Public(value) and type(value) == "number" and value == value end
    bridge.Finite = function(value) return bridge.Number(value) and value > -math.huge and value < math.huge end
    assert(loadfile(root .. "/MSUF_Suite_Modules/EditMode.lua"))("MSUF_Suite_Modules", {
        NS = { DB = {}, Safety = { IsForbidden = function() return false end },
            IsCombatLocked = function() return false end },
        Suite = bridge,
    })
    local editFrame = {
        GetScale = function() return 1 end,
        ClearAllPoints = function() end,
        SetPoint = function() end,
    }
    assert(bridge.RegisterOwnedMover("bags", "combined", {
        label = "Combined bags", getFrame = function() return editFrame end,
        xKey = "windowX", yKey = "windowY", point = "BOTTOMRIGHT",
        moveValues = { windowMoved = true }, resetKeys = { "windowMoved" },
        historyKeys = { "windowMoved", "windowScale" },
    }))
    assert(#registered.extraControls == 2 and registered.extraControls[1].id == "windowX"
        and registered.extraControls[2].id == "windowY",
        "all registered Suite movers need exact X/Y popup controls")
    local before = registered.captureState()
    assert(before.values.windowMoved == false and before.values.windowScale == 1)
    assert(registered.movePosition({ state = before, deltaX = 10, deltaY = -5, phase = "commit" })
        and values.windowX == -30 and values.windowY == 27 and values.windowMoved == true,
        "bag window Edit Mode move did not enable persistent custom position")
    assert(registered.resetPosition() and values.windowMoved == false
        and values.windowX == 0 and values.windowY == 0,
        "bag window Reset position did not return to native placement")
    assert(registered.restoreState(before) and values.windowX == -40
        and values.windowY == 32 and values.windowMoved == false,
        "bag window Edit Mode undo did not restore position ownership")

    -- A capture hook moves only the drag start: undo restores the saved
    -- offsets, never the live (native) anchor the drag started from.
    local liveRegistered
    registered = nil
    assert(bridge.RegisterOwnedMover("bags", "live", {
        label = "Live bag", getFrame = function() return editFrame end,
        xKey = "windowX", yKey = "windowY", point = "BOTTOMRIGHT",
        capture = function(origin) origin.windowX, origin.windowY = -500, 90 end,
        moveValues = { windowMoved = true },
    }))
    liveRegistered = registered
    values.windowX, values.windowY = 0, 0
    values.windowMoved = false
    assert(liveRegistered.extraControls[1].get() == -500 and liveRegistered.extraControls[2].get() == 90,
        "an unmoved native bag must show its live position in the popup")
    assert(liveRegistered.extraControls[1].set(-490) and values.windowX == -490
        and values.windowY == 90 and values.windowMoved,
        "first exact X edit jumped to stale saved Y or left native placement active")
    values.windowX, values.windowY, values.windowMoved = 0, 0, false
    local start = liveRegistered.captureState()
    assert(liveRegistered.movePosition({ state = start, deltaX = 10, deltaY = -5, phase = "commit" })
        and values.windowX == -490 and values.windowY == 85,
        "a capture hook did not move the drag start")
    assert(liveRegistered.restoreState(start) and values.windowX == 0 and values.windowY == 0,
        "undo wrote the live drag start into the profile instead of the saved offsets")

    -- Every owned frame gets X/Y beside its module-specific size control.
    local sizeControl = { id = "windowScale", label = "Scale %", kind = "number",
        min = 0.5, max = 2, step = 0.1,
        get = function() return values.windowScale end,
        set = function(value) return bridge.Set("bags", "windowScale", value) end }
    assert(bridge.RegisterOwnedMover("bags", "quick", {
        label = "Quick frame", getFrame = function() return editFrame end,
        xKey = "windowX", yKey = "windowY", point = "CENTER",
        historyKeys = { "windowScale" },
        extraControls = { sizeControl },
    }))
    assert(#registered.extraControls == 3 and registered.extraControls[1].label == "X"
        and registered.extraControls[2].label == "Y"
        and registered.extraControls[3] == sizeControl,
        "editable coordinates were not inserted before size controls")
    local quickBefore = registered.captureState()
    assert(registered.extraControls[1].set(45) and registered.extraControls[2].set(-28)
        and registered.extraControls[3].set(1.5)
        and values.windowX == 45 and values.windowY == -28 and values.windowScale == 1.5,
        "popup controls did not write the frame's profile values")
    assert(registered.restoreState(quickBefore) and values.windowX == 0
        and values.windowY == 0 and values.windowScale == 1,
        "popup coordinate and size edits were not undoable")
end
-- Retail and WoW Forever always have these APIs: Bags calls them directly
-- instead of guarding against a client that lacks them.
do
    local file = assert(io.open(root .. "/MSUF_Suite_Bags/Bags.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, name in ipairs({ "GetMoney", "UnitGUID", "IsShiftKeyDown", "GetCursorPosition",
        "UpdateContainerFrameAnchors", "RequestLoadItemDataByID", "GetItemQualityColor", "SetWordWrap",
        "IsMenuOpen", "SetMenuOpen", "SetTitleOffsets", "GetScaledRect", "GetEffectiveScale", "IsMovable" }) do
        assert(not source:find("type%([%w_%.]*" .. name .. "%)"), name .. " is guarded as if a client lacked it")
    end
    -- GameTooltip and the shared runtime's mover refresh always exist, and
    -- CVars are read through C_CVar like everywhere else in the Suite.
    local code = source:gsub("%-%-[^\n]*", "")
    local probe = code:match("(GameTooltip) then") or code:match("(S%.RefreshOwnedMovers) then")
        or code:match("[^_.](GetCVar)%(")
    assert(not probe, "Bags probes or bypasses " .. tostring(probe))
end
-- The native Retail bank pools item buttons. Exercise its post-refresh and
-- search hooks without creating a second bank window or touching item clicks.
do
    state.Safety = { IsForbidden = function() return false end }
    local bankHooks = {}
    local bankButtons, bankPanel = {}, nil
    BankPanelItemButtonMixin = {
        Refresh = function(self) self.itemInfo = items[self.slot] end,
        IsShown = function() return true end,
        GetBankTabID = function() return 7 end,
        GetContainerSlotID = function(self) return self.slot end,
    }
    BankPanelMixin = {
        UpdateSearchResults = function() end,
        GenerateItemSlotsForSelectedTab = function()
            for i = 1, #bankButtons do bankButtons[i]:Refresh() end
        end,
        OnShow = function(self) self:GenerateItemSlotsForSelectedTab() end,
    }
    -- XML mixins copy methods to each instance. Replacing a method on the
    -- global mixin later does not replace the panel/button's copied method.
    local function CopyMethods(target, mixin)
        for key, value in pairs(mixin) do target[key] = value end
        return target
    end
    local function BankButton(slot)
        local button = CopyMethods({ bankButton = true, slot = slot }, BankPanelItemButtonMixin)
        button:Refresh()
        return button
    end
    local nativeHook = hooksecurefunc
    hooksecurefunc = function(target, name, callback)
        if target == BankPanelItemButtonMixin or target == BankPanelMixin
            or target == bankPanel or type(target) == "table" and target.bankButton then
            bankHooks[target] = bankHooks[target] or {}
            bankHooks[target][name] = (bankHooks[target][name] or 0) + 1
            local original = assert(target[name])
            target[name] = function(...)
                original(...)
                callback(...)
            end
        else
            nativeHook(target, name, callback)
        end
    end
    items[4] = { hyperlink = "gear-a", itemID = 104, quality = 4 }
    items[5] = { hyperlink = "pending-bank", itemID = 1105, quality = 3 }
    items[6] = { hyperlink = "food", itemID = 106, quality = 1 }
    for slot = 4, 6 do
        bankButtons[#bankButtons + 1] = BankButton(slot)
    end
    bankPanel = CopyMethods({
        IsShown = function() return true end,
        HookScript = function(self, name, callback)
            assert(name == "OnShow" and not self.onShowHook, "bank show hook was duplicated")
            self.onShowHook = callback
        end,
        EnumerateValidItems = function()
            local index = 0
            return function() index = index + 1; return bankButtons[index] end
        end,
    }, BankPanelMixin)
    BankFrame = { BankPanel = bankPanel, IsShown = function() return true end }
    module.config.showBankItemLevel = true
    module.active = true
    module:Enable()
    assert(bankHooks[bankPanel] and bankHooks[bankPanel].UpdateSearchResults == 1
        and bankHooks[bankPanel].GenerateItemSlotsForSelectedTab == 1 and bankPanel.onShowHook
        and not bankHooks[BankPanelMixin] and not bankHooks[BankPanelItemButtonMixin]
        and module.bankOverlays[bankButtons[1]].label.text == "640"
        and module.bankOverlays[bankButtons[1]].label.shown
        and not module.bankOverlays[bankButtons[3]].label,
        "native bank equipment levels did not appear without touching non-gear")
    local calls = levelCalls
    bankButtons[1]:Refresh()
    assert(levelCalls == calls, "unchanged bank item repeated its level lookup")
    assert(requests[1105] == 1 and context.events.GET_ITEM_INFO_RECEIVED,
        "uncached bank item was not requested once through the existing item event")
    levels["pending-bank"] = 666
    context.events.GET_ITEM_INFO_RECEIVED(module, "GET_ITEM_INFO_RECEIVED", 1105, true)
    assert(module.bankOverlays[bankButtons[2]].label.text == "666"
        and module.bankOverlays[bankButtons[2]].label.shown,
        "loaded bank item did not repaint its own button")
    items[5] = { hyperlink = "pending-fail", itemID = 1106, quality = 3 }
    bankButtons[2]:Refresh()
    assert(requests[1106] == 1 and context.events.GET_ITEM_INFO_RECEIVED,
        "missing bank data was not requested once")
    context.events.GET_ITEM_INFO_RECEIVED(module, "GET_ITEM_INFO_RECEIVED", 1106, false)
    bankButtons[2]:Refresh()
    assert(requests[1106] == 1 and not module.bankOverlays[bankButtons[2]].label.shown,
        "failed item lookup looped or displayed stale level")
    items[4].isFiltered = true
    bankPanel:UpdateSearchResults()
    assert(not module.bankOverlays[bankButtons[1]].label.shown,
        "bank search did not hide the filtered item-level label")
    items[4].isFiltered = nil
    bankPanel:UpdateSearchResults()
    assert(module.bankOverlays[bankButtons[1]].label.shown,
        "clearing bank search did not restore the label")
    items[4] = { hyperlink = "gear-b", itemID = 1104, quality = 4 }
    bankPanel:GenerateItemSlotsForSelectedTab()
    assert(module.bankOverlays[bankButtons[1]].label.text == "651",
        "tab change left the reused bank button's previous item level")
    items[7] = { hyperlink = "gear-a", itemID = 1107, quality = 4 }
    bankButtons[4] = BankButton(7)
    bankPanel:GenerateItemSlotsForSelectedTab()
    assert(module.bankOverlays[bankButtons[4]].label.text == "640"
        and module.bankOverlays[bankButtons[4]].label.shown,
        "new pooled bank button did not receive an overlay after generation")
    items[7] = { hyperlink = "gear-b", itemID = 1108, quality = 4 }
    bankButtons[4]:Refresh()
    assert(module.bankOverlays[bankButtons[4]].label.text == "651",
        "new pooled button did not hook later native refreshes")
    bankPanel:OnShow()
    bankPanel.onShowHook(bankPanel)
    module:ApplyBankLevels()
    for i = 1, #bankButtons do
        assert(bankHooks[bankButtons[i]].Refresh == 1, "bank button refresh hook was duplicated")
    end
    module.config.showBankItemLevel = false
    module:Refresh()
    assert(not module.bankOverlays[bankButtons[1]].label.shown
        and not context.events.BANKFRAME_OPENED,
        "disabled bank levels retained a label or bank event")
    calls = levelCalls
    bankButtons[1]:Refresh()
    bankPanel:GenerateItemSlotsForSelectedTab()
    bankPanel:UpdateSearchResults()
    assert(not module.bankOverlays[bankButtons[1]].label.shown,
        "permanent native hook painted while bank levels were disabled")
    assert(levelCalls == calls, "disabled bank levels performed item-level lookups")
    module.active = false
    module:Disable()
    BankFrame = nil
    hooksecurefunc = nativeHook
end
print("Suite bags: window styling, native bag layout, item levels, cache, and disable passed")

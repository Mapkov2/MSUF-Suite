local root = assert(arg[1])
local card, outline, buffCard, buffOutline, combatEvents, timer
local callbacks = {}
local queued, reads, combat, spells, actionTextures = 0, 0, false, 0, 0
local function Noop() end
local function Widget()
    local w = { scripts = {}, events = {} }
    function w:SetScript(key, cb) self.scripts[key] = cb end
    function w:HookScript(key, cb) self.scripts[key] = cb end
    function w:RegisterEvent(event) self.events[event] = true end
    function w:UnregisterAllEvents() self.events = {} end
    function w:SetText(value) self.text, self.textWrites = value, (self.textWrites or 0) + 1 end
    function w:SetTexture(value) self.texture, self.textureWrites = value, (self.textureWrites or 0) + 1 end
    function w:SetPoint(...) self.anchor = { ... } end
    function w:GetPoint() return unpack(self.anchor or {}) end
    function w:GetTextColor() return 1, 1, 1, 1 end
    function w:SetHeight(value) self.height, self.heightWrites = value, (self.heightWrites or 0) + 1 end
    function w:GetHeight() return self.height or 90 end
    function w:IsShown() return self.shown == true end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:SetShown(value) self.shown = not not value end
    function w:GetEffectiveScale() return 1 end
    function w:GetFrameLevel() return self.frameLevel or 4 end
    function w:SetAlpha(alpha) self.alpha = alpha end
    function w:GetAlpha() return self.alpha or 1 end
    w.SetTexCoord, w.SetSize, w.SetJustifyH, w.SetMaxLines, w.SetWordWrap = Noop, Noop, Noop, Noop, Noop
    w.SetTextColor, w.EnableMouse, w.SetFrameStrata, w.ClearAllPoints, w.SetClampedToScreen = Noop, Noop, Noop, Noop, Noop
    w.SetWidth, w.SetAllPoints = Noop, Noop
    function w:SetFrameLevel(level) self.frameLevel = level end
    function w:SetColorTexture(...) self.color = { ... } end
    function w:SetVertexColor(...) self.color = { ... } end
    function w:CreateFontString()
        local text = Widget()
        self.fontStrings = self.fontStrings or {}
        self.fontStrings[#self.fontStrings + 1] = text
        return text
    end
    function w:CreateTexture()
        local texture = Widget()
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end
    return w
end
UIParent, GameTooltip = Widget(), Widget()
BuffFrameTooltip = Widget()
GameTooltipTextLeft1 = Widget()
function GameTooltipTextLeft1:GetText() return "Current title" end
function GameTooltipTextLeft1:GetTop() return 800 end
function GameTooltipTextLeft1:GetBottom() return 782 end
function GameTooltipTextLeft1:GetLeft() return 60 end
function UIParent:GetTop() return 1000 end
function GameTooltip:GetTop() return 809 end
function GameTooltip:GetWidth() return 208 end
function GameTooltip:SetAlpha() error("The card wrote to the shared tooltip") end
function GameTooltip:GetUnit() error("The card tried to resolve a unit token") end
GameTooltip:Show()
function GameTooltip:GetPrimaryTooltipData() return self.current end
function GameTooltip:GetProcessingTooltipInfo() return self.processing end
function GameTooltip:GetPrimaryTooltipInfo() return self.primaryInfo end
function GameTooltip:GetOwner() return self.owner end
BuffFrameTooltip.GetPrimaryTooltipData = GameTooltip.GetPrimaryTooltipData
BuffFrameTooltip.GetWidth, BuffFrameTooltip.GetTop = GameTooltip.GetWidth, GameTooltip.GetTop
BuffFrameTooltip.GetOwner = GameTooltip.GetOwner
BuffFrameTooltipTextLeft1 = GameTooltipTextLeft1
Enum = { TooltipDataType = { Item = 1, Spell = 2, Unit = 3, Object = 4, Quest = 23, UnitAura = 7, PetAction = 11, Totem = 18, Flyout = 22, Macro = 25 } }
TooltipComparisonManager = {
    AnchorShoppingTooltips = function() end,
}
function hooksecurefunc(target, method, handler)
    assert(target == TooltipComparisonManager and method == "AnchorShoppingTooltips",
        "the comparison fix hooked a shared tooltip method")
    local original = target[method]
    target[method] = function(self, ...)
        original(self, ...)
        handler(self, ...)
    end
end
TooltipDataProcessor = { AddTooltipPostCall = function(typ, cb)
    assert(type(typ) == "number" and not callbacks[typ], "duplicate or global tooltip registration")
    callbacks[typ] = cb
end }
C_Item = {
    GetItemInfo = function(link)
        reads = reads + 1
        return link, nil, 3, 20, 1, "Armor", "Cloth", nil, nil, 123
    end,
    GetDetailedItemLevelInfo = function() return 45 end,
    GetItemQualityColor = function() return .1, .4, 1 end,
}
C_Spell = { GetSpellTexture = function(id)
    spells = spells + 1
    return id == 117 and 135847 or 135846
end }
C_ActionBar = { GetActionTexture = function(slot)
    assert(slot == 37, "the icon lookup did not use its native action slot")
    actionTextures = actionTextures + 1
    return 135849
end }
local timers = {}
C_Timer = { After = function(_, job)
    queued, timer = queued + 1, true
    timers[#timers + 1] = job
end }
local function Flush()
    local jobs = timers
    timers, timer = {}, nil
    for index = 1, #jobs do jobs[index]() end
end
CreateFrame = function(_, _, parent)
    local frame = Widget()
    if parent == GameTooltip then
        if not card then card = frame else outline = frame end
    elseif parent == BuffFrameTooltip then
        if not buffCard then buffCard = frame else buffOutline = frame end
    elseif not parent then combatEvents = frame end
    return frame
end
canaccesstable = function(value) return not value.restricted end
local listener
local corePanel, coreFill, coreAccent = Widget(), Widget(), Widget()
corePanel.name, corePanel.line2 = Widget(), Widget()
corePanel.name:SetPoint("TOPLEFT", 8, -8)
corePanel.line2:SetPoint("TOPLEFT", corePanel.name, "BOTTOMLEFT", 0, -2)
function corePanel:CreateTexture(_, _, _, subLevel)
    return subLevel and coreFill or coreAccent
end
local coreStyler, deferredCoreStyle
local textAPI = { Text = function(text) return text end, HostBridge = {
    SetUnitFrameTooltipPanelStyler = function(styler)
        coreStyler = styler
        return true
    end,
} }
local vitals = { Refresh = function() return false end }
local NS = {
    TooltipVitals = vitals,
    Client = { isForever = false, isMainline = true },
    DB = { enabled = true, theme = { itemTooltipStyle = "compact" } },
    SuiteCore = function() return textAPI end,
    Safety = {
        Dispatch = function(callback, ...) return callback(...) end,
        HasMethod = function(target, key) return target and type(target[key]) == "function" end,
        Public = function(value) return type(value) ~= "table" or not value.secret end,
        Field = function(target, key) return target[key] end,
        IsForbidden = function(tip) return tip.forbidden end,
        CanCreateRegions = function(tip) return not tip.forbidden and not (combat and tip.protected) end,
        Read = function(tip, key)
            local value = tip and tip[key] and tip[key](tip)
            if type(value) ~= "table" or not value.secret then return value end
        end,
        ReadColor = function() return 1, .5, .2 end,
        Call = function(tip, key) if tip[key] then return tip[key](tip) end end,
    },
    IsCombatLocked = function() return combat end,
    CombatGate = { RunOrDefer = function(_, job) deferredCoreStyle = job end },
    Registry = { AddListener = function(_, cb) listener = cb end,
        NotifyListeners = function(domain) listener(nil, domain) end },
    Theme = { GetColor = function() return 1, 1, 1, 1 end },
    LabelStyle = { Apply = Noop },
    Surface = { Attach = Noop, MediaPath = Noop, SetMediaTexture = Noop },
}
local core = { CatalogBuild = { Module = Noop, Add = Noop } }
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Tooltips.lua"))("MSUF_Suite", core)
NS.Defaults = { theme = core.TooltipAppearance.defaults }
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, field in pairs(value) do result[key] = Copy(field) end
    return result
end
NS.CopyValue = Copy
assert(loadfile(root .. "/MSUF_Suite_Tooltips/TooltipChrome.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Tooltips/TooltipCardSettings.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Tooltips/ItemTooltipCard.lua"))("MSUF_Suite_Skin", NS)
NS.ItemTooltipCard.Refresh()
assert(not next(callbacks) and not timer and not card, "compact style registered item callbacks")
local API = NS.ItemTooltipCard
GameTooltip:Hide()
GameTooltip.current = { type = 1, hyperlink = "item:1" }
assert(API.SetTypeStyle("item", "custom"))
local function Build(kind, primary, source)
    GameTooltip.scripts.OnTooltipCleared()
    GameTooltip.current = primary
    GameTooltip.primaryInfo = source or {}
    GameTooltip.processing = GameTooltip.primaryInfo
    callbacks[kind](GameTooltip, primary)
end
Build(1, GameTooltip.current)
assert(card:IsShown() and outline:IsShown() and reads == 1 and not timer,
    "the first item build waited for the next frame")
GameTooltip:Show()
GameTooltip.scripts.OnShow()
assert(card.anchor[1] == "BOTTOMRIGHT" and card.anchor[2] == GameTooltip and card.anchor[3] == "TOPRIGHT"
    and card.anchor[4] == 0 and card.anchor[5] == -28 and reads == 1 and not timer,
    "the card does not follow the native tooltip edges")
for _ = 1, 30 do
    GameTooltip.scripts.OnTooltipCleared()
    assert(card:IsShown() and outline:IsShown(), "ClearLines dropped the displayed header during a rebuild")
    callbacks[1](GameTooltip, GameTooltip.current)
    assert(card:IsShown(), "an item rebuild showed a native frame between cards")
end
assert(reads == 1 and queued == 1, "unchanged rebuilds fetched metadata or queued redundant work")
Flush()
function GameTooltip:GetWidth() return 0 end
GameTooltip.scripts.OnSizeChanged()
assert(card:IsShown() and timer, "a transient native width dropped the current header")
function GameTooltip:GetWidth() return 208 end
GameTooltip.scripts.OnSizeChanged()
Flush()
assert(card:IsShown() and reads == 1, "settling the width rebuilt the same item")
GameTooltip.scripts.OnTooltipCleared()
Flush()
assert(not card:IsShown() and not outline:IsShown(), "a clear without replacement retained an old header")
assert(callbacks[7] and callbacks[11] and callbacks[18] and callbacks[22] and callbacks[25],
    "native aura or action tooltip types have no card callback")
Build(7, { type = 7, id = 801 })
assert(not card:IsShown(), "aura took the item card setting")
Build(1, { type = 1, hyperlink = { secret = true } })
assert(card:IsShown() and outline:IsShown() and reads == 1 and not card.textures[1]:IsShown(),
    "restricted item metadata removed the card or caused an item lookup")
Build(2, { type = 2, id = 116 })
assert(not card:IsShown(), "spell inherited the item presentation")
Flush()
assert(API.SetTypeStyle("spell", "custom"))
assert(card:IsShown() and not timer, "the spell waited for the next frame")
GameTooltip:Hide()
GameTooltip.scripts.OnHide()
Build(2, { type = 2, id = 116 })
assert(card:IsShown() and outline:IsShown() and not timer, "the first spell did not paint before the native Show")
GameTooltip:Show()
GameTooltip.scripts.OnShow()
local firstSpellLookup = spells
callbacks[1](GameTooltip, { type = 1, id = 20 })
assert(card:IsShown() and spells == firstSpellLookup and reads == 1, "an appended item replaced a spell title")
Build(1, { type = 1, hyperlink = "item:2" })
assert(card:IsShown() and reads == 2)
Flush()
callbacks[1](Widget(), GameTooltip.current)
assert(not timer, "comparison tooltip scheduled the main item card")
combat = true
Build(1, { type = 1, hyperlink = "item:during-combat" })
assert(reads == 3 and card:IsShown(), "readable combat items lost their styling")
Build(1, { type = 1, restricted = true })
assert(reads == 3 and card:IsShown() and outline:IsShown() and not card.textures[1]:IsShown(),
    "restricted combat item data caused a lookup or dropped the display-only card")
combat = false
Flush()
assert(API.TypeStyle("loot") == "suite" and API.SetTypeStyle("loot", "custom"))
assert(API.SetPreset("detailed") and API.Preset() == "detailed")
assert(API.SetPreset("compact") and API.TypeStyle("item") == "custom" and API.TypeStyle("spell") == "custom"
    and API.TypeStyle("unit") == "suite" and API.TypeStyle("loot") == "custom",
    "reset changed which tooltip kinds use the custom style")
assert(API.SetTypeStyle("unit", "custom"))
assert(coreStyler and not coreFill:IsShown(), "Core delivered a panel before the first hover")
combat, corePanel.protected = true, true
coreStyler(corePanel)
assert(deferredCoreStyle and not coreFill:IsShown(), "a protected Core panel was written during combat")
deferredCoreStyle, corePanel.protected = nil, false
coreStyler(corePanel)
assert(not deferredCoreStyle and coreFill:IsShown() and coreAccent:IsShown() and corePanel:GetHeight() > 90,
    "an unprotected Core panel lost its style on its first combat hover")
local firstCombatHeight, firstCombatAnchor = corePanel:GetHeight(), corePanel.name.anchor[4]
combat = false
coreStyler(corePanel)
assert(corePanel:GetHeight() == firstCombatHeight and corePanel.name.anchor[4] == firstCombatAnchor,
    "first-hover Core title geometry differed between combat states")
Build(3, { type = 3 })
assert(card:IsShown(), "a public unit header was skipped")
local combatTitle = setmetatable({ secret = true }, { __tostring = function() error("formatted a restricted title in Lua") end })
function GameTooltipTextLeft1:GetText() return combatTitle end
callbacks[3](GameTooltip, GameTooltip.current)
local renderedTitle = card.fontStrings[1]
assert(card:IsShown() and outline:IsShown() and rawequal(renderedTitle.text, combatTitle),
    "a protected unit title was not sent straight to the card's text sink")
combat = true
local blockedPrimary = setmetatable({ secret = true }, { __index = function() error("read restricted tooltip data") end })
local beforeSpells = spells
local ownerTexture, ownerReads = 135844, 0
GameTooltip.owner = { Icon = { GetTexture = function()
    ownerReads = ownerReads + 1
    return ownerTexture
end } }
Build(2, blockedPrimary)
local cardIcon = card.textures[1]
assert(card:IsShown() and rawequal(renderedTitle.text, combatTitle) and spells == beforeSpells,
    "opaque action data lost the selected Spell card or queried a private spell ID")
assert(cardIcon:IsShown() and cardIcon.texture == ownerTexture,
    "the restricted spell lost its displayed action button icon")
ownerTexture = 135845
Build(2, { type = 2, id = { secret = true } })
assert(cardIcon:IsShown() and cardIcon.texture == ownerTexture and spells == beforeSpells,
    "a restricted spell ID discarded the new owner's public icon")
GameTooltip.owner.Icon, GameTooltip.owner.icon = nil, GameTooltip.owner.Icon
local protectedTexture = {
    __eq = function() error("compared a restricted texture in Lua") end,
    __tostring = function() error("formatted a restricted texture in Lua") end,
}
ownerTexture = setmetatable({ secret = true }, protectedTexture)
Build(2, blockedPrimary)
assert(cardIcon:IsShown() and rawequal(cardIcon.texture, ownerTexture),
    "the action button's display-only icon was not forwarded to the card texture")
local titleWrites, iconWrites, heightWrites = renderedTitle.textWrites, cardIcon.textureWrites, card.heightWrites
local beforeOwnerReads = ownerReads
for _ = 1, 15 do GameTooltip.scripts.OnSizeChanged() end
assert(renderedTitle.textWrites == titleWrites and cardIcon.textureWrites == iconWrites
    and spells == beforeSpells and ownerReads == beforeOwnerReads,
    "an unchanged layout re-rendered or fetched the restricted icon")
GameTooltip.processing = {}
callbacks[1](GameTooltip, { secret = true })
assert(card:IsShown() and renderedTitle.textWrites == titleWrites and cardIcon.textureWrites == iconWrites,
    "appended restricted data overwrote the primary action tooltip")
local nextTitle = { secret = true }
combatTitle = nextTitle
ownerTexture = setmetatable({ secret = true }, protectedTexture)
Build(2, blockedPrimary)
assert(card:IsShown() and rawequal(renderedTitle.text, nextTitle) and renderedTitle.textWrites == titleWrites + 1,
    "a new protected title was not displayed on exactly one primary build")
assert(rawequal(cardIcon.texture, ownerTexture) and cardIcon.textureWrites == iconWrites + 1
    and card.heightWrites == heightWrites,
    "the next primary build did not replace the display-only icon without rebuilding the header")
combat = false
assert(API.Set("icon", false) and not cardIcon:IsShown() and cardIcon.texture == nil,
    "the icon option did not hide the slot or clear its protected texture")
assert(API.Set("icon", true) and cardIcon:IsShown() and rawequal(cardIcon.texture, ownerTexture))
GameTooltip.scripts.OnHide()
assert(not card:IsShown() and renderedTitle.text == "" and cardIcon.texture == nil,
    "hiding the card retained its protected render values")
GameTooltip.owner.icon.IsShown = function() return false end
Build(2, { type = 2, id = { secret = true } })
assert(card:IsShown() and not cardIcon:IsShown() and cardIcon.texture == nil,
    "a spell without a readable ID or visible icon borrowed the previous tooltip's texture")
GameTooltip.owner = nil
combat = true
local actionSource = { getterName = "GetAction", getterArgs = { 37 } }
Build(2, blockedPrimary, actionSource)
assert(cardIcon:IsShown() and cardIcon.texture == 135849 and actionTextures == 1 and spells == beforeSpells,
    "the GCD rebuild did not resolve the action-slot icon exactly once")
local beforeActionTextures = actionTextures
for _ = 1, 15 do GameTooltip.scripts.OnSizeChanged() end
assert(actionTextures == beforeActionTextures, "layout-only updates requeried the native action slot")
GameTooltip.owner = { Icon = { GetTexture = function() return ownerTexture end } }
Build(2, blockedPrimary, actionSource)
assert(cardIcon.texture == 135849 and actionTextures == beforeActionTextures + 1,
    "an opaque owner icon prevented the public action-slot fallback")
GameTooltip.owner = nil
beforeActionTextures = actionTextures
Build(2, { type = 2, id = 116 }, { getterName = "GetAction", getterArgs = { { secret = true } } })
assert(cardIcon:IsShown() and cardIcon.texture == 135846 and actionTextures == beforeActionTextures,
    "a private action slot was passed to the public action API")
local beforeSourceLookup = spells
Build(2, blockedPrimary, { getterName = "GetSpellByID", getterArgs = { 117 } })
assert(cardIcon:IsShown() and cardIcon.texture == 135847 and spells == beforeSourceLookup + 1,
    "the tooltip did not recover the icon from its original spell argument")
beforeSourceLookup = spells
GameTooltip.owner = { Icon = { GetTexture = function() return 135848 end } }
Build(2, { type = 2, id = 116 }, { getterName = "GetSpellByID", getterArgs = { 116 } })
assert(cardIcon:IsShown() and cardIcon.texture == 135848 and spells == beforeSourceLookup,
    "native cooldown texture was ignored whenever the payload had a readable spell ID")
Build(2, blockedPrimary, { getterName = "GetSpellByID", getterArgs = { { secret = true } } })
assert(cardIcon:IsShown() and cardIcon.texture == 135848 and spells == beforeSourceLookup,
    "the displayed cooldown icon was removed by a restricted rebuild")
GameTooltip.owner = nil
combat = false
function GameTooltipTextLeft1:GetText() return "Current title" end
assert(API.SetOffsets(16, -1) and API.Preset() == "custom")
assert(API.Set("borderWidth", 3) and API.SetBorderColor(.4, .5, .6, 1) and API.Setting("borderMode") == "custom")
function GameTooltipTextLeft1:GetTop() return 995 end
function GameTooltipTextLeft1:GetBottom() return 979 end
function GameTooltip:GetWidth() return 106 end
Build(1, { type = 1, hyperlink = "item:edge" })
assert(not card:IsShown() and outline:IsShown() and outline.anchor[2] == GameTooltip,
    "the top edge duplicated the item title or dropped the outline")
assert(outline.textures[1]:GetHeight() == 3 and outline.textures[1].color[1] == .4,
    "configured outline thickness and color never reached the renderer")
function GameTooltipTextLeft1:GetTop() return 800 end
function GameTooltipTextLeft1:GetBottom() return 782 end
GameTooltip.current = nil
function GameTooltip:GetItem() return "Item", "item:from-native" end
GameTooltip.scripts.OnShow()
assert(card:IsShown(), "a public native item without a primary record lost its style")
Flush()
local initialQueue = queued
function GameTooltip:GetWidth() return 0 end
Build(1, { type = 1, hyperlink = "item:late-layout" })
GameTooltip.scripts.OnSizeChanged()
GameTooltip.scripts.OnSizeChanged()
assert(not card:IsShown() and queued == initialQueue + 1 and timer, "an unsettled layout queued repeated updates")
function GameTooltip:GetWidth() return 106 end
GameTooltip.scripts.OnSizeChanged()
assert(card:IsShown(), "the first usable layout waited on the timer")
Flush()
assert(API.Set("borderMode", "native") and card:IsShown() and not outline:IsShown())
assert(API.Set("borderMode", "suite"))
local icon = 135844
GameTooltip.owner = { Icon = { GetTexture = function() return icon end } }
local beforeIconReads = spells
for _, kind in ipairs({ 7, 11, 18, 22, 25 }) do
    Build(kind, { type = kind, id = 801 })
    assert(card:IsShown() and outline:IsShown() and card.textures[1].texture == icon,
        "spell style omitted a native aura or action tooltip")
end
assert(spells == beforeIconReads, "an aura or action ID was used as a spell ID")
icon = { secret = true }
Build(7, { type = 7, id = { secret = true } })
assert(card:IsShown() and cardIcon:IsShown() and rawequal(cardIcon.texture, icon),
    "a protected aura icon was not forwarded to the card texture")
function GameTooltipTextLeft1:GetText() return { secret = true } end
callbacks[7](GameTooltip, GameTooltip.current)
assert(card:IsShown() and outline:IsShown() and renderedTitle.text.secret,
    "a restricted aura title dropped the card or missed the native text sink")
function GameTooltipTextLeft1:GetText() return "Current title" end
BuffFrameTooltip.current = { type = 7, id = 801 }
BuffFrameTooltip.owner = { icon = { GetTexture = function() return 135846 end } }
callbacks[7](BuffFrameTooltip, BuffFrameTooltip.current)
assert(buffCard:IsShown() and buffOutline:IsShown() and buffCard.textures[1].texture == 135846 and card:IsShown(),
    "the Forever buff tooltip did not get its own styled view")
BuffFrameTooltip.scripts.OnHide()
assert(not buffCard:IsShown() and not buffOutline:IsShown() and outline:IsShown(),
    "hiding the Forever buff tooltip touched the mouse tooltip")
Flush()
assert(API.SetTypeStyle("item", "suite"))
Build(1, { type = 1, hyperlink = "item:action" })
assert(not card:IsShown(), "an action bar item inherited the spell style")
assert(API.SetTypeStyle("unit", "suite") and API.SetTypeStyle("spell", "suite"))
assert(not card:IsShown() and not coreFill:IsShown() and not coreAccent:IsShown() and next(combatEvents.events) == nil)
assert(corePanel:GetHeight() == 90 and corePanel.name.anchor[2] == 8 and corePanel.line2.anchor[2] == corePanel.name,
    "switching to Suite style did not restore Core's original geometry")
Flush()
callbacks[1](GameTooltip, GameTooltip.current)
assert(not timer, "a released tooltip still schedules card work")

-- An already released Core may publish its first panel only on hover.
local bridgeSuite = { Public = NS.Safety.Public, Dispatch = function(fn, ...) return fn(...) end }
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridge.lua"))("MSUF_Suite", bridgeSuite)
assert(loadfile(root .. "/MSUF_Suite/Core/HostBridgeTooltip.lua"))("MSUF_Suite", bridgeSuite)
local discovered, hooked = 0, 0
MSUF_NS = { Tooltips = { ShowUnit = function()
    MSUF_PlayerInfoFrame = corePanel
    return true
end } }
hooksecurefunc = function(api, method, callback)
    local before = api[method]
    hooked = hooked + 1
    api[method] = function(...)
        local result = before(...)
        callback(...)
        return result
    end
end
local function Receive(frame)
    assert(frame == corePanel)
    discovered = discovered + 1
end
local bridge = bridgeSuite.HostBridge
assert(not bridge.OwnsUnitFrameTooltip({}))
assert(not bridge.OwnsUnitFrameTooltip({ _msufUnitTooltipOwner = { secret = true } }))
assert(bridge.OwnsUnitFrameTooltip({ _msufUnitTooltipOwner = corePanel }))
assert(bridge.SetUnitFrameTooltipPanelStyler(Receive) and discovered == 0)
assert(MSUF_NS.Tooltips.ShowUnit() and discovered == 1)
assert(MSUF_NS.Tooltips.ShowUnit() and discovered == 1)
assert(bridge.SetUnitFrameTooltipPanelStyler(nil))
assert(bridge.SetUnitFrameTooltipPanelStyler(Receive) and discovered == 2 and hooked == 1)
local positioned = 0
corePanel:Show()
assert(bridge.SetUnitFrameTooltipPanelPositioner(function(panel)
    assert(panel == corePanel)
    positioned = positioned + 1
end) and positioned == 1 and hooked == 1)
assert(MSUF_NS.Tooltips.ShowUnit() and positioned == 2)
corePanel._msufEditPreviewActive = true
assert(MSUF_NS.Tooltips.ShowUnit() and positioned == 2, "the shared anchor moved the standalone edit preview")
corePanel._msufEditPreviewActive = nil
assert(bridge.SetUnitFrameTooltipPanelPositioner(nil))
assert(MSUF_NS.Tooltips.ShowUnit() and positioned == 2)
-- Exercise the shared fill separately so the isolated card tests above still
-- cover the fallback used when the native chrome adapter cannot skin a tooltip.
local coverMode, backing, restoreCount, createCount
restoreCount, createCount = 0, 0
function GameTooltipTextLeft1:GetText() return "Current title" end
function GameTooltipTextLeft1:GetTop() return 800 end
function GameTooltipTextLeft1:GetBottom() return 782 end
local nativeTitleAlpha
NS.TooltipChrome = {
    IsActive = function(tip) return tip == GameTooltip end,
    SetCardBacking = function(tip, value)
        assert(tip == GameTooltip)
        coverMode = value
        return true
    end,
    SettleBackdrop = Noop,
}
NS.Safety.CanDecorate = function() return true end
NS.Safety.CanCreateRegions = function() return true end
NS.Safety.CreateChildFrame = function(_, tip)
    assert(tip == GameTooltip)
    createCount = createCount + 1
    backing = Widget()
    return backing
end
NS.Surface.Attach = function() return true end
NS.Surface.SetVisible = function(frame, visible) frame.fillVisible = visible end
NS.Cosmetics = {
    Fade = function(region)
        nativeTitleAlpha = region:GetAlpha()
        region:SetAlpha(0)
        return true
    end,
    Restore = function(region)
        assert(nativeTitleAlpha)
        restoreCount = restoreCount + 1
        region:SetAlpha(nativeTitleAlpha)
    end,
}
GameTooltipTextLeft1:SetAlpha(.8)
GameTooltip:Show()
assert(API.SetPreset("detailed"))
assert(API.Set("cardSurface", "unified") and API.SetTypeStyle("item", "custom"), "cardSurface selector missing")
local data = { type = 1, hyperlink = "item:unified" }
Build(1, data)
assert(backing and backing:IsShown() and backing:GetFrameLevel() == GameTooltip:GetFrameLevel() - 1
    and GameTooltipTextLeft1:GetAlpha() == 0 and coverMode == "all" and card.fillVisible == false,
    "unified card did not replace both paints")
for _ = 1, 20 do Build(1, data) end
assert(createCount == 1 and restoreCount == 0 and backing:IsShown(), "an in-place rebuild recreated or dropped the surface")
local rightEdge = 930
function UIParent:GetRight() return 1000 end
function UIParent:GetLeft() return 0 end
function GameTooltip:GetWidth() return 94 end
function GameTooltip:GetRight() return rightEdge end
function GameTooltip:GetLeft() return rightEdge - 94 end
GameTooltip.scripts.OnSizeChanged()
assert(card.anchor[4] == 66 and outline.anchor[2] == backing,
    "a narrow tooltip cannot fit the icon and metadata in a single surface")
rightEdge = 990
GameTooltip.scripts.OnSizeChanged()
assert(card.anchor[4] == 10, "the custom card extends past the right edge of the screen")
assert(API.Set("borderMode", "native") and coverMode == "fill", "Keep must keep the native border")
assert(API.Set("cardSurface", "split") and restoreCount == 1 and not coverMode and not backing:IsShown()
    and GameTooltipTextLeft1:GetAlpha() == .8 and card.fillVisible == true, "split did not restore native regions")
assert(API.Set("cardSurface", "unified"))
assert(API.SetTypeStyle("item", "suite") and GameTooltipTextLeft1:GetAlpha() == .8 and not backing:IsShown(),
    "turning off the extension must restore the native tooltip")
local function Comparison(name, caption)
    local tip, title, badge = Widget(), Widget(), Widget()
    tip.current = { type = 1, hyperlink = "item:" .. name }
    tip.owner, tip.CompareHeader = GameTooltip, badge
    badge.Label = Widget()
    badge.Label:SetText(caption)
    badge:Show()
    tip.GetOwner, tip.GetPrimaryTooltipData = GameTooltip.GetOwner, GameTooltip.GetPrimaryTooltipData
    tip.GetTop, tip.GetWidth = GameTooltip.GetTop, GameTooltip.GetWidth
    function tip:GetName() return name end
    title.GetTop, title.GetBottom = GameTooltipTextLeft1.GetTop, GameTooltipTextLeft1.GetBottom
    function title:GetText() return name .. " item" end
    function badge.Label:GetText() return self.text end
    _G[name], _G[name .. "TextLeft1"] = tip, title
    return tip, title, badge
end

local first, firstTitle, firstBadge = Comparison("ShoppingTooltip1", "Equipped")
local second, secondTitle, secondBadge = Comparison("ShoppingTooltip2", "If Equipped Together")
local reference, refTitle, refBadge = Comparison("ItemRefShoppingTooltip2", "If Equipped Together")
GameTooltip.shoppingTooltips = { first, second }
local coverModes, originalAlphas = {}, {}
NS.TooltipChrome.IsActive = function() return true end
NS.TooltipChrome.SetCardBacking = function(tip, mode) coverModes[tip] = mode return true end
NS.Cosmetics.Fade = function(region)
    originalAlphas[region] = originalAlphas[region] or region:GetAlpha()
    region:SetAlpha(0)
    return true
end
NS.Cosmetics.Restore = function(region)
    region:SetAlpha(assert(originalAlphas[region]))
    originalAlphas[region] = nil
end
NS.Safety.CreateChildFrame = function() return Widget() end

callbacks[1](first, first.current)
assert(not first.scripts.OnShow and firstBadge:GetAlpha() == 1, "Suite style allocated a comparison extension")
assert(API.SetTypeStyle("item", "custom") and API.Set("borderMode", "suite"))
rightEdge = 900
Build(1, { type = 1, hyperlink = "item:primary" })
assert(card.anchor[4] == 66, "the main card did not start with extra space")
local function ShowComparison(tip, title, badge)
    callbacks[1](tip, tip.current)
    assert(API.HasVisibleHeader(tip), "equipped item never reached the Item tooltip card")
    tip:Show()
    tip.scripts.OnShow()
    assert(title:GetAlpha() == 0 and badge:GetAlpha() == 0 and coverModes[tip] == "all",
        "comparison card did not take over the title, badge and background")
end
ShowComparison(first, firstTitle, firstBadge)
assert(card.anchor[4] == 0, "the main tooltip still overlaps its comparison")
ShowComparison(second, secondTitle, secondBadge)
ShowComparison(reference, refTitle, refBadge)

-- Rebuilds of the two equipped items retain the Suite card while the
-- client's final layout can restore the original title after the item post-call.
local manager = TooltipComparisonManager
manager.tooltip = GameTooltip
local priorReads = reads
for _ = 1, 12 do
    callbacks[1](first, first.current)
    callbacks[1](second, second.current)
    firstTitle:SetAlpha(1)
    secondTitle:SetAlpha(1)
    manager:AnchorShoppingTooltips(true, true)
    assert(firstTitle:GetAlpha() == 0 and secondTitle:GetAlpha() == 0,
        "both native comparison titles flashed after the final anchor")
    assert(API.HasVisibleHeader(first) and API.HasVisibleHeader(second), "a comparison card dropped during refresh")
end
assert(reads == priorReads, "the compare completion reread unchanged items")

local comparisonWidth = first:GetWidth()
function first:GetWidth() return comparisonWidth end
first.scripts.OnTooltipCleared()
firstTitle:SetAlpha(1)
comparisonWidth = nil
callbacks[1](first, first.current)
assert(firstTitle:GetAlpha() == 0 and API.HasVisibleHeader(first),
    "temporary missing geometry exposed the old native title")
comparisonWidth = 208
manager:AnchorShoppingTooltips(true, true)
assert(firstTitle:GetAlpha() == 0 and API.HasVisibleHeader(first), "the comparison did not settle after anchoring")
Flush()

first:Hide()
first.scripts.OnHide()
assert(not API.HasVisibleHeader(first) and firstTitle:GetAlpha() == 1 and firstBadge:GetAlpha() == 1,
    "closing comparison did not restore the native title and caption")
assert(card.anchor[4] == 0, "the main tooltip expanded while a second comparison was visible")
second:Hide()
second.scripts.OnHide()
assert(card.anchor[4] == 66, "the main card lost its extra width after comparisons closed")
assert(API.SetTypeStyle("item", "suite"))
assert(not API.HasVisibleHeader(reference) and refTitle:GetAlpha() == 1 and refBadge:GetAlpha() == 1,
    "the current Item style did not reach the chat-link comparison")
local palette = NS.TooltipPalette
NS.Theme.StyleProfile = function(profile, look)
    local retail = look == "modern"
    assert(retail or look == "gridClassic")
    profile.theme.colors = { popup = { retail and .1 or .05, .1, .1, .9 }, ink = { .02, .03, .04, .9 },
        text = { 1, .9, .8, 1 }, accent = { .8, .6, .2, 1 }, border = { .5, .6, .7, 1 } }
    profile.theme.shellOpacity, profile.theme.borderOpacity, profile.theme.gradient = .8, .75, retail
    return true
end
assert(API.SetPreset("retail") and API.SetTypeStyle("unit", "custom"))
local r, _, _, a = palette.Fill({})
assert(r == .1 and math.abs(a - .72) < .0001 and API.TypeStyle("item") == "suite",
    "the preset did not apply its backdrop or changed which types use the card")
assert(API.SetPreset("dense") and palette.IsActive(), "changing the layout removed the selected colors")
assert(API.SetPreset("forever") and palette.Fill({}) == .05, "the Forever look was not distinct")
assert(API.SetPaletteColor("fillColor", .3, .4, .5, .7) and palette.Fill({}) == .3)
assert(API.SetPreset("compact") and not palette.IsActive(), "Default did not return to the Suite theme")
assert(API.TypeStyle("quest") == "custom", "quest and object tooltips did not inherit world hover styling")
function GameTooltipTextLeft1:GetText() return "Fresh Manure" end
Build(4, { type = 4 })
assert(API.HasVisibleHeader(GameTooltip) and card.textures[1].texture == nil, "a quest object did not reach the card")
Build(23, { type = 23 })
assert(API.HasVisibleHeader(GameTooltip), "a quest did not reach the card")
assert(API.SetTypeStyle("quest", "suite"))
Build(23, { type = 23 })
assert(not API.HasVisibleHeader(GameTooltip), "the quest style could not be disabled separately")
function C_Item.GetItemLinkByGUID(guid)
    assert(guid == "Item-public")
    return "item:public-guid"
end
local savedGetItem = GameTooltip.GetItem
function GameTooltip:GetItem() error("native GetItem wrapper read potentially restricted fields") end
assert(API.SetTypeStyle("item", "custom"))
local beforeRestrictedItem = reads
combat = true
Build(1, { type = 1, hyperlink = { secret = true }, guid = { secret = true }, id = 42 })
assert(card:IsShown() and reads == beforeRestrictedItem + 1 and card.textures[1]:IsShown(),
    "the card did not use the readable item ID")
Build(1, { type = 1, hyperlink = { secret = true }, guid = "Item-public" })
assert(card:IsShown() and reads == beforeRestrictedItem + 2 and card.textures[1]:IsShown(),
    "the card did not use the readable item GUID")
GameTooltip.GetItem = savedGetItem
combat = false
Flush()
print("item tooltip cards: public quest and object data, palettes, restricted fallback and comparisons passed")

-- Independent vital styling follows the tooltip profile across layout presets.
assert(API.SetUnitBarOffsets("unitHealth", 18, -3))
assert(API.SetUnitBarOffsets("unitHealthText", 12, -6))
assert(not API.SetUnitBarSize("unitHealthText", 25, 18))
assert(API.Set("unitHealthTextFormat", "percent") and API.Set("unitHealthTextFont", "Shared font"))
assert(API.Set("unitHealthTextSize", 20) and API.SetUnitBarColor("unitHealthTextColor", .1, .2, .3, 1))
assert(API.SetUnitBarSize("unitHealth", 71, 19))
assert(API.Set("unitHealthTexture", "Unloaded media pack"))
assert(API.Set("unitHealthBackground", "Track pattern"))
assert(API.SetUnitBarColor("unitHealthBackgroundColor", .1, .2, .3, .6))
assert(API.SetPreset("detailed"))
assert(API.Setting("unitHealthX") == 18 and API.Setting("unitHealthY") == -3)
assert(API.Setting("unitHealthTextX") == 12 and API.Setting("unitHealthTextY") == -6)
assert(API.Setting("unitHealthTextFormat") == "percent" and API.Setting("unitHealthTextSize") == 20)
assert(API.Setting("unitHealthTextFont") == "Shared font")
assert(API.Setting("unitHealthWidth") == 71 and API.Setting("unitHealthHeight") == 19)
assert(API.Setting("unitHealthTexture") == "Unloaded media pack" and API.Setting("unitHealthBackground") == "Track pattern")
local _, _, _, backgroundAlpha = API.UnitBarColor("unitHealthBackgroundColor")
assert(backgroundAlpha == .6)
assert(API.SetUnitBarSize("unitPower", 999, 4))
assert(API.Setting("unitPowerWidth") == 150 and API.Setting("unitPowerHeight") == 8)
assert(API.Setting("unitHealthWidth") == 71, "editing Power changed Health")
assert(API.ResetUnitVitals() and API.Setting("unitHealthX") == 0 and API.Setting("unitHealthWidth") == 100
    and API.Setting("unitHealthTexture") == "")

-- The HP mirror also uses the settlement timer with the header card off.
Flush()
for _, kind in ipairs({ "item", "spell", "unit", "quest" }) do assert(API.SetTypeStyle(kind, "suite")) end
vitals.Enabled = true
local settled = 0
vitals.NativeCleared = function() return true end
vitals.FinishNativeClear = function() settled = settled + 1 end
GameTooltip.scripts.OnTooltipCleared()
assert(timer and settled == 0, "the visible health mirror did not get the shared settlement timer")
callbacks[2](GameTooltip, { type = 2 })
assert(settled == 0, "appended content settled the native health mirror")
GameTooltip.current = { type = 2 }
callbacks[2](GameTooltip, GameTooltip.current)
assert(settled == 1, "a confirmed non-unit tooltip kept the old mirror until the timer")
Flush()
assert(settled == 1, "the timer settled the same clear twice")
GameTooltip.scripts.OnTooltipCleared()
Flush()
assert(settled == 2, "clearing without replacement kept the health mirror with the card off")

local shown, hidden, resized = 0, 0, 0
vitals.NativeShown = function() shown = shown + 1 end
vitals.NativeHidden = function() hidden = hidden + 1 end
vitals.NativeResized = function(width)
    assert(width == 240)
    resized = resized + 1
end
vitals.Enabled = false
GameTooltip.scripts.OnShow()
GameTooltip.scripts.OnSizeChanged(GameTooltip, 240)
GameTooltip.scripts.OnHide()
assert(shown == 0 and hidden == 0 and resized == 0, "disabled vitals received shared lifecycle events")
vitals.Enabled = true
GameTooltip.scripts.OnShow()
GameTooltip.scripts.OnSizeChanged(GameTooltip, 240)
GameTooltip.scripts.OnHide()
assert(shown == 1 and hidden == 1 and resized == 1, "the shared tooltip lost the active vitals lifecycle")

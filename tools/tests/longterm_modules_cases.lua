-- Product lifecycle regressions. Each invocation owns one fresh Lua world.
local cases = {}
cases.bank_cursor = function(root, variant, flavor)
    local arg = {root, variant}
local root, scenario = assert(arg[1]), arg[2] or "foreign"
local cursor, cleared = "refundable-A", nil
local function widget()
    return setmetatable({}, { __index = function(_, key)
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "IsShown" then return function(self) return self.shown end end
        if key == "SetScript" then return function(self, event, fn) self[event] = fn end end
        return function() end
    end })
end
local P = {
    NS = { Client = { isForever = false }, IsCombatLocked = function() return false end },
    Suite = { CreateFrame = widget, CreateTexture = widget,
        Public = function(v) return v ~= "secret" end,
        PublicText = function(v) return v ~= "secret" and type(v) == "string" and v or nil end },
    GridView = { Font = widget },
    BagsModule = { active = true, config = {} },
    BankInventory = { enabled = true, active = true },
}
Enum = { BankType = { Account = 2 } }
BankFrame = { IsShown = function() return true end }
C_Bank = { CanUseBank = function() return true end }
C_Cursor = { GetCursorItem = function() return cursor end }
C_Item = { CanBeRefunded = function() return true end, GetItemGUID = function(location) return location end }
CursorHasItem = function() return cursor ~= nil end
IsModifiedClick = function() return false end
ClearCursor = function() cleared, cursor = cursor, nil end
OKAY, CANCEL, END_REFUND = "Okay", "Cancel", "End refund?"
assert(loadfile(root .. "/MSUF_Suite_Bags/BankActions.lua"))("MSUF_Suite_Bags", P)
P.BankActions.Click({ record = { bag = 13, slot = 1, bankType = 2 } }, "LeftButton")
if scenario == "foreign" then cursor = "unrelated-B"
elseif scenario == "empty" then cursor = nil
elseif scenario == "unreadable" then C_Item.GetItemGUID = function() return "secret" end
elseif scenario ~= "original" then error("unknown cursor case") end
-- BankInventory calls this when the bank closes or its owned view stops.
P.BankActions.Cancel()
print(scenario .. " after closing bank: cursor=" .. tostring(cursor) .. ", cleared=" .. tostring(cleared))
if scenario == "foreign" then assert(cursor == "unrelated-B" and cleared == nil, "closing old refund question cleared a foreign cursor item")
elseif scenario == "original" then assert(cursor == nil and cleared == "refundable-A", "cancel did not return its own original cursor")
elseif scenario == "empty" then assert(cursor == nil and cleared == nil, "empty cursor changed during cancel")
else assert(cursor == "refundable-A" and cleared == nil, "unreadable cursor identity was treated as owned") end

end

cases.bank_disable = function(root, variant, flavor)
    local arg = {root, variant}
local root = assert(arg[1])
local scenario=arg[2] or "module_disabled"
local cursor, deposited, frames = "refundable-A", 0, {}
local function widget(kind)
    local w = { kind = kind, shown = false }
    frames[#frames + 1] = w
    return setmetatable(w, { __index = function(_, key)
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "IsShown" then return function(self) return self.shown end end
        if key == "SetScript" then return function(self, event, fn) self[event] = fn end end
        return function() end
    end })
end
local P = {
    NS = { Client = { isForever = false }, IsCombatLocked = function() return false end,
        BagsBankView = { TABS = 1, CHARACTER = 2, WARBANK = 3, CATEGORIES = 4 }, BagsView = {} },
    Suite = { CreateFrame = widget, CreateTexture = widget,
        Public=function(v) return v~="secret" end,
        PublicText=function(v) return v~="secret" and type(v)=="string" and v or nil end },
    GridView = { Font = widget },
    BagsModule = { active = true, config={} },
    InventoryModel = { New = function() return {} end },
    InventoryIndex = { Reset = function() end },
    BankInventoryIndex = { New = function() return {} end },
}
Enum = { BankType = { Account = 2 }, ItemQuality = { Poor = 0 } }
BankFrame = { IsShown = function() return true end, HookScript = function() end }
C_Bank = { CanUseBank = function() return true end }
C_Cursor = { GetCursorItem = function() return cursor end }
C_Item = { CanBeRefunded = function() return true end, GetItemGUID = function(location) return location end }
C_Container = { PickupContainerItem = function() deposited, cursor = deposited + 1, nil end }
CursorHasItem = function() return cursor ~= nil end
IsModifiedClick = function() return false end
ClearCursor = function() cursor = nil end
OKAY, CANCEL, END_REFUND = "Okay", "Cancel", "End refund?"
assert(loadfile(root .. "/MSUF_Suite_Bags/BankActions.lua"))("MSUF_Suite_Bags", P)
assert(loadfile(root .. "/MSUF_Suite_Bags/BankInventory.lua"))("MSUF_Suite_Bags", P)
P.BankInventory.active=true
P.BankActions.Click({ record = { bag = 13, slot = 1, bankType = 2 } }, "LeftButton")
local question = frames[1]
local accept
for _, f in ipairs(frames) do if f.kind == "Button" and f.OnClick then accept = accept or f.OnClick end end
assert(question.shown and accept)
if scenario~="original" then
    if scenario~="view_disabled" then P.BagsModule.active=false end
    P.BankInventory.Disable()
end
print("refund question shown after real BankInventory.Disable=" .. tostring(question.shown))
accept()
print("deposit requests after module disabled=" .. deposited)
if scenario=="original" then assert(not question.shown and deposited==1,"original active bank acceptance failed")
else assert(not question.shown and deposited == 0, "disabled bank view left a stale actionable refund confirmation") end

end

cases.currency_menu = function(root, variant, flavor)
    local arg = {root, variant}
local root = assert(arg[1])
local scenario = arg[2] or "profile"
local callbacks, writes = {}, 0
local a, b = { currencyIDs = "10" }, { currencyIDs = "20" }
local M = { active = true, config = a }
local menu = {}
function menu:CreateCheckbox(_, _, toggle)
    callbacks[#callbacks + 1] = toggle
    return { SetEnabled = function() end }
end
local clear
function menu:CreateButton(_,callback) clear=callback end
function menu:CreateTitle() end
function menu:CreateDivider() end
function menu:SetScrollMode() end
local S = {
    Text = function(v) return v end,
    Public = function() return true end,
    Finite = function(v) return type(v) == "number" end,
    Set = function(_, key, value) writes = writes + 1; M.config[key] = value end,
    ContextMenu = function(owner, generate) generate(owner, menu) end,
}
local combat = false
local NS = {DB=a,InCombat=function() return combat end}
C_CurrencyInfo = {
    GetCurrencyInfo = function() return { name = "Ten" } end,
    GetCurrencyListSize = function() return 0 end,
}
assert(loadfile(root .. "/MSUF_Suite_Bags/CurrencyPicker.lua"))("MSUF_Suite_Bags", { Suite = S, BagsModule = M, NS=NS })
S.BagCurrencyMenu({})
assert(#callbacks == 1)
local old=callbacks[1]
if scenario=="profile" or scenario=="clear_profile" then M.config,NS.DB=b,b
elseif scenario=="reopen" then S.BagCurrencyMenu({})
elseif scenario=="disabled" then M.active=false
elseif scenario=="combat" then combat=true end
if scenario=="clear_profile" then clear() else old() end
print("new profile currencyIDs=" .. tostring(b.currencyIDs) .. ", stale menu writes=" .. writes)
if scenario=="original" then assert(a.currencyIDs=="" and writes==1,"original currency menu stopped working")
else assert(b.currencyIDs == "20" and writes == 0, "expired currency picker wrote current selected IDs") end

end

cases.datatext_movers = function(root, variant, flavor)
    local arg = {root, variant}
local root = assert(arg[1])
local lastSpec
local owned = {}
local S = { Text = function(v) return v end, UnregisterEditElements = function() owned = {} end,
    HasOwnedMover = function(_, id) return owned[id] == true end, RefreshOwnedMovers = function() end,
    RegisterOwnedMover = function(_, id, spec) lastSpec=spec; owned[id]=true; return true end }
local P = { NS = {}, Suite = S, DataTextBarKeys = function(index)
    return { prefix = "bar" .. index, enabled = "bar" .. index .. "Enabled" }
end }
assert(loadfile(root .. "/MSUF_Suite_DataTexts/Movers.lua"))("MSUF_Suite_DataTexts", P)
local m = { config = {}, bars = {}, barIDs = {}, presentIDs = {} }
local function register(id)
    m.bars, m.barIDs, m.presentIDs = { [id] = {} }, { id }, { [id] = true }
    P.DataTextMovers.Register(m)
end
collectgarbage("collect")
local before = collectgarbage("count")
for i = 1, 10000 do register(i) end
local presentSpec=lastSpec
register(10000)
assert(lastSpec==presentSpec,"warm registration recreated the present bar mover spec")
collectgarbage("collect")
local after = collectgarbage("count")
local spec, cache
for i = 1, 20 do local name, value = debug.getupvalue(P.DataTextMovers.Register, i); if name == "Spec" then spec = value end end
assert(spec)
for i = 1, 20 do local name, value = debug.getupvalue(spec, i); if name == "specs" then cache = value end end
assert(cache)
local count = 0
for _ in pairs(cache) do count = count + 1 end
print("active bars=1, cached historical mover specs=" .. count .. ", retained heap KiB=" .. string.format("%.1f", after - before))
assert(count <= 256, "mover cache retained every removed historical bar ID despite the active 256-bar bound")

end

cases.datatext_overlay = function(root, variant, flavor)
    local arg = {root, flavor, variant}
-- DataTexts against the client's protection rules (clientSecurity harness):
-- places are ordinary buttons that may move in combat, protected clicks run
-- on secure buttons that never depend on a bar during combat, and combat
-- visibility follows the client's own combat state.
local root = assert(arg[1], "repository root required")
local flavor = arg[2] or "Mainline"
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local hour, minute = 14, 3
local loaded, microClicks = {}, {}
local W = H.New(root, flavor, { clientSecurity = true, beforeModules = function(world)
    local G = world.G
    -- The cold fixture stops at Suite.lua; the client continues with this provider.
    local fontBridge = assert(loadfile(root .. "/MSUF_Suite/Core/FontBridge.lua"))
    setfenv(fontBridge, G)
    fontBridge("MSUF_Suite", world.Suite)
    G.GetGameTime = function() return hour, minute end
    G.GetMoney = function() return 120000 end
    G.C_Container = {
        GetContainerNumSlots = function() return 20 end,
        GetContainerNumFreeSlots = function() return 8, 0 end,
    }
    G.PlayerHasToy = function() return false end
    G.C_Item = {
        GetItemCount = function(id) return id == 6948 and 1 or 0 end,
        GetItemInfo = function(id) return id == 6948 and "Hearthstone" or nil, nil, nil, nil, nil, nil, nil, nil, nil, 134414 end,
    }
    -- The deprecation fallbacks are off: only C_SpecializationInfo exists.
    G.GetSpecialization, G.GetSpecializationInfo = nil, nil
    G.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 62, "Arcane", "", 135932 end,
    }
    G.C_Spell = { GetSpellCooldownDuration = function() return nil end }
    G.C_AddOns.LoadAddOn = function(name) loaded[#loaded + 1] = name end
    -- Blizzard's micro buttons; their own OnClick records whether it ran secure.
    -- layoutIndex marks the buttons Blizzard put into its micro menu
    -- (MicroMenuMixin:AddButton): Forever's menu leaves PlayerSpells out,
    -- Retail's has no separate Spellbook and Talent buttons.
    local unlisted = flavor == "Forever" and { PlayerSpellsMicroButton = true }
        or { SpellbookMicroButton = true, TalentMicroButton = true }
    for index, name in ipairs({ "CharacterMicroButton", "PlayerSpellsMicroButton", "SpellbookMicroButton",
        "TalentMicroButton", "QuestLogMicroButton", "GuildMicroButton", "MainMenuMicroButton" }) do
        local native = world.New("Button", name, world.UIParent)
        native.tooltipText = name .. " tip"
        if not unlisted[name] then native.layoutIndex = index end
        native.scripts.OnClick = function(self)
            microClicks[#microClicks + 1] = { name = self.name, secure = world.secure }
        end
    end
    -- Blizzard_UIParentPanelManager: an addon's ShowUIPanel/HideUIPanel hand
    -- the panel to the secure FramePositionDelegate (refused in combat).
    world.panelCalls = {}
    local function Panel(shown)
        return function(frame)
            world.panelCalls[#world.panelCalls + 1] = { frame = frame, shown = shown, secure = world.secure }
            if not G.InCombatLockdown() then world.Blizzard(function() frame:SetShown(shown) end) end
        end
    end
    G.ShowUIPanel, G.HideUIPanel = Panel(true), Panel(false)
    G.SOUNDKIT = { IG_MAINMENU_OPEN = 850, IG_MAINMENU_QUIT = 851 }
    G.PlaySound = function(sound) world.sounds = (world.sounds or 0) + 1; world.lastSound = sound end
    G.GameMenuFrame = world.New("Frame", "GameMenuFrame", world.UIParent)
    G.GameMenuFrame:Hide()
    -- The minimap's zone text button opens the world map
    -- (MinimapZoneTextButtonMixin:OnClick); the openers record their callers.
    G.MinimapCluster.ZoneTextButton.scripts.OnClick = function()
        microClicks[#microClicks + 1] = { name = "ZoneTextButton", secure = world.secure }
    end
    -- The character window's currency tab runs CharacterFrame:ToggleTokenFrame()
    -- (CharacterFrameTabButtonMixin:OnClick).
    G.CharacterFrameTab3.scripts.OnClick = function()
        microClicks[#microClicks + 1] = { name = "CharacterFrameTab3", secure = world.secure }
    end
    world.opened = {}
    for _, name in ipairs({ "ToggleCharacter", "ToggleWorldMap" }) do
        G[name] = function(tab)
            world.opened[#world.opened + 1] = { name = name, tab = tab, secure = world.secure }
        end
    end
    -- MainMenuMicroButtonMixin:OnClick (Blizzard_MicroMenu/Mainline) acts only
    -- while the cursor is over the micro button itself.
    G.MainMenuMicroButton.scripts.OnClick = function(self)
        microClicks[#microClicks + 1] = { name = self.name, secure = world.secure }
        if not self:IsMouseOver() then return end
        if G.GameMenuFrame:IsShown() then G.HideUIPanel(G.GameMenuFrame) else G.ShowUIPanel(G.GameMenuFrame) end
    end
end })
local G, S, NS = W.G, W.S, W.Suite
function G.GameTooltip:SetItemByID(id) self.lines = { "item:" .. id } end
W.LoadAddon("MSUF_Suite_DataTexts")
local M = assert(S.instances.dataTexts)
local A = W.private.DataTextActions
local function Choice(key)
    for index, value in ipairs(NS.DataTextSourceKeys) do
        if value == key then return index end
    end
    error("unknown DataText source " .. key)
end
S.Start()
local c = S.Config("dataTexts")
assert(S.SetMany("dataTexts", { enabled = true, bar1Enabled = true, bar1Layout = 2,
    bar1Slot1 = Choice("clock"), bar1Slot2 = Choice("hearth"), bar1Slot3 = Choice("specialization"),
    bar1Slot4 = Choice("audio"), bar1Slot5 = Choice("portals"), bar1Slot6 = Choice("microMenu"),
    bar2Enabled = true, bar2Visibility = 2, bar2Slot1 = Choice("fps"), bar2Slot2 = 1, bar2Slot3 = 1,
    bar3Enabled = true, bar3Visibility = 3, bar3Slot1 = Choice("gold"), bar3Slot2 = 1, bar3Slot3 = 1,
    bar4Enabled = true, bar4Slot1 = Choice("durability"), bar4Slot2 = Choice("coordinates"),
    bar4Slot3 = Choice("location"), bar4Slot4 = Choice("currency") }))
local bar = assert(M.bars[1])
local slots = bar.slots
local clock, hearth, spec, audio, portals, micro = slots[1], slots[2], slots[3], slots[4], slots[5], slots[6]


-- No configured Hearthstone: PrepareHearths then returns without refreshing the overlay.
assert(S.SetMany("dataTexts", { bar1Slot1 = Choice("specialization"), bar1Slot2 = 1,
    bar1Slot3 = 1, bar1Slot4 = 1, bar1Slot5 = 1, bar1Slot6 = 1,
    bar2Enabled = false, bar3Enabled = false, bar4Enabled = false }))
local button = M.bars[1].slots[1]
W.Fire(button, "OnEnter")
local overlay = assert(A.overlay)
assert(overlay.shown and overlay.owner == button and overlay:GetAttribute("type1") == "click")
local scenario = arg[3] or "plain"
if scenario == "secure" then
    assert(S.Set("dataTexts", "bar1Slot1", Choice("currency")))
    print("secure change: overlay shown=" .. tostring(overlay.shown))
    assert(not overlay.shown or overlay:GetAttribute("clickbutton1") == G.CharacterFrameTab3,
        "secure source change retained the original specialization target")
elseif scenario == "hidden_slot" then
    assert(S.Set("dataTexts", "bar1Slot1", 1))
    print("hidden slot: overlay shown=" .. tostring(overlay.shown))
    assert(not overlay.shown and overlay.owner == nil, "hidden slot left an actionable secure overlay")
elseif scenario == "hidden_bar" then
    assert(S.Set("dataTexts", "bar1Enabled", false))
    assert(not overlay.shown and overlay.owner == nil, "hidden bar left an actionable secure overlay")
else
    assert(S.Set("dataTexts", "bar1Slot1", Choice("audio")))
    print("source now=" .. tostring(button.extra.kind) .. ", overlay shown=" .. tostring(overlay.shown)
        .. ", secure type=" .. tostring(overlay:GetAttribute("type1")))
    assert(not overlay.shown and overlay.owner == nil, "source change left old secure overlay over the new audio place")
end

end

cases.hybrid_epoch = function(root, variant, flavor)
    local arg = {root, variant}
local root = assert(arg[1])
local S = { Finite = function(v) return type(v) == "number" end, Public = function() return true end,
    Dispatch = function(fn, ...) return fn(...) end }
local NS = { Safety = { IsForbidden = function() return false end },
    MinimapShape = { SQUARE = 1, CIRCLE = 2, WIDE = 3 },
    MinimapVisibility = { IN_COMBAT = 2, OUT_OF_COMBAT = 3 }, MinimapAnchorPoints = {} }
local P = { NS = NS, Suite = S }
local mask = { texture = "native-original-A" }
function mask:GetTexture() return self.texture end
function mask:SetTexture(value) self.texture = value end
HybridMinimap = { CircleMask = mask }
assert(loadfile(root .. "/MSUF_Suite_Minimap/Host.lua"))("MSUF_Suite_Minimap", P)
local mm = P.Minimap
mm.M.config = { shape = NS.MinimapShape.CIRCLE }
mm.ApplyHybrid()
mm.ReleaseHybrid()
mask.texture = "changed-while-suite-disabled-B"
mm.ApplyHybrid()
mm.ReleaseHybrid()
print("mask after second release=" .. mask.texture)
assert(mask.texture == "changed-while-suite-disabled-B", "hybrid mask restore reused a previous activation's original")

end

cases.hybrid_replacement = function(root, variant, flavor)
    local arg = {root, variant}
local root, replacement = assert(arg[1]), arg[2] or "mask"
local S = { Finite = function(v) return type(v) == "number" end, Public = function() return true end,
    Dispatch = function(fn, ...) return fn(...) end }
local NS = { Safety = { IsForbidden = function() return false end },
    MinimapShape = { SQUARE = 1, CIRCLE = 2, WIDE = 3 },
    MinimapVisibility = { IN_COMBAT = 2, OUT_OF_COMBAT = 3 }, MinimapAnchorPoints = {} }
local P = { NS = NS, Suite = S }
local function newMask(texture)
    return { texture = texture, GetTexture = function(self) return self.texture end,
        SetTexture = function(self, value) self.texture = value end }
end
local old, nextMask = newMask("old-native-A"), newMask("new-native-B")
HybridMinimap = { CircleMask = old }
assert(loadfile(root .. "/MSUF_Suite_Minimap/Host.lua"))("MSUF_Suite_Minimap", P)
local mm = P.Minimap
mm.M.config = { shape = NS.MinimapShape.SQUARE }
mm.ApplyHybrid()
if replacement == "frame" then HybridMinimap = { CircleMask = nextMask }
else HybridMinimap.CircleMask = nextMask end
mm.ApplyHybrid()
mm.ReleaseHybrid()
print(replacement .. " replacement: restored new mask=" .. nextMask.texture)
assert(nextMask.texture == "new-native-B", "replacing native hybrid mask restored another object's original")

end

cases.keystone = function(root, variant, flavor)
    local arg = {root, variant}
local root = assert(arg[1])
local scenario=arg[2] or "no_guild"
local installed, command, messages, notices = {}, nil, {}, {}
local function widget()
    return setmetatable({}, { __index = function(_, key)
        if key == "SetText" then return function(self, text) self.text = text end end
        return function() end
    end })
end
local S = {
    Install = function(id, m) installed[id] = m end,
    RegisterSlash = function(_, fn) command = fn end,
    SlashAliasFree = function() return false end,
    Text = function(t) return t end,
    Public = function(v) return v~="secret" end,
    PublicText = function(v) return type(v) == "string" and v ~= "" and v or nil end,
    Finite = function(v) return type(v) == "number" and v == v end,
    Print = function(v) notices[#notices + 1] = v end,
    CreateFrame = widget, CreateTexture = widget, CreateFontString = widget,
    SetStyledFont = function() end, GlobalFontPath = function() return "font" end,
}
local NS = { IsCombatLocked = function() return false end }
GetTime = function() return 20 end
IsInGuild = function() if scenario=="guild" then return true elseif scenario=="secret_guild" then return "secret" end return false end
LE_PARTY_CATEGORY_INSTANCE = 2
IsInGroup = function(category) return scenario~="ungrouped" and category == nil end
IsInRaid = function() return false end
Enum = { SendAddonMessageResult = { Success = 0 } }
UISpecialFrames = {}
C_MythicPlus = {
    GetOwnedKeystoneChallengeMapID = function() return 101 end,
    GetOwnedKeystoneLevel = function() return 12 end,
}
C_ChallengeMode = { GetMapUIInfo = function() return "The Dawn" end }
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(_, payload, channel)
        messages[#messages + 1] = { payload, channel }
        return 0
    end,
}
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/MPlusKeystoneShare.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
local m = assert(installed.mythicKeyShare)
m.active, m.config = true, {}
m.context = { Event = function() end, RemoveEvent = function() end }
m:Enable()
command(scenario=="group" and "group" or "guild")
print("guild membership=false, party membership=true, request='guild'")
for i, sent in ipairs(messages) do print("sent " .. sent[1] .. " to " .. sent[2]) end
if scenario=="guild" then assert(#messages==1 and messages[1][2]=="GUILD","valid guild query failed")
elseif scenario=="group" then assert(#messages==1 and messages[1][2]=="PARTY","valid party query failed")
else assert(#messages == 0, "explicit guild request fell back to unrelated party channel") end

end

cases.merchant_refund = function(root, variant, flavor)
    local arg = {root, variant}
local root = assert(arg[1], "repository root required")
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end

local templates = {}
local function Widget(parent)
    local w = { parent = parent, shown = true, alpha = 1, mouse = false, scripts = {}, points = {} }
    function w:SetScript(name, callback) self.scripts[name] = callback end
    function w:HookScript(name, callback)
        local old = self.scripts[name]
        self.scripts[name] = function(...) if old then old(...) end; callback(...) end
    end
    function w:Show()
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function w:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function w:SetShown(value) if value then self:Show() else self:Hide() end end
    function w:IsShown() return self.shown end
    function w:SetParent(value) self.parent = value end
    function w:GetScript(name) return self.scripts[name] end
    function w:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function w:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    -- Region:IsMouseMotionFocus: the pointer rests on this frame, not a child.
    function w:IsMouseMotionFocus() return self.motionFocus == true end
    function w:SetAlpha(value) self.alpha = value end
    function w:GetAlpha() return self.alpha end
    function w:EnableMouse(value) self.mouse = value end
    function w:IsMouseEnabled() return self.mouse end
    function w:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function w:ClearAllPoints() self.points = {} end
    function w:SetSize(width, height) self.width, self.height = width, height end
    function w:SetFrameLevel(level) self.level = level end
    function w:GetFrameLevel() return self.level or 1 end
    function w:SetText(value) self.text = value end
    function w:SetTextColor(...) self.textColor = { ... } end
    function w:SetVertexColor(...) self.vertex = { ... } end
    function w:SetTexture(value) self.texture = value end
    function w:SetDesaturated(value) self.desaturated = value end
    function w:SetFont(...) self.font = { ... } end
    function w:SetMinMaxValues(low, high)
        self.low, self.high = low, high
        local value = math.max(low, math.min(high, self.value or 0))
        if value ~= self.value then self:SetValue(value) end
    end
    function w:SetValue(value)
        if value == self.value then return end
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
    for _, name in ipairs({ "SetAllPoints", "SetColorTexture", "SetJustifyH", "SetWordWrap", "RegisterForClicks",
        "RegisterForDrag", "EnableMouseWheel", "SetOrientation", "SetThumbTexture", "SetValueStep",
        "SetObeyStepOnDrag" }) do
        w[name] = function() end
    end
    return w
end

-- Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua as far as the list
-- meets it: MerchantFrame_Update shows the page controls on the merchant
-- tab for more than ten offers and hides them on the buyback tab, which shows
-- MerchantItem11 and 12; it never shows MerchantItem1-10 themselves.
MERCHANT_ITEMS_PER_PAGE, MERCHANT_HIGH_PRICE_COST = 10, 1500000
MerchantFrame = Widget()
MerchantFrame.shown, MerchantFrame.selectedTab, MerchantFrame.page, MerchantFrame.level = false, 1, 1, 5
for i = 1, 12 do
    local item = Widget(MerchantFrame)
    item.ItemButton = Widget(item)
    item.ItemButton.mouse = true
    _G["MerchantItem" .. i], _G["MerchantItem" .. i .. "ItemButton"] = item, item.ItemButton
end
MerchantItem11.shown, MerchantItem12.shown = false, false
MerchantPrevPageButton, MerchantNextPageButton, MerchantPageText = Widget(MerchantFrame), Widget(MerchantFrame), Widget(MerchantFrame)
MerchantPrevPageButton.mouse, MerchantNextPageButton.mouse = true, true
local offers = 30
GetMerchantNumItems = function() return offers end
local nativeUpdates = 0
MerchantFrame_Update = function()
    nativeUpdates = nativeUpdates + 1
    local paged = MerchantFrame.selectedTab == 1 and offers > MERCHANT_ITEMS_PER_PAGE
    for _, control in ipairs({ MerchantPrevPageButton, MerchantNextPageButton, MerchantPageText }) do
        control:SetShown(paged)
    end
    MerchantItem11:SetShown(MerchantFrame.selectedTab == 2)
    MerchantItem12:SetShown(MerchantFrame.selectedTab == 2)
end
MerchantFrame:SetScript("OnShow", function() MerchantFrame_Update() end)
hooksecurefunc = function(name, callback)
    local original = _G[name]
    _G[name] = function(...) original(...); callback(...) end
end
local deferred = {}
C_Timer = { After = function(_, callback) deferred[#deferred + 1] = callback end }
-- Every wait here is for the next frame; the frame clock stands still.
GetTime = function() return 100 end
local function RunFrame()
    local queue = deferred
    deferred = {}
    for _, callback in ipairs(queue) do callback() end
end
wipe = function(t) for key in pairs(t) do t[key] = nil end return t end

-- Offers: 1 an epic sword with an item level, 2 paid in a currency, 3 at a
-- high price and not refundable, 4 sold in stacks of 20, 5 still loading.
local loaded = { [5] = false }
local infoReads = 0
C_MerchantFrame = {
    GetItemInfo = function(index)
        infoReads = infoReads + 1
        if index > offers then return nil end
        local info = { name = "Offer " .. index, texture = 100 + index, price = 10, stackCount = 1, numAvailable = -1,
            isPurchasable = true, isUsable = true, hasExtendedCost = false, isQuestStartItem = false }
        if index == 1 then info.name = "Sword" end
        if index == 2 then info.price, info.hasExtendedCost = 0, true end
        if index == 3 then info.price = 2000000 end
        if index == 4 then info.stackCount = 20 end
        if index == 6 then info.isUsable, info.numAvailable = false, 3 end
        return info
    end,
    IsMerchantItemRefundable = function(index) return index ~= 3 end,
}
GetMerchantItemLink = function(index) if index <= offers then return "item:" .. index end end
GetMerchantItemID = function(index) return index end
GetMerchantItemCostInfo = function(index) return index == 2 and 1 or 0 end
GetMerchantItemCostItem = function(index, i) if index == 2 and i == 1 then return 777, 50, nil, "Valorstones" end end
GetMerchantItemMaxStack = function(index) return index == 4 and 200 or 1 end
CanAffordMerchantItem = function(index) return index ~= 3 end
GetMoney = function() return 1000000 end
local requests = {}
C_Item = {
    GetItemInfo = function(link)
        local id = tonumber(link:match("%d+"))
        if loaded[id] == false then return nil end
        return "Offer", link, id == 1 and 4 or 1
    end,
    IsEquippableItem = function(link) return link == "item:1" end,
    GetDetailedItemLevelInfo = function() return 600.4 end,
    GetItemCount = function() return 0 end,
    RequestLoadItemDataByID = function(id) requests[#requests + 1] = id end,
}
C_Heirloom = { IsItemHeirloom = function() return false end, PlayerHasHeirloom = function() return false end }
C_CurrencyInfo = { GetCoinTextureString = function(value) return value .. "c" end,
    GetCurrencyContainerInfo = function() return nil end }
CreateSimpleTextureMarkup = function(texture) return "|T" .. texture .. "|t" end
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 }, [4] = { r = .64, g = .21, b = .93 } }
TEXTURE_ITEM_QUEST_BANG = "bang"
local bought, picked = {}, {}
BuyMerchantItem = function(index, quantity) bought[#bought + 1] = { index, quantity } end
PickupMerchantItem = function(index) picked[#picked + 1] = index end
local cursor, modifier, chatLink = nil, nil, false
GetCursorInfo = function() return cursor end
IsModifiedClick = function(kind) if kind then return modifier == kind end return modifier ~= nil end
HandleModifiedItemClick = function() return chatLink end
local tooltip = {}
GameTooltip = { SetOwner = function(_, owner) tooltip.owner = owner end,
    SetMerchantItem = function(_, index) tooltip.index = index end }
GameTooltip_ShowCompareItem = function() end
GameTooltip_HideResetCursor = function() end
SetCursor = function(kind) tooltip.cursor = kind end

-- Blizzard's generic dialogs; tests answer them.
local dialogs = dofile(root .. "/tools/tests/suite_test_support.lua").StaticPopups()
local function Confirmation() return dialogs.Last("GENERIC_CONFIRMATION") end
local function QuantityPrompt() return dialogs.Last("GENERIC_INPUT_BOX") end

local S, modules, printed = { instances = {} }, {}, {}
S.Public = function(value) return value ~= "secret" end
S.PublicText = function(value) return S.Public(value) and type(value) == "string" and value ~= "" and value or nil end
S.Finite = function(value) return S.Public(value) and type(value) == "number" and value == value end
S.Text = function(value) return value end
S.BlizzardText = function(_, fallback) return fallback end
S.SetFont = function(w, ...) w:SetFont(...) end
S.Dispatch = function(callback, ...) return callback(...) end
-- Every frame the list creates, and how many were created with a parent.
local created, parentedCreates = {}, 0
S.CreateFrame = function(kind, _, parent, template)
    templates[#templates + 1] = template or false
    if parent ~= nil then parentedCreates = parentedCreates + 1 end
    local frame = Widget(parent)
    frame.kind = kind
    created[#created + 1] = frame
    return frame
end
S.CreateTexture = function(parent) return Widget(parent) end
S.CreateFontString = S.CreateTexture
S.Install = function(id, module) modules[id] = module end
local combat = false
local NS = { Safety = { IsForbidden = function() return false end }, IsCombatLocked = function() return combat end,
    Print = function(text) printed[#printed + 1] = text end, Dispatch = S.Dispatch }
-- S.Debounce and the context timers (MSUF_Suite_Modules/Timers.lua).
local TimerContext = dofile(root .. "/tools/tests/suite_test_support.lua").ModuleTimers(root, S, NS)
-- Context:HideControl as MSUF_Suite_Modules/Runtime.lua runs it: alpha and
-- mouse are recorded and restored, never Show/Hide; in combat it only queues.
local queued = false
local function Context()
    local context = { events = {}, records = {} }
    function context:Event(name, callback) self.events[name] = callback end
    function context:RemoveEvent(name) self.events[name] = nil end
    function context:HideControl(frame, hidden)
        local record = self.records[frame]
        if hidden then
            if combat then queued = true return end
            if not record then self.records[frame] = { alpha = frame:GetAlpha(), mouse = frame:IsMouseEnabled() } end
            frame:SetAlpha(0)
            frame:EnableMouse(false)
        elseif record then
            frame:SetAlpha(record.alpha)
            frame:EnableMouse(record.mouse)
            self.records[frame] = nil
        end
    end
    return context
end
-- The Suite's questions (S.Confirm, S.AskText) live in MSUF_Suite_Modules/Dialogs.lua.
assert(loadfile(root .. "/MSUF_Suite_Modules/Dialogs.lua"))("MSUF_Suite_Modules", { Suite = S })
for _, file in ipairs({ "MerchantWatch", "SharedItems", "MerchantList" }) do
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/" .. file .. ".lua"))("test", { NS = NS, Suite = S })
end
local list = modules.merchantList
list.active, list.context, list.config = true, TimerContext("merchantList", list, Context()), { rowHeight = 44 }
list:Enable()
Check(not list.panel or not list.panel.shown, "the list showed without an open merchant")


MerchantFrame:Show()
NS.DB = {}
NS.InCombat=function() return combat end
local scenario = arg[2] or "accept_replaced"
local refunds, clears, cursorGUID = {}, 0, "A"
local slotGUID = "A"
cursor = "item"
C_Cursor = { GetCursorItem = function() if cursor ~= "item" then return nil end return {
    IsBagAndSlot = function() return true end, GetBagAndSlot = function() return 0, 3 end,
    IsEquipmentSlot = function() return false end, GetItemGUID = function() return cursorGUID end,
} end }
C_Container = {
    GetContainerItemPurchaseInfo = function() return { refundSeconds = 3600, money = 5000, itemCount = 0, currencyCount = 0 } end,
    GetContainerItemLink = function() return "item:" .. slotGUID end,
    ContainerRefundItemPurchase = function() refunds[#refunds + 1] = slotGUID end,
}
C_Item.GetItemGUID = function(location)
    if location.GetItemGUID then return location:GetItemGUID() end
    return slotGUID
end
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
ClearCursor = function() clears = clears + 1 end
list.rows[1].scripts.OnClick(list.rows[1], "LeftButton")
local question = assert(Confirmation(), "refund question missing")
if scenario == "accept_replaced" then
    slotGUID, cursorGUID = "B", "B"
    dialogs.Accept(question)
    print("refunds=" .. #refunds .. ", refundedGUID=" .. tostring(refunds[1]))
    assert(#refunds == 0, "original A confirmation refunded different B")
elseif scenario == "cancel_foreign" then
    cursorGUID = "B"
    dialogs.Cancel(question)
    print("cursor clears=" .. clears)
    assert(clears == 0, "refund decline cleared unrelated B cursor")
elseif scenario == "cancel_unreadable" then
    cursorGUID = "secret"
    dialogs.Cancel(question)
    assert(clears == 0, "refund decline cleared an unreadable cursor")
elseif scenario == "cancel_empty" then
    cursor = nil
    cursorItem = nil
    dialogs.Cancel(question)
    assert(clears == 0, "refund decline cleared an empty cursor")
elseif scenario == "cancel_original" then
    dialogs.Cancel(question)
    assert(clears == 1, "refund decline failed to return original A")
elseif scenario == "accept_disabled" then
    list.active = false
    dialogs.Accept(question)
    assert(#refunds == 0, "disabled merchant list refunded original A")
elseif scenario == "accept_profile" then
    NS.DB = {}
    dialogs.Accept(question)
    assert(#refunds == 0, "old merchant refund question survived a profile change")
elseif scenario == "original" then
    dialogs.Accept(question)
    assert(#refunds == 1 and refunds[1] == "A", "original item refund failed")
    print("original refund preserved")
end

end

cases.nameplate_flags = function(root, variant, flavor)
    local arg = {root, variant}
local root = assert(arg[1])
local scenario=arg[2] or "stacking"
local live, saved, module = {}, {}, nil
local NS = { Client = { isForever = false, isMainline = true }, Text = function(v) return v end,
    Public = function() return true end, InCombat = function() return false end,
    Safety = { IsForbidden = function() return false end } }
local S = { Install = function(_, m) module = m end,
    RestoreCVar = function(_, key)
        if saved[key] ~= nil then live[key], saved[key] = saved[key], nil end
    end }
local function noop() end
local function helper() return setmetatable({}, { __index = function() return noop end }) end
C_CVar = { GetCVar = function(key) return live[key] end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/NameplateStyle.lua"))("MSUF_Suite", NS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/Nameplates.lua"))("MSUF_Suite", NS)
local P = { NS = NS, Suite = S }
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Modes.lua"))("MSUF_Suite_Nameplates", P)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/CVars.lua"))("MSUF_Suite_Nameplates", P)
for _, name in ipairs({ "Layout", "Roles", "Text", "Power", "Threat", "Level", "CastTime", "Auras", "KickReady", "Selection", "AuraColors", "Geometry" }) do P[name] = helper() end
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Decor.lua"))("MSUF_Suite_Nameplates", P)
assert(loadfile(root .. "/MSUF_Suite_Nameplates/Skin.lua"))("MSUF_Suite_Nameplates", P)
module.context = { CVar = function(_, key, value)
    if saved[key] == nil then saved[key] = live[key] end
    live[key] = value
    return true
end }
module.config = {}
for key, rule in pairs(NS.SuiteCatalog.nameplates.rules) do module.config[key] = rule.default end
module.config.enemyTextMode, module.config.enemyRarityIcon = 1, 1
local flagKey,showKey = "nameplateStackingTypes","plateStackEnemy"
module.config.plateStackEnemy, module.config.plateStackFriendly = 2, 1
if scenario=="simplified" then
    flagKey,showKey="nameplateSimplifiedTypes","plateSimpleMinion"
    module.config.plateStackEnemy=1
    for _,key in ipairs({"plateSimpleMinion","plateSimpleMinus","plateSimpleFriendlyPlayer","plateSimpleFriendlyNpc"}) do module.config[key]=1 end
    module.config.plateSimpleMinion=2
end
live[flagKey] = string.char(1, 66)
module.active = true
module.questJob = { Cancel = noop }
P.CVars.Apply(module)
assert(live[flagKey]:byte(2) - 64 == 3)
if scenario=="unchanged" then
    P.CVars.Apply(module)
    assert(live[flagKey]:byte(2)-64==3,"unchanged native flags drifted")
    return
end
if scenario=="all_keep" then
    module.config[showKey]=1
    P.CVars.Apply(module)
    assert(live[flagKey]:byte(2)-64==2,"all Keep did not restore native flags")
    module.config[showKey]=2
end
module.active = false
module:Disable() -- Actual public lifecycle; does it forget the prior native flags?
for key, value in pairs(saved) do live[key], saved[key] = value, nil end -- Context Release restores owned CVars.
live[flagKey] = string.char(1, 64)
module.active = true
P.CVars.Apply(module)
local flags = live[flagKey]:byte(2) - 64
print("new activation, enemy=Show, friendly=Keep, native baseline=0, applied mask=" .. flags)
assert(flags == 1, "Keep Blizzard setting reused prior activation's friendly flag")

end

cases.options_color = function(root, variant, flavor)
    local arg = {root, variant}
local root=assert(arg[1])
local captured,writes
local P={S={},M={},T={},Tr=function(v) return v end,HM={ReleaseColorShortcut=function() end},
    catalog={actionbars={rules={bar1BackgroundColor={default='102030'},bar2BackgroundColor={default='203040'}}}},
    W={AttachContextColorShortcut=function(_,opts) captured=opts;return {} end},
    Suite={RGB=function(v) return v end}}
local scenario=arg[2] or 'retarget'
local moduleID=scenario=='removed' and 'dataTexts' or 'actionbars'
P.catalog.dataTexts=P.catalog.actionbars
local selected=1
MSUF_NS={Client={Flavor='Mainline',IsForever=false}}
securecallfunction=function(fn,...) return fn(...) end
assert(loadfile(root..'/MSUF_Suite/Core/Platform.lua'))('MSUF_Suite',P.Suite)
P.S.Config=function() return P.Suite.DB end
P.Suite.DB=scenario=='default' and {} or {bar1BackgroundColor='102030',bar2BackgroundColor='203040',barIds='1,2'}
P.Get=function(_,key) return P.S.Config()[key] or P.catalog.actionbars.rules[key].default end
P.Set=function(_,key,value) writes=key;P.S.Config()[key]=value;return true end
assert(loadfile(root..'/MSUF_Suite_Options/Menu/Controls.lua'))('MSUF_Suite_Options',P)
P.AttachRuleColors({},'Bar colors',moduleID,{{key='bar1BackgroundColor',label='Background color',color=true}},
    function(key) return key:gsub('^bar1','bar'..selected) end)
local target=captured.getTargets()[1]
assert(target.settingKey=='msufsuite.'..moduleID..'.bar1BackgroundColor')
if scenario=='default' then
    local r,g,b=target.get()
    local er,eg,eb=P.Suite.RGB('102030')
    assert(r==er and g==eg and b==eb,'unmaterialized color did not use catalog default')
    return
end
if scenario=='retarget' then selected=2
elseif scenario=='removed' then P.Suite.DB.barIds='2'
elseif scenario=='profile' then P.Suite.DB={};P.Suite.Registry.NotifyListeners('profile') end
target.set(1,0,0)
print('picker target='..target.settingKey..', actual written key='..tostring(writes))
if scenario=='original' then assert(writes=='bar1BackgroundColor','original target stopped writing its color')
elseif scenario=='profile' then assert(writes==nil,'old color target wrote a different profile')
elseif scenario=='removed' then assert(writes==nil,'old color target wrote a removed dynamic bar')
else assert(writes==nil or writes=='bar1BackgroundColor','bar1 color picker silently wrote selected bar2') end

end

cases.options_secure = function(root, variant, flavor)
    local arg = {root, variant}
local root = assert(arg[1])
local created, refreshers = {}, {}
local scenario = arg[2] or 'disabled_macro'
local function Widget()
    local f = { shown = true, enabled = true, attrs = {}, scripts = {}, level = 2 }
    function f:SetPoint() end
    function f:SetAttribute(k, v) self.attrs[k] = v end
    function f:GetAttribute(k) return self.attrs[k] end
    function f:SetScript(k, v) self.scripts[k] = v end
    function f:GetScript(k) return self.scripts[k] end
    function f:HookScript(k, v) local old=self.scripts[k];self.scripts[k]=function(...) if old then old(...) end;v(...) end end
    function f:SetEnabled(v) self.enabled = v end
    function f:IsEnabled() return self.enabled end
    function f:RegisterForClicks() end
    function f:RegisterEvent() end
    function f:UnregisterEvent() end
    function f:Hide() self.shown=false end
    function f:Show() self.shown=true end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown end
    function f:ClearAllPoints() end
    function f:SetAllPoints() end
    function f:GetFrameStrata() return 'DIALOG' end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameStrata() end
    function f:SetFrameLevel(v) self.level = v end
    created[#created+1] = f
    return f
end
UIParent = Widget()
CreateFrame = Widget
RegisterStateDriver = function() end
InCombatLockdown = function() return false end
local S = {}
MSUFSuite = { Suite=S, SuiteCatalog={}, SuiteOrder={}, Database={}, FontRendering={}, InCombat=function() return false end,
    HostBridge={Menu2=function() return {} end} }
MSUF_NS={Client={Flavor='Mainline',IsForever=false}}
securecallfunction=function(fn,...) return fn(...) end
assert(loadfile(root..'/MSUF_Suite/Core/Platform.lua'))('MSUF_Suite',MSUFSuite)
MSUFSuite.InCombat=function() return false end
assert(loadfile(root..'/MSUF_Suite/Core/FontBridge.lua'))('MSUF_Suite',MSUFSuite)
MSUF2 = { Widgets={}, Theme={Button=Widget}, TrackRefresh=function(_,f) refreshers[#refreshers+1]=f end }
local P = {}
assert(loadfile(root..'/MSUF_Suite_Options/Menu/Bridge.lua'))('MSUF_Suite_Options',P)
local enabled, target = true, Widget()
local originalTarget = target
local button
if scenario:match('^click_') then
    button = P.Button({},UIParent,'Native action',0,0,100,function() end,function() return enabled end)
    P.SecureClick(button,function() return target end)
else
    button = P.SecureMacroButton({},UIParent,'Open Edit Mode',0,0,100,'/editmode',function() return enabled end)
end
button.scripts.OnEnter(button)
local overlay = created[#created]
assert(overlay:IsShown(),'overlay did not attach')
if scenario:match('^click_') then assert(overlay:GetAttribute('clickbutton1') == originalTarget)
else assert(overlay:GetAttribute('macrotext1') == '/editmode') end
if scenario == 'click_retarget' then target = Widget()
elseif scenario ~= 'macro_original' and scenario ~= 'click_original' then enabled = false end
refreshers[#refreshers]()
print('button enabled='..tostring(button:IsEnabled())..', secure overlay shown='..tostring(overlay:IsShown()))
if scenario == 'click_retarget' then
    assert(not overlay:IsShown() or overlay:GetAttribute('clickbutton1') == target,'refreshed action still clicks previous target A')
elseif scenario == 'macro_original' or scenario == 'click_original' then
    assert(button:IsEnabled() and overlay:IsShown(),'unchanged eligible action lost its usable delegate')
else
    assert(not overlay:IsShown(),'disabled menu action still has a usable secure overlay')
end

end

cases.options_source = function(root, variant, flavor)
    local arg = {root, variant}
local root = assert(arg[1])
local frames, writes = {}, 0
local scenario=arg[2] or 'profile'
local function Widget()
    local w = { shown=true, scripts={}, text='' }
    setmetatable(w,{__index=function() return function() end end})
    function w:SetScript(k,v) self.scripts[k]=v end
    function w:HookScript(k,v) local old=self.scripts[k];self.scripts[k]=function(...) if old then old(...) end;v(...) end end
    function w:SetSize(x,y) self.width,self.height=x,y end
    function w:Hide() local old=self.shown;self.shown=false;if old and self.scripts.OnHide then self.scripts.OnHide(self) end end
    function w:Show() local old=self.shown;self.shown=true;if not old and self.scripts.OnShow then self.scripts.OnShow(self) end end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown end
    function w:SetShown(v) if v then self:Show() else self:Hide() end end
    function w:SetText(v) self.text=v;if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
    function w:GetText() return self.text end
    function w:CreateTexture() return Widget() end
    frames[#frames+1]=w
    return w
end
UIParent=Widget()
CreateFrame=Widget
local a,b={bar1Slot1=1},{bar1Slot1=1}
local current=a
local combat=false
local Suite={DB=a, DataTextSources={'None','Clock'},DataTextSourceKeys={'none','clock'}}
MSUF_NS={Client={Flavor='Mainline',IsForever=false}}
securecallfunction=function(fn,...) return fn(...) end
assert(loadfile(root..'/MSUF_Suite/Core/Platform.lua'))('MSUF_Suite',Suite)
local P={Suite=Suite,HM={SkipHistoryCheckpoint=function() end},M={frame=UIParent},
    T={Button=Widget,colors={text={}}},Tr=function(v) return v end,Combat=function() return combat end,
    Text=Widget,SetButtonText=function() end,SetTranslatedText=function() end}
P.S={Config=function() return current end}
P.Get=function(_,key) return current[key] end
P.Set=function(_,key,value) writes=writes+1;current[key]=value;return true end
assert(loadfile(root..'/MSUF_Suite_Options/Pages/DataTextsSourcePicker.lua'))('MSUF_Suite_Options',P)
local anchor=Widget()
assert(P.DataTextsSourcePicker.Open(anchor,1,1))
local popup
for _,frame in ipairs(frames) do if frame.width==430 and frame.height==468 then popup=frame end end
assert(popup and popup.rows[1],'picker did not materialize actual choices')
if scenario=='profile' or scenario=='profile_aba' then
    current,Suite.DB=b,b
    Suite.Registry.NotifyListeners('profile')
    if scenario=='profile_aba' then
        current,Suite.DB=a,a
        Suite.Registry.NotifyListeners('profile')
    end
elseif scenario=='combat' then combat=true end
popup.rows[1].scripts.OnClick()
print('new profile source='..b.bar1Slot1..', stale popup writes='..writes)
if scenario=='original' then assert(writes==1 and a.bar1Slot1==2 and b.bar1Slot1==1,'original picker no longer writes its source')
else assert(writes==0 and b.bar1Slot1==1,'source popup outlived its valid session') end

end

cases.options_copy = function(root, variant, flavor)
    local arg = {root, variant}
local root=assert(arg[1])
local scenario=arg[2] or 'profile'
local a={bar1Size=33,bar2Size=22,bar1Visibility=1,bar2Visibility=1}
local b={bar1Size=44,bar2Size=55,bar1Visibility=1,bar2Visibility=1}
local current,writes,question=a,0,nil
MSUF_NS={Client={Flavor='Mainline',IsForever=false}}
securecallfunction=function(fn,...) return fn(...) end
InCombatLockdown=function() return false end
local S={Config=function() return current end,SetMany=function(_,values)
    writes=writes+1;for key,value in pairs(values) do current[key]=value end;return true end}
local rules=setmetatable({},{__index=function(_,key) return {key=key,default=1,max=12} end})
local Suite={Suite=S,SuiteCatalog={actionbars={title='Action bars',rules=rules}},SuiteOrder={},Database={MAX_PROFILE_NAME_BYTES=48},
    ActionBarCount=3,ActionBarEnum={VISIBILITY={NEVER=8}},ActionBarTitles={'Action bar 1','Action bar 2','Action bar 3'},
    HostBridge={Menu2=function() return {} end},DB=a}
assert(loadfile(root..'/MSUF_Suite/Core/Platform.lua'))('MSUF_Suite',Suite)
Suite.InCombat=function() return false end
MSUFSuite=Suite
MSUF2={Widgets={},Theme={},ShowStatusFeedback=function() end}
StaticPopup_ShowCustomGenericConfirmation=function(data) question=data end
local P={}
assert(loadfile(root..'/MSUF_Suite_Options/Menu/Bridge.lua'))('MSUF_Suite_Options',P)
P.Refresh=function() end
if scenario:match('^save_') then
    Suite.SuiteProfiles={SaveAs=function() writes=writes+1;return true end}
    StaticPopup_Show=function(_,_,_,data)
        question=data
        return {GetEditBox=function() return {GetMaxBytes=function() return 256 end,SetMaxBytes=function() end} end}
    end
    assert(P.SaveSetupAs())
    assert(question and question.callback,'real Save as did not ask for a name')
    if scenario~='save_original' then
        current,Suite.DB=b,b
        Suite.Registry.NotifyListeners('profile')
        if scenario=='save_aba' then current,Suite.DB=a,a;Suite.Registry.NotifyListeners('profile') end
    end
    question.callback('New setup')
    if scenario=='save_original' then assert(writes==1,'original Save as stopped working')
    else assert(writes==0,'old Save as dialog saved a different profile session') end
    return
end
assert(loadfile(root..'/MSUF_Suite_Options/Pages/ActionBars.lua'))('MSUF_Suite_Options',P)
local found,seen={},{}
local function Visit(fn)
    if type(fn)~='function' or seen[fn] then return end
    seen[fn]=true
    for index=1,60 do
        local name,value=debug.getupvalue(fn,index)
        if not name then break end
        if type(value)=='function' then found[name]=value;Visit(value) end
    end
end
Visit(P.pages[1].build)
assert(found.SelectCopyDestination and found.RunCopyTo,'real copy callbacks were not found')
found.SelectCopyDestination('all')
found.RunCopyTo({Hide=function() end})
assert(question and question.callback,'Copy All did not open its real confirmation')
if scenario=='profile' or scenario=='profile_aba' then
    current,Suite.DB=b,b
    Suite.Registry.NotifyListeners('profile')
    if scenario=='profile_aba' then current,Suite.DB=a,a;Suite.Registry.NotifyListeners('profile') end
end
question.callback()
print('copy writes='..writes..', profile B bar2Size='..b.bar2Size)
if scenario=='original' then assert(writes==1 and a.bar2Size==33,'original Copy All stopped working')
else assert(writes==0 and b.bar2Size==55,'old Copy All confirmation rewrote a replacement profile') end

end

cases.options_crests = function(root, variant, flavor)
    local arg = {root, variant}
local root=assert(arg[1])
local scenario=arg[2] or 'profile'
local a,b={crestCurrencyIDs='10',crestCurrencies='1'},{crestCurrencyIDs='20',crestCurrencies='2'}
local current,writes,callback,clear=a,0,nil,nil
local menu={}
function menu:CreateCheckbox(_,_,run) callback=run end
function menu:CreateButton(_,run) clear=run;return {SetResponse=function() end} end
function menu:CreateTitle() end
function menu:CreateDivider() end
function menu:SetScrollMode() end
C_CurrencyInfo={GetCurrencyInfo=function() return {name='Ten'} end,GetCurrencyListSize=function() return 0 end}
local Suite={DataTextCrestMode={SELECTED=2,OBSERVED=1},DB=a}
MSUF_NS={Client={Flavor='Mainline',IsForever=false}}
securecallfunction=function(fn,...) return fn(...) end
assert(loadfile(root..'/MSUF_Suite/Core/Platform.lua'))('MSUF_Suite',Suite)
local build
local P={Suite=Suite,S={Config=function() return current end},Tr=function(v) return v end,
    RegisterPage=function(spec) build=spec.build end,Combat=function() return false end}
P.Get=function(_,key) return current[key] end
P.SetMany=function(_,values) writes=writes+1;for k,v in pairs(values) do current[k]=v end;return true end
P.ContextMenu=function(owner,generator) generator(owner,menu) end
Suite.Suite, Suite.SuiteCatalog, Suite.SuiteOrder = P.S, {}, {}
Suite.Database, Suite.HostBridge = {}, {Menu2=function() return {} end}
MSUFSuite, MSUF2 = Suite, {Widgets={},Theme={}}
Suite.InCombat=P.Combat
local bridge={}
assert(loadfile(root..'/MSUF_Suite_Options/Menu/Bridge.lua'))('MSUF_Suite_Options',bridge)
P.ProfileGuard=bridge.ProfileGuard
assert(loadfile(root..'/MSUF_Suite_Options/Pages/DataTexts.lua'))('MSUF_Suite_Options',P)
local found,seen={},{}
local function Visit(fn)
    if type(fn)~='function' or seen[fn] then return end
    seen[fn]=true
    for i=1,60 do local name,value=debug.getupvalue(fn,i);if not name then break end
        if type(value)=='function' then found[name]=value;Visit(value) end
    end
end
Visit(build)
if scenario:match('^stage_') then
    P.S.DataTextExtraSources={CrestChoices=function() return {{order=1,currencyID=10}} end}
    assert(found.SeasonStagesMenu,'real stage chooser callback missing')({})
else
    assert(found.CrestCurrencyMenu,'real crest chooser callback missing')({})
end
assert(callback and clear,'real chooser did not produce callbacks')
if scenario~='original' and scenario~='stage_original' then
    current,Suite.DB=b,b;Suite.Registry.NotifyListeners('profile')
    if scenario=='profile_aba' then current,Suite.DB=a,a;Suite.Registry.NotifyListeners('profile') end
end
if scenario=='clear_profile' or scenario=='stage_clear' then clear() else callback() end
print('new profile crests='..b.crestCurrencyIDs..', stale writes='..writes)
if scenario=='stage_original' then assert(writes==1 and a.crestCurrencies=='','original stage toggle stopped working')
elseif scenario=='original' then assert(writes==1 and a.crestCurrencyIDs=='','original crest toggle stopped working')
else assert(writes==0 and b.crestCurrencyIDs=='20' and b.crestCurrencies=='2','old crest chooser overwrote a replacement profile') end

end

local root, name = assert(arg[1], "repository root required"), assert(arg[2], "case required")
assert(cases[name], "unknown lifecycle case " .. name)(root, arg[3], arg[4])

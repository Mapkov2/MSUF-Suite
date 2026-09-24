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
    for _, key in ipairs({ "SetDrawLayer", "SetJustifyH", "SetShadowOffset", "SetShadowColor" }) do
        font[key] = function() end
    end
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
    GetScaledRect = function(self)
        local scale = self.scale
        local right = 1000 + self.point[4] * scale
        local bottom = self.point[5] * scale
        return right - 430 * scale, bottom, 430 * scale, 700 * scale
    end,
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
    GetScaledRect = function(self)
        local scale = self.scale
        local right = 1000 + self.point[4] * scale
        local bottom = self.point[5] * scale
        return right - 180 * scale, bottom, 180 * scale, 400 * scale
    end,
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
C_Container = { GetContainerItemInfo = function(_, slot)
    infoCalls = infoCalls + 1
    return items[slot]
end }
C_Item = {
    IsEquippableItem = function(link) return link ~= "food" end,
    GetDetailedItemLevelInfo = function(link) levelCalls = levelCalls + 1; return levels[link] end,
    RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end,
}
GetCVar = function() return bagMode end
GetItemQualityColor = function(quality) return quality == 4 and 0.7 or 1, 0.5, 1 end

local S = {
    Public = function(value) return value ~= "secret" end,
    CreateFontString = function(parent) local font = Font(); font.parent = parent; return font end,
    CreateFrame = function(_, _, parent) return VisualFrame(parent) end,
    CreateTexture = function(parent) return Texture(parent) end,
    RGB = function(hex)
        return tonumber(hex:sub(1, 2), 16) / 255,
            tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255
    end,
    ResolveFont = function() return nil end,
    SetFont = function(font, _, size) font.size = size end,
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
        for key, value in pairs(values) do module.config[key] = value end
        module:Refresh()
        return true
    end,
    editMode = false,
}
local state = { IsCombatLocked = function() return combat end,
    RootDB = { suiteGold = { ["Player-test"] = 100000 } }, loginKind = "login",
    goldSessionCaptured = true }
assert(loadfile(root .. "/MSUF_Suite_Bags/Bags.lua"))("MSUF_Suite_Bags", {
    NS = state, Suite = S,
})
assert(module and #fonts == 0 and #textures == 0 and not next(hooks), "dormant module did work before enable")

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
module.config = { showItemLevel = true, itemLevelSize = 12, font = "", qualityColor = true,
    showSessionGold = true,
    windowScale = 1, windowMoved = false, windowX = 0, windowY = 0,
    styleWindows = false, backgroundColor = "14181b", backgroundOpacity = 98, accentColor = "9f8960",
    reagentWindowMoved = false, reagentWindowX = 0, reagentWindowY = 0 }
module.context, module.active = context, true
module:Enable()
assert(bagMode == "1" and hooks.UpdateItems and hooks.OnShow, "combined bag or hooks missing")
assert(#textures == 23 and module.windows[ContainerFrameCombinedBags]
    and module.windows[ContainerFrame6] and textures[2].color[4] == 0.98,
    "combined and reagent bag backgrounds were not styled on enable")
local combinedStyle, reagentStyle = module.windows[ContainerFrameCombinedBags], module.windows[ContainerFrame6]
assert(combinedStyle.goldLabel and combinedStyle.goldLabel.text == "Session 0c"
    and combinedStyle.goldLabel.width == 210
    and combinedStyle.goldLabel.parent == ContainerFrameCombinedBags.MoneyFrame
    and combinedStyle.goldLabel.point[2] == ContainerFrameCombinedBags.MoneyFrame
    and context.events.PLAYER_MONEY and context.events.PLAYER_ENTERING_WORLD,
    "the combined bag did not show the login gold baseline")
money = 112345
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Session +1g 23s 45c"
    and combinedStyle.goldLabel.color[2] > combinedStyle.goldLabel.color[1],
    "gold gains did not update from the money event")
money = 90000
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Session -1g"
    and combinedStyle.goldLabel.color[1] > combinedStyle.goldLabel.color[2],
    "gold losses did not update from the money event")
money = "secret"
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Session —", "unknown money showed a stale gain or loss")
money = 100000
module.config.showSessionGold = false
module:Refresh()
assert(not combinedStyle.goldLabel.shown and not context.events.PLAYER_MONEY,
    "disabled session gold kept its label or event")
module.config.showSessionGold = true
module:Refresh()
assert(combinedStyle.goldLabel.shown and context.events.PLAYER_MONEY
    and combinedStyle.goldLabel.text == "Session 0c", "session gold did not return when enabled")
state.goldSessionCaptured = false
state.RootDB.suiteGold["Player-test"] = 999999
money = 120000
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Session 0c"
    and state.RootDB.suiteGold["Player-test"] == 120000 and state.goldSessionCaptured,
    "an unreadable login baseline leaked a stale session change")
money = 130000
context.events.PLAYER_MONEY(module, "PLAYER_MONEY")
assert(combinedStyle.goldLabel.text == "Session +1g",
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
assert(buttons[3].emptyBackgroundAtlas == false and buttons[3].emptyIcon == nil
    and buttons[3].ItemSlotBackground.alpha == 0
    and module.overlays[buttons[3]].slotOuter.color
    and module.overlays[buttons[3]].slotInner.color,
    "empty combined slots still draw Blizzard's embossed bag artwork")
assert(buttons[1].emptyBackgroundAtlas == false and buttons[1].textureCalls == nil,
    "styling replaced a loaded item icon")
ContainerFrame6.shown = true
hooks.ReagentOnShow()
assert(#textures == 25 and reagentButton.emptyBackgroundAtlas == false
    and reagentButton.emptyIcon == nil and module.overlays[reagentButton].slotOuter.shown,
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
assert(hooks.NativeAnchors and nativeLayouts > 0 and module.config.windowX == -40
    and module.config.windowY == 32 and ContainerFrameCombinedBags.scale == 0.9,
    "the Suite bag window did not preserve Blizzard's initial placement")
module:RegisterMovers()
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
    and infoCalls == infoBefore + 2,
    "unchanged native bag refresh repeated the slot walk or queried empty slots")
local originalHasItem = buttons[1].HasItem
buttons[1].HasItem = function() return "secret" end
infoBefore = infoCalls
hooks.UpdateItems()
assert(infoCalls == infoBefore + 2,
    "unknown HasItem state skipped a potentially occupied slot")
buttons[1].HasItem = originalHasItem

items[1] = { hyperlink = "gear-b", itemID = 103, quality = 4 }
hooks.UpdateItems()
assert(module.overlays[buttons[1]].label.text == "651", "changed slot kept its old item level")
items[3] = { hyperlink = "gear-loading", itemID = 104, quality = 2 }
hooks.UpdateItems()
assert(requests[104] == 1 and context.events.GET_ITEM_INFO_RECEIVED
    and not module.overlays[buttons[3]].label.shown, "missing item data was not deferred")
hooks.UpdateItems()
assert(requests[104] == 1, "pending item data was requested repeatedly")
items[2] = { hyperlink = "gear-loading", itemID = 104, quality = 2 }
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
    and infoCalls == infoBefore + 2 and enumerations == enumerationsBefore,
    "item data completion rescanned the bag or missed a duplicate item")
items[2] = { hyperlink = "food", itemID = 102, quality = 1 }
hooks.UpdateItems()
items[3] = { hyperlink = "gear-vanished", itemID = 105, quality = 2 }
hooks.UpdateItems()
assert(requests[105] == 1 and module.requested[105], "new missing item data was not requested")
items[3] = nil
hooks.UpdateItems()
assert(not module.requested[105] and not context.events.GET_ITEM_INFO_RECEIVED,
    "a removed item left a stale request or item event")
items[3] = { hyperlink = "gear-vanished", itemID = 105, quality = 2 }
hooks.UpdateItems()
assert(requests[105] == 2, "a returning item could not request its missing data again")
items[3] = nil
hooks.UpdateItems()

module.config.itemLevelSize = 15
module:Refresh()
assert(module.overlays[buttons[1]].label.size == 15, "font setting did not refresh")
module.config.showItemLevel = false
module:Refresh()
assert(not module.overlays[buttons[1]].label.shown, "turning labels off left text visible")
local hideCalls = module.overlays[buttons[1]].label.hideCalls
hooks.UpdateItems()
assert(module.overlays[buttons[1]].label.hideCalls == hideCalls,
    "disabled item levels kept repainting hidden labels on bag updates")
module.config.showItemLevel = true
module:Refresh()
assert(module.overlays[buttons[1]].label.shown, "turning labels on did not repaint")
buttons[4] = {
    emptyBackgroundAtlas = "bags-item-slot64",
    ItemSlotBackground = VisualFrame(),
    GetBagID = function() return 0 end,
    GetID = function() return 4 end,
    HasItem = function() return true end,
    SetItemButtonTexture = buttons[1].SetItemButtonTexture,
}
items[4] = { hyperlink = "gear-a", itemID = 101, quality = 4 }
combat = true
hooks.UpdateItems()
assert(queued > 0 and not module.overlays[buttons[4]].label, "combat created a new label on a native button")
combat = false
module:Refresh()
assert(module.overlays[buttons[4]].label.shown, "queued label was not created after combat")
items[3] = nil
module.active = false
module:Disable()
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
    and buttons[3].emptyIcon == "bags-item-slot64"
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
    and buttons[3].emptyBackgroundAtlas == false
    and buttons[3].emptyIcon == nil
    and buttons[3].ItemSlotBackground.alpha == 0
    and module.overlays[buttons[3]].slotOuter.shown,
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
            windowX = { default = 0 }, windowY = { default = 0 },
            windowMoved = { default = false }, windowScale = { default = 1 },
        } } },
        Public = function() return true end,
        Text = function(value) return value end,
        Config = function() return values end,
        SetMany = function(_, changes)
            for key, value in pairs(changes) do values[key] = value end
            return true
        end,
    }
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
end
print("Suite bags: window styling, native bag layout, item levels, cache, and disable passed")

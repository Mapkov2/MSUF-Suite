-- Player aura layout (QoL playerAuras) per player UNIT_AURA, on a model of
-- Blizzard_BuffFrame (live 12.1.5 BuffFrame.lua; Forever 1.60.1 the same):
--   * every UNIT_AURA that adds, removes or updates an aura runs both frames'
--     Update -> UpdateAuras, UpdateAuraButtons (283-295);
--   * DebuffFrame's UpdateAuraButtons ends in UpdateGridLayout (751-754), which
--     lays out only enabled buttons (doNotAnchorDisabledFrames) and resets
--     their scale, size, points, Icon and Duration anchors (147-163) and the
--     AuraContainer anchor;
--   * a refill shows, hides and refills buttons: SetTexture keeps TexCoords,
--     fonts and native border sizes stay (Update, 1049-1103);
--   * Edit Mode's first refill resets every Duration font object (374);
--   * both frames are Edit Mode systems: SetPoint and ClearAllPoints are Lua
--     overrides, SetPoint marks Edit Mode's anchors dirty
--     (EditModeSystemTemplates.lua 9-17, 147-156); ApplySystemAnchor places
--     the frame and UpdateSystem then lays the auras out (1945-1948);
--   * BuffFrame anchors its container to CollapseAndExpandButton (554);
--   * StatusTrayManager re-anchors a default-placed BuffFrame on its own.
-- 32 buff buttons; 16 debuff buttons and 6 private aura anchors.
-- Three numbers per scenario, as in suite_hot_event_native_budget_contract:
--   instructions  VM instructions of shipped Suite code (client stand-ins and
--                 the Blizzard model are not counted);
--   KB            allocation in a second pass, GC stopped;
--   natives       client API calls made by shipped Suite code, per API.
-- Scenarios with 20 buffs and 5 debuffs shown:
--   refresh       an aura refreshed (same shown buttons): the common case;
--   combatRefresh the same in combat lockdown (the raid case: unprotected
--                 native buttons are still written, after IsProtected);
--   buffGain      one buff gained (20 -> 21);
--   debuffGain    one debuff gained (5 -> 6).
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")

-- Measured 2026-10-16. A budget may grow by at most 2 %. Natives are budgeted
-- per client API, exactly: an API the table leaves out must not be called.
-- Before this change every UNIT_AURA ran three full repaints of both frames
-- (the UpdateAuraButtons hooks of both frames and DebuffFrame's nested
-- UpdateGridLayout hook): per shown button scale, size, points, icon, crop,
-- a four-edge outline and two fonts, each time.
--   refresh       39045 instr, .019 KB, 4284 natives (SetPoint 855,
--                 ClearAllPoints 630, SetShown 375, SetColorTexture 300,
--                 SetSize 249, SetFont 150, InCombatLockdown 99 ...);
--   combatRefresh 39342 instr, .019 KB, 4383 natives (IsProtected 99);
--   buffGain      40446 instr, .019 KB, 4437 natives;
--   debuffGain    39979 instr, .019 KB, 4386 natives.
-- After: the buff frame reads its 33 buttons (IsShown and issecretvalue) and
-- writes nothing; the debuff frame re-places what Blizzard's UpdateGridLayout
-- has just reset (5 debuffs and 6 private anchors: scale, size, points, icon
-- and duration anchors, and the container). Neither frame moves on an aura
-- update. Artwork, outlines and fonts are painted once per configuration,
-- adoption or Edit Mode switch.
-- 2026-10-17 (independent review): the frames move only after Blizzard moved
-- them; refresh 180 -> 178 natives, buffGain 194 -> 190.
local SHOWN = { IsShown = 55, issecretvalue = 55 }
local function WithShown(extra)
    local budget = {}
    for api, count in pairs(SHOWN) do budget[api] = count end
    for api, count in pairs(extra) do budget[api] = (budget[api] or 0) + count end
    return budget
end
local BASELINE = {
    refresh = { instructions = 1564, natives = WithShown({ ClearAllPoints = 22, InCombatLockdown = 1,
        SetAllPoints = 5, SetPoint = 17, SetScale = 11, SetSize = 12 }) },
    combatRefresh = { instructions = 1744, natives = WithShown({ ClearAllPoints = 22, InCombatLockdown = 1,
        IsProtected = 12, issecretvalue = 12, SetAllPoints = 5, SetPoint = 17, SetScale = 11, SetSize = 12 }) },
    buffGain = { instructions = 1713, natives = WithShown({ ClearAllPoints = 26, InCombatLockdown = 2,
        SetAllPoints = 6, SetPoint = 20, SetScale = 12, SetSize = 14 }) },
    debuffGain = { instructions = 1659, natives = WithShown({ ClearAllPoints = 25, InCombatLockdown = 1,
        SetAllPoints = 6, SetPoint = 19, SetScale = 12, SetSize = 13 }) },
}

------------------------------------------------------------------ native counting
local function ProductCode(source)
    return source:find("/MSUF_Suite[%w_]*/") and not source:find("/tools/", 1, true)
end

-- Natives are counted only in the natives pass; the model records widget
-- state everywhere except the KB pass, where its own tables would count.
local natives, counting, recording = { total = 0, byName = {} }, false, true
-- Whether the function that called a stand-in is shipped code (level 3: the
-- caller of the stand-in that calls this).
local function FromProduct()
    local info = debug.getinfo(3, "S")
    return info and ProductCode((info.source:gsub("\\", "/")))
end
local function Count(name)
    natives.total = natives.total + 1
    natives.byName[name] = (natives.byName[name] or 0) + 1
end
local function Native(name, fn)
    return function(...)
        if counting and FromProduct() then Count(name) end
        return fn(...)
    end
end

-- Secrets raise on any Lua use; only the counted issecretvalue sees them.
local SecretMT = {}
local function Raise(what) return function() error("secret value used in Lua: " .. what, 2) end end
for _, key in ipairs({ "__eq", "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__unm", "__concat",
    "__len", "__call" }) do SecretMT[key] = Raise(key) end
SecretMT.__index, SecretMT.__newindex, SecretMT.__tostring = Raise("index"), Raise("assignment"), Raise("tostring")
local secrets = setmetatable({}, { __mode = "k" })
local function Secret()
    local value = setmetatable({}, SecretMT)
    secrets[value] = true
    return value
end
local function IsSecretValue(value) return value ~= nil and rawget(secrets, value) == true end
issecretvalue = Native("issecretvalue", IsSecretValue)

------------------------------------------------------------------ client widgets
-- Setters whose secret arguments are AllowedWhenUntainted raise when addon
-- code passes one; SetTexCoord, SetAlpha and SetTextColor accept it and add a secret aspect
-- to the region (FrameAPI/TextureBase documentation), which is counted.
local aspectsAdded = 0
local REFUSES_SECRETS = { SetPoint = true, SetSize = true, SetScale = true, SetFont = true, SetShadowColor = true,
    SetShadowOffset = true, SetFrameLevel = true, SetWidth = true, SetHeight = true }
local ADDS_ASPECT = { SetTexCoord = true, SetAlpha = true, SetTextColor = true }
local function SecretArgument(...)
    for index = 1, select("#", ...) do
        if IsSecretValue((select(index, ...))) then return true end
    end
    return false
end

local Methods = { Frame = {}, Texture = {}, FontString = {} }
local function Method(kinds, name, fn)
    local function stand(self, ...)
        if counting and FromProduct() then Count(name) end
        if SecretArgument(...) and FromProduct() then
            if REFUSES_SECRETS[name] then error(name .. " refuses a secret argument from addon code", 2) end
            if ADDS_ASPECT[name] then aspectsAdded = aspectsAdded + 1 end
        end
        return fn(self, ...)
    end
    for kind in kinds:gmatch("%a+") do Methods[kind][name] = stand end
end
-- A getter answers a secret while the region's aspect is secret.
local function Getter(kinds, name, fn)
    Method(kinds, name, function(self, ...)
        if self.secret and self.secret[name] then return Secret(), Secret(), Secret(), Secret() end
        return fn(self, ...)
    end)
end
-- A setter that records state the painted-state comparison reads.
local function Setter(kinds, name, fn)
    Method(kinds, name, function(self, ...)
        if recording then fn(self, ...) end
    end)
end
local ALL = "Frame Texture FontString"
Getter(ALL, "GetWidth", function(self) return self.width end)
Getter(ALL, "GetHeight", function(self) return self.height end)
Getter(ALL, "GetScale", function(self) return self.scale end)
Getter(ALL, "GetAlpha", function(self) return self.alpha end)
Method(ALL, "GetNumPoints", function(self) return #self.points end)
Getter(ALL, "GetPoint", function(self, index) return unpack(self.points[index]) end)
Setter(ALL, "SetPoint", function(self, ...) self.points[#self.points + 1] = { ... } end)
Setter(ALL, "ClearAllPoints", function(self) self.points = {} end)
Setter(ALL, "SetAllPoints", function(self, other)
    self.points = { { "TOPLEFT", other, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", other, "BOTTOMRIGHT", 0, 0 } }
end)
-- Native code never sizes the aura FontStrings; a size there is the module's.
Method(ALL, "SetSize", function(self, w, h)
    self.width, self.height = w, h
    if self.kind == "FontString" then self.sized = true end
end)
Method(ALL, "SetWidth", function(self, w) self.width = w end)
Method(ALL, "SetHeight", function(self, h) self.height = h end)
Method(ALL, "SetScale", function(self, scale) self.scale = scale end)
Method(ALL, "SetAlpha", function(self, alpha) self.alpha = alpha end)
Method(ALL, "IsObjectType", function(self, kind) return self.kind == kind end)
Getter(ALL, "IsShown", function(self) return self.shown end)
Method(ALL, "SetShown", function(self, shown) self.shown = shown and true or false end)
Method(ALL, "Show", function(self) self.shown = true end)
Method(ALL, "Hide", function(self) self.shown = false end)
Getter("Frame", "IsProtected", function(self) return self.protected == true end)
Getter("Frame", "GetFrameLevel", function(self) return self.level end)
Method("Frame", "SetFrameLevel", function(self, level) self.level = level end)
Method("Frame", "EnableMouse", function() end)
Getter("Texture", "GetTexCoord", function(self) return unpack(self.coords) end)
Setter("Texture", "SetTexCoord", function(self, ...) self.coords = { ... } end)
Method("Texture", "SetTexture", function(self, file) self.file = file end)
Setter("Texture", "SetColorTexture", function(self, ...) self.color = { ... } end)
Method("FontString", "GetFont", function(self) return unpack(self.font) end)
Setter("FontString", "SetFont", function(self, ...) self.font = { ... } end)
Setter("FontString", "SetFontObject", function(self)
    self.font, self.color = { "native.ttf", 10, "" }, { 1, .82, 0, 1 }
end)
Getter("FontString", "GetTextColor", function(self) return unpack(self.color) end)
Setter("FontString", "SetTextColor", function(self, ...) self.color = { ... } end)
Method("FontString", "GetShadowColor", function(self) return unpack(self.shadow) end)
Setter("FontString", "SetShadowColor", function(self, ...) self.shadow = { ... } end)
Method("FontString", "GetShadowOffset", function(self) return unpack(self.shadowOffset) end)
Setter("FontString", "SetShadowOffset", function(self, ...) self.shadowOffset = { ... } end)
Method("FontString", "SetText", function(self, text) self.text = text end)

local Meta = {}
for kind, methods in pairs(Methods) do Meta[kind] = { __index = methods } end
local function Widget(kind, width, height)
    return setmetatable({ kind = kind, width = width or 30, height = height or 30, scale = 1, alpha = 1, points = {},
        shown = true, level = 5, coords = { 0, 1, 0, 1 }, font = { "native.ttf", 10, "" }, color = { 1, .82, 0, 1 },
        shadow = { 0, 0, 0, 1 }, shadowOffset = { 1, -1 } }, Meta[kind == "Button" and "Frame" or kind])
end
Methods.Frame.CreateTexture = Native("CreateTexture", function() return Widget("Texture") end)

------------------------------------------------------------------ Blizzard_BuffFrame model
local function AuraButton()
    local button = Widget("Button", 30, 40)
    button.shown = false
    button.Icon = Widget("Texture", 30, 30)
    button.Count, button.Duration = Widget("FontString"), Widget("FontString")
    button.DebuffBorder, button.TempEnchantBorder = Widget("Texture", 40, 40), Widget("Texture", 32, 32)
    -- AuraButtonMixin:Update: artwork and text only; no font, TexCoord or size.
    function button:Update(info)
        self.Icon:SetTexture(info.texture)
        self.Count:SetText(info.count)
    end
    return button
end

local function PrivateAnchor()
    local anchor = Widget("Frame", 30, 40)
    anchor.isAuraAnchor = true
    anchor.Icon, anchor.Duration = Widget("Frame", 30, 30), Widget("Frame", 29, 11)
    return anchor
end

-- AuraContainerMixin:UpdateGridLayout and UpdateAuraContainerAnchor.
local function NativeLayout(frame, auras)
    local slot = 0
    for _, aura in ipairs(auras) do
        if not frame.doNotAnchorDisabledFrames or aura.hasValidInfo or aura.isExample or aura.isAuraAnchor then
            slot = slot + 1
            aura:SetScale(1)
            aura:SetSize(30, 40)
            aura.Icon:ClearAllPoints()
            aura.Icon:SetPoint("TOP", aura, "TOP")
            aura.Duration:ClearAllPoints()
            aura.Duration:SetPoint("TOP", aura.Icon, "BOTTOM")
            aura:ClearAllPoints()
            aura:SetPoint("TOPRIGHT", frame.AuraContainer, "TOPRIGHT", -35 * (slot - 1), 0)
        end
    end
    frame.AuraContainer:ClearAllPoints()
    frame.AuraContainer:SetPoint("TOPRIGHT", frame.containerAnchor, frame.containerPoint)
end

-- AuraFrameEditModeMixin:TryEditModeUpdateAuraButtons, then AuraFrameMixin:UpdateAuraButtons.
local function Refill(frame)
    if frame.isInEditMode then
        if not frame.hasInitializedForEditMode then
            for _, button in ipairs(frame.auraFrames) do
                if button.isAuraAnchor then
                    button:Hide()
                else
                    button.isExample = true
                    button.Duration:SetFontObject("DEFAULT_AURA_DURATION_FONT")
                    button:Show()
                end
            end
            frame.hasInitializedForEditMode = true
        end
        return
    end
    if frame.hasInitializedForEditMode then
        for _, button in ipairs(frame.auraFrames) do
            if button.isAuraAnchor then button:Show() end
        end
    end
    frame.hasInitializedForEditMode = false
    local nextInfo = 1
    for _, button in ipairs(frame.auraFrames) do
        if not button.isAuraAnchor then
            button.isExample, button.hasValidInfo = false, false
            local info = frame.auraInfo[nextInfo]
            nextInfo = nextInfo + 1
            button:SetShown(info ~= nil)
            if info then
                button.hasValidInfo = true
                button:Update(info)
            end
        end
    end
end

local function AuraFrame(buttons, anchors)
    local frame = Widget("Frame", 400, 80)
    frame.AuraContainer, frame.auraFrames, frame.auraInfo, frame.pending = Widget("Frame", 400, 80), {}, {}, {}
    frame.containerAnchor, frame.containerPoint = frame, "TOPRIGHT"
    for _ = 1, buttons do frame.auraFrames[#frame.auraFrames + 1] = AuraButton() end
    for _ = 1, anchors do frame.auraFrames[#frame.auraFrames + 1] = PrivateAnchor() end
    function frame:UpdateAuras() self.auraInfo = self.pending end
    function frame:Update()
        self:UpdateAuras()
        self:UpdateAuraButtons()
    end
    function frame:SetIsEditing(editing) self.isInEditMode = editing end
    function frame:IsEditing() return self.isInEditMode end
    return frame
end

local BuffFrame = AuraFrame(32, 0)
BuffFrame.ConsolidatedBuffs, BuffFrame.CollapseAndExpandButton = AuraButton(), Widget("Frame", 15, 30)
BuffFrame.containerAnchor, BuffFrame.containerPoint = BuffFrame.CollapseAndExpandButton, "TOPLEFT"
BuffFrame.consolidated = { BuffFrame.ConsolidatedBuffs }
for _, button in ipairs(BuffFrame.auraFrames) do BuffFrame.consolidated[#BuffFrame.consolidated + 1] = button end
-- With consolidateBuffs on, SyncToConsolidatedBuffs shows the button and lays
-- out again on every Update (prevShownStatus is an undefined global, 1279-1288).
function BuffFrame:UpdateAuras()
    self.auraInfo = self.pending
    if self.consolidate then
        self.ConsolidatedBuffs:SetShown(true)
        self:UpdateGridLayout()
    end
end
function BuffFrame:RefreshConsolidationFrameVisibility() self.ConsolidatedBuffs:SetShown(self.consolidate == true) end
function BuffFrame:UpdateAuraButtons()
    Refill(self)
    self:RefreshConsolidationFrameVisibility()
end
function BuffFrame:UpdateGridLayout() NativeLayout(self, self.consolidate and self.consolidated or self.auraFrames) end
function BuffFrame:Update()
    self:UpdateAuras()
    self:UpdateAuraButtons()
    self:RefreshConsolidationFrameVisibility()
end

local DebuffFrame = AuraFrame(16, 6)
DebuffFrame.doNotAnchorDisabledFrames = true
DebuffFrameMixin = {}
function DebuffFrameMixin:UpdateAuraButtons()
    Refill(self)
    self:UpdateGridLayout()
end
DebuffFrame.UpdateAuraButtons = DebuffFrameMixin.UpdateAuraButtons
function DebuffFrame:UpdateGridLayout() NativeLayout(self, self.auraFrames) end
_G.BuffFrame, _G.DebuffFrame, Minimap = BuffFrame, DebuffFrame, Widget("Frame", 200, 200)

-- EditModeSystemMixin:OnSystemLoad replaces SetPoint and ClearAllPoints with
-- Lua overrides; each SetPoint marks Edit Mode's anchors dirty.
local anchorDirty, screen = 0, Widget("Frame", 1920, 1080)
local function EditModeSystem(frame, x, y)
    local setPoint, clearAllPoints = Methods.Frame.SetPoint, Methods.Frame.ClearAllPoints
    frame.SetPoint = Native("SetPoint", function(self, ...)
        setPoint(self, ...)
        anchorDirty = anchorDirty + 1
    end)
    frame.ClearAllPoints = Native("ClearAllPoints", function(self) clearAllPoints(self) end)
    function frame:ApplySystemAnchor()
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", screen, "TOPRIGHT", x, y)
    end
    function frame:UpdateSystem()
        self:ApplySystemAnchor()
        self:UpdateGridLayout()
    end
end
EditModeSystem(BuffFrame, -205, -13)
EditModeSystem(DebuffFrame, -205, -155)
-- StatusTrayManager.UpdateTrayAndBuffFrameLayout re-anchors a default-placed
-- BuffFrame (after EDIT_MODE_LAYOUTS_UPDATED and when a help tray shows).
StatusTrayManager = { UpdateTrayAndBuffFrameLayout = function()
    BuffFrame:ClearAllPoints()
    BuffFrame:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -205, -13)
end }

-- Built once per size, so a measured pass allocates nothing of the model's.
local infoLists = {}
local function Infos(count, base)
    local key = base + count
    if not infoLists[key] then
        infoLists[key] = {}
        for index = 1, count do infoLists[key][index] = { texture = base + index, count = 1 } end
    end
    return infoLists[key]
end
-- The client delivers the player's UNIT_AURA to both frames.
local function UnitAura(buffs, debuffs)
    BuffFrame.pending, DebuffFrame.pending = Infos(buffs, 1000), Infos(debuffs, 2000)
    BuffFrame:Update()
    DebuffFrame:Update()
end

hooksecurefunc = function(object, key, hook)
    local original = assert(object[key], key)
    object[key] = function(...)
        local a, b, c = original(...)
        hook(...)
        return a, b, c
    end
end

------------------------------------------------------------------ the shipped module
local function Source(path)
    local file = assert(io.open(root .. path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
-- A shipped function, compiled under its own file name so its instructions count.
local function Shipped(path, pattern, prefix, suffix, ...)
    local block = assert(Source(path):match(pattern), pattern .. " is missing from " .. path)
    local chunk = assert(loadstring((prefix or "") .. "\n" .. block .. "\n" .. (suffix or ""), "@" .. root .. path))
    return chunk(...)
end
local PLATFORM, SURFACES = "/MSUF_Suite/Core/Platform.lua", "/MSUF_Suite_Modules/Surfaces.lua"
local Platform = Shipped(PLATFORM, "\n(function Suite%.RGB%(hex%)\n.-\nend)\n", "local Suite = ...",
    "return Suite", {})
Shipped(PLATFORM, "\n(function Suite%.SharedMedia%(%)\n.-\nend)\n", "local Suite = ...", "", Platform)
Shipped(PLATFORM, "\n(function Suite%.ResolveFont%(key%)\n.-\nend)\n", "local Suite = ...", "", Platform)

local combat, queued, module = false, {}, nil
local S = { RGB = Platform.RGB, ResolveFont = Platform.ResolveFont }
Shipped(SURFACES, "\n(function S%.PlaceEdges%(.-\nend)\n", "local S = ...", "", S)
S.CreateFrame = Native("CreateFrame", function() return Widget("Frame") end)
S.CreateTexture = function(parent) return parent:CreateTexture() end
S.Queue = function(id) queued[id] = true end
S.Install = function(_, instance) module = instance end
-- NS.IsCombatLocked is InCombatLockdown() (MSUF_Suite_Skin/Core/Bootstrap.lua).
local NS = { IsSecret = issecretvalue, IsCombatLocked = Native("InCombatLockdown", function() return combat end),
    MSUFMedia = { font = "msuf.ttf" } }
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/PlayerAuras.lua"))("MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })

local catalogNS = { Client = { isForever = false }, Text = function(text) return text end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLife.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeIndicators.lua"))("MSUF_Suite", catalogNS)
local config = {}
for key, rule in pairs(catalogNS.SuiteCatalog.playerAuras.rules) do config[key] = rule.default end
module.config, module.context, module.active = config, { Event = function() end }, true

------------------------------------------------------------------ the painted state
-- What a player sees of one shown button: its geometry and artwork.
local function Snapshot(frame)
    local rows = {}
    local function Points(region)
        local out = {}
        for index, point in ipairs(region.points) do
            out[index] = table.concat({ tostring(point[1]), tostring(point[3]), tostring(point[4]),
                tostring(point[5]) }, ",")
        end
        return table.concat(out, ";")
    end
    local function Row(index, button)
        if button.shown then
            local row = { index, button.width, button.height, button.scale, Points(button) }
            if not button.isAuraAnchor then
                row[#row + 1] = Points(button.Icon) .. "|" .. table.concat(button.Icon.coords, ",")
                row[#row + 1] = table.concat(button.Duration.font, ",") .. "|" .. Points(button.Duration)
                row[#row + 1] = table.concat(button.Count.font, ",") .. "|" .. Points(button.Count)
                row[#row + 1] = button.DebuffBorder.width .. "x" .. button.DebuffBorder.height
            end
            rows[#rows + 1] = table.concat(row, " ", 1, #row)
        end
    end
    if frame.ConsolidatedBuffs then Row(0, frame.ConsolidatedBuffs) end
    for index, button in ipairs(frame.auraFrames) do Row(index, button) end
    rows[#rows + 1] = Points(frame) .. " / " .. Points(frame.AuraContainer) .. " " .. frame.AuraContainer.width
        .. "x" .. frame.AuraContainer.height
    return table.concat(rows, "\n")
end
-- Every shown button carries the configured geometry, crop, anchors and fonts.
local function Painted(frame, label)
    local offset = frame == DebuffFrame and config.debuffOffset or 0
    assert(#frame.points == 1 and frame.points[1][2] == Minimap, label .. ": the frame left the minimap")
    assert(frame.points[1][4] == config.x and frame.points[1][5] == config.y - offset,
        label .. ": the frame is not at the configured position")
    local buttons = frame.ConsolidatedBuffs and { frame.ConsolidatedBuffs } or {}
    for _, button in ipairs(frame.auraFrames) do buttons[#buttons + 1] = button end
    for _, button in ipairs(buttons) do
        if button.shown then
            assert(button.width == config.iconWidth and button.height == config.iconHeight and button.scale == 1,
                label .. ": a shown button kept native geometry")
            if not button.isAuraAnchor then
                local duration = button.Duration.points
                assert(#duration == 1 and duration[1][1] == "BOTTOMLEFT" and duration[1][2] == button,
                    label .. ": a duration kept its native anchor")
                assert(button.Icon.points[1][2] == button and button.Icon.coords[1] > 0, label .. ": an icon is not cropped")
                assert(button.Duration.font[1] == "msuf.ttf" and button.Count.font[1] == "msuf.ttf",
                    label .. ": a native font remained")
            end
        end
    end
end

-- The incremental paint must leave exactly what a full repaint would.
local function SameAsFullRepaint(label)
    Painted(BuffFrame, label)
    Painted(DebuffFrame, label)
    local buffs, debuffs = Snapshot(BuffFrame), Snapshot(DebuffFrame)
    module:Refresh()
    assert(Snapshot(BuffFrame) == buffs, label .. ": buff frame differs from a full repaint\n" .. buffs)
    assert(Snapshot(DebuffFrame) == debuffs, label .. ": debuff frame differs from a full repaint\n" .. debuffs)
end

------------------------------------------------------------------ measuring
local function Instructions(fn)
    collectgarbage("collect")
    collectgarbage("stop")
    local count = 0
    debug.sethook(function()
        local info = debug.getinfo(2, "S")
        if info and ProductCode(info.source:gsub("\\", "/")) then count = count + 1 end
    end, "", 1)
    fn()
    debug.sethook()
    collectgarbage("restart")
    return count
end

local function Deep(depth, a, b, c, d, e, f, g, h)
    if depth > 0 then return Deep(depth - 1, a, b, c, d, e, f, g, h) + 0 end
    return 0
end

local function Kilobytes(fn)
    collectgarbage("collect")
    collectgarbage("stop")
    Deep(120)
    recording = false
    local before = collectgarbage("count")
    fn()
    local used = collectgarbage("count") - before
    recording = true
    collectgarbage("restart")
    return used
end

local function Natives(fn)
    local before, byName = natives.total, {}
    for name, count in pairs(natives.byName) do byName[name] = count end
    counting = true
    fn()
    counting = false
    local detail, deltas = {}, {}
    for name, count in pairs(natives.byName) do
        local delta = count - (byName[name] or 0)
        if delta > 0 then
            detail[#detail + 1] = name .. "=" .. delta
            deltas[name] = delta
        end
    end
    table.sort(detail)
    return natives.total - before, table.concat(detail, " "), deltas
end

local failures = {}
local function Budget(name, prepare, scenario)
    -- A warm pass first: the first sight of a button records its originals.
    prepare()
    scenario()
    prepare()
    local count = Instructions(scenario)
    prepare()
    local kilobytes = Kilobytes(scenario)
    prepare()
    kilobytes = math.min(kilobytes, Kilobytes(scenario))
    prepare()
    local calls, detail, deltas = Natives(scenario)
    print(string.format("%s %d instr %.3f KB %d natives (%s)", name, count, kilobytes, calls, detail))
    local base = BASELINE[name]
    if count > math.floor(base.instructions * 1.02) then
        failures[#failures + 1] = string.format("%s: %d instructions, baseline %d (+2 %% = %d)", name, count,
            base.instructions, math.floor(base.instructions * 1.02))
    end
    if kilobytes > .0005 then failures[#failures + 1] = string.format("%s allocates %.3f KB", name, kilobytes) end
    for api, delta in pairs(deltas) do
        if delta > (base.natives[api] or 0) then
            failures[#failures + 1] = string.format("%s: %d %s calls, budget %d (all: %s)", name, delta, api,
                base.natives[api] or 0, detail)
        end
    end
    SameAsFullRepaint(name)
end

------------------------------------------------------------------ scenarios
module:Enable()
UnitAura(20, 5)
SameAsFullRepaint("enable")
assert(DebuffFrame.UpdateAuraButtons == DebuffFrameMixin.UpdateAuraButtons,
    "DebuffFrame.UpdateAuraButtons is hooked although its UpdateGridLayout hook sees every refill")

Budget("refresh", function() UnitAura(20, 5) end, function() UnitAura(20, 5) end)
combat = true
Budget("combatRefresh", function() UnitAura(20, 5) end, function() UnitAura(20, 5) end)
combat = false
Budget("buffGain", function() UnitAura(20, 5) end, function() UnitAura(21, 5) end)
Budget("debuffGain", function() UnitAura(20, 5) end, function() UnitAura(20, 6) end)

-- No aura update moves an Edit Mode system frame (each move marks Edit Mode's
-- anchors dirty from addon code).
UnitAura(20, 5)
local dirty = anchorDirty
UnitAura(21, 6)
UnitAura(20, 5)
assert(anchorDirty == dirty, "an aura update moved a frame: Edit Mode anchors marked dirty "
    .. (anchorDirty - dirty) .. " times")

-- An aura refresh writes nothing on the buff frame.
UnitAura(20, 5)
local _, detail = Natives(function()
    BuffFrame.pending = Infos(20, 1000)
    BuffFrame:Update()
end)
assert(detail == "IsShown=33 issecretvalue=33",
    "a buff refresh must only read the 32 buttons and the consolidation button: " .. detail)

-- A new position or size in the options moves and repaints both frames.
config.x, config.y, config.debuffOffset, config.iconWidth = config.x - 30, config.y - 10, config.debuffOffset + 20, 40
module:Refresh()
Painted(BuffFrame, "configuration change")
Painted(DebuffFrame, "configuration change")
SameAsFullRepaint("configuration change")

-- Gains, losses and a native relayout land in the right slots.
UnitAura(24, 3)
SameAsFullRepaint("mixed gain and loss")
UnitAura(2, 0)
SameAsFullRepaint("most auras gone")
BuffFrame:UpdateGridLayout()
SameAsFullRepaint("native buff relayout")
StatusTrayManager.UpdateTrayAndBuffFrameLayout()
SameAsFullRepaint("status tray re-anchor")
-- A spec or layout change applies the Edit Mode layout: the frames move, then
-- the auras are laid out.
BuffFrame:UpdateSystem()
DebuffFrame:UpdateSystem()
SameAsFullRepaint("edit mode layout applied")
UnitAura(0, 0)
BuffFrame:UpdateGridLayout()
SameAsFullRepaint("native relayout with no auras")
-- Consolidated buffs take the first slot while consolidateBuffs is on.
BuffFrame.consolidate = true
UnitAura(20, 5)
assert(BuffFrame.ConsolidatedBuffs.shown, "the model shows the consolidation button")
SameAsFullRepaint("consolidation shown")
BuffFrame.consolidate = false
UnitAura(20, 5)
SameAsFullRepaint("consolidation hidden")

-- Edit Mode resets every Duration font object (EditModeManager RefreshAuraFrame:
-- SetIsEditing, then UpdateAuraButtons); the module paints its font again.
for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
    frame:SetIsEditing(true)
    frame:UpdateAuraButtons()
end
for _, button in ipairs(BuffFrame.auraFrames) do
    assert(button.shown and button.Duration.font[1] == "msuf.ttf" and button.Duration.font[2] == config.fontSize,
        "an Edit Mode example kept the native duration font")
end
SameAsFullRepaint("edit mode")
for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
    frame:SetIsEditing(false)
    frame:Update()
end
SameAsFullRepaint("edit mode exit")
-- With no auras: ExitEditMode reverts the layout (UpdateSystems) while still
-- editing, then OnEditModeExit refills (EditModeManager.lua 111-114).
UnitAura(0, 0)
for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
    frame:SetIsEditing(true)
    frame:UpdateAuraButtons()
end
for _, frame in ipairs({ BuffFrame, DebuffFrame }) do frame:UpdateSystem() end
for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
    frame:SetIsEditing(false)
    frame:Update()
end
SameAsFullRepaint("edit mode exit with no auras")

-- A protected frame in combat waits for the module's queued re-apply; its
-- unprotected buttons wait with it.
UnitAura(20, 5)
BuffFrame:UpdateGridLayout()
assert(BuffFrame.auraFrames[21].width == 30, "the native layout resets the hidden buttons too")
combat, BuffFrame.protected = true, true
UnitAura(22, 5)
assert(queued.playerAuras, "a protected frame in combat was not queued")
assert(BuffFrame.auraFrames[21].width == 30 and BuffFrame.auraFrames[22].width == 30,
    "a button was placed while its protected frame waited for the end of combat")
local rowsHeight = BuffFrame.AuraContainer.height
queued.playerAuras = nil
UnitAura(10, 5)
assert(queued.playerAuras and BuffFrame.AuraContainer.height == rowsHeight,
    "a protected frame was resized in combat")
combat, BuffFrame.protected = false, nil
module:Refresh()
SameAsFullRepaint("after combat")
-- A restyle that combat interrupts is finished by the next sync that may write.
UnitAura(20, 5)
combat, BuffFrame.auraFrames[1].protected, queued.playerAuras = true, true, nil
BuffFrame:SetIsEditing(true)
BuffFrame:UpdateAuraButtons()
assert(queued.playerAuras, "a protected button in combat was not queued")
BuffFrame.auraFrames[1].protected = nil
BuffFrame:UpdateAuraButtons()
Painted(BuffFrame, "restyle after a refusal")
BuffFrame:SetIsEditing(false)
BuffFrame:Update()
combat = false
module:Refresh()
SameAsFullRepaint("restyle after a refusal, after combat")

-- A protected button waits too, and so do the slots after it.
UnitAura(20, 5)
BuffFrame:UpdateGridLayout()
combat, BuffFrame.auraFrames[21].protected, queued.playerAuras = true, true, nil
UnitAura(22, 5)
assert(queued.playerAuras and BuffFrame.auraFrames[21].width == 30 and BuffFrame.auraFrames[22].width == 30,
    "a protected button or a later slot was placed in combat")
combat, BuffFrame.auraFrames[21].protected = false, nil
module:Refresh()
SameAsFullRepaint("after combat, protected button")

-- Secret aspects (12.x): a crop animation's TexCoords, a warning flash's
-- Alpha, a scale, a frame level and a shown state may be secret. Nothing is
-- compared or restored from them, and no secret reaches a setter.
-- Disable puts back only what the module wrote: Edit Mode's opacity on the
-- frame stays, and no FontString is given a fixed size.
BuffFrame:SetAlpha(.5)
module:Disable()
assert(BuffFrame.alpha == .5, "disable put back a frame alpha the module never wrote")
for _, button in ipairs(BuffFrame.auraFrames) do
    assert(not (button.Count.sized or button.Duration.sized), "disable gave an aura FontString a fixed size")
end
module.active = true
local first, second, third = BuffFrame.auraFrames[1], BuffFrame.auraFrames[2], BuffFrame.auraFrames[3]
first.Icon.secret = { GetTexCoord = true }
second.secret = { GetAlpha = true, GetScale = true, GetFrameLevel = true }
third.Duration.secret = { GetTextColor = true }
BuffFrame.auraFrames[4].secret = { IsShown = true }
BuffFrame.auraFrames[5].secret = { GetPoint = true, GetWidth = true, GetHeight = true }
module:Enable()
UnitAura(6, 1)
module:Disable()
assert(aspectsAdded == 0, "a secret value reached SetTexCoord, SetAlpha or SetTextColor from addon code")
assert(first.Icon.coords[2] ~= 1, "an unreadable crop must stay as it was, not be restored")
assert(second.Count.font[1] == "native.ttf" and third.Duration.font[1] == "native.ttf",
    "readable aspects were not restored")
BuffFrame.auraFrames[4].secret, BuffFrame.auraFrames[5].secret = nil, nil

assert(#failures == 0, table.concat(failures, "\n"))
print("player aura cadence, cold styling, edit mode, combat queue and secret aspects: OK")

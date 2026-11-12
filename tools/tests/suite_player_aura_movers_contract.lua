local root = assert(arg[1], "repository root required")
-- Player aura layout (QoL playerAuras) in MSUF Edit Mode: the buff and the
-- debuff row are Suite movers (MSUF_Suite_Modules/EditMode.lua, the real
-- controller, against a stand-in of MSUF's public Edit Mode API).
--   * a drag preview moves only the rows' AuraContainers (plain child
--     frames): BuffFrame and DebuffFrame are Edit Mode systems whose SetPoint
--     and ClearAllPoints are Blizzard Lua overrides, so a preview step must
--     not call them;
--   * an aura relayout during a drag keeps the preview;
--   * the commit writes x/y (buffs) or debuffX/debuffOffset (debuffs, the
--     offset grows downwards), and the refresh pins the frames once;
--   * a cancel, combat and Disable leave nothing shifted.

------------------------------------------------------------------ client stand-ins
local overrideCalls = 0
local function Region(w, h)
    local r = { width = w or 30, height = h or 40, scale = 1, alpha = 1, points = {}, shown = true,
        font = { "native.ttf", 10, "" }, color = { 1, 1, 1, 1 }, shadow = { 0, 0, 0, 1 }, shadowOffset = { 0, 0 },
        coords = { 0, 0, 0, 1, 1, 0, 1, 1 } }
    function r:GetWidth() return self.width end
    function r:GetHeight() return self.height end
    function r:GetScale() return self.scale end
    function r:GetAlpha() return self.alpha end
    function r:SetAlpha(v) self.alpha = v end
    function r:GetNumPoints() return #self.points end
    function r:GetPoint(i) return unpack(self.points[i]) end
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:ClearAllPoints() self.points = {} end
    function r:SetSize(w2, h2) self.width, self.height = w2, h2 end
    function r:SetScale(s) self.scale = s end
    function r:GetTexCoord() return unpack(self.coords) end
    function r:SetTexCoord(...) self.coords = { ... } end
    function r:GetFont() return unpack(self.font) end
    function r:SetFont(...) self.font = { ... } end
    function r:GetTextColor() return unpack(self.color) end
    function r:SetTextColor(...) self.color = { ... } end
    function r:GetShadowColor() return unpack(self.shadow) end
    function r:SetShadowColor(...) self.shadow = { ... } end
    function r:GetShadowOffset() return unpack(self.shadowOffset) end
    function r:SetShadowOffset(...) self.shadowOffset = { ... } end
    function r:SetAllPoints(parent)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        self:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    end
    function r:SetFrameLevel(n) self.level = n end
    function r:GetFrameLevel() return self.level or 1 end
    function r:IsProtected() return false end
    function r:IsShown() return self.shown end
    function r:IsVisible() return self.shown end
    function r:SetShown(v) self.shown = v end
    function r:Hide() self.shown = false end
    function r:EnableMouse() end
    return r
end
local function Button()
    local b = Region()
    b.Icon, b.Count, b.Duration, b.DebuffBorder = Region(), Region(), Region(), Region(40, 40)
    b.Icon.kind = "Texture"
    return b
end
-- An Edit Mode system: SetPoint and ClearAllPoints are Lua overrides that
-- touch Edit Mode state (EditModeSystemTemplates.lua 9-17, 147-156).
local function System()
    local frame = Region()
    frame.AuraContainer = Region()
    frame.auraFrames = { Button(), Button() }
    local setPoint, clear = frame.SetPoint, frame.ClearAllPoints
    function frame:SetPoint(...)
        overrideCalls = overrideCalls + 1
        return setPoint(self, ...)
    end
    function frame:ClearAllPoints()
        overrideCalls = overrideCalls + 1
        return clear(self)
    end
    function frame:UpdateGridLayout()
        for _, b in ipairs(self.auraFrames) do b:SetSize(30, 40) end
        self.AuraContainer:ClearAllPoints()
        self.AuraContainer:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
    end
    -- Its screen rect (left, right, top, bottom; nil: not laid out) and the
    -- clamp insets of its Edit Mode selection (UpdateClampOffsets).
    function frame:GetLeft() return self.rect and self.rect[1] end
    function frame:GetRight() return self.rect and self.rect[2] end
    function frame:GetTop() return self.rect and self.rect[3] end
    function frame:GetBottom() return self.rect and self.rect[4] end
    function frame:GetClampRectInsets() return unpack(self.insets or { 0, 0, 0, 0 }) end
    return frame
end
_G.UIParent, _G.Minimap = Region(1920, 1080), Region()
StatusTrayManager = { UpdateTrayAndBuffFrameLayout = function() end }
hooksecurefunc = function(obj, key, callback)
    local old = obj[key]
    obj[key] = function(self, ...)
        local out = { old(self, ...) }
        callback(self, ...)
        return unpack(out)
    end
end
_G.BuffFrame, _G.DebuffFrame = System(), System()

------------------------------------------------------------------ the catalog and the Suite
local catalogNS = { Client = { isForever = false }, Text = function(text) return text end }
assert(loadfile(root .. "/MSUF_Suite/Core/SuiteCatalog.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLife.lua"))("MSUF_Suite", catalogNS)
assert(loadfile(root .. "/MSUF_Suite/Core/Catalog/QualityOfLifeIndicators.lua"))("MSUF_Suite", catalogNS)
local rules = catalogNS.SuiteCatalog.playerAuras.rules
local config = {}
for key, rule in pairs(rules) do config[key] = rule.default end

local locked, module = false, nil
local P = { NS = {
    IsCombatLocked = function() return locked end, InCombat = function() return locked end,
    IsSecret = function() return false end, DB = {},
    Safety = { IsForbidden = function(r) return r.forbidden == true end },
    HostBridge = { IconSkinLook = function() end, PaintIconSkin = function() return false end,
        WatchIconSkins = function() end, SuppressEditElement = function() end,
        RefreshSuppressedEditElements = function() end },
    MSUFMedia = { font = "native.ttf" },
}, Suite = {} }
local S = P.Suite
S.Finite = function(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
S.CreateFrame = function() return Region() end
S.CreateTexture = function() return Region() end
S.RGB = function() return 0, 0, 0 end
S.PlaceEdges = function() end
S.ResolveFont = function() return "modern.ttf" end
S.Queue = function() end
S.Text = function(text) return text end
S.catalog = catalogNS.SuiteCatalog
S.states = { playerAuras = { active = true } }
S.Config = function() return config end
-- The Suite's setters: clamp to the rule as Suite.lua's CheckedValue does,
-- then the controller refreshes the running module (S.Apply).
local writes = 0
S.SetMany = function(_, values)
    for key, value in pairs(values) do
        local rule = assert(rules[key], "unknown setting " .. key)
        value = math.max(rule.min, math.min(rule.max, value))
        config[key] = rule.step == 1 and math.floor(value) or value
    end
    writes = writes + 1
    module:Refresh()
    return true
end
S.Set = function(id, key, value) return S.SetMany(id, { [key] = value }) end
S.CommitEditPosition = function(id, values)
    if locked then return false, "combat" end
    return S.SetMany(id, values)
end
S.Install = function(_, m) module = m end
-- The controller re-applies a running module (Suite.lua ApplyModule).
S.Apply = function(id)
    if S.states[id].active then module:Refresh() end
    S.states[id].editMode = S.editMode == true
end
P.PlayerAuraSkins = { Yield = function() end }

-- MSUF's public Edit Mode API (MSUF_EditMode_PublicAPI.lua), reduced to registration.
local elements = {}
_G.MSUF_EditModeAPI = {
    RegisterElement = function(owner, element)
        elements[owner .. ":" .. element.id] = element
        return true
    end,
    UnregisterOwner = function(owner)
        for key in pairs(elements) do
            if key:sub(1, #owner + 1) == owner .. ":" then elements[key] = nil end
        end
    end,
}
assert(loadfile(root .. "/MSUF_Suite_Modules/EditMode.lua"))("MSUF_Suite_Modules", P)
assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/PlayerAuras.lua"))("MSUF_Suite_QualityOfLife", P)
assert(module, "PlayerAuras.lua did not install its module")
S.instances = { playerAuras = module }
local events = {}
module.config, module.active = config, true
module.context = { Event = function(_, event, handler) events[event] = handler end }
-- Registered before the first Adopt: nothing to hold yet.
S.RefreshEditMover("playerAuras")
local early = assert(elements["MSUFSuite.playerAuras:buffs"], "the buff row has no MSUF Edit Mode mover")
assert(early.getFrame() == nil and not early.isEnabled(), "a mover offered a row the module has not laid out")
module:Enable()
S.RefreshEditMover("playerAuras")

------------------------------------------------------------------ checks
local function Anchor(region)
    assert(#region.points == 1, "expected one anchor, found " .. #region.points)
    return region.points[1]
end
local function AtMinimap(frame, x, y, label)
    local point = Anchor(frame)
    assert(point[1] == "TOPRIGHT" and point[2] == Minimap and point[3] == "TOPLEFT", label .. ": left the minimap")
    assert(point[4] == x and point[5] == y,
        string.format("%s: at %s,%s, expected %s,%s", label, tostring(point[4]), tostring(point[5]), x, y))
end
local function Shifted(frame, x, y, label)
    local point = Anchor(frame.AuraContainer)
    assert(point[1] == "TOPRIGHT" and point[2] == frame and point[3] == "TOPRIGHT", label .. ": container left its frame")
    assert(point[4] == x and point[5] == y,
        string.format("%s: container at %s,%s, expected %s,%s", label, tostring(point[4]), tostring(point[5]), x, y))
end
local function Pinned(label)
    AtMinimap(BuffFrame, config.x, config.y, label .. " (buffs)")
    AtMinimap(DebuffFrame, config.x + config.debuffX, config.y - config.debuffOffset, label .. " (debuffs)")
    Shifted(BuffFrame, 0, 0, label .. " (buffs)")
    Shifted(DebuffFrame, 0, 0, label .. " (debuffs)")
end
local function Drag(element, dx, dy, phase, state)
    return element.movePosition({ state = state, deltaX = dx, deltaY = dy, phase = phase })
end

local buffs = assert(elements["MSUFSuite.playerAuras:buffs"], "the buff row has no MSUF Edit Mode mover")
local debuffs = assert(elements["MSUFSuite.playerAuras:debuffs"], "the debuff row has no MSUF Edit Mode mover")
assert(buffs.label == "Player buffs" and debuffs.label == "Player debuffs")
-- MSUF flags the frame a mover drags (_msufDragActive): each mover holds a
-- Suite frame laid over its row's container, never a Blizzard frame.
for element, frame in pairs({ [buffs] = BuffFrame, [debuffs] = DebuffFrame }) do
    local handle = element.getFrame()
    assert(handle and handle ~= frame.AuraContainer and handle ~= frame, "a mover holds a Blizzard frame")
    assert(#handle.points == 2 and handle.points[1][2] == frame.AuraContainer
        and handle.points[2][2] == frame.AuraContainer, "a mover does not cover its row's laid-out icons")
    assert(element.getFrame() == handle, "a mover made a second handle")
end
assert(buffs.isEnabled() and debuffs.isEnabled(), "the movers are not available while the layout runs")
Pinned("enabled")

-- Popup controls: buffs edit x/y and the shared icon layout; debuffs edit
-- their own offsets in place of a generic X/Y.
local function Ids(element)
    local ids = {}
    for index, control in ipairs(element.extraControls) do
        ids[index] = control.id
        local rule = assert(rules[control.id], "control without a rule: " .. control.id)
        assert(control.min == rule.min and control.max == rule.max, control.id .. ": range differs from its rule")
    end
    return table.concat(ids, ",")
end
assert(Ids(buffs) == "x,y,iconWidth,iconHeight,iconZoom,perRow,spacing,rowSpacing", "buff controls: " .. Ids(buffs))
assert(Ids(debuffs) == "debuffX,debuffOffset,iconWidth,iconHeight,iconZoom,perRow,spacing,rowSpacing",
    "debuff controls: " .. Ids(debuffs))
-- Their size is in those controls: the host's W/H readout of the block goes.
assert(buffs.sizeSummary == false and debuffs.sizeSummary == false, "the movers keep the W/H readout")

-- Icon zoom: the artwork cut per side. 7 is the crop the layout always had
-- (52x26 icons: a .43 half width, .215 half height of the artwork).
local function Crop(button)
    local c = button.Icon.coords
    return string.format("%.3f,%.3f,%.3f,%.3f", c[1], c[2], c[3], c[4])
end
assert(config.iconZoom == 7 and Crop(BuffFrame.auraFrames[1]) == "0.070,0.930,0.285,0.715",
    "the default zoom changed the crop: " .. Crop(BuffFrame.auraFrames[1]))
assert(buffs.extraControls[5].set(0))
assert(Crop(BuffFrame.auraFrames[1]) == "0.000,1.000,0.250,0.750" and Crop(DebuffFrame.auraFrames[1])
    == "0.000,1.000,0.250,0.750", "the popup's zoom did not reach the icons")
assert(debuffs.extraControls[5].set(20))
assert(Crop(BuffFrame.auraFrames[2]) == "0.200,0.800,0.350,0.650", "zoom 20: " .. Crop(BuffFrame.auraFrames[2]))
assert(S.Set("playerAuras", "iconZoom", 7))
assert(rules.debuffOffset.min < 0, "the debuff row cannot be dragged above the buff row")

-- A buff drag previews on both containers and never runs the system overrides.
local x0, y0 = config.x, config.y
local state = buffs.captureState()
overrideCalls, writes = 0, 0
assert(Drag(buffs, 10, -5, "preview", state) == true, "the buff preview was refused")
assert(Drag(buffs, 14, -7, "preview", state) == true)
assert(overrideCalls == 0, "a drag preview called the Edit Mode system overrides " .. overrideCalls .. " times")
assert(writes == 0 and config.x == x0 and config.y == y0, "a drag preview wrote the settings")
AtMinimap(BuffFrame, x0, y0, "buff preview")
Shifted(BuffFrame, 14, -7, "buff preview")
Shifted(DebuffFrame, 14, -7, "buff preview carries the debuffs")
-- Blizzard lays the auras out again mid-drag (UNIT_AURA): the preview holds.
BuffFrame:UpdateGridLayout()
DebuffFrame:UpdateGridLayout()
Shifted(BuffFrame, 14, -7, "relayout during the buff preview")
Shifted(DebuffFrame, 14, -7, "relayout during the buff preview")
assert(overrideCalls == 0, "a relayout during the drag re-pinned a frame")

-- The commit writes the position; the refresh pins each frame once.
assert(Drag(buffs, 14, -7, "commit", state) == true, "the buff commit was refused")
assert(writes == 1 and config.x == x0 + 14 and config.y == y0 - 7, "the buff commit wrote the wrong position")
assert(overrideCalls == 4, "the commit pinned the frames " .. overrideCalls .. " override calls, expected 4")
Pinned("buff commit")

-- A debuff drag moves only the debuff row; its offset grows downwards.
local dx0, offset0 = config.debuffX, config.debuffOffset
state = debuffs.captureState()
assert(Drag(debuffs, -20, 30, "preview", state) == true, "the debuff preview was refused")
Shifted(DebuffFrame, -20, 30, "debuff preview")
Shifted(BuffFrame, 0, 0, "debuff preview leaves the buffs")
assert(Drag(debuffs, -20, 30, "commit", state) == true)
assert(config.debuffX == dx0 - 20 and config.debuffOffset == offset0 - 30, "the debuff commit wrote the wrong offsets")
Pinned("debuff commit")
-- Above the buff row.
state = debuffs.captureState()
assert(Drag(debuffs, 0, 200, "commit", state) == true)
assert(config.debuffOffset == offset0 - 230, "the debuff row was clamped below the buffs: " .. config.debuffOffset)
Pinned("debuffs above buffs")

-- A frame scale converts the host's UIParent deltas, in preview and commit.
BuffFrame.scale = 2
state = buffs.captureState()
x0 = config.x
assert(Drag(buffs, 10, -6, "preview", state) == true)
Shifted(BuffFrame, 5, -3, "scaled buff preview")
assert(Drag(buffs, 10, 0, "commit", state) == true)
assert(config.x == x0 + 5, "the frame scale was ignored")
BuffFrame.scale = 1
DebuffFrame.scale = 2
state = debuffs.captureState()
dx0, offset0 = config.debuffX, config.debuffOffset
assert(Drag(debuffs, -8, 12, "preview", state) == true)
Shifted(DebuffFrame, -4, 6, "scaled debuff preview")
assert(Drag(debuffs, -8, 12, "commit", state) == true)
assert(config.debuffX == dx0 - 4 and config.debuffOffset == offset0 - 6, "the debuff frame scale was ignored")
DebuffFrame.scale = 1

-- The settings' range: the preview stops where the commit would clamp.
state = buffs.captureState()
assert(Drag(buffs, -10000, 0, "preview", state) == true)
Shifted(BuffFrame, rules.x.min - config.x, 0, "buff preview past the range")
assert(Drag(buffs, -10000, 0, "commit", state) == true)
assert(config.x == rules.x.min)
state = debuffs.captureState()
offset0 = config.debuffOffset
assert(Drag(debuffs, 0, -10000, "preview", state) == true)
Shifted(DebuffFrame, 0, offset0 - rules.debuffOffset.max, "debuff preview past the range")
assert(Drag(debuffs, 0, -10000, "commit", state) == true)
assert(config.debuffOffset == rules.debuffOffset.max)
assert(buffs.resetPosition() and debuffs.resetPosition())
assert(config.x == rules.x.default and config.debuffOffset == rules.debuffOffset.default)
Pinned("reset")

-- The screen: Blizzard clamps each frame (sized for all its aura slots)
-- inside its selection; a drag stops there, so the drop stays where it
-- showed. A buff drag also keeps the debuff frame it carries on screen.
BuffFrame.rect, BuffFrame.insets = { 1500, 1880, 1060, 900 }, { 0, -15, 0, 0 }
DebuffFrame.rect = { 1500, 1880, 880, 700 }
state = buffs.captureState()
x0, y0 = config.x, config.y
-- Buff frame alone: right 55 (inset 15), down 900; the debuff frame: right
-- 40, down 700.
assert(Drag(buffs, 300, -1000, "preview", state) == true)
Shifted(BuffFrame, 40, -700, "buff preview at the screen edge")
Shifted(DebuffFrame, 40, -700, "debuff row carried to the screen edge")
assert(Drag(buffs, 300, -1000, "commit", state) == true)
assert(config.x == x0 + 40 and config.y == y0 - 700, "the buff commit left the screen")
DebuffFrame.rect = nil
state = buffs.captureState()
x0 = config.x
assert(Drag(buffs, 300, 0, "commit", state) == true)
assert(config.x == x0 + 55, "the buff frame's clamp insets were ignored")
DebuffFrame.rect = { 1500, 1880, 880, 700 }
state = debuffs.captureState()
offset0 = config.debuffOffset
assert(Drag(debuffs, -2000, 500, "commit", state) == true)
assert(config.debuffX == -1500 and config.debuffOffset == offset0 - 200, "the debuff commit left the screen")
BuffFrame.rect, BuffFrame.insets, DebuffFrame.rect = nil, nil, nil
assert(buffs.resetPosition() and debuffs.resetPosition())
Pinned("reset after the screen edge")

-- A buff row that cannot preview (its frame is not laid out) leaves the
-- debuff row alone: the host drops a refused preview without a restore.
-- (Its anchor names a forbidden frame, so its original anchor is unreadable.)
module:Disable()
local blocked = Region()
blocked.forbidden = true
BuffFrame.points = { { "TOPRIGHT", blocked, "TOPRIGHT", 0, 0 } }
module:Enable()
assert(buffs.getFrame(), "the buff mover lost its handle")
assert(Drag(buffs, 6, 6, "preview", buffs.captureState()) == false, "an unplaced buff row previewed")
Shifted(DebuffFrame, 0, 0, "debuff row after a refused buff preview")
module:Disable()
BuffFrame.points = {}
module:Enable()
Pinned("buff row placed again")

-- Cancel: MSUF restores the start state; the preview goes away.
state = buffs.captureState()
x0, y0 = config.x, config.y
assert(Drag(buffs, 40, 40, "preview", state) == true)
assert(buffs.restoreState(state))
assert(config.x == x0 and config.y == y0)
Pinned("cancel")

-- Combat: the controller refuses the drag before the module moves anything.
state = buffs.captureState()
locked = true
assert(Drag(buffs, 25, 25, "preview", state) == false, "a drag preview ran in combat")
locked = false
Pinned("combat")

-- A refused commit (lockdown) keeps the preview through combat; the
-- module's own combat-end Adopt drops it.
state = buffs.captureState()
assert(Drag(buffs, 8, 8, "preview", state) == true)
locked = true
assert(not Drag(buffs, 8, 8, "commit", state))
locked = false
assert(events.PLAYER_REGEN_ENABLED, "the module does not adopt at the combat end")
events.PLAYER_REGEN_ENABLED()
Pinned("combat end after a refused commit")

-- MSUF Edit Mode closes while a drag previews.
S.SetEditMode(true)
assert(Drag(buffs, 12, 12, "preview", buffs.captureState()) == true)
S.SetEditMode(false)
Pinned("Edit Mode closed mid-drag")

-- Disable restores Blizzard's anchors and drops a preview.
assert(Drag(buffs, 9, 9, "preview", buffs.captureState()) == true)
module.active = false
S.states.playerAuras.active = false
module:Disable()
assert(not buffs.isEnabled() and not debuffs.isEnabled(), "the movers outlived the layout")
-- Blizzard's original frame anchor (none in this model) and its own relayout.
assert(#BuffFrame.points == 0, "Disable left the Suite's frame anchor behind")
Shifted(BuffFrame, 0, 0, "Disable")
module.active = true
S.states.playerAuras.active = true
module:Enable()
Pinned("enabled again after a preview and Disable")
print("Player aura movers: Suite handles, preview without system overrides, commit, debuff offsets, scale, range, "
    .. "screen clamp, refused preview, cancel, combat, Edit Mode exit, disable: OK")

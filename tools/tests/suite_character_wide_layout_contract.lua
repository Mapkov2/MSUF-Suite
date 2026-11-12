-- The "Wide layout" toggle (Suite options, Skinning > Character panel and
-- stats) decides whether the modern Character view widens Blizzard's window.
-- It used to be read only for profiles without a view, and every normalized
-- profile has one, so the toggle did nothing. Off keeps the modern view at
-- Blizzard's size with the compact gear info beside the native slots (the
-- behaviour of the original "wide equipment layout" option, GEAR_WIDE_OPTION);
-- the default profile keeps the wide layout.
-- Usage: lua suite_character_wide_layout_contract.lua <Suite root> [GearAnnotations.lua]
local root = assert(arg[1], "Suite root required")
local gearSource = arg[2] or root .. "/MSUF_Suite_Skin/Adapters/GearAnnotations.lua"
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
C_Timer = { After = Noop }
-- Blizzard's panel manager owns its slots and their layout. The skin never runs
-- its pass: from addon code the pass and the windows' scripts ran under the
-- skin's taint (with Talents open it called PlayerSpellsFrame.SetMinimized
-- there). The window Blizzard laid out after a resized Character window moves
-- by the width the layout changed instead (WindowControlPolicy.ShiftFollowers).
UpdateUIPanelPositions = function() error("the skin ran Blizzard's panel layout pass") end
UIParent = {}
local panelSlots = {}
GetUIPanel = function(slot) return panelSlots[slot] end
-- Window controls load before the adapters (TOC); none of these windows has any.
local windowControls = { states = {} }

local NS = {
    -- Retail: the dossier and its modern equipment rows are available.
    Client = { isForever = false, isMainline = true, modernEquipment = true },
    IsCombatLocked = function() return false end,
    SuiteCore = function() return MSUFSuite end,
    FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
    Theme = { RefreshDynamicLook = Noop },
    Registry = { AddListener = Noop, QueueJob = Noop, NotifyListeners = Noop },
    GenericWindows = { IsCategoryEnabled = function() return true end },
    Surface = { SetVisible = function(frame, visible) frame.surfaceVisible = visible end },
    WindowControls = windowControls,
}
local skin = root .. "/MSUF_Suite_Skin/"
MSUFSuite = { Skin = {} }
for _, file in ipairs({ "Core/Safety", "Core/Cosmetics", "Core/Defaults", "Core/DefaultsLooks", "Core/Database",
    "Rendering/WindowControlPolicy", "Adapters/AdapterKit", "Adapters/CharacterDetails", "Adapters/GearGeometry" }) do
    assert(loadfile(skin .. file .. ".lua"))("MSUF_Suite_Skin", NS)
end
assert(loadfile(gearSource))("MSUF_Suite_Skin", NS)
local Gear, Details = NS.GearAnnotations, NS.CharacterDetails
-- The option setter reapplies the Character panels; their layout pass is the
-- one below (CharacterDetails.Refresh -> GearAnnotations.ApplyLayout).
local panelApplies = 0
NS.CharacterPanel = { Apply = function() panelApplies = panelApplies + 1 end }
NS.InspectPanel = { Apply = Noop }

local function Region(width, height, point)
    local frame = { width = width, height = height, scale = 1, shown = true, points = { point } }
    function frame:GetWidth() return self.width end
    function frame:SetWidth(value) self.width = value end
    function frame:GetHeight() return self.height end
    function frame:SetHeight(value) self.height = value end
    function frame:GetScale() return self.scale end
    function frame:SetScale(value) self.scale = value end
    function frame:GetNumPoints() return #self.points end
    function frame:GetPoint(index) return unpack(self.points[index], 1, 5) end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:SetShown(shown) self.shown = shown end
    return frame
end

-- Blizzard's Character window on the expanded paper doll (CharacterFrame.lua:
-- CHARACTERFRAME_EXPANDED_WIDTH 540) and the native regions the wide layout moves.
CharacterFrame = Region(540, 424, { "TOPLEFT", nil, "TOPLEFT", 16, -116 })
CharacterFrame.Expanded = true
CharacterFrame.activeSubframe = "PaperDollFrame"
CharacterFrame.UpdateSize = Noop
CharacterFrame.Inset = Region(332, 360, { "TOPLEFT", CharacterFrame, "TOPLEFT", 4, -60 })
CharacterFrame.InsetRight = Region(200, 360, { "TOPLEFT", CharacterFrame.Inset, "TOPRIGHT", 1, 0 })
CharacterModelScene = Region(231, 320, { "TOPLEFT", CharacterFrame, "TOPLEFT", 52, -66 })
PaperDollFrame = Region(540, 424, { "TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0 })
CharacterHeadSlot = Region(37, 37, { "TOPLEFT", CharacterFrame.Inset, "TOPLEFT", 4, -2 })
CharacterShirtSlot = Region(37, 37, { "TOPLEFT", CharacterFrame.Inset, "TOPLEFT", 4, -250 })

local v = { kind = "character", active = true, host = Region(1, 1), root = CharacterFrame,
    panel = Region(352, 644, { "TOPLEFT", CharacterFrame, "TOPRIGHT", 0, 0 }), rows = {} }
Details.views[CharacterFrame] = v

-- Talents in the next slot, where Blizzard's pass put it: 16 + 540 + 32.
local talents = Region(660, 600, { "TOPLEFT", UIParent, "TOPLEFT", 588, -116 })
local talentWrites, talentsProtected = 0, false
local talentPoint = talents.SetPoint
function talents:SetPoint(...) talentWrites = talentWrites + 1; return talentPoint(self, ...) end
function talents:IsProtected() return talentsProtected, false end
panelSlots.left, panelSlots.center = CharacterFrame, talents
local function TalentsX()
    local _, _, _, x = talents:GetPoint(1)
    return x
end

local function Native()
    local _, _, _, headX, headY = CharacterHeadSlot:GetPoint(1)
    return not v.wide and not v.list and CharacterFrame.width == 540 and CharacterFrame.height == 424
        and CharacterModelScene.width == 231 and CharacterModelScene.height == 320
        and headX == 4 and headY == -2 and not Gear.IsWide()
end
local function Wide()
    local _, _, _, headX = CharacterHeadSlot:GetPoint(1)
    return v.wide and CharacterFrame.width == 920 and CharacterFrame.height == 540
        and CharacterModelScene.width == 220 and headX == 18 and Gear.IsWide()
end

-- The options row is still there and writes this setting through the setter.
local options = assert(io.open(root .. "/MSUF_Suite_Options/Pages/AppearanceKit.lua", "rb"))
local page = options:read("*a")
options:close()
Check(page:find('{ "Wide layout", "characterDetails", "wideLayout", "CharacterDetails" }', 1, true),
    "the Wide layout option row is missing")

-- The default profile keeps today's look: the modern view, widened.
NS.DB = NS.Database.Normalize(NS.CopyValue(NS.Defaults))
Check(NS.DB.characterDetails.view == "modern" and NS.DB.characterDetails.wideLayout == true,
    "the default Character view changed")
Gear.ApplyLayout(v)
Check(Wide(), "the default modern view lost its wide layout")
Check(TalentsX() == 588 + 380, "the window after the widened Character window did not move by the added width")

-- Turning the toggle off returns the window and its regions to Blizzard's
-- geometry; the window after it moves back by the width it lost.
Check(Details.SetOption("wideLayout", false) and NS.DB.characterDetails.wideLayout == false
    and panelApplies == 1, "the Wide layout setter did not store the choice and reapply the panel")
Gear.ApplyLayout(v)
Check(Native(), "turning Wide layout off kept the wide Character layout")
Check(TalentsX() == 588, "the window after the narrowed Character window did not move back")
Check(CharacterFrame.Inset.surfaceVisible == true, "the native inset stayed hidden after the wide layout")
local writes = talentWrites
Gear.ApplyLayout(v)
Check(Native() and talentWrites == writes, "a repeated layout pass moved the window after it")

-- Turning it on again widens the modern view.
Check(Details.SetOption("wideLayout", true), "the Wide layout setter refused true")
Gear.ApplyLayout(v)
Check(Wide(), "turning Wide layout on again did not widen the modern view")

-- Native UpdateSize must not collapse the configured safe layout in combat. A
-- protected window after it (Talents in combat) keeps the place Blizzard's own
-- pass gave it; only that pass moves it again.
local locked = true
NS.IsCombatLocked = function() return locked end
NS.CombatGate = { RunOrDefer = function(_, callback) NS.pendingLayout = callback end }
Gear.FollowNativeSize(v)
Check(Wide(), "an unchanged window gave up the wide layout in combat")
-- Blizzard's UpdateSize resets the width; its own pass re-anchors Talents.
CharacterFrame.width, talents.points[1][4], talentsProtected = 540, 588, true
CharacterFrame.InsetRight.IsProtected = function() return true, false end
writes = talentWrites
Gear.FollowNativeSize(v)
Check(Wide(), "native UpdateSize collapsed the safe wide Character layout in combat")
Check(talentWrites == writes and TalentsX() == 588, "a protected window was moved in combat")
local _, _, _, insetX = CharacterFrame.InsetRight:GetPoint(1)
Check(insetX == 704, "a protected region was moved in combat")
locked, talentsProtected = false, false
CharacterFrame.InsetRight.IsProtected = nil
Gear.ApplyLayout(v)
Check(Wide() and talentWrites == writes, "an unchanged layout moved the window after it")
-- Blizzard's next pass (any window opening or closing) places Talents again.
talents.points[1][4] = 588 + 380
Gear.RestoreLayout(v)
Check(Native() and TalentsX() == 588, "the layout after combat no longer restores Blizzard's geometry")
-- A window Blizzard centres (TOP) does not follow the Character window's width.
talents.points[1] = { "TOP", UIParent, "TOP", 0, -116 }
writes = talentWrites
Gear.ApplyLayout(v)
Gear.RestoreLayout(v)
Check(talentWrites == writes, "a centred window was moved after the Character window")
talents.points[1] = { "TOPLEFT", UIParent, "TOPLEFT", 588, -116 }

-- First combat open and hide/reopen use the same reversible layout.
locked = true
Gear.ApplyLayout(v)
Check(Wide(), "first combat open lost the wide layout")
Gear.RestoreLayout(v)
Check(Native(), "combat close did not restore the safe native geometry")
Gear.ApplyLayout(v)
Check(Wide(), "combat reopen did not restore the configured layout")
v.host.shown = false
CharacterFrame.width, talents.points[1][4] = 540, 588
writes = talentWrites
Gear.FollowNativeSize(v)
Gear.ApplyLayout(v)
Check(CharacterFrame.width == 540 and talentWrites == writes,
    "hidden Character window performed layout work")
v.host.shown = true
Gear.ApplyLayout(v)

-- If another addon makes the root protected, never resize it in combat.
CharacterFrame.IsProtected = function() return true, true end
CharacterFrame.width = 540
Gear.FollowNativeSize(v)
local _, _, _, headX, headY = CharacterHeadSlot:GetPoint(1)
Check(CharacterFrame.width == 540 and headX == 4 and headY == -2 and not Gear.IsWide(),
    "protected Character root was resized or unsafe overflow survived")
locked = false
CharacterFrame.IsProtected = nil
Gear.ApplyLayout(v)
Check(Wide(), "the wide layout did not come back for the next checks")

-- The list and classic views are separate choices the toggle does not change.
for _, wide in ipairs({ true, false }) do
    NS.DB.characterDetails.wideLayout = wide
    NS.DB.characterDetails.view = "list"
    Gear.ApplyLayout(v)
    Check(v.list and not v.wide and CharacterFrame.width == 380 and CharacterFrame.height == 694,
        "Wide layout changed the list view")
    NS.DB.characterDetails.view = "classic"
    Gear.ApplyLayout(v)
    Check(Native(), "Wide layout changed the classic view")
    NS.DB.characterDetails.view = "modern"
    Gear.ApplyLayout(v)
    Check(wide and Wide() or not wide and Native(), "the modern view did not follow Wide layout")
end

-- A profile from before the view selector keeps its own reading of the parts.
NS.DB.characterDetails = { enabled = true, inlineGear = true, wideLayout = true }
Gear.ApplyLayout(v)
Check(Wide(), "a profile without a view lost the wide layout")
NS.DB.characterDetails.wideLayout = false
Gear.ApplyLayout(v)
Check(Native(), "a profile without a view ignored its Wide layout opt-out")
NS.DB.characterDetails = { enabled = true, inlineGear = false, wideLayout = true }
Gear.ApplyLayout(v)
Check(Native(), "a profile without a view widened without its gear info")

-- Cached owned annotations can inherit protection from their native anchors.
-- The combat refusal must precede Hide/Show, fonts and geometry; once safe,
-- ordinary combat cleanup still happens immediately.
locked = true
local annotationHost, writes = Region(1, 1), 0
local protected = true
function annotationHost:IsProtected() return protected, false end
function annotationHost:Hide() writes = writes + 1 end
GameTooltip = { IsOwned = function() return false end }
GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF" end }
local annotation = { host = annotationHost, status = {}, gems = {}, fonts = {
    { SetFont = function() error("protected annotation font was written") end },
} }
local row = { annotation = annotation }
local savedRows = v.rows
v.rows = { row }
Gear.Hide(v)
Gear.Update(v, row, "HeadSlot")
Check(writes == 0, "protected cached annotation received a combat write")
Gear.Paint(v, row)
protected = false
Gear.Update(v, row, "HeadSlot")
Check(writes == 1, "safe combat annotation cleanup was deferred")
protected = true
v.wideInfo, v.wide = annotationHost, true
Gear.UpdateSummary(v)
local icon = Region(1, 1)
function icon:IsProtected() return true, false end
function icon:Show() error("protected owned row icon was shown") end
row.icon = icon
Gear.RestoreLayout(v)
Check(writes == 1, "protected summary was hidden during layout cleanup")
v.rows, v.wideInfo = savedRows, nil
local width = CharacterFrame.GetWidth
v.geometry[CharacterFrame] = { appliedWidth = CharacterFrame.width, appliedHeight = CharacterFrame.height }
function CharacterFrame:IsForbidden() return true end
function CharacterFrame:GetWidth() error("forbidden Character geometry was read") end
Gear.RestoreLayout(v)
Gear.FollowNativeSize(v)
CharacterFrame.IsForbidden, CharacterFrame.GetWidth = nil, width
locked = false

-- The Suite presentation moves only the exact native interaction surfaces.
-- Its art keeps the stock parent, model dimensions, panel manager and scripts.
v.geometry, v.wide, v.list = nil, false, false
local geometry = assert(MSUFSuite.Skin.CharacterGeometry)
local pending
NS.CombatGate = {
    RunOrDefer = function(_, callback) if locked then pending = callback else callback() end end,
    Cancel = function() pending = nil end,
}
local function NativeWrite() error("Suite wrote native root geometry or a native script") end
CharacterFrame.SetWidth, CharacterFrame.SetHeight, CharacterFrame.SetPoint = NativeWrite, NativeWrite, NativeWrite
UpdateUIPanelPositions = NativeWrite
local function Layered(frame, parent, strata, level)
    frame.parent, frame.strata, frame.level = parent, strata or "MEDIUM", level or 1
    frame.insets, frame.insetWrites = { 0, 0, 0, 0 }, 0
    function frame:GetParent() return self.parent end
    function frame:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
    function frame:GetFrameStrata() return self.strata end
    function frame:SetFrameStrata(value) self.strata = value end
    function frame:GetFrameLevel() return self.level end
    function frame:SetFrameLevel(value) self.level = value end
    function frame:GetRegions() return unpack(self.regions or {}) end
    function frame:GetHitRectInsets() return unpack(self.insets) end
    function frame:SetHitRectInsets(...)
        assert(not locked, "the Suite wrote native hit insets in combat")
        self.insets, self.insetWrites = { ... }, self.insetWrites + 1
    end
    frame.SetParent, frame.SetScript, frame.Show, frame.Hide = NativeWrite, NativeWrite, NativeWrite, NativeWrite
    return frame
end
Layered(CharacterFrame, nil)
CharacterFrame.scale = 0.8
Layered(PaperDollFrame, CharacterFrame)
PaperDollFrame.scale = 0.9
local items = Layered(Region(1, 1), PaperDollFrame)
items.scale = 1.2
local head = Layered(CharacterHeadSlot, items, "MEDIUM", 100)
local headPoint = head.points[1]
head.insets = { 1, 2, 3, 4 }
local weapon = Layered(Region(37, 37, { "CENTER", items, "CENTER", 7, -9 }), items, "MEDIUM", 100)
CharacterMainHandSlot = weapon
local close = Layered(Region(24, 24, { "TOPRIGHT", CharacterFrame, "TOPRIGHT", -2, -2 }), CharacterFrame, "MEDIUM", 6)
local closePoint = close.points[1]
CharacterFrame.CloseButton = close
local model = Layered(CharacterModelScene, PaperDollFrame, "MEDIUM", 50)
model.points = { { "TOPLEFT", CharacterFrame, "TOPLEFT", 8, -66 },
    { "TOPRIGHT", CharacterFrame, "TOPRIGHT", -8, -66 }, { "BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -8, 8 } }
model.SetWidth, model.SetHeight = NativeWrite, NativeWrite
local modelPoints = model.points
local leftPane = Layered(Region(1, 1), CharacterFrame)
local modelControls = Layered(Region(100, 20, { "TOP", leftPane, "TOP", 0, -40 }), model, "MEDIUM", 51)
model.ControlFrame = modelControls
local function Art(kind, alpha)
    local region = { kind = kind, alpha = alpha, vertex = { 1, 1, 1, 0.7 } }
    function region:GetObjectType() return self.kind end
    function region:GetAlpha() return self.alpha end
    function region:SetAlpha(value) self.alpha = value end
    function region:GetVertexColor() return unpack(self.vertex) end
    function region:SetVertexColor(...) self.vertex = { ... } end
    return region
end
local icon, border, count, cooldown = Art("Texture", 0.8), Art("Texture", 0.7), Art("FontString", 1), Art("Texture", 0.4)
head.regions, head.BorderFrame = { icon, count }, Layered(Region(1, 1), head)
head.BorderFrame.regions = { border }
head.Cooldown = Layered(Region(1, 1), head)
head.Cooldown.regions = { cooldown }
model.BackgroundTopLeft, model.BackgroundOverlay = Art("Texture", 0.9), Art("Texture", 0.5)
PaperDollInnerBorderBottom2 = Art("Texture", 0.6)
local closeArt = Art("Texture", 1)
close.regions = { closeArt }
local plan = {
    width = 940, height = 576, strata = "HIGH", artLevel = 550, modelLevel = 570, slotLevel = 590, reportLevel = 610, closeLevel = 630,
    slots = { { token = "HeadSlot", x = 22, alternateX = 184, y = 111, size = 32 },
        { token = "MainHandSlot", x = 360, alternateX = 280, y = 483, size = 32 },
        { token = "AmmoSlot", x = 400, y = 483, size = 32, optional = true } },
    model = { x = 278, y = 114, width = 244, height = 312 },
    close = { x = 910, y = 4, size = 22 },
}
function weapon:IsProtected() return true, true end
Check(not geometry.Apply(CharacterFrame, plan) and head.points[1] == headPoint and head.scale == 1 and icon.alpha == 0.8,
    "preflight partially changed equipment before rejecting a required protected slot")
weapon.IsProtected = nil
local setInsets = weapon.SetHitRectInsets
weapon.SetHitRectInsets = nil
Check(not geometry.Apply(CharacterFrame, plan) and head.points[1] == headPoint and head.insetWrites == 0,
    "the required native hit-rect API was checked after a partial layout")
weapon.SetHitRectInsets = setInsets
NS.Cosmetics.Fade(border, "prior-skin-owner")
Check(geometry.Apply(CharacterFrame, plan), "the Suite native geometry could not start")
local _, anchor, _, anchorX, anchorY = head:GetPoint(1)
local ratio = head:GetEffectiveScale() / CharacterFrame:GetEffectiveScale()
Check(anchor == CharacterFrame and math.abs(head:GetWidth() * ratio - 32) < 0.01
    and math.abs(anchorX * ratio - 22) < 0.01 and math.abs(anchorY * ratio + 111) < 0.01,
    "the original equipment button did not align to the authored icon at inherited scale")
local left, right, top, bottom = head:GetHitRectInsets()
local weaponRatio = weapon:GetEffectiveScale() / CharacterFrame:GetEffectiveScale()
local weaponLeft, weaponRight = weapon:GetHitRectInsets()
Check(left == 0 and math.abs(right * ratio + 162) < 0.01 and top == 0 and bottom == 0
    and math.abs(weaponLeft * weaponRatio + 80) < 0.01 and weaponRight == 0,
    "native hit extents did not cover both icon positions at the authored scale")
Check(head.parent == items and model.parent == PaperDollFrame and close.parent == CharacterFrame
    and head.level == CharacterFrame.level + plan.slotLevel and model.level == CharacterFrame.level + plan.modelLevel
    and close.level == CharacterFrame.level + plan.closeLevel and head.strata == "HIGH",
    "native descendants lost their parents or relative layer")
local closeAnchor, closeRelative, closeRelativePoint, closeX, closeY = close:GetPoint(1)
local closeRatio = close:GetEffectiveScale() / CharacterFrame:GetEffectiveScale()
Check(closeAnchor == "TOPLEFT" and closeRelative == CharacterFrame and closeRelativePoint == "TOPLEFT"
    and math.abs(closeX * closeRatio - 910) < 0.01 and math.abs(closeY * closeRatio + 4) < 0.01
    and math.abs(close:GetWidth() * closeRatio - 22) < 0.01 and closeArt.alpha == 1,
    "native Close did not match the Suite button without changing its original art")
Check(model:GetNumPoints() == 2 and CharacterFrame:GetWidth() == 540,
    "the Suite layout changed the Blizzard root or native model size property")
local controlPoint, controlAnchor = modelControls:GetPoint(1)
Check(controlPoint == "TOP" and controlAnchor == leftPane and modelControls.parent == model and modelControls.strata == "LOW",
    "the stock model controls painted over the original Suite artwork")
NS.WindowControls = {
    SuiteAction = function(frame, layout, action)
        Check(frame == CharacterFrame and layout == plan and action == "release", "window action lost its native root or plan")
        return true
    end,
}
Check(not geometry.WindowAction(items, "release") and geometry.WindowAction(CharacterFrame, "release"),
    "the native window action did not honor its geometry owner")
Check(icon.alpha == 0 and border.alpha == 0 and count.alpha == 1 and cooldown.alpha == 0.4
    and model.BackgroundTopLeft.alpha == 0 and model.BackgroundOverlay.vertex[4] == 0 and PaperDollInnerBorderBottom2.alpha == 0,
    "slot or model art conflicted with the Suite stage or hid separate native feedback")
Check(NS.Cosmetics.GetOwner(border) == "prior-skin-owner", "Suite stole an existing skin alpha claim")
NS.Cosmetics.RestoreOwner("prior-skin-owner")
Check(geometry.Apply(CharacterFrame, plan) and border.alpha == 0, "appearance refresh did not pick up the released native border")
Check(head.insetWrites == 1 and weapon.insetWrites == 1, "the same layout rewrote native hit insets")
Gear.ApplyLayout(v)
Check(head.points[1][2] == CharacterFrame and not Gear.IsWide(), "Basic layout competed with the Suite owner")

locked = true
Check(not geometry.Apply(CharacterFrame, plan), "the Suite reapplied native geometry during combat")
geometry.Release(CharacterFrame)
Check(type(pending) == "function" and icon.alpha == 0 and head.level == CharacterFrame.level + plan.slotLevel and head.insetWrites == 1,
    "native geometry was restored before combat ended")
locked = false
weapon:SetFrameLevel(777)
weapon:SetHitRectInsets(5, 6, 7, 8)
local release = pending
pending = nil
release()
local _, oldAnchor, _, oldX, oldY = head:GetPoint(1)
Check(oldAnchor == headPoint[2] and oldX == headPoint[4] and oldY == headPoint[5] and head.scale == 1
    and head.strata == "MEDIUM" and head.level == 100 and weapon.level == 777,
    "native anchor/scale/layers were not restored or a later native layer was overwritten")
left, right, top, bottom = head:GetHitRectInsets()
local laterLeft, laterRight, laterTop, laterBottom = weapon:GetHitRectInsets()
Check(left == 1 and right == 2 and top == 3 and bottom == 4
    and laterLeft == 5 and laterRight == 6 and laterTop == 7 and laterBottom == 8,
    "release did not restore the owned hit insets or overwrote a later native change")
closeAnchor, closeRelative, closeRelativePoint, closeX, closeY = close:GetPoint(1)
Check(closeAnchor == closePoint[1] and closeRelative == closePoint[2] and closeRelativePoint == closePoint[3]
    and closeX == closePoint[4] and closeY == closePoint[5] and close.scale == 1 and close.level == 6,
    "Basic did not get its original Close anchor, scale and layer back")
Check(not geometry.WindowAction(CharacterFrame, "release"), "released geometry still offered native window actions")
local _, restoredControlAnchor, _, _, restoredControlY = modelControls:GetPoint(1)
Check(restoredControlAnchor == leftPane and restoredControlY == -40 and modelControls.level == 51 and modelControls.strata == "MEDIUM"
    and PaperDollInnerBorderBottom2.alpha == 0.6, "stock model controls or borders were left in the Suite layout")
Check(model:GetNumPoints() == #modelPoints and model.points[3][2] == modelPoints[3][2]
    and icon.alpha == 0.8 and border.alpha == 0.7 and model.BackgroundTopLeft.alpha == 0.9 and model.BackgroundOverlay.vertex[4] == 0.7,
    "release left a native scene anchor or cosmetic suppression behind")
print("Suite character wide layout: " .. checks .. " checks passed")

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
-- UIParent's panel manager re-anchors a resized Character window.
local panelRepositions = 0
UpdateUIPanelPositions = function() panelRepositions = panelRepositions + 1 end

local NS = {
    -- Retail: the dossier and its modern equipment rows are available.
    Client = { isForever = false, isMainline = true, modernEquipment = true,
        IsGamepadUI = function() return false end },
    IsCombatLocked = function() return false end,
    FontFaces = { "friz", "arial", "morpheus", "skurri", "sharedMedia", "custom" },
    Theme = { RefreshDynamicLook = Noop },
    Registry = { AddListener = Noop, QueueJob = Noop, NotifyListeners = Noop },
    GenericWindows = { IsCategoryEnabled = function() return true end },
    Surface = { SetVisible = function(frame, visible) frame.surfaceVisible = visible end },
}
local skin = root .. "/MSUF_Suite_Skin/"
for _, file in ipairs({ "Core/Safety", "Core/Defaults", "Core/DefaultsLooks", "Core/Database",
    "Adapters/AdapterKit", "Adapters/CharacterDetails" }) do
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
local options = assert(io.open(root .. "/MSUF_Suite_Options/Pages/Appearance.lua", "rb"))
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

-- Turning the toggle off returns the window and its regions to Blizzard's
-- geometry; the panel manager re-anchors the narrower window.
local repositions = panelRepositions
Check(Details.SetOption("wideLayout", false) and NS.DB.characterDetails.wideLayout == false
    and panelApplies == 1, "the Wide layout setter did not store the choice and reapply the panel")
Gear.ApplyLayout(v)
Check(Native(), "turning Wide layout off kept the wide Character layout")
Check(panelRepositions == repositions + 1, "the narrowed Character window was not re-anchored")
Check(CharacterFrame.Inset.surfaceVisible == true, "the native inset stayed hidden after the wide layout")
Gear.ApplyLayout(v)
Check(Native() and panelRepositions == repositions + 1, "a repeated layout pass changed the native window")

-- Turning it on again widens the modern view.
Check(Details.SetOption("wideLayout", true), "the Wide layout setter refused true")
Gear.ApplyLayout(v)
Check(Wide(), "turning Wide layout on again did not widen the modern view")

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

-- Under WoW Forever's Gamepad UI the skin never drives the panel manager
-- (Core/Client.lua, IsGamepadUI): resizing the window leaves its placement to
-- Blizzard. Forever's Camelot CharacterFrame has no InsetRight today, so this
-- holds the rule for a layout that gains one.
NS.DB.characterDetails = NS.CopyValue(NS.Defaults.characterDetails)
NS.Client.IsGamepadUI = function() return true end
repositions = panelRepositions
Gear.ApplyLayout(v)
Check(Wide() and panelRepositions == repositions,
    "the wide layout drove the panel manager under the Gamepad UI")
NS.DB.characterDetails.wideLayout = false
Gear.ApplyLayout(v)
Check(Native() and panelRepositions == repositions,
    "the narrowed layout drove the panel manager under the Gamepad UI")
NS.Client.IsGamepadUI = function() return false end

print("Suite character wide layout: " .. checks .. " checks passed")

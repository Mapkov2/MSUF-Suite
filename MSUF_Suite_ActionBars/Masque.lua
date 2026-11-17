local _, P = ...
local NS, S = P.NS, P.Suite
-- Optional Masque skins ("Skin Suite-made buttons with Masque", off by
-- default): one Masque group per bar, holding only buttons the Suite created
-- itself (bars 9 and 10, and bar 1 where Blizzard's buttons cannot be
-- reused). Blizzard's reused action buttons and the adopted stance and pet
-- buttons never join: the Suite does not own them. Masque draws the frame,
-- icon placement, highlight, pushed, checked, border and flash art; the Suite
-- keeps its texts, swipe colors, glows and cooldown anchors (Style.lua skips
-- everything else while rec.masqued). Joins and leaves run only in the
-- controller's refresh, which never runs in combat; nothing here runs from
-- events, timers or the cursor. Without Masque loaded nothing joins and no
-- group exists; a Masque that loads later is picked up by the next refresh.
--
-- Spell flyouts stay outside: Blizzard's SpellFlyout and its popup buttons
-- belong to Blizzard, which reparents the flyout to whichever button opens
-- it. Neither Masque nor the Suite style is applied to them, and the Suite
-- never reparents them or writes their attributes. The Suite's share of a
-- flyout is its own opener button (skinned here) and that button's
-- flyoutDirection attribute (Bars.lua LayoutBar).
local AB = P.ActionBars
local M = AB.M
local Masque = {}
AB.Masque = Masque
local LAST_ACTION = AB.ENUM.BAR.LAST_ACTION
-- The template textures the style pass hides or fades; Masque needs them shown.
local SHOWN = { "Normal", "Pushed", "Highlight", "Checked" }
local groups = {} -- bar index -> Masque group while it holds buttons

-- The Masque library, or nil while Masque is not loaded.
local function Library()
    local stub = rawget(_G, "LibStub")
    if type(stub) ~= "table" then return nil end
    local lib = stub:GetLibrary("Masque", true)
    return type(lib) == "table" and lib or nil
end

-- Only buttons the Suite created; never a reused or adopted Blizzard button.
local function Eligible(rec)
    return rec.owned == true and not rec.native
end
Masque.Eligible = Eligible

-- Whether any bar has a group (the refresh then keeps it in sync).
function Masque.Active()
    return next(groups) ~= nil
end

-- The regions handed to Masque, made once per button. Texts stay the Suite's.
local function Regions(rec)
    local regions = rec.masqueRegions
    if not regions then
        local button = rec.button
        regions = {
            Icon = button.icon, Cooldown = button.cooldown, Normal = button:GetNormalTexture(),
            Pushed = button:GetPushedTexture(), Highlight = button:GetHighlightTexture(),
            Checked = button:GetCheckedTexture(), Border = button.Border, Flash = button.Flash,
        }
        rec.masqueRegions = regions
    end
    return regions
end

-- The Suite's own art steps aside before Masque skins the button.
local function Hand(rec)
    local bar = rec.bar
    AB.ClearDecoration(rec)
    AB.ShowEdges(rec.borderEdges, false)
    AB.ShowEdges(rec.hoverEdges, false)
    AB.ShowEdges(rec.pressEdges, false)
    rec.pressBorder = false
    if rec.slotTexture then rec.slotTexture:Hide() end
    if rec.skinned then
        local size = bar.size or M.config[bar.key.Size]
        rec.skinned = NS.HostBridge.PaintIconSkin(rec.button, nil, size, bar.height or size) or nil
    end
    local regions = Regions(rec)
    for i = 1, #SHOWN do
        local region = regions[SHOWN[i]]
        if region then region:SetAlpha(1) end
    end
end

local function Join(rec, group)
    Hand(rec)
    group:AddButton(rec.button, Regions(rec), "Action", true)
    rec.masqued = true
    -- The texts and cooldown anchors follow the bar again (masqued branch).
    if AB.style then AB.StyleButton(rec) end
end

-- Masque puts its default look back; the full style pass then restores the
-- Suite look (art remembered before Masque joined, edges, shape and skin).
local function Leave(rec, group)
    group:RemoveButton(rec.button)
    rec.masqued = nil
    if rec.slotTexture then rec.slotTexture:Show() end
    rec.styleGen = nil
    if AB.style then AB.StyleButton(rec) end
end

local function Reskinned()
    if M.active and M.config.masque then EventRegistry:TriggerEvent("MSUFSuite.ActionBars.StyleChanged") end
end

local function Install(lib, bar, reskin)
    local index = bar.index
    local group, changed = groups[index], false
    for i = 1, #bar.buttons do
        local rec = bar.buttons[i]
        if Eligible(rec) and not rec.masqued then
            if not group then
                group = lib:Group("MSUF Suite", S.Text(NS.ActionBarTitles[index]), "actionbar" .. index)
                hooksecurefunc(group, "ReSkin", Reskinned)
            end
            groups[index] = group
            Join(rec, group)
            changed = true
        end
    end
    if group and (changed or reskin) then group:ReSkin() end
end

local function Restore(bar)
    local group = groups[bar.index]
    if not group then return end
    for i = 1, #bar.buttons do
        local rec = bar.buttons[i]
        if rec.masqued then Leave(rec, group) end
    end
    groups[bar.index] = nil
    group:Delete()
end

-- Joins or returns every Suite-made button after the style pass of a
-- refresh. reskin(index) says whether that bar's look or size changed.
function Masque.Sync(reskin)
    if NS.IsCombatLocked() then return end
    local lib = M.config.masque == true and Library() or nil
    for index = 1, LAST_ACTION do
        local bar = AB.bars[index]
        if bar then
            if lib then
                Install(lib, bar, reskin and reskin(index))
            else
                Restore(bar)
            end
        end
    end
end

function Masque.Release()
    if NS.IsCombatLocked() then return end
    for index in pairs(groups) do Restore(AB.bars[index]) end
end

-- Read-only view for the contract tests.
function AB.Diagnostics.MasqueGroups()
    local list = {}
    for index in pairs(groups) do list[#list + 1] = index end
    table.sort(list)
    return list
end

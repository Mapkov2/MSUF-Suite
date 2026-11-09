local root = assert(arg[1]):gsub("\\", "/")
arg[4] = "fixture"
local F = dofile(root .. "/tools/tests/suite_menu_geometry_contract.lua")
local M, P, mw = F.M, F.P, F.mw
local PAGE = "suite_dataTexts"
local SECTION = PAGE .. "_presets"

local built, build = {}, P.DataTextPage.Build
P.DataTextPage.Build = function(ctx, ...)
    build(ctx, ...)
    built[ctx.entry] = ctx.dataTextWorkspace
end

local function Workspace()
    assert(M.activeKey == PAGE, "Back left DataTexts")
    return assert(built[M.cache[PAGE]])
end

local function Click(button)
    assert(button and button:IsVisible() and button:IsEnabled(), "expected an available menu button")
    F.MenuWorld.FireScript(button, "OnClick")
    mw:RunTimers(1000)
end

local function Gallery()
    local workspace = Workspace()
    assert(workspace.deck.selected == "add", "window transition lost the Add Bar gallery")
    return workspace.deck.views.add.cards
end

local function CheckCards(stacked)
    local cards = Gallery()
    local first, second = cards[1], cards[2]
    for _, card in ipairs(cards) do
        assert(card.title:GetParent() == card.frame and card.preview.host:GetParent() == card.frame
            and card.description:GetParent() == card.frame and card.button:GetParent() == card.frame,
            "preset and its add button are not grouped in the same card")
        local point, relative = card.button:GetPoint()
        assert(point == "BOTTOMLEFT" and relative == card.frame, "add button is outside its card's layout")
    end
    local _, _, _, firstX, firstY = first.frame:GetPoint()
    local _, _, _, secondX, secondY = second.frame:GetPoint()
    if stacked then
        assert(firstX == secondX and secondY < firstY - first.frame:GetHeight(), "narrow presets do not stack")
    else
        assert(firstY == secondY and secondX > firstX + first.frame:GetWidth(), "wide presets do not have a visible gutter")
        assert(first.frame:GetHeight() == second.frame:GetHeight(), "paired add buttons are not aligned")
    end
end

local config = P.S.Config("dataTexts")
config.barIds = "1,2"
assert(M.SelectPage(PAGE))
mw:RunTimers(1000)
Workspace().choose(2, "details", 3)
M.scrollFrame:SetVerticalScroll(67)
Click(Workspace().buttons.add)
assert(M.scrollFrame:GetVerticalScroll() == 0, "Add Bar opened with its heading offscreen")
Click(M.pageHistoryBackButton)
assert(Workspace().deck.selected == 2 and P.DataTextPage.selections[2].slot == 3,
    "Back did not return to the same bar and slot")
assert(M.GetPageHistoryState().previousPage == "home", "local Back consumed the Menu2 page history")
assert(M.scrollFrame:GetVerticalScroll() == 67, "Back did not restore the editor scroll")

Workspace().choose("shared")
M.pageBackStack = {}
M.RefreshPageHistoryNav()
Click(Workspace().buttons.add)
CheckCards(false)
local section = M.cache[PAGE].sections[SECTION]
section:SetWidth(440)
F.MenuWorld.FireScript(section, "OnSizeChanged", 440, section:GetHeight())
CheckCards(true)

local normal = M.cache[PAGE]
assert(M.MaximizeSlashMenuWindow())
mw:RunTimers(1000)
Gallery()
assert(M.cache[PAGE] ~= normal, "fixture did not exercise a newly built maximized view")
assert(M.MinimizeSlashMenuWindow())
mw:RunTimers(1000)
assert(not M.frame:IsShown() and M.minimizedBar:IsShown(), "fixture did not minimize the window")
assert(M.RestoreMinimizedSlashMenu())
mw:RunTimers(1000)
Gallery()
assert(M.MaximizeSlashMenuWindow())
mw:RunTimers(1000)
Gallery()
assert(M.cache[PAGE] == normal, "fixture did not exercise the cached normal view")
Click(M.pageHistoryBackButton)
assert(Workspace().deck.selected == "shared", "Back after resize lost the originating All bars view")

assert(M.MaximizeSlashMenuWindow())
mw:RunTimers(1000)
assert(Workspace().deck.selected == "shared", "restoring a cached layout reopened a dismissed gallery")
Click(Workspace().buttons.add)
local back
for _, control in ipairs({ M.cache[PAGE].sections[SECTION]:GetChildren() }) do
    local label = P.HM.GetControlLabel(control)
    if label and label:GetText() == P.Tr("Back") then back = control end
end
Click(back)
assert(Workspace().deck.selected == "shared", "the in-gallery Back button did not return to DataTexts")

Click(Workspace().buttons.add)
local gallery = Gallery()
Click(gallery[1].button)
local created = P.Suite.DataTextBarIDs(config)[3]
assert(created and Workspace().deck.selected == created, "adding a preset did not open the new bar editor")
print("DataTexts gallery navigation, window controls and responsive card layout PASS")

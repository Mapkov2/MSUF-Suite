-- Native encounter header art with the actual surface/control renderer.
local root = assert(arg[1], "Suite root required")
local file = assert(io.open(root .. "/tools/tests/suite_skin_encounter_render_contract.lua", "rb"))
local source = file:read("*a"); file:close()
local stop = assert(source:find("local boss=Button()", 1, true))
local body = [======[
local override = os.getenv("SUITE_EJ_PANELS_SOURCE")
if override then assert(loadfile(override))("MSUF_Suite_Skin", NS) end
local locked, glyphCount = false, 0
InCombatLockdown = function() return locked end
NS.IsCombatLocked = InCombatLockdown
local function Protected(self) return self.protected == true, self.protected == true end
local function Bullet(parent)
    local row = Target()
    row.Bullet, row.parent = Texture(), parent
    row.IsProtected, row.Bullet.IsProtected = Protected, Protected
    function row:CreateFontString()
        glyphCount = glyphCount + 1
        local glyph = Text()
        function glyph:SetAllPoints(target) self.anchor = target end
        function glyph:SetText(text) self.text = text end
        function glyph:IsForbidden() return self.forbidden == true end
        function glyph:Show() assert(not self.forbidden, "forbidden glyph show"); self.shown = true end
        function glyph:Hide() assert(not self.forbidden, "forbidden glyph hide"); self.shown = false end
        row.glyph = glyph
        return glyph
    end
    return row
end
local nativeArt = {
    "eLeftUp", "eMidUp", "eRightUp", "eLeftDown", "eMidDown", "eRightDown",
    "cLeftUp", "cMidUp", "cRightUp", "cLeftDown", "cMidDown", "cRightDown",
}
local function Header()
    local row = Target()
    row.button, row.Bullets = Button(), { Bullet(), Bullet() }
    row.button.title, row.button.expandedIcon = Text(), Text()
    row.button.abilityIcon, row.button.icon1 = Texture(), Texture()
    row.button.OnClick, row.flashAnim = Noop, {}
    for _, key in ipairs(nativeArt) do row.button[key] = Texture() end
    return row
end
local journal, encounter, info, overview = Target(), Target(), Target(), Target()
local visible = true
function journal:IsVisible() return visible end
journal.encounter, encounter.info = encounter, info
info.overviewScroll, info.detailsScroll = { child = overview }, { child = Target() }
overview.header, overview.Bullets = Texture(), { Bullet() }
function overview:GetName() return "EncounterJournalEncounterFrameInfoOverviewScrollFrameChild" end
local overviewTitle = Text()
overviewTitle.r = .929
_G[overview:GetName() .. "Title"] = overviewTitle
local role, ability = Header(), Header()
overview.overviews, encounter.usedHeaders = { role }, { ability }
local state = { frame=journal, owner="journal-style", active=true, surfaces=NS.AdapterKit.WeakSet(),
    textColors=NS.AdapterKit.NewTextColors(), deferred={} }
NS.EncounterJournalPanels.Abilities(state)
local function Styled()
    Check(overview.header:GetAlpha() == 0, "native gold overview band remains")
    Check(overviewTitle.r == NS.Theme.GetColor("title"), "unkeyed Overview title is still gold")
    for _, row in ipairs({role, ability}) do
        local surface = NS.Registry.GetSurface(row.button)
        Check(surface and surface.fill.shown, "role/ability header has no theme surface")
        Check(surface.spec.role == "navigation", "header does not use the shared section material")
        Check(row.button.highlight == surface.highlight and row.button.pushed == surface.pushed,
            "header lost themed mouse-over/press feedback")
        for _, key in ipairs(nativeArt) do
            row.button[key]:Show()
            Check(row.button[key]:GetAlpha() == 0, "native expanded/collapsed gold art returned: " .. key)
        end
        Check(row.button.abilityIcon:GetAlpha() == 1 and row.button.icon1:GetAlpha() == 1,
            "ability or role icon was suppressed")
        Check(row.button.OnClick == Noop and row.flashAnim ~= nil, "native interaction/flash was replaced")
        for _, bullet in ipairs(row.Bullets) do
            Check(bullet.Bullet:GetAlpha() == 0, "gold bullet remains")
            Check(bullet.glyph and bullet.glyph.shown and bullet.glyph.anchor == bullet.Bullet,
                "replacement bullet is absent or detached from native layout")
            Check(bullet.glyph.r == NS.Theme.GetColor("text"), "replacement bullet ignores theme")
        end
    end
end
Styled()
local count, beforePaints = glyphCount, paints
for _ = 1, 100 do NS.EncounterJournalPanels.Abilities(state) end
Check(glyphCount == count and paints == beforePaints, "warm updates rebuild glyphs or surfaces")
local function Allocated()
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 1000 do NS.EncounterJournalPanels.Abilities(state) end
    local growth = collectgarbage("count") - before
    collectgarbage("restart")
    return growth
end
Check(math.min(Allocated(), Allocated()) < 2, "warm style pass allocates on every update")
locked = true
role.Bullets[3] = Bullet()
NS.EncounterJournalPanels.Abilities(state)
Check(role.Bullets[3].glyph and role.Bullets[3].glyph.shown, "new unprotected combat bullet is not styled")
role.Bullets[4] = Bullet()
role.Bullets[4].protected = true
NS.EncounterJournalPanels.Abilities(state)
Check(role.Bullets[4].glyph == nil and role.Bullets[4].Bullet:GetAlpha() == 1, "protected bullet was changed")
locked, role.Bullets[4].protected = false, false
NS.EncounterJournalPanels.Abilities(state)
Styled()
visible = false
role.Bullets[5] = Bullet()
NS.EncounterJournalPanels.Abilities(state)
Check(role.Bullets[5].glyph == nil, "hidden guide allocated bullet visuals")
visible = true
NS.EncounterJournalPanels.Abilities(state)
NS.AdapterKit.CancelHidden(state.journalAbilityJob)
Check(role.Bullets[5].glyph and role.Bullets[5].glyph.shown, "reopened guide lost new bullet")
NS.DB.theme.colors.text = { .8, .9, 1, 1 }
NS.AdapterKit.RefreshTextColors(state.textColors)
NS.ControlSkin.RefreshOwner(state.owner)
Styled()
local bars, owners = {}, {}
NS.ScrollBarSkin = { Apply = function(bar, owner) owners[bar] = owner end }
for index = 1, 5 do bars[index] = Target() end
info.BossesScrollBar, info.overviewScroll.ScrollBar, info.detailsScroll.ScrollBar = bars[1], bars[2], bars[3]
encounter.instance, info.LootContainer = { LoreScrollBar = bars[4] }, { ScrollBar = bars[5] }
NS.EncounterJournalPanels.Apply(state)
for _, bar in ipairs(bars) do Check(owners[bar] == state.owner, "exact journal scrollbar missed the shared skin") end
NS.ControlSkin.DisableOwner(state.owner)
NS.AdapterKit.HideSurfaces(state)
NS.AdapterKit.RestoreTextColors(state.textColors)
NS.EncounterJournalPanels.Reset(state)
NS.Cosmetics.RestoreOwner(state.owner)
Check(overview.header:GetAlpha() == 1 and overviewTitle.r == .929, "overview did not restore")
for _, row in ipairs({role, ability}) do
    for _, key in ipairs(nativeArt) do Check(row.button[key]:GetAlpha() == 1, "native header art did not restore") end
    for _, bullet in ipairs(row.Bullets) do
        Check(bullet.Bullet:GetAlpha() == 1 and not bullet.glyph.shown, "bullet disable left duplicate or missing art")
    end
end
count = glyphCount
NS.EncounterJournalPanels.Abilities(state)
Check(glyphCount == count, "reenable leaked another glyph per pooled bullet")
Styled()
local guardedGlyph = role.Bullets[1].glyph
guardedGlyph.forbidden = true
NS.EncounterJournalPanels.Abilities(state)
NS.EncounterJournalPanels.Reset(state)
Check(guardedGlyph.shown, "forbidden cached glyph was touched during reset")
guardedGlyph.forbidden = false
print("suite_skin_encounter_style_contract: " .. checks .. " checks passed")
]======]
assert(loadstring(source:sub(1, stop - 1) .. body, "@encounter_style"))()

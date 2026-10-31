-- Actual skin renderer: idle boss fills, native state art and theme selection.
local root = assert(arg[1], "Suite root required")
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function Noop() end

securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = function() return false end
Enum = { UITextureSliceMode = { Stretched = 1 } }
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
C_Timer = { After = function(_, callback) callback() end }

local paints = 0
local function Texture()
    local texture = { shown = true }
    for _, method in ipairs({ "SetTexture", "SetVertexColor", "SetGradient", "ClearTextureSlice",
        "SetTextureSliceMargins", "SetTextureSliceMode" }) do
        texture[method] = function() paints = paints + 1 end
    end
    function texture:GetAlpha() return self.alpha or 1 end
    function texture:SetAlpha(a) self.alpha = a end
    function texture:GetBlendMode() return "ADD" end
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    function texture:ClearAllPoints() end
    function texture:SetPoint() end
    function texture:SetDrawLayer() end
    return texture
end
local function Target(objectType)
    local target = {}
    function target:IsForbidden() return false end
    function target:IsProtected() return false, false end
    function target:GetObjectType() return objectType or "Frame" end
    function target:GetParent() return nil end
    function target:CreateTexture() return Texture() end
    function target:HookScript() end
    return target
end

local NS = {
    path = "",
    Client = { isForever = false },
    IsCombatLocked = function() return false end,
    BlizzardYellow = { TrackFrame = Noop },
}
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", NS)
NS.DB = NS.CopyValue(NS.Defaults)
for _, file in ipairs({ "Core/Safety.lua", "Core/Registry.lua", "Core/Theme.lua",
    "Rendering/Geometry.lua", "Rendering/Surface.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end

NS.Checkmarks = { GetWindowAction = Noop, TrackButton = Noop, TrackDropdown = Noop,
    UntrackDropdown = Noop, UntrackOwner = Noop }
NS.WindowActionSkin = {}
for _, file in ipairs({ "Core/Cosmetics.lua", "Rendering/ControlSkin.lua", "Adapters/AdapterKit.lua", "Adapters/EncounterJournalPanels.lua" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/" .. file))("MSUF_Suite_Skin", NS)
end
local function Text()
    local font = { r=1,g=1,b=1,a=1 }
    function font:GetTextColor() return self.r,self.g,self.b,self.a end
    function font:SetTextColor(r,g,b,a) self.r,self.g,self.b,self.a=r,g,b,a end
    return font
end
local function Button()
    local button=Target("Button")
    button.normal,button.highlight,button.pushed,button.disabled=Texture(),Texture(),Texture(),Texture()
    button.originalHighlight,button.originalPushed=button.highlight,button.pushed
    function button:GetNormalTexture() return self.normal end
    function button:GetHighlightTexture() return self.highlight end
    function button:GetPushedTexture() return self.pushed end
    function button:GetDisabledTexture() return self.disabled end
    function button:SetHighlightTexture(t) self.highlight=t end
    function button:SetPushedTexture(t) self.pushed=t end
    function button:SetDisabledTexture(t) self.disabled=t end
    button.text=Text()
    return button
end
local boss=Button()
boss.creature=Texture()
local state={owner="journal",active=true,surfaces=NS.AdapterKit.WeakSet(),textColors=NS.AdapterKit.NewTextColors(),deferred={},frame={}}
Check(NS.EncounterJournalPanels.Row(state,boss),"boss was not classified")
local surface=NS.Registry.GetSurface(boss)
Check(boss.normal.alpha==0,"real control left normal boss art visible")
Check(surface.fill.shown==true,"boss idle fill is hidden")
Check(boss.creature.alpha==nil,"boss portrait was faded")
Check(boss.highlight==surface.highlight and boss.pushed==surface.pushed,"boss state art did not adopt renderer")
local oldPaints=paints
for _=1,100 do NS.EncounterJournalPanels.Row(state,boss) end
Check(paints==oldPaints,"warmed boss row repainted its surface")
local first,second=Button(),Button()
state.frame.navBar={navList={first,second}}
NS.EncounterJournalPanels.Navigation(state)
Check(NS.Registry.GetSurface(first).active==false and NS.Registry.GetSurface(second).active==true,"nav initial selection incorrect")
NS.ControlSkin.RefreshOwner("journal")
Check(NS.Registry.GetSurface(second).active==true,"real owner refresh lost selected breadcrumb")
state.frame.navBar.navList[2]=nil
NS.EncounterJournalPanels.Navigation(state)
Check(NS.Registry.GetSurface(first).active==true,"nav transition missed new selection")
NS.ControlSkin.RefreshOwner("journal")
Check(NS.Registry.GetSurface(first).active==true,"real refresh lost transitioned selection")
local info={ tab=2 }
state.frame.encounter={info=info}
for id,key in ipairs({"overviewTab","lootTab","bossTab","modelTab"}) do
    local tab=Button()
    tab.id=id
    function tab:GetID() return self.id end
    tab.selected,tab.unselected=Texture(),Texture()
    info[key]=tab
end
NS.EncounterJournalPanels.SideTabs(state)
for _,key in ipairs({"overviewTab","lootTab","bossTab","modelTab"}) do
    local tab=info[key]
    local tabSurface=NS.Registry.GetSurface(tab)
    Check(tab.normal.alpha==0 and tabSurface.fill.shown,"side tab native background or missing fill: "..key)
    Check(tab.highlight==tabSurface.highlight and tab.pushed==tabSurface.pushed,"side tab state art was not replaced")
    Check(tab.selected.alpha==nil and tab.unselected.alpha==nil,"semantic side tab icons were faded")
end
NS.ControlSkin.RefreshOwner("journal")
Check(NS.Registry.GetSurface(info.lootTab).active and not NS.Registry.GetSurface(info.overviewTab).active,
    "owner refresh lost side tab selection")
oldPaints=paints
for _=1,1000 do NS.EncounterJournalPanels.SideTabs(state) end
Check(paints==oldPaints,"unchanged side tabs repainted")
info.tab=3
NS.EncounterJournalPanels.SideTabs(state)
NS.ControlSkin.RefreshOwner("journal")
Check(NS.Registry.GetSurface(info.bossTab).active and not NS.Registry.GetSurface(info.lootTab).active,
    "side tab selection transition missed")
NS.ControlSkin.DisableOwner("journal")
NS.AdapterKit.HideSurfaces(state)
NS.Cosmetics.RestoreOwner("journal")
Check(boss.normal.alpha==1 and first.normal.alpha==1 and second.normal.alpha==1,"native normal art did not restore")
Check(boss.highlight==boss.originalHighlight and boss.pushed==boss.originalPushed,"native states did not restore")
Check(info.lootTab.normal.alpha==1 and info.lootTab.highlight==info.lootTab.originalHighlight,"side tab native art did not restore")
print("EncounterJournal renderer: "..checks.." checks passed")

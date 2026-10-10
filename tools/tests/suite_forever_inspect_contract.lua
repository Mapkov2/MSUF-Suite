local root = assert(arg[1])
-- The real Safety, AdapterKit, PaperDollChrome and InspectPanel. The renderer
-- stubs keep the client's refusal: ControlSkin's button path needs the button
-- state-texture setters (Rendering/Surface.lua SupportsButtonStateTextures),
-- which a Frame from LargeSideTabButtonTemplate does not have.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end
InCombatLockdown = function() return false end
local function noop() end

local function Texture(shown)
    return { shown = shown ~= false, alpha = 1,
        IsShown = function(self) return self.shown end,
        SetShown = function(self, value) self.shown = value == true end,
        SetAlpha = function(self, value) self.alpha = value end }
end
-- Blizzard_InspectUI/Camelot/Blizzard_InspectUI.xml:4-11 and 54-75: Frames
-- inheriting LargeSideTabButtonTemplate (Blizzard_SharedXML/Mainline/
-- SharedUIPanelTemplates.xml:1008-1053) with SidePanelTabButtonMixin's
-- SetChecked (SharedUIPanelTemplates.lua:389-399).
local function SideTab(id, checked)
    local tab = { id = id, Background = Texture(), SelectedTexture = Texture(checked),
        TabGlow = Texture(), Icon = Texture() }
    function tab:GetObjectType() return "Frame" end
    function tab:CreateTexture() return Texture() end
    function tab:GetID() return self.id end
    function tab:SetChecked(value) self.SelectedTexture:SetShown(value) end
    return tab
end

hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then return end
    local native = target[method]
    target[method] = function(...)
        native(...)
        callback(...)
    end
end

local surfaces, controls = {}, {}
local ns = {
    IsCombatLocked = function() return false end,
    Client = { isForever = true },
    Cosmetics = {
        Fade = function(region) region.alpha = 0; return true end,
        SuppressVertexAlpha = function(region) region.vertexAlpha = 0; return true end,
        FadeNineSlice = noop, RestoreOwner = noop,
    },
    Surface = {
        Attach = function(target, spec) surfaces[target] = { spec = spec }; return surfaces[target] end,
        Ensure = function(target, spec)
            surfaces[target] = surfaces[target] or { spec = spec }
            return surfaces[target]
        end,
        SetActive = function(target, active)
            if not surfaces[target] then return false end
            surfaces[target].active = active
            return true
        end,
    },
    ControlSkin = { ApplyButton = function(button, _, spec)
        if type(button.CreateTexture) ~= "function" or type(button.SetHighlightTexture) ~= "function"
            or type(button.SetPushedTexture) ~= "function" then
            return nil, "invalid button"
        end
        controls[button] = spec
        return {}
    end },
    IconSkin = { Apply = function() return {} end },
    Registry = { AddListener = noop, GetSurface = function() return nil end },
    CombatGate = { RunOrDefer = function(_, callback) callback(); return true end, Cancel = noop },
    GenericWindows = { IsCategoryEnabled = function() return true end },
    CharacterDetails = { Apply = noop, Disable = noop },
    WindowControls = { Attach = noop },
}
ns.Safety = assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", ns) or ns.Safety
for _, file in ipairs({ "AdapterKit", "PaperDollChrome", "InspectPanel" }) do
    assert(loadfile(root .. "/MSUF_Suite_Skin/Adapters/" .. file .. ".lua"))("MSUF_Suite_Skin", ns)
end

local character, pvp, guild = SideTab(1, false), SideTab(2, true), SideTab(3, false)
InspectFrame = { ModeTabs = { CharacterTab = character, PvPTab = pvp, GuildTab = guild,
    Tabs = { character, pvp, guild } } }
function InspectFrame:CreateTexture() return Texture() end
InspectFrame.SetSelectedModeTabByID = function(self, id)
    for _, tab in ipairs(self.ModeTabs.Tabs) do tab:SetChecked(tab:GetID() == id) end
end

-- Forever's ranged slot (Blizzard_InspectUI/Camelot/InspectPaperDollFrame.xml:310).
InspectRangedSlot = { Icon = Texture(), IconBorder = Texture() }
function InspectRangedSlot:CreateTexture() return Texture() end
assert(ns.InspectPanel.Apply(), "Forever Inspect did not apply")
assert(surfaces[InspectRangedSlot], "Forever's Inspect ranged slot stayed unskinned (FV-10)")
assert(#reported == 0, "Forever Inspect raised: " .. tostring(reported[1]))
for _, tab in ipairs({ character, pvp, guild }) do
    assert(surfaces[tab] and surfaces[tab].spec.activeRole == "navigationActive",
        "a Forever Inspect side tab (a Frame) stayed unskinned (FV-9)")
    assert(tab.Background.alpha == 0 and tab.SelectedTexture.alpha == 0 and tab.TabGlow.vertexAlpha == 0,
        "a Forever Inspect side tab kept its native tab art under the surface")
end
assert(surfaces[pvp].active == true and surfaces[character].active == false and surfaces[guild].active == false,
    "the side tab surfaces did not show the native selection")
assert(pvp.SelectedTexture.shown and not character.SelectedTexture.shown,
    "the Inspect skin changed the native selected tab")
-- A native tab change (InspectSwitchTabs / SetupModeTabs -> SetSelectedModeTabByID).
InspectFrame:SetSelectedModeTabByID(3)
assert(surfaces[guild].active == true and surfaces[pvp].active == false,
    "a native Inspect tab change did not move the selection surface")

-- An older Forever build without PvPTab.
surfaces = {}
InspectFrame.ModeTabs.PvPTab = nil
assert(ns.InspectPanel.Apply() and surfaces[character] and surfaces[guild] and not surfaces[pvp],
    "older Forever Inspect tabs did not skin without PvPTab")
print("Forever Inspect: side tabs skinned as Frames, native selection followed, older builds passed")

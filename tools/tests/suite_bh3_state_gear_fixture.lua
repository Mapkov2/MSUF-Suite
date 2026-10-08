BH3("S08-A1",function()
-- Probe: does the "Inline gear" toggle (characterDetails.inlineGear) change the
-- Character window's inline gear annotations? Loads the real GearAnnotations.lua
-- and the real Database.lua normalization rule that forces a view.
local root = arg[1] .. "/"

local function Mock(name)
    local m = { _name = name, _shown = true }
    return setmetatable(m, { __index = function(t, k)
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
        if k == "IsShown" or k == "IsVisible" then return function(self) return self._shown end end
        if k == "GetFrameLevel" then return function() return 5 end end
        if k == "GetWidth" or k == "GetHeight" then return function() return 37 end end
        if k == "CreateFontString" or k == "CreateTexture" then
            return function() return Mock(name .. "." .. k) end
        end
        if k == "GetText" then return function() return "" end end
        return function() end
    end })
end

local NS = {
    IsCombatLocked = function() return false end,
    AdapterKit = { DEFAULT_FONT = "Fonts\\FRIZQT__.TTF", FontPath = function() return "Fonts\\FRIZQT__.TTF" end },
    Safety = {
        Public = function() return true end,
        CanCreateRegions = function() return true end,
        CreateChildFrame = function(kind, parent) return Mock(kind) end,
        GetProtection = function() return nil end,
    },
    Surface = { SkinOwnedButton = function() return {} end, SetVisible = function() end },
    Theme = { GetColor = function() return 1, 1, 1, 1 end, GetMaterialOpacity = function() return 1 end },
    Materials = { input = {} },
    L = setmetatable({}, { __index = function(_, k) return k end }),
    EquipmentInfo = { AddTooltip = function() end },
    CharacterDetails = { views = {} },
}
ITEM_QUALITY_COLORS = { [4] = { r = 1, g = 0, b = 1 } }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
GameTooltip = Mock("GameTooltip")
CharacterHeadSlot = Mock("CharacterHeadSlot")
InspectHeadSlot = Mock("InspectHeadSlot")

local Gear = assert(loadfile(root .. "MSUF_Suite_Skin/Adapters/GearAnnotations.lua"))("MSUF_Suite_Skin", NS)

local function Run(kind, inlineGear)
    NS.DB = { characterDetails = { view = "modern", enabled = true, expanded = true,
        styleEQoL = true, inlineGear = inlineGear, wideLayout = true } }
    local v = { kind = kind, host = Mock("host"), rows = {}, unit = kind == "inspect" and "target" or "player" }
    local row = { slot = 1, slotName = "HeadSlot",
        audit = { link = "item:1::", name = "Helm", itemLevel = 700, quality = 4, enchantApplicable = true } }
    Gear.Update(v, row, "HeadSlot")
    local a = row.annotation
    return a ~= nil and a.host._shown == true
end

assert(Run("character",true) and not Run("character",false), "S08-A1: Inline gear off retained character annotations")

end)

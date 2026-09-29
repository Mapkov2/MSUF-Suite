local root = assert(arg[1], "repository root required")
local module
local scheduled = {}
local bagSlots = 4
local combat = false
local bag = {
    [1] = { itemID = 100, itemName = "Zed Gem", hyperlink = "gem:100", iconFileID = 10, stackCount = 2 },
    [2] = { itemID = 102, hyperlink = "gear:102", iconFileID = 12, stackCount = 1 },
    [3] = { itemID = 101, itemName = "Amy Gem", hyperlink = "gem:101", iconFileID = 11, stackCount = 1 },
}

local function Widget(parent)
    local w = { parent = parent, shown = true }
    local noOp = function() end
    w.SetSize, w.SetPoint, w.SetAllPoints, w.SetColorTexture = noOp, noOp, noOp, noOp
    w.SetTexture, w.SetWidth, w.SetJustifyH, w.SetWordWrap = noOp, noOp, noOp, noOp
    function w:GetParent() return self.parent end
    function w:Show() self.shown = true end
    function w:Hide() self.shown = false end
    function w:IsShown() return self.shown end
    function w:EnableMouse() end
    function w:SetScript(event, fn) self[event] = fn end
    function w:CreateTexture() return Widget(self) end
    function w:CreateFontString()
        local fs = Widget(self)
        function fs:SetFontObject(font) assert(font); self.font = font end
        function fs:SetText(value)
            assert(self.font, "SetText without a font")
            self.text = value
        end
        return fs
    end
    return w
end

CreateFrame = function(_, _, parent) return Widget(parent) end
GameFontNormalSmall, GameFontDisableSmall, GameFontHighlightSmall = {}, {}, {}
Enum = { ItemClass = { Gem = 3 } }
C_Container = {
    GetContainerNumSlots = function(index) return index == 0 and bagSlots or 0 end,
    GetContainerItemInfo = function(index, slot) return index == 0 and bag[slot] or nil end,
}
C_Item = {
    GetItemInfoInstant = function(link)
        return nil, nil, nil, nil, nil, link:find("gem:", 1, true) and 3 or 4
    end,
}
C_Timer = { After = function(_, fn) scheduled[#scheduled + 1] = fn end }
GameTooltip = {
    SetOwner = function() end,
    SetBagItem = function(_, index, slot) assert(index == 0 and slot == 3) end,
    Show = function() end,
    Hide = function() end,
}
local S = {
    Text = function(value) return value end,
    Public = function(value) return value ~= "secret" end,
    Finite = function(value) return type(value) == "number" and value == value end,
    Install = function(id, instance)
        assert(id == "socketGemSuggestions")
        module = instance
    end,
}
local NS = {
    Safety = { IsForbidden = function() return false end },
    IsCombatLocked = function() return combat end,
}
local context = { events = {} }
function context:Event(name, fn) self.events[name] = fn end
function context:RemoveEvent(name) self.events[name] = nil end

assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/SocketGemSuggestions.lua"))(
    "MSUF_Suite_QualityOfLife", { NS = NS, Suite = S })
module.context, module.active = context, true
module:Enable()
assert(not module.panel, "socket panel was created outside the native UI")

ItemSocketingFrame = Widget()
ItemSocketingFrame:Hide()
context.events.SOCKET_INFO_UPDATE(module, "SOCKET_INFO_UPDATE")
ItemSocketingFrame:Show() -- Blizzard shows its native window during the event.
scheduled[1]()
assert(module.panel and module.panel:IsShown(), "native socket opening did not show gems")
assert(module.panel.rows[1].name.text == "Amy Gem", "gems were not sorted by name")
assert(module.panel.rows[2].name.text == "Zed Gem"
    and module.panel.rows[2].count.text == "2", "stack count was not shown")
assert(not module.panel.rows[3]:IsShown(), "non-gems were displayed")
module.panel.rows[1].OnEnter(module.panel.rows[1]) -- Native bag tooltip remains available.
module.panel.rows[1].OnLeave(module.panel.rows[1])

bag[3] = { itemID = 101, hyperlink = "secret", iconFileID = 11, stackCount = 1 }
context.events.BAG_UPDATE_DELAYED(module, "BAG_UPDATE_DELAYED")
assert(module.panel.rows[1].name.text == "Zed Gem"
    and not module.panel.rows[2]:IsShown(), "secret item was read or displayed")

for slot = 5, 11 do
    bag[slot] = { itemID = 200 + slot, itemName = "Gem " .. slot,
        hyperlink = "gem:" .. slot, iconFileID = 20 + slot, stackCount = 1 }
end
bagSlots = 11
context.events.BAG_UPDATE_DELAYED(module, "BAG_UPDATE_DELAYED")
assert(module.panel.more:IsShown() and module.panel.more.text:find("(2)", 1, true),
    "additional carried gems were silently truncated")

combat = true
context.events.BAG_UPDATE_DELAYED(module, "BAG_UPDATE_DELAYED")
assert(not module.panel:IsShown() and context.events.PLAYER_REGEN_ENABLED,
    "combat did not defer its optional panel")
combat = false
context.events.PLAYER_REGEN_ENABLED(module, "PLAYER_REGEN_ENABLED")
assert(module.panel:IsShown() and not context.events.PLAYER_REGEN_ENABLED,
    "panel did not resume after combat")

module:Disable()
module.active = false
assert(not module.panel:IsShown() and not context.events.SOCKET_INFO_UPDATE
    and not context.events.BAG_UPDATE_DELAYED and not context.events.PLAYER_REGEN_ENABLED,
    "disable left UI or events active")
module.active = true
module:Enable()
assert(module.panel:IsShown() and context.events.SOCKET_INFO_UPDATE,
    "enable did not restore the panel")
context.events.SOCKET_INFO_UPDATE(module, "SOCKET_INFO_UPDATE")
local deferred = scheduled[#scheduled]
module:Disable()
module.active = false
deferred()
assert(not module.panel:IsShown(), "a pending socket event revived disabled UI")
print("suite_socket_gem_suggestions_contract: ok")

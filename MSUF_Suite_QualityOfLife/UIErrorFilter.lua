local _, P = ...
local NS, S = P.NS, P.Suite

-- Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua owns the message list and
-- exposes per-type filtering. Configure it once instead of handling every
-- UI_ERROR_MESSAGE ourselves.
local M = {}
local MESSAGE_TYPES = {
    range = { "LE_GAME_ERR_SPELL_OUT_OF_RANGE" },
    target = { "LE_GAME_ERR_GENERIC_NO_VALID_TARGETS" },
    mana = { "LE_GAME_ERR_OUT_OF_MANA" },
    item = { "LE_GAME_ERR_ITEM_COOLDOWN", "LE_GAME_ERR_CANT_USE_ITEM" },
}
local QUERY_SENTINEL = {}

local function Usable(frame)
    return frame and not NS.Safety.IsForbidden(frame)
end

local function Release(self)
    local frame = self.frame
    if Usable(frame) and self.owned then
        for id, previous in pairs(self.owned) do
            -- Respect a later change that enabled a message while we ran.
            local current = frame:ShouldDisplayMessageType(id, QUERY_SENTINEL)
            if previous and S.Public(current) and current == false then
                frame:SetMessageTypeEnabled(id, previous)
            end
        end
    end
    self.owned, self.frame = nil, nil
end

local function Sync(self)
    local frame = _G.UIErrorsFrame
    if frame ~= self.frame then Release(self) end
    local needed = false
    for key in pairs(MESSAGE_TYPES) do
        if self.config[key] then
            needed = true
            break
        end
    end
    if not needed then
        Release(self)
        self.context:RemoveEvent("ADDON_LOADED")
        return
    end
    if not Usable(frame) then
        self.context:Event("ADDON_LOADED", function(module) Sync(module) end)
        return
    end
    self.context:RemoveEvent("ADDON_LOADED")
    self.frame, self.owned = frame, self.owned or {}
    local wanted = {}
    for key, names in pairs(MESSAGE_TYPES) do
        if self.config[key] then
            for i = 1, #names do
                local id = _G[names[i]]
                if S.Finite(id) then wanted[id] = true end
            end
        end
    end
    for id, previous in pairs(self.owned) do
        if not wanted[id] then
            local current = frame:ShouldDisplayMessageType(id, QUERY_SENTINEL)
            if previous and S.Public(current) and current == false then
                frame:SetMessageTypeEnabled(id, previous)
            end
            self.owned[id] = nil
        end
    end
    for id in pairs(wanted) do
        if self.owned[id] == nil then
            local previous = frame:ShouldDisplayMessageType(id, QUERY_SENTINEL)
            if S.Public(previous) and type(previous) == "boolean" then
                self.owned[id] = previous
                if previous then frame:SetMessageTypeEnabled(id, false) end
            end
        end
    end
end

function M:Enable() Sync(self) end
function M:Refresh() Sync(self) end
function M:Disable() Release(self) end

S.Install("uiErrorFilter", M)

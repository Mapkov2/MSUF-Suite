local _, NS = ...
local CreateFrame = NS.Suite.CreateFrame
local Routing = {}
NS.Routing = Routing

local CHARACTER_BINDING = "TOGGLECHARACTER0"
local MODIFIERS = { "ALT-", "CTRL-", "SHIFT-" }
local ROUTES = {
    { CHARACTER_BINDING, "overview", "PaperDollFrame" },
    { "TOGGLECHARACTER2", "reputation", "ReputationFrame" },
    { "TOGGLECURRENCY", "currency", "TokenFrame" },
}
if NS.Host.Client.isForever then
    ROUTES[#ROUTES + 1] = { "TOGGLECHARACTER4", "pvp", "PVPRankFrame" }
end

local APPLY = [[
self:ClearBindings()
if not self:GetAttribute("routingEnabled") then return end
local state = self:GetAttribute("state-character")
if state == "suite" then
    for i = 1, self:GetAttribute("routeCount") do
        self:SetBindingClick(false, self:GetAttribute("key"..i), self:GetAttribute("name"..i), "LeftButton")
    end
elseif state == "combat" then
    local key = self:GetAttribute("combatKey")
    if key then
        self:SetBindingClick(false, key, self:GetAttribute("combatButton"), "LeftButton")
        local alias = self:GetAttribute("nativeAlias")
        if alias then self:SetBinding(false, alias, "TOGGLECHARACTER0") end
    end
end
]]

local owner, openPanel, syncing, nativeCombatKey
local keys, names = {}, {}

local function Click(button)
    local route = ROUTES[button.routeIndex]
    if not NS.CanOpenCharacter() then return end
    if openPanel and openPanel(route[2]) then return end
    if NS.Host.InCombat() then return end
    if route[2] == "currency" then
        local size = NS.Number(C_CurrencyInfo.GetCurrencyListSize())
        if not size or size == 0 then return end
    end
    ToggleCharacter(route[3])
end

local function CreateOwner()
    owner = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
    owner:SetAttribute("_onstate-character", APPLY)
    for i = 1, #ROUTES do
        local route = ROUTES[i]
        local button = CreateFrame("Button", "MSUFSuiteCharacterBinding" .. i, UIParent)
        button.routeIndex = i
        button:RegisterForClicks("LeftButtonUp")
        button:SetScript("OnClick", Click)
        route[4] = button:GetName()
    end
    owner:SetAttribute("combatButton", ROUTES[1][4])
    RegisterStateDriver(owner, "character", "[petbattle] native; [combat] combat; suite")
end

local function KeyboardKey(value)
    local key = NS.String(value)
    if key and not key:match("^PAD") and not key:find("-PAD", 1, true) then return key end
end

local function AddKey(key, name)
    if not key then return end
    local index = #keys + 1
    keys[index], names[index] = key, name
end

local function NativeKey(primary, secondary)
    if not primary then return end
    if secondary and secondary ~= primary then
        local action = GetBindingAction(secondary, true)
        if NS.Public(action) and (action == CHARACTER_BINDING
            or action == "CLICK " .. ROUTES[1][4] .. ":LeftButton") then return secondary end
    end
    if primary:find("-", 1, true) then return end
    for i = 1, #MODIFIERS do
        local key = MODIFIERS[i] .. primary
        local action = GetBindingAction(key, true)
        if NS.Public(action) and (action == "" or action == CHARACTER_BINDING) then return key, key end
    end
end

local function RoutesMatch(combatKey, nativeAlias)
    if not owner:GetAttribute("routingEnabled") or owner:GetAttribute("routeCount") ~= #keys
        or owner:GetAttribute("combatKey") ~= combatKey or owner:GetAttribute("nativeAlias") ~= nativeAlias then return false end
    for i = 1, #keys do
        if owner:GetAttribute("key" .. i) ~= keys[i] or owner:GetAttribute("name" .. i) ~= names[i] then return false end
    end
    return true
end

local function ApplyRoutes(combatReady)
    if not owner then CreateOwner() end
    wipe(keys)
    wipe(names)
    local primary, secondary
    for i = 1, #ROUTES do
        local route = ROUTES[i]
        local first, second = GetBindingKey(route[1])
        first, second = KeyboardKey(first), KeyboardKey(second)
        if i == 1 then primary, secondary = first or second, first and second end
        AddKey(first, route[4])
        AddKey(second, route[4])
    end
    -- Keep the primary key native if no other combat path can be reserved.
    local native, alias
    if combatReady then native, alias = NativeKey(primary, secondary) end
    local combatKey = native and primary
    nativeCombatKey = native or primary
    if RoutesMatch(combatKey, alias) then return end
    owner:SetAttribute("combatKey", combatKey)
    owner:SetAttribute("nativeAlias", alias)
    owner:SetAttribute("routeCount", #keys)
    for i = 1, #keys do
        owner:SetAttribute("key" .. i, keys[i])
        owner:SetAttribute("name" .. i, names[i])
    end
    owner:SetAttribute("routingEnabled", true)
    SecureHandlerExecute(owner, APPLY)
end

function Routing.NativeCombatKey()
    return nativeCombatKey
end

function Routing.Sync(callback, combatReady)
    if syncing then return end
    openPanel = callback
    if NS.Host.InCombat() then return end
    syncing = true
    if callback and NS.CanOpenCharacter() then
        ApplyRoutes(combatReady)
    else
        nativeCombatKey = nil
        if owner and owner:GetAttribute("routingEnabled") then
            owner:SetAttribute("routingEnabled", false)
            SecureHandlerExecute(owner, APPLY)
        end
    end
    syncing = nil
end

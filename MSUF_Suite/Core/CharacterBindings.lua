local _, NS = ...
local Text, Tabs = NS.Text, NS.CharacterTabs
local PLAYER, TAB_ID_LIMIT = "tab", 16
local Bindings = { Native = {}, Slots = {} }
NS.CharacterBindings = Bindings

local function Native(id, command, label, key, defaultTab, retailOnly)
    local binding = { id = id, command = command, label = Text(label), key = key, defaultTab = defaultTab, retailOnly = retailOnly }
    if not defaultTab then
        binding.override = "MSUFSUITE_CHARACTER_FROM_" .. id:upper()
        binding.defaultLabel = Text("Blizzard window")
    end
    return binding
end

-- Separate Blizzard windows are opt-in routes. The default keeps the
-- original Blizzard command, including its special window and combat rules.
local nativeDescriptors = {
    Native("character", "TOGGLECHARACTER0", "Character", "homeTab", "overview"),
    Native("reputation", "TOGGLECHARACTER2", "Reputation", "reputationBindingTab", "reputation"),
    Native("currency", "TOGGLECURRENCY", "Currency", "currencyBindingTab", "currency"),
    Native("pvp", "TOGGLECHARACTER4", "PvP", "pvpBindingTab", NS.Client.isForever and "pvp" or nil),
    Native("professions", "TOGGLEPROFESSIONBOOK", "Professions", "professionsBindingTab"),
    Native("statistics", "TOGGLESTATISTICS", "Statistics", "statisticsBindingTab", nil, true),
}
local nativeById, byCommand, directById = {}, {}, {}
for _, binding in ipairs(nativeDescriptors) do
    if not binding.retailOnly or NS.Client.isMainline then
        Bindings.Native[#Bindings.Native + 1], nativeById[binding.id] = binding, binding
        if binding.override then byCommand[binding.override] = binding end
    end
end

local function Direct(id, label)
    return { id = id, command = "MSUFSUITE_CHARACTER_" .. id:upper(), label = Text(label) }
end

Bindings.Direct = {
    Direct("overview", "Overview"),
    Direct("gear", "Equipment"),
    Direct("reputation", "Reputation"),
    Direct("attributes", "Attributes"),
    Direct("skills", "Skills"),
    Direct("pvp", "PvP"),
    Direct("currency", "Currency"),
    Direct("statistics", "Statistics"),
}

_G.BINDING_HEADER_MSUFSUITE_CHARACTER = Text("Character Panel")
local openLabel = Text("Open %s")
for _, binding in ipairs(Bindings.Direct) do
    byCommand[binding.command], directById[binding.id] = binding, binding
    _G["BINDING_NAME_" .. binding.command] = openLabel:format(binding.label)
end

-- Slots are commands in Blizzard's binding set. A Suite profile links a
-- slot to an explicit, stable tab ID. Tab order never changes that link.
local slotLabel = Text("Custom tab shortcut %d")
local namedSlotLabel = Text("Custom tab shortcut %d (%s)")
local slotNames = {}
for i = 1, Tabs.TabLimit do
    local command = "MSUFSUITE_CHARACTER_CUSTOM" .. i
    local binding = { command = command, key = "characterBindingSlot" .. i, label = slotLabel:format(i), index = i }
    Bindings.Slots[i], byCommand[command] = binding, binding
    _G["BINDING_NAME_" .. command] = binding.label
end

function Bindings.RefreshLabels(config)
    for i, binding in ipairs(Bindings.Slots) do
        local id = config and config[binding.key]
        local tab = id and id ~= "" and Tabs.Find(config, id)
        local name = tab and tab.name or nil
        if name ~= slotNames[i] then
            slotNames[i] = name
            _G["BINDING_NAME_" .. binding.command] = name and namedSlotLabel:format(i, name) or binding.label
        end
    end
end

function Bindings.NativeTab(config, nativeId)
    local binding = nativeById[nativeId]
    if not binding then return end
    local header = NS.CharacterHeader
    local id = config[binding.key]
    if not id or id == "" then id = binding.defaultTab end
    if id and header.TabVisible(config, PLAYER, id) then return id end
    if not binding.override then return header.HomeTab(config, PLAYER) end
end

function Bindings.DirectTab(config, command)
    local binding = byCommand[command]
    if not binding then return end
    if binding.override then return Bindings.NativeTab(config, binding.id) end
    local id = binding.id or config[binding.key]
    if NS.CharacterHeader.TabVisible(config, PLAYER, id) then return id end
end

function Bindings.CommandForTab(config, id)
    local binding = directById[id]
    if binding then return binding.command end
    if not Tabs.Find(config, id) then return end
    for _, slot in ipairs(Bindings.Slots) do
        if config[slot.key] == id then return slot.command end
    end
end

function Bindings.SetSlot(config, index, id)
    local slot = Bindings.Slots[index]
    if not slot then return end
    local current = config[slot.key] or ""
    if id == current then return end
    if id == "" then return { [slot.key] = "" } end
    if not Tabs.Find(config, id) or Tabs.Find(config, current) then return end

    local patch = { [slot.key] = id }
    for _, other in ipairs(Bindings.Slots) do
        if config[other.key] == id then patch[other.key] = "" end
    end
    return patch
end

function Bindings.SetNativeTab(config, nativeId, id)
    local binding = nativeById[nativeId]
    if not binding then return end
    if id == "" then
        if nativeId == "character" then id = binding.defaultTab end
    elseif not NS.CharacterHeader.TabVisible(config, PLAYER, id) then
        return
    end
    if (config[binding.key] or "") ~= id then return { [binding.key] = id } end
end

function Bindings.ClearTab(config, id, patch)
    -- The home destination is already handled by CharacterHeader.
    for i = 2, #nativeDescriptors do
        local key = nativeDescriptors[i].key
        if config[key] == id then patch[key] = "" end
    end
    for _, slot in ipairs(Bindings.Slots) do
        if config[slot.key] == id then patch[slot.key] = "" end
    end
end

function Bindings.Normalize(config)
    for i = 2, #nativeDescriptors do
        local key = nativeDescriptors[i].key
        local id = config[key]
        if id ~= nil and id ~= "" and not directById[id] and not Tabs.Find(config, id) then config[key] = "" end
    end
    local seen = {}
    for _, slot in ipairs(Bindings.Slots) do
        local id = config[slot.key]
        if id ~= nil and id ~= "" then
            if not Tabs.Find(config, id) or seen[id] then
                config[slot.key] = ""
            else
                seen[id] = true
            end
        end
    end
end

function Bindings.RegisterSettings(build, module)
    -- Retain every route in the profile even on the other client.
    local rules = {}
    for i = 2, #nativeDescriptors do
        rules[#rules + 1] = build.String(nativeDescriptors[i].key, "Shortcut destination", "", TAB_ID_LIMIT)
    end
    for _, slot in ipairs(Bindings.Slots) do
        rules[#rules + 1] = build.String(slot.key, "Custom tab shortcut", "", TAB_ID_LIMIT)
    end
    for _, rule in ipairs(rules) do rule.hidden = true end
    build.Section(module, "bindings", "Key bindings", rules)
end

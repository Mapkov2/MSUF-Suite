local _, P = ...
local NS, S = P.NS, P.Suite
if not NS.Client.isForever then return end
local M = {}
local IN_COMBAT = { inCombat = true }
local BANK = Enum.SpellBookSpellBank.Player
local VOLUMES = { Sound_MusicVolume = "music", Sound_AmbienceVolume = "ambience", Sound_SFXVolume = "effects" }
local function Restore()
    if not M.audio then return end
    M.audio = nil
    for key in pairs(VOLUMES) do S.RestoreCVar("fishingComfort", key) end
    S.RefreshSoundProfile()
end
local function FishingSpell()
    local _, _, _, index = GetProfessions()
    if not S.Finite(index) then return end
    local _, _, _, _, count, offset = GetProfessionInfo(index)
    if not S.Finite(count) or not S.Finite(offset) then return end
    for i = 1, math.min(count, 8) do
        local info = C_SpellBook.GetSpellBookItemInfo(offset + i, BANK)
        if S.Public(info) and type(info) == "table" and S.Finite(info.spellID) then
            local passive = C_Spell.IsSpellPassive(info.spellID)
            if S.Public(passive) and passive == false then return info.spellID end
        end
    end
end
local function ItemID(text)
    local id = type(text) == "string" and text:match("^%s*(%d+)%s*$")
    id = id and tonumber(id)
    return id and id > 0 and id < 2147483647 and id or nil
end
local function SecureButton(name)
    local button = S.CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:Hide()
    return button
end
local cleanup
local Prepare
Prepare = function()
    if NS.InCombat() then
        if not M.active then
            if not cleanup then
                cleanup = S.CreateFrame("Frame")
                cleanup:SetScript("OnEvent", function()
                    cleanup:UnregisterAllEvents()
                    Prepare()
                end)
            end
            cleanup:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
        return
    end
    if cleanup then cleanup:UnregisterAllEvents() end
    if not M.button then
        if not M.active then return end
        M.button, M.lure = SecureButton("MSUFSuiteFishing"), SecureButton("MSUFSuiteFishingLure")
    end
    local spell = M.active and FishingSpell()
    M.spell = spell
    local info = spell and C_Spell.GetSpellInfo(spell)
    local name = S.Public(info) and type(info) == "table" and S.PublicText(info.name)
    local macro = name and "/cast " .. name
    local rod = M.active and ItemID(M.config.rod)
    if rod and macro then
        local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(rod)
        if S.Finite(class) and S.Finite(subclass) and class == Enum.ItemClass.Weapon
            and subclass == Enum.ItemWeaponSubclass.Fishingpole then macro = "/equip item:" .. rod .. "\n" .. macro end
    end
    local lure = M.active and ItemID(M.config.lure)
    local lureMacro = lure and "/use item:" .. lure .. "\n/use " .. INVSLOT_MAINHAND or nil
    if macro then macro = "/stopmacro [combat]\n" .. macro end
    if lureMacro then lureMacro = "/stopmacro [combat]\n" .. lureMacro end
    M.button:SetAttribute("macrotext1", macro)
    M.button:SetAttribute("type1", macro and "macro" or nil)
    M.lure:SetAttribute("macrotext1", lureMacro)
    M.lure:SetAttribute("type1", lureMacro and "macro" or nil)
end
local function Audio(_, event, unit)
    if unit ~= "player" then return end
    Restore()
    if event ~= "UNIT_SPELLCAST_CHANNEL_START" or not M.config.audio or not M.spell or NS.InCombat() then return end
    local _, _, _, _, _, _, _, spell = UnitChannelInfo("player")
    if not S.Finite(spell) or spell ~= M.spell then return end
    S.SuspendSoundProfile()
    M.audio = true
    for key, setting in pairs(VOLUMES) do M.context:CVar(key, M.config[setting] / 100) end
end
local function Changed(_, event)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LEAVING_WORLD" then
        Restore()
        return
    end
    Prepare()
end
function M:Enable()
    self.context:Event("PLAYER_REGEN_DISABLED", Changed, IN_COMBAT)
    self.context:Event("PLAYER_REGEN_ENABLED", Changed, IN_COMBAT)
    self.context:Event("PLAYER_ENTERING_WORLD", Changed, IN_COMBAT)
    self.context:Event("PLAYER_LEAVING_WORLD", Changed, IN_COMBAT)
    self.context:Event("SPELLS_CHANGED", Changed, IN_COMBAT)
    self.context:Event("SKILL_LINES_CHANGED", Changed, IN_COMBAT)
    self:Refresh()
end
function M:Refresh()
    Restore()
    for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED" }) do
        if self.config.audio then self.context:Event(event, Audio, IN_COMBAT, "player")
        else
            self.context:RemoveEvent(event)
        end
    end
    Prepare()
end
function M:Disable()
    Restore()
    Prepare()
end
S.Install("fishingComfort", M)

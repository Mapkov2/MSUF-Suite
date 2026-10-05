local _, P = ...
local Suite, S = P.Suite, P.S
local Preview = {}
P.ActionBarPreview = Preview
local IsSecret = Suite.IsSecret
local function Number(value) return not IsSecret(value) and type(value) == "number" end

local function Slot(bar, ordinal)
    local slot = S.ActionBarPreviewSlot and S.ActionBarPreviewSlot(bar, ordinal)
    if Number(slot) then return slot end
    if bar ~= 1 then return Suite.ActionBarFirstSlots[bar] + ordinal - 1 end
    -- Without the optional runtime, Blizzard's button already resolves bonus,
    -- vehicle and ordinary pages. Read it without changing the live frame.
    local native = rawget(_G, "ActionButton" .. ordinal)
    slot = native and not Suite.Safety.IsForbidden(native) and native.action
    if Number(slot) then return slot end
    local page = C_ActionBar.GetActionBarPage()
    return ((Number(page) and page or 1) - 1) * 12 + ordinal
end

function Preview.Key(bar, ordinal)
    local key = GetBindingKey(Suite.ActionBarCommands[bar] .. ordinal)
    if IsSecret(key) or type(key) ~= "string" then return "" end
    return S.KeyText and S.KeyText(key) or GetBindingText(key)
end

local function Action(tile, slot, config)
    tile.slot = slot
    local has = C_ActionBar.HasAction(slot)
    tile.count:SetText(C_ActionBar.GetActionDisplayCount(slot))
    local usesText = C_ActionBar.UsesActionText(slot)
    if not IsSecret(usesText) and usesText then tile.name:SetText(C_ActionBar.GetActionText(slot)) end
    local duration = C_ActionBar.GetActionCooldownDuration(slot)
    if duration then tile.cooldown:SetCooldownFromDurationObject(duration) end
    local charges = C_ActionBar.GetActionCharges(slot)
    if not IsSecret(charges) and type(charges) == "table" then
        local active = charges.isActive
        if not IsSecret(active) and active then
            local recharge = C_ActionBar.GetActionChargeDuration(slot)
            if recharge then tile.chargeCooldown:SetCooldownFromDurationObject(recharge) end
        end
        if config.hideEmptyCharges and Number(charges.maxCharges) and charges.maxCharges > 1
            and not IsSecret(charges.currentCharges) and charges.currentCharges == 0 then tile.count:SetAlpha(0) end
    end
    return C_ActionBar.GetActionTexture(slot), not IsSecret(has) and has == true
end

local function LegacyCooldown(cooldown, start, duration, enabled)
    -- These legacy APIs do not offer duration objects. Never inspect or send
    -- protected numeric values through the tainted SetCooldown path.
    if Number(start) and Number(duration) and not IsSecret(enabled)
        and enabled and enabled ~= 0 and start > 0 and duration > 0 then
        cooldown:SetCooldown(start, duration)
    end
end

function Preview.Read(tile, bar, ordinal, config)
    tile.key:SetText(Preview.Key(bar, ordinal))
    tile.count:SetText("")
    tile.count:SetAlpha(1)
    tile.name:SetText("")
    tile.cooldown:Clear()
    tile.chargeCooldown:Clear()
    local texture, filled
    if bar <= 10 then
        texture, filled = Action(tile, Slot(bar, ordinal), config)
    elseif bar == 11 then
        local forms = GetNumShapeshiftForms()
        if Number(forms) and ordinal <= forms then
            texture = GetShapeshiftFormInfo(ordinal)
            filled = true
            LegacyCooldown(tile.cooldown, GetShapeshiftFormCooldown(ordinal))
        end
    else
        local name, icon, token = GetPetActionInfo(ordinal)
        if not IsSecret(token) and token and not IsSecret(icon) and type(icon) == "string" then
            icon = rawget(_G, icon)
        end
        texture = icon
        filled = not IsSecret(name) and name ~= nil
        if filled then LegacyCooldown(tile.cooldown, GetPetActionCooldown(ordinal)) end
    end
    tile.icon:SetTexture(texture)
    tile.filled = filled == true
    tile.icon:SetShown(tile.filled)
end

-- The preview owns no timer loop. A burst of native changes gets one paint
-- next frame; subscriptions and queued work stop when this canvas hides.
local EVENTS = { "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_BINDINGS", "UPDATE_MACROS",
    "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USES", "BAG_UPDATE_DELAYED",
    "SPELL_UPDATE_ICON", "UPDATE_SUMMONPETS_ACTION",
    "UPDATE_SHAPESHIFT_FORMS", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_COOLDOWN",
    "PET_BAR_UPDATE", "PET_UI_UPDATE", "PET_BAR_UPDATE_COOLDOWN", "UNIT_PET",
    "MODIFIER_STATE_CHANGED", "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD" }
function Preview.Watch(ui)
    local host = ui.host
    host:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_PET" and (IsSecret(unit) or unit ~= "player") then return end
        if ui.pending then return end
        ui.pending = true
        C_Timer.After(0, function()
            ui.pending = false
            if ui.active then ui.Paint() end
        end)
    end)
    host:SetScript("OnShow", function()
        ui.active = true
        for _, event in ipairs(EVENTS) do host:RegisterEvent(event) end
        ui.Paint()
    end)
    host:SetScript("OnHide", function()
        ui.active = false
        host:UnregisterAllEvents()
    end)
    if host:IsVisible() then host:GetScript("OnShow")() end
end

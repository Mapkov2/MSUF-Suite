local _, P = ...
local Suite, S = P.Suite, P.S
local Preview = {}
P.ActionBarPreview = Preview
local IsSecret = Suite.IsSecret
local ENUM = Suite.ActionBarEnum
local LAST_ACTION = ENUM.BAR.LAST_ACTION
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
    local page = GetActionBarPage()
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
    tile.glow = false
    -- The color setting the bar's own paint tints this button with.
    tile.tint = bar <= LAST_ACTION and S.ActionBarPreviewTint and S.ActionBarPreviewTint(bar, ordinal) or nil
end

-- Out of range and a spell alert are short-lived on a real bar, so their
-- options would almost never show. While an option is on, the second button
-- the preview displays wears the out-of-range color and the third the alert
-- glow (the last button when fewer show), on a sample icon if the slot is
-- empty. Stance and pet buttons have neither state. `displayed` lists the
-- `shown` buttons in order, after Preview.Read.
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SAMPLE_RANGE, SAMPLE_GLOW = 2, 3
local function SampleTile(displayed, shown, position)
    local tile = displayed[math.min(position, shown)]
    if not tile.filled then
        tile.icon:SetTexture(SAMPLE_ICON)
        tile.icon:SetShown(true)
        tile.filled = true
    end
    return tile
end
function Preview.Sample(displayed, shown, bar, config)
    if shown == 0 or bar > LAST_ACTION then return end
    if config.rangeColoring then SampleTile(displayed, shown, SAMPLE_RANGE).tint = "rangeColor" end
    if config.procGlow ~= ENUM.PROC_GLOW.NONE then SampleTile(displayed, shown, SAMPLE_GLOW).glow = true end
end

-- Page arrows hang beside bar 1 only: the side they sit on ("LEFT" or
-- "RIGHT"), else nil.
function Preview.PageArrowSide(bar, config)
    if bar ~= ENUM.BAR.MAIN or not config.pageArrows then return nil end
    return config.pageArrowSide == ENUM.PAGE_ARROW_SIDE.LEFT and "LEFT" or "RIGHT"
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
-- The kit host registers the events while the preview shows and repaints once
-- a frame however many arrive; the events themselves stay here.
function Preview.Watch(ui)
    local host = ui.host
    ui.kit = Suite.PreviewKit.NewHost(nil, { frame = host, paint = function() ui.Paint() end,
        activate = function(kit)
            for _, event in ipairs(EVENTS) do host:RegisterEvent(event) end
            kit:Paint("show")
        end,
        deactivate = function() host:UnregisterAllEvents() end })
    host:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_PET" and (IsSecret(unit) or unit ~= "player") then return end
        ui.kit:Request("event")
    end)
    host:SetScript("OnShow", function() ui.kit:Activate() end)
    host:SetScript("OnHide", function() ui.kit:Deactivate() end)
    if host:IsVisible() then ui.kit:Activate() end
end

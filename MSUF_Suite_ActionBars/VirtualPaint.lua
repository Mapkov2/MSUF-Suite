local _, P = ...
local NS, S = P.NS, P.Suite
local AB = P.ActionBars
local M = AB.M
local Public = S.Public
local BAR, VIS = AB.ENUM.BAR.INDEPENDENT, AB.ENUM.VISIBILITY
local Virtual = {}
AB.VirtualPaint = Virtual

local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Number(value)
    return Public(value) and type(value) == "number"
end

local function MacroIndex(id)
    if type(id) == "number" then return id end
    local index = GetMacroIndexByName(id)
    if Number(index) and index > 0 then return index end
end

function Virtual.Spell(action)
    if not action then return end
    local kind, id = action.kind, action.id
    if kind == "spell" then return id end
    local spell
    if kind == "macro" then
        local index = MacroIndex(id)
        if index then spell = GetMacroSpell(index) end
    elseif kind == "mount" then
        spell = select(2, C_MountJournal.GetMountInfoByID(id))
    end
    if Number(spell) and spell > 0 then return spell end
end

function Virtual.ActionInfo(action)
    if not action then return end
    local kind = action.kind
    if kind == "flyout" then return kind, action.id end
    local spell = Virtual.Spell(action)
    if kind == "macro" then return kind, spell, "spell" end
    if spell then return "spell", spell end
    return kind
end

local function VisualSpell(action)
    local spell = Virtual.Spell(action)
    if not spell then return end
    local override = C_Spell.GetOverrideSpell(spell)
    return Number(override) and override > 0 and override or spell
end

local function FlyoutIcon(id)
    local _, _, slots = GetFlyoutInfo(id)
    if not Number(slots) then return end
    for i = 1, slots do
        local spell, override, known = GetFlyoutSlotInfo(id, i)
        if Public(known) and known and Number(spell) then
            return C_Spell.GetSpellTexture(Number(override) and override > 0 and override or spell)
        end
    end
end

local function Texture(action, spell)
    local kind, id = action.kind, action.id
    if kind == "macro" then
        local index = MacroIndex(id)
        if index then
            local name, icon = GetMacroInfo(index)
            return icon, name
        end
    elseif kind == "item" or kind == "toy" then
        return C_Item.GetItemIconByID(id)
    elseif kind == "flyout" then
        local icon = FlyoutIcon(id)
        return icon
    elseif kind == "equipmentset" then
        local _, icon = C_EquipmentSet.GetEquipmentSetInfo(id)
        return icon
    elseif kind == "outfit" then
        if id == 0 then
            return C_Spell.GetSpellTexture(Constants.TransmogOutfitDataConsts.CLEAR_TRANSMOG_OUTFIT_MANUAL_SPELL_ID)
        end
        local info = C_TransmogOutfitInfo.GetOutfitInfo(id)
        if Public(info) and info then return info.icon end
    elseif kind == "battlepet" then
        local icon = select(9, C_PetJournal.GetPetInfoByPetID(id))
        return icon
    elseif spell then
        return C_Spell.GetSpellTexture(spell)
    end
end

local function Visuals(action, spell)
    local texture, name = Texture(action, spell)
    if not NS.IsSecret(texture) and not texture then texture = UNKNOWN_ICON end
    return texture, name
end

local function SetDuration(frame, object)
    if object then
        frame:SetCooldownFromDurationObject(object)
    else
        frame:Clear()
    end
end

local function SetLegacyCooldown(frame, start, duration, enable)
    if Number(start) and Number(duration) and Public(enable)
        and enable and enable ~= 0 and start > 0 and duration > 0 then
        frame:SetCooldown(start, duration)
    else
        frame:Clear()
    end
end

local function Cooldowns(action, spell, cooldown, charge, loc)
    local replace
    if spell then
        if loc and AB.locActive then
            local loss = C_Spell.GetSpellLossOfControlCooldownInfo(spell)
            local active = Public(loss) and loss and loss.isActive
            if Public(active) and active then
                local override = loss.shouldReplaceNormalCooldown
                replace = Public(override) and override == true
                SetDuration(loc, C_Spell.GetSpellLossOfControlCooldownDuration(spell))
            else
                loc:Clear()
            end
        elseif loc then
            loc:Clear()
        end
        SetDuration(cooldown, not replace and C_Spell.GetSpellCooldownDuration(spell) or nil)
        if charge then SetDuration(charge, not replace and C_Spell.GetSpellChargeDuration(spell) or nil) end
    else
        if loc then loc:Clear() end
        if charge then charge:Clear() end
        local kind = action.kind
        if kind == "item" or kind == "toy" then
            SetLegacyCooldown(cooldown, C_Item.GetItemCooldown(action.id))
        else
            cooldown:Clear()
        end
    end
    return replace
end

local function SetCount(frame, action, spell, config)
    if not frame then return end
    local alpha = 1
    if spell then
        frame:SetText(C_Spell.GetSpellDisplayCount(spell, 99))
        if config.hideEmptyCharges then
            local charges = C_Spell.GetSpellCharges(spell)
            if Public(charges) and type(charges) == "table" then
                local maximum, current = charges.maxCharges, charges.currentCharges
                if Number(maximum) and maximum > 1 and Number(current) and current == 0 then alpha = 0 end
            end
        end
    elseif action.kind == "item" then
        local count = C_Item.GetItemCount(action.id, false, true)
        frame:SetText(count)
    else
        frame:SetText("")
    end
    frame:SetAlpha(alpha)
end

local function Feedback(rec, spell, replace)
    local config = M.config
    local desaturate, alpha = config.desaturateCooldown, config.cooldownAlpha < 100
    local object = spell and not replace and (desaturate or alpha) and C_Spell.GetSpellCooldownDuration(spell, true)
    if not object and not rec.feedback then return end
    local button = rec.button
    rec.feedback = object and true or nil
    if desaturate and object then
        button.icon:SetDesaturation(object:EvaluateRemainingDuration(AB.desatCurve))
    else
        button.icon:SetDesaturation(0)
    end
    if alpha and object then
        button:SetAlpha(object:EvaluateRemainingDuration(AB.alphaCurve))
    else
        button:SetAlpha(1)
    end
end

function Virtual.Cooldown(rec, spell)
    local action = rec.virtualAction
    if not action then return end
    local button = rec.button
    if spell == nil then spell = VisualSpell(action) end
    local replace = Cooldowns(action, spell, button.cooldown, button.chargeCooldown, button.lossOfControlCooldown)
    Feedback(rec, spell, replace)
    return spell or false
end

function Virtual.Count(rec, spell)
    local action = rec.virtualAction
    if not action then return end
    if spell == nil then spell = VisualSpell(action) end
    SetCount(rec.button.Count, action, spell, M.config)
end

function Virtual.CooldownAndCount(rec, spell)
    Virtual.Count(rec, Virtual.Cooldown(rec, spell))
end

local function MacroText(action)
    if action.kind == "macro" then
        local index = MacroIndex(action.id)
        if index then return GetMacroInfo(index) end
    end
    return ""
end

function Virtual.Preview(action, tile, config)
    if not action then return end
    local spell = VisualSpell(action)
    Cooldowns(action, spell, tile.cooldown, tile.chargeCooldown)
    SetCount(tile.count, action, spell, config)
    local texture, name = Visuals(action, spell)
    tile.name:SetText(name)
    return texture, true
end

local function TextureAndText(rec, spell)
    local action = rec.virtualAction
    local button = rec.button
    local texture, name = Visuals(action, spell)
    button.icon:SetTexture(texture)
    button.icon:Show()
    if button.Name then button.Name:SetText(name) end
    if button.Border then
        local equipped = action.kind == "item" and C_Item.IsEquippedItem(action.id)
        if Public(equipped) and equipped then
            button.Border:SetVertexColor(0, 1, 0, .5)
            button.Border:Show()
        else
            button.Border:Hide()
        end
    end
end

local function Usability(rec, spell)
    local action = rec.virtualAction
    if not action then return false end
    if spell == nil then spell = VisualSpell(action) end
    if spell then
        local inRange = M.config.rangeColoring and C_Spell.IsSpellInRange(spell, "target")
        rec.outOfRange = Public(inRange) and inRange == false and M.config.rangeColoring or nil
        return C_Spell.IsSpellUsable(spell)
    end
    rec.outOfRange = nil
    if action.kind == "item" then return C_Item.IsUsableItem(action.id) end
    return true
end

function Virtual.State(rec, spell)
    local action = rec.virtualAction
    local checked = false
    if M.config.castHighlight and action then
        if spell == nil then spell = VisualSpell(action) end
        if spell then
            local current = C_Spell.IsCurrentSpell(spell)
            if Public(current) and current then
                checked = true
            else
                local repeatCast = C_Spell.IsAutoRepeatSpell(spell)
                checked = Public(repeatCast) and repeatCast == true
            end
        end
    end
    rec.button:SetChecked(checked)
    rec.decorChecked = checked
    AB.UpdateDecorState(rec)
end

local function TooltipText(tooltip, title, text)
    if Public(title) and type(title) == "string" then
        tooltip:SetText(title)
        if Public(text) and type(text) == "string" and text ~= "" then tooltip:AddLine(text, 1, 1, 1, true) end
        tooltip:Show()
    end
end

function Virtual.Tooltip(rec)
    local action = rec.virtualAction
    if not action then return end
    local kind, id = action.kind, action.id
    local tooltip = GameTooltip
    if kind == "item" then
        tooltip:SetItemByID(id)
    elseif kind == "toy" then
        tooltip:SetToyByItemID(id)
    elseif kind == "macro" then
        TooltipText(tooltip, (MacroText(action)))
    elseif kind == "flyout" then
        TooltipText(tooltip, GetFlyoutInfo(id))
    elseif kind == "equipmentset" then
        tooltip:SetEquipmentSet(id)
    elseif kind == "outfit" then
        if id == 0 then
            tooltip:SetSpellByID(Constants.TransmogOutfitDataConsts.CLEAR_TRANSMOG_OUTFIT_MANUAL_SPELL_ID)
        else
            tooltip:SetOutfit(id)
        end
    elseif kind == "battlepet" then
        local _, customName, _, _, _, _, _, name = C_PetJournal.GetPetInfoByPetID(id)
        TooltipText(tooltip, Public(customName) and customName or name)
    else
        local spell = VisualSpell(action)
        if spell then tooltip:SetSpellByID(spell) end
    end
end


function Virtual.Usable(rec, spell)
    local usable, noMana = Usability(rec, spell)
    if not Public(usable) or usable == nil then usable = false end
    AB.Painter.Usable(rec, usable, noMana)
end

function Virtual.Paint(rec)
    local painter = AB.Painter
    if rec.virtualAction then
        rec.filled, rec.tint = true, nil
        local action = rec.virtualAction
        local spell = VisualSpell(action) or false
        TextureAndText(rec, spell)
        Virtual.Usable(rec, spell)
        Virtual.State(rec, spell)
        Virtual.CooldownAndCount(rec, spell)
        local quality
        if action.kind == "item" then
            quality = C_TradeSkillUI.GetItemReagentQualityInfo(action.id)
            if Public(quality) and not quality then quality = C_TradeSkillUI.GetItemCraftedQualityInfo(action.id) end
        end
        painter.SetQuality(rec, quality)
        painter.GlowCheck(rec)
        painter.RouteSpell(rec)
    else
        painter.Clear(rec)
        rec.outOfRange = nil
    end
    AB.UpdateAssist(rec)
end

function S.ActionBarPreviewVirtual(ordinal, tile, config)
    local bar = M.active and AB.bars[BAR]
    local rec = bar and bar.buttons[ordinal]
    if rec and rec.virtual then return Virtual.Preview(rec.virtualAction, tile, config) end
end


-- Direct actions receive their own native notifications only while their
-- type is assigned to an enabled bar. The shared flush coalesces repaints.
local function Changed()
    local bar = M.active and AB.bars[BAR]
    if bar and AB.Painter.Visible(bar) then AB.MarkBar(bar) end
end

local function RangeChanged(_, _, spell, inRange, checksRange)
    if not Number(spell) or not Public(inRange) or not Public(checksRange) then return end
    local painter = AB.Painter
    local buttons = painter.spellButtons[spell]
    if not buttons then return end
    local out = checksRange and not inRange or nil
    for i = 1, #buttons do
        local rec = buttons[i]
        if rec.virtual and rec.filled and painter.Visible(rec.bar) and rec.outOfRange ~= out then
            rec.outOfRange = out
            painter.Tint(rec)
        end
    end
end

local IN_COMBAT = { inCombat = true }
local EVENTS = {
    BAG_UPDATE_COOLDOWN = Changed,
    MODIFIER_STATE_CHANGED = Changed,
    PLAYER_TARGET_CHANGED = Changed,
    SPELL_UPDATE_USES = Changed,
    SPELL_RANGE_CHECK_UPDATE = RangeChanged,
    EQUIPMENT_SETS_CHANGED = function() AB.Virtual.Sync(true) end,
}
local registered = {}

function Virtual.SyncEvents(context)
    local bar = AB.bars[BAR]
    local items, macro, spell, equipment
    if bar and M.config[AB.KEYS[BAR].Visibility] ~= VIS.NEVER then
        for i = 1, #bar.buttons do
            local action = bar.buttons[i].virtualAction
            local kind = action and action.kind
            items = items or kind == "item" or kind == "toy"
            macro = macro or kind == "macro"
            spell = spell or kind == "spell" or kind == "mount"
            equipment = equipment or kind == "equipmentset"
        end
    end
    local range = (spell or macro) and M.config.rangeColoring
    for event, handler in pairs(EVENTS) do
        local wanted = (event == "BAG_UPDATE_COOLDOWN" and items)
            or (event == "MODIFIER_STATE_CHANGED" and macro)
            or (event == "PLAYER_TARGET_CHANGED" and range)
            or (event == "SPELL_UPDATE_USES" and (spell or macro))
            or (event == "SPELL_RANGE_CHECK_UPDATE" and range)
            or (event == "EQUIPMENT_SETS_CHANGED" and equipment)
        if wanted and not registered[event] then
            registered[event] = true
            context:Event(event, handler, IN_COMBAT)
        elseif not wanted and registered[event] then
            registered[event] = nil
            context:RemoveEvent(event)
        end
    end
end

function Virtual.StopEvents(context)
    for event in pairs(registered) do
        registered[event] = nil
        context:RemoveEvent(event)
    end
end

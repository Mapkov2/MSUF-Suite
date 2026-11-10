local _, P = ...
local NS, S = P.NS, P.Suite
local E = {}
P.ExtensionEffects = E

local function Pulse(region)
    local group = region:CreateAnimationGroup()
    local animation = group:CreateAnimation("Alpha")
    animation:SetFromAlpha(.3)
    animation:SetToAlpha(1)
    animation:SetDuration(.5)
    group:SetLooping("BOUNCE")
    return group
end

function E.Configure(plan)
    if not plan.enabled or not plan.execute then return end
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, 0)
    curve:AddPoint(.000001, plan.executeAlpha)
    curve:AddPoint(plan.executeAt + .000001, 0)
    curve:AddPoint(1, 0)
    plan.executeCurve = curve
end

local function ExecuteVisual(state)
    local visual = state.executeVisual
    if visual then return visual end
    local gate = CreateFrame("Frame", nil, state.uf)
    gate:SetAllPoints(state.health)
    gate:EnableMouse(false)
    local pulse = CreateFrame("Frame", nil, gate)
    pulse:SetAllPoints(gate)
    pulse:EnableMouse(false)
    visual = { gate = gate, pulse = pulse, border = NS.NameplateStyle.CreateBorder(pulse), animation = Pulse(pulse) }
    state.executeVisual = visual
    return visual
end

function E.Execute(state)
    local plan, visual = state.plan, state.executeVisual
    if not plan.executeCurve or state.prefix ~= "enemy" or state.visible == false then
        if visual then visual.animation:Stop() visual.gate:Hide() end
        return
    end
    visual = visual or ExecuteVisual(state)
    if visual.plan ~= plan then
        NS.NameplateStyle.PaintBorder(visual.border, state.health, 2, plan.executeColor)
        visual.plan = plan
    end
    -- Restricted health is transformed and consumed entirely in native code.
    -- Lua never tests restricted alpha or runs a health-driven update script.
    local alpha = UnitHealthPercent(state.unit, false, plan.executeCurve)
    visual.gate:SetAlpha(alpha)
    visual.gate:Show()
    if S.Finite(alpha) and alpha <= 0 then
        visual.animation:Stop()
    elseif not visual.animation:IsPlaying() then
        visual.animation:Play()
    end
end

local function InterruptVisual(state)
    if state.interruptVisual then return state.interruptVisual end
    if not state.cast then return end
    local frame = CreateFrame("Frame", nil, state.uf)
    frame:SetAllPoints(state.cast)
    frame:EnableMouse(false)
    local level = state.cast:GetFrameLevel()
    if S.Finite(level) then frame:SetFrameLevel(level + 15) end
    local fill = frame:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(frame)
    local text = frame:CreateFontString(nil, "OVERLAY", "SystemFont_NamePlateCastBar")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetTextColor(1, 1, 1)
    local visual = { frame = frame, fill = fill, text = text, animation = Pulse(fill) }
    state.interruptVisual = visual
    return visual
end

function E.Interrupt(state, guid)
    if not state.plan.interrupt then return end
    local visual = InterruptVisual(state)
    if not visual then return end
    local plan = state.plan
    visual.fill:SetColorTexture(S.RGB(plan.interruptColor))
    visual.text:SetText(NS.Text("Interrupted"))
    if plan.interruptWho and (NS.IsSecret(guid) or type(guid) == "string" and guid ~= "") then
        -- UnitNameFromGUID explicitly allows tainted callers with secret
        -- arguments. The returned name goes straight into a native text sink.
        local name = UnitNameFromGUID(guid)
        if NS.IsSecret(name) or type(name) == "string" and name ~= "" then
            visual.text:SetFormattedText(NS.Text("Interrupted by %s"), name)
        end
    end
    if plan.interruptFlash then visual.animation:Play() else visual.animation:Stop() end
    visual.frame:SetAlpha(1)
    visual.frame:Show()
    state.interruptUntil = GetTime() + plan.interruptDuration
end

function E.EndInterrupt(state)
    local visual = state.interruptVisual
    if visual then
        visual.animation:Stop()
        if P.ExtensionLayout.Mutable(state, visual.frame) then
            visual.frame:Hide()
        else
            visual.frame:SetAlpha(0)
        end
    end
    state.interruptUntil = nil
end

function E.Reminder(state, wanted)
    local label = state.focusLabel
    if wanted then
        if not label then
            label = state.uf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("BOTTOM", state.uf.name, "TOP", 0, 14)
            label:SetText(NS.Text("Set a hostile focus"))
            state.focusLabel = label
        end
        label:SetTextColor(S.RGB(state.plan.focusColor))
        label:Show()
    elseif label then
        label:Hide()
    end
end

function E.Range(state)
    local label = state.rangeLabel
    if state.plan.range and state.plan.rangeText and state.prefix == "enemy" then
        if not label then
            label = state.uf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOP", state.health, "BOTTOM", 0, -14)
            state.rangeLabel = label
        end
        label:SetText(NS.Text(NS.NameplateExtensions.RangeLabels[state.range or 3]))
        label:Show()
    elseif label then
        label:Hide()
    end
end

local function IdentityIcon(state, key, atlas, index)
    local icon = state[key]
    if not atlas then
        if icon then icon:Hide() end
        return
    end
    if not icon then
        icon = state.uf:CreateTexture(nil, "OVERLAY")
        state[key] = icon
    end
    local side = state.plan[state.prefix]
    icon:SetAtlas(atlas)
    icon:SetSize(side.identitySize, side.identitySize)
    icon:ClearAllPoints()
    icon:SetPoint("RIGHT", state.uf.name, "LEFT", side.identityX - index * (side.identitySize + 2), side.identityY)
    icon:Show()
end

function E.Identity(state)
    local mode = state.plan[state.prefix].identity
    local classAtlas, factionAtlas
    if mode > 1 and (state.kind == "enemyPlayer" or state.kind == "friendlyPlayer") then
        local restricted = C_Secrets.ShouldUnitIdentityBeSecret(state.unit)
        if not NS.IsSecret(restricted) and restricted == false then
            if mode == 2 or mode == 4 then
                local _, class = UnitClass(state.unit)
                if not NS.IsSecret(class) and type(class) == "string" and class ~= "" then classAtlas = GetClassAtlas(class) end
            end
            if mode == 3 or mode == 4 then
                local faction = UnitFactionGroup(state.unit)
                if not NS.IsSecret(faction) and (faction == "Horde" or faction == "Alliance") then
                    -- Both are taken from the loaded client's native PvP indicator style.
                    factionAtlas = NS.Client.isForever and "UI-HUD-UnitFrame-SmallCircle-" .. faction
                        or "UI-HUD-UnitFrame-Player-PVP-" .. faction .. "Icon"
                end
            end
        end
    end
    IdentityIcon(state, "classIcon", classAtlas, 0)
    IdentityIcon(state, "factionIcon", factionAtlas, classAtlas and 1 or 0)
end

function E.Hide(state)
    E.EndInterrupt(state)
    local visual = state.executeVisual
    if visual then visual.animation:Stop() visual.gate:Hide() end
    if state.focusLabel then state.focusLabel:Hide() end
    if state.rangeLabel then state.rangeLabel:Hide() end
    if state.classIcon then state.classIcon:Hide() end
    if state.factionIcon then state.factionIcon:Hide() end
end

local function OwnedAlpha(state, alpha)
    if state.labels then for _, label in pairs(state.labels) do label:SetAlpha(alpha) end end
    if state.focusLabel then state.focusLabel:SetAlpha(alpha) end
    if state.rangeLabel then state.rangeLabel:SetAlpha(alpha) end
    if state.classIcon then state.classIcon:SetAlpha(alpha) end
    if state.factionIcon then state.factionIcon:SetAlpha(alpha) end
end

function E.Suspend(state)
    if state.suspended then return end
    state.suspended = true
    OwnedAlpha(state, 0)
    if state.interruptVisual then state.interruptVisual.frame:SetAlpha(0) state.interruptVisual.animation:Stop() end
    if state.executeVisual then state.executeVisual.gate:SetAlpha(0) state.executeVisual.animation:Stop() end
end

function E.Resume(state)
    if not state.suspended then return end
    state.suspended = nil
    OwnedAlpha(state, 1)
    if state.interruptVisual then state.interruptVisual.frame:SetAlpha(1) end
end

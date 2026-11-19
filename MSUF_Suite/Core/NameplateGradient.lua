local _, NS = ...
local Gradient = {}
NS.NameplateStyle.Gradient = Gradient

local white = "Interface\\Buttons\\WHITE8X8"
local directions = {
    { axis = "HORIZONTAL", reverse = true }, -- Left
    { axis = "HORIZONTAL" },                 -- Right
    { axis = "VERTICAL" },                   -- Up
    { axis = "VERTICAL", reverse = true },   -- Down
}

function Gradient.Plan(config, key, previous)
    if config.look == 2 then return end
    local gradientKey, glossKey = key .. "Gradient", key .. "Gloss"
    local strength = config[gradientKey .. "Enabled"] and (config[gradientKey .. "Strength"] or 45) or 0
    local gloss = config[glossKey .. "Enabled"] and (config[glossKey .. "Strength"] or 50) or 0
    if strength <= 0 and gloss <= 0 then return end
    local color = strength > 0 and (config[gradientKey .. "Color"] or "000000")
    local left, right = color and config[gradientKey .. "DirLeft"] == true, color and config[gradientKey .. "DirRight"] ~= false
    local up, down = color and config[gradientKey .. "DirUp"] == true, color and config[gradientKey .. "DirDown"] == true
    if color and not (left or right or up or down) then right = true end
    if previous and previous.strength == strength and previous.color == color and previous.gloss == gloss
        and previous[1] == left and previous[2] == right and previous[3] == up and previous[4] == down then
        return previous
    end
    local plan = { left, right, up, down, strength = strength, color = color, gloss = gloss }
    if color then
        local r, g, b = NS.RGB(color)
        plan.clear, plan.tint = CreateColor(r, g, b, 0), CreateColor(r, g, b, strength / 100)
    end
    return plan
end

local function ApplyMask(texture, previous, mask)
    if not texture then return end
    if previous then texture:RemoveMaskTexture(previous) end
    if mask then texture:AddMaskTexture(mask) end
end

function Gradient.SetMask(state, mask)
    if not state or state.mask == mask then return end
    local previous = state.mask
    for i = 1, #directions do ApplyMask(state[i], previous, mask) end
    ApplyMask(state.glossUpper, previous, mask)
    ApplyMask(state.glossLower, previous, mask)
    state.mask = mask
end

-- These textures follow the filled region using native anchors. The bar
-- continues to own progress and neither painter needs to read its value.
function Gradient.Paint(owner, state, target, plan, initialMask)
    if not target then plan = nil end
    if not state then
        if not plan then return end
        state = { mask = initialMask }
    end
    if state.plan == plan and (not plan or state.target == target) then return state end
    for i, direction in ipairs(directions) do
        local texture = state[i]
        if plan and plan[i] then
            if not texture then
                -- Above role/DoT fill colors and below the bar text.
                texture = owner:CreateTexture(nil, "OVERLAY", nil, -2)
                texture:SetTexture(white)
                if state.alpha then texture:SetAlpha(state.alpha) end
                ApplyMask(texture, nil, state.mask)
                state[i] = texture
            end
            if not state.plan or not state.plan[i] or state.target ~= target then
                texture:ClearAllPoints()
                texture:SetAllPoints(target)
            end
            if not state.plan or not state.plan[i] or state.plan.color ~= plan.color or state.plan.strength ~= plan.strength then
                local first, last = plan.clear, plan.tint
                if direction.reverse then first, last = last, first end
                texture:SetGradient(direction.axis, first, last)
                texture:Show()
            end
        elseif texture and state.plan and state.plan[i] then
            texture:Hide()
        end
    end
    if plan and plan.gloss > 0 then
        local upper, lower = NS.GlossMaterial.Fill(owner, target, plan.gloss, state.alpha)
        if upper ~= state.glossUpper then
            ApplyMask(upper, nil, state.mask)
            ApplyMask(lower, nil, state.mask)
            state.glossUpper, state.glossLower = upper, lower
        end
        state.glossOwner = owner
    elseif state.glossOwner then
        NS.GlossMaterial.Fill(state.glossOwner)
        state.glossOwner = nil
    end
    state.plan, state.target = plan, plan and target
    return state
end

function Gradient.SetAlpha(state, alpha)
    if not state or state.alpha == alpha then return end
    state.alpha = alpha
    for i = 1, #directions do
        if state[i] then state[i]:SetAlpha(alpha) end
    end
    if state.glossOwner then NS.GlossMaterial.SetBarOpacity(state.glossOwner, alpha) end
end

local function CanAttach(uf, health, fill, combat)
    if not fill then return false end
    if fill.CanBeAccessedInContext then
        local accessible = fill:CanBeAccessedInContext()
        if not NS.Public(accessible) or not accessible then return false end
    end
    if not combat then return true end
    local protected, ownerProtected = health:IsProtected(), uf:IsProtected()
    return NS.Public(protected) and NS.Public(ownerProtected) and protected == false and ownerProtected == false
end

function Gradient.PaintHealth(health, visual, plan, uf, pending)
    local previous = visual.gradient
    if not (plan or previous) then return end
    local fill = plan and health:GetStatusBarTexture()
    if not NS.Public(fill) or fill and NS.Safety.IsForbidden(fill) then fill = nil end
    if plan and (not previous or previous.plan ~= plan or previous.target ~= fill) then
        local combat = NS.InCombat()
        if not CanAttach(uf, health, fill, combat) then
            if combat then pending[uf] = true end
            fill = nil
        end
    end
    visual.gradient = Gradient.Paint(health, previous, fill, plan, visual.slantMask)
end

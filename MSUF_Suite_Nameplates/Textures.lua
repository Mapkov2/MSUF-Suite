local _, private = ...
local NS, S = private.NS, private.Suite
local Textures = {
    saved = setmetatable({}, { __mode = "k" }),
    hooks = setmetatable({}, { __mode = "k" }),
    masks = setmetatable({}, { __mode = "k" }),
}
private.Textures = Textures

function Textures.Bind(module) Textures.module = module end
local function Safe(region) return region and not NS.Safety.IsForbidden(region) end

local function Detach(saved)
    if saved.mask then
        for _, field in ipairs({ "fill", "overlay" }) do
            local texture = saved[field]
            if Safe(texture) and texture.RemoveMaskTexture then texture:RemoveMaskTexture(saved.mask) end
        end
        saved.mask:Hide()
    end
    saved.overlay = nil
end

local function RestoreFill(saved)
    local fill = saved.fill
    if not Safe(fill) then return end
    local current = fill:GetTexture()
    if S.Public(current) and current == saved.applied then
        if saved.atlas and saved.atlas ~= "" then fill:SetAtlas(saved.atlas)
        else fill:SetTexture(saved.texture) end
        if saved.coords then fill:SetTexCoord(unpack(saved.coords)) end
    end
end

function Textures.Restore(health)
    local saved = Textures.saved[health]
    if not saved then return end
    Detach(saved)
    RestoreFill(saved)
    Textures.saved[health] = nil
end

function Textures.MaskOverlay(health, overlay, active)
    local saved = Textures.saved[health]
    if not saved or not saved.mask then return end
    local previous = saved.overlay
    local current = active and overlay or nil
    if previous == current then return end
    if Safe(previous) and previous.RemoveMaskTexture then previous:RemoveMaskTexture(saved.mask) end
    saved.overlay = nil
    if Safe(current) and current.AddMaskTexture then
        current:AddMaskTexture(saved.mask)
        saved.overlay = current
    end
end

local function Capture(fill, texture, atlas)
    local coords
    if fill.GetTexCoord then
        coords = { fill:GetTexCoord() }
        -- Texture coordinates can be secret; never retain or branch on them.
        if #coords ~= 8 then return nil end
        for i = 1, 8 do if not S.Finite(coords[i]) then return nil end end
    end
    return { fill = fill, texture = texture, atlas = atlas, coords = coords }
end

local function Mask(health, saved)
    local fill = saved.fill
    if not health.CreateMaskTexture or not fill.AddMaskTexture then return end
    local mask = Textures.masks[health]
    if not mask then
        mask = health:CreateMaskTexture(nil, "ARTWORK")
        mask:SetAllPoints(health)
        Textures.masks[health] = mask
    end
    if saved.atlas and saved.atlas ~= "" then mask:SetAtlas(saved.atlas)
    else mask:SetTexture(saved.texture or "Interface\\TargetingFrame\\UI-StatusBar") end
    if saved.coords then mask:SetTexCoord(unpack(saved.coords)) end
    mask:Show()
    fill:AddMaskTexture(mask)
    saved.mask = mask
    local m = Textures.module
    local visual = m.visuals[health]
    if visual then Textures.MaskOverlay(health, visual.fill, m.config.enemyRoleColors and m.roles[health] ~= nil) end
end

function Textures.Apply(uf, health)
    local m = Textures.module
    if not m.active or m.config.look == 2 or not S.Public(uf.isFriend) or type(uf.isFriend) ~= "boolean" then
        Textures.Restore(health); return
    end
    local prefix = uf.isFriend and "friendly" or "enemy"
    if not m.config[prefix] then Textures.Restore(health); return end
    local texture, focus
    if prefix == "enemy" then texture, focus = m.healthTexture, m.focusHealthTexture
    else texture, focus = m.friendlyHealthTexture, m.friendlyFocusHealthTexture end
    if focus and m.focused[health] then texture = focus end
    if not texture then Textures.Restore(health); return end
    local fill = health:GetStatusBarTexture()
    if not Safe(fill) then return end
    local current, atlas = fill:GetTexture(), fill.GetAtlas and fill:GetAtlas()
    if not S.Public(current) or not S.Public(atlas) then return end
    local saved = Textures.saved[health]
    local nativeChanged = not saved or saved.fill ~= fill or current ~= saved.applied or atlas and atlas ~= ""
    if nativeChanged then
        local original = Capture(fill, current, atlas)
        if not original then Textures.Restore(health); return end
        if saved then
            Detach(saved)
            if saved.fill ~= fill then RestoreFill(saved) end
        end
        saved = original
        Textures.saved[health] = saved
    end
    if nativeChanged or saved.request ~= texture then
        fill:SetTexture(texture)
        if fill.SetTexCoord then fill:SetTexCoord(0, 1, 0, 1) end
        local applied = fill:GetTexture()
        if S.Public(applied) then saved.applied = applied end
        saved.request = texture
        if nativeChanged then Mask(health, saved) end
    end
    -- Only explicit overrides observe native reanchoring; no health events,
    -- geometry measurements, native state writes or per-frame work.
    if not Textures.hooks[uf] and type(uf.UpdateAnchors) == "function" then
        Textures.hooks[uf] = true
        hooksecurefunc(uf, "UpdateAnchors", function(frame)
            if not m.active then return end
            local bar = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar
            if Safe(bar) then Textures.Apply(frame, bar) end
        end)
    end
end

function Textures.RestoreAll()
    for health in pairs(Textures.saved) do Textures.Restore(health) end
end

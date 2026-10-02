local _, private = ...
local NS = private.NS
local Threat = {}
private.Threat = Threat

local owner, hooked
local flashes = setmetatable({}, { __mode = "k" })
local highlights = setmetatable({}, { __mode = "k" })

local function Safe(region)
    return region and not NS.Safety.IsForbidden(region)
end

local function Eligible(uf)
    local config = owner and owner.config
    return owner and owner.active and config and config.look ~= 2 and config.enemy
        and Safe(uf) and NS.Public(uf.isFriend) and uf.isFriend == false
end

local function Color(region, hex)
    if not Safe(region) then return false end
    region:SetVertexColor(NS.RGB(hex))
    return true
end

-- Blizzard may tint these textures with values addon code cannot read; such
-- a color is not remembered, and the texture keeps Blizzard's tint.
local function Original(region)
    if not Safe(region) then return nil end
    local r, g, b, a = region:GetVertexColor()
    if not NS.Finite(r) or not NS.Finite(g) or not NS.Finite(b) or not NS.Finite(a) then return nil end
    return { r, g, b, a }
end

local function RestoreFlash(uf)
    local original = flashes[uf]
    if not original then return end
    local region = uf.aggroFlash
    if Safe(region) then
        region:SetVertexColor(original[1], original[2], original[3], original[4])
        flashes[uf] = nil
    end
end

local function RestoreHighlight(uf)
    if not highlights[uf] then return end
    local color = Original(uf.aggroHighlight)
    local base, additive = uf.aggroHighlightBase, uf.aggroHighlightAdditive
    if color and Safe(base) and Safe(additive) then
        base:SetVertexColor(color[1], color[2], color[3])
        additive:SetVertexColor(color[1], color[2], color[3])
        highlights[uf] = nil
    end
end

local function TintHighlight(uf)
    if Color(uf.aggroHighlightBase, owner.config.threatHighlightColor)
        and Color(uf.aggroHighlightAdditive, owner.config.threatHighlightColor) then
        highlights[uf] = owner.config.threatHighlightColor
    end
end

function Threat.Apply(uf)
    if not Safe(uf) then return end
    local config = owner and owner.config
    local eligible = Eligible(uf)
    if eligible and config.threatFlashColorEnabled then
        if not flashes[uf] then flashes[uf] = Original(uf.aggroFlash) end
        local original = flashes[uf]
        if original and original.applied ~= config.threatFlashColor
            and Color(uf.aggroFlash, config.threatFlashColor) then
            original.applied = config.threatFlashColor
        end
    else
        RestoreFlash(uf)
    end
    if eligible and config.threatHighlightColorEnabled then
        if highlights[uf] ~= config.threatHighlightColor then TintHighlight(uf) end
    else
        RestoreHighlight(uf)
    end
end

function Threat.Refresh()
    if hooked or not owner or not owner.active or owner.config.look == 2
        or not owner.config.enemy or not owner.config.threatHighlightColorEnabled then return end
    -- Skin.lua's plate hooks also reach the unit frames that already exist.
    private.HookPlates("UpdateAggroHighlight", function(uf)
        if Eligible(uf) and owner.config.threatHighlightColorEnabled then TintHighlight(uf) end
    end)
    hooked = true
end

function Threat.Enable(module)
    owner = module
    Threat.Refresh()
end

function Threat.Restore(uf)
    if not Safe(uf) then return end
    RestoreFlash(uf)
    RestoreHighlight(uf)
end

function Threat.Disable()
    for uf in pairs(flashes) do Threat.Restore(uf) end
    for uf in pairs(highlights) do Threat.Restore(uf) end
    owner = nil
end

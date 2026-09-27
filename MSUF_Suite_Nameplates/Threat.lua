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
    if not Safe(region) or type(region.SetVertexColor) ~= "function" then return false end
    local r, g, b = NS.RGB(hex)
    return pcall(region.SetVertexColor, region, r, g, b)
end

local function Original(region)
    if not Safe(region) or type(region.GetVertexColor) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(region.GetVertexColor, region)
    if not ok or not NS.Public(r) or not NS.Public(g) or not NS.Public(b)
        or not NS.Public(a) or not NS.Finite(r) or not NS.Finite(g)
        or not NS.Finite(b) or not NS.Finite(a) then return nil end
    return { r, g, b, a }
end

local function RestoreFlash(uf)
    local original = flashes[uf]
    if not original then return end
    local region = uf.aggroFlash
    if Safe(region) and pcall(region.SetVertexColor, region, unpack(original)) then
        flashes[uf] = nil
    end
end

local function RestoreHighlight(uf)
    if not highlights[uf] then return end
    local color = Original(uf.aggroHighlight)
    local base, additive = uf.aggroHighlightBase, uf.aggroHighlightAdditive
    if color and Safe(base) and Safe(additive)
        and pcall(base.SetVertexColor, base, color[1], color[2], color[3])
        and pcall(additive.SetVertexColor, additive, color[1], color[2], color[3]) then
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
    else RestoreFlash(uf) end
    if eligible and config.threatHighlightColorEnabled then
        if highlights[uf] ~= config.threatHighlightColor then TintHighlight(uf) end
    else RestoreHighlight(uf) end
end

function Threat.Refresh()
    if hooked or not owner or not owner.active or owner.config.look == 2
        or not owner.config.enemy or not owner.config.threatHighlightColorEnabled then return end
    local mixin = _G.NamePlateUnitFrameMixin
    if type(mixin) ~= "table" or type(mixin.UpdateAggroHighlight) ~= "function" then return end
    hooksecurefunc(mixin, "UpdateAggroHighlight", function(uf)
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

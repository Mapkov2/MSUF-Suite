local _, private = ...
local Style = private.NS.NameplateStyle
local Settings = {}
private.CastSettings = Settings

function Settings.Read(config)
    local current = Style.SharedCastbar(config.look)
    local target = config.look ~= 2 and config.castTargetHighlightStyle == 1
        and (config.enemyCastDisplay ~= 2 or config.enemyCastTargetHighlight)
    if not current and not target then return end
    local style = {}
    for key, value in pairs(current or {}) do style[key] = value end
    style.targetHighlight = target == true or nil
    if style.slanted and Style.SlantedSettings then
        local _, direction = Style.SlantedSettings(config)
        style.slantedDirection = direction
    elseif current and Style.RoundedCastMaterial then
        local material = Style.RoundedCastMaterial()
        if material then style.slanted, style.slantedDirection = true, material end
    end
    return style
end

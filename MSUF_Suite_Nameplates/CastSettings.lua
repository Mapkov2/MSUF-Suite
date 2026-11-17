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
    return style
end

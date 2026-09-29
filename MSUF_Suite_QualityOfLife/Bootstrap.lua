local _, private = ...
local suite = assert(_G.MSUFSuite, 'MSUF_Suite is required')
private.NS, private.Suite = suite, suite.Suite

-- Pure palette lookup for Suite-owned QoL surfaces. Semantic warning/status
-- colors remain with their modules.
function private.Suite.QoLStyle(config)
    local looks = suite.QoLVisualStyles
    return looks[config and config.look] or looks[1]
end

function private.Suite.QoLColor(region, hex, alpha)
    local r, g, b = private.Suite.RGB(hex)
    region:SetColorTexture(r, g, b, alpha or 1)
end

local _, P = ...
local NS, S = P.NS, P.Suite
-- MSUF Edit Mode movers of the DataTexts bars. Each bar's mover spec and its
-- closures are made once per bar ID and reused; a refresh only renames them
-- and registers the present bars again.
local Movers = {}
P.DataTextMovers = Movers
local ID = "dataTexts"
local BAR_LABEL = S.Text("DataTexts bar %d")
local specs = {}

local function Spec(module, index)
    local spec = specs[index]
    if spec then return spec end
    local keys = P.DataTextBarKeys(index)
    local prefix, enabledKey = keys.prefix, keys.enabled
    local pointKey, widthKey, heightKey = prefix .. "Point", prefix .. "Width", prefix .. "Height"
    spec = {
        nameKey = prefix .. "Name", order = 690 + index,
        centerPopup = true,
        getFrame = function() return module.bars[index] and module.bars[index].frame end,
        isEnabled = function() return module.presentIDs[index] and module.config[enabledKey] == true end,
        xKey = prefix .. "X", yKey = prefix .. "Y", pointKey = pointKey,
        point = function() return NS.DataTextPoints[module.config[pointKey]] or "BOTTOM" end,
        historyKeys = { widthKey, heightKey },
        extraControls = {
            { id = "width", label = "Width", kind = "number", min = 180, max = 900, step = 1,
                get = function() return S.Config(ID)[widthKey] end,
                set = function(value) return S.Set(ID, widthKey, value) end },
            { id = "height", label = "Height", kind = "number", min = 18, max = 100, step = 1,
                get = function() return S.Config(ID)[heightKey] end,
                set = function(value) return S.Set(ID, heightKey, value) end },
        },
    }
    specs[index] = spec
    return spec
end

function Movers.Register(module)
    S.UnregisterEditElements(ID)
    for _, i in ipairs(module.barIDs) do
        if module.bars[i] then
            local spec = Spec(module, i)
            spec.label = module.config[spec.nameKey] or BAR_LABEL:format(i)
            S.RegisterOwnedMover(ID, "bar" .. i, spec)
        end
    end
end

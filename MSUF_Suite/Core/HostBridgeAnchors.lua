local _, Suite = ...
local Bridge = Suite.HostBridge
local EMPTY = {}

-- Read host exports at use time: group and optional Suite movers register
-- after login too. Older hosts keep their exports on the namespace itself.
local function Exports()
    local host = Bridge.Namespace()
    return host and (host.PublicGlobals or host) or EMPTY
end

local function Registry()
    local em = Exports().MSUF_EM2
    return em and em.Registry
end

function Bridge.EditAnchorElements()
    local registry = Registry()
    return registry and registry.All and registry.All() or EMPTY
end

function Bridge.WatchEditAnchors(owner, callback)
    local registry = Registry()
    if not registry then return end
    if callback and registry.RegisterChangeListener then registry.RegisterChangeListener(owner, callback)
    elseif not callback and registry.UnregisterChangeListener then registry.UnregisterChangeListener(owner) end
end

function Bridge.EditChoiceControls()
    local api = Exports().MSUF_EditModeAPI
    local capabilities = api and api.GetCapabilities and api.GetCapabilities()
    return capabilities and capabilities.choiceControls == true
end

-- Options can choose an attachment even when every runtime module is off.
-- Keys stay stable when custom CDM bars register or change their names.
function Bridge.EditAnchorChoices(exclude)
    local tr = Suite.Text
    local values = { { value = "", text = tr("Screen") } }
    for key, element in pairs(Bridge.EditAnchorElements()) do
        if key ~= exclude then
            local group = element.externalPublicElement and element.group
            values[#values + 1] = { value = key,
                text = tr("%s: %s"):format(group and tr(group) or "MSUF", tr(element.label or key)) }
        end
    end
    table.sort(values, function(a, b)
        if a.value == "" or b.value == "" then return a.value == "" and b.value ~= "" end
        return a.text < b.text
    end)
    return values
end

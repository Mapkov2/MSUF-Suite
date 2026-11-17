local _, P = ...
local Suite = P.Suite

local function Resolve(page, target)
    local control = target and target.controlId
    if type(control) ~= "string" then return end
    local client, fallback, controlId = control:match("^msufsuite%.changelog|([^|]*)|([^|]*)|(.*)$")
    if not client then return end

    local selectedClient = Suite.Client.isForever and "forever" or "retail"
    local destination = { pageKey = page, sectionId = target.sectionId }
    if client == "" or client == selectedClient then
        destination.controlId = controlId ~= "" and controlId or nil
        destination.settingKey = target.settingKey
        destination.prepareKind = target.prepareKind
        destination.prepareValue = target.prepareValue
    else
        destination.sectionId = fallback
    end
    return page, destination, {}
end

Suite.HostBridge.RegisterSearchTargetResolver(P.M, "MSUF_Suite.Changelog", Resolve)

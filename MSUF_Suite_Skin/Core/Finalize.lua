local _, NS = ...

-- API v1 is intentionally frozen for addons which already use the original
-- imperative facade.  New integrations should negotiate API v2 through
-- MapkoSkin.GetAPI(2, 0), which returns isolated reversible clients.
local LegacyAPI = {
    version = NS.apiVersion,
}

function LegacyAPI.Surface(frame, options)
    return NS.Surface.Attach(frame, options)
end

function LegacyAPI.OwnedButton(button, options)
    return NS.Surface.SkinOwnedButton(button, options)
end

function LegacyAPI.SetActive(frame, active)
    return NS.Surface.SetActive(frame, active)
end

function LegacyAPI.SetNativeStateSync(frame, enabled)
    return NS.Surface.SetNativeStateSync(frame, enabled)
end

function LegacyAPI.GetColor(key)
    return NS.Theme.GetColor(key)
end

function LegacyAPI.GetLook()
    return NS.DB and NS.DB.theme and NS.DB.theme.look or "midnight"
end

function LegacyAPI.GetAppearance(key)
    local theme = NS.DB and NS.DB.theme
    return theme and theme[key] or nil
end

function LegacyAPI.IsEnabled()
    return NS.DB and NS.DB.enabled == true
end

function LegacyAPI.OnThemeChanged(owner, callback)
    NS.Registry.AddListener(owner, callback)
end

function LegacyAPI.RemoveThemeListener(owner)
    NS.Registry.RemoveListener(owner)
end

function LegacyAPI.RegisterAdapter(definition)
    return NS.Adapters.Register(definition)
end

local function GetAPI(first, second, third)
    local major, minimumMinor
    if first == NS then
        major, minimumMinor = second, third
    else
        major, minimumMinor = first, second
    end
    major = tonumber(major) or 1
    minimumMinor = tonumber(minimumMinor) or 0
    if major == 1 and minimumMinor <= 0 then return LegacyAPI end
    if major == NS.PublicAPI.major and minimumMinor <= NS.PublicAPI.minor then
        return NS.PublicAPI.API
    end
    return nil, "unsupported-version"
end

NS.API = LegacyAPI
NS.GetAPI = GetAPI
NS.PublicAPI.Activate()
NS.ready = true

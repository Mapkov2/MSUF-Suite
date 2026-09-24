local _, NS = ...

local localeTables = {}

function NS.RegisterLocale(locale, values)
    if type(locale) ~= "string" or type(values) ~= "table" then
        return
    end
    localeTables[locale] = values
end

function NS.InitializeLocalization()
    local activeLocale = type(GetLocale) == "function" and GetLocale() or "enUS"
    local fallback = localeTables.enUS or {}
    local active = localeTables[activeLocale] or fallback
    local resolved = {}

    setmetatable(resolved, {
        __index = function(_, key)
            local value = active[key]
            if value == nil then
                value = fallback[key]
            end
            return value == nil and key or value
        end,
    })

    NS.L = resolved
    localeTables = nil
end

local _, NS = ...

local Registry = {
    surfaces = setmetatable({}, { __mode = "k" }),
    surfaceTokens = setmetatable({}, { __mode = "k" }),
    tokenConsumers = {},
    listeners = setmetatable({}, { __mode = "k" }),
}
NS.Registry = Registry

local function WeakSet()
    return setmetatable({}, { __mode = "k" })
end

function Registry.GetSurface(target)
    return Registry.surfaces[target]
end

function Registry.RegisterSurface(target, state, tokens)
    Registry.surfaces[target] = state

    -- Reuse the target's membership set. A repeated attach refreshes the full
    -- spec, but must not tear down identical token subscriptions or allocate
    -- a new hash table. False marks old memberships until this pass confirms them.
    local bound = Registry.surfaceTokens[target]
    if not bound then bound = {}; Registry.surfaceTokens[target] = bound end
    for token in pairs(bound) do
        bound[token] = false
    end
    for index = 1, tokens and #tokens or 0 do
        local token = tokens[index]
        if bound[token] == nil then
            local consumers = Registry.tokenConsumers[token]
            if not consumers then
                consumers = WeakSet()
                Registry.tokenConsumers[token] = consumers
            end
            consumers[target] = true
        end
        bound[token] = true
    end
    for token, retained in pairs(bound) do
        if not retained then
            local consumers = Registry.tokenConsumers[token]
            if consumers then consumers[target] = nil end
            bound[token] = nil
        end
    end
end

local function RefreshTarget(target)
    local state = Registry.surfaces[target]
    if state and type(state.refresh) == "function" then
        state.refresh(state)
    end
end

function Registry.RefreshToken(token)
    if NS.IsCombatLocked() then
        return false
    end
    local consumers = Registry.tokenConsumers[token]
    if not consumers then
        return true
    end
    for target in pairs(consumers) do
        RefreshTarget(target)
    end
    return true
end

function Registry.RefreshAll()
    if NS.IsCombatLocked() then
        return false
    end
    for target in pairs(Registry.surfaces) do
        RefreshTarget(target)
    end
    return true
end

function Registry.AddListener(owner, callback)
    if type(owner) == "table" and type(callback) == "function" then
        Registry.listeners[owner] = callback
    end
end

function Registry.RemoveListener(owner)
    Registry.listeners[owner] = nil
end

function Registry.NotifyListeners(domain, key)
    if NS.IsCombatLocked() then
        return false
    end
    for owner, callback in pairs(Registry.listeners) do
        local ok, message = pcall(callback, owner, domain, key)
        if not ok then
            NS.ReportError("theme listener", message)
        end
    end
    return true
end

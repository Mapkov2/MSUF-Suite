local _, NS = ...

-- Guards for touching Blizzard and other foreign objects without protected
-- calls. Each known failure has an explicit check instead of a swallowed error:
--   * Forbidden objects reject every method except IsForbidden.
--   * 12.x getters return secret values instead of raising; a secret must not
--     be compared, used as a table key or in arithmetic (Safety.Public).
--   * Blizzard_Menu's compositor frames report (without raising) when a
--     disallowed member such as CreateTexture is indexed (CanCreateRegions).
--   * Explicitly protected objects stay untouched. Implicitly protected ones
--     (containers of a secure descendant) are decorated only out of combat.
local Safety = {}
NS.Safety = Safety

-- True when the value can be compared, used as a key or in arithmetic.
function Safety.Public(value)
    local isSecret = issecretvalue
    if isSecret == nil or not isSecret(value) then return true end
    return canaccessvalue ~= nil and canaccessvalue(value) == true
end

-- Every helper below returns at least one value, so a result can go straight
-- into type(), tonumber() or a comparison.

-- A field of a widget or table; nil for anything else.
function Safety.Field(target, key)
    if type(target) == "table" then return target[key] end
    return nil
end

function Safety.IsForbidden(target)
    if type(target) ~= "table" or type(target.IsForbidden) ~= "function" then return false end
    local forbidden = target:IsForbidden()
    return not Safety.Public(forbidden) or forbidden == true
end

-- Passes all results through; a call that returned nothing yields nil.
local function AtLeastOne(first, ...)
    return first, ...
end

-- Calls target:name(...) when the object is readable and has that method,
-- and returns its results. nil otherwise. Results may be secret: check them
-- with Safety.Public before comparing.
function Safety.Call(target, name, ...)
    if type(target) ~= "table" or Safety.IsForbidden(target) then return nil end
    local method = target[name]
    if type(method) ~= "function" then return nil end
    return AtLeastOne(method(target, ...))
end

-- Calls target:name(...) for its side effect. True when the call happened.
function Safety.Invoke(target, name, ...)
    if type(target) ~= "table" or Safety.IsForbidden(target) then return false end
    local method = target[name]
    if type(method) ~= "function" then return false end
    method(target, ...)
    return true
end

-- The first result of target:name(...), or nil when it is unavailable or
-- secret. Use for getters whose result is compared or used as a number.
function Safety.Read(target, name, ...)
    local value = Safety.Call(target, name, ...)
    if Safety.Public(value) then return value end
    return nil
end

-- r, g, b, a from a color getter such as GetVertexColor or GetTextColor, or
-- nil unless every channel is a readable number. A missing alpha reads as 1.
function Safety.ReadColor(target, name)
    local r, g, b, a = Safety.Call(target, name)
    local Public = Safety.Public
    if not Public(r) or not Public(g) or not Public(b) or not Public(a) then return nil end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    if type(a) ~= "number" then a = 1 end
    return r, g, b, a
end

-- The compositor's permitted Attach* redirects identify its frames without
-- touching a disallowed member.
function Safety.IsCompositorManaged(target)
    return type(target) == "table"
        and type(target.AttachTexture) == "function"
        and type(target.AttachFontString) == "function"
        and type(target.AttachFrame) == "function"
        and type(target.AttachTemplate) == "function"
end

-- protected, explicit. Unreadable answers count as protected.
local function ReadProtection(target)
    if type(target.IsProtected) ~= "function" then return false, false end
    local protected, explicit = target:IsProtected()
    if not Safety.Public(protected) or not Safety.Public(explicit) then return true, true end
    return protected == true, explicit == true
end

function Safety.GetProtection(target)
    if type(target) ~= "table" then return false, false end
    if Safety.IsForbidden(target) then return true, true end
    return ReadProtection(target)
end

function Safety.CanDecorate(target, allowImplicitProtected)
    if type(target) ~= "table" or Safety.IsForbidden(target) then return false end
    local protected, explicit = ReadProtection(target)
    if explicit then return false end
    if protected then
        return allowImplicitProtected == true
            and (type(InCombatLockdown) ~= "function" or not InCombatLockdown())
    end
    return true
end

-- Controls follow the same rule as cosmetic surfaces.
Safety.CanControl = Safety.CanDecorate

function Safety.CanCreateRegions(target, allowImplicitProtected)
    return Safety.CanDecorate(target, allowImplicitProtected)
        and not Safety.IsCompositorManaged(target)
end

-- Runs code that other addons can supply (theme listeners and adapters from
-- the public API) the way Blizzard's CallbackRegistry runs its callbacks: an
-- error is reported to the error handler (BugSack) and the caller's loop goes
-- on. Nothing is swallowed. Returns the results, or nothing after an error.
-- Offline test harnesses have no securecallfunction and call directly.
Safety.Dispatch = securecallfunction or function(callback, ...)
    return callback(...)
end

return Safety

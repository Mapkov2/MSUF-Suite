local _, NS = ...

-- WoW reports protection as two values: the first also includes frames which
-- merely contain/anchor an explicitly secure descendant; the second identifies
-- the explicitly protected object itself.  Purely cosmetic surfaces may be
-- attached to an implicit ancestor outside combat, but controls and explicitly
-- protected/forbidden objects remain completely untouched.
local Safety = {}
NS.Safety = Safety

local function AccessibleBoolean(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then
        if type(canaccessvalue) ~= "function" or not canaccessvalue(value) then
            return nil
        end
    end
    return value == true
end

-- Pass the operands through pcall; do not allocate a capturing closure per read.
local function IndexMember(object, key)
    return object[key]
end

local function ReadMember(target, key)
    if not target then return nil end
    local ok, value = pcall(IndexMember, target, key)
    return ok and value or nil
end

-- Blizzard_Menu's compositor temporarily replaces the metatable of menu
-- frames. Merely indexing CreateTexture/CreateFontString on those frames emits
-- an assert-safe UI error; the permitted Attach* redirect methods identify the
-- compositor without touching any disallowed member.
function Safety.IsCompositorManaged(target)
    return type(ReadMember(target, "AttachTexture")) == "function"
        and type(ReadMember(target, "AttachFontString")) == "function"
        and type(ReadMember(target, "AttachFrame")) == "function"
        and type(ReadMember(target, "AttachTemplate")) == "function"
end

function Safety.GetProtection(target)
    if not target or type(target.IsProtected) ~= "function" then
        return false, false
    end
    local ok, protected, explicit = pcall(target.IsProtected, target)
    if not ok then
        return true, true
    end
    protected = AccessibleBoolean(protected)
    explicit = AccessibleBoolean(explicit)
    if protected == nil or explicit == nil then
        return true, true
    end
    return protected, explicit
end

function Safety.IsForbidden(target)
    if not target or type(target.IsForbidden) ~= "function" then
        return false
    end
    local ok, forbidden = pcall(target.IsForbidden, target)
    if not ok then
        return true
    end
    forbidden = AccessibleBoolean(forbidden)
    return forbidden == nil or forbidden == true
end

function Safety.CanDecorate(target, allowImplicitProtected)
    if not target or Safety.IsForbidden(target) then
        return false
    end
    local protected, explicit = Safety.GetProtection(target)
    if explicit == true then
        return false
    end
    if protected == true then
        return allowImplicitProtected == true
            and (type(InCombatLockdown) ~= "function" or not InCombatLockdown())
    end
    return true
end

function Safety.CanControl(target, allowImplicitProtected)
    if not target or Safety.IsForbidden(target) then
        return false
    end
    local protected, explicit = Safety.GetProtection(target)
    if explicit == true then
        return false
    end
    if protected == true then
        return allowImplicitProtected == true
            and (type(InCombatLockdown) ~= "function" or not InCombatLockdown())
    end
    return true
end

function Safety.CanCreateRegions(target, allowImplicitProtected)
    return Safety.CanDecorate(target, allowImplicitProtected)
        and not Safety.IsCompositorManaged(target)
end

return Safety

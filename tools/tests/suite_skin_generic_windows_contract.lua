-- GenericWindows pooled-row lifecycle and the static Blizzard catalog contract.
local root = assert(arg[1], "Suite root required")
local skin = root .. "/MSUF_Suite_Skin/"
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function ReadSource(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

-- Catalog: validated once at load, fail-closed and diagnosable.
do
    local NS = {}
    assert(loadfile(skin .. "Adapters/Catalog.lua"))("MSUF_Suite_Skin", NS)
    local catalog = NS.BlizzardCatalog
    Check(catalog.IsGlassContractValid() and catalog.glass.valid
        and #catalog.GetGlassErrors() == 0, "reviewed catalog is valid")

    local byte, concat, hashed = string.byte, table.concat, 0
    string.byte = function(...) hashed = hashed + 1; return byte(...) end
    table.concat = function(...) hashed = hashed + 1; return concat(...) end
    local validated = 0
    for _ = 1, 50 do
        for _, entry in ipairs(catalog.entries) do
            if catalog.IsGlassContractValid() and catalog.ValidateGlassEntry(entry) then
                validated = validated + 1
            end
        end
    end
    string.byte, table.concat = byte, concat
    Check(hashed == 0 and validated == 50 * #catalog.entries,
        "glass validation rehashed the catalog instead of using its load-time result")
    Check(not catalog.ValidateGlassEntry({ id = "foreign", frames = {} })
        and not catalog.ValidateGlassEntry(nil),
        "a foreign entry passed glass validation")

    local source = ReadSource(skin .. "Adapters/Catalog.lua")
    local function LoadModified(pattern, replacement)
        local modified, count = source:gsub(pattern, replacement)
        assert(count == 1, "catalog fixture pattern missing: " .. pattern)
        local copy = {}
        assert(loadstring(modified, "modified catalog"))("MSUF_Suite_Skin", copy)
        return copy.BlizzardCatalog
    end
    local function HasError(target, prefix)
        for _, item in ipairs(target.GetGlassErrors()) do
            if type(item.reason) == "string" and item.reason:sub(1, #prefix) == prefix then
                return true
            end
        end
        return false
    end
    local unreviewed = LoadModified('REVIEWED_CATALOG_FINGERPRINT = "[^"]+"',
        'REVIEWED_CATALOG_FINGERPRINT = "00000000-00000000"')
    Check(not unreviewed.IsGlassContractValid() and not unreviewed.glass.valid
        and not unreviewed.ValidateGlassEntry(unreviewed.entries[1])
        and HasError(unreviewed, "catalog-snapshot-unreviewed:"),
        "an unreviewed catalog snapshot did not fail closed with a listed reason")
    local recounted = LoadModified("REVIEWED_CATALOG_ROOTS = %d+", "REVIEWED_CATALOG_ROOTS = 1")
    Check(not recounted.IsGlassContractValid()
        and not recounted.ValidateGlassEntry(recounted.entries[1])
        and HasError(recounted, "catalog-root-count:"),
        "a changed root inventory did not fail closed with a listed reason")
end

-- GenericWindows with the real Safety, AdapterKit and Catalog and stubbed renderers.
local locked = false
local listener
local counters = { attach = 0, yellow = 0, checkmarks = 0, unregister = 0 }
local registered = {}

local function EventFrame()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript() end
    return frame
end
CreateFrame = EventFrame
ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }

local NS = {
    IsCombatLocked = function() return locked end,
    Client = {
        IsAddOnLoaded = function() return true end,
        HasAddOn = function() return true end,
    },
    CombatGate = {
        RunOrDefer = function(_, callback)
            if locked then return false, "combat" end
            callback()
            return true
        end,
        Cancel = function() end,
    },
    Surface = {
        Attach = function(target, spec)
            counters.attach = counters.attach + 1
            target.surfaceSpec = spec
            return { spec = spec }
        end,
        SetVisible = function(target, visible) target.surfaceVisible = visible end,
    },
    Cosmetics = {
        Fade = function() return true end,
        Restore = function() end,
        RestoreOwner = function() end,
        SuppressVertexAlpha = function() end,
    },
    ControlSkin = { DisableOwner = function() end },
    IconSkin = { DisableOwner = function() end },
    ScrollBarSkin = { DisableOwner = function() end },
    Registry = {
        AddListener = function(_, callback) listener = callback end,
        GetSurface = function() return nil end,
    },
    Theme = { GetColor = function() return 1, 1, 1, 1 end },
    BlizzardYellow = {
        TrackFrame = function() counters.yellow = counters.yellow + 1 end,
        TrackMenuSelection = function() end,
    },
    Checkmarks = {
        TrackFrame = function() counters.checkmarks = counters.checkmarks + 1 end,
        TrackDropdown = function() end,
        IsDropdown = function() return false end,
        GetWindowAction = function() return nil end,
        UntrackOwner = function() end,
    },
}
for _, file in ipairs({ "Core/Safety.lua", "Adapters/Catalog.lua",
    "Adapters/SharedChrome.lua", "Adapters/GenericWindows.lua" }) do
    assert(loadfile(skin .. file))("MSUF_Suite_Skin", NS)
end
local GenericWindows = NS.GenericWindows

local function Frame(name, children)
    local frame = { name = name, children = children or {}, childReads = 0 }
    function frame:GetObjectType() return "Frame" end
    function frame:GetName() return self.name end
    function frame:CreateTexture() return {} end
    function frame:GetChildren()
        self.childReads = self.childReads + 1
        return unpack(self.children)
    end
    function frame:GetNumChildren() return #self.children end
    return frame
end

local rowOne, rowTwo = Frame(nil), Frame(nil)
local scrollBox = Frame("ContractScrollBox")
scrollBox.rows = { rowOne }
function scrollBox:HasView() return true end
function scrollBox:RegisterCallback(event, callback, owner)
    registered[owner] = { event = event, callback = callback }
end
function scrollBox:UnregisterCallback(event, owner)
    counters.unregister = counters.unregister + 1
    registered[owner] = nil
end
function scrollBox:ForEachFrame(callback)
    for _, row in ipairs(self.rows) do callback(row) end
end
function scrollBox:Initialize(row)
    for owner, registration in pairs(registered) do
        registration.callback(owner, row)
    end
end
local window = Frame("ContractWindow", { scrollBox })
local MODE = { role = "shell", allowImplicitProtected = true }

Check(GenericWindows.ApplyFrame(window, "contract", MODE), "generic window did not apply")
Check(next(registered) ~= nil and rowOne.childReads == 1 and rowOne.surfaceSpec
    and rowOne.surfaceSpec.listItem == true,
    "visible pooled row did not receive its full skin pass at registration")

rowOne.childReads, counters.attach, counters.yellow = 0, 0, 0
scrollBox:Initialize(rowOne)
Check(rowOne.childReads == 0 and counters.attach == 0 and counters.yellow == 1
    and counters.checkmarks > 0,
    "recycled row repeated the full frame-skin pass instead of refreshing its state")

scrollBox:Initialize(rowTwo)
Check(rowTwo.childReads == 1 and rowTwo.surfaceSpec == rowOne.surfaceSpec,
    "new pooled row was not skinned once with the shared row spec")

collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 2000 do
    scrollBox:Initialize(rowOne)
    scrollBox:Initialize(rowTwo)
end
local grown = collectgarbage("count") - before
collectgarbage("restart")
Check(grown < 1, ("pooled row refresh allocated %.2f KB for 4000 callbacks"):format(grown))

locked = true
rowOne.childReads, counters.yellow = 0, 0
scrollBox:Initialize(rowOne)
locked = false
Check(rowOne.childReads == 0 and counters.yellow == 0, "pooled rows were painted in combat")

Check(type(listener) == "function", "row registration did not follow theme changes")
listener(GenericWindows, "theme", "look")
scrollBox:Initialize(rowOne)
Check(rowOne.childReads == 1, "theme change did not invalidate the pooled row skin")
rowOne.childReads = 0
listener(GenericWindows, "category", "group")
scrollBox:Initialize(rowOne)
Check(rowOne.childReads == 0, "a category notification re-skinned pooled rows")

Check(GenericWindows.Disable("contract") and counters.unregister == 1 and next(registered) == nil,
    "disable did not unregister the pooled row callback")
rowOne.childReads = 0
Check(GenericWindows.ApplyFrame(window, "contract", MODE) and rowOne.childReads == 1,
    "re-enabling did not re-skin the visible pooled row")

-- The catalog entry list is sorted once; counts reuse it.
Check(GenericWindows.GetCatalogCount() > 0, "reviewed catalog entries are missing")
local sort, sorted = table.sort, 0
table.sort = function(...) sorted = sorted + 1; return sort(...) end
GenericWindows.GetCounts()
GenericWindows.GetCategories()
local catalogCount = GenericWindows.GetCatalogCount()
table.sort = sort
Check(sorted == 0 and catalogCount > 0, "catalog entries were rebuilt for a status query")

print("Suite skin generic windows: " .. checks .. " checks passed")

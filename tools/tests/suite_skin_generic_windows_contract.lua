-- GenericWindows pooled-row lifecycle, the static Blizzard catalog contract and
-- the Blizzard window adapters that build on the shared AdapterKit.
local root = assert(arg[1], "Suite root required")
local skin = root .. "/MSUF_Suite_Skin/"
local checks = 0
local function Check(value, message)
    assert(value, message)
    checks = checks + 1
end

-- Adapter sections collect their failures, so one broken adapter cannot hide
-- the result of the others.
local failures = {}
local function Expect(value, message)
    checks = checks + 1
    if not value then failures[#failures + 1] = message end
end

local function Section(name, body)
    local ok, message = pcall(body)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(message) end
end

local function ReadSource(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

-- Catalog: classified once at load, each entry fail-closed and diagnosable.
-- Catalog.lua holds the data and the review; CatalogGlass.lua classifies it.
-- Whether the catalog still matches its review (fingerprint, entry and root
-- counts) is this test's contract: an unreviewed edit fails here, while the
-- game keeps every entry it can classify.
local function Hash(text, seed, multiplier, modulus)
    local value = seed
    for index = 1, #text do
        value = (value * multiplier + text:byte(index)) % modulus
    end
    return value
end

-- Entry order, ids, categories, addon owners, skip flags and ordered roots.
local function CatalogFingerprint(entries)
    local parts = { tostring(#entries) }
    for index = 1, #entries do
        local entry = entries[index]
        parts[#parts + 1] = table.concat({
            type(entry.id) == "string" and entry.id or "",
            type(entry.category) == "string" and entry.category or "",
            type(entry.addon) == "string" and entry.addon or "",
            entry.skipGeneric == true and "1" or "0",
            type(entry.frames) == "table" and table.concat(entry.frames, "\31") or "",
        }, "\30")
    end
    local text = table.concat(parts, "\29")
    return ("%08x-%08x"):format(
        Hash(text, 216613626, 131, 2147483647),
        Hash(text, 16777619, 137, 2147483629))
end

-- The review problems of one loaded catalog data table.
local function ReviewProblems(data, catalog)
    local problems = {}
    local fingerprint = CatalogFingerprint(data.entries)
    if fingerprint ~= data.reviewedFingerprint then
        problems[#problems + 1] = "catalog-snapshot-unreviewed:" .. fingerprint
    end
    if #data.entries ~= data.reviewedEntries then
        problems[#problems + 1] = "catalog-entry-count:" .. #data.entries
    end
    if #catalog.frames ~= data.reviewedRoots then
        problems[#problems + 1] = "catalog-root-count:" .. #catalog.frames
    end
    return problems
end

local function HasProblem(problems, prefix)
    for _, problem in ipairs(problems) do
        if problem:sub(1, #prefix) == prefix then return true end
    end
    return false
end

do
    -- Core/Client.lua loads before the catalog (TOC); the review is Retail's.
    local NS = { Client = { isForever = false } }
    assert(loadfile(skin .. "Adapters/Catalog.lua"))("MSUF_Suite_Skin", NS)
    local data = NS.BlizzardCatalogData
    local byte, concat, hashed = string.byte, table.concat, 0
    string.byte = function(...) hashed = hashed + 1; return byte(...) end
    assert(loadfile(skin .. "Adapters/CatalogGlass.lua"))("MSUF_Suite_Skin", NS)
    string.byte = byte
    Check(hashed == 0, "loading the catalog hashed it in game")
    local catalog = NS.BlizzardCatalog
    Check(catalog.glass.valid
        and #catalog.GetGlassErrors() == 0, "reviewed catalog is valid")
    local problems = ReviewProblems(data, catalog)
    Check(#problems == 0, "the catalog changed without its review: " .. table.concat(problems, ", "))

    local validated = 0
    hashed = 0
    string.byte = function(...) hashed = hashed + 1; return byte(...) end
    table.concat = function(...) hashed = hashed + 1; return concat(...) end
    for _ = 1, 50 do
        for _, entry in ipairs(catalog.entries) do
            if catalog.ValidateGlassEntry(entry) then
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
    Check(not source:find("function", 1, true) and not source:find("NS.BlizzardCatalog =", 1, true),
        "Catalog.lua holds code again instead of data only")
    local function LoadModified(pattern, replacement)
        local modified, count = source:gsub(pattern, replacement)
        assert(count == 1, "catalog fixture pattern missing: " .. pattern)
        local copy = { Client = NS.Client }
        assert(loadstring(modified, "modified catalog"))("MSUF_Suite_Skin", copy)
        local modifiedData = copy.BlizzardCatalogData
        assert(loadfile(skin .. "Adapters/CatalogGlass.lua"))("MSUF_Suite_Skin", copy)
        return copy.BlizzardCatalog, modifiedData
    end
    -- An unreviewed catalog fails this contract; the game keeps its entries.
    local unreviewed, unreviewedData = LoadModified('local REVIEWED_CATALOG_FINGERPRINT = "[^"]+"',
        'local REVIEWED_CATALOG_FINGERPRINT = "00000000-00000000"')
    Check(HasProblem(ReviewProblems(unreviewedData, unreviewed), "catalog-snapshot-unreviewed:"),
        "the review contract missed an unreviewed catalog snapshot")
    Check(unreviewed.ValidateGlassEntry(unreviewed.entries[1]) and unreviewed.glass.valid,
        "an unreviewed catalog snapshot switched the catalog off in game")
    local recounted, recountedData = LoadModified("local REVIEWED_CATALOG_ROOTS = %d+", "local REVIEWED_CATALOG_ROOTS = 1")
    Check(HasProblem(ReviewProblems(recountedData, recounted), "catalog-root-count:"),
        "the review contract missed a changed root inventory")
    Check(recounted.ValidateGlassEntry(recounted.entries[1]),
        "a changed root inventory switched the catalog off in game")
    -- A root the review cannot classify closes only its own entry.
    local first = catalog.entries[1]
    local broken = LoadModified('id = "' .. first.id .. '",', 'id = "' .. first.id .. '", skipGeneric = true,')
    local brokenErrors = broken.GetGlassErrors()
    Check(not broken.ValidateGlassEntry(broken.entries[1]) and broken.ValidateGlassEntry(broken.entries[2])
        and #brokenErrors > 0 and brokenErrors[1].id == first.id,
        "an unclassifiable entry did not close alone with a listed reason")
end

-- Blizzard's callback isolation (securecallfunction): an error is reported to
-- the error handler and the caller goes on. Reports are counted, so a
-- boundary can be shown to report instead of swallowing.
local reported = {}
securecallfunction = function(callback, ...)
    local results = { pcall(callback, ...) }
    if not results[1] then
        reported[#reported + 1] = tostring(results[2])
        return
    end
    return unpack(results, 2, table.maxn(results))
end

-- hooksecurefunc post-hooks: the original runs first, then the hook.
function hooksecurefunc(target, method, callback)
    if type(target) == "string" then
        target, method, callback = _G, target, method
    end
    local original = target[method]
    assert(type(original) == "function", "hook target missing: " .. tostring(method))
    target[method] = function(...)
        original(...)
        callback(...)
    end
end

-- GenericWindows with the real Safety, AdapterKit and Catalog and stubbed renderers.
local locked = false
local listener
local listeners = {}
local counters = { attach = 0, yellow = 0, checkmarks = 0, unregister = 0 }
local yellowFrames
local registered = {}
local createdFrames = {}

local function NewFrame()
    local frame = { scripts = {}, events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:HookScript(name, callback) self.scripts[name] = callback end
    function frame:SetParent(parent) self.parent = parent end
    function frame:GetParent() return self.parent end
    function frame:ClearAllPoints() end
    function frame:SetAllPoints() end
    function frame:SetFrameStrata() end
    function frame:SetFrameLevel() end
    function frame:EnableMouse() end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    createdFrames[#createdFrames + 1] = frame
    return frame
end
CreateFrame = function() return NewFrame() end
ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
-- Global callbacks the window adapters register; none fires in this contract.
EventRegistry = { RegisterCallback = function() end, UnregisterCallback = function() end }

local NS
NS = {
    -- The skin's locale table (Locales/Localization.lua) is ready before
    -- any of this runs; here every key reads as itself.
    L = setmetatable({}, { __index = function(_, key) return key end }),
    IsCombatLocked = function() return locked end,
    -- The skin's handle on the Suite core (Core/Bootstrap.lua).
    SuiteCore = function() return MSUFSuite end,
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
        -- This gate never keeps a job for later.
        IsPending = function() return false end,
    },
    Surface = {
        Attach = function(target, spec)
            counters.attach = counters.attach + 1
            target.surfaceSpec = spec
            return { spec = spec, edge = { SetDrawLayer = function() end } }
        end,
        -- The update-hook attach (Surface.Ensure) counts as an attach here.
        Ensure = function(target, spec) return NS.Surface.Attach(target, spec) end,
        SetVisible = function(target, visible) target.surfaceVisible = visible end,
        SetActive = function(target, active) target.surfaceActive = active end,
    },
    Cosmetics = {
        Fade = function() return true end,
        FadeNineSlice = function() end,
        FadeDialogHeader = function() end,
        Restore = function() end,
        RestoreOwner = function() end,
        SuppressVertexAlpha = function() end,
        GetOwner = function() return nil end,
    },
    ControlSkin = {
        DisableOwner = function() end,
        RefreshOwner = function() end,
        Refresh = function() return true end,
        IsApplied = function() return false end,
    },
    IconSkin = { DisableOwner = function() end, GetOwner = function() return nil end },
    ScrollBarSkin = { DisableOwner = function() end },
    Registry = {
        AddListener = function(owner, callback)
            listeners[owner] = callback
            if owner == NS.GenericWindows then listener = callback end
        end,
        RemoveListener = function(owner) listeners[owner] = nil end,
        GetSurface = function() return nil end,
        -- Coalesced repaints run at once here.
        QueueJob = function(job) job() end,
    },
    Theme = { GetColor = function() return 1, 1, 1, 1 end },
    BlizzardYellow = {
        TrackFrame = function(frame)
            counters.yellow = counters.yellow + 1
            if yellowFrames then yellowFrames[frame] = true end
        end,
        TrackFrames = function(frames, count)
            for index = 1, count do
                counters.yellow = counters.yellow + 1
                if yellowFrames then yellowFrames[frames[index]] = true end
            end
        end,
        TrackMenuSelection = function() end,
    },
    Checkmarks = {
        TrackFrame = function() counters.checkmarks = counters.checkmarks + 1 end,
        TrackDropdown = function() end,
        IsDropdown = function() return false end,
        GetWindowAction = function() return nil end,
        UntrackOwner = function() end,
        TrackTexture = function() return true end,
        UntrackTexture = function() end,
        TrackButton = function() return true end,
    },
    WindowActionSkin = {
        Apply = function() return nil end,
        SyncNativeVisual = function() return nil end,
        DisableOwner = function() end,
    },
    WindowControls = { TrackFocus = function() end, Attach = function() end, DisableOwner = function() end },
    -- Adapters that load after the generic windows; none owns a frame here.
    CharacterDetails = { IsHost = function() return false end },
    CharacterStats = { IsHost = function() return false end },
    EQoLCharacter = { IsHost = function() return false end },
    MacroWindow = { Apply = function() end, Disable = function() end },
    QuestText = { Activate = function() end, Deactivate = function() end },
    Adapters = { Refresh = function() return true end },
}
-- The shared value helpers and the Retail Micro Bar line length of
-- Defaults.lua, which loads before every adapter.
do
    local defaults = { Client = NS.Client }
    assert(loadfile(skin .. "Core/Defaults.lua"))("MSUF_Suite_Skin", defaults)
    assert(loadfile(skin .. "Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", defaults)
    NS.Clamp, NS.IsListed = defaults.Clamp, defaults.IsListed
    NS.MicroMenuMaxButtonsPerLine = defaults.MicroMenuMaxButtonsPerLine
end
local function ColdSource(file)
    local baseline = os.getenv("SUITE_SKIN_COLD_BASELINE")
    local path = baseline and baseline .. "/MSUF_Suite_Skin/" .. file
    local found = path and io.open(path, "rb")
    if found then found:close(); return path end
    return skin .. file
end
-- Safety reads issecretvalue at load; "generic traversal secrets" assigns it later.
dofile(root .. "/tools/tests/suite_test_support.lua").SecretValues()
for _, file in ipairs({ "Core/Safety.lua", "Core/SuiteOwnership.lua",
    "Adapters/Catalog.lua", "Adapters/CatalogGlass.lua",
    "Adapters/AdapterKit.lua", "Adapters/SharedChrome.lua",
    "Adapters/GenericWindows.lua", "Adapters/GenericWindowsNodes.lua", "Adapters/GenericWindowsFrames.lua",
    "Adapters/GenericWindowsCatalog.lua" }) do
    assert(loadfile(ColdSource(file)))("MSUF_Suite_Skin", NS)
end
local GenericWindows = NS.GenericWindows
local Kit = NS.AdapterKit
local genericLoadFrame = createdFrames[#createdFrames]

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

local rowChild = Frame(nil)
local rowOne, rowTwo = Frame(nil, { rowChild }), Frame(nil)
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

counters.attach, counters.yellow = 0, 0
yellowFrames = {}
scrollBox:Initialize(rowOne)
Check(counters.attach == 0 and counters.checkmarks > 0 and yellowFrames[rowOne],
    "recycled row repeated the full frame-skin pass instead of refreshing its state")
Expect(yellowFrames[rowChild] == true,
    "a recycled row refreshed Blizzard gold only on its own regions, not in its child frames")
yellowFrames = nil

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
rowOne.childReads, counters.yellow = 0, 0
scrollBox:Initialize(rowOne)
Check(rowOne.childReads == 0 and counters.yellow > 0,
    "a recycled row enumerated its children again instead of revisiting its recorded subtree")

-- The visible row pays one effective-visibility read to suppress all of its
-- cosmetic work while hidden. Budget this accepted gate separately.
do
    local instructions, visibilityReads = 0, 0
    function scrollBox:IsVisible() visibilityReads = visibilityReads + 1; return true end
    local function CountInstruction() instructions = instructions + 1 end
    debug.sethook(CountInstruction, "", 1)
    scrollBox:Initialize(rowOne)
    debug.sethook()
    print(("Visible row budget: %d VM; %d visibility reads"):format(instructions, visibilityReads))
    -- Accepted: the public-row guard adds 20 VM instructions (175 -> 195).
    -- One native visibility read; hidden rows perform no cosmetic pass.
    Check(instructions <= 210 and visibilityReads <= 1, "visible row exceeded its visibility gate budget")
    scrollBox.IsVisible = nil
end

locked = true
rowOne.childReads, counters.yellow = 0, 0
scrollBox:Initialize(rowOne)
locked = false
Check(rowOne.childReads == 0 and counters.yellow > 0, "safe pooled native text was not repainted in combat")

Check(type(listener) == "function", "row registration did not follow theme changes")
counters.attach = 0
listener(GenericWindows, "theme", "look")
scrollBox:Initialize(rowOne)
Check(counters.attach == 1, "theme change did not invalidate the pooled row skin")
counters.attach = 0
listener(GenericWindows, "category", "group")
scrollBox:Initialize(rowOne)
Check(counters.attach == 0, "a category notification re-skinned pooled rows")

Check(GenericWindows.Disable("contract") and counters.unregister == 1 and next(registered) == nil,
    "disable did not unregister the pooled row callback")
rowOne.childReads = 0
Check(GenericWindows.ApplyFrame(window, "contract", MODE) and rowOne.childReads == 1,
    "re-enabling did not re-skin the visible pooled row")

-- The catalog entry list is sorted once; counts reuse it.
Check(GenericWindows.GetCounts().total > 0, "reviewed catalog entries are missing")
local sort, sorted = table.sort, 0
table.sort = function(...) sorted = sorted + 1; return sort(...) end
GenericWindows.GetCounts()
GenericWindows.GetCategories()
local catalogCount = GenericWindows.GetCounts().total
table.sort = sort
Check(sorted == 0 and catalogCount > 0, "catalog entries were rebuilt for a status query")

-- Surfaces a running Suite module replaces stay with that module
-- (Core/SuiteOwnership.lua); free ones keep their skin.
local suiteOwned = {}
MSUFSuite = { Suite = { OwnsBlizzardSurface = function(surface) return suiteOwned[surface] == true end } }
-- The chat adapter keeps its colour ledger in the Suite core's skin boundary.
dofile(root .. "/tools/tests/suite_test_support.lua").SuiteSkinBoundary(root, MSUFSuite)
assert(loadfile(skin .. "Core/SuiteOwnership.lua"))("MSUF_Suite_Skin", NS)

local faded, fade = {}, NS.Cosmetics.Fade
NS.Cosmetics.Fade = function(region, ...)
    faded[region] = true
    return fade(region, ...)
end
local freeBag = Frame("ContainerFrameCombinedBags")
freeBag.Bg = {}
ContainerFrameCombinedBags = freeBag
Check(GenericWindows.ApplyFrame(freeBag, "bags", MODE) and freeBag.surfaceSpec and faded[freeBag.Bg],
    "a bag window without the Bags module lost its skin")
suiteOwned.bagWindows = true
local ownedBag = Frame("ContainerFrameCombinedBags")
ownedBag.Bg = {}
ContainerFrameCombinedBags = ownedBag
Check(GenericWindows.ApplyFrame(ownedBag, "bags", MODE) and ownedBag.surfaceSpec == nil
    and not faded[ownedBag.Bg], "the skin painted a bag shell the Bags module owns")
NS.Cosmetics.Fade = fade
Check(MODE.rootSurface == nil and MODE.preserveRootArt == nil, "the owned bag mode changed the caller's mode")
local otherWindow = Frame("ContractOtherWindow")
Check(GenericWindows.ApplyFrame(otherWindow, "bags", MODE) and otherWindow.surfaceSpec,
    "the bag shell rule reached another window")
ContainerFrameCombinedBags = nil
suiteOwned.bagWindows = nil

local bagBarEntry
for _, entry in ipairs(NS.BlizzardCatalog.entries) do
    if entry.id == "hud-bag-bar" then bagBarEntry = entry end
end
suiteOwned.bagBar = true
local entryApplied, entryState = GenericWindows.ApplyEntry(bagBarEntry, "entries")
Check(not entryApplied and entryState == "disabled" and GenericWindows.GetStatus("hud-bag-bar") == "disabled",
    "the skin styled the bag bar DataTexts hides")
suiteOwned.bagBar = false
entryApplied, entryState = GenericWindows.ApplyEntry(bagBarEntry, "entries")
Check(entryState ~= "disabled", "the skin left a visible bag bar unstyled")

-- The Forever roots must travel through the real catalog's LoD dispatcher,
-- native X skinning and the normal shared geometry attachment.
do
    local forever = {}
    for key, value in pairs(NS) do forever[key] = value end
    local loaded, attached, painted = {}, {}, {}
    forever.Client = { isForever = true,
        IsAddOnLoaded = function(addon) return loaded[addon] == true end,
        HasAddOn = function() return true end }
    forever.WindowControls = { TrackFocus = function() end,
        Attach = function(frame, owner) attached[frame] = owner end,
        DisableOwner = function() end,
    }
    forever.ControlSkin = {}
    for key, value in pairs(NS.ControlSkin) do forever.ControlSkin[key] = value end
    forever.ControlSkin.ApplyButton = function(button) painted[button] = true; return {} end
    forever.Checkmarks = {}
    for key, value in pairs(NS.Checkmarks) do forever.Checkmarks[key] = value end
    forever.Checkmarks.GetWindowAction = function(button) return button.nativeClose and "close" or nil end
    assert(loadfile(arg[2] or skin .. "Adapters/Catalog.lua"))("MSUF_Suite_Skin", forever)
    local data = forever.BlizzardCatalogData
    for _, file in ipairs({ "Adapters/CatalogGlass.lua", "Adapters/GenericWindows.lua",
        "Adapters/GenericWindowsNodes.lua", "Adapters/GenericWindowsFrames.lua", "Adapters/GenericWindowsCatalog.lua" }) do
        assert(loadfile(skin .. file))("MSUF_Suite_Skin", forever)
    end
    Check(#ReviewProblems(data, forever.BlizzardCatalog) == 0 and forever.BlizzardCatalog.glass.valid,
        "Forever catalog fingerprint, root count or classifications are stale")
    local loader = createdFrames[#createdFrames]
    local legacy = forever.BlizzardCatalog.FindByFrame("LegacySystemFrame")
    Check(legacy.skipGeneric == true and data.dedicatedOwners[legacy.id] == "ForeverLegacyTree",
        "the Legacy window must stay outside the generic CheckButton traversal")
    for _, name in ipairs({ "PetStableFrame" }) do
        local entry = forever.BlizzardCatalog.FindByFrame(name)
        Check(entry ~= nil, name .. " has no Forever catalog entry")
        local panel = Frame(name)
        panel.scripts = {}
        function panel:HookScript(script, callback) self.scripts[script] = callback end
        panel.CloseButton = Frame(name .. "CloseButton")
        function panel.CloseButton:GetObjectType() return "Button" end
        panel.CloseButton.nativeClose, panel.CloseButton.shown = true, false
        local nativeClick = function() end
        panel.CloseButton.OnClick = nativeClick
        local prior = _G[name]
        _G[name] = panel
        local owner = "contract:forever:" .. name
        local applied, status = forever.GenericWindows.ApplyEntry(entry, owner)
        Check(not applied and status == "waiting" and loader.events.ADDON_LOADED
            and not attached[panel] and not painted[panel.CloseButton], name .. " skipped its native LoD gate")
        loaded[entry.addon] = true
        loader.scripts.OnEvent(loader, "ADDON_LOADED", entry.addon)
        Check(attached[panel] == owner and painted[panel.CloseButton] and panel.surfaceSpec,
            name .. " did not receive its native X skin and shared controls after addon load")
        Check(not loader.events.ADDON_LOADED and not panel.CloseButton.shown
            and panel.CloseButton.OnClick == nativeClick, name .. " changed native close behavior or retained a load poll")
        forever.GenericWindows.Disable(owner)
        _G[name] = prior
    end
end

-- Cooldown viewers: Loss of Control keeps its skin, the viewers wait for
-- Blizzard only while the Suite cooldown manager is off.
local waits = 0
EventUtil = { ContinueOnAddOnLoaded = function() waits = waits + 1 end }
NS.Client.IsAddOnLoaded = function() return false end
assert(loadfile(skin .. "Adapters/SemanticHUD.lua"))("MSUF_Suite_Skin", NS)
suiteOwned.cooldownViewers = true
local hudApplied, hudState = NS.SemanticHUD.Apply("ownedHud")
Check(hudApplied and hudState == "applied" and waits == 0,
    "the skin waited for cooldown viewers the Suite cooldown manager owns")
NS.SemanticHUD.Disable("ownedHud")
suiteOwned.cooldownViewers = false
hudApplied, hudState = NS.SemanticHUD.Apply("freeHud")
Check(hudApplied and hudState == "waiting" and waits == 1,
    "the skin stopped styling cooldown viewers the Suite left to Blizzard")
NS.SemanticHUD.Disable("freeHud")
NS.Client.IsAddOnLoaded = function() return true end
EventUtil = nil

-------------------------------------------------------------------------------
-- Adapter sections
-------------------------------------------------------------------------------

local function Load(file, namespace)
    if file == "EncounterJournal.lua" then
        assert(loadfile(skin .. "Adapters/EncounterJournalPanels.lua"))("MSUF_Suite_Skin", namespace or NS)
    end
    local override = file == "PlayerSpells.lua" and os.getenv("SUITE_PLAYER_SPELLS_SOURCE")
    assert(loadfile(override or ColdSource("Adapters/" .. file)))("MSUF_Suite_Skin", namespace or NS)
end

-- A text region whose color reads back the way the client stores it.
local function Text(r, g, b, a)
    local text = { color = { r, g, b, a or 1 } }
    function text:GetObjectType() return "FontString" end
    function text:GetTextColor() return unpack(self.color) end
    function text:SetTextColor(red, green, blue, alpha)
        self.color = { red, green, blue, alpha or 1 }
    end
    return text
end

local function Near(left, right)
    return math.abs(left - right) <= 1 / 255
end

-- Counts GenericWindows passes per frame while body runs.
local function CountingApplyFrame()
    local calls = {}
    local original = GenericWindows.ApplyFrame
    GenericWindows.ApplyFrame = function(frame, ...)
        calls[frame] = (calls[frame] or 0) + 1
        return original(frame, ...)
    end
    return calls, function() GenericWindows.ApplyFrame = original end
end

-- A ScrollBox that reports rows to its registrations like CallbackRegistry.
local function RowBox()
    local box = { callbacks = {}, rows = {} }
    function box:RegisterCallback(_, callback, owner) self.callbacks[owner] = callback end
    function box:UnregisterCallback(_, owner) self.callbacks[owner] = nil end
    function box:ForEachFrame(callback)
        for _, row in ipairs(self.rows) do callback(row) end
    end
    function box:Initialize(row)
        for owner, callback in pairs(self.callbacks) do callback(owner, row) end
    end
    return box
end

Section("adapter kit colors", function()
    -- Colors read back with 8-bit precision. Neither a refresh nor the restore
    -- may mistake our installed color for the native one.
    local function Quantize(value) return math.floor(value * 255 + 0.5) / 255 end
    local font = Text(0.1, 0.2, 0.3, 1)
    function font:SetTextColor(r, g, b, a)
        self.color = { Quantize(r), Quantize(g), Quantize(b), Quantize(a or 1) }
    end
    local getColor = NS.Theme.GetColor
    NS.Theme.GetColor = function() return 0.8123, 0.4567, 0.1234, 1 end
    local colors = Kit.NewTextColors()
    Kit.SetTextColor(colors, font, "text")
    Kit.SetTextColor(colors, font, "text", true)
    Kit.RestoreTextColors(colors)
    NS.Theme.GetColor = getColor
    Expect(Near(font.color[1], 0.1) and Near(font.color[2], 0.2) and Near(font.color[3], 0.3),
        "restoring text colors compared floats exactly and kept the skin color")
end)

Section("selection indicator combat gate", function()
    local created = #createdFrames
    locked = true
    local shown = Kit.SelectionIndicator({ owner = "indicator", surfaces = Kit.WeakSet() }, {},
        Frame("ContractTab"), Frame("ContractPanel"), true)
    locked = false
    Expect(shown == false and #createdFrames == created,
        "a selection indicator was created or moved in combat")
end)

Section("native character stats stay outside generic skin registration", function()
    local stats = Frame("CharacterStatsPaneScrollBox")
    local list = Frame("CharacterStatsPaneScrollBoxScrollBox")
    stats.children = { list }
    function list:HasView() return true end
    function list:RegisterCallback() error("generic skin registered on the native stats list") end
    function list:ForEachFrame() end
    local character = Frame("CharacterFrame", { stats })
    local popup = Frame("GearManagerPopupFrame")
    _G.CharacterFrame, _G.GearManagerPopupFrame = character, popup
    local motion = {}
    GenericWindows.SetMenuMotionProvider(function(frame) motion[frame] = true end, function() end)
    Expect(GenericWindows.ApplyAll("native-character"), "native character catalog pass failed")
    Expect(character.childReads == 0 and stats.childReads == 0 and not motion[character],
        "generic skin traversed or registered menu motion on the native character window")
    Expect(GenericWindows.GetStatus("character") == "applied" and popup.surfaceSpec and motion[popup],
        "native character exclusion also skipped the separate gear manager popup")
    GenericWindows.Disable("native-character")
    GenericWindows.SetMenuMotionProvider(function() end, function() end)
    _G.CharacterFrame, _G.GearManagerPopupFrame = nil, nil
end)

Section("catalog entries are isolated", function()
    local raising = Frame("GearManagerPopupFrame")
    function raising:GetChildren() error("contract: GearManagerPopupFrame raised") end
    local bank = Frame("BankFrame")
    _G.GearManagerPopupFrame, _G.BankFrame = raising, bank
    local before = #reported
    local ok = pcall(GenericWindows.ApplyAll, "isolation")
    Expect(ok and bank.surfaceSpec ~= nil,
        "a raising catalog entry stopped the entries after it")
    Expect(GenericWindows.GetStatus("character") == "error" and #reported > before,
        "a raising catalog entry was not reported as an error")
    GenericWindows.Disable("isolation")

    -- Entries waiting for the same load-on-demand addon are isolated too.
    local laterBank = Frame("BankFrame")
    _G.BankFrame = laterBank
    local addonLoaded = false
    NS.Client.IsAddOnLoaded = function(addon)
        return addon ~= "Blizzard_UIPanels_Game" or addonLoaded
    end
    GenericWindows.ScheduleLoadOnDemand("bucket")
    addonLoaded = true
    ok = pcall(genericLoadFrame.scripts.OnEvent, genericLoadFrame, "ADDON_LOADED", "Blizzard_UIPanels_Game")
    NS.Client.IsAddOnLoaded = function() return true end
    Expect(ok and laterBank.surfaceSpec ~= nil,
        "a raising entry of a loaded addon stopped the other waiting entries")
    GenericWindows.Disable("bucket")
    _G.GearManagerPopupFrame, _G.BankFrame = nil, nil
end)

Section("shared chrome", function()
    local SharedChrome = NS.SharedChrome
    local calls, restore = CountingApplyFrame()
    _G.TalkingHeadFrame = setmetatable({}, {
        __index = function() error("contract: talking head raised") end,
    })
    local raid = Frame("RaidParentFrame")
    _G.RaidParentFrame = raid
    local entries = { Frame(nil), Frame(nil) }
    local queue = Frame("QueueStatusFrame")
    function queue:IsShown() return true end
    queue.statusEntriesPool = {
        EnumerateActive = function()
            local index = 0
            return function()
                index = index + 1
                return entries[index]
            end
        end,
    }
    _G.QueueStatusFrame = queue
    local choice = Frame("PlayerChoiceFrame")
    function choice:SetupOptions() end
    function choice:OnPageChanged() end
    _G.PlayerChoiceFrame = choice

    local before = #reported
    local ok = pcall(SharedChrome.Apply, "chrome")
    Expect(ok and calls[raid] == 1 and #reported == before + 1,
        "a raising chrome kind stopped the other kinds or was not reported")
    Expect(calls[queue] == 1 and calls[entries[1]] == 1 and calls[entries[2]] == 1,
        "the queue status root and entries were not skinned")

    for frame in pairs(calls) do calls[frame] = nil end
    SharedChrome:OnQueueStatusUpdated()
    SharedChrome:OnQueueStatusUpdated()
    Expect(calls[queue] == nil and calls[entries[1]] == nil,
        "queue updates re-skinned the status root and its known entries")
    entries[3] = Frame(nil)
    SharedChrome:OnQueueStatusUpdated()
    Expect(calls[entries[3]] == 1 and calls[entries[1]] == nil and calls[queue] == nil,
        "a new queue entry was not skinned alone")
    for owner, callback in pairs(listeners) do callback(owner, "theme", "look") end
    SharedChrome:OnQueueStatusUpdated()
    Expect(calls[queue] == 1 and calls[entries[1]] == 1,
        "a look change did not give the queue status one fresh pass")

    for frame in pairs(calls) do calls[frame] = nil end
    choice:SetupOptions()
    Expect(calls[choice] == 1, "rebuilt player choice options were not skinned")

    SharedChrome.Disable("chrome")
    restore()
    _G.TalkingHeadFrame, _G.RaidParentFrame, _G.QueueStatusFrame, _G.PlayerChoiceFrame = nil, nil, nil, nil
end)

Section("deep windows", function()
    -- A private namespace: the post-hooks installed here stay local.
    local deepNS = setmetatable({}, { __index = NS })
    local motionWatches, motionPlays = {}, 0
    deepNS.ContentMotion = {
        Watch = function(frame, owner)
            if not frame or frame == deepNS.protectedBook then return false end
            motionWatches[frame] = owner
            return true
        end,
        Play = function(frame, owner, skill)
            Check(locked and motionWatches[frame] == owner and skill == 171,
                "the combat profession switch bypassed the prepared page")
            motionPlays = motionPlays + 1
        end,
    }
    Load("DeepWindows.lua", deepNS)
    Load("DeepWindowsProfessions.lua", deepNS)
    local calls, restore = CountingApplyFrame()

    -- Blizzard_ProfessionsFrame.lua: ProfessionsMixin:Refresh refreshes every
    -- page (self.Pages) before its own title and tabs.
    local professionsMixin = {}
    function professionsMixin:Refresh()
        for _, page in ipairs(self.Pages) do page:Refresh(self.professionInfo) end
    end
    local craftingMixin = {}
    function craftingMixin:Init() end
    function craftingMixin:Refresh() end
    function craftingMixin:SchematicPostInit() end
    _G.ProfessionsMixin, _G.ProfessionsCraftingPageMixin = professionsMixin, craftingMixin
    -- XML frames carry their own copy of the mixin. The window holds about
    -- 1,200 nodes, most of them in its pages.
    local function Leaves(parent, count)
        for index = 1, count do
            local leaf = Frame(nil)
            leaf.parent = parent
            function leaf:GetParent() return self.parent end
            parent.children[index] = leaf
        end
    end
    local professions = Frame("ProfessionsFrame")
    professions.scripts = {}
    function professions:HookScript(script, callback) self.scripts[script] = callback end
    professions.Refresh = professionsMixin.Refresh
    local crafting = Frame(nil)
    for key, method in pairs(craftingMixin) do crafting[key] = method end
    function crafting:GetParent() return professions end
    professions.CraftingPage = crafting
    local schematic = Frame(nil)
    function schematic:GetParent() return crafting end
    crafting.SchematicForm = schematic
    local spec = Frame(nil)
    function spec:Refresh() end
    function spec:GetParent() return professions end
    professions.SpecPage = spec
    professions.Pages = { crafting, spec }
    local chrome = Frame(nil)
    function chrome:GetParent() return professions end
    Leaves(crafting, 600)
    crafting.children[#crafting.children + 1] = schematic
    Leaves(schematic, 100)
    Leaves(spec, 300)
    Leaves(chrome, 200)
    professions.children = { crafting, spec, chrome }
    _G.ProfessionsFrame = professions

    local traitMixin = {}
    function traitMixin:ApplyLayout() end
    _G.GenericTraitFrameMixin = traitMixin
    local traits = Frame("GenericTraitFrame")
    traits.scripts = {}
    function traits:HookScript(script, callback) self.scripts[script] = callback end
    traits.ApplyLayout = traitMixin.ApplyLayout
    _G.GenericTraitFrame = traits

    local queued = {}
    C_Timer = { After = function(_, callback) queued[#queued + 1] = callback end }
    local function NextFrame()
        while #queued > 0 do table.remove(queued, 1)() end
    end
    local descendants = {}
    local applyDescendant = GenericWindows.ApplyDescendant
    GenericWindows.ApplyDescendant = function(frame, ...)
        descendants[frame] = (descendants[frame] or 0) + 1
        return applyDescendant(frame, ...)
    end
    local function Reset()
        for frame in pairs(calls) do calls[frame] = nil end
        for frame in pairs(descendants) do descendants[frame] = nil end
    end

    local forever = NS.Client.isForever
    NS.Client.isForever = true
    function professions:RightTabSelected() end
    local book, rank = Frame(nil), Frame(nil)
    deepNS.protectedBook = book
    -- Forever's rank bar (ProfessionsRankBarTemplate): Background and Border
    -- are the ornate art; Fill and the Rank lane (y -3) carry the value.
    rank.Rank, rank.Background, rank.Border, rank.Fill = Frame(nil), {}, {}, {}
    function rank:GetFrameLevel() return 7 end
    local unlearn = Frame(nil)
    book.ProfessionsContentFrame = { PrimaryProfession1 = { StatusBar = rank, UnlearnButton = unlearn } }
    professions.BookPage = book
    -- Forever side tabs (LargeSideTabButtonTemplate): overview + one per profession.
    local function SideTab()
        local tab = Frame(nil)
        tab.Icon, tab.Background, tab.TabGlow = {}, {}, {}
        tab.SelectedTexture = { shown = false, IsShown = function(self) return self.shown end }
        function tab:SetChecked(checked) self.SelectedTexture.shown = checked end
        return tab
    end
    local overviewTab, miningTab = SideTab(), SideTab()
    professions.ProfessionsOverviewTab, professions.rightProfessionTabs = overviewTab, { miningTab }
    local rankFaded, rankButtons, rankTrack = {}, {}, nil
    local fadeBefore, applyButtonBefore, createBefore = NS.Cosmetics.Fade, NS.ControlSkin.ApplyButton, CreateFrame
    NS.Cosmetics.Fade = function(region, ...) rankFaded[region] = true; return fadeBefore(region, ...) end
    NS.ControlSkin.ApplyButton = function(button, owner, spec) rankButtons[button] = spec; return {} end
    -- The portrait (profession icon) and the anonymous ornate recipe frame.
    local portrait = {}
    professions.PortraitContainer = { portrait = portrait, GetFrameLevel = function() return 9 end }
    local insideFrame = { GetAtlas = function() return "common-insideframe" end }
    function schematic:GetRegions() return insideFrame end
    local ownedFrames = {}
    CreateFrame = function(frameType, name, parent)
        Check(parent == nil, "an owned frame was created with a parent (Forever SmartNavigation hook)")
        local frame = createBefore(frameType, name, parent)
        function frame:SetPoint(point, relative) self.points = (self.points or 0) + 1; self.lane = relative end
        function frame:SetFrameLevel(level) self.level = level end
        function frame:CreateTexture()
            local texture = {}
            function texture:SetTexture(path) self.path = path end
            function texture:SetDesaturated(value) self.desaturated = value end
            function texture:SetVertexColor() self.tinted = true end
            function texture:ClearAllPoints() end
            function texture:SetPoint(_, relative) self.anchor = self.anchor or relative end
            self.ring = texture
            return texture
        end
        ownedFrames[#ownedFrames + 1] = frame
        return frame
    end
    deepNS.DeepWindows.Apply("deep")
    -- First the rank track (book pass), then the portrait bezel.
    rankTrack = ownedFrames[1]
    local bezel = ownedFrames[2]
    Expect(bezel and bezel.parent == professions.PortraitContainer and bezel.level == 17
        and bezel.ring.desaturated and bezel.ring.tinted and bezel.ring.anchor == portrait,
        "the profession portrait missed its owned bezel")
    Expect(rankFaded[insideFrame], "Forever's ornate recipe frame (common-insideframe) stayed visible")
    NS.Cosmetics.Fade, NS.ControlSkin.ApplyButton, CreateFrame = fadeBefore, applyButtonBefore, createBefore
    Expect(rankTrack and rankTrack.parent == rank and rankTrack.lane == rank.Rank and rankTrack.points == 2
        and rankTrack.level == 6 and rankTrack.surfaceSpec and rankTrack.surfaceSpec.role == "status",
        "the Forever rank bar track is not an owned status surface on the Rank lane below the bar")
    Expect(rankFaded[rank.Background] and rankFaded[rank.Border] and not rankFaded[rank.Fill],
        "the rank bar faded its value fill or kept its ornate frame")
    Expect(rankButtons[unlearn] and rankButtons[unlearn].role == "button" and not rankFaded[unlearn],
        "the unlearn button stayed unskinned or lost its icon")
    for _, tab in ipairs({ overviewTab, miningTab }) do
        Expect(tab.surfaceSpec and tab.surfaceSpec.role == "navigation" and tab.surfaceSpec.selectionEdge
            and tab.surfaceSpec.radius == 6, "a Forever profession side tab missed the Legacy tab tile")
        Expect(rankFaded[tab.Background] and rankFaded[tab.SelectedTexture] and not rankFaded[tab.Icon],
            "a profession side tab kept its ornate frame or lost its icon")
    end
    -- Blizzard's SetChecked drives the tile's selection.
    local getSurface = NS.Registry.GetSurface
    NS.Registry.GetSurface = function(target)
        return target.surfaceSpec and { spec = target.surfaceSpec, visible = true } or nil
    end
    miningTab:SetChecked(true)
    overviewTab:SetChecked(false)
    NS.Registry.GetSurface = getSurface
    Expect(miningTab.surfaceActive == true and overviewTab.surfaceActive == false,
        "the profession side tab selection did not follow Blizzard's SetChecked")
    Expect(motionWatches[crafting] == "deep" and motionWatches[spec] == "deep" and motionWatches[rank] == "deep"
        and not motionWatches[book], "profession animations missed exact pages or targeted the protected book")
    locked = true
    professions:RightTabSelected({ skillLine = 164 })
    professions:RightTabSelected({ skillLine = 164 })
    professions:RightTabSelected({ skillLine = 171 })
    professions:RightTabSelected({ skillLine = 171 })
    professions:RightTabSelected({})
    Expect(motionPlays == 1, "the same-page combat animation missed a skill switch or replayed a refresh")
    locked, NS.Client.isForever = false, forever
    NextFrame()
    Reset()
    locked = true
    crafting:SchematicPostInit()
    Expect(calls[professions] == nil and descendants[schematic] == 1,
        "a safe combat recipe change did not paint its schematic immediately")
    locked = false
    NextFrame()
    Reset()
    function professions:IsProtected() return true, false end
    locked = true
    deepNS.DeepWindows:OnProfessionsTabSet(professions)
    crafting:SchematicPostInit()
    Expect(calls[professions] == 1 and descendants[schematic] == 1,
        "protected profession shell suppressed the safe schematic")
    professions.IsProtected = nil
    locked = false
    NextFrame()
    Reset()
    -- A recipe click (SchematicPostInit) re-skins the schematic at once, in
    -- Blizzard's call: no frame shows native art, and no full window pass.
    crafting:SchematicPostInit()
    Expect(calls[professions] == nil and descendants[schematic] == 1,
        "a recipe click ran a full profession pass or left its schematic unskinned until the next frame")
    crafting:SchematicPostInit()
    Expect(descendants[schematic] == 1, "one frame skinned the same schematic twice")
    NextFrame()
    Reset()
    crafting:Init()
    Expect(calls[professions] == nil and descendants[crafting] == 1,
        "a crafting page signal did not re-skin just that page")
    NextFrame()
    Reset()
    -- ProfessionsFrame:Refresh runs on every trade skill list update, so on
    -- every craft: its pages pass over their own subtrees, and the window,
    -- applied in this skin generation, takes no second full pass.
    professions:Refresh()
    Expect(calls[professions] == nil and descendants[crafting] == 1 and descendants[spec] == 1,
        "a profession window refresh walked the whole window again, or skipped a page")
    NextFrame()
    Reset()
    local function RefreshCost()
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        local ticks = 0
        debug.sethook(function() ticks = ticks + 1 end, "", 1)
        professions:Refresh()
        debug.sethook()
        local kilobytes = collectgarbage("count") - before
        collectgarbage("restart")
        NextFrame()
        Reset()
        return ticks, kilobytes
    end
    RefreshCost()
    -- Measured 2026-10-02 in this fixture (GC stopped): 3,129,656 VM
    -- instructions before the skin-generation guard (each page walked again
    -- inside the window's full pass) and 126.7 KB, 1,655,494 and 78.4 KB with
    -- it; budgets +2 %.
    local cost, kilobytes = RefreshCost()
    Expect(cost <= 1688600, ("a profession window refresh costs %d VM instructions (budget 1688600)"):format(cost))
    Expect(kilobytes <= 80, ("a profession window refresh allocates %.1f KB (budget 80)"):format(kilobytes))
    -- A tab switch gives the window its full pass; the other signals of that
    -- frame take none.
    deepNS.DeepWindows:OnProfessionsTabSet(professions)
    crafting:Init()
    crafting:SchematicPostInit()
    professions.scripts.OnShow(professions)
    Expect(calls[professions] == 1 and next(descendants) == nil,
        "one burst of profession lifecycle signals took more than one pass")
    NextFrame()
    -- Reopening a window applied in this skin generation takes no pass.
    Reset()
    professions.scripts.OnShow(professions)
    Expect(calls[professions] == nil, "reopening an applied profession window repeated its full pass")
    -- After a look change the first signal gives the window its full pass.
    for owner, callback in pairs(listeners) do callback(owner, "theme", "look") end
    crafting:SchematicPostInit()
    Expect(calls[professions] == 1 and next(descendants) == nil,
        "a look change did not give the profession window a full pass")
    NextFrame()

    Reset()
    traits:ApplyLayout()
    traits.scripts.OnShow(traits)
    Expect(calls[traits] == 1,
        "generic trait lifecycle hooks targeted the mixin instead of the existing frame")
    NextFrame()
    Reset()
    traits.scripts.OnShow(traits)
    Expect(calls[traits] == nil, "reopening an applied trait window repeated its full pass")
    C_Timer = nil
    GenericWindows.ApplyDescendant = applyDescendant

    -- The window families apply in their order from before the split (quest
    -- and bank, professions, customer orders, the warband collection, generic
    -- traits), and the customer-order window gets its pass.
    local customerOrders = Frame("ProfessionsCustomerOrdersFrame")
    _G.ProfessionsCustomerOrdersFrame = customerOrders
    local FAMILIES = {
        "Blizzard_UIPanels_Game", "Blizzard_Professions", "Blizzard_ProfessionsCustomerOrders",
        "Blizzard_Collections", "Blizzard_GenericTraitUI",
    }
    local isFamily, seen, order = {}, {}, {}
    for _, addon in ipairs(FAMILIES) do isFamily[addon] = true end
    local isAddOnLoaded = NS.Client.IsAddOnLoaded
    NS.Client.IsAddOnLoaded = function(addon)
        if isFamily[addon] and not seen[addon] then
            seen[addon] = true
            order[#order + 1] = addon
        end
        return true
    end
    Reset()
    deepNS.DeepWindows.Apply("family-order")
    NS.Client.IsAddOnLoaded = isAddOnLoaded
    Expect(table.concat(order, ",") == table.concat(FAMILIES, ","),
        "the deep window families applied in another order: " .. table.concat(order, ","))
    Expect(calls[customerOrders] == 1, "the customer-order window was not skinned")
    deepNS.DeepWindows.Disable("family-order")
    _G.ProfessionsCustomerOrdersFrame = nil

    -- Every window is its own error boundary: a raising one is reported and
    -- the other windows still apply.
    deepNS.DeepWindows.Disable("deep")
    Expect(rankTrack and rankTrack.surfaceVisible == false, "disabling the deep windows left the rank bar track visible")
    Reset()
    local brokenProfessions = Frame("ProfessionsFrame")
    function brokenProfessions:GetChildren() error("contract: professions raised") end
    _G.ProfessionsFrame = brokenProfessions
    local reportedBefore = #reported
    local applied = pcall(deepNS.DeepWindows.Apply, "deep")
    Expect(applied and calls[traits] == 1 and #reported == reportedBefore + 1,
        "a raising deep window stopped the other windows or was not reported")
    _G.ProfessionsFrame = professions

    -- A raising bag renderer is reported, not raised into Blizzard's caller.
    local generate = function() end
    _G.ContainerFrame_GenerateFrame = generate
    deepNS.DeepWindows.InstallContainerGenerateHook(function() error("contract: bag renderer raised") end)
    local before = #reported
    local ok = pcall(_G.ContainerFrame_GenerateFrame, Frame("ContainerFrame1"))
    Expect(ok and #reported == before + 1,
        "a raising bag renderer escaped into ContainerFrame_GenerateFrame's caller")

    deepNS.DeepWindows.Disable("deep")
    restore()
    _G.ProfessionsFrame, _G.GenericTraitFrame, _G.ContainerFrame_GenerateFrame = nil, nil, nil
    _G.ProfessionsMixin, _G.ProfessionsCraftingPageMixin, _G.GenericTraitFrameMixin = nil, nil, nil
end)

Section("common menus", function()
    Load("DeepWindows.lua")
    Load("DeepWindowsProfessions.lua")
    local bag = Frame("ContainerFrame1")
    local items = {}
    -- ContainerFrame_GenerateFrame shows the bag, whose OnShow fires the
    -- OpenBag callback, then UpdateItems sets each reused button's quality
    -- border for its current contents; the post-hook runs last.
    _G.ContainerFrame_GenerateFrame = function(frame)
        NS.CommonMenus:OnBagOpened(frame)
        for _, item in ipairs(items) do _G.SetItemButtonQuality(item, item.contents) end
    end
    Load("CommonMenus.lua")
    local itemSkins = {}
    local raiseFor
    local attach, fade = NS.Surface.Attach, NS.Cosmetics.Fade
    local applyButton = NS.ControlSkin.ApplyButton or function() return {} end
    local buttonSkinCalls, faded = 0, {}
    NS.ControlSkin.ApplyButton = function(button, ...)
        if button.GetBagID then
            buttonSkinCalls = buttonSkinCalls + 1
            return {}
        end
        return applyButton(button, ...)
    end
    NS.Surface.Attach = function(button, spec)
        if button.GetBagID then
            if button == raiseFor then error("contract: item skin raised") end
            itemSkins[button] = (itemSkins[button] or 0) + 1
        end
        return attach(button, spec)
    end
    NS.Cosmetics.Fade = function(region, owner)
        faded[region] = owner
        return fade(region, owner)
    end
    NS.ControlSkin.ApplySearchBox = function() return {} end
    -- IconSkin reads the native quality border while it skins.
    local iconStates, iconPaints = {}, {}
    local getState, getOwner = NS.IconSkin.GetState, NS.IconSkin.GetOwner
    NS.IconSkin.Apply = function(button, owner, spec)
        button.skinnedQuality = spec.nativeBorder.quality
        iconPaints[button] = (iconPaints[button] or 0) + 1
        iconStates[button] = { owner = owner, icon = spec.icon, nativeBorder = spec.nativeBorder }
        return iconStates[button]
    end
    NS.IconSkin.GetState = function(button) return iconStates[button] end
    NS.IconSkin.GetOwner = function(button)
        local iconState = iconStates[button]
        return iconState and iconState.owner or nil
    end
    -- The paint-only repaint (Rendering/IconSkin.lua) reads the same border.
    local repaint = NS.IconSkin.Repaint
    NS.IconSkin.Repaint = function(button)
        button.repaintedQuality = button.IconBorder.quality
        return true
    end
    local function Item()
        local button = Frame(nil)
        button.icon, button.IconBorder, button.contents = {}, { quality = "empty" }, "common"
        function button:GetBagID() return 0 end
        function button:GetID() return 1 end
        function button:GetParent() return bag end
        items[#items + 1] = button
        return button
    end
    Item()
    Item()
    bag.itemButtonPool = {
        EnumerateActive = function()
            local index = 0
            return function()
                index = index + 1
                return items[index]
            end
        end,
    }
    local calls, restore = CountingApplyFrame()
    -- ContainerFrameMixin:UpdateItems sets each button's border through it.
    _G.SetItemButtonQuality = function(button, quality) button.IconBorder.quality = quality end
    NS.CommonMenus.Apply("menus")
    _G.ContainerFrame_GenerateFrame(bag, 16, 0)
    Expect(calls[bag] == 1 and itemSkins[items[1]] == 1,
        "one bag opening skinned the bag window or its items twice")
    local slotSpec = items[1].surfaceSpec
    Expect(buttonSkinCalls == 0 and slotSpec and slotSpec.interactive == false and slotSpec.motion == false,
        "the bag skin must leave native slot button states and click scripts alone")
    Expect(items[1].skinnedQuality == "common",
        "a bag button took its quality border before UpdateItems had set it")
    local added = Item()
    items[1].contents = "epic"
    local paints = iconPaints[items[1]]
    _G.ContainerFrame_GenerateFrame(bag, 16, 0)
    Expect(iconPaints[items[1]] == paints + 1, "reopening a bag repainted a reused border twice")
    Expect(calls[bag] == 1 and itemSkins[added] == 1 and itemSkins[items[1]] == 1,
        "reopening a bag re-skinned more than its new item buttons")
    Expect(items[1].skinnedQuality == "epic",
        "a reused bag button kept the quality border of its old contents")
    -- Initialize gives a button moved into the combined bag an ItemSlotBackground.
    items[2].ItemSlotBackground = {}
    _G.ContainerFrame_GenerateFrame(bag, 16, 0)
    Expect(itemSkins[items[2]] == 2 and itemSkins[items[1]] == 1 and faded[items[2].ItemSlotBackground] == "menus",
        "a reused bag button's new ItemSlotBackground was not faded")

    -- BAG_UPDATE, or item data that loads after opening, updates an open bag
    -- through UpdateItems alone.
    local skins = itemSkins[items[1]]
    _G.SetItemButtonQuality(items[1], "rare")
    Expect(items[1].skinnedQuality == "rare" and itemSkins[items[1]] == skins,
        "an open bag's item border kept the quality it had before a bag update")
    local foreign = Frame(nil)
    foreign.icon, foreign.IconBorder = {}, { quality = "empty" }
    _G.SetItemButtonQuality(foreign, "epic")
    Expect(foreign.skinnedQuality == nil, "the border hook painted an item button no skin owns")
    -- BankPanelItemButtonMixin:Refresh and other item windows set borders
    -- through the same function; every border IconSkin owns follows it.
    local bankButton = Frame(nil)
    bankButton.icon, bankButton.IconBorder = {}, { quality = "common" }
    Kit.SkinItemIcon(bankButton, "bank", bankButton.icon, bankButton.IconBorder, true)
    _G.SetItemButtonQuality(bankButton, "epic")
    Expect(bankButton.skinnedQuality == "epic", "a bank item border kept the quality of its old contents")
    -- Looting in combat with the bags open: the owned border lines take the
    -- new quality as paint only, without a skin pass.
    local combatSkins = itemSkins[items[1]]
    locked = true
    _G.SetItemButtonQuality(items[1], "legendary")
    _G.SetItemButtonQuality(foreign, "legendary")
    locked = false
    Expect(items[1].skinnedQuality == "rare" and itemSkins[items[1]] == combatSkins,
        "a bag item was skinned again in combat")
    Expect(items[1].repaintedQuality == "legendary", "a bag item border kept its old quality in combat")
    Expect(foreign.repaintedQuality == nil, "the combat repaint reached an item button no skin owns")

    raiseFor = Item()
    local before = #reported
    local ok = pcall(_G.ContainerFrame_GenerateFrame, bag, 16, 0)
    Expect(ok and #reported > before,
        "a raising bag pass escaped into Blizzard's bag update")
    local iconApply = NS.IconSkin.Apply
    NS.IconSkin.Apply = function() error("contract: bag border raised") end
    before = #reported
    ok = pcall(_G.SetItemButtonQuality, items[1], "epic")
    NS.IconSkin.Apply = iconApply
    Expect(ok and items[1].IconBorder.quality == "epic" and #reported == before + 1,
        "a raising bag border repaint escaped into Blizzard's item update")
    NS.CommonMenus.Disable("menus")
    Expect(items[1].surfaceVisible == false, "disabling the bag skin left a slot surface visible")
    NS.Surface.Attach, NS.ControlSkin.ApplyButton, NS.Cosmetics.Fade = attach, applyButton, fade
    restore()
    NS.IconSkin.GetState, NS.IconSkin.GetOwner, NS.IconSkin.Repaint = getState, getOwner, repaint
    _G.ContainerFrame_GenerateFrame, _G.SetItemButtonQuality = nil, nil
end)

Section("legacy windows", function()
    Load("LegacyWindows.lua")
    _G.CalendarFrame = Frame("CalendarFrame")
    local day = Frame("CalendarDayButton1")
    function day:GetNormalTexture() error("contract: calendar day raised") end
    _G.CalendarDayButton1 = day
    _G.MerchantFrame = Frame("MerchantFrame")
    local merchantItem = Frame("MerchantItem1")
    _G.MerchantItem1 = merchantItem
    local before = #reported
    local ok, applied, state = pcall(NS.LegacyWindows.Apply, "legacy")
    Expect(ok and applied and state == "partial" and merchantItem.surfaceSpec ~= nil
        and #reported == before + 1,
        "a raising legacy window group stopped the other groups")
    NS.LegacyWindows.Disable("legacy")
    _G.CalendarFrame, _G.CalendarDayButton1, _G.MerchantFrame, _G.MerchantItem1 = nil, nil, nil, nil
end)

Section("social ui tabs", function()
    Load("SocialUI.lua")
    local mixin = {}
    function mixin:RefreshTabs() self.tabs = self.nextTabs end
    function mixin:RefreshTabStates() end
    function mixin:EnumerateTabs()
        local index = 0
        return function()
            index = index + 1
            return self.tabs[index]
        end
    end
    _G.SocialUIFrameMixin = mixin
    local cardMixin = {}
    function cardMixin:Initialize() end
    function cardMixin:SetSelected() end
    _G.FriendsListSocialCardMixin = cardMixin
    local social = Frame("SocialUIFrame")
    for key, method in pairs(mixin) do social[key] = method end
    social.tabs = {}
    local friends = Frame(nil)
    friends.ScrollBox = RowBox()
    social.FriendsList = friends
    _G.SocialUIFrame = social
    NS.SocialUISkin.Apply("social")
    local tab = Frame("SocialTab")
    tab.SelectedTexture = { IsShown = function() return true end }
    social.nextTabs = { tab }
    social:RefreshTabs()
    Expect(tab.surfaceSpec ~= nil and tab.surfaceSpec.role == "navigation" and tab.surfaceActive == true,
        "social tabs were not skinned after the frame rebuilt them")
    local tabAttaches = 0
    local tabAttach = NS.Surface.Attach
    NS.Surface.Attach = function(target, ...)
        if target == tab then tabAttaches = tabAttaches + 1 end
        return tabAttach(target, ...)
    end
    tab.SelectedTexture = { IsShown = function() return false end }
    social:RefreshTabStates()
    NS.Surface.Attach = tabAttach
    Expect(tabAttaches == 0 and tab.surfaceActive == false,
        "a tab state refresh re-attached the tab surfaces instead of following the selection")
    local raisingTab = setmetatable({}, { __index = function() error("contract: social tab raised") end })
    social.nextTabs = { raisingTab }
    local before = #reported
    local rebuilt = pcall(social.RefreshTabs, social)
    Expect(rebuilt and social.tabs[1] == raisingTab and #reported == before + 1,
        "a raising social tab escaped into Blizzard's RefreshTabs")
    social.nextTabs = { tab }
    social:RefreshTabs()

    -- A friend card Blizzard creates now carries the (hooked) mixin; the
    -- ScrollBox then reports it. It is skinned once.
    local attaches = 0
    local attach = NS.Surface.Attach
    NS.Surface.Attach = function(target, ...)
        attaches = attaches + 1
        return attach(target, ...)
    end
    local card = Frame(nil)
    for key, method in pairs(cardMixin) do card[key] = method end
    for _, key in ipairs({ "Background", "PresenceHolder", "PartyButton", "GameIconHolder",
        "TextHolder", "StateDisplay", "FriendName" }) do
        card[key] = {}
    end
    function card:GetParent() return friends end
    card:Initialize()
    friends.ScrollBox:Initialize(card)
    NS.Surface.Attach = attach
    Expect(attaches == 1, "a friend card was skinned by both its Initialize hook and the ScrollBox")
    NS.SocialUISkin.Disable("social")
    _G.SocialUIFrame, _G.SocialUIFrameMixin, _G.FriendsListSocialCardMixin = nil, nil, nil
end)

Section("encounter journal row colors", function()
    Load("EncounterJournal.lua")
    local journal = Frame("EncounterJournal")
    local monthly = Frame(nil)
    local box = RowBox()
    monthly.ScrollBox = box
    journal.MonthlyActivitiesFrame = monthly
    NS.ControlSkin.ApplyTab = function() return {} end
    local getColor = NS.Theme.GetColor
    local roleColors = { muted = { 0.41, 0.42, 0.43, 1 }, blizzardYellow = { 0.95, 0.77, 0.2, 1 } }
    NS.Theme.GetColor = function(role)
        local color = roleColors[role]
        if color then return color[1], color[2], color[3], color[4] end
        return 0.61, 0.62, 0.63, 1
    end
    NS.EncounterJournalSkin.Apply(journal, "journal")
    local name, conditions = Text(1, 1, 1), Text(1, 0.125, 0.125)
    local row = Frame(nil)
    row.TextContainer = { NameText = name, ConditionsText = conditions }
    box:Initialize(row)
    Expect(Near(name.color[1], 0.61), "a plain activity name was not themed")
    Expect(Near(conditions.color[1], 1) and Near(conditions.color[2], 0.125),
        "unmet activity conditions lost their red")
    -- The row is reused for an activity whose conditions are met, then for
    -- an unmet one again.
    conditions:SetTextColor(1, 0.82, 0)
    box:Initialize(row)
    Expect(Near(conditions.color[1], 0.61), "met activity conditions were not themed")
    conditions:SetTextColor(1, 0.125, 0.125)
    box:Initialize(row)
    Expect(Near(conditions.color[2], 0.125), "a reused row painted over Blizzard's red")
    local power = Frame(nil)
    power.Name = Text(1, 0.5, 0)
    box:Initialize(power)
    Expect(Near(power.Name.color[2], 0.5), "a legendary power name lost its quality color")
    -- Completed activities are painted black: their completion signal.
    local completed = Frame(nil)
    completed.TextContainer = { NameText = Text(0, 0, 0), ConditionsText = Text(0, 0, 0) }
    box:Initialize(completed)
    Expect(Near(completed.TextContainer.NameText.color[1], 0.41)
        and Near(completed.TextContainer.ConditionsText.color[1], 0.41),
        "a completed activity lost its distinct completion color")
    -- Gold the skin already retinted to its own Blizzard-yellow is plain too.
    local retinted = Frame(nil)
    retinted.TextContainer = { NameText = Text(0.95, 0.77, 0.2) }
    box:Initialize(retinted)
    Expect(Near(retinted.TextContainer.NameText.color[1], 0.61),
        "a row label in the skin's Blizzard-yellow kept that color")
    -- Only the skin's own yellow is plain; a gold Blizzard painted near it is not.
    local nearYellow = Frame(nil)
    nearYellow.TextContainer = { NameText = Text(0.96, 0.78, 0.21) }
    box:Initialize(nearYellow)
    Expect(Near(nearYellow.TextContainer.NameText.color[1], 0.96),
        "a Blizzard color near the skin's yellow was taken for the skin's own")
    -- A look change keeps a label Blizzard recolored in place since our pass.
    local recolored = Frame(nil)
    recolored.TextContainer = { NameText = Text(1, 1, 1), ConditionsText = Text(1, 1, 1) }
    box:Initialize(recolored)
    recolored.TextContainer.ConditionsText:SetTextColor(1, 0.125, 0.125)
    roleColors.muted = { 0.45, 0.46, 0.47, 1 }
    NS.EncounterJournalSkin:OnThemeChanged()
    Expect(Near(recolored.TextContainer.ConditionsText.color[2], 0.125),
        "a look change repainted a row label Blizzard had recolored")
    Expect(Near(recolored.TextContainer.NameText.color[1], 0.61),
        "a look change dropped the theme color of a plain row label")
    Expect(Near(completed.TextContainer.NameText.color[1], 0.45),
        "a look change did not repaint a completed activity in the new muted color")
    -- A pooled label that alternates between Blizzard's meaningful color and
    -- a plain one allocates nothing per initialization.
    local label = { r = 1, g = 1, b = 1, a = 1 }
    function label:GetObjectType() return "FontString" end
    function label:GetTextColor() return self.r, self.g, self.b, self.a end
    function label:SetTextColor(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a or 1 end
    local flipping = Frame(nil)
    flipping.TextContainer = { ConditionsText = label }
    local attachStub, staticSurface = NS.Surface.Attach, { spec = {} }
    NS.Surface.Attach = function() return staticSurface end
    box:Initialize(flipping)
    collectgarbage("collect")
    collectgarbage("stop")
    local memory = collectgarbage("count")
    for _ = 1, 500 do
        label:SetTextColor(1, 0.125, 0.125)
        box:Initialize(flipping)
        label:SetTextColor(1, 1, 1)
        box:Initialize(flipping)
    end
    local grown = collectgarbage("count") - memory
    collectgarbage("restart")
    NS.Surface.Attach = attachStub
    Expect(grown < 2, ("alternating row colors allocated %.1f KB for 1000 initializations"):format(grown))
    NS.EncounterJournalSkin.Disable(journal, "journal")
    NS.Theme.GetColor = getColor
    Expect(Near(name.color[1], 1) and Near(conditions.color[2], 0.125),
        "disable did not restore plain row text or overwrote Blizzard's current color")
end)

Section("player spells tab colors", function()
    Load("PlayerSpells.lua")
    local label = Text(1, 0.82, 0)
    local tab = Frame("PlayerSpellsTab")
    tab.Text, tab.isSelected = label, true
    local spells = Frame("PlayerSpellsFrame")
    spells.shown, spells.hooks = true, {}
    function spells:IsShown() return self.shown end
    function spells:HookScript(name, callback)
        assert(not self.hooks[name], "duplicate spellbook hook")
        self.hooks[name] = callback
    end
    spells.TabSystem = { tabs = { tab } }
    -- The spell book's search box takes the shared search box skin.
    local spellBook = Frame(nil)
    spellBook.SearchBox = Frame(nil)
    spells.SpellBookFrame = spellBook
    local talents = Frame(nil)
    talents.shown = false
    function talents:IsShown() return self.shown end
    spells.TalentsFrame = talents
    local searchBoxes = {}
    local attached = {}
    local attachControls = NS.WindowControls.Attach
    local releaseControls = NS.WindowControls.DisableOwner
    local releasedOwner
    NS.WindowControls.Attach = function(frame, owner)
        attached[#attached + 1] = { frame = frame, owner = owner }
    end
    NS.WindowControls.DisableOwner = function(owner) releasedOwner = owner end
    local applySearchBox = NS.ControlSkin.ApplySearchBox
    NS.ControlSkin.ApplySearchBox = function(box)
        searchBoxes[box] = true
        return {}
    end
    local getColor = NS.Theme.GetColor
    local themeRed, themeReads = 0.71, 0
    NS.Theme.GetColor = function() themeReads = themeReads + 1; return themeRed, 0.72, 0.73, 1 end
    -- The portrait overhangs the frame corner: a small round copy sits in the
    -- title bar and follows Blizzard's portrait changes (spellbook, class, spec).
    local spellsPortrait = { texture = 136830, coords = { 0, 0, 0, 1, 1, 0, 1, 1 } }
    function spellsPortrait:GetTexture() return self.texture end
    function spellsPortrait:GetTexCoord() return unpack(self.coords) end
    function spellsPortrait:SetTexture(texture) self.texture = texture end
    function spellsPortrait:SetTexCoord(...) self.coords = { ... } end
    spells.PortraitContainer = { portrait = spellsPortrait, GetFrameLevel = function() return 4 end }
    local createSpells, spellFrames = CreateFrame, {}
    CreateFrame = function(...)
        local frame = createSpells(...)
        function frame:SetFrameLevel(level) self.level = level end
        function frame:SetSize(width, height) self.width, self.height = width, height end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:IsShown() return self.shown == true end
        function frame:CreateTexture()
            local texture = {}
            function texture:SetAllPoints() end
            function texture:SetTexture(value) self.texture = value end
            function texture:SetTexCoord(...) self.coords = { ... } end
            self.icon = texture
            return texture
        end
        spellFrames[#spellFrames + 1] = frame
        return frame
    end
    NS.PlayerSpellsSkin.Apply(spells, "spells")
    CreateFrame = createSpells
    local spellBadge
    for _, frame in ipairs(spellFrames) do
        if frame.parent == spells and frame.icon then spellBadge = frame end
    end
    Expect(spellBadge and spellBadge.shown and spellBadge.level == 5 and spellBadge.width == 18
        and spellBadge.point[1] == "TOPLEFT" and spellBadge.point[2] == spells
        and spellBadge.point[4] > 0 and spellBadge.point[5] < 0,
        "the spellbook portrait lacks its small badge inside the title bar")
    Expect(spellBadge.icon.texture == 136830 and spellBadge.icon.coords[8] == 1,
        "the portrait badge does not show Blizzard's portrait")
    spellsPortrait:SetTexCoord(0.25, 0, 0.25, 0.5, 0.5, 0, 0.5, 0.5)
    spellsPortrait:SetTexture("Interface/TargetingFrame/UI-Classes-Circles")
    Expect(spellBadge.icon.texture == "Interface/TargetingFrame/UI-Classes-Circles"
        and spellBadge.icon.coords[1] == 0.25 and spellBadge.icon.coords[8] == 0.5,
        "the portrait badge missed Blizzard's class portrait change")
    NS.ControlSkin.ApplySearchBox = applySearchBox
    Expect(searchBoxes[spellBook.SearchBox], "the spell book search box was not skinned")
    Expect(talents.surfaceSpec and talents.surfaceSpec.role == "panel" and talents.childReads == 0,
        "hidden talents lacked a prepared shell or traversed the hidden tree")
    Expect(#attached == 1 and attached[1].frame == spells and attached[1].owner == "spells",
        "the dedicated spellbook adapter did not attach window controls to its root")
    NS.PlayerSpellsSkin:OnFrameTabSet(spells)
    Expect(#attached == 2 and attached[2].frame == spells and attached[2].owner == "spells",
        "native spellbook tab changes did not reapply its stored window controls")
    Expect(Near(label.color[1], 0.71), "the selected tab label was not themed")
    local attachBefore, paintBefore = #attached, counters.attach
    spells.shown = false
    for _ = 1, 100 do
        NS.PlayerSpellsSkin:OnDisplayedSpellsChanged()
        NS.PlayerSpellsSkin:OnFrameTabSet(spells)
    end
    NS.PlayerSpellsSkin:OnDisplayedSpellsChanged()
    themeRed = 0.81
    NS.PlayerSpellsSkin:OnThemeChanged()
    Expect(Near(label.color[1], 0.71), "theme change repainted a hidden spellbook")
    Expect(#attached == attachBefore and counters.attach == paintBefore,
        "hidden spellbook callbacks exceeded zero visual work budget")
    Expect(spells.hooks.OnShow ~= nil, "hidden spellbook has no show refresh")
    spells.shown = true
    if spells.hooks.OnShow then spells.hooks.OnShow(spells) end
    Expect(#attached == attachBefore + 1, "show lost the coalesced page refresh")
    Expect(Near(label.color[1], 0.81), "show lost the hidden theme change")
    attachBefore, paintBefore = #attached, counters.attach
    local readsBefore = themeReads
    if spells.hooks.OnShow then spells.hooks.OnShow(spells) end
    Expect(#attached == attachBefore and counters.attach == paintBefore and themeReads == readsBefore,
        "show without invalidation repeated visual work")
    local defer, deferred = NS.CombatGate.RunOrDefer, nil
    NS.CombatGate.RunOrDefer = function(_, callback) deferred = callback end
    locked = true
    NS.PlayerSpellsSkin:OnFrameTabSet(spells)
    Expect(#attached == attachBefore and deferred ~= nil, "combat refresh was not deferred")
    spells.shown, locked = false, false
    if deferred then deferred() end
    Expect(#attached == attachBefore, "combat-end job painted a closed spellbook")
    spells.shown = true
    if spells.hooks.OnShow then spells.hooks.OnShow(spells) end
    Expect(#attached == attachBefore + 1, "reopen lost combat-deferred page work")
    locked = true
    NS.PlayerSpellsSkin:OnFrameTabSet(spells)
    locked = false
    NS.PlayerSpellsSkin:QueueRefresh(spells)
    paintBefore, readsBefore = counters.attach, themeReads
    if deferred then deferred() end
    Expect(counters.attach == paintBefore and themeReads == readsBefore,
        "older combat job repeated an already completed refresh")
    NS.CombatGate.RunOrDefer = defer
    NS.PlayerSpellsSkin.Disable(spells, "spells")
    Expect(releasedOwner == "spells", "disabling the dedicated spellbook skin did not release its window controls")
    Expect(spellBadge and spellBadge.shown == false, "disabling the spellbook skin left the portrait badge visible")
    local previousSpells, previousDB = _G.PlayerSpellsFrame, NS.DB
    local cold = Frame("PlayerSpellsFrame")
    cold.TalentsFrame, cold.SpellBookFrame = Frame(nil), Frame(nil)
    function cold:IsShown() return true end
    function cold:IsProtected() return true, false end
    function cold.SpellBookFrame:IsProtected() return true, false end
    function cold.SpellBookFrame:IsShown() return false end
    function cold:HookScript() end
    _G.PlayerSpellsFrame = cold
    NS.DB = { enabled = true, skins = {} }
    locked = true
    NS.PlayerSpellsSkin.AttachWindowControls(cold, "spells")
    Expect(cold.TalentsFrame.surfaceSpec and not cold.surfaceSpec and not cold.SpellBookFrame.surfaceSpec,
        "first combat opening skipped safe talent chrome or wrote a protected shell")
    locked = false
    NS.PlayerSpellsSkin.Disable(cold, "spells")
    _G.PlayerSpellsFrame, NS.DB = previousSpells, previousDB
    NS.WindowControls.Attach = attachControls
    NS.WindowControls.DisableOwner = releaseControls
    NS.Theme.GetColor = getColor
    Expect(Near(label.color[1], 1) and Near(label.color[2], 0.82),
        "a tab refresh recaptured our own color as the native one")
end)

Section("prepared Forever spells window combat artwork", function()
    local oldClient, oldCosmetics, oldGetSurface = NS.Client, NS.Cosmetics, NS.Registry.GetSurface
    local oldLockdown = InCombatLockdown
    NS.Client = { isForever = true }
    InCombatLockdown = function() return locked end
    assert(loadfile(skin .. "Core/Cosmetics.lua"))("MSUF_Suite_Skin", NS)
    Load("PlayerSpells.lua")
    local writes = 0
    local function Art()
        return { alpha = 1, GetAlpha = function(self) return self.alpha end,
            SetAlpha = function(self, value) self.alpha = value; writes = writes + 1 end }
    end
    local spells, book, talents = Frame("PlayerSpellsFrame"), Frame(nil), Frame(nil)
    spells.SpellBookFrame, spells.TalentsFrame = book, talents
    spells.shown, book.shown, talents.shown = false, true, false
    for _, frame in ipairs({ spells, book, talents }) do
        function frame:IsShown() return self.shown end
        function frame:IsProtected() return true, false end
    end
    function spells:HookScript(_, callback) self.onShow = callback end
    book.BookBGHalved, book.BookBGLeft = Art(), Art()
    talents.ClassBackground, talents.BackgroundBorder = Art(), Art()
    local shell = { fill = { IsShown = function() return true end } }
    NS.Registry.GetSurface = function(target)
        if (target == book or target == talents) and target.surfaceSpec then return shell end
    end
    local previousAdapters, previousDB, previousSpells = NS.Adapters, NS.DB, PlayerSpellsFrame
    local previousEvents, previousAddOns = EventUtil, C_AddOns
    local continuation, loads = nil, 0
    PlayerSpellsFrame, NS.DB, book.shown = nil, { enabled = true, skins = {} }, false
    spells.Bg = Art()
    NS.Client.HasAddOn = function(addon) return addon == "Blizzard_PlayerSpells" end
    NS.Client.IsAddOnLoaded = function() return PlayerSpellsFrame ~= nil end
    EventUtil = { ContinueOnAddOnLoaded = function(addon, callback)
        assert(addon == "Blizzard_PlayerSpells" and not continuation)
        continuation = callback
    end }
    C_AddOns = { LoadAddOn = function(addon)
        assert(not locked and addon == "Blizzard_PlayerSpells" and loads == 0)
        loads, PlayerSpellsFrame = loads + 1, spells
        continuation()
    end }
    local originalTrackTree = NS.Checkmarks.TrackControlTree
    NS.Checkmarks.TrackControlTree = function() end
    Load("Blizzard.lua")
    local adapters = NS.Adapters
    assert(not adapters.Apply("playerSpells") and loads == 0, "native addon loaded inside the login pass")
    if adapters.PrepareCombatWindows then adapters.PrepareCombatWindows() end
    Expect(loads == 1 and not spells.shown and not book.shown and not talents.shown
        and spells.surfaceSpec and book.surfaceSpec and talents.surfaceSpec and spells.Bg.alpha == 0
        and talents.ClassBackground.alpha == 0 and talents.BackgroundBorder.alpha == 0,
        "hidden native shells or the Forever talent backdrop were not prepared before the first fight")
    local prepared = NS.PlayerSpellsSkin.states[spells] ~= nil
    PlayerSpellsFrame, NS.DB, NS.Adapters = previousSpells, previousDB, previousAdapters
    EventUtil, C_AddOns, NS.Checkmarks.TrackControlTree = previousEvents, previousAddOns, originalTrackTree
    if not prepared then return end

    book.BookBGHalved.alpha = 1
    book.BookBGLeft.alpha = 1
    function book.BookBGLeft:IsProtected() return true, true end
    spells.shown, book.shown, locked = true, true, true
    local attaches = counters.attach
    NS.PlayerSpellsSkin:OnDisplayedSpellsChanged()
    Expect(book.BookBGHalved.alpha == 1, "spell-data update traversed prepared chrome")
    spells.onShow(spells)
    Expect(book.BookBGHalved.alpha == 0 and book.BookBGLeft.alpha == 1,
        "combat reopening did not repair safe spellbook artwork or touched a protected region")
    local painted = writes
    spells.onShow(spells)
    Expect(writes == painted, "unchanged combat artwork performed another write")
    talents.ClassBackground.alpha = 1
    book.shown, talents.shown = false, true
    local applyButton, applyPasses = NS.ControlSkin.ApplyButton, 0
    talents.ApplyButton = Frame(nil)
    NS.ControlSkin.ApplyButton = function()
        applyPasses = applyPasses + 1
        return {}
    end
    NS.PlayerSpellsSkin:OnFrameTabSet(spells)
    NS.PlayerSpellsSkin:OnFrameTabSet(spells)
    NS.ControlSkin.ApplyButton = applyButton
    Expect(talents.ClassBackground.alpha == 0 and counters.attach == attaches,
        "combat tab selection did not repair the prepared artwork without reattaching")
    Expect(applyPasses == 1, "unchanged combat talent controls repainted or stayed native")

    local vertexWrites = 0
    local function VertexArt()
        return { a = 1, GetVertexColor = function(self) return 1, 1, 1, self.a end,
            SetVertexColor = function(self, _, _, _, alpha) self.a = alpha; vertexWrites = vertexWrites + 1 end }
    end
    local header, row, button = Frame(nil), Frame(nil), Frame(nil)
    header.Backplate, header.Border, header.Text = VertexArt(), VertexArt(), Text(0.4, 0.2, 0.1)
    row.Backplate, row.Button = VertexArt(), button
    row.TextContainer = { Name = Text(0.4, 0.2, 0.1), SubName = Text(0.4, 0.2, 0.1) }
    button.Border = VertexArt()
    function button:IsProtected() return true, true end
    local displayed = { header, row }
    local pageReads = 0
    book.PagedSpellsFrame = { GetFrames = function() pageReads = pageReads + 1; return displayed end }
    book.shown, talents.shown = true, false
    NS.PlayerSpellsSkin:OnDisplayedSpellsChanged()
    Expect(header.Backplate.a == 0 and header.Border.a == 0 and row.Backplate.a == 0,
        "pooled spellbook rows or header kept their native combat art")
    Expect(row.TextContainer.Name.color[1] == NS.Theme.GetColor("text")
        and row.TextContainer.SubName.color[1] == NS.Theme.GetColor("muted"),
        "pooled spell labels waited until combat ended")
    Expect(not button.surfaceSpec and button.Border.a == 0,
        "spellbook combat paint touched the protected cast button or missed its safe border")
    local vertexPaints = vertexWrites
    NS.PlayerSpellsSkin:OnDisplayedSpellsChanged()
    Expect(vertexWrites == vertexPaints, "unchanged spellbook rows repeated vertex writes")
    local visiblePageReads = pageReads
    function book:IsVisible() return false end
    NS.PlayerSpellsSkin:OnDisplayedSpellsChanged()
    Expect(pageReads == visiblePageReads, "hidden spellbook rows were visited during combat")

    locked = false
    NS.PlayerSpellsSkin.Disable(spells, "prepared-spells")
    spells.shown, book.shown, talents.shown = false, false, false
    NS.ControlSkin.ApplyButton = function()
        applyPasses = applyPasses + 1
        return {}
    end
    NS.PlayerSpellsSkin.Apply(spells, "prepared-spells")
    spells.shown, talents.shown, locked = true, true, true
    NS.PlayerSpellsSkin:OnFrameTabSet(spells)
    Expect(applyPasses == 2, "re-enabled talent controls retained stale skin ownership")
    NS.ControlSkin.ApplyButton = applyButton
    locked = false
    NS.PlayerSpellsSkin.Disable(spells, "prepared-spells")
    local oldSpells, oldDB = PlayerSpellsFrame, NS.DB
    local cold = Frame("PlayerSpellsFrame")
    cold.TalentsFrame, cold.Bg = Frame(nil), Art()
    cold.NineSlice = Frame(nil)
    cold.NineSlice.TopEdge = Art()
    cold.TitleContainer = { TitleText = Text(0.4, 0.2, 0.1) }
    function cold:IsProtected() return true, false end
    function cold:IsShown() return true end
    function cold.TalentsFrame:IsShown() return true end
    function cold:HookScript() end
    PlayerSpellsFrame, NS.DB, locked = cold, { enabled = true, skins = {} }, true
    NS.PlayerSpellsSkin.AttachWindowControls(cold, "prepared-spells")
    Expect(cold.TalentsFrame.surfaceSpec and not cold.surfaceSpec
        and cold.Bg.alpha == 1 and cold.NineSlice.TopEdge.alpha == 1
        and cold.TitleContainer.TitleText.color[1] == NS.Theme.GetColor("title"),
        "cold protected talent root lost its shell, safe title styling or protection")
    locked = false
    NS.PlayerSpellsSkin.Disable(cold, "prepared-spells")

    local oldEvents, oldGate, oldApplyButton = EventRegistry, NS.CombatGate, NS.ControlSkin.ApplyButton
    local function ColdBook(forever)
        NS.Client.isForever = forever
        local root, spellBook, talentPage = Frame("PlayerSpellsFrame"), Frame(nil), Frame(nil)
        root.SpellBookFrame, root.TalentsFrame = spellBook, talentPage
        spellBook.shown, talentPage.shown = true, false
        spellBook.BookBGLeft, talentPage.Background, root.Bg = Art(), Art(), Art()
        for _, frame in ipairs({ root, spellBook, talentPage }) do
            function frame:IsShown() return self.shown == true end
            function frame:IsProtected() return true, self.explicit == true end
            function frame:CreateTexture()
                assert(not locked, "cold combat path wrote to a protected container")
                return {}
            end
        end
        function root:HookScript(event, callback)
            assert(event == "OnShow" and not self.onShow, "cold root hooked twice")
            self.onShow = callback
        end

        local function SpellRow()
            local item, cast = Frame(nil), Frame(nil)
            item.Button, item.TextContainer = cast, { Name = Text(0.4, 0.2, 0.1) }
            cast.Border = VertexArt()
            function cast:IsProtected() return true, true end
            return item
        end
        local rows = { SpellRow() }
        spellBook.PagedSpellsFrame = { GetFrames = function() return rows end }
        talentPage.ApplyButton = Frame(nil)
        local applied, callbacks, jobs, registrations = 0, {}, {}, 0
        NS.ControlSkin.ApplyButton = function(frame)
            assert(frame == talentPage.ApplyButton, "combat path painted an unexpected control")
            applied = applied + 1
            return {}
        end
        EventRegistry = {
            RegisterCallback = function(_, event, callback, owner)
                assert(not callbacks[event], "native event registered twice")
                callbacks[event] = { callback, owner }
                registrations = registrations + 1
            end,
            UnregisterCallback = function(_, event) callbacks[event] = nil end,
        }
        NS.CombatGate = {
            RunOrDefer = function(key, callback) jobs[key] = callback end,
            IsPending = function(key) return jobs[key] ~= nil end,
            Cancel = function(key) jobs[key] = nil end,
        }
        local function Fire(event, ...)
            local registration = assert(callbacks[event], "cold native event was not registered")
            registration[1](registration[2], ...)
        end

        PlayerSpellsFrame, locked = root, true
        NS.PlayerSpellsSkin.Apply(root, "cold-spells")
        assert(root.onShow and next(callbacks) == nil, "hidden first open registered visual callbacks")
        root.shown = true
        root.onShow(root)
        Expect(registrations == 2 and rows[1].surfaceSpec
            and rows[1].TextContainer.Name.color[1] == NS.Theme.GetColor("text"),
            "first combat spellbook did not activate and paint safe rows")
        Expect(not root.surfaceSpec and not spellBook.surfaceSpec and not rows[1].Button.surfaceSpec
            and root.Bg.alpha == 1 and spellBook.BookBGLeft.alpha == 1 and root.childReads == 0,
            "cold combat altered a protected shell, cast button or native artwork without a replacement")

        rows[1] = SpellRow()
        Fire("PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged")
        Expect(rows[1].surfaceSpec and rows[1].Button.Border.a == 0 and not rows[1].Button.surfaceSpec,
            "recycled cold spell row did not repaint its safe decoration")
        spellBook.shown, talentPage.shown = false, true
        Fire("PlayerSpellsFrame.TabSet", root)
        Fire("PlayerSpellsFrame.TabSet", root)
        Expect(applied == 1 and not talentPage.surfaceSpec and talentPage.Background.alpha == 1
            and talentPage.childReads == 0,
            "cold talent page did not paint only its safe controls")

        locked = false
        if forever then
            root.explicit = true
            assert(jobs["playerSpells:apply"])()
            Expect(not root.surfaceSpec and NS.PlayerSpellsSkin.callbacksRegistered,
                "a refused full upgrade dropped the safe lane")
            spellBook.shown, talentPage.shown = true, false
            rows[1] = SpellRow()
            Fire("PlayerSpellsFrame.SpellBookFrame.DisplayedSpellsChanged")
            Expect(rows[1].surfaceSpec, "a refused full upgrade froze safe row updates")
            root.explicit = false
        end
        assert(jobs["playerSpells:apply"])()
        Expect(root.surfaceSpec and spellBook.surfaceSpec and talentPage.surfaceSpec
            and registrations == 2 and not rows[1].Button.surfaceSpec,
            "combat exit did not upgrade the same skin state without duplicate callbacks")
        NS.PlayerSpellsSkin.Disable(root, "cold-spells")
        Expect(next(callbacks) == nil, "disabling the adapter retained native callbacks")
    end
    ColdBook(false)
    ColdBook(true)
    EventRegistry, NS.CombatGate, NS.ControlSkin.ApplyButton = oldEvents, oldGate, oldApplyButton
    PlayerSpellsFrame, NS.DB = oldSpells, oldDB
    NS.Client, NS.Cosmetics, NS.Registry.GetSurface = oldClient, oldCosmetics, oldGetSurface
    InCombatLockdown = oldLockdown
end)

Section("edit mode and game menu pools", function()
    Load("EditMode.lua")
    Load("GameMenu.lua")
    local acquires = 0
    local function Pool(active)
        return {
            Acquire = function() acquires = acquires + 1; return Frame(nil) end,
            Release = function() end,
            GetNumActive = function() return #active end,
            IsActive = function(_, object)
                for _, button in ipairs(active) do
                    if button == object then return true end
                end
                return false
            end,
            EnumerateActive = function()
                local index = 0
                return function()
                    index = index + 1
                    return active[index]
                end
            end,
        }
    end
    local settings = { Frame(nil) }
    local dialog = Frame("EditModeSystemSettingsDialog")
    function dialog:UpdateDialog() end
    local system, otherSystem = Frame("PlayerFrame"), Frame("TargetFrame")
    dialog.attachedToSystem = system
    local settingPool = Pool(settings)
    dialog.pools = {
        GetPool = function() return settingPool end,
        EnumerateActiveByTemplate = function(_, template)
            if template ~= "EditModeSettingDropdownTemplate" then return function() end end
            return settingPool.EnumerateActive()
        end,
    }
    _G.EditModeSystemSettingsDialog = dialog
    local manager = Frame("EditModeManagerFrame")
    function manager:SetHasActiveChanges() end
    local gridCheck = Frame(nil)
    gridCheck.Button = Frame(nil)
    function gridCheck:SetControlChecked(checked) self.checked = checked end
    manager.ShowGridCheckButton = gridCheck
    NS.EditModeSkin.Apply(manager, "edit")
    Expect(acquires == 0, "Edit Mode acquired Blizzard pool frames from addon code")
    Expect(settings[1].surfaceSpec ~= nil, "an active Edit Mode setting was not skinned")
    settings[2] = Frame(nil)
    dialog:UpdateDialog(system)
    Expect(settings[2].surfaceSpec ~= nil, "settings Blizzard acquired later were not skinned")
    -- UpdateSystems calls UpdateDialog for every system; only the attached
    -- one changes the dialog. A slider step re-acquires skinned frames.
    local attaches = counters.attach
    settings[3] = Frame(nil)
    dialog:UpdateDialog(otherSystem)
    Expect(counters.attach == attaches and settings[3].surfaceSpec == nil,
        "UpdateDialog for another system skinned the settings dialog")
    dialog:UpdateDialog(system)
    Expect(counters.attach == attaches + 1 and settings[3].surfaceSpec ~= nil,
        "UpdateDialog skinned setting frames again that were already skinned")
    -- Blizzard's setter runs our repaint inside its own call: a raising
    -- repaint is reported and Blizzard's change goes on.
    local checkApply = NS.ControlSkin.ApplyButton
    NS.ControlSkin.ApplyButton = function() error("contract: edit mode check raised") end
    local before = #reported
    local checked = pcall(gridCheck.SetControlChecked, gridCheck, true)
    NS.ControlSkin.ApplyButton = checkApply
    Expect(checked and gridCheck.checked == true and #reported == before + 1,
        "a raising Edit Mode check repaint escaped into Blizzard's setter")
    NS.EditModeSkin.Disable(manager, "edit")
    _G.EditModeSystemSettingsDialog = nil

    acquires = 0
    local skinned = {}
    local skinnedInset = {}
    local pending = {}
    local priorTimer = C_Timer
    C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
    NS.ControlSkin.ApplyThreeSliceButton = function(button, _, spec)
        skinned[button] = (skinned[button] or 0) + 1
        skinnedInset[button] = spec.inset
        return {}
    end
    local panelSkinned = {}
    local panelInset = {}
    local priorApplyButton = NS.ControlSkin.ApplyButton
    NS.ControlSkin.ApplyButton = function(button, _, spec)
        panelSkinned[button] = true
        panelInset[button] = spec.inset
        return {}
    end
    local buttons = { Frame(nil) }
    buttons[1].GetObjectType = function() return "Button" end
    buttons[1].Left, buttons[1].Center, buttons[1].Right = {}, {}, {}
    local menu = Frame("GameMenuFrame")
    menu.shown = true
    function menu:IsShown() return self.shown end
    menu.children[1] = buttons[1]
    menu.buttonPool = Pool(buttons)
    function menu:InitButtons() end
    local header = Text(1, 0.82, 0)
    menu.Header = { Text = header }
    NS.GameMenuSkin.Apply(menu, "menu")
    Expect(skinned[buttons[1]] == 1, "the Game Menu initial pass skinned a pooled button twice")
    Expect(acquires == 0, "the Game Menu acquired Blizzard pool frames from addon code")
    buttons[2] = Frame(nil)
    local direct = Frame(nil)
    function direct:GetObjectType() return "Button" end
    direct.Left, direct.Center, direct.Right = {}, {}, {}
    menu.children[2] = direct
    menu:InitButtons()
    Expect(skinned[buttons[1]] == 2, "the Game Menu rebuild skinned a pooled button twice")
    Expect(skinned[buttons[1]] and skinned[buttons[2]],
        "Game Menu buttons Blizzard acquired were not skinned")
    Expect(skinned[direct], "a direct Game Menu button added after the first pass was not skinned")
    menu:InitButtons()
    menu:InitButtons()
    Expect(#pending == 1, "Game Menu rebuilds did not coalesce their late direct-button pass")
    local late = Frame(nil)
    function late:GetObjectType() return "Button" end
    late.Left, late.Center, late.Right = {}, {}, {}
    menu.children[3] = late
    local msuf = Frame(nil)
    function msuf:GetObjectType() return "Button" end
    menu.MSUF, menu.children[4] = msuf, msuf
    local msufThree = Frame(nil)
    function msufThree:GetObjectType() return "Button" end
    msufThree.Left, msufThree.Center, msufThree.Right = {}, {}, {}
    Expect(#pending == 1, "Game Menu did not schedule a late direct-button pass")
    local poolApplies = skinned[buttons[1]]
    pending[1]()
    Expect(skinned[buttons[1]] == poolApplies, "the Game Menu late pass re-skinned active pooled buttons")
    Expect(skinned[late] and panelSkinned[msuf],
        "Game Menu buttons added after InitButtons did not receive the Suite skin")
    Expect(skinnedInset[buttons[1]] == 0 and skinnedInset[late] == 0,
        "the Game Menu pool or direct buttons lost their shared full-width bounds")
    -- Compare the painted border on both buttons, not a border to a raw frame.
    local function BorderMatchesMacros(inset)
        return type(inset) == "number" and inset == skinnedInset[buttons[1]]
    end
    Expect(BorderMatchesMacros(panelInset[msuf]),
        "the MSUF fallback button border does not align with Macros")
    menu.MSUF, menu.children[4] = msufThree, msufThree
    menu:InitButtons()
    Expect(BorderMatchesMacros(skinnedInset[msufThree]),
        "the MSUF three-slice button border does not align with Macros")
    for _, stop in ipairs({ "hidden", "disabled" }) do
        menu:InitButtons()
        local reads = menu.childReads
        if stop == "hidden" then menu.shown = false end
        if stop == "combat" then locked = true end
        if stop == "disabled" then NS.GameMenuSkin.Disable(menu, "menu") end
        Expect(pending[#pending] == pending[1], "Game Menu rebuild allocated another late-pass callback")
        pending[#pending]()
        Expect(menu.childReads == reads, "Game Menu late pass still ran while " .. stop)
        menu.shown, locked = true, false
    end
    NS.GameMenuSkin.Apply(menu, "menu")
    menu:InitButtons()
    local resumedReads = menu.childReads
    pending[#pending]()
    Expect(menu.childReads == resumedReads + 1,
        "Game Menu late pass did not resume after an inactive or combat callback")
    C_Timer = priorTimer
    NS.ControlSkin.ApplyButton = priorApplyButton
    -- The native title color comes back only while the theme's is shown.
    header:SetTextColor(0.5, 0.5, 0.5)
    NS.GameMenuSkin.Disable(menu, "menu")
    Expect(Near(header.color[1], 0.5) and Near(header.color[2], 0.5),
        "disabling the Game Menu skin overwrote a header color Blizzard had set")
    NS.GameMenuSkin.Apply(menu, "menu")
    NS.GameMenuSkin.Disable(menu, "menu")
    Expect(Near(header.color[1], 0.5), "the Game Menu header did not get its native color back")
end)

Section("cooldown viewer acquire hooks", function()
    local specs, applies = {}, 0
    local qualityReads = 0
    NS.IconSkin.Apply = function(_, _, spec)
        applies = applies + 1
        specs[spec] = true
        -- The viewer overlay is white frame art: no quality colour to read.
        if spec.nativeQuality ~= false then qualityReads = qualityReads + 1 end
        return {}
    end
    local names = {
        { "BuffBarCooldownViewer", "BuffBarCooldownViewerMixin" },
        { "BuffIconCooldownViewer", "BuffIconCooldownViewerMixin" },
        { "EssentialCooldownViewer", "EssentialCooldownViewerMixin" },
        { "UtilityCooldownViewer", "UtilityCooldownViewerMixin" },
    }
    local viewers = {}
    for index, pair in ipairs(names) do
        local mixin = {}
        function mixin:OnAcquireItemFrame() end
        function mixin:RefreshLayout()
            self.active = {}
            for _, item in ipairs(self.pending) do
                self.active[#self.active + 1] = item
                self:OnAcquireItemFrame(item)
            end
        end
        function mixin:OnShow() end
        _G[pair[2]] = mixin
        local viewer = Frame(pair[1])
        for key, method in pairs(mixin) do viewer[key] = method end
        viewer.active, viewer.pending = {}, {}
        viewer.itemFramePool = {
            EnumerateActive = function()
                local position = 0
                return function()
                    position = position + 1
                    return viewer.active[position]
                end, nil, nil
            end,
        }
        _G[pair[1]] = viewer
        viewers[index] = viewer
    end
    local function IconItem()
        local overlay = {}
        function overlay:GetObjectType() return "Texture" end
        function overlay:GetName() return nil end
        function overlay:GetAtlas() return "UI-HUD-CoolDownManager-IconOverlay" end
        local item = Frame(nil)
        item.Icon = {}
        function item:GetRegions() return overlay end
        return item
    end
    NS.SemanticHUD.Apply("viewers")
    local essential = viewers[3]
    for index = 1, 8 do essential.pending[index] = IconItem() end
    applies = 0
    essential:RefreshLayout()
    Expect(applies == 8, ("a cooldown layout of 8 items took %d icon passes"):format(applies))
    Expect(qualityReads == 0, "cooldown icons took their border colour from the white viewer overlay")
    local count = 0
    for _ in pairs(specs) do count = count + 1 end
    Expect(count == 1, "each cooldown icon pass built its own icon spec")
    -- RefreshLayout acquires the items in a loop: a raising item is reported
    -- and the loop goes on.
    local raisingItem = essential.pending[3]
    NS.IconSkin.Apply = function(button)
        if button == raisingItem then error("contract: cooldown icon raised") end
        applies = applies + 1
        return {}
    end
    applies = 0
    local before = #reported
    local ok = pcall(essential.RefreshLayout, essential)
    Expect(ok and #essential.active == 8 and applies == 7 and #reported == before + 1,
        "a raising cooldown icon stopped Blizzard's RefreshLayout or was not reported")
    NS.SemanticHUD.Disable("viewers")
    for _, pair in ipairs(names) do _G[pair[1]], _G[pair[2]] = nil, nil end
end)

Section("chat color flag", function()
    Load("ChatFrames.lua")
    ChatTypeInfo = {
        SYSTEM = { r = 1, g = 1, b = 0 },
        MONSTER_SAY = { r = 1, g = 1, b = 0.6 },
        MONSTER_PARTY = { r = 0.6, g = 0.6, b = 1 },
    }
    local raiseOnce = true
    function ChangeChatColor(chatType, r, g, b)
        if raiseOnce then
            raiseOnce = false
            error("contract: ChangeChatColor raised")
        end
        local info = ChatTypeInfo[chatType]
        info.r, info.g, info.b = r, g, b
    end
    function FCFTab_UpdateColors() end
    -- Blizzard_ChatFrameBase loads at startup: the dock and CHAT_FRAMES exist.
    GeneralDockManager, CHAT_FRAMES = Frame("GeneralDockManager"), {}
    local chatFrame = Frame("ChatFrame1")
    local tab = Frame("ChatFrame1Tab")
    tab.Text = Text(1, 0.82, 0)
    _G.ChatFrame1, _G.ChatFrame1Tab = chatFrame, tab
    local before = #reported
    local ok = pcall(NS.ChatFramesSkin.Apply, chatFrame, "chat")
    Expect(ok and #reported == before + 1, "a raising chat color change escaped the skin")
    -- The player picks a new system color: it is theirs from now on. A
    -- theme change does not paint over it and a disable does not reset it,
    -- which only holds while the hook still observes changes.
    ChangeChatColor("SYSTEM", 0.2, 0.3, 0.4)
    NS.ChatFramesSkin:OnThemeChanged("color", "blizzardYellow")
    Expect(ChatTypeInfo.SYSTEM.r == 0.2 and ChatTypeInfo.SYSTEM.b == 0.4,
        "a failed color change left later chat color changes ignored")
    -- FCFDock_UpdateTabs repaints every tab in a loop.
    local raisingTab = Frame("ChatFrame2Tab")
    function raisingTab:GetName() error("contract: chat tab raised") end
    before = #reported
    ok = pcall(FCFTab_UpdateColors, raisingTab, true)
    Expect(ok and #reported == before + 1, "a raising chat tab repaint escaped into FCFTab_UpdateColors")
    -- A tab color Blizzard set near ours is Blizzard's: disable keeps it.
    Expect(Near(tab.Text.color[1], 1) and Near(tab.Text.color[2], 1), "the chat tab text was not themed")
    tab.Text:SetTextColor(0.99, 0.99, 0.99)
    NS.ChatFramesSkin.Disable(nil, "chat")
    Expect(Near(tab.Text.color[2], 0.99), "disable overwrote a chat tab color Blizzard had set")
    Expect(ChatTypeInfo.SYSTEM.r == 0.2, "disable reset the system color the player picked")
    ChatTypeInfo, ChangeChatColor, FCFTab_UpdateColors = nil, nil, nil
    GeneralDockManager, CHAT_FRAMES = nil, nil
    _G.ChatFrame1, _G.ChatFrame1Tab = nil, nil
end)

Section("damage meter rows", function()
    Load("DamageMeter.lua")
    NS.DB = { hud = { damageMeterRows = true, damageMeterDetails = true, damageMeterWindows = true } }
    local box = RowBox()
    box.viewReady = false
    function box:HasView() return self.viewReady end
    function box:ForEachFrame(callback)
        assert(self.viewReady, "ForEachFrame reached an uninitialized Blizzard view")
        for _, row in ipairs(self.rows) do callback(row) end
    end
    local window = Frame("DamageMeterSessionWindow1")
    window.MinimizeContainer = { ScrollBox = box }
    window.MinimizeButton = Frame(nil)
    function window:SetMinimized(minimized) self.minimized = minimized end
    local meter = Frame("DamageMeter")
    function meter:ForEachSessionWindow(callback) callback(window) end
    local ok = pcall(NS.DamageMeterSkin.Apply, meter, "meter")
    Expect(ok, "the damage meter walked a ScrollBox before Blizzard built its view")
    local row = Frame(nil)
    row.StatusBar = Frame(nil)
    box:Initialize(row)
    Expect(row.StatusBar.surfaceSpec ~= nil, "an initialized damage meter row was not skinned")
    local syncVisual = NS.WindowActionSkin.SyncNativeVisual
    NS.WindowActionSkin.SyncNativeVisual = function() error("contract: minimize repaint raised") end
    local before = #reported
    local minimized = pcall(window.SetMinimized, window, true)
    NS.WindowActionSkin.SyncNativeVisual = syncVisual
    Expect(minimized and window.minimized == true and #reported == before + 1,
        "a raising minimize repaint escaped into Blizzard's SetMinimized")
    NS.DamageMeterSkin.Disable(nil, "meter")
    Expect(next(box.callbacks) == nil, "the damage meter row callback survived disable")
    NS.DB = nil
end)

-- Session windows the player opens after the skin applied come from
-- DamageMeter:SetupSessionWindow (Blizzard_DamageMeter/DamageMeter.lua:284),
-- which creates the window on first use.
Section("damage meter windows opened later", function()
    Load("DamageMeter.lua")
    NS.DB = { hud = { damageMeterRows = true, damageMeterDetails = true, damageMeterWindows = true } }
    local windows = {}
    local meter = Frame("DamageMeter")
    function meter:ForEachSessionWindow(callback)
        for _, window in ipairs(windows) do callback(window) end
    end
    function meter:SetupSessionWindow(index, windowData)
        if windowData.sessionWindow then return end
        local window = Frame("DamageMeterSessionWindow" .. index)
        window.MinimizeContainer = { ScrollBox = RowBox() }
        window.MinimizeButton = Frame(nil)
        function window:SetMinimized(minimized) self.minimized = minimized end
        windowData.sessionWindow = window
        windows[#windows + 1] = window
    end
    meter:SetupSessionWindow(1, {})
    Expect(NS.DamageMeterSkin.Apply(meter, "meter") and windows[1].surfaceSpec ~= nil,
        "the primary damage meter window was not skinned")
    local second = {}
    meter:SetupSessionWindow(2, second)
    Expect(second.sessionWindow.surfaceSpec ~= nil, "a damage meter window opened after the skin applied stayed unskinned")
    Expect(next(second.sessionWindow.MinimizeContainer.ScrollBox.callbacks) ~= nil,
        "the rows of a damage meter window opened later are not skinned")
    -- In combat the pass waits for the gate; one pass covers every window.
    local deferred = {}
    local runOrDefer = NS.CombatGate.RunOrDefer
    NS.CombatGate.RunOrDefer = function(key, callback) deferred[key] = callback; return false end
    locked = true
    local third = {}
    meter:SetupSessionWindow(3, third)
    locked = false
    NS.CombatGate.RunOrDefer = runOrDefer
    local pass = deferred["damageMeter:windows"]
    Expect(third.sessionWindow.surfaceSpec == nil and pass, "a damage meter window set up in combat was not deferred")
    if pass then pass() end
    Expect(third.sessionWindow.surfaceSpec ~= nil, "the deferred pass did not skin the window set up in combat")
    NS.DamageMeterSkin.Disable(nil, "meter")
    local fourth = {}
    meter:SetupSessionWindow(4, fourth)
    Expect(fourth.sessionWindow.surfaceSpec == nil, "a damage meter window set up after disable was skinned")
    NS.DB = nil
end)

Section("major windows pvp categories", function()
    Load("MajorWindows.lua")
    Load("MajorWindowsItems.lua")
    _G.PVPUIFrame = Frame("PVPUIFrame")
    local queue = Frame("PVPQueueFrame")
    for index = 1, 5 do queue["CategoryButton" .. index] = Frame("CategoryButton" .. index) end
    _G.PVPQueueFrame = queue
    _G.HonorFrame = Frame("HonorFrame")
    _G.LFGListPVPStub = Frame("LFGListPVPStub")
    _G.TrainingGroundsFrame = Frame("TrainingGroundsFrame")
    -- 12.1.5 and Forever name the first Training Grounds button
    -- RandomTrainingGroundBGButton (Blizzard_PVPUI/Mainline/Blizzard_PVPUI.xml:1543).
    local trainingList = Frame("BonusTrainingGroundList")
    trainingList.RandomTrainingGroundBGButton = Frame("RandomTrainingGroundBGButton")
    trainingList.RandomTrainingGroundArenaButton = Frame("RandomTrainingGroundArenaButton")
    _G.TrainingGroundsFrame.BonusTrainingGroundList = trainingList
    local paintedPvP = {}
    local pvpApplyButton = NS.ControlSkin.ApplyButton
    NS.ControlSkin.ApplyButton = function(button) paintedPvP[button] = true; return {} end
    NS.MajorWindows.Apply("major")
    NS.ControlSkin.ApplyButton = pvpApplyButton
    Expect(paintedPvP[trainingList.RandomTrainingGroundBGButton]
        and paintedPvP[trainingList.RandomTrainingGroundArenaButton],
        "the 12.1.5 and Forever Training Grounds battleground button stayed unskinned (P2-2)")
    local indicators = NS.MajorWindows.indicators
    Expect(indicators[queue.CategoryButton1] ~= nil and indicators[queue.CategoryButton3] ~= nil
        and indicators[queue.CategoryButton4] ~= nil,
        "PvP categories after a missing panel lost their selection indicator")
    NS.MajorWindows.Disable("major")
    _G.PVPUIFrame, _G.PVPQueueFrame, _G.HonorFrame = nil, nil, nil
    _G.LFGListPVPStub, _G.TrainingGroundsFrame = nil, nil

    _G.PVPUIFrame = setmetatable({}, { __index = function() error("contract: pvp window raised") end })
    local vault = Frame("WeeklyRewardsFrame")
    _G.WeeklyRewardsFrame = vault
    local before = #reported
    local ok, applied, state = pcall(NS.MajorWindows.Apply, "isolated")
    Expect(ok and applied and state == "partial" and vault.surfaceSpec ~= nil and #reported == before + 1,
        "a raising major window group stopped the other groups or was not reported")
    NS.MajorWindows.Disable("isolated")
    _G.PVPUIFrame, _G.WeeklyRewardsFrame = nil, nil
end)

Section("taxi map semantic artwork", function()
    -- Shared/TaxiFrame.lua on Mainline and Forever paints the actual map into
    -- InsetBg with SetTaxiMap; it is not the decorative inset of other panels.
    local previousCosmetics, previousButton = NS.Cosmetics, NS.ControlSkin.ApplyButton
    local previousAction, previousControls = NS.Checkmarks.GetWindowAction, NS.WindowControls.Attach
    local previousTaxi, previousTrade = _G.TaxiFrame, _G.TradeFrame
    assert(loadfile(skin .. "Core/Cosmetics.lua"))("MSUF_Suite_Skin", NS)
    local function Texture(parent, path)
        local texture = { parent = parent, path = path, alpha = 1, writes = 0 }
        function texture:GetObjectType() return "Texture" end
        function texture:GetParent() return self.parent end
        function texture:GetAlpha() return self.alpha end
        function texture:SetAlpha(value) self.alpha = value; self.writes = self.writes + 1 end
        return texture
    end
    local node = Frame("TaxiButton1")
    function node:GetObjectType() return "Button" end
    node.NormalTexture = Texture(node, "Interface\\TaxiFrame\\UI-Taxi-Icon-White")
    local nativeClick = function() end
    node.OnClick = nativeClick
    local routeMap = Frame("TaxiRouteMap", { node })
    routeMap.Route = Texture(routeMap, "Interface\\TaxiFrame\\UI-Taxi-Line")
    local frame = Frame("TaxiFrame", { routeMap })
    frame.InsetBg = Texture(frame, "native-eastern-kingdoms-map")
    frame.Bg = Texture(frame, "native-window-background")
    frame.CloseButton = Frame("TaxiFrameCloseButton")
    function frame.CloseButton:GetObjectType() return "Button" end
    frame.CloseButton.OnClick = nativeClick
    frame.shown, frame.hooks = false, {}
    function frame:IsShown() return self.shown end
    function frame:HookScript(script, callback) self.hooks[script] = callback end
    NS.ControlSkin.ApplyButton = function(button) button.skinned = true; return {} end
    NS.Checkmarks.GetWindowAction = function(button) return button == frame.CloseButton and "close" or nil end
    NS.WindowControls.Attach = function(target) target.controlsAttached = true end
    _G.TaxiFrame = frame
    local trade = Frame("TradeFrame")
    trade.InsetBg = Texture(trade, "native-decorative-inset")
    _G.TradeFrame = trade
    local entry = NS.BlizzardCatalog.FindByFrame("TaxiFrame")
    local owner = "contract:taxi-map"
    GenericWindows.ApplyEntry(entry, owner)
    Expect(frame.surfaceSpec == nil and frame.InsetBg.writes == 0 and frame.hooks.OnShow,
        "hidden taxi map was skinned before its native opening")
    frame.shown = true
    frame.hooks.OnShow(frame)
    local function CheckMap(stage)
        Expect(frame.InsetBg.alpha == 1 and frame.InsetBg.writes == 0,
            stage .. ": skin erased the native taxi map stored in InsetBg")
        Expect(frame.surfaceSpec and frame.surfaceSpec.fillVisible == false,
            stage .. ": taxi shell lays a material fill over semantic map art")
        Expect(frame.InsetBg.path == "native-eastern-kingdoms-map"
            and routeMap.Route.alpha == 1 and node.NormalTexture.alpha == 1,
            stage .. ": native taxi texture, route or node art changed")
        Expect(node.OnClick == nativeClick and frame.CloseButton.OnClick == nativeClick,
            stage .. ": native taxi or close action changed")
        Expect(frame.CloseButton.skinned and frame.controlsAttached,
            stage .. ": taxi close skin or window controls were lost")
        Expect(routeMap.surfaceSpec == nil and node.surfaceSpec == nil,
            stage .. ": semantic taxi canvas or node gained an extra surface")
    end
    CheckMap("first opening")
    Expect(trade.InsetBg.alpha == 0 and trade.surfaceSpec.fillVisible,
        "taxi exception changed ordinary NPC window inset skinning")
    GenericWindows.ApplyEntry(entry, owner)
    CheckMap("reapply")
    frame.shown = false
    frame.shown = true
    frame.hooks.OnShow(frame)
    CheckMap("reopen")
    GenericWindows.Disable(owner)
    Expect(frame.InsetBg.alpha == 1 and frame.InsetBg.writes == 0 and frame.surfaceVisible == false,
        "disabling the taxi skin changed native map opacity or retained the shell")
    Expect(trade.InsetBg.alpha == 1, "disabling did not restore the ordinary decorative inset")
    GenericWindows.ApplyEntry(entry, owner)
    CheckMap("reenable")
    GenericWindows.Disable(owner)
    _G.TaxiFrame, _G.TradeFrame = previousTaxi, previousTrade
    NS.Cosmetics, NS.ControlSkin.ApplyButton = previousCosmetics, previousButton
    NS.Checkmarks.GetWindowAction, NS.WindowControls.Attach = previousAction, previousControls
end)

Section("prey scouting map", function()
    -- Retail/Forever reuse CovenantMissionFrame for the midnight texture kit.
    -- MapTab, its scroll child and detail tiles use the root's frame level;
    -- a root BACKGROUND fill therefore washes over the semantic map tiles.
    Load("MajorWindows.lua")
    Load("MajorWindowsItems.lua")
    local previousCosmetics = NS.Cosmetics
    assert(loadfile(skin .. "Core/Cosmetics.lua"))("MSUF_Suite_Skin", NS)
    local function Texture(parent, atlas)
        local texture = { parent = parent, atlas = atlas, alpha = 1 }
        function texture:GetObjectType() return "Texture" end
        function texture:GetParent() return self.parent end
        function texture:GetAtlas() return self.atlas end
        function texture:GetAlpha() return self.alpha end
        function texture:SetAlpha(alpha) self.alpha = alpha end
        return texture
    end
    local child = Frame(nil)
    child.TiledBackground = Texture(child, "AdventureMap_TileBg")
    child.Tile = Texture(child, "native-map-tile")
    local pin = Frame(nil)
    pin.Icon = Texture(pin, "AdventureMapIcon-Quest")
    local scroll = Frame(nil, { child, pin })
    scroll.Child = child
    local map = Frame(nil, { scroll })
    map.ScrollContainer = scroll
    local raised = Frame(nil)
    raised.TopEdge = Texture(raised, "native-raised-edge")
    local close = Frame(nil)
    function close:GetObjectType() return "Button" end
    local nativeClick = function() end
    close.OnClick = nativeClick
    local mission = Frame("CovenantMissionFrameMissions")
    local frame = Frame("CovenantMissionFrame", { map, raised, close, mission })
    frame.MapTab, frame.RaisedBorder, frame.CloseButton = map, raised, close
    frame.Border = Texture(frame, "UI-Frame-midnight-Border")
    frame.BackgroundTile = Texture(frame, "Adventures-Missions-BG-02")
    frame.Top, frame.Bottom = Texture(frame), Texture(frame)
    frame.Left, frame.Right = Texture(frame), Texture(frame)
    frame.TopLeftCorner, frame.TopRightCorner = Texture(frame), Texture(frame)
    frame.BotLeftCorner, frame.BotRightCorner = Texture(frame), Texture(frame)
    frame.TopBorder, frame.BottomBorder = Texture(frame), Texture(frame)
    frame.LeftBorder, frame.RightBorder = Texture(frame), Texture(frame)
    frame.OverlayElements = { CloseButtonBorder = Texture(close, "native-close-ring") }
    function frame:UpdateTextures()
        self.Border.atlas = "UI-Frame-" .. (self.textureKit or "midnight") .. "-Border"
        self.Border:SetAlpha(1)
        self.RaisedBorder.TopEdge:SetAlpha(1)
        self.OverlayElements.CloseButtonBorder:SetAlpha(1)
        self.nativeUpdates = (self.nativeUpdates or 0) + 1
    end
    local priorRoot = _G.CovenantMissionFrame
    _G.CovenantMissionFrame = nil
    local previousButton, previousAction = NS.ControlSkin.ApplyButton, NS.Checkmarks.GetWindowAction
    NS.ControlSkin.ApplyButton = function(button) button.controlSkinned = true; return {} end
    NS.Checkmarks.GetWindowAction = function(button) return button == close and "close" or nil end
    local previousLoaded, previousEvents = NS.Client.IsAddOnLoaded, EventUtil
    local onLoaded
    NS.Client.IsAddOnLoaded = function(addon) return addon ~= "Blizzard_GarrisonUI" end
    EventUtil = { ContinueOnAddOnLoaded = function(addon, callback)
        if addon == "Blizzard_GarrisonUI" then onLoaded = callback end
    end }
    NS.MajorWindows.Apply("prey")
    Expect(type(onLoaded) == "function", "scouting skin missed late Blizzard_GarrisonUI loading")
    _G.CovenantMissionFrame = frame
    NS.Client.IsAddOnLoaded, EventUtil = previousLoaded, previousEvents
    if onLoaded then onLoaded() end
    local previousHook, hookCount = hooksecurefunc, 0
    hooksecurefunc = function(target, method, callback)
        if target == frame and method == "UpdateTextures" then hookCount = hookCount + 1 end
        return previousHook(target, method, callback)
    end
    -- A late generic catalog pass must keep the dedicated skin's clear canvas.
    local entry = NS.BlizzardCatalog.FindByFrame("CovenantMissionFrame")
    GenericWindows.ApplyEntry(entry, "prey")
    Expect(frame.surfaceSpec and frame.surfaceSpec.fillVisible == false,
        "late generic catalog pass covered Prey map with a root fill")
    NS.MajorWindows.Apply("prey")
    Expect(frame.surfaceSpec and frame.surfaceSpec.fillVisible == false,
        "Prey map is covered by a generic root material fill")
    Expect(frame.Border.alpha == 0 and raised.TopEdge.alpha == 0
        and frame.OverlayElements.CloseButtonBorder.alpha == 0,
        "Midnight scouting border, raised border or close ring stayed native")
    Expect(frame.Top.alpha == 0 and frame.BotLeftCorner.alpha == 0,
        "legacy scouting corner/edge chrome stayed native")
    Expect(map.surfaceSpec == nil and child.surfaceSpec == nil and pin.surfaceSpec == nil
        and child.Tile.alpha == 1 and child.TiledBackground.alpha == 1 and pin.Icon.alpha == 1,
        "scouting skin changed map art, pins or canvas surfaces")
    Expect(mission.childReads > 0 and close.controlSkinned and close.OnClick == nativeClick,
        "scouting fix removed mission traversal or changed the native close action")
    frame:UpdateTextures()
    Expect(frame.nativeUpdates == 1 and frame.Border.alpha == 0 and raised.TopEdge.alpha == 0
        and frame.OverlayElements.CloseButtonBorder.alpha == 0,
        "native UpdateTextures restored scouting chrome on reopening")
    frame.textureKit = "Dragonflight"
    frame:UpdateTextures()
    Expect(frame.Border.atlas == "UI-Frame-Dragonflight-Border" and frame.Border.alpha == 0,
        "texture-kit switch escaped the scouting skin or changed its native atlas")
    local previousDB = NS.DB
    NS.DB = { skinCategories = { expansion = false } }
    frame:UpdateTextures()
    Expect(frame.Border.alpha == 1, "disabled expansion category was reskinned by the hook")
    NS.DB = previousDB
    local previousDefer, pending = NS.CombatGate.RunOrDefer, nil
    NS.CombatGate.RunOrDefer = function(key, callback)
        if locked and key == "major-windows:scouting-map" then pending = callback; return false end
        return previousDefer(key, callback)
    end
    locked = true
    frame:UpdateTextures()
    Expect(frame.Border.alpha == 0 and pending ~= nil, "safe scouting chrome waited for combat end")
    locked = false
    if pending then pending() end
    Expect(pending ~= nil and frame.Border.alpha == 0,
        "scouting structural completion lost its styling")
    NS.CombatGate.RunOrDefer = previousDefer
    function frame:IsProtected() return true, true end
    frame:UpdateTextures()
    Expect(frame.Border.alpha == 1, "scouting hook decorated an explicitly protected root")
    frame.IsProtected = nil
    NS.MajorWindows.Apply("prey")
    NS.MajorWindows.Disable("prey")
    GenericWindows.Disable("prey")
    Expect(frame.Border.alpha == 1 and frame.Top.alpha == 1 and raised.TopEdge.alpha == 1
        and frame.OverlayElements.CloseButtonBorder.alpha == 1,
        "scouting disable did not restore native chrome")
    local before = counters.attach
    frame:UpdateTextures()
    Expect(frame.Border.alpha == 1 and counters.attach == before,
        "scouting hook kept painting after disable")
    GenericWindows.ApplyEntry(entry, "prey")
    NS.MajorWindows.Apply("prey")
    frame:UpdateTextures()
    Expect(frame.Border.alpha == 0 and frame.surfaceSpec.fillVisible == false,
        "scouting skin failed to re-enable")
    Expect(hookCount == 0, "scouting repaint or re-enable installed a duplicate native hook")
    NS.MajorWindows.Disable("prey")
    GenericWindows.Disable("prey")
    _G.CovenantMissionFrame = priorRoot
    NS.ControlSkin.ApplyButton, NS.Checkmarks.GetWindowAction = previousButton, previousAction
    NS.Cosmetics = previousCosmetics
    hooksecurefunc = previousHook
end)

Section("common art", function()
    Load("CommonArt.lua")
    _G.PVEFrame = Frame("PVEFrame")
    local list = Frame("LFGListFrame")
    _G.LFGListFrame = list
    _G.LFGListCategorySelection_UpdateCategoryButtons = function() end
    NS.CommonArt.Apply("art")
    Expect(list.surfaceSpec == nil, "a missing Group Finder panel path skinned its root instead")
    local card = Frame("LFGListCategoryCard")
    NS.ControlSkin.ApplyButton = function(button)
        if button == card then error("contract: category card raised") end
        return {}
    end
    local before = #reported
    local ok = pcall(_G.LFGListCategorySelection_UpdateCategoryButtons, { CategoryButtons = { card } })
    Expect(ok and #reported == before + 1,
        "a raising category card pass escaped into Blizzard's caller")
    NS.CommonArt.Disable("art")
    _G.PVEFrame, _G.LFGListFrame, _G.LFGListCategorySelection_UpdateCategoryButtons = nil, nil, nil
end)

Section("micro menu", function()
    local visualApplies, relayouts = 0, 0
    local raisePrepare = false
    local bar = Frame("MapkoSkinMicroBar")
    local microNS = setmetatable({
        Client = { isForever = false },
        MicroMenuLoadConditions = {},
        DB = { icons = { microMenu = {
            iconStyle = "bold", tint = "native", layoutMode = "owned",
            buttonBackground = false, buttonBorder = 0, barBackground = false, barBorder = 0,
        } } },
        MicroMenuVisual = {
            Prepare = function()
                if raisePrepare then error("contract: micro button raised") end
                return true
            end,
            Apply = function() visualApplies = visualApplies + 1; return true end,
            Restore = function() return true end,
        },
        OwnedMicroBar = {
            Apply = function() return bar, "owned" end,
            GetFrames = function() return bar end,
            TrackHoverButtons = function() end,
            Relayout = function() relayouts = relayouts + 1; return true end,
            Disable = function() return true end,
            HoverEnter = function() end,
            HoverLeave = function() end,
        },
    }, { __index = NS })
    Load("MicroMenuStates.lua", microNS)
    Load("MicroMenu.lua", microNS)
    Load("MicroMenuSettings.lua", microNS)
    local menu = Frame("MicroMenu")
    _G.MicroMenu = menu
    local container = Frame("MicroMenuContainer")
    function container:Layout() end
    _G.MicroMenuContainer = container
    local buttons = {}
    for index, name in ipairs({ "CharacterMicroButton", "QuestLogMicroButton" }) do
        local button = Frame(name)
        button.shown = true
        function button:GetObjectType() return "Button" end
        function button:GetParent() return menu end
        function button:IsShown() return self.shown end
        function button:HookScript() end
        for _, method in ipairs({ "SetPushed", "SetNormal", "OnEnable", "OnDisable" }) do
            button[method] = function() end
        end
        _G[name] = button
        buttons[index] = button
    end
    local queued = {}
    C_Timer = { After = function(_, callback) queued[#queued + 1] = callback end }
    local skinApi = microNS.MicroMenuSkin
    skinApi.Apply(menu, "micro")
    local applied = visualApplies
    container:Layout()
    table.remove(queued, 1)()
    Expect(visualApplies == applied and relayouts == 0,
        "a layout signal with the same shown buttons re-skinned or re-laid the Micro Bar")
    buttons[2].shown = false
    container:Layout()
    table.remove(queued, 1)()
    Expect(visualApplies == applied and relayouts == 1,
        "a hidden Micro Bar button re-skinned the bar instead of placing its grid again")

    raisePrepare = true
    local ok = pcall(skinApi.RefreshActive)
    raisePrepare = false
    local before = visualApplies
    buttons[1]:SetNormal()
    table.remove(queued, 1)()
    Expect(ok and visualApplies == before + 1,
        "a raising Micro Bar transition left the button hooks silenced")

    -- UpdateMicroButtons walks every button: a raising repaint is reported
    -- and the walk goes on.
    local visualApply = microNS.MicroMenuVisual.Apply
    microNS.MicroMenuVisual.Apply = function(button, ...)
        if button == buttons[1] then error("contract: micro repaint raised") end
        return visualApply(button, ...)
    end
    before = visualApplies
    local reportedBefore = #reported
    ok = pcall(function()
        for _, button in ipairs(buttons) do button:SetNormal() end
        table.remove(queued, 1)()
    end)
    microNS.MicroMenuVisual.Apply = visualApply
    Expect(ok and visualApplies == before + 1 and #reported == reportedBefore + 1,
        "a raising Micro Bar repaint stopped Blizzard's button loop or was not reported")
    skinApi.Disable()
    C_Timer = nil
    _G.MicroMenu, _G.MicroMenuContainer = nil, nil
    _G.CharacterMicroButton, _G.QuestLogMicroButton = nil, nil
end)

-- Blizzard pools filled only by Blizzard: an Acquire outside its own
-- update path counts as one made by our code.
local blizzardAcquiring = false
local addonAcquires = 0
local function CardPool()
    local pool = { active = {}, inactive = {} }
    function pool:Acquire()
        if not blizzardAcquiring then addonAcquires = addonAcquires + 1 end
        local card = table.remove(self.inactive)
        if not card then
            card = Frame(nil)
            card.Background, card.Divider = {}, {}
        end
        self.active[#self.active + 1] = card
        return card
    end
    function pool:Release(card)
        for index, active in ipairs(self.active) do
            if active == card then
                table.remove(self.active, index)
                self.inactive[#self.inactive + 1] = card
                return
            end
        end
    end
    function pool:ReleaseAll()
        for index = #self.active, 1, -1 do self:Release(self.active[index]) end
    end
    function pool:GetNumActive() return #self.active end
    function pool:EnumerateActive()
        local index = 0
        return function()
            index = index + 1
            return self.active[index]
        end
    end
    function pool:GetNextActive(current)
        if current == nil then return self.active[1] end
        for index, active in ipairs(self.active) do
            if active == current then return self.active[index + 1] end
        end
        return nil
    end
    return pool
end

local function BlizzardFill(pool, count)
    blizzardAcquiring = true
    pool:ReleaseAll()
    for _ = 1, count do pool:Acquire() end
    blizzardAcquiring = false
end

Section("encounter journal journey cards", function()
    Load("EncounterJournal.lua")
    NS.ControlSkin.ApplyTab = function() return {} end
    local journal = Frame("EncounterJournal")
    local journeys = Frame(nil)
    local progress = Frame(nil)
    progress.rewardPool = CardPool()
    function progress:SetRewards() BlizzardFill(self.rewardPool, 2) end
    local highlights = Frame(nil)
    highlights.highlightPool = CardPool()
    function highlights:DisplayHighlights() BlizzardFill(self.highlightPool, 3) end
    local overview = Frame(nil)
    overview.Highlights = highlights
    journeys.JourneyProgress, journeys.JourneyOverview = progress, overview
    journal.JourneysFrame = journeys
    addonAcquires = 0
    NS.EncounterJournalSkin.Apply(journal, "journeys")
    Expect(addonAcquires == 0, "the Encounter Journal acquired Blizzard pool frames from addon code")
    progress:SetRewards()
    highlights:DisplayHighlights()
    Expect(progress.rewardPool.active[2].surfaceSpec ~= nil
        and highlights.highlightPool.active[3].surfaceSpec ~= nil,
        "journey cards Blizzard acquired were not skinned")
    NS.EncounterJournalSkin.Disable(journal, "journeys")
end)

Section("housing reward cards", function()
    Load("MajorWindows.lua")
    Load("MajorWindowsItems.lua")
    local upgrade = Frame(nil)
    upgrade.rewardPoolLarge, upgrade.rewardPoolSmall = CardPool(), CardPool()
    upgrade.RewardsFrame = Frame(nil)
    upgrade.houseLevelRewardInfos = { { rewards = { 1, 2, 3 } }, { rewards = { 1, 2, 3, 4, 5, 6 } } }
    function upgrade:AllRewardsLoaded() return true end
    function upgrade:SetRewards() BlizzardFill(self.rewardPoolLarge, 3) end
    local dashboard = Frame("HousingDashboardFrame")
    dashboard.HouseInfoContent = { ContentFrame = { HouseUpgradeFrame = upgrade } }
    _G.HousingDashboardFrame = dashboard
    addonAcquires = 0
    NS.MajorWindows.Apply("housing")
    Expect(addonAcquires == 0, "the housing dashboard acquired Blizzard pool frames from addon code")
    upgrade:SetRewards()
    Expect(upgrade.rewardPoolLarge.active[1].surfaceSpec ~= nil
        and upgrade.rewardPoolLarge.active[3].surfaceSpec ~= nil,
        "housing reward cards Blizzard acquired were not skinned")
    NS.MajorWindows.Disable("housing")
    _G.HousingDashboardFrame = nil
end)

Section("micro menu tint read-back", function()
    local previousTimer, queued = C_Timer, {}
    C_Timer = { After = function(_, callback) queued[#queued + 1] = callback end }
    -- Vertex colors read back at 8-bit precision.
    local function Quantize(value) return math.floor(value * 255 + 0.5) / 255 end
    local icon = { r = 1, g = 1, b = 1, a = 1 }
    function icon:GetVertexColor() return self.r, self.g, self.b, self.a end
    function icon:SetVertexColor(r, g, b, a)
        self.r, self.g, self.b, self.a = Quantize(r), Quantize(g), Quantize(b), Quantize(a or 1)
    end
    local bar = Frame("MapkoSkinMicroBar")
    local function Yes() return true end
    local microNS = setmetatable({
        Client = { isForever = false },
        MicroMenuLoadConditions = {},
        DB = { icons = { microMenu = {
            iconStyle = "blizzardIcons", tint = "native", normalOpacity = 0.5, layoutMode = "owned",
            buttonBackground = false, buttonBorder = 0, barBackground = false, barBorder = 0,
        } } },
        MicroMenuVisual = { Prepare = Yes, Apply = Yes, Restore = Yes },
        OwnedMicroBar = {
            Apply = function() return bar, "owned" end,
            GetFrames = function() return bar end,
            TrackHoverButtons = function() end,
            Relayout = Yes,
            Disable = Yes,
            HoverEnter = function() end,
            HoverLeave = function() end,
        },
    }, { __index = NS })
    Load("MicroMenuStates.lua", microNS)
    Load("MicroMenu.lua", microNS)
    Load("MicroMenuSettings.lua", microNS)
    local menu = Frame("MicroMenu")
    local container = Frame("MicroMenuContainer")
    function container:Layout() end
    local button = Frame("CharacterMicroButton")
    function button:GetObjectType() return "Button" end
    function button:GetParent() return menu end
    function button:IsShown() return true end
    function button:HookScript() end
    function button:GetNormalTexture() return icon end
    for _, method in ipairs({ "SetPushed", "SetNormal", "OnEnable", "OnDisable" }) do
        button[method] = function() end
    end
    _G.MicroMenu, _G.MicroMenuContainer, _G.CharacterMicroButton = menu, container, button
    microNS.MicroMenuSkin.Apply(menu, "tint")
    Expect(Near(icon.a, 0.5), "the Blizzard micro icon did not take its opacity")
    for _ = 1, 3 do button:SetNormal() end
    table.remove(queued, 1)()
    Expect(Near(icon.a, 0.5), ("state hooks compounded the micro icon opacity to %.3f"):format(icon.a))
    microNS.MicroMenuSkin.Disable()
    Expect(Near(icon.a, 1), "disable did not give the micro icon its native color back")
    -- Monochrome icon colors also desaturate the native icon (the settings of
    -- the pass, MicroMenuStates.ApplyTextureTint); disable restores it.
    icon.desaturated = false
    function icon:IsDesaturated() return self.desaturated end
    function icon:SetDesaturated(value) self.desaturated = value end
    microNS.DB.icons.microMenu.tint = "monochrome"
    microNS.MicroMenuSkin.Apply(menu, "tint")
    Expect(icon.desaturated == true, "a monochrome Micro Bar did not desaturate the Blizzard icon")
    button:SetNormal()
    table.remove(queued, 1)()
    Expect(icon.desaturated == true, "a state hook dropped the monochrome desaturation")
    microNS.MicroMenuSkin.Disable()
    Expect(icon.desaturated == false, "disable did not give the micro icon its native saturation back")
    _G.MicroMenu, _G.MicroMenuContainer, _G.CharacterMicroButton = nil, nil, nil
    C_Timer = previousTimer
end)

Section("static popup hooks", function()
    -- SharedXML button handlers every client has; the adapter post-hooks them.
    _G.UIPanelButton_OnShow = function() end
    _G.UIPanelCloseButton_SetBorderAtlas = function() end
    local popup = Frame("StaticPopup1")
    popup.CloseButton = Frame(nil)
    function popup:SetupButtons() end
    function popup:SetupCloseButton() self.closeSetup = true end
    _G.StaticPopup1 = popup
    local popupNS = setmetatable({ DB = {} }, { __index = NS })
    Load("UIPanelButtons.lua", popupNS)
    popupNS.UIPanelButtons.active = true
    local adopt = NS.WindowActionSkin.AdoptNativeVisual
    NS.WindowActionSkin.AdoptNativeVisual = function() error("contract: popup close raised") end
    local before = #reported
    local ok = pcall(popup.SetupCloseButton, popup, { closeButton = true })
    NS.WindowActionSkin.AdoptNativeVisual = adopt
    Expect(ok and popup.closeSetup and #reported == before + 1,
        "a raising popup skin escaped into Blizzard's StaticPopup setup")
    popupNS.UIPanelButtons.active = false
    _G.StaticPopup1, _G.UIPanelButton_OnShow, _G.UIPanelCloseButton_SetBorderAtlas = nil, nil, nil
end)

Section("owned micro bar", function()
    local previousTimer, queued = C_Timer, {}
    C_Timer = { After = function(_, callback) queued[#queued + 1] = callback end }
    -- Retail and Forever scale MicroMenu by this game rule (0: no factor).
    C_GameRules = { GetGameRuleAsFloat = function() return 0 end }
    Enum = Enum or {}
    Enum.GameRule = Enum.GameRule or { MicrobarScale = 1 }
    -- Widgets with the frame and texture methods the owned bar calls.
    local placements = {}
    local function Noop() end
    local Widget
    local widgetMethods = {
        "SetAllPoints", "EnableMouse", "SetFrameLevel", "SetSize", "SetMovable",
        "SetClampedToScreen", "Hide", "Show", "SetShown", "SetFrameStrata", "RegisterForDrag",
        "RegisterEvent", "RegisterUnitEvent", "UnregisterEvent", "SetAlpha", "ClearAllPoints",
        "SetScale", "SetOverrideScale", "StartMoving", "StopMovingOrSizing", "AddMaskTexture",
        "SetTexture", "SetDesaturated", "SetVertexColor", "SetColorTexture", "SetHeight",
        "SetText", "ResetMicroMenuPosition", "OverrideMicroMenuPosition",
    }
    Widget = function(name, parent)
        local widget = { name = name, parent = parent, scripts = {}, alpha = 1 }
        for _, method in ipairs(widgetMethods) do widget[method] = Noop end
        function widget:GetName() return self.name end
        function widget:GetObjectType() return "Frame" end
        function widget:GetParent() return self.parent end
        function widget:SetParent(newParent) self.parent = newParent end
        function widget:GetFrameLevel() return 0 end
        function widget:IsShown() return true end
        function widget:GetAlpha() return self.alpha end
        function widget:SetAlpha(alpha) self.alpha = alpha end
        function widget:SetPoint() placements[self] = (placements[self] or 0) + 1 end
        function widget:SetScript(script, callback) self.scripts[script] = callback end
        function widget:HookScript(script, callback) self.scripts[script] = callback end
        function widget:CreateTexture() return Widget() end
        function widget:CreateMaskTexture() return Widget() end
        function widget:CreateFontString() return Widget() end
        return widget
    end

    local surfaces, attaches, prepares = {}, 0, 0
    local microNS = setmetatable({
        Client = { isForever = false, SupportsEvent = function() return true end },
        MicroMenuLoadConditions = {},
        DB = { icons = { microMenu = {
            iconStyle = "blizzardIcons", tint = "native", layoutMode = "owned", locked = true,
            buttonBackground = true, buttonBorder = 1, barBackground = false, barBorder = 0,
        } } },
        MicroMenuVisual = {
            Prepare = function() prepares = prepares + 1; return true end,
            Apply = function() return true end,
            Restore = function() return true end,
        },
        Registry = {
            GetSurface = function(target) return surfaces[target] end,
            AddListener = function() end,
            RemoveListener = function() end,
        },
        Surface = {
            Attach = function(target, spec)
                attaches = attaches + 1
                local surface = surfaces[target] or {}
                surface.spec, surface.visible = spec, true
                surfaces[target] = surface
                return surface
            end,
            SetVisible = function(target, visible)
                if surfaces[target] then surfaces[target].visible = visible end
                return true
            end,
        },
    }, { __index = NS })

    local createFrame, uiParent = CreateFrame, UIParent
    local created = {}
    CreateFrame = function(_, name, parent)
        local widget = Widget(name, parent)
        created[#created + 1] = widget
        return widget
    end
    UIParent = Widget("UIParent")
    -- Retail and Forever keep MicroMenu's frame level when reparenting it.
    local frameUtil = FrameUtil
    FrameUtil = { SetParentMaintainRenderLayering = function(frame, parent) frame:SetParent(parent) end }
    for _, file in ipairs({ "OwnedMicroBarLayout.lua", "OwnedMicroBarVisibility.lua", "OwnedMicroBarEditMode.lua",
        "OwnedMicroBar.lua" }) do
        Load(file, microNS)
    end
    local eventFrame = created[1]
    Load("MicroMenuStates.lua", microNS)
    Load("MicroMenu.lua", microNS)
    Load("MicroMenuSettings.lua", microNS)

    local container = Widget("MicroMenuContainer")
    function container:Layout() end
    local root = Widget("MicroMenu", container)
    function root:Layout() end
    _G.MicroMenu, _G.MicroMenuContainer = root, container
    local buttons = {}
    for index, name in ipairs({ "CharacterMicroButton", "QuestLogMicroButton" }) do
        local button = Widget(name, root)
        function button:GetObjectType() return "Button" end
        for _, method in ipairs({ "SetPushed", "SetNormal", "OnEnable", "OnDisable" }) do
            button[method] = Noop
        end
        button.Background, button.PushedBackground = Widget(), Widget()
        _G[name] = button
        buttons[index] = button
    end
    function root:GetChildren() return buttons[1], buttons[2] end
    -- Blizzard_HelpFrame creates the help ticket button at startup on every client.
    local help = Widget("HelpOpenWebTicketButton")
    local helpPoint
    function help:SetPoint(...) helpPoint = { ... } end
    _G.HelpOpenWebTicketButton = help

    local skinApi = microNS.MicroMenuSkin
    skinApi.Apply(root, "owned")
    local bar = microNS.OwnedMicroBar.GetFrames()
    Expect(root.parent == bar and prepares == 2, "the owned Micro Bar did not take the menu")

    -- A native state hook keeps the plate the full pass attached.
    attaches = 0
    buttons[1]:SetPushed()
    table.remove(queued, 1)()
    Expect(attaches == 0, "a Micro Bar state hook built and attached a new button plate")

    -- Combat end with nothing deferred keeps the bar where it is: combat
    -- moved nothing (suite_skin_micro_bar_combat_end_contract.lua).
    attaches, prepares = 0, 0
    for widget in pairs(placements) do placements[widget] = nil end
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_REGEN_ENABLED")
    Expect(prepares == 0 and attaches == 0 and next(placements) == nil,
        "combat end with nothing deferred placed or re-skinned the owned Micro Bar")
    -- A loading screen or a pet battle only place the bar again.
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PET_BATTLE_CLOSE" }) do
        eventFrame.scripts.OnEvent(eventFrame, event)
    end
    Expect(prepares == 0 and attaches == 0,
        "a loading screen re-skinned the owned Micro Bar instead of placing it again")
    Expect((placements[bar] or 0) > 0 and (placements[root] or 0) > 0,
        "a loading screen did not place the owned Micro Bar again")
    -- Once Blizzard has taken the menu back, the bar takes it and skins it again.
    root.parent = container
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
    Expect(root.parent == bar and prepares == 2, "the owned Micro Bar did not take the menu back")

    -- MicroMenu:Layout runs inside Blizzard's calls: a raising grid pass is
    -- reported and Blizzard's caller goes on.
    function root:ClearAllPoints() error("contract: owned grid raised") end
    local before = #reported
    local ok = pcall(root.Layout, root)
    root.ClearAllPoints = Noop
    Expect(ok and #reported == before + 1, "a raising owned grid pass escaped into MicroMenu:Layout")

    -- On Retail (MicroMenuPositionEnum) the help ticket button follows the
    -- screen quadrant of the owned bar, not the saved anchor (bottom right
    -- by default): with the bar in the top left it sits below the left edge
    -- button.
    _G.MicroMenuPositionEnum = {}
    buttons[1].layoutIndex, buttons[2].layoutIndex = 1, 2
    buttons[1].GetCenter = function() return 10, 10 end
    buttons[2].GetCenter = function() return 50, 10 end
    function bar:GetCenter() return 100, 700 end
    function UIParent:GetCenter() return 500, 400 end
    Expect(microNS.OwnedMicroBar.Relayout(root) and helpPoint and helpPoint[2] == buttons[2]
        and helpPoint[5] == -25, "the help ticket button did not follow the owned bar's quadrant")
    _G.HelpOpenWebTicketButton, _G.MicroMenuPositionEnum = nil, nil

    skinApi.Disable()
    CreateFrame, UIParent, FrameUtil = createFrame, uiParent, frameUtil
    C_Timer = previousTimer
    _G.MicroMenu, _G.MicroMenuContainer = nil, nil
    _G.CharacterMicroButton, _G.QuestLogMicroButton = nil, nil
end)

Section("world map", function()
    Load("WorldMapQuests.lua")
    Load("WorldMap.lua")
    local calls, restore = CountingApplyFrame()
    local navSkins = 0
    local applyButton = NS.ControlSkin.ApplyButton
    NS.ControlSkin.ApplyButton = function()
        navSkins = navSkins + 1
        return {}
    end
    -- QuestMapFrame.QuestsFrame.ScrollFrame (QuestScrollFrame) owns the row
    -- pools; QuestLogQuests_Update releases and refills them.
    local contents = Frame(nil)
    local scroll = Frame("QuestScrollFrame", { contents })
    local quests = Frame(nil, { scroll })
    quests.ScrollFrame = scroll
    local questLog = Frame("QuestMapFrame", { quests })
    questLog.QuestsFrame = quests
    function contents:GetParent() return scroll end
    function scroll:GetParent() return quests end
    function quests:GetParent() return questLog end
    local activeRows = {}
    scroll.titleFramePool = {
        EnumerateActive = function() return pairs(activeRows) end,
    }
    local function AcquireRow()
        local row = Frame(nil)
        function row:GetObjectType() return "Button" end
        function row:GetFontString() return {} end
        function row:GetParent() return contents end
        contents.children[#contents.children + 1] = row
        activeRows[row] = true
        return row
    end
    local rowAttaches = {}
    local countingAttach = NS.Surface.Attach
    NS.Surface.Attach = function(target, ...)
        rowAttaches[target] = (rowAttaches[target] or 0) + 1
        return countingAttach(target, ...)
    end
    local function Outlined(row)
        return row.surfaceSpec ~= nil and row.surfaceSpec.role == "button"
    end
    _G.QuestLogQuests_Update = function() end
    local firstRow = AcquireRow()
    local map = Frame("WorldMapFrame")
    map.visible = true
    function map:IsVisible() return self.visible end
    map.QuestLog = questLog
    map.NavBar = Frame(nil)
    map.NavBar.navList = { Frame("HomeButton") }
    NS.WorldMapSkin.Apply(map, "map")
    Expect(calls[questLog] == 1, "the world map quest log was not skinned")
    Expect(Outlined(firstRow), "a quest log row did not get its hover outline")
    -- Opening the map again keeps what this skin generation applied; the
    -- navigation bar, which the new map can rebuild, is refreshed.
    navSkins = 0
    NS.WorldMapSkin:OnWorldMapShown()
    Expect(calls[questLog] == 1 and navSkins == 1,
        "reopening the world map repeated its full pass or skipped the navigation bar")

    -- QuestLogQuests_Update repaints reused titles in Blizzard's gold; the
    -- skin's yellow follows on every update, not only on the first pass.
    yellowFrames = {}
    _G.QuestLogQuests_Update()
    Expect(yellowFrames[firstRow] == true, "a reused quest row kept Blizzard's gold after an update")
    yellowFrames = nil

    -- While the map is closed, Blizzard's quest log update acquires a row its
    -- pool had to create; it has its outline once the map opens again.
    local closedRow = AcquireRow()
    local firstAttaches = rowAttaches[firstRow]
    map.visible = false
    _G.QuestLogQuests_Update()
    Expect(not Outlined(closedRow), "a hidden map skinned a new quest row")
    map.visible = true
    NS.WorldMapSkin:OnWorldMapShown()
    Expect(Outlined(closedRow), "a quest row created while the map was closed had no outline after reopening")
    Expect(rowAttaches[firstRow] == firstAttaches and calls[questLog] == 1,
        "a quest log update skinned known rows again or repeated the full pass")
    -- A row acquired in combat, when the update hook stays quiet, takes its
    -- pass on the next opening.
    local combatRow = AcquireRow()
    locked = true
    _G.QuestLogQuests_Update()
    locked = false
    Expect(not Outlined(combatRow), "a quest row was skinned in combat")
    NS.WorldMapSkin:OnWorldMapShown()
    Expect(Outlined(combatRow), "a quest row acquired in combat had no outline after reopening")
    -- The update hook runs inside Blizzard's call: a raising row is reported.
    local raisingRow = AcquireRow()
    function raisingRow:GetObjectType() error("contract: quest row raised") end
    local before = #reported
    local updated = pcall(_G.QuestLogQuests_Update)
    activeRows[raisingRow] = nil
    table.remove(contents.children)
    Expect(updated and #reported == before + 1, "a raising quest row escaped into QuestLogQuests_Update")
    NS.Surface.Attach = countingAttach

    for owner, callback in pairs(listeners) do callback(owner, "theme", "look") end
    NS.WorldMapSkin:OnWorldMapShown()
    Expect(calls[questLog] == 2, "a look change did not give the reopened world map a pass")

    -- The quest log's display-mode refresh builds no field lists.
    restore()
    local applyFrame, attach, staticSurface = GenericWindows.ApplyFrame, NS.Surface.Attach, { spec = {} }
    GenericWindows.ApplyFrame = function() return true end
    NS.Surface.Attach = function() return staticSurface end
    NS.WorldMapSkin:OnQuestLogModeChanged()
    collectgarbage("collect")
    collectgarbage("stop")
    local memory = collectgarbage("count")
    for _ = 1, 200 do NS.WorldMapSkin:OnQuestLogModeChanged() end
    local grown = collectgarbage("count") - memory
    collectgarbage("restart")
    GenericWindows.ApplyFrame, NS.Surface.Attach = applyFrame, attach
    Expect(grown < 1, ("the quest log refresh allocated %.1f KB for 200 passes"):format(grown))

    -- Rows the quest log pass did not reach (beyond its depth, or past its
    -- node limit) are not taken for skinned: the next update skins them.
    -- Frames whose GetParent follows their children lists.
    local function Linked(frame)
        for _, child in ipairs(frame.children) do
            function child:GetParent() return frame end
            Linked(child)
        end
        return frame
    end
    local function QuestMap(name, rowParent, row)
        local mapRows = { [row] = true }
        local mapScroll = Frame(name .. "Scroll", { rowParent })
        mapScroll.titleFramePool = { EnumerateActive = function() return pairs(mapRows) end }
        local mapQuests = Frame(nil, { mapScroll })
        mapQuests.ScrollFrame = mapScroll
        local mapLog = Linked(Frame(name .. "QuestLog", { mapQuests }))
        mapLog.QuestsFrame = mapQuests
        local mapFrame = Frame(name)
        function mapFrame:IsVisible() return true end
        mapFrame.QuestLog = mapLog
        return mapFrame
    end
    local function QuestRow()
        local row = Frame(nil)
        function row:GetObjectType() return "Button" end
        function row:GetFontString() return {} end
        return row
    end
    local deepRow = QuestRow()
    local deepMap = QuestMap("ContractDeepMap",
        Frame(nil, { Frame(nil, { Frame(nil, { Frame(nil, { deepRow }) }) }) }), deepRow)
    NS.WorldMapSkin.Apply(deepMap, "deep-map")
    local wideRow = QuestRow()
    local fillers = {}
    for index = 1, 430 do fillers[index] = Frame(nil) end
    fillers[#fillers + 1] = wideRow
    local wideMap = QuestMap("ContractWideMap", Frame(nil, fillers), wideRow)
    NS.WorldMapSkin.Apply(wideMap, "wide-map")
    _G.QuestLogQuests_Update()
    Expect(Outlined(deepRow), "a quest row beyond the quest log pass's depth was taken for skinned")
    Expect(Outlined(wideRow), "a quest row past the quest log pass's node limit was taken for skinned")
    NS.WorldMapSkin.Disable(deepMap, "deep-map")
    NS.WorldMapSkin.Disable(wideMap, "wide-map")
    NS.WorldMapSkin.Disable(map, "map")
    NS.ControlSkin.ApplyButton = applyButton
    _G.QuestLogQuests_Update = nil
end)

Section("communities column layout", function()
    Load("Communities.lua")
    NS.Checkmarks.TrackControlTree = function() end
    -- Blizzard_Communities loads at startup; its mixin names the frame events.
    CommunitiesFrameMixin = { Event = { DisplayModeChanged = "DisplayModeChanged", ClubSelected = "ClubSelected" } }
    local communities = Frame("CommunitiesFrame")
    local columns = Frame(nil)
    function columns:LayoutColumns() end
    local raise = false
    columns.columnHeaders = {
        EnumerateActive = function()
            if raise then error("contract: column headers raised") end
            return function() end
        end,
    }
    communities.MemberList = Frame(nil)
    communities.MemberList.ColumnDisplay = columns
    NS.CommunitiesSkin.Apply(communities, "communities")
    raise = true
    local before = #reported
    local ok = pcall(columns.LayoutColumns, columns)
    raise = false
    Expect(ok and #reported == before + 1,
        "a raising column header pass escaped into Blizzard's LayoutColumns")
    -- Another owner takes the frame over: the first owner's skin comes off
    -- with that owner's records.
    local restoreOwner, restored = NS.Cosmetics.RestoreOwner, {}
    NS.Cosmetics.RestoreOwner = function(owner) restored[#restored + 1] = owner end
    NS.CommunitiesSkin.Apply(communities, "communities-other")
    Expect(restored[1] == "communities" and NS.CommunitiesSkin.states[communities].owner == "communities-other",
        "a new Communities owner did not take the previous owner's skin off")
    NS.CommunitiesSkin.Disable(communities, "communities-other")
    NS.Cosmetics.RestoreOwner = restoreOwner
    NS.Checkmarks.TrackControlTree = nil
    CommunitiesFrameMixin = nil
end)

Section("generic traversal secrets", function()
    -- 12.x getters return secrets; comparing one raises in the client.
    local secretMeta = { __eq = function() error("contract: compared a secret value") end }
    local secretParent = setmetatable({ secret = true }, secretMeta)
    local uiParent = setmetatable(Frame("UIParent"), secretMeta)
    local isSecret, previousParent = issecretvalue, UIParent
    issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    UIParent = uiParent
    local secretChild = setmetatable({ secret = true, reads = 0 }, {
        __index = function(child, key)
            rawset(child, "reads", rawget(child, "reads") + 1)
            return nil
        end,
    })
    local window = Frame("ContractSecretWindow")
    function window:GetParent() return secretParent end
    local ok, applied = pcall(GenericWindows.ApplyFrame, window, "secrets", MODE)
    Expect(ok and applied, "a window with a secret parent was compared or not skinned")
    local parentWindow = Frame("ContractSecretChildren", { secretChild })
    ok, applied = pcall(GenericWindows.ApplyFrame, parentWindow, "secrets", MODE)
    local child = Frame("ContractSecretParentChild")
    function child:GetParent() return secretParent end
    local parentChecked, isParent = pcall(Kit.ParentIs, child, uiParent)
    local descendantChecked, isDescendant = pcall(Kit.IsDescendantOf, child, uiParent, 4)
    issecretvalue, UIParent = isSecret, previousParent
    Expect(ok and applied and rawget(secretChild, "reads") == 0, "the traversal read a secret child")
    Expect(parentChecked and not isParent and descendantChecked and not isDescendant,
        "the adapter kit compared a secret parent")
    GenericWindows.Disable("secrets")
end)

Section("traversal tracks each button once", function()
    -- A parent's Checkmarks child pass tracks every child button, so each
    -- node but the root of a pass skips its own button tracking.
    local tracked, trackFrame = {}, NS.Checkmarks.TrackFrame
    NS.Checkmarks.TrackFrame = function(frame, _, buttonTracked)
        tracked[frame] = buttonTracked == true
    end
    local grandchild = Frame(nil)
    local child = Frame(nil, { grandchild })
    local sibling = Frame(nil)
    local window = Frame("ContractTrackOnceWindow", { child, sibling })
    GenericWindows.ApplyFrame(window, "track-once", MODE)
    Expect(tracked[window] == false and tracked[child] == true and tracked[sibling] == true
        and tracked[grandchild] == true, "a frame pass tracked a child button twice or skipped its root")
    tracked = {}
    GenericWindows.ApplyDescendant(child, "track-once", MODE)
    Expect(tracked[child] == false and tracked[grandchild] == true,
        "a descendant pass skipped the button of its own root")
    local pooledMode = { maxDepth = 3, maxNodes = 16 }
    function child:IsProtected() return self.protected == true, false end
    locked = true
    tracked = {}
    Expect(GenericWindows.ApplyDescendant(child, "track-once", pooledMode) and tracked[child] == false,
        "safe native pooled descendant could not initialize during combat")
    tracked = {}
    Expect(GenericWindows.RefreshDescendant(child, "track-once", pooledMode) and tracked[child] ~= nil,
        "safe native pooled descendant lost its combat recolor")
    child.protected = true
    tracked = {}
    Expect(not GenericWindows.ApplyDescendant(child, "track-once", pooledMode)
        and not GenericWindows.RefreshDescendant(child, "track-once", pooledMode) and next(tracked) == nil,
        "protected descendant entered combat styling")
    child.protected = false
    child.IsVisible = function() return false end
    Expect(not GenericWindows.ApplyDescendant(child, "track-once", pooledMode)
        and not GenericWindows.RefreshDescendant(child, "track-once", pooledMode), "hidden descendant performed combat work")
    child.IsVisible = nil
    locked = false
    NS.Checkmarks.TrackFrame = trackFrame
    GenericWindows.Disable("track-once")
end)

Section("supported clients and shared helpers", function()
    -- The Suite supports Retail and Forever, which both load the Mainline TOC.
    local toc = ReadSource(skin .. "MSUF_Suite_Skin_Mainline.toc")
    Expect(not toc:find("ClientWindows", 1, true) and io.open(skin .. "Adapters/ClientWindows.lua") == nil,
        "the Classic-only client window adapter is still shipped")
    local chromeAt = toc:find("Adapters\\PaperDollChrome.lua", 1, true)
    local panelAt = toc:find("Adapters\\CharacterPanel.lua", 1, true)
    local inspectAt = toc:find("Adapters\\InspectPanel.lua", 1, true)
    Expect(chromeAt and panelAt and inspectAt and chromeAt < panelAt and chromeAt < inspectAt,
        "PaperDollChrome must load before both PaperDoll panels")
    for _, file in ipairs({ "UIPanelButtons", "SemanticHUD", "EquipmentInfo", "CharacterDetails",
        "CharacterStats", "EQoLCharacter", "CharacterPanel", "ChatFrames", "DamageMeter",
        "EditMode", "MacroWindow", "MicroMenu", "MicroMenuStates", "OwnedMicroBar" }) do
        local source = ReadSource(skin .. "Adapters/" .. file .. ".lua")
        Expect(not source:find("local function HasMethod", 1, true)
            and not source:find("local function Accessible", 1, true)
            and not source:find("local function Read(", 1, true)
            and not source:find("local function ReadAlpha", 1, true)
            and not source:find("local function ReadVertex", 1, true)
            and not source:find("local function PublicCall", 1, true)
            and not source:find("local function IsSecret", 1, true),
            file .. " keeps its own copy of a Safety reader")
    end
    Expect(Kit.ReadMethod == nil, "the unused AdapterKit.ReadMethod is still shipped")
    -- Colour comparisons use Safety.SameColor with its shared tolerances.
    for _, file in ipairs({ "QuestText", "EncounterJournal", "ChatFrames", "SharedChrome",
        "AdapterKit" }) do
        local source = ReadSource(skin .. "Adapters/" .. file .. ".lua")
        Expect(not source:find("COLOR_TOLERANCE", 1, true) and not source:find("math.abs", 1, true),
            file .. " keeps its own colour tolerance")
    end
    for _, file in ipairs({ "MicroMenu", "MicroMenuStates", "OwnedMicroBar", "SharedChrome", "AdapterKit" }) do
        Expect(not ReadSource(skin .. "Adapters/" .. file .. ".lua"):find('Call%(%s*[%w_]+,%s*"GetParent"%)'),
            file .. " compares a GetParent result that can be secret")
    end
    -- Stored-colour checks go through the secret-safe Safety.ColorMatches.
    for _, file in ipairs({ "ChatFrames", "QuestText", "AdapterKit", "MicroMenuStates" }) do
        local source = ReadSource(skin .. "Adapters/" .. file .. ".lua")
        Expect(source:find("Safety.ColorMatches", 1, true) ~= nil
            and not source:find("local function SameRGB", 1, true)
            and not source:find("local function ShowsColor", 1, true)
            and not source:find("local function MatchesColor", 1, true)
            and not source:find("local function SameVertex", 1, true),
            file .. " keeps its own colour-match wrapper")
    end
    local microSource = ReadSource(skin .. "Adapters/MicroMenu.lua")
    Expect(not microSource:find("Blizzard keeps ownership of\n-- layout", 1, true)
        and microSource:find("OwnedMicroBar takes the whole MicroMenu", 1, true),
        "the Micro Menu header still says Blizzard owns the layout")
    -- GenericWindows is split into cohesive files in load order.
    local previousAt = 0
    for _, file in ipairs({ "GenericWindows", "GenericWindowsNodes", "GenericWindowsFrames", "GenericWindowsCatalog" }) do
        local at = toc:find("Adapters\\" .. file .. ".lua", 1, true)
        Expect(at and at > previousAt, file .. " is missing from the TOC or out of order")
        previousAt = at or previousAt
        local handle = io.open(skin .. "Adapters/" .. file .. ".lua", "rb")
        local lines = 0
        if handle then
            for _ in handle:read("*a"):gmatch("\n") do lines = lines + 1 end
            handle:close()
        end
        Expect(lines > 0 and lines < 900, file .. (" has %d lines"):format(lines))
    end
end)

-- Split adapters load after the file they build on, and every code file stays
-- below 900 lines (Catalog.lua is the reviewed data table). Retail and Forever
-- APIs are called without existence checks.
Section("adapter file structure", function()
    local toc = ReadSource(skin .. "MSUF_Suite_Skin_Mainline.toc")
    local order = {}
    for file in toc:gmatch("Adapters\\([%w_]+)%.lua") do order[#order + 1] = file end
    local position = {}
    for index, file in ipairs(order) do position[file] = index end
    for _, chain in ipairs({
        { "Catalog", "CatalogGlass", "AdapterKit", "SharedChrome" },
        { "DeepWindows", "DeepWindowsProfessions" },
        { "OwnedMicroBarLayout", "OwnedMicroBarVisibility", "OwnedMicroBarEditMode", "OwnedMicroBar",
            "MicroMenuStates", "MicroMenu", "MicroMenuSettings" },
    }) do
        for index = 2, #chain do
            Expect(position[chain[index - 1]] and position[chain[index]]
                and position[chain[index - 1]] < position[chain[index]],
                chain[index] .. " is missing from the TOC or loads before " .. chain[index - 1])
        end
    end
    local guards = {
        "type(hooksecurefunc)", "type(CreateFrame)", "_G.C_Timer", "C_Timer and", "C_Item and",
        "not C_Item", "C_TooltipInfo and", "_G.EventRegistry", "not EventRegistry", "_G.EventUtil",
        "not EventUtil", "EventUtil and", "type(_G.SetPortraitTexture)", "type(_G.IsInInstance)",
        "type(_G.RegisterStateDriver)", "type(_G.UnregisterStateDriver)", "GameTooltip and",
        "not GameTooltip", "type(UpdateUIPanelPositions)", "type(GetInventoryItemLink)", "type(_G.",
    }
    for _, file in ipairs(order) do
        local source = ReadSource(skin .. "Adapters/" .. file .. ".lua")
        local _, lines = source:gsub("\n", "")
        Expect(file == "Catalog" or lines < 900, file .. (" has %d lines"):format(lines))
        if file ~= "AdapterKit" and file ~= "Blizzard" and source:find("NS.AdapterKit", 1, true) then
            Expect(position[file] > position.AdapterKit, file .. " reads AdapterKit before it loads")
        end
        if file ~= "Blizzard" then
            for _, guard in ipairs(guards) do
                Expect(not source:find(guard, 1, true), file .. " still checks that " .. guard .. " exists")
            end
            -- Parents of foreign frames can be secret: Safety.Read or Kit.ParentIs.
            Expect(not source:find('Call%(%s*[%w_]+,%s*"GetParent"%)'),
                file .. " reads a parent that can be secret without Safety.Read")
        end
    end
    Expect(not ReadSource(skin .. "Adapters/SharedChrome.lua"):find("function AdapterKit.", 1, true),
        "SharedChrome.lua defines AdapterKit helpers again")
    for _, file in ipairs({ "EncounterJournal", "PlayerSpells" }) do
        Expect(not ReadSource(skin .. "Adapters/" .. file .. ".lua"):find("local function SkinSearchBox", 1, true),
            file .. " keeps its own search box skin")
    end

    -- The shared search box skin: one input look, reversible text colors.
    local skinned
    local applySearchBox = NS.ControlSkin.ApplySearchBox
    NS.ControlSkin.ApplySearchBox = function(box, owner, spec)
        skinned = { box = box, owner = owner, role = spec.role, height = spec.pillHeight }
        return {}
    end
    local box, placeholder = Text(0.9, 0.9, 0.9), Text(0.5, 0.5, 0.5)
    box.Instructions = placeholder
    local context = { owner = "search", textColors = Kit.NewTextColors() }
    Kit.SkinSearchBox(context, box)
    NS.ControlSkin.ApplySearchBox = applySearchBox
    Expect(skinned and skinned.box == box and skinned.owner == "search" and skinned.role == "input"
        and skinned.height == 28 and box.color[1] == 1 and placeholder.color[1] == 1,
        "the shared search box skin did not style the box and its placeholder")
    Kit.RestoreTextColors(context.textColors)
    Expect(box.color[1] == 0.9 and placeholder.color[1] == 0.5,
        "the shared search box skin did not restore the native text colors")
end)


Section("hidden windows defer cosmetic work until visible", function()
    local function Window(name)
        local frame = Frame(name)
        frame.shown, frame.parentShown, frame.hooks = false, true, {}
        function frame:IsShown() return self.shown end
        function frame:IsVisible() return self.shown and self.parentShown end
        function frame:HookScript(script, callback)
            self.hooks[script] = self.hooks[script] or {}
            table.insert(self.hooks[script], callback)
        end
        function frame:Display(shown)
            self.shown = shown
            if shown then
                if self.beforeShow then self.beforeShow(self) end
                for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
            end
        end
        return frame
    end
    local function Paints() return counters.attach + counters.yellow end
    Load("SocialUI.lua")
    local social = Window("SocialUIFrame")
    social.FriendsList = { ScrollBox = RowBox() }
    function social:EnumerateTabs() return function() end end
    function social:RefreshTabs() end
    function social:RefreshTabStates() end
    _G.SocialUIFrame = social
    local beforeSocial = Paints()
    NS.SocialUISkin.Apply("hidden-social")
    NS.SocialUISkin.Apply("hidden-social")
    Expect(Paints() == beforeSocial and not social.surfaceSpec,
        "closed social window was skinned before its native opening")
    local socialState = NS.SocialUISkin.owners["hidden-social"]
    Expect(next(socialState.scrollBoxes) == nil, "closed social list acquired row/motion callbacks")
    Expect(#(social.hooks.OnShow or {}) == 1, "repeated hidden social applies duplicated its wake hook")
    social.beforeShow = function()
        Expect(Paints() == beforeSocial, "social skin ran before native OnShow")
    end
    social:Display(true)
    social.beforeShow = nil
    Expect(social.surfaceSpec ~= nil and next(socialState.scrollBoxes) ~= nil,
        "native social opening did not acquire its full skin")
    social:Display(false)
    local afterSocial = Paints()
    NS.SocialUISkin.Apply("hidden-social")
    Expect(Paints() == afterSocial, "hidden social refresh mutated its native content")
    NS.SocialUISkin.Disable("hidden-social")
    social:Display(true)
    Expect(Paints() == afterSocial and NS.SocialUISkin.owners["hidden-social"] == nil,
        "cancelled social skin woke on a later opening")
    _G.SocialUIFrame = nil
    local combatSocial = Window("SocialUIFrame")
    combatSocial.FriendsList = { ScrollBox = RowBox() }
    combatSocial.EnumerateTabs = social.EnumerateTabs
    combatSocial.RefreshTabs, combatSocial.RefreshTabStates = social.RefreshTabs, social.RefreshTabStates
    _G.SocialUIFrame = combatSocial
    local runOrDefer, cancel = NS.CombatGate.RunOrDefer, NS.CombatGate.Cancel
    local queued = {}
    NS.CombatGate.RunOrDefer = function(key, callback)
        if locked then queued[key] = callback return false, "combat" end
        callback()
        return true
    end
    NS.CombatGate.Cancel = function(key) queued[key] = nil end
    local combatPaints = Paints()
    NS.SocialUISkin.Apply("combat-social")
    locked = true
    combatSocial:Display(true)
    Expect(next(queued) ~= nil and Paints() == combatPaints,
        "cold combat social opening lost its deferred skin or painted immediately")
    combatSocial:Display(false)
    locked = false
    for key, callback in pairs(queued) do queued[key] = nil callback() end
    Expect(Paints() == combatPaints, "combat-end replay skinned a closed social window")
    combatSocial:Display(true)
    Expect(combatSocial.surfaceSpec ~= nil, "social skin did not recover on the next native opening")
    NS.SocialUISkin.Disable("combat-social")
    NS.CombatGate.RunOrDefer, NS.CombatGate.Cancel = runOrDefer, cancel
    _G.SocialUIFrame = nil
    local ordered, order = Window("OrderedSkin"), {}
    local function Order(value) order[#order + 1] = value end
    Kit.DeferHidden(ordered, {}, Order, "common", nil, nil, 20)
    Kit.DeferHidden(ordered, {}, Order, "major", nil, nil, 10)
    Kit.DeferHidden(ordered, {}, Order, "generic")
    ordered:Display(true)
    Expect(table.concat(order, ",") == "generic,major,common", "hidden skin layers did not retain generic-before-specialized order")
    local shared = Window("CancellationWindow")
    local ownerA, ownerB, calls = {}, {}, 0
    local function CancelOther(other)
        calls = calls + 1
        NS.AdapterKit.CancelHidden(other)
    end
    NS.AdapterKit.DeferHidden(shared, ownerA, CancelOther, ownerB)
    NS.AdapterKit.DeferHidden(shared, ownerB, CancelOther, ownerA)
    shared:Display(true)
    Expect(calls == 1, "same-show cancellation dispatched a canceled owner")
    shared:Display(false)
    local replaced = 0
    local function Replacement() replaced = replaced + 1 end
    local function HideAndReplace(other)
        shared:Display(false)
        NS.AdapterKit.DeferHidden(shared, other, Replacement)
    end
    NS.AdapterKit.DeferHidden(shared, ownerA, HideAndReplace, ownerB)
    NS.AdapterKit.DeferHidden(shared, ownerB, HideAndReplace, ownerA)
    shared:Display(true)
    Expect(replaced == 0, "OnShow dispatched replacement work after the frame hid again")
    shared:Display(true)
    Expect(replaced == 1, "replacement request did not survive until the next show")
    collectgarbage("collect")
    collectgarbage("stop")
    local memory = collectgarbage("count")
    for _ = 1, 1000 do shared:Display(true) end
    local growth = collectgarbage("count") - memory
    collectgarbage("restart")
    Expect(growth < 1, "clean OnShow allocated pending request tables")
    Load("MajorWindows.lua")
    Load("MajorWindowsItems.lua")
    local previous = _G.PVPUIFrame
    local panel = Window("PVPUIFrame")
    _G.PVPUIFrame = panel
    local before = Paints()
    NS.MajorWindows.Apply("cold-major")
    Expect(Paints() == before and panel.surfaceSpec == nil, "hidden major window performed initial cosmetic traversal")
    for _ = 1, 30 do NS.MajorWindows.Apply("cold-major") end
    Expect(Paints() == before, "repeated hidden major requests painted")
    Expect(#(panel.hooks.OnShow or {}) == 1, "hidden major requests added duplicate/missing show hooks")
    panel:Display(true)
    Expect(panel.surfaceSpec ~= nil and Paints() > before, "first show did not paint the deferred major window")
    before = Paints()
    panel:Display(false)
    panel:Display(true)
    Expect(Paints() == before, "clean major reopen repeated a tree pass")
    panel:Display(false)
    NS.MajorWindows.Apply("cold-major")
    NS.MajorWindows.Disable("cold-major")
    before = Paints()
    panel:Display(true)
    Expect(Paints() == before, "hidden major request repainted after disable")
    local originalGate, pending = NS.CombatGate, {}
    NS.CombatGate = {
        RunOrDefer = function(key, callback)
            if locked then pending[key] = callback else callback() end
        end,
        Cancel = function(key) pending[key] = nil end,
        IsPending = function(key) return pending[key] ~= nil end,
    }
    panel = Window("PVPUIFrame")
    _G.PVPUIFrame = panel
    local priorQueue, priorHonor, priorNativeLock = _G.PVPQueueFrame, _G.HonorFrame, InCombatLockdown
    local specialCard = Frame("ProtectedHonorBonus")
    function specialCard:IsProtected() return true, false end
    _G.HonorFrame = { BonusFrame = specialCard }
    _G.PVPQueueFrame = {}
    InCombatLockdown = function() return false end
    NS.MajorWindows.Apply("cold-combat")
    before = Paints()
    locked = true
    panel:Display(true)
    Expect(Paints() > before and next(pending) ~= nil, "first combat show lost safe styling or structural completion")
    Expect(specialCard.surfaceSpec == nil, "combat show painted a protected specialized card")
    before = Paints()
    panel:Display(false)
    locked = false
    for key, callback in pairs(pending) do pending[key] = nil; callback() end
    Expect(Paints() == before, "combat end painted a window that had hidden again")
    panel:Display(true)
    Expect(Paints() > before, "post-combat first show did not apply the latest skin")
    Expect(specialCard.surfaceSpec and specialCard.surfaceSpec.role == "panel",
        "post-combat completion lost the specialized protected card")
    _G.PVPQueueFrame, _G.HonorFrame, InCombatLockdown = priorQueue, priorHonor, priorNativeLock
    NS.MajorWindows.Disable("cold-combat")
    NS.CombatGate = originalGate
    _G.PVPUIFrame = previous

    local previousBook, previousContent, previousForever = ProfessionsBookFrame, ProfessionsContentFrame, NS.Client.isForever
    local book, content = Window("ProfessionsBookFrame"), Window("ProfessionsContentFrame")
    ProfessionsBookFrame, ProfessionsContentFrame, NS.Client.isForever = book, content, false
    local oldPrimary, oldMotion = PrimaryProfession1, NS.ContentMotion
    local card, rank = Window("PrimaryProfession1"), Window(nil)
    PrimaryProfession1, card.statusBar = card, rank
    local watched = {}
    NS.ContentMotion = { Watch = function(frame)
        if not frame or frame == book then return false end
        watched[frame] = true
        return true
    end }
    local priorNativeLockdown = InCombatLockdown
    InCombatLockdown = function() return locked end
    function book:IsProtected() return true, false end
    NS.MajorWindows.Apply("retail-profession-book")
    Expect(not book:IsShown() and book.surfaceSpec and content.surfaceSpec,
        "standalone Retail profession book did not prepare while closed")
    Expect(watched[rank] and not watched[book], "the protected standalone book lost its safe opening animation")
    before = Paints()
    locked = true
    book:Display(true)
    Expect(book.surfaceSpec and Paints() == before,
        "first combat open repainted the Retail profession book or lost its prepared skin")
    locked = false
    NS.MajorWindows.Disable("retail-profession-book")
    local foreignBook = Window("ProfessionsBookFrame")
    ProfessionsBookFrame, NS.Client.isForever = foreignBook, true
    NS.MajorWindows.Apply("forever-profession-book")
    Expect(not foreignBook.surfaceSpec and not foreignBook.hooks.OnShow,
        "Forever applied the standalone Retail profession book adapter")
    NS.MajorWindows.Disable("forever-profession-book")
    ProfessionsBookFrame, ProfessionsContentFrame, NS.Client.isForever = previousBook, previousContent, previousForever
    PrimaryProfession1, NS.ContentMotion = oldPrimary, oldMotion
    InCombatLockdown = priorNativeLockdown

    local frame = Window("ColdGenericFrame")
    local entry = { id = "cold-generic", category = "utility", frames = { frame } }
    before = Paints()
    GenericWindows.ApplyEntry(entry, "cold-generic")
    Expect(Paints() == before and frame.surfaceSpec == nil, "hidden catalog frame performed a tree pass")
    frame.shown, frame.parentShown = true, false
    local cancelHidden, cancellationScans = Kit.CancelHidden, 0
    Kit.CancelHidden = function(owner) cancellationScans = cancellationScans + 1; return cancelHidden(owner) end
    for _ = 1, 30 do GenericWindows.ApplyEntry(entry, "cold-generic") end
    Kit.CancelHidden = cancelHidden
    Expect(cancellationScans == 0, "catalog apply scanned unrelated hidden windows")
    Expect(Paints() == before, "a shown frame under a hidden parent performed a tree pass")
    frame.parentShown = true
    frame:Display(true)
    Expect(frame.surfaceSpec ~= nil and Paints() > before, "catalog frame did not catch up on parent show")
    frame:Display(false)
    GenericWindows.ApplyEntry(entry, "cold-generic")
    GenericWindows.Disable("cold-generic")
    before = Paints()
    frame:Display(true)
    Expect(Paints() == before, "hidden catalog job survived owner disable")

    local combatWindow = Window("CombatFirstWindow")
    local combatEntry = { id = "combat-first-window", category = "utility", frames = { combatWindow } }
    GenericWindows.ApplyEntry(combatEntry, "combat-first-window")
    before = Paints()
    locked = true
    combatWindow:Display(true)
    Expect(combatWindow.surfaceSpec ~= nil and Paints() > before,
        "unprotected catalog window lost its skin on first combat opening")
    local combatReads, combatPaints = combatWindow.childReads, Paints()
    for _ = 1, 100 do combatWindow:Display(false); combatWindow:Display(true) end
    Expect(combatWindow.childReads == combatReads and Paints() == combatPaints,
        "clean combat reopening repeated traversal or painting")
    locked = false
    GenericWindows.Disable("combat-first-window")

    -- Protected HUD roots (ExtraActionBarFrame, OverrideActionBar, SpellFlyout,
    -- TargetFrame ...) are decided at once, as before hidden deferral: they show
    -- mostly in combat, so an OnShow wait wakes in combat and re-arms after it.
    local previousLockdown = InCombatLockdown
    InCombatLockdown = function() return locked end
    local explicitRoot, implicitRoot = Window("ColdExplicitRoot"), Window("ColdImplicitRoot")
    function explicitRoot:IsProtected() return true, true end
    function implicitRoot:IsProtected() return true, false end
    local _, explicitState = GenericWindows.ApplyEntry(
        { id = "cold-explicit", category = "utility", frames = { explicitRoot } }, "cold-protected")
    local _, implicitState = GenericWindows.ApplyEntry(
        { id = "cold-implicit", category = "utility", frames = { implicitRoot } }, "cold-protected")
    Expect(explicitState == "protected" and GenericWindows.GetStatus("cold-explicit") == "protected"
        and explicitRoot.hooks.OnShow == nil, "a hidden protected root waited for its OnShow instead of reading protected")
    Expect(implicitState == "applied" and implicitRoot.surfaceSpec ~= nil and implicitRoot.hooks.OnShow == nil,
        "a hidden implicitly protected root waited for an OnShow in combat instead of painting out of combat")
    GenericWindows.Disable("cold-protected")
    InCombatLockdown = previousLockdown
    -- Unprotected HUD roots (EncounterTimeline, the encounter warnings, cooldown
    -- viewers shown in combat) paint at once as well, for the same reason.
    local hudEntry = NS.BlizzardCatalog.FindByFrame("EncounterTimeline")
    local previousTimeline = _G.EncounterTimeline
    local timeline = Window("EncounterTimeline")
    _G.EncounterTimeline = timeline
    local _, hudState = GenericWindows.ApplyEntry(hudEntry, "cold-hud")
    Expect(hudEntry.category == "hud" and hudState == "applied"
        and GenericWindows.GetStatus(hudEntry.id) == "applied" and timeline.hooks.OnShow == nil,
        "a hidden HUD root waited for an OnShow in combat instead of painting at once")
    GenericWindows.Disable("cold-hud")
    _G.EncounterTimeline = previousTimeline

    local list = Window("ColdScrollBox")
    local row = Frame("ColdRow")
    local rowCallback, rowOwner, visits
    visits = 0
    function list:HasView() return true end
    function list:RegisterCallback(_, callback, owner) rowCallback, rowOwner = callback, owner end
    function list:UnregisterCallback() rowCallback, rowOwner = nil, nil end
    function list:ForEachFrame(callback) visits = visits + 1; callback(row) end
    local host = Frame("VisibleHost", { list })
    GenericWindows.ApplyFrame(host, "cold-rows", MODE)
    Expect(visits == 0 and row.surfaceSpec == nil, "hidden ScrollBox enumerated its pooled rows")
    before = Paints()
    for _ = 1, 30 do rowCallback(rowOwner, row) end
    Expect(visits == 0 and Paints() == before, "hidden row initializations painted")
    collectgarbage("collect")
    collectgarbage("stop")
    memory = collectgarbage("count")
    for _ = 1, 1000 do rowCallback(rowOwner, row) end
    growth = collectgarbage("count") - memory
    collectgarbage("restart")
    Expect(growth < 1 and Paints() == before, "warm hidden row callbacks allocated jobs or painted")
    list:Display(true)
    Expect(visits == 1 and row.surfaceSpec ~= nil, "shown ScrollBox did not catch up once")
    before = Paints()
    list:Display(false)
    rowCallback(rowOwner, row)
    GenericWindows.Disable("cold-rows")
    before = Paints()
    list:Display(true)
    Expect(visits == 1 and Paints() == before, "disabled ScrollBox retained a cosmetic job")

    local weak = setmetatable({}, { __mode = "v" })
    do
        local disposable = Window("DisposableScrollBox")
        disposable.HasView, disposable.RegisterCallback = list.HasView, function() end
        disposable.UnregisterCallback, disposable.ForEachFrame = function() end, function() end
        GenericWindows.ApplyFrame(disposable, "gc-rows", MODE)
        weak[1] = disposable
    end
    collectgarbage("collect")
    collectgarbage("collect")
    Expect(weak[1] == nil, "hidden row registration retained a discarded ScrollBox")
    GenericWindows.Disable("gc-rows")

    local first, second = Window("SiblingA"), Window("SiblingB")
    local siblings = { id = "cold-siblings", category = "utility", frames = { first, second } }
    GenericWindows.ApplyEntry(siblings, "cold-siblings")
    first:Display(true)
    local firstReads = first.childReads
    second:Display(true)
    Expect(first.childReads == firstReads, "showing a sibling repeated the visible sibling's generic pass")
    first:Display(false)
    second:Display(false)
    first:Display(true)
    local siblingPaints = Paints()
    first:Display(false)
    second:Display(true)
    second:Display(false)
    first:Display(true)
    Expect(Paints() == siblingPaints, "alternating clean catalog siblings re-armed full passes")
    GenericWindows.Disable("cold-siblings")
    first, second = Window("ExclusiveA"), Window("ExclusiveB")
    siblings = { id = "cold-exclusive", category = "utility", frames = { first, second } }
    GenericWindows.ApplyEntry(siblings, "cold-exclusive")
    first:Display(true)
    first:Display(false)
    second:Display(true)
    second:Display(false)
    siblingPaints = Paints()
    first:Display(true)
    first:Display(false)
    second:Display(true)
    Expect(Paints() == siblingPaints, "exclusive catalog siblings re-armed each other")
    GenericWindows.Disable("cold-exclusive")

    local overlap = Window("SharedCatalogFrame")
    GenericWindows.ApplyEntry({ id = "overlap-one", category = "utility", frames = { overlap } }, "overlap")
    GenericWindows.ApplyEntry({ id = "overlap-two", category = "utility", frames = { overlap } }, "overlap")
    overlap:Display(true)
    Expect(GenericWindows.GetStatus("overlap-one") == "applied" and GenericWindows.GetStatus("overlap-two") == "applied",
        "two catalog entries sharing a frame overwrote a pending pass")
    GenericWindows.Disable("overlap")
    local firstError, broken, unvisited = Window("BeforeError"), Window("BrokenWindow"), Window("AfterError")
    broken.shown = true
    function broken:GetChildren() error("cold entry sibling failure") end
    local failedEntry = { id = "cold-errors", category = "utility", frames = { firstError, broken, unvisited } }
    local failed = pcall(GenericWindows.ApplyEntry, failedEntry, "cold-errors")
    Expect(not failed, "raising sibling did not reach the entry error boundary")
    firstError:Display(true)
    Expect(GenericWindows.GetStatus("cold-errors") == "error", "reveal erased an incomplete catalog entry failure")
    GenericWindows.Disable("cold-errors")
    broken, firstError = Window("DeferredError"), Window("OtherDeferred")
    function broken:GetChildren() error("deferred entry sibling failure") end
    failedEntry = { id = "cold-deferred-errors", category = "utility", frames = { broken, firstError } }
    GenericWindows.ApplyEntry(failedEntry, "cold-deferred-errors")
    broken:Display(true)
    firstError:Display(true)
    Expect(GenericWindows.GetStatus("cold-deferred-errors") == "error", "sibling reveal erased a deferred frame error")
    broken.GetChildren = function() return end
    GenericWindows.ApplyEntry(failedEntry, "cold-deferred-errors")
    Expect(GenericWindows.GetStatus("cold-deferred-errors") == "applied", "successful full refresh retained a stale error")
    GenericWindows.Disable("cold-deferred-errors")

    local deferred, savedGate = {}, NS.CombatGate
    NS.CombatGate = {
        RunOrDefer = function(key, callback) if locked then deferred[key] = callback else callback() end end,
        Cancel = function(key) deferred[key] = nil end,
        IsPending = function(key) return deferred[key] ~= nil end,
    }
    local savedLockdown = InCombatLockdown
    InCombatLockdown = function() return false end
    local safe, guarded = Window("CombatLoadedSafe"), Window("CombatLoadedProtected")
    safe.shown, guarded.shown = true, true
    local nativeFade, guardedWrites = NS.Cosmetics.Fade, 0
    local guardedArt = Frame("ProtectedNamedChrome")
    function guardedArt:IsProtected() return true, false end
    safe.Bg = guardedArt
    NS.Cosmetics.Fade = function(region, ...)
        if region == guardedArt then guardedWrites = guardedWrites + 1 end
        return nativeFade(region, ...)
    end
    function guarded:IsProtected() return true, false end
    local loadedEntry = { id = "combat-loaded", category = "utility", frames = { safe, guarded } }
    locked = true -- InCombatLockdown is still false at this event edge.
    GenericWindows.ApplyEntry(loadedEntry, "combat-loaded")
    Expect(safe.surfaceSpec ~= nil and guarded.surfaceSpec == nil and guarded.childReads == 0,
        "combat-loaded entry skipped its safe root or traversed its protected sibling")
    Expect(guardedWrites == 0, "combat pass wrote protected named chrome")
    local safeReads = safe.childReads
    safe:Display(false)
    locked = false
    for key, callback in pairs(deferred) do deferred[key] = nil; callback() end
    Expect(safe.childReads == safeReads and guarded.surfaceSpec ~= nil,
        "combat completion painted a closed root or lost protected work")
    safe:Display(true)
    Expect(safe.childReads > safeReads, "post-combat reveal lost structural completion")
    Expect(guardedWrites > 0, "post-combat reveal lost protected named chrome")
    NS.Cosmetics.Fade = nativeFade
    GenericWindows.Disable("combat-loaded")
    local inactive = Window("CombatDisabled")
    inactive.shown = true
    locked = true
    GenericWindows.ApplyEntry({ id = "combat-disabled", category = "utility", frames = { inactive } }, "combat-disabled")
    GenericWindows.Disable("combat-disabled")
    local inactiveReads = inactive.childReads
    locked = false
    for key, callback in pairs(deferred) do deferred[key] = nil; callback() end
    Expect(inactive.childReads == inactiveReads, "disabled owner replayed a combat completion")

    InCombatLockdown = savedLockdown
    local rows = { Frame("CatchupOne"), Frame("CatchupTwo") }
    local catchup = Window("CombatScrollBox")
    catchup.HasView, catchup.RegisterCallback = list.HasView, list.RegisterCallback
    catchup.UnregisterCallback = list.UnregisterCallback
    function catchup:ForEachFrame(callback) for _, item in ipairs(rows) do callback(item) end end
    GenericWindows.ApplyFrame(Frame("CatchupHost", { catchup }), "catchup-rows", MODE)
    locked = true
    catchup:Display(true)
    Expect(rows[1].surfaceSpec ~= nil and rows[2].surfaceSpec ~= nil, "safe row catchup lost combat first-show styling")
    locked = false
    for key, callback in pairs(deferred) do deferred[key] = nil; callback() end
    Expect(rows[1].surfaceSpec ~= nil and rows[2].surfaceSpec ~= nil, "combat first show lost the pending ScrollBox catchup")
    catchup:Display(false)
    rows = { Frame("ProtectedCatchupOne"), Frame("ProtectedCatchupTwo") }
    rowCallback(rowOwner, rows[1])
    function catchup:IsProtected() return true, false end
    locked = true
    catchup:Display(true)
    Expect(rows[1].surfaceSpec == nil and rows[2].surfaceSpec == nil,
        "protected ScrollBox catchup painted during combat")
    locked = false
    catchup.IsProtected = nil
    for key, callback in pairs(deferred) do deferred[key] = nil; callback() end
    Expect(rows[1].surfaceSpec ~= nil and rows[2].surfaceSpec ~= nil,
        "combat first show lost the pending ScrollBox catchup")
    catchup:Display(false)
    rows = { Frame("NativeShowOne"), Frame("NativeShowTwo") }
    rowCallback(rowOwner, rows[1])
    rowCallback(rowOwner, rows[2])
    catchup.shown = true
    rowCallback(rowOwner, rows[1])
    catchup:Display(true)
    Expect(rows[1].surfaceSpec ~= nil and rows[2].surfaceSpec ~= nil, "native show initialization canceled the remaining row catchup")
    GenericWindows.Disable("catchup-rows")
    NS.CombatGate = savedGate

    Load("CommonArt.lua")
    local oldCategoryHook = _G.LFGListCategorySelection_UpdateCategoryButtons
    _G.LFGListCategorySelection_UpdateCategoryButtons = function() end
    local oldPVE, oldNavigation, oldButton = _G.PVEFrame, _G.GroupFinderFrame, NS.ControlSkin.ApplyButton
    NS.ControlSkin.ApplyButton = function(button, _, spec) button.lastSpec = spec; return {} end
    local function Finder(shown, owner)
        local finder, navigation = Window("PVEFrame"), Frame("GroupFinderFrame")
        navigation.groupButton1 = Frame("GroupFinderFrameGroupButton1")
        finder.children = { navigation }
        finder.shown = shown
        _G.PVEFrame, _G.GroupFinderFrame = finder, navigation
        finder.beforeShow = function()
            _G.LFGListCategorySelection_UpdateCategoryButtons({ CategoryButtons = {} })
        end
        local entry = { id = "ordered-finder", category = "group", frames = { finder } }
        GenericWindows.ApplyEntry(entry, owner)
        NS.MajorWindows.Apply(owner)
        NS.CommonArt.Apply(owner)
        if not shown then finder:Display(true) end
        local spec = navigation.groupButton1.lastSpec
        Expect(spec and spec.radius == 8 and spec.pillHeight == 48 and spec.activeRole == nil,
            "hidden Group Finder reversed the final CommonArt navigation style")
        finder:Display(false)
        GenericWindows.ApplyEntry(entry, owner)
        NS.MajorWindows.Apply(owner)
        NS.CommonArt.Apply(owner)
        navigation.groupButton1.lastSpec = nil
        finder:Display(true)
        spec = navigation.groupButton1.lastSpec
        Expect(spec and spec.radius == 8 and spec.pillHeight == 48,
            "hidden settings refresh changed the Group Finder's final navigation style")
        NS.CommonArt.Disable(owner)
        NS.MajorWindows.Disable(owner)
        GenericWindows.Disable(owner)
    end
    Finder(true, "visible-finder")
    Finder(false, "hidden-finder")
    local oldList = _G.LFGListFrame
    local pooled = Window("LFGSearchScrollBox")
    pooled.callbacks = {}
    pooled.rows = { Frame("LFGFirstRow"), Frame("LFGSecondRow") }
    pooled.HasView = function() return true end
    pooled.RegisterCallback, pooled.UnregisterCallback = RowBox().RegisterCallback, RowBox().UnregisterCallback
    pooled.ForEachFrame, pooled.Initialize = RowBox().ForEachFrame, RowBox().Initialize
    _G.PVEFrame = Window("PVEFrame")
    _G.PVEFrame.shown = true
    _G.GroupFinderFrame = nil
    _G.LFGListFrame = { SearchPanel = { ScrollBox = pooled } }
    local nativeGate, rowJobs = NS.CombatGate, {}
    NS.CombatGate = {
        RunOrDefer = function(key, callback) if locked then rowJobs[key] = callback else callback() end end,
        Cancel = function(key) rowJobs[key] = nil end,
        IsPending = function(key) return rowJobs[key] ~= nil end,
    }
    GenericWindows.ApplyFrame(Frame("GenericRowsHost", { pooled }), "shared-rows", MODE)
    NS.CommonArt.Apply("shared-rows")
    pooled:Initialize(pooled.rows[1])
    Expect(not pooled.rows[1].lastSpec and not pooled.rows[2].lastSpec, "CommonArt painted hidden finder rows")
    locked = true
    pooled:Display(true)
    Expect(not pooled.rows[1].lastSpec and next(rowJobs) ~= nil, "CommonArt lost its precombat hidden obligation")
    locked = false
    for key, callback in pairs(rowJobs) do rowJobs[key] = nil; callback() end
    Expect(pooled.rows[1].lastSpec and pooled.rows[2].lastSpec, "CommonArt did not restore every deferred row after combat")
    pooled:Display(false)
    pooled.rows = { Frame("LFGRecycledOne"), Frame("LFGRecycledTwo") }
    pooled:Initialize(pooled.rows[1])
    pooled.shown = true
    pooled:Initialize(pooled.rows[1])
    pooled:Display(true)
    Expect(pooled.rows[1].lastSpec and pooled.rows[2].lastSpec, "native row initialization lost CommonArt sibling rows")
    pooled:Display(false)
    pooled:Initialize(pooled.rows[1])
    NS.CommonArt.Disable("shared-rows")
    GenericWindows.Disable("shared-rows")
    pooled.rows = { Frame("DisabledCommonRow") }
    pooled:Display(true)
    Expect(pooled.rows[1].lastSpec == nil and next(rowJobs) == nil, "disabled CommonArt retained row work")
    NS.CombatGate, _G.LFGListFrame = nativeGate, oldList
    _G.LFGListCategorySelection_UpdateCategoryButtons = oldCategoryHook

    local retained = setmetatable({}, { __mode = "v" })
    local metricOwner = { deferred = {} }
    local metricNS = setmetatable({ GenericWindows = {}, GenericWindowsShared = {
        DEFAULT_OWNER = "metrics", OwnerState = function() return metricOwner end,
        OwnerKey = tostring, CatalogMode = function(mode) return mode end,
        CanSkin = function() return true end, DeactivateOwner = function() end,
        ApplyFrameNow = function()
            local metrics = { nodes = 1, surfaces = 2, controls = 3, scrollBars = 4, protected = 0, errors = 0 }
            for index = 1, 200 do metrics["scratch" .. index] = {} end
            retained[1] = metrics
            return true, "applied", metrics
        end,
    } }, { __index = NS })
    Load("GenericWindowsCatalog.lua", metricNS)
    local metricFrame = Window("MetricsLifetime")
    metricFrame.shown = true
    metricNS.GenericWindows.ApplyEntry({ id = "metrics-lifetime", category = "utility", frames = { metricFrame } })
    collectgarbage("collect")
    collectgarbage("collect")
    Expect(retained[1] == nil, "catalog retained a frame pass's scratch metrics")
    _G.PVEFrame, _G.GroupFinderFrame, NS.ControlSkin.ApplyButton = oldPVE, oldNavigation, oldButton
end)

Section("map canvas chrome", function()
    for _, name in ipairs({ "FlightMapFrame", "BattlefieldMapFrame", "TaxiFrame" }) do
        local entry = NS.BlizzardCatalog.FindByFrame(name)
        local mode = entry.frameModes and entry.frameModes[name] or entry.mode
        Expect(type(mode) == "table" and mode.preserveRootArt == true and mode.fillVisible == false,
            name .. " covers the native map canvas with a full window fill")
    end
end)

Section("native chat configuration", function()
    local owner = "chat-config-contract"
    NS.DB = { enabled = true }
    local surfaces, jobs = {}, {}
    NS.Surface = {
        Attach = function(target, spec)
            local surface = { spec = spec, visible = true }
            surfaces[target] = surface
            return surface
        end,
        SetActive = function(target, active) surfaces[target].active = active end,
        SetVisible = function(target, visible) surfaces[target].visible = visible end,
    }
    NS.Registry.GetSurface = function(target) return surfaces[target] end
    NS.CombatGate.RunOrDefer = function(key, callback)
        if locked then jobs[key] = callback else callback() end
    end
    NS.CombatGate.Cancel = function(key) jobs[key] = nil end
    assert(loadfile(skin .. "Core/Cosmetics.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(skin .. "Core/Checkmarks.lua"))("MSUF_Suite_Skin", NS)
    local function Noop() end
    NS.Checkmarks.TrackDropdown = Noop
    NS.WindowActionSkin.HasOwnedStates = function() return false end
    NS.WindowActionSkin.IsApplied = function() return false end
    NS.Theme.GetColor = function(role)
        if role == "checkmark" then return 0.25, 0.75, 1, 1 end
        return 1, 1, 1, 1
    end
    assert(loadfile(os.getenv("SUITE_CHAT_CONFIG_SKIN_SOURCE") or skin .. "Adapters/ChatConfig.lua"))("MSUF_Suite_Skin", NS)

    local function Region(alpha)
        return {
            alpha = alpha, shown = true,
            GetAlpha = function(self) return self.alpha end,
            SetAlpha = function(self, value) self.alpha = value end,
            IsShown = function(self) return self.shown end,
        }
    end
    local function Panel(name)
        local panel = Frame(name)
        panel.NineSlice = { TopEdge = Region(0.5) }
        return panel
    end
    local function CheckTexture(alpha)
        local texture = Region(alpha)
        texture.red, texture.green, texture.blue = 1, 1, 1
        texture.writes = 0
        texture.GetTexture = function() return 12345 end
        texture.GetVertexColor = function(self) return self.red, self.green, self.blue, self.alpha end
        texture.SetVertexColor = function(self, r, g, b, a)
            self.red, self.green, self.blue, self.alpha = r, g, b, a
            self.writes = self.writes + 1
        end
        texture.IsDesaturated = function(self) return self.desaturated == true end
        texture.SetDesaturated = function(self, value) self.desaturated = value end
        return texture
    end
    local function Checkbox()
        local check = Frame(nil)
        check.alpha, check.checkedArt, check.disabledArt = 1, CheckTexture(1), CheckTexture(0.6)
        check.GetObjectType = function() return "CheckButton" end
        check.GetCheckedTexture = function(self) return self.checkedArt end
        check.GetDisabledCheckedTexture = function(self) return self.disabledArt end
        check.SetChecked = function(self, value) self.checked = value end
        check.Click = function(self) self:SetChecked(not self.checked) end
        return check
    end
    local function Tinted(texture, alpha)
        return texture and texture.desaturated and texture.red == 0.25
            and texture.green == 0.75 and texture.blue == 1 and texture.alpha == alpha
    end
    local function TintedCheck(check)
        return Tinted(check.checkedArt, 1) and Tinted(check.disabledArt, 0.6)
    end
    local function FilterRow()
        local row = Panel(nil)
        row.layoutType = "TooltipDefaultLayout"
        row.CheckButton, row.ColorSwatch = Checkbox(), Region(1)
        return row
    end
    local function Tab()
        local tab = Frame(nil)
        tab.IsShown = function() return true end
        tab.Left, tab.ActiveMiddle, tab.HighlightMiddle = Region(1), Region(1), Region(1)
        return tab
    end
    local function Category()
        local button = Frame(nil)
        button.Highlight = Region(1)
        button.IsHighlightLocked = function(self) return self.locked == true end
        return button
    end
    local frame, group, panel = Frame("ChatConfigFrame"), Panel("ChatConfigChatSettingsLeft"), Panel(nil)
    local firstTab, secondTab = Tab(), Tab()
    local firstCategory, secondCategory = Category(), Category()
    local firstRow, thirdTab = FilterRow(), Tab()
    local tiered = Panel("CombatConfigMessageTypesLeft")
    local tieredParent, tieredChild = Checkbox(), Checkbox()
    group.children[1] = firstRow
    tiered.children[1] = tieredParent
    tieredParent.children[1] = tieredChild
    _G.CombatConfigMessageTypesLeft = tiered
    _G.CombatConfigMessageTypesLeftCheckbox1 = tieredParent
    firstCategory.locked = true
    secondTab.ActiveMiddle.shown = false
    frame.ChatTabManager = { Tabs = { firstTab, secondTab } }
    frame.ChatTabManager.UpdateSelection = function(self, selected)
        for index, tab in ipairs(self.Tabs) do
            tab.ActiveMiddle.shown, tab.ActiveMiddle.alpha = index == selected, 1
        end
    end
    _G.ChatConfigFrame, _G.ChatConfigBackgroundFrame, _G.ChatConfigChatSettingsLeft = frame, panel, group
    _G.ChatConfigCategoryFrameButton1, _G.ChatConfigCategoryFrameButton2 = firstCategory, secondCategory
    _G.ChatConfigCategory_OnClick = function(button)
        firstCategory.locked, secondCategory.locked = button == firstCategory, button == secondCategory
    end
    _G.ChatConfig_CreateCheckboxes = function(parent, row) parent.children[#parent.children + 1] = row end
    _G.ChatConfig_UpdateCheckboxes = function(parent)
        for _, row in ipairs(parent.children) do row.CheckButton:SetChecked(true) end
    end
    _G.ChatConfig_CreateTieredCheckboxes = function(parent, row)
        local index = #parent.children + 1
        parent.children[index] = row
        _G[parent:GetName() .. "Checkbox" .. index] = row
    end
    _G.ChatConfig_UpdateTieredCheckboxes = function(parent, index)
        local row = parent.children[index]
        row:SetChecked(true)
        row.children[1]:SetChecked(true)
    end

    local function Selected(target, selected)
        return surfaces[target] and surfaces[target].active == selected
    end
    local function Hidden(target)
        return surfaces[target] and surfaces[target].visible == false
    end
    local entry
    for _, candidate in ipairs(NS.BlizzardCatalog.entries) do
        if candidate.id == "chat-configuration" then entry = candidate end
    end
    Expect(GenericWindows.ApplyEntry(entry, owner), "ChatConfig must skin through the utility catalog")
    Expect(surfaces[panel] and panel.NineSlice.TopEdge.alpha == 0 and firstRow.NineSlice.TopEdge.alpha == 0,
        "native ChatConfig panel/row NineSlices still stack borders")
    Expect(firstRow.CheckButton.alpha == 1 and firstRow.ColorSwatch.alpha == 1,
        "ChatConfig filter controls lost semantic art")
    Expect(TintedCheck(firstRow.CheckButton), "Chat filters did not tint both file-based checkbox states")
    Expect(TintedCheck(tieredParent) and TintedCheck(tieredChild),
        "Combat Log Message Types did not tint parent and child checkbox states")
    firstRow.CheckButton:Click()
    Expect(firstRow.CheckButton.checked and TintedCheck(firstRow.CheckButton),
        "native checkbox click did not retain checked state and theme")
    local beforeUpdate = firstRow.CheckButton.checkedArt.writes
    _G.ChatConfig_UpdateCheckboxes(group)
    Expect(firstRow.CheckButton.checkedArt.writes == beforeUpdate, "stable checkmark was repainted on a native update")
    Expect(Selected(firstTab, true) and Selected(secondTab, false)
        and firstTab.Left.alpha == 0 and firstTab.ActiveMiddle.alpha == 0,
        "ChatConfig tabs did not distinguish the initial native selection")
    Expect(Selected(firstCategory, true) and Selected(secondCategory, false)
        and firstCategory.Highlight.alpha == 0,
        "ChatConfig category highlight did not follow the initial native selection")

    frame.ChatTabManager.Tabs[3] = thirdTab
    frame.ChatTabManager:UpdateSelection(3)
    _G.ChatConfigCategory_OnClick(secondCategory)
    local lateRow, unrelated = FilterRow(), FilterRow()
    _G.ChatConfig_CreateCheckboxes(group, lateRow)
    _G.ChatConfig_CreateCheckboxes(Panel(nil), unrelated)
    Expect(Selected(thirdTab, true) and Selected(firstTab, false)
        and firstTab.ActiveMiddle.alpha == 0, "recycled ChatConfig tabs lost their owned selected style")
    Expect(secondCategory.locked and Selected(secondCategory, true) and Selected(firstCategory, false),
        "clicking a native ChatConfig category left stale selected chrome")
    Expect(lateRow.NineSlice.TopEdge.alpha == 0 and unrelated.NineSlice.TopEdge.alpha == 0.5,
        "ChatConfig did not skin newly created filter rows within its own groups")
    Expect(TintedCheck(lateRow.CheckButton) and not TintedCheck(unrelated.CheckButton),
        "lazy Chat filter creation missed a checkbox or painted a foreign one")
    local newTier, newChild = Checkbox(), Checkbox()
    newTier.children[1] = newChild
    _G.ChatConfig_CreateTieredCheckboxes(tiered, newTier)
    Expect(TintedCheck(newTier) and TintedCheck(newChild), "new Combat Log parent or child missed the theme")
    newChild.checkedArt = CheckTexture(1)
    _G.ChatConfig_UpdateTieredCheckboxes(tiered, 2)
    Expect(newTier.checked and newChild.checked and TintedCheck(newChild),
        "programmatic Combat Log update did not repaint replacement check art")
    lateRow.CheckButton.disabledArt = CheckTexture(0.6)
    _G.ChatConfig_UpdateCheckboxes(group)
    Expect(TintedCheck(lateRow.CheckButton), "programmatic Chat filter update missed replacement disabled art")

    locked = true
    tieredChild.checkedArt = CheckTexture(1)
    _G.ChatConfig_UpdateTieredCheckboxes(tiered, 1)
    Expect(not TintedCheck(tieredChild), "Combat Log checkmark changed during combat")
    frame.ChatTabManager:UpdateSelection(2)
    _G.ChatConfigCategory_OnClick(firstCategory)
    local key, refresh = next(jobs)
    Expect(key and next(jobs, key) == nil and Selected(thirdTab, true) and firstTab.ActiveMiddle.alpha == 1,
        "ChatConfig updated native cosmetics in combat or queued multiple jobs")
    locked = false
    if key then
        jobs[key] = nil
        refresh()
    end
    Expect(Selected(secondTab, true) and Selected(thirdTab, false) and Selected(firstCategory, true),
        "ChatConfig combat replay did not read the latest native selection")
    Expect(TintedCheck(tieredChild), "deferred Combat Log checkmark did not repaint")
    GenericWindows.Disable(owner)
    Expect(firstRow.NineSlice.TopEdge.alpha == 0.5 and lateRow.NineSlice.TopEdge.alpha == 0.5
        and firstCategory.Highlight.alpha == 1 and thirdTab.Left.alpha == 1 and Hidden(panel),
        "ChatConfig disable did not restore native art and hide owned surfaces")
    Expect(not TintedCheck(firstRow.CheckButton) and not TintedCheck(tieredChild)
        and tieredChild.checkedArt.red == 1 and tieredChild.disabledArt.alpha == 0.6 and tieredChild.checked,
        "ChatConfig disable did not restore native marks or changed the filter value")
    local disabledRow = FilterRow()
    _G.ChatConfig_CreateCheckboxes(group, disabledRow)
    frame.ChatTabManager:UpdateSelection(3)
    Expect(disabledRow.NineSlice.TopEdge.alpha == 0.5 and Hidden(thirdTab) and not TintedCheck(disabledRow.CheckButton),
        "disabled ChatConfig hooks still styled the native window")
end)

if #failures > 0 then
    error(#failures .. " adapter check(s) failed:\n  " .. table.concat(failures, "\n  "))
end
print("Suite skin generic windows: " .. checks .. " checks passed")

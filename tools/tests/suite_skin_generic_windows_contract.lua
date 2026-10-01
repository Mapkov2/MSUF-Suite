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
    local NS = {}
    assert(loadfile(skin .. "Adapters/Catalog.lua"))("MSUF_Suite_Skin", NS)
    local data = NS.BlizzardCatalogData
    local byte, concat, hashed = string.byte, table.concat, 0
    string.byte = function(...) hashed = hashed + 1; return byte(...) end
    assert(loadfile(skin .. "Adapters/CatalogGlass.lua"))("MSUF_Suite_Skin", NS)
    string.byte = byte
    Check(hashed == 0, "loading the catalog hashed it in game")
    local catalog = NS.BlizzardCatalog
    Check(catalog.IsGlassContractValid() and catalog.glass.valid
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
        local copy = {}
        assert(loadstring(modified, "modified catalog"))("MSUF_Suite_Skin", copy)
        local modifiedData = copy.BlizzardCatalogData
        assert(loadfile(skin .. "Adapters/CatalogGlass.lua"))("MSUF_Suite_Skin", copy)
        return copy.BlizzardCatalog, modifiedData
    end
    -- An unreviewed catalog fails this contract; the game keeps its entries.
    local unreviewed, unreviewedData = LoadModified('REVIEWED_CATALOG_FINGERPRINT = "[^"]+"',
        'REVIEWED_CATALOG_FINGERPRINT = "00000000-00000000"')
    Check(HasProblem(ReviewProblems(unreviewedData, unreviewed), "catalog-snapshot-unreviewed:"),
        "the review contract missed an unreviewed catalog snapshot")
    Check(unreviewed.ValidateGlassEntry(unreviewed.entries[1]) and unreviewed.IsGlassContractValid(),
        "an unreviewed catalog snapshot switched the catalog off in game")
    local recounted, recountedData = LoadModified("REVIEWED_CATALOG_ROOTS = %d+", "REVIEWED_CATALOG_ROOTS = 1")
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
    WindowControls = { Attach = function() end, DisableOwner = function() end },
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
for _, file in ipairs({ "Core/Safety.lua", "Core/SuiteOwnership.lua",
    "Adapters/Catalog.lua", "Adapters/CatalogGlass.lua",
    "Adapters/AdapterKit.lua", "Adapters/SharedChrome.lua",
    "Adapters/GenericWindows.lua", "Adapters/GenericWindowsFrames.lua", "Adapters/GenericWindowsCatalog.lua" }) do
    assert(loadfile(skin .. file))("MSUF_Suite_Skin", NS)
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

locked = true
rowOne.childReads, counters.yellow = 0, 0
scrollBox:Initialize(rowOne)
locked = false
Check(rowOne.childReads == 0 and counters.yellow == 0, "pooled rows were painted in combat")

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
Check(GenericWindows.GetCatalogCount() > 0, "reviewed catalog entries are missing")
local sort, sorted = table.sort, 0
table.sort = function(...) sorted = sorted + 1; return sort(...) end
GenericWindows.GetCounts()
GenericWindows.GetCategories()
local catalogCount = GenericWindows.GetCatalogCount()
table.sort = sort
Check(sorted == 0 and catalogCount > 0, "catalog entries were rebuilt for a status query")

-- Surfaces a running Suite module replaces stay with that module
-- (Core/SuiteOwnership.lua); free ones keep their skin.
local suiteOwned = {}
MSUFSuite = { Suite = { OwnsBlizzardSurface = function(surface) return suiteOwned[surface] == true end } }
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
    assert(loadfile(skin .. "Adapters/" .. file))("MSUF_Suite_Skin", namespace or NS)
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

Section("catalog entries are isolated", function()
    local raising = Frame("CharacterFrame")
    function raising:GetChildren() error("contract: CharacterFrame raised") end
    local bank = Frame("BankFrame")
    _G.CharacterFrame, _G.BankFrame = raising, bank
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
    _G.CharacterFrame, _G.BankFrame = nil, nil
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
    Load("DeepWindows.lua", deepNS)
    Load("DeepWindowsProfessions.lua", deepNS)
    local calls, restore = CountingApplyFrame()

    local professionsMixin = {}
    function professionsMixin:Refresh() end
    local craftingMixin = {}
    function craftingMixin:Init() end
    function craftingMixin:Refresh() end
    function craftingMixin:SchematicPostInit() end
    _G.ProfessionsMixin, _G.ProfessionsCraftingPageMixin = professionsMixin, craftingMixin
    -- XML frames carry their own copy of the mixin.
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

    deepNS.DeepWindows.Apply("deep")
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
    -- One ProfessionsFrame:Refresh burst: the window pass covers its pages.
    professions:Refresh()
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
    NS.ControlSkin.ApplyButton = function(button)
        if button == raiseFor then error("contract: item skin raised") end
        itemSkins[button] = (itemSkins[button] or 0) + 1
        return {}
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
    Expect(itemSkins[items[2]] == 2 and itemSkins[items[1]] == 1,
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
    spells.TabSystem = { tabs = { tab } }
    -- The spell book's search box takes the shared search box skin.
    local spellBook = Frame(nil)
    spellBook.SearchBox = Frame(nil)
    spells.SpellBookFrame = spellBook
    local searchBoxes = {}
    local applySearchBox = NS.ControlSkin.ApplySearchBox
    NS.ControlSkin.ApplySearchBox = function(box)
        searchBoxes[box] = true
        return {}
    end
    local getColor = NS.Theme.GetColor
    NS.Theme.GetColor = function() return 0.71, 0.72, 0.73, 1 end
    NS.PlayerSpellsSkin.Apply(spells, "spells")
    NS.ControlSkin.ApplySearchBox = applySearchBox
    Expect(searchBoxes[spellBook.SearchBox], "the spell book search box was not skinned")
    NS.PlayerSpellsSkin:OnFrameTabSet(spells)
    Expect(Near(label.color[1], 0.71), "the selected tab label was not themed")
    NS.PlayerSpellsSkin.Disable(spells, "spells")
    NS.Theme.GetColor = getColor
    Expect(Near(label.color[1], 1) and Near(label.color[2], 0.82),
        "a tab refresh recaptured our own color as the native one")
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
    Expect(skinnedInset[buttons[1]] == 2 and skinnedInset[late] == 2,
        "the Game Menu pool or other direct buttons lost their normal inset")
    -- The reported regression had identical 200x36 button frame bounds for
    -- Macros and MSUF, but MSUF's painted edge lost two pixels per side.
    -- Verify the rendered edge reaches those shared bounds after the late pass.
    local macroBounds = { left = 1180, right = 1380, top = 400, bottom = 364 }
    local function BorderMatchesMacros(inset)
        if type(inset) ~= "number" then return false end
        local msufBounds = { left = 1180, right = 1380, top = 400, bottom = 364 }
        return msufBounds.left + inset == macroBounds.left
            and msufBounds.right - inset == macroBounds.right
            and msufBounds.top - inset == macroBounds.top
            and msufBounds.bottom + inset == macroBounds.bottom
    end
    Expect(BorderMatchesMacros(panelInset[msuf]),
        "the MSUF fallback button border does not align with Macros")
    menu.MSUF, menu.children[4] = msufThree, msufThree
    menu:InitButtons()
    Expect(BorderMatchesMacros(skinnedInset[msufThree]),
        "the MSUF three-slice button border does not align with Macros")
    for _, stop in ipairs({ "hidden", "combat", "disabled" }) do
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

Section("major windows pvp categories", function()
    Load("MajorWindows.lua")
    _G.PVPUIFrame = Frame("PVPUIFrame")
    local queue = Frame("PVPQueueFrame")
    for index = 1, 5 do queue["CategoryButton" .. index] = Frame("CategoryButton" .. index) end
    _G.PVPQueueFrame = queue
    _G.HonorFrame = Frame("HonorFrame")
    _G.LFGListPVPStub = Frame("LFGListPVPStub")
    _G.TrainingGroundsFrame = Frame("TrainingGroundsFrame")
    NS.MajorWindows.Apply("major")
    Expect(NS.MajorWindows.GetIndicator(queue.CategoryButton1) ~= nil
        and NS.MajorWindows.GetIndicator(queue.CategoryButton3) ~= nil
        and NS.MajorWindows.GetIndicator(queue.CategoryButton4) ~= nil,
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
    Expect(Near(icon.a, 0.5), ("state hooks compounded the micro icon opacity to %.3f"):format(icon.a))
    microNS.MicroMenuSkin.Disable()
    Expect(Near(icon.a, 1), "disable did not give the micro icon its native color back")
    _G.MicroMenu, _G.MicroMenuContainer, _G.CharacterMicroButton = nil, nil, nil
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
    for _, file in ipairs({ "OwnedMicroBarLayout.lua", "OwnedMicroBarVisibility.lua", "OwnedMicroBar.lua" }) do
        Load(file, microNS)
    end
    local eventFrame = created[1]
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
    Expect(attaches == 0, "a Micro Bar state hook built and attached a new button plate")

    -- Combat end, a loading screen or a pet battle only place the bar again.
    attaches, prepares = 0, 0
    for widget in pairs(placements) do placements[widget] = nil end
    for _, event in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "PET_BATTLE_CLOSE" }) do
        eventFrame.scripts.OnEvent(eventFrame, event)
    end
    Expect(prepares == 0 and attaches == 0,
        "combat end re-skinned the owned Micro Bar instead of placing it again")
    Expect((placements[bar] or 0) > 0 and (placements[root] or 0) > 0,
        "combat end did not place the owned Micro Bar again")
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
    _G.MicroMenu, _G.MicroMenuContainer = nil, nil
    _G.CharacterMicroButton, _G.QuestLogMicroButton = nil, nil
end)

Section("world map", function()
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
    _G.QuestLogQuests_Update()
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
    NS.CommunitiesSkin.Disable(communities, "communities")
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
        "EditMode", "MacroWindow", "MicroMenu", "OwnedMicroBar" }) do
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
    for _, file in ipairs({ "MicroMenu", "OwnedMicroBar", "SharedChrome", "AdapterKit" }) do
        Expect(not ReadSource(skin .. "Adapters/" .. file .. ".lua"):find('Call%(%s*[%w_]+,%s*"GetParent"%)'),
            file .. " compares a GetParent result that can be secret")
    end
    -- Stored-colour checks go through the secret-safe Safety.ColorMatches.
    for _, file in ipairs({ "ChatFrames", "QuestText", "AdapterKit", "MicroMenu" }) do
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
    for _, file in ipairs({ "GenericWindows", "GenericWindowsFrames", "GenericWindowsCatalog" }) do
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
        { "OwnedMicroBarLayout", "OwnedMicroBarVisibility", "OwnedMicroBar", "MicroMenu", "MicroMenuSettings" },
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

if #failures > 0 then
    error(#failures .. " adapter check(s) failed:\n  " .. table.concat(failures, "\n  "))
end
print("Suite skin generic windows: " .. checks .. " checks passed")

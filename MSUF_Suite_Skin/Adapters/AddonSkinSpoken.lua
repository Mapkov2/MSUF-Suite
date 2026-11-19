local _, NS = ...

-- Spoken 3.10 creates its players and Place Story panel lazily, including
-- when narration starts automatically.
-- Observe construction/configuration, never the audio queue or per-frame Tick.
local SpokenSkin = {}
NS.SpokenSkin = SpokenSkin
local Safety, Visuals = NS.Safety, NS.AddonSkinVisuals
local hooked = setmetatable({}, { __mode = "k" })
local waiting = setmetatable({}, { __mode = "k" })
local PLACE_PANEL, SUBTITLE = "SpokenPlacesPanel", "SpokenSubtitleFrame"
local separatorOwner = "spoken-separators"
local subtitleDots = { "dot", "heldDot", "moreDot" }
local events, separatorsActive = CreateFrame("Frame"), false
local playerNames = { SpokenPlayerFrame = true, SpokenMinimalPlayerFrame = true,
    SpokenDialogueUIPlayerFrame = true }
local classic = { role = "shell", maxDepth = 0, maxNodes = 0, registerDynamicRows = false, allowImplicitProtected = false }
local transparent = { rootSurface = false, maxDepth = 0, maxNodes = 0,
    registerDynamicRows = false, allowImplicitProtected = false }
local methods = {
    PlayerFrame = { "Initialize", "InitDisplay", "RefreshConfig", "ApplyArt" },
    MinimalPlayer = { "Initialize", "BuildMenu", "RefreshConfig" },
    DialogueUIPlayer = { "Initialize", "RefreshConfig" },
    Options = { "Open", "ToggleCompendium" }, Transcript = { "Initialize" },
}

local function Changed()
    if NS.AddonSkins.IsEnabled("spoken") then NS.AddonSkins.RefreshAddon("spoken") end
end

function SpokenSkin.CanTouch(frame)
    local frozen = Safety.Field(frame, "spokenFrozen")
    if not Safety.Public(frozen) or frozen == true then return false end
    local environment = rawget(_G, "SpokenEnv")
    local player = Safety.Field(environment, "DialogueUIPlayer")
    local playerFrame = Safety.Field(player, "frame")
    if not Safety.Public(playerFrame) then return false end
    if playerFrame == frame then
        local buffered = Safety.Field(player, "buffered")
        if not Safety.Public(buffered) or buffered == true then return false end
    end
    return true
end

function SpokenSkin.Defer(frame, job) waiting[frame] = job end

local function Unbuffered()
    for frame, job in pairs(waiting) do
        if SpokenSkin.CanTouch(frame) then waiting[frame] = nil NS.Registry.QueueJob(job) end
    end
    Changed()
end

local function Hook(module, key, callback)
    if not Safety.HasMethod(module, key) then return end
    local hooks = hooked[module]
    if not hooks then hooks = {} hooked[module] = hooks end
    if hooks[key] == module[key] then return end
    hooksecurefunc(module, key, callback or Changed)
    hooks[key] = module[key]
end

local function UsesBlizzardTypography()
    local db = NS.DB
    return db and db.enabled == true and db.blizzardWindowsEnabled ~= false
        and db.typography and db.typography.enabled == true
end

local SyncSeparators
local function SeparatorsChanged()
    if separatorsActive or UsesBlizzardTypography() then NS.Registry.QueueJob(SyncSeparators) end
end

local function RootBuilt()
    SeparatorsChanged()
    Changed()
end

-- Spoken inherits GameFont objects. Keep these separators readable when the
-- Blizzard font override is on, even with optional addon decoration disabled.
SyncSeparators = function()
    local subtitle = Safety.Field(rawget(_G, "SpokenEnv"), "Subtitle")
    local places = rawget(_G, "SpokenPlaces")
    local enabled = UsesBlizzardTypography()
    local needsLoad = enabled and ((not subtitle and NS.Client.HasAddOn("Spoken"))
        or (not places and NS.Client.HasAddOn("Spoken_Places")))
    if needsLoad then events:RegisterEvent("ADDON_LOADED") else events:UnregisterEvent("ADDON_LOADED") end
    if not enabled then
        if separatorsActive then Visuals.Release(separatorOwner) end
        separatorsActive = false
        return
    end
    separatorsActive = true
    Hook(subtitle, "Build", RootBuilt)
    Hook(places, "SetupMapPanel", RootBuilt)
    Hook(places, "ApplyPanelOptions", SeparatorsChanged)
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local frame = Safety.Field(subtitle, "frame")
    if Visuals.Safe(frame) and SpokenSkin.CanTouch(frame) then
        for _, key in ipairs(subtitleDots) do Visuals.Label(Safety.Field(subtitle, key), separatorOwner, font) end
    end
    local panel = rawget(_G, PLACE_PANEL)
    if Visuals.Safe(panel) then
        local page = Safety.Field(panel, "page")
        local label = Safety.Field(Safety.Field(page, "sub"), "text")
        Visuals.Label(label, separatorOwner, font)
    end
end

NS.Registry.AddListener(SpokenSkin, function(_, domain)
    if domain == "typography" or domain == "profile" or domain == "adapter" or domain == "theme" then
        SeparatorsChanged()
    end
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_LOGIN" then self:UnregisterEvent(event) end
    if event == "PLAYER_LOGIN" or addon == NS.addonName or addon == "Spoken" or addon == "Spoken_Places" then
        NS.Registry.QueueJob(SyncSeparators)
    end
end)

function SpokenSkin.Install()
    local environment = rawget(_G, "SpokenEnv")
    if type(environment) ~= "table" then return end
    NS.CompendiumSkin.Install()
    for name, list in pairs(methods) do
        local module = rawget(environment, name)
        for index = 1, #list do Hook(module, list[index]) end
    end
    Hook(rawget(environment, "Subtitle"), "Build", RootBuilt)
    Hook(rawget(_G, "SpokenPlaces"), "SetupMapPanel", RootBuilt)
    local dialogue = rawget(environment, "DialogueUIPlayer")
    if Safety.HasMethod(dialogue, "Unbuffer") then
        local hooks = hooked[dialogue]
        if not hooks then hooks = {} hooked[dialogue] = hooks end
        if hooks.Unbuffer ~= dialogue.Unbuffer then
            hooksecurefunc(dialogue, "Unbuffer", Unbuffered)
            hooks.Unbuffer = dialogue.Unbuffer
        end
    end
    local api = rawget(_G, "Spoken")
    for _, key in ipairs({ "ShowContribution", "ShowReport", "ShowGatherInstructions", "ShowGatheredText" }) do Hook(api, key) end
    local compendium = rawget(_G, "SpokenCompendium")
    Hook(compendium, "Show")
    Hook(compendium, "Toggle")
end

function SpokenSkin.Direct(frame)
    local name = Safety.Read(frame, "GetName")
    return frame == rawget(_G, "SpokenDialogueUIPlayerFrame")
        or name == "SpokenDialogueUIPlayerFrame" or name == SUBTITLE
end

local function PaintSubtitle(frame, owner)
    local subtitle = Safety.Field(rawget(_G, "SpokenEnv"), "Subtitle")
    local target = Safety.Field(subtitle, "frame")
    if not Safety.Public(target) or target ~= frame then return false end
    Visuals.Text(Safety.Field(subtitle, "title"), owner, "title", false)
    Visuals.Tint(Safety.Field(subtitle, "shadow"), owner, "background")
    Visuals.Tint(Safety.Field(subtitle, "fill"), owner, "accent")
    return true
end

local Labels
local function ChildLabels(owner, remaining, ...)
    for index = 1, select("#", ...) do
        if remaining <= 0 then break end
        remaining = Labels(select(index, ...), owner, remaining - 1)
    end
    return remaining
end

Labels = function(frame, owner, remaining)
    -- Spoken reparents this shared caption widget between all player styles,
    -- including the framebuffer variant. It must never inherit our leases
    -- from another player's owner.
    if frame == rawget(_G, "SpokenTranscriptFrame") then return remaining end
    if not Visuals.Safe(frame) then return remaining end
    for _, region in ipairs({ Safety.Call(frame, "GetRegions") }) do Visuals.Label(region, owner) end
    return ChildLabels(owner, remaining, Safety.Call(frame, "GetChildren"))
end

function SpokenSkin.PaintDirect(frame, owner)
    if not SpokenSkin.CanTouch(frame) then return false end
    if Safety.Read(frame, "GetName") == SUBTITLE then return PaintSubtitle(frame, owner) end
    -- This variant becomes a native framebuffer during Spoken's fades. No
    -- shared Surface/Control/Motion registration may repaint it while frozen.
    local environment = rawget(_G, "SpokenEnv")
    local player = Safety.Field(environment, "DialogueUIPlayer")
    local parchments = Safety.Field(player, "parchments")
    if type(parchments) == "table" then
        for index = 1, math.min(#parchments, 3) do Visuals.Tint(parchments[index], owner, "background") end
    end
    Labels(frame, owner, 480)
    return true
end

function SpokenSkin.Mode(frame, fallback)
    local name = Safety.Read(frame, "GetName")
    if name == "SpokenPlayerFrame" or name == PLACE_PANEL then return classic end
    if playerNames[name] then return transparent end
    return fallback
end

local function PaintPlace(frame, owner)
    Visuals.Backdrop(frame, owner, "shell")
    local title = Safety.Field(Safety.Field(frame, "TitleContainer"), "TitleText")
    Visuals.Text(title, owner, "title")
    local close = Safety.Field(frame, "close")
    if Visuals.Safe(close) then NS.WindowActionSkin.ApplyExplicit(close, owner, "close") end
    -- The rim only draws the decorative quest-log surround. The parchment,
    -- ink, picture, 3D model and story controls belong to the page.
    local rim = Safety.Field(frame, "rim")
    if Visuals.Safe(rim) then NS.Cosmetics.Fade(rim, owner) end
end

local function Regions(owner, ...)
    for index = 1, math.min(select("#", ...), 64) do Visuals.Label(select(index, ...), owner) end
end

local function Children(frame, owner, ...)
    local portrait = Safety.Field(frame, "portrait")
    for index = 1, math.min(select("#", ...), 8) do
        local child = select(index, ...)
        if child ~= portrait and Visuals.Safe(child) then
            Labels(child, owner, 64)
        end
    end
end

function SpokenSkin.Paint(frame, owner)
    if NS.CompendiumSkin.Paint(frame, owner) then return end
    local name = Safety.Read(frame, "GetName")
    if name == PLACE_PANEL then return PaintPlace(frame, owner) end
    if not playerNames[name] then Visuals.Tree(frame, owner) return end
    local background = Safety.Field(frame, "background")
    if Safety.Read(background, "GetObjectType") == "Texture" then NS.Cosmetics.Fade(background, owner) end
    if name == "SpokenMinimalPlayerFrame" then
        local environment = rawget(_G, "SpokenEnv")
        local minimal = Safety.Field(environment, "MinimalPlayer")
        Visuals.Backdrop(Safety.Field(minimal, "panel"), owner, "panel")
        local paper = Safety.Field(minimal, "paper")
        if Safety.Read(paper, "GetObjectType") == "Texture" then NS.Cosmetics.Fade(paper, owner) end
    end
    Regions(owner, Safety.Call(frame, "GetRegions"))
    Children(frame, owner, Safety.Call(frame, "GetChildren"))
end

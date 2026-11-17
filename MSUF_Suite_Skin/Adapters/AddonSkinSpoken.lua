local _, NS = ...

-- Spoken 3.9 UI/PlayerFrame.lua, MinimalPlayer.lua and DialogueUIPlayer.lua
-- create their players lazily, including when narration starts automatically.
-- Observe construction/configuration, never the audio queue or per-frame Tick.
local SpokenSkin = {}
NS.SpokenSkin = SpokenSkin
local Safety, Visuals = NS.Safety, NS.AddonSkinVisuals
local hooked = setmetatable({}, { __mode = "k" })
local waiting = setmetatable({}, { __mode = "k" })
local playerNames = { SpokenPlayerFrame = true, SpokenMinimalPlayerFrame = true,
    SpokenDialogueUIPlayerFrame = true, SpokenSubtitleFrame = true }
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

local function Hook(module, key)
    if not Safety.HasMethod(module, key) then return end
    local hooks = hooked[module]
    if not hooks then hooks = {} hooked[module] = hooks end
    if hooks[key] == module[key] then return end
    hooksecurefunc(module, key, Changed)
    hooks[key] = module[key]
end

function SpokenSkin.Install()
    local environment = rawget(_G, "SpokenEnv")
    if type(environment) ~= "table" then return end
    NS.CompendiumSkin.Install()
    for name, list in pairs(methods) do
        local module = rawget(environment, name)
        for index = 1, #list do Hook(module, list[index]) end
    end
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
    return frame == rawget(_G, "SpokenDialogueUIPlayerFrame")
        or Safety.Read(frame, "GetName") == "SpokenDialogueUIPlayerFrame"
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
    if name == "SpokenPlayerFrame" then return classic end
    if playerNames[name] then return transparent end
    return fallback
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

local _, NS = ...

local TutorialPointers = {}
NS.TutorialPointers = TutorialPointers
local Safety, Kit = NS.Safety, NS.AdapterKit
local OWNER = "tutorialPointers"
local MODE = {
    role = "popup", maxDepth = 0, maxNodes = 1, motion = false,
    registerDynamicRows = false,
}
local watched = setmetatable({}, { __mode = "k" })
local installed = setmetatable({}, { __mode = "k" })
local managers = {
    Blizzard_TutorialManager = "TutorialPointerFrame",
    Blizzard_BoostTutorial = "NPE_TutorialPointerFrame",
}
local enabled = false
local arrows = { "UP", "DOWN", "LEFT", "RIGHT" }

local function TintArrow(texture)
    local atlas = Safety.Read(texture, "GetAtlas")
    if type(atlas) == "string" and atlas:match("^NPE_Arrow") then
        NS.Checkmarks.TrackTexture(texture, OWNER, "accent")
    end
end

local function StyleArrows(pointer)
    for index = 1, #arrows do
        local name = "Arrow_" .. arrows[index]
        Kit.ForEachRegion(Safety.Field(pointer, name .. "1"), TintArrow)
        Kit.ForEachRegion(Safety.Field(pointer, name .. "2"), TintArrow)
    end
end

local function Enabled()
    return enabled and NS.DB and NS.DB.enabled
        and NS.GenericWindows.IsCategoryEnabled("tutorial")
end

local function Paint(pointer)
    if not Enabled() or NS.IsCombatLocked()
        or Safety.Read(pointer, "IsVisible") ~= true then return end
    local content = Safety.Field(pointer, "Content")
    if not Safety.Public(content) or not Safety.CanDecorate(content) then return end
    NS.GenericWindows.ApplyFrame(content, OWNER, MODE)
    NS.BlizzardYellow.TrackFrame(content)
    StyleArrows(pointer)
end

local function Queue(pointer)
    if not Safety.Public(pointer) or type(pointer) ~= "table" then return end
    local job = watched[pointer]
    if not job then
        job = function() Paint(pointer) end
        watched[pointer] = job
    end
    NS.Registry.QueueJob(job)
end

local function PointShown(manager)
    if not Enabled() or NS.IsCombatLocked() then return end
    local nextID = Safety.Field(manager, "NextID")
    local visible = Safety.Field(manager, "InUseFrames")
    if not Safety.Public(nextID) or type(nextID) ~= "number"
        or not Safety.Public(visible) or type(visible) ~= "table" then return end
    Queue(Safety.Field(visible, nextID - 1))
end

local function WatchManager(name)
    local manager = Safety.Field(_G, name)
    if not Safety.Public(manager) or not Safety.HasMethod(manager, "Show") then return end
    if not installed[manager] then
        if not Kit.HookFunction(manager, "Show", Safety.Isolated(PointShown)) then return end
        installed[manager] = true
    end
    local shown = Safety.Field(manager, "InUseFrames")
    if Safety.Public(shown) and type(shown) == "table" then
        for _, pointer in pairs(shown) do Queue(pointer) end
    end
end

function TutorialPointers.Enable()
    enabled = true
    if not Enabled() then return end
    for _, name in pairs(managers) do WatchManager(name) end
end

function TutorialPointers.AddonLoaded(addon)
    local name = managers[addon]
    if name and Enabled() then WatchManager(name) end
end

function TutorialPointers.Disable()
    enabled = false
    NS.GenericWindows.Disable(OWNER)
end

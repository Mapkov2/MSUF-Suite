-- Window controls keep a stored panel position through Blizzard's panel
-- layout, whichever path placed the panel. A profile without stored positions
-- followed by one with them used to place the Character window without the
-- UpdateUIPanelPositions post-hook, so the next native layout pass (the
-- Reputation tab changes the window's width) snapped it back to Blizzard's slot.
-- Usage: lua suite_window_controls_profile_hook_contract.lua <Suite root> [WindowControls.lua]
local root = assert(arg[1], "Suite root required")
local source = arg[2] or root .. "/MSUF_Suite_Skin/Rendering/WindowControls.lua"
local checks = 0
local function Check(value, label)
    assert(value, label)
    checks = checks + 1
end

securecallfunction = function(callback, ...) return callback(...) end
InCombatLockdown = function() return false end
IsMouseButtonDown = function() return false end
GetCursorPosition = function() return 0, 0 end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
HideUIPanel = function(frame) frame:Hide() end
ShowUIPanel = function(frame) frame:Show() end

local function Frame(name, parent, kind)
    local frame = {
        name = name, parent = parent, kind = kind or "Frame", shown = true,
        scale = 1, width = 540, height = 500, left = 16, top = 964,
        movable = true, scripts = {}, hooks = {},
    }
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:GetObjectType() return self.kind end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetScale() return self.scale end
    function frame:GetEffectiveScale() return self.scale end
    function frame:SetScale(value) self.scale = value end
    function frame:IsProtected() return false, false end
    function frame:IsForbidden() return false end
    function frame:IsShown() return self.shown end
    function frame:IsMouseOver() return false end
    function frame:GetFrameLevel() return self.frameLevel or 1 end
    function frame:GetLeft() return self.left end
    function frame:GetTop() return self.top end
    function frame:GetNumPoints() return self.point and 1 or 0 end
    function frame:GetPoint() if self.point then return unpack(self.point, 1, 5) end end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetWidth(width) self.width = width end
    function frame:SetHeight(height) self.height = height end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetAllPoints() end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetFrameLevel(value) self.frameLevel = value end
    function frame:SetFrameStrata() end
    function frame:SetClampedToScreen() end
    function frame:SetMovable(value) self.movable = value end
    function frame:IsMovable() return self.movable end
    function frame:RegisterForDrag() end
    function frame:EnableMouse() end
    function frame:RegisterForClicks() end
    function frame:SetButtonState() end
    function frame:SetNormalTexture() end
    function frame:SetHighlightTexture() end
    function frame:SetPushedTexture() end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:HookScript(event, callback)
        self.hooks[event] = self.hooks[event] or {}
        table.insert(self.hooks[event], callback)
    end
    function frame:Show()
        self.shown = true
        for _, callback in ipairs(self.hooks.OnShow or {}) do callback(self) end
    end
    function frame:Hide()
        self.shown = false
        for _, callback in ipairs(self.hooks.OnHide or {}) do callback(self) end
    end
    function frame:CreateTexture()
        return { SetAllPoints = function() end, SetColorTexture = function() end }
    end
    function frame:CreateFontString()
        return { SetPoint = function() end, SetJustifyH = function() end,
            SetText = function() end, SetTextColor = function() end }
    end
    return frame
end
CreateFrame = function(kind, _, parent) return Frame(nil, parent, kind) end
UIParent = Frame("UIParent")
UIParent.width, UIParent.height = 1920, 1080

local NATIVE_X, NATIVE_Y = 16, -116
local character, hookInstalls

-- The client's hooksecurefunc: the global becomes the original followed by
-- the post-hook.
hooksecurefunc = function(name, post)
    assert(name == "UpdateUIPanelPositions", "unexpected secure hook " .. tostring(name))
    hookInstalls = hookInstalls + 1
    local original = _G[name]
    _G[name] = function(...)
        original(...)
        post(...)
    end
end

-- A fresh client session: the panel manager's left slot and the Character
-- window, whose UpdateSize mirrors upstream/live
-- Blizzard_UIPanels_Game/Mainline/CharacterFrame.lua (CharacterFrameMixin:UpdateSize,
-- Reputation 400 wide, expanded paper doll 540) and calls the global
-- UpdateUIPanelPositions when the width changes. That global re-anchors the
-- left panel at TOPLEFT (leftOffset + xoffset) / scale, yPos / scale
-- (Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua, UpdateUIPanelPositions).
local function NewSession(forever, look)
    hookInstalls = 0
    character = Frame("CharacterFrame", UIParent)
    character.CloseButton = Frame(nil, character, "Button")
    character.activeSubframe = "PaperDollFrame"
    character:SetPoint("TOPLEFT", "UIParent", "TOPLEFT", NATIVE_X, NATIVE_Y)
    function character:UpdateSize()
        local oldWidth = self:GetWidth()
        local width = self.activeSubframe == "PaperDollFrame" and 540 or 400
        self:SetWidth(width)
        if oldWidth ~= width then UpdateUIPanelPositions(self) end
    end
    UIPanelWindows = { CharacterFrame = { area = "left", pushable = 3 } }
    UpdateUIPanelPositions = function()
        local scale = character:GetScale()
        character:ClearAllPoints()
        character:SetPoint("TOPLEFT", "UIParent", "TOPLEFT", NATIVE_X / scale, NATIVE_Y / scale)
    end

    local listeners, jobs = {}, {}
    local NS = {
        L = setmetatable({}, { __index = function(_, key) return key end }),
        IsCombatLocked = function() return InCombatLockdown() end,
        Theme = { GetColor = function() return 0.2, 0.3, 0.4, 1 end },
        Registry = {
            AddListener = function(owner, callback) listeners[owner] = callback end,
            QueueJob = function(job) jobs[#jobs + 1] = job end,
        },
        BlizzardCatalog = { FindByFrame = function(name)
            if name == "CharacterFrame" then return { category = "character" } end
        end },
        CombatGate = { RunOrDefer = function(_, callback) callback() return true end },
        Client = { isForever = forever == true },
        Adapters = { ApplyAll = function() end },
    }
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Safety.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/Defaults.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(root .. "/MSUF_Suite_Skin/Core/DefaultsLooks.lua"))("MSUF_Suite_Skin", NS)
    assert(loadfile(source))("MSUF_Suite_Skin", NS)
    local session = { NS = NS }
    function session.Profile(positions)
        NS.DB = { enabled = true, skins = { blizzardWindows = true }, theme = { look = look or "midnight" },
            windowControls = { enabled = true, scales = {}, positions = positions } }
    end
    -- Registry.NotifyListeners("profile", "activate"), then the next frame's jobs.
    function session.NotifyProfile()
        for owner, callback in pairs(listeners) do callback(owner, "profile", "activate") end
        local queued = jobs
        jobs = {}
        for _, job in ipairs(queued) do job() end
    end
    return session
end

local function At(x, y)
    local point = character.point
    return point and point[1] == "TOPLEFT" and point[4] == x and point[5] == y
end

-- Login on a profile without stored positions, then activate one that has
-- them. Each placement path on its own must leave the panel layout hook in
-- place, so the Reputation tab's width change keeps the stored position.
local stored = { CharacterFrame = { x = 600, y = -300 } }
local paths = {
    -- Database.ApplyActiveSettings -> Adapters.ApplyAll -> Attach (existing panel).
    attach = function(session) session.NS.WindowControls.Attach(character, "blizzardWindows") end,
    -- Database.ApplyActiveSettings -> NotifyListeners("profile") -> Refresh job.
    refresh = function(session) session.NotifyProfile() end,
    -- The player opens the window again after the switch.
    reopen = function()
        character:Hide()
        character:Show()
    end,
}
for _, name in ipairs({ "attach", "refresh", "reopen" }) do
    local session = NewSession(false)
    session.Profile({})
    Check(session.NS.WindowControls.Attach(character, "blizzardWindows"), name .. ": Character window not attached")
    Check(At(NATIVE_X, NATIVE_Y), name .. ": a profile without positions moved the window")
    session.Profile(stored)
    paths[name](session)
    Check(At(600, -300), name .. ": the new profile's stored position was not applied")
    character.activeSubframe = "ReputationFrame"
    character:UpdateSize()
    Check(character.width == 400 and At(600, -300),
        name .. ": the Reputation tab's panel layout snapped the window back to Blizzard's slot")
    character.activeSubframe = "PaperDollFrame"
    character:UpdateSize()
    Check(At(600, -300), name .. ": returning to the paper doll lost the stored position")
    Check(hookInstalls == 1, name .. ": the panel layout hook was installed " .. hookInstalls .. " times")
end

-- The hook is installed once however often panels are placed, and a session
-- that never places a panel never installs it.
do
    local session = NewSession(false)
    session.Profile(stored)
    Check(session.NS.WindowControls.Attach(character, "blizzardWindows") and At(600, -300),
        "login with stored positions did not place the window")
    for _ = 1, 5 do
        session.NotifyProfile()
        character:Hide()
        character:Show()
        session.NS.WindowControls.Attach(character, "blizzardWindows")
        UpdateUIPanelPositions(character)
    end
    Check(hookInstalls == 1 and At(600, -300), "repeated placements installed the hook again or lost the position")
    local positionless = NewSession(false)
    positionless.Profile({})
    positionless.NS.WindowControls.Attach(character, "blizzardWindows")
    positionless.NotifyProfile()
    character:Hide()
    character:Show()
    Check(hookInstalls == 0, "a session without placed panels hooked Blizzard's panel layout")
end

-- Forever's Glass look docks the Character window by default without a saved
-- position; Blizzard's layout pass keeps it docked.
do
    local session = NewSession(true, "foreverGlass")
    session.Profile({})
    Check(session.NS.WindowControls.Attach(character, "blizzardWindows") and At(0, 0),
        "Forever Glass did not dock the Character window")
    UpdateUIPanelPositions(character)
    Check(At(0, 0) and hookInstalls == 1, "Blizzard's panel layout displaced the Forever dock")
end

print("Suite window controls profile hook: " .. checks .. " checks passed")

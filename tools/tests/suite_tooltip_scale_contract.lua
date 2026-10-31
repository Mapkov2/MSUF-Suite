-- GameTooltip's scale has one owner (MSUF_Suite/Core/TooltipScale.lua): the
-- Quality of Life tooltip scale and the Minimap hover scale each set only their
-- percent, and the scale written is Blizzard's own times both. Run with the
-- real owner, TooltipVisibility.lua and Minimap/Tooltips.lua, in every order
-- the two can meet: which hooks the tooltip first, and which scale lands first.
local root = assert(arg[1], "repository root required")
local Support = dofile(root .. "/tools/tests/suite_test_support.lua")
local Float32 = dofile(root .. "/tools/tests/suite_minimap_harness.lua").Float32
local checks = 0
local function Check(value, message) assert(value, message); checks = checks + 1 end
local function Near(a, b) return math.abs(a - b) < 1e-5 end

-- The client's ApproximatelyEqual (Blizzard_SharedXMLBase/MathUtil.lua).
ApproximatelyEqual = function(a, b, epsilon) return math.abs(a - b) < (epsilon or .000001) end
hooksecurefunc = function(owner)
    assert(owner ~= GameTooltip, "shared tooltip method hook is forbidden")
end

local NATIVE, QOL, MINIMAP = .8, 120, 150
local MINIMAP_ONLY, QOL_ONLY = NATIVE * MINIMAP / 100, NATIVE * QOL / 100
local BOTH = NATIVE * QOL / 100 * MINIMAP / 100
local HOOKABLE = { OnShow = true, OnHide = true, OnTooltipCleared = true }
local worlds = {}

-- GameTooltip as addon code meets it: the client reads a scale back as a
-- 32-bit float, and writes are counted.
local function NewTooltip(world)
    local tooltip = { shown = false, scale = NATIVE, alpha = 1, scripts = {} }
    function tooltip:IsShown() return self.shown end
    function tooltip:GetOwner() return self.owner end
    function tooltip:SetOwner(owner) self.owner = owner end
    function tooltip:GetAlpha() return self.alpha end
    function tooltip:SetAlpha(value) self.alpha = value end
    function tooltip:GetScale() return Float32(self.scale) end
    function tooltip:SetScale(value)
        self.scale = value
        world.writes = world.writes + 1
    end
    function tooltip:HookScript(name, callback)
        world.hooked[#world.hooked + 1] = name
        local old = self.scripts[name]
        self.scripts[name] = function(...) if old then old(...) end; callback(...) end
    end
    function tooltip:Show()
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function tooltip:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    return tooltip
end

-- A fresh Suite: the real owner and both real callers on a stand-in core.
local function NewWorld(label)
    local world = { label = label, writes = 0, hooked = {}, button = {}, other = {} }
    local tooltip = NewTooltip(world)
    world.tooltip, world.methods = tooltip, {}
    for key, value in pairs(tooltip) do
        if type(value) == "function" then world.methods[key] = value end
    end
    GameTooltip = tooltip
    local ns = {
        Safety = { IsForbidden = function(frame) return frame.forbidden == true end },
        Finite = function(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end,
        InCombat = function() return false end,
    }
    local suite = { Public = function() return true end, Finite = ns.Finite,
        Install = function(_, module) world.qol = module end,
        TooltipLines = { Add = function() end } }
    assert(loadfile(root .. "/MSUF_Suite/Core/TooltipScale.lua"))("MSUF_Suite", ns)
    world.MM = { M = { active = true, config = { tooltipScale = 100 } } }
    assert(loadfile(root .. "/MSUF_Suite_Minimap/Tooltips.lua"))("MSUF_Suite_Minimap",
        { NS = ns, Suite = suite, Minimap = world.MM })
    assert(loadfile(root .. "/MSUF_Suite_QualityOfLife/TooltipVisibility.lua"))("MSUF_Suite_QualityOfLife",
        { NS = ns, Suite = suite })
    world.qol.context = { Event = function() end, RemoveEvent = function() end }
    world.qol.config = { inCombat = false, inInstances = false, revealModifier = 1, scale = 100 }
    worlds[#worlds + 1] = world
    return world
end

local function Hover(world, button)
    world.tooltip:SetOwner(button or world.button)
    world.MM.ScaleTooltip(button or world.button)
end
local function Leave(world, button) world.MM.HideInfoTooltip(button or world.button) end
local function SetMinimap(world, percent) world.MM.M.config.tooltipScale = percent end
local function EnableQoL(world, percent)
    world.qol.active = true
    world.qol.config.scale = percent
    world.qol:Enable()
end
local function Expect(world, scale, message)
    local read = world.tooltip:GetScale()
    Check(Near(read, scale), world.label .. ": " .. message .. " (scale " .. read .. ", expected " .. scale .. ")")
end

-- The Minimap hooks OnHide with its first scaled hover; ends it again so the
-- hook order is the only thing the call leaves behind.
local function HookMinimap(world)
    SetMinimap(world, MINIMAP)
    Hover(world)
    Leave(world)
    Expect(world, NATIVE, "a hover left a scale behind")
end

-- Both orders of hooking the tooltip, both orders of the scales landing.
for _, qolHooksFirst in ipairs({ true, false }) do
    for _, minimapScalesFirst in ipairs({ true, false }) do
        local world = NewWorld((qolHooksFirst and "QoL hooks first" or "Minimap hooks first")
            .. ", " .. (minimapScalesFirst and "Minimap scales first" or "QoL scales first"))
        local tooltip = world.tooltip
        if qolHooksFirst then EnableQoL(world, 100) HookMinimap(world) else HookMinimap(world) EnableQoL(world, 100) end
        world.qol.config.scale = QOL
        if minimapScalesFirst then
            Hover(world)
            Expect(world, MINIMAP_ONLY, "the hover scale was not set before the tooltip showed")
            tooltip:Show()
        else
            tooltip:Show()
            Expect(world, QOL_ONLY, "the tooltip was not scaled on show")
            Hover(world)
        end
        Expect(world, BOTH, "the two scales did not compose")
        Hover(world)
        Expect(world, BOTH, "a repeated hover compounded")
        Leave(world)
        Check(not tooltip.shown, world.label .. ": the hover left the tooltip shown")
        Expect(world, NATIVE, "leaving did not give Blizzard's scale back")
        tooltip:Show()
        Expect(world, QOL_ONLY, "the next show did not start from Blizzard's scale")
        tooltip:Hide()
        Expect(world, NATIVE, "hiding did not give Blizzard's scale back")
    end
end

-- A hover that ends while another owner keeps the tooltip shown takes only
-- its own scale back.
do
    local world = NewWorld("hover ends under a shown tooltip")
    EnableQoL(world, QOL)
    SetMinimap(world, MINIMAP)
    world.tooltip:Show()
    Hover(world)
    Expect(world, BOTH, "the two scales did not compose")
    world.tooltip:SetOwner(world.other)
    Leave(world)
    Check(world.tooltip.shown, world.label .. ": the other owner's tooltip was hidden")
    Expect(world, QOL_ONLY, "ending the hover kept its scale")
    world.tooltip:Hide()
    Expect(world, NATIVE, "hiding did not give Blizzard's scale back")
end

-- Another button taking the hover neither compounds nor ends the session.
do
    local world = NewWorld("two buttons")
    EnableQoL(world, QOL)
    SetMinimap(world, MINIMAP)
    Hover(world)
    world.tooltip:Show()
    Hover(world, world.other)
    Expect(world, BOTH, "the next button's hover compounded")
    Leave(world)
    Expect(world, BOTH, "the first button ended the second one's hover")
    Leave(world, world.other)
    Expect(world, NATIVE, "the second button's hover did not end")
end

-- The module changes or stops while a hover scales the tooltip.
do
    local world = NewWorld("module changes during a hover")
    EnableQoL(world, QOL)
    SetMinimap(world, MINIMAP)
    Hover(world)
    world.tooltip:Show()
    world.qol.config.scale = 50
    world.qol:Refresh()
    Expect(world, NATIVE * .5 * MINIMAP / 100, "a new percent did not reach the shown tooltip")
    world.qol.config.scale = 100
    world.qol:Refresh()
    Expect(world, MINIMAP_ONLY, "the default percent took the hover scale with it")
    world.qol.config.scale = QOL
    world.qol:Refresh()
    Expect(world, BOTH, "the percent was not applied again")
    world.qol.active = false
    world.qol:Disable()
    Expect(world, MINIMAP_ONLY, "disabling the module took the hover scale with it")
    world.tooltip:Hide()
    Expect(world, NATIVE, "the hover scale stayed after the tooltip hid")
    world.tooltip:Show()
    Expect(world, NATIVE, "a disabled module scaled the tooltip")
    world.tooltip:Hide()
end

-- A hover that began before the module's first capture: the module must not
-- take the hover's scale for Blizzard's.
do
    local world = NewWorld("hover before the module")
    SetMinimap(world, MINIMAP)
    HookMinimap(world)
    Hover(world)
    world.tooltip:Show()
    Expect(world, MINIMAP_ONLY, "the hover was not scaled")
    EnableQoL(world, QOL)
    Expect(world, BOTH, "the module did not compose with the running hover")
    Leave(world)
    Expect(world, NATIVE, "the hover scale became the module's base")
    world.tooltip:Show()
    Expect(world, QOL_ONLY, "the next show scaled from the hover's scale")
    world.tooltip:Hide()
    Expect(world, NATIVE, "hiding did not give Blizzard's scale back")
end

-- Each side alone puts back exactly Blizzard's scale.
do
    local world = NewWorld("one side only")
    EnableQoL(world, QOL)
    world.tooltip:Show()
    Expect(world, QOL_ONLY, "the module alone did not scale")
    world.tooltip:Hide()
    Expect(world, NATIVE, "the module alone left a scale")
    world.qol.config.scale = 100
    SetMinimap(world, MINIMAP)
    Hover(world)
    world.tooltip:Show()
    Expect(world, MINIMAP_ONLY, "the hover alone did not scale")
    Leave(world)
    Expect(world, NATIVE, "the hover alone left a scale")
end

-- A scale another addon wrote meanwhile stays, and the next scale starts
-- from it.
do
    local world = NewWorld("foreign scale")
    EnableQoL(world, QOL)
    SetMinimap(world, MINIMAP)
    Hover(world)
    world.tooltip:Show()
    world.tooltip.scale = .9
    Leave(world)
    Expect(world, .9, "a scale another addon wrote was overwritten")
    world.tooltip:Show()
    Expect(world, .9 * QOL / 100, "the next show did not start from the foreign scale")
    world.tooltip:Hide()
    Expect(world, .9, "hiding overwrote the foreign scale")
end

-- 100 from both sides never writes the tooltip's scale, and a forbidden
-- tooltip is never written.
do
    local world = NewWorld("defaults")
    EnableQoL(world, 100)
    SetMinimap(world, 100)
    Hover(world)
    world.tooltip:Show()
    Leave(world)
    SetMinimap(world, nil)
    Hover(world)
    world.tooltip:Show()
    world.tooltip:Hide()
    world.qol:Refresh()
    world.qol.active = false
    world.qol:Disable()
    Check(world.writes == 0, world.label .. ": " .. world.writes .. " scale writes at the default percent")
    local forbidden = NewWorld("forbidden tooltip")
    forbidden.tooltip.forbidden = true
    EnableQoL(forbidden, QOL)
    SetMinimap(forbidden, MINIMAP)
    forbidden.MM.ScaleTooltip(forbidden.button)
    forbidden.tooltip:Show()
    Check(forbidden.writes == 0, forbidden.label .. ": a forbidden tooltip was scaled")
end

-- The shared tooltip is hooked by script only, and only the owner writes it.
for _, world in ipairs(worlds) do
    for key, method in pairs(world.methods) do
        Check(world.tooltip[key] == method, world.label .. ": GameTooltip:" .. key .. " was replaced")
    end
    for _, name in ipairs(world.hooked) do
        Check(HOOKABLE[name], world.label .. ": GameTooltip was hooked on " .. name)
    end
end
local writers = {}
for _, addon in ipairs({ "MSUF_Suite", "MSUF_Suite_QualityOfLife", "MSUF_Suite_Minimap" }) do
    for _, file in ipairs(Support.TocFiles(root, addon)) do
        if file:match("%.lua$") then
            local handle = assert(io.open(root .. "/" .. addon .. "/" .. file, "rb"))
            local code = handle:read("*a"):gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
            handle:close()
            if code:find("[Tt]ooltip:SetScale%s*%(") then writers[#writers + 1] = addon .. "/" .. file end
        end
    end
end
Check(#writers == 1 and writers[1] == "MSUF_Suite/Core/TooltipScale.lua",
    "GameTooltip's scale is written outside its owner: " .. table.concat(writers, ", "))
print("Tooltip scale owner: " .. checks .. " checks passed")

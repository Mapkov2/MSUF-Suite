local root = assert(arg[1])
local function Load(path, namespace)
    return assert(loadfile(root .. "/" .. path))("MSUF_Suite", namespace)
end

local Methods = {}
Methods.__index = Methods
local function Frame(parent)
    local frame = setmetatable({ parent = parent, children = {}, scripts = {}, shown = true, writes = 0 }, Methods)
    if parent then parent.children[#parent.children + 1] = frame end
    return frame
end

function Methods:SetScript(event, callback) self.scripts[event] = callback end
function Methods:Fire(event, ...)
    if self.scripts[event] then return self.scripts[event](self, ...) end
end
function Methods:HookScript(event, callback)
    local prior = self.scripts[event]
    self.scripts[event] = function(frame, ...)
        if prior then prior(frame, ...) end
        callback(frame, ...)
    end
end
function Methods:SetShown(shown)
    if shown == self.shown then return end
    self.shown = shown
    self:Fire(shown and "OnShow" or "OnHide")
end
function Methods:Show() self:SetShown(true) end
function Methods:Hide() self:SetShown(false) end
function Methods:IsShown() return self.shown end
function Methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Methods:SetPoint(...)
    self.anchor = { ... }
    self.anchorWrites = (self.anchorWrites or 0) + 1
end
function Methods:ClearAllPoints() self.anchor = nil end
function Methods:SetAllPoints() end
function Methods:SetSize(width, height) self.width, self.height = width, height end
function Methods:SetHeight(height) self.height = height end
function Methods:SetWidth(width) self.width = width end
function Methods:GetWidth() return self.width or self.parent.width - 32 end
function Methods:GetHeight() return self.height end
function Methods:SetScale(scale) self.scale = scale end
function Methods:GetEffectiveScale() return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Methods:SetFrameLevel(level) self.level = level end
function Methods:GetFrameLevel() return self.level or 1 end
function Methods:SetEnabled(enabled) self.enabled = enabled end
function Methods:SetAlpha(alpha) self.alpha = alpha end
function Methods:RegisterForDrag() end
function Methods:RegisterForClicks() end
function Methods:EnableMouse() end
function Methods:EnableKeyboard() end
function Methods:SetMovable() end
function Methods:SetPropagateKeyboardInput() end
function Methods:SetTexture() end
function Methods:SetWordWrap() end
function Methods:SetJustifyH() end
function Methods:SetColorTexture(...) self.textureColor = { ... } end
function Methods:SetTextColor(...) self.textColor = { ... } end
function Methods:SetText(value) self.value, self.writes = value, self.writes + 1 end
function Methods:GetUnboundedStringWidth() return #self.value * 6 end
function Methods:GetStringHeight() return 14 end
function Methods:IsMouseOver() return self.hovered end
function Methods:CreateTexture() return Frame(self) end
function Methods:CreateFontString() return Frame(self) end

function CreateFrame(_, _, parent) return Frame(parent) end
function SetPortraitTexture(texture, unit) texture.unit = unit end
function wipe(values) for key in pairs(values) do values[key] = nil end end
local cursorX, cursorY = 0, 0
local held = false
function GetCursorPosition() return cursorX, cursorY end
function IsMouseButtonDown(button) return button == "LeftButton" and held end

local function Position(frame)
    local anchor = assert(frame.anchor)
    if #anchor == 5 then return anchor[4], anchor[5] end
    return anchor[2], anchor[3]
end

local function Near(left, right) return math.abs(left - right) < 0.000001 end

local function Press(button)
    held = true
    cursorX, cursorY = 200, 200
    button:Fire("OnMouseDown", "LeftButton")
end

local function Travel(button, dx, dy)
    local scale = button:GetEffectiveScale()
    cursorX, cursorY = 200 + dx * scale, 200 + dy * scale
    button:Fire("OnUpdate")
end

local function Release(button)
    held = false
    button:Fire("OnMouseUp", "LeftButton")
    button:Fire("OnClick", "LeftButton")
    assert(not button.scripts.OnUpdate, "gesture left its pointer script running")
end

local function TabTravel(from, to)
    local fromX, fromY = Position(from)
    local toX, toY = Position(to)
    Travel(from, toX + to:GetWidth() / 2 - fromX - from:GetWidth() / 2, toY - fromY)
end

local function Test(initialPreview)
    local config, combat, profile, refresh = {}, false, {}, nil
    local paths, toggles, writes, menuItems = {}, {}, {}, {}
    local skin = { IsEnabled = function() return false end }
    local Suite = {
        Text = function(value) return value end,
        Client = {},
        IsSecret = function() return false end,
        Number = tonumber,
        Skin = { Acquire = function() return skin end },
        ResolveFont = function(key) if key == "Alt" then return "Alt.ttf" end end,
        Suite = {
            FontRevision = 1, Config = function() return config end, GlobalFontPath = function() return "Global.ttf" end,
            SetFont = function(text, path, size) text.font, text.size = path, size end,
        },
    }
    Load("MSUF_Suite/Core/SuiteCatalog.lua", Suite)
    Load("MSUF_Suite/Core/CharacterTabs.lua", Suite)
    Load("MSUF_Suite/Core/CharacterBindings.lua", Suite)
    Load("MSUF_Suite/Core/Catalog/CharacterPanel.lua", Suite)
    Load("MSUF_Suite/Core/CharacterHeader.lua", Suite)
    Load("MSUF_Suite/Core/PreviewKit.lua", Suite)
    local rules = Suite.SuiteCatalog.characterPanel.rules
    for key, rule in pairs(rules) do config[key] = rule.default end
    local colorSection = {}
    local function Record(value) paths[#paths + 1] = value end
    Suite.HostBridge = { OpenExactMenuSetting = function(_, page, section, key)
        Record(page .. ":" .. section .. ":" .. key)
        return true
    end }
    local function Font(parent, _, value)
        local font = Frame(parent)
        font:SetText(value)
        return font
    end
    local ctx, bindingTab = {}, nil
    local P = {
        CharacterPanelBindings = { Build = function(owner) assert(owner == ctx) end,
            Open = function(owner, tab) assert(owner == ctx) bindingTab = tab end },
        Suite = Suite, S = Suite.Suite, Tr = Suite.Text, catalog = Suite.SuiteCatalog,
        Combat = function() return combat end,
        ProfileGuard = function() local owner = profile return function() return owner == profile end end,
        ContextMenu = function(anchor, generate)
            menuItems = {}
            generate(anchor, { CreateTitle = function(_, label) menuItems[label] = true end,
                CreateButton = function(_, label, click) menuItems[label] = click end })
        end,
        Set = function(_, key, value)
            config[key] = value
            writes[#writes + 1] = key
            refresh()
        end,
        SetMany = function(_, values)
            for key, value in pairs(values) do config[key] = value end
            writes[#writes + 1] = "position"
            refresh()
            return true
        end,
        ResetRules = function(_, list)
            for _, rule in ipairs(list) do config[rule.key] = rule.default end
            refresh()
        end,
        M = {
            AddTooltip = function() end,
            TrackRefresh = function(_, callback) refresh = callback end,
            SelectPage = Record,
            ColorsSetPainterCategory = Record,
            cache = { opt_colors = { sections = { colors_suite_characterPanel = colorSection } } },
        },
        W = { FocusCollapsibleSection = function(section) Record(section) end },
        T = {
            colors = { muted = {}, accent = { 1, .5, 0 } }, Font = Font,
            Button = function(parent, label, width, height)
                local button = Frame(parent)
                button:SetSize(width, height)
                button.label = Font(button, nil, label)
                toggles[label] = button
                return button
            end,
        },
        HM = { GetControlLabel = function(button) return button.label end, SkipHistoryCheckpoint = function() end,
            SetCommandAction = function() end },
        SetTranslatedText = function(text, value) text:SetText(value) end,
        SetButtonText = function(button, value) button.label:SetText(value) end,
        HUDMenu = { Prepare = function() end },
        RegisterPage = function() end,
        EnsureSectionContent = function() end,
        ModuleCard = function(_, _, _, _, actions) ctx.actions = actions end,
        SectionRules = function(_, section, accept)
            local matches = {}
            for _, rule in pairs(rules) do
                if rule.section == section and (not accept or accept(rule)) then matches[#matches + 1] = rule end
            end
            return matches
        end,
        RuleSection = function(_, _, _, _, id, _, controls)
            if id == "suite_hud_characterPanel_appearance" then ctx.appearanceControls = controls end
            if id == "suite_hud_characterPanel_reputation" then ctx.reputationControls = controls end
            return { id = id, controls = controls }
        end,
    }
    local customSelection, contentOpened, actionsOpened
    local restoring, restoreStock, offeredStock
    local customCancels = 0
    P.CharacterCustomTabs = { Create = function(_, changed)
        return {
            Add = function(_, _, hidden, restore)
                if restoring then
                    offeredStock, restoreStock = hidden, restore
                    return
                end
                local tabs = Suite.CharacterTabs.Copy(config)
                local id = Suite.CharacterTabs.Create(tabs, "empty", "My Raid Tab")
                P.Set("characterPanel", "customTabs", Suite.CharacterTabs.Encode(tabs))
                changed(id)
            end,
            Refresh = function(_, _, top, id, visible)
                customSelection = visible and id or nil
                return customSelection and top + 32 or top
            end,
            Cancel = function() customCancels = customCancels + 1 end,
            AttachPreview = function(_, _, id) customSelection = id end,
            DetachPreview = function() customSelection = nil end,
            OpenContent = function() contentOpened = customSelection end,
            OpenTabActions = function() actionsOpened = customSelection end,
        }
    end }
    local directOrder, directXY, directField
    P.CharacterPreviewHandles = { Create = function()
        return {
            Refresh = function(_, order, xy) directOrder, directXY = order, xy end,
            Release = function() end,
            Cancel = function() end,
            Selected = function() end,
            SelectField = function(_, id) directField = id end,
            SelectTab = function() end,
            Nudge = function() end,
        }
    end }
    P.PreviewCanvas = { Runtime = function(_, key) return P.S[key] ~= nil end }
    Load("MSUF_Suite_Options/Menu/PreviewInteraction.lua", P)
    Load("MSUF_Suite_Options/Pages/CharacterPanelEditor.lua", P)
    Load("MSUF_Suite_Options/Pages/CharacterPanel.lua", P)
    Load("MSUF_Suite_Options/Pages/HUD.lua", P)
    P.BuildHUDCharacterPanel(ctx, {})
    assert(rules.showFullStats and rules.showFullStats.default == true, "full Overview stats must default on")
    local appearance = {}
    for _, rule in ipairs(ctx.appearanceControls) do appearance[rule.key] = true end
    assert(rules.showAttributesTab and rules.showAttributesTab.default == false, "Attributes must be opt-in")
    assert(appearance.mode and appearance.showFullStats and appearance.showAttributesTab and not appearance.tabOrder,
        "the existing Appearance section did not expose both stats toggles")
    local reputation = {}
    for _, rule in ipairs(assert(ctx.reputationControls)) do reputation[rule.key] = rule end
    assert(reputation.showReputationBars.default == false and reputation.reputationValue.default == 1
        and reputation.reputationGoal.default == 1 and reputation.reputationGoal.max == 8
        and reputation.reputationBarHeight.min == 2 and reputation.reputationBarHeight.max == 8
        and reputation.reputationBarColor.color and reputation.reputationBarColor.default == "",
        "the dedicated Reputation section omitted the bars, target, text or style settings")
    local pane = Frame()
    pane.width = 720
    local height, host
    local paintedMode, paintedTab, hidden, chooseTab
    local function InstallPreview()
        P.S.CharacterPanelPreview = { New = function(parent, samples, select)
            assert(parent == host.children[1] and samples.own and samples.inspect)
            chooseTab = select
            local header = Suite.CharacterHeader.Create(parent)
            return {
                view = { header = header },
                Paint = function(_, profile, mode, _, tab, overrides)
                    paintedMode, paintedTab, hidden = mode, tab, false
                    header:Render(profile, samples[mode], nil, Suite.CharacterHeader.PreviewWidth, 0, overrides)
                    return 390
                end,
                Hide = function() hidden = true end,
            }
        end }
    end
    if initialPreview then InstallPreview() end
    host = P.CharacterPanelEditor.Build(ctx, pane, function(value) height = value end)
    host:Show()
    if initialPreview then
        assert(paintedMode == "own" and paintedTab == "overview" and height >= 390, "cold full preview did not open")
        assert(toggles["+"]:IsShown() and not toggles["Add content"]:IsShown() and directOrder[1].id == "overview",
            "cold full preview did not offer creation from the main canvas")
        toggles["+"]:Fire("OnClick")
        assert(paintedTab == customSelection and toggles["Add content"]:IsShown(),
            "creating from the full preview did not activate its tab and actions")
        host:Hide()
        return
    end
    local buttons = host.children[2].children[1].children
    local named, metadata = buttons[2], buttons[3]
    assert(named.text.font == "Global.ttf" and named.text.value == "Mapko", "preview did not use the shared header")
    config.headerNameFont, config.headerNameSize, config.headerNameColor = "Alt", 20, "804020"
    refresh()
    assert(named.text.font == "Alt.ttf" and named.text.size == 20 and named.text.textColor[1] == 128 / 255)
    Press(named)
    Release(named)
    assert(paths[#paths] == "suite_hud:suite_hud_characterPanel_name:msufsuite.characterPanel.headerNameSize",
        "click did not focus the exact font-size setting")
    assert(#ctx.characterHeaderSections.name.controls == 6 and #ctx.characterHeaderSections.portrait.controls == 4)

    for _, tab in ipairs(Suite.CharacterHeader.Tabs) do assert(toggles[tab.label], tab.id) end
    assert(not toggles.Stats and toggles.Statistics, "Stats preview tab was not removed independently of Statistics")
    local reputation, equipment, overview = toggles.Reputation, toggles.Equipment, toggles.Overview
    config.headerZoneVisible = true
    refresh()
    assert(buttons[7]:IsShown() and not toggles.Compare:IsShown())
    toggles.Inspect:Fire("OnClick")
    assert(named.text.value == "Alyra" and named.text.font == "Alt.ttf" and not buttons[7]:IsShown())
    assert(toggles.Compare:IsShown() and overview:IsShown() and equipment:IsShown() and not reputation:IsShown(),
        "Inspect preview did not show its own tab set")
    Press(overview)
    TabTravel(overview, toggles.Compare)
    Release(overview)
    assert(config.inspectTabOrder == "gear,compare,overview" and config.tabOrder == "",
        "Inspect tab drag did not maintain an independent order")
    toggles["Own character"]:Fire("OnClick")
    assert(named.text.value == "Mapko" and buttons[7]:IsShown() and reputation:IsShown() and not toggles.Compare:IsShown())
    local startX = Position(reputation)
    Press(reputation)
    TabTravel(reputation, equipment)
    assert(Position(reputation) ~= startX and config.tabOrder == "", "tab did not visibly follow pointer before commit")
    Release(reputation)
    assert(config.tabOrder:match("^overview,reputation,gear"), "tab drop did not move the selected tab")
    reputation:Fire("OnClick")
    toggles[">"]:Fire("OnClick")
    assert(config.tabOrder:match("^overview,gear,reputation"), "arrow did not reorder the selected tab")
    local before = #writes
    Press(reputation)
    TabTravel(reputation, equipment)
    profile = {}
    Release(reputation)
    assert(#writes == before, "stale drag wrote into another profile")

    before = #writes
    assert(not config.headerGuildVisible and not buttons[6]:IsShown())
    toggles.Guild:Fire("OnClick", "LeftButton")
    assert(buttons[6]:IsShown() and not config.headerGuildVisible and #writes == before,
        "preview layer did not expose the sample independently of live visibility")
    toggles.Tabs:Fire("OnClick", "LeftButton")
    assert(not reputation:IsShown() and #writes == before, "tab layer leaked into profile")
    toggles.Tabs:Fire("OnClick", "LeftButton")
    assert(reputation:IsShown())
    toggles.Guild:Fire("OnClick", "RightButton")
    assert(paths[#paths]:find("headerGuildSize", 1, true), "layer shortcut did not focus exact settings")

    for index, field in ipairs(Suite.CharacterHeader.Fields) do
        local button = buttons[index]
        local x, y = Position(button)
        local dx, dy = x > 100 and -20 or 20, y < -3 and 3 or -3
        local beforePaths, beforeWrites = #paths, #writes
        Press(button)
        Travel(button, dx, dy)
        local movedX, movedY = Position(button)
        assert(Near(movedX, x + dx) and Near(movedY, y + dy) and #writes == beforeWrites,
            field.id .. " did not follow pointer")
        local anchorWrites = button.anchorWrites
        button:Fire("OnUpdate")
        assert(button.anchorWrites == anchorWrites, "stationary drag rewrote anchors")
        Release(button)
        assert(config[field.prefix .. "X"] == dx and config[field.prefix .. "Y"] == dy and #writes == beforeWrites + 1,
            field.id .. " did not commit once")
        assert(#paths == beforePaths, "drag also navigated to settings")
    end
    Press(metadata)
    Release(metadata)
    assert(paths[#paths]:find("headerLevelSize", 1, true), "subsequent click could not navigate")

    config.headerNameX = Suite.CharacterHeader.PreviewWidth
    refresh()
    local clamped = named.x - named.baseX
    local x = Position(named)
    Press(named)
    Travel(named, -20, 0)
    assert(Near(Position(named), x - 20), "clamped saved position jumped when dragging inward")
    Release(named)
    assert(config.headerNameX == clamped - 20, "clamped drag committed from the inaccessible saved coordinate")

    before = #writes
    Press(named)
    Travel(named, -25, 0)
    held = false
    named:Fire("OnUpdate")
    assert(not named.scripts.OnUpdate and config.headerNameX == clamped - 45 and #writes == before + 1,
        "mouse-up outside the handle did not finish the drag")
    Release(named)
    assert(#writes == before + 1, "late native mouse-up committed twice")

    Press(named)
    held = false
    named:Fire("OnUpdate")
    assert(not named.scripts.OnUpdate and #writes == before + 1, "lost press below threshold stranded its pointer script")

    Press(named)
    Travel(named, -15, 0)
    combat = true
    before = #writes
    named:Fire("OnUpdate")
    assert(not named.scripts.OnUpdate, "combat did not cancel active pointer capture")
    Release(named)
    assert(#writes == before, "combat accepted a position change")
    combat = false

    local wide = height
    pane.width = 270
    host:Fire("OnSizeChanged", 238)
    assert(height > wide and toggles.Statistics.anchor[5] < reputation.anchor[5], "narrow preview clipped its tab rail")
    ctx.actions[1][2]()
    assert(paths[#paths - 2] == "opt_colors" and paths[#paths - 1] == "suite" and paths[#paths] == colorSection)
    ctx.actions[2][2]()
    assert(config.tabOrder == "" and config.inspectTabOrder == "" and config.headerOrder == "",
        "reset did not restore default orders")
    toggles["+"]:Fire("OnClick")
    local custom = assert(toggles["My Raid Tab"], "custom tab was not created as a preview drag handle")
    local id = config.customTabs and Suite.CharacterTabs.Get(config)[1].id
    assert(customSelection == id and custom:IsShown(), "new custom tab was not selected immediately")
    Press(custom)
    TabTravel(custom, equipment)
    Release(custom)
    assert(config.tabOrder:match("^overview," .. id .. ",gear"), "custom tab did not reorder with native tabs")
    local customTabs = Suite.CharacterTabs.Copy(config)
    customTabs[1].name = "Renamed Raid Tab"
    P.Set("characterPanel", "customTabs", Suite.CharacterTabs.Encode(customTabs))
    assert(custom.label.value == "Renamed Raid Tab" and customSelection == id, "renaming lost selection or tab order")
    toggles.Inspect:Fire("OnClick")
    assert(not toggles["+"]:IsShown() and not custom:IsShown() and not customSelection, "own tabs leaked into Inspect")
    toggles["Own character"]:Fire("OnClick")
    assert(custom:IsShown() and customSelection == id)
    Press(equipment)
    Release(equipment)
    assert(not customSelection, "clicking a native tab did not leave custom content")
    Press(custom)
    Release(custom)
    assert(customSelection == id, "clicking a custom tab did not open its editor")
    local xy = assert(toggles["Position X/Y"], "position mode was missing")
    assert(xy:IsShown(), "position mode was hidden in the own-character preview")
    xy:Fire("OnClick")
    local scale = math.min(1, host:GetWidth() / Suite.CharacterHeader.PreviewWidth)
    local px, py = Position(custom)
    local oldOrder, oldLayout = config.tabOrder, config.customTabs
    Press(custom)
    Travel(custom, 20 * scale, 6 * scale)
    local sx, sy = Position(custom)
    assert(Near(sx, px + 20 * scale) and Near(sy, py + 6 * scale) and config.customTabs == oldLayout,
        "tab did not follow both scaled axes before release")
    Release(custom)
    local xOffset, yOffset = Suite.CharacterTabs.Position(Suite.CharacterTabs.Find(config, id))
    assert(xOffset == 20 and yOffset == 6 and config.tabOrder == oldOrder,
        "position drag did not persist logical X/Y or changed tab order")
    xy:Fire("OnClick")
    local afterX, afterY = Position(custom)
    assert(Near(afterX, sx) and Near(afterY, sy), "switching to reorder lost the saved position")
    customTabs = Suite.CharacterTabs.Copy(config)
    table.remove(customTabs, 1)
    P.Set("characterPanel", "customTabs", Suite.CharacterTabs.Encode(customTabs))
    assert(not custom:IsShown() and not customSelection, "removed tab kept a preview handle visible")
    toggles["+"]:Fire("OnClick")
    assert(custom:IsShown() and custom.spec.id == customSelection and customSelection ~= id,
        "adding after removal did not recycle its tab button")
    Press(named)
    Travel(named, -10, 0)
    host:Hide()
    assert(not named.scripts.OnUpdate, "hidden preview kept a pointer script")
    config.headerNameSize = 18
    refresh()
    assert(named.text.size == 20, "hidden preview repainted")

    InstallPreview()
    host:Show()
    assert(paintedMode == "own" and paintedTab == custom.spec.id and height >= 390,
        "Character Panel did not open its complete preview by default")
    assert(not named:IsVisible() and not toggles.Edit and toggles["+"]:IsShown(),
        "the full preview did not expose editing on the same canvas")
    toggles["Add content"]:Fire("OnClick")
    toggles["Tab actions"]:Fire("OnClick")
    assert(contentOpened == customSelection and actionsOpened == customSelection)
    toggles["Position X/Y"]:Fire("OnClick")
    assert(directXY and paintedTab == customSelection, "X/Y toggled away from the full preview")
    local beforeResize = customCancels
    pane.width = 500
    host:Fire("OnSizeChanged", 468)
    assert(customCancels == beforeResize + 1 and paintedTab == customSelection,
        "resize reused a direct-content drag or lost its selected tab")
    toggles.Name:Fire("OnClick", "RightButton")
    assert(directField == "name", "layers did not select the rendered header grip")
    chooseTab("gear")
    assert(paintedTab == "gear" and not toggles["Add content"]:IsShown())
    toggles.Inspect:Fire("OnClick")
    chooseTab("compare")
    assert(paintedMode == "inspect" and paintedTab == "compare" and not directXY)
    assert(not toggles["+"]:IsShown() and not toggles["Add content"]:IsShown(),
        "custom editing controls leaked into Inspect")
    toggles["Own character"]:Fire("OnClick")
    assert(paintedMode == "own" and paintedTab == "gear" and not hidden,
        "mode switch lost the selected Own tab")
    local framesBefore = #host.children
    toggles["Tab actions"]:Fire("OnClick")
    local staleHide = assert(menuItems["Hide tab"], "built-in tab had no hide action")
    profile = {}
    staleHide()
    assert(Suite.CharacterHeader.TabVisible(config, "tab", "gear"), "old profile menu hid a tab")
    toggles["Tab actions"]:Fire("OnClick")
    assert(menuItems["Key bindings"])()
    assert(bindingTab == "gear", "tab actions did not open bindings for the selected tab")
    assert(menuItems["Use as character start tab"])()
    assert(config.homeTab == "gear", "the selected built-in tab could not become C home")
    toggles["Tab actions"]:Fire("OnClick")
    assert(menuItems["Character start tab"], "current C home was not labeled")
    assert(menuItems["Hide tab"])()
    assert(config.homeTab == "overview" and paintedTab == "overview"
        and not Suite.CharacterHeader.TabVisible(config, "tab", "gear"),
        "hiding the selected C home did not fall back to a visible tab")

    restoring = true
    toggles["+"]:Fire("OnClick")
    assert(offeredStock[1].id == "gear", "the Add menu did not offer the hidden built-in tab")
    local staleRestore = restoreStock
    toggles.Inspect:Fire("OnClick")
    staleRestore("gear")
    assert(not Suite.CharacterHeader.TabVisible(config, "tab", "gear"), "an old menu restored into a different window")
    toggles["Tab actions"]:Fire("OnClick")
    assert(not menuItems["Use as character start tab"] and not menuItems["Key bindings"] and menuItems["Hide tab"],
        "Inspect offered player tab binding actions")
    assert(menuItems["Hide tab"])()
    assert(paintedTab == "overview" and toggles["+"]:IsShown(), "Inspect could not hide and restore a built-in tab")
    toggles["+"]:Fire("OnClick")
    assert(offeredStock[1].id == "compare")
    restoreStock("compare")
    assert(paintedTab == "compare" and not toggles["+"]:IsShown(), "restoring Inspect Compare changed the wrong window")

    toggles["Own character"]:Fire("OnClick")
    toggles["+"]:Fire("OnClick")
    restoreStock("gear")
    assert(paintedTab == "gear" and config.homeTab == "overview"
        and Suite.CharacterHeader.TabVisible(config, "tab", "gear")
        and #host.children == framesBefore, "restoring a built-in recreated controls or changed C home")
    host:Hide()
    assert(hidden, "closing the editor left the runtime preview active")
end

Test()
Test(true)
print("Character header editor: real drag scripts, both tab orders, preview layers, exact focus, cancellation, and Colors")

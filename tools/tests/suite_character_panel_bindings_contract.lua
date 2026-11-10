local root = assert(arg[1], "repository root")
local candidate = arg[2]
local function Load(file, target)
    local path = candidate and (candidate .. "/" .. file) or (root .. "/" .. file)
    local fn = loadfile(path)
    if not fn then fn = assert(loadfile(root .. "/" .. file)) end
    fn("MSUF_Suite", target)
end

local function Run(forever)
    local combat, generation, set = false, 1, 1
    local pendingModifiers = ""
    local readContext, writes, saves = nil, 0, 0
    local blocked
    local config = { homeTab = "overview" }
    local tabs = {
        { id = "overview", label = "Overview" }, { id = "gear", label = "Equipment" },
        { id = "reputation", label = "Reputation" }, { id = "custom23", label = "Raid Prep", name = "Raid Prep", custom = true },
    }
    local function Find(_, id)
        for _, entry in ipairs(tabs) do if entry.id == id then return entry end end
    end
    local Header = {
        HomeTab = function(data) return data.homeTab end,
        Order = function() return tabs end,
        TabVisible = function(data, _, id) return Find(data, id) ~= nil end,
    }
    local contexts = {}
    local actions = { [11] = {}, [12] = {}, [13] = {}, [14] = {}, [20] = {} }
    contexts.TOGGLECHARACTER0, contexts.TOGGLECHARACTER2, contexts.TOGGLECURRENCY, contexts.TOGGLECHARACTER4 = 11, 12, 13, 14
    local function Keys(command, context)
        local bucket = actions[context]
        bucket[command] = bucket[command] or {}
        return bucket[command]
    end
    Keys("TOGGLECHARACTER0", 11)[1] = "Q"
    Keys("TOGGLECHARACTER0", 11)[2] = "F3"
    Keys("MSUFSUITE_CHARACTER_CUSTOM1", 20)[1] = "F9"
    Keys("CONFLICT", 11)[1] = "F2"
    _G.C_KeyBindings = { GetBindingContextForAction = function(command) return contexts[command] or 20 end }
    _G.GetBindingKey = function(command, _, context)
        assert((contexts[command] or 20) == context, command)
        readContext = context
        return unpack(Keys(command, context))
    end
    _G.GetBindingText = function(key) return key end
    _G.GetBindingName = function(command) return "action " .. command end
    _G.GetBindingAction = function(key, _, context)
        for command, values in pairs(actions[context]) do
            for _, saved in ipairs(values) do if saved == key then return command end end
        end
        return ""
    end
    local eventOwner
    _G.SetBinding = function(key, command, context)
        assert(not combat, "binding mutation in combat")
        writes = writes + 1
        if key == blocked and command then return false end
        local old = GetBindingAction(key, nil, context)
        if old ~= "" then
            local list = Keys(old, context)
            for i = #list, 1, -1 do if list[i] == key then table.remove(list, i) end end
        end
        if command then
            local list = Keys(command, context)
            list[#list + 1] = key
        end
        if eventOwner then eventOwner:Fire("OnEvent", "UPDATE_BINDINGS") end
        return 1
    end
    _G.Enum = { BindingSet = { Default = 0, Account = 1, Character = 2 } }
    _G.GetCurrentBindingSet = function() return set end
    _G.SaveBindings = function(scope) assert(scope == set) saves = saves + 1 end
    _G.GetConvertedKeyOrButton = function(key) return key end
    _G.IsKeyPressIgnoredForBinding = function(key) return key == "LCTRL" end
    _G.CreateKeyChordStringUsingMetaKeyState = function(key) return pendingModifiers .. key end
    local openCategory, openSearch
    _G.Settings = { KEYBINDINGS_CATEGORY_ID = 42, OpenToCategory = function(category, search)
        openCategory, openSearch = category, search
    end }

    local Methods = {}
    Methods.__index = Methods
    function Methods:IsVisible() return self.visible and (not self.parent or self.parent:IsVisible()) end
    function Methods:IsShown() return self.visible end
    function Methods:SetShown(value) self.visible = value end
    function Methods:SetPoint() end
    function Methods:GetStringHeight() return 12 end
    function Methods:SetEnabled(value) self.enabled = value end
    function Methods:SetScript(name, fn) self.scripts[name] = fn end
    function Methods:HookScript(name, fn) self.scripts[name] = fn end
    function Methods:EnableKeyboard(value) self.keyboard = value end
    function Methods:EnableGamePadButton(value) self.gamepad = value end
    function Methods:EnableMouseWheel(value) self.mouseWheel = value end
    function Methods:SetPropagateKeyboardInput(value) self.propagate = value end
    function Methods:RegisterForClicks(...) self.clicks = { ... } end
    function Methods:RegisterEvent(name) self.events[name] = true end
    function Methods:UnregisterEvent(name) self.events[name] = nil end
    function Methods:Fire(event, ...)
        if event == "OnKeyDown" and not self.keyboard then return end
        if event == "OnGamePadButtonDown" and not self.gamepad then return end
        if event == "OnMouseWheel" and not self.mouseWheel then return end
        if self.scripts[event] then self.scripts[event](self, ...) end
    end
    local function Frame(parent, visible)
        return setmetatable({ parent = parent, visible = visible ~= false, scripts = {}, events = {} }, Methods)
    end
    local body, ctx = Frame(nil, false), {}
    local controls, menu, notices = {}, {}, {}
    local pending, refresh
    local function Identity(value) return value end
    local Suite = {
        Public = function(value) return value ~= "secret" end,
        Text = Identity, Client = { isForever = forever, isMainline = not forever },
        CharacterHeader = Header, CharacterTabs = { TabLimit = 8, Find = Find },
        Dispatch = function(fn, ...) return fn(...) end,
        Finish = function(fn, ...) return true, fn(...) end,
        Print = function(message) notices[#notices + 1] = message end,
    }
    Load("MSUF_Suite/Core/CharacterBindings.lua", Suite)
    local P = {
        Suite = Suite, S = { Config = function() return config end, CharacterHeader = Header },
        W = { FocusCollapsibleSection = function(section)
            assert(section == body)
            body.visible = true
            body:Fire("OnShow")
        end },
        HM = { GetSectionWidth = function() return 480 end },
        M = { AddTooltip = function() end, TrackRefresh = function(_, fn) refresh = fn end },
        T = { Button = function(parent) return Frame(parent) end },
        Tr = Identity, Combat = function() return combat end,
        SetButtonText = function(button, value) button.text = value end,
        ProfileGuard = function()
            local token = generation
            return function() return token == generation and not combat end
        end,
        Description = function(parent) return Frame(parent) end,
        Text = function(parent) return Frame(parent) end,
        LazySection = function(_, _, title, open, data)
            assert(title == "Key bindings" and not open)
            pending = data
            return body
        end,
        EnsureSectionContent = function(section)
            assert(section == body)
            if pending then
                local data = pending
                pending = nil
                data.finish(body, data.content(body))
            end
        end,
        FinishBody = function() end,
        Meta = function(_, _, key) return key end,
        HUDMenu = { Prepare = function(_, entries)
            for _, entry in ipairs(entries) do controls[entry.meta] = entry.widget end
        end },
        ContextMenu = function(button, init)
            menu = {}
            init(button, { CreateButton = function(_, text, fn) menu[text] = fn end })
        end,
        SetMany = function(id, patch)
            assert(id == "characterPanel")
            for key, value in pairs(patch) do config[key] = value end
            return true
        end,
    }
    Load("MSUF_Suite_Options/Pages/CharacterPanelBindings.lua", P)
    local editor = assert(P.CharacterPanelBindings)
    editor.Build(ctx, {})
    assert(not next(controls), "accordion created input controls before opening")
    assert(editor.Open(ctx, "custom23"))
    eventOwner = controls.openBlizzardBindings
    assert(eventOwner.events.UPDATE_BINDINGS and controls.directBinding.text == "Raid Prep")
    assert(not controls.directKey1.enabled, "custom command was available before explicit assignment")
    controls.shortcutSlot:Fire("OnClick", "LeftButton")
    assert(menu["Custom tab shortcut 1 (F9)"], "existing key was hidden on available slot")
    assert(menu["Custom tab shortcut 2 (No shortcut assigned)"])
    local crowdedSlot = Keys("MSUFSUITE_CHARACTER_CUSTOM3", 20)
    crowdedSlot[1], crowdedSlot[2] = "F11", "F12"
    controls.shortcutSlot:Fire("OnClick", "LeftButton")
    local staleCrowded = menu["Custom tab shortcut 3 (F11, F12)"]
    crowdedSlot[3] = "F10"
    staleCrowded()
    assert(not config.characterBindingSlot3)
    controls.shortcutSlot:Fire("OnClick", "LeftButton")
    assert(not menu["Custom tab shortcut 3 (F11, F12)"])
    -- A Blizzard settings change during the slot menu invalidates its preview.
    local staleSlot = menu["Custom tab shortcut 2 (No shortcut assigned)"]
    Keys("MSUFSUITE_CHARACTER_CUSTOM2", 20)[1] = "F11"
    staleSlot()
    assert(not config.characterBindingSlot2)
    controls.shortcutSlot:Fire("OnClick", "LeftButton")
    menu["Custom tab shortcut 1 (F9)"]()
    assert(config.characterBindingSlot1 == "custom23" and controls.directKey1.text == "F9")
    controls.openBlizzardBindings:Fire("OnClick", "LeftButton")
    assert(openCategory == 42 and openSearch == "Character Panel")
    assert(_G.BINDING_NAME_MSUFSUITE_CHARACTER_CUSTOM1 == "Custom tab shortcut 1 (Raid Prep)")
    controls.shortcutSlot:Fire("OnClick", "LeftButton")
    local staleRemoval = menu["Remove shortcut slot"]
    config.characterBindingSlot1 = "anotherTab"
    staleRemoval()
    assert(config.characterBindingSlot1 == "anotherTab", "stale slot menu removed another tab's binding")
    config.characterBindingSlot1 = "custom23"
    controls.shortcutSlot:Fire("OnClick", "LeftButton")
    menu["Remove shortcut slot"]()
    assert(config.characterBindingSlot1 == "" and not controls.directKey1.enabled
        and Keys("MSUFSUITE_CHARACTER_CUSTOM1", 20)[1] == "F9", "slot unassignment changed game binding")

    controls.nativeBinding:Fire("OnClick", "LeftButton")
    assert(menu.PvP and menu.Professions and (menu.Statistics ~= nil) == not forever)
    menu.Professions()
    assert(controls.bindingDestination.text == "Blizzard window")
    controls.bindingDestination:Fire("OnClick", "LeftButton")
    menu["Raid Prep"]()
    assert(config.professionsBindingTab == "custom23" and controls.bindingDestination.text == "Raid Prep")
    controls.bindingDestination:Fire("OnClick", "LeftButton")
    menu["Blizzard window"]()
    assert(config.professionsBindingTab == "" and controls.bindingDestination.text == "Blizzard window")
    controls.nativeBinding:Fire("OnClick", "LeftButton")
    menu.Character()
    controls.bindingDestination:Fire("OnClick", "LeftButton")
    menu["Raid Prep"]()
    assert(config.homeTab == "custom23" and controls.bindingDestination.text == "Raid Prep")
    local key = controls.nativeKey1
    assert(key.text == "Q" and controls.nativeKey2.text == "F3" and readContext == 11)
    key:Fire("OnClick", "LeftButton")
    assert(key.keyboard and key.gamepad and key.mouseWheel and key.propagate == false and key.clicks[1] == "AnyUp")
    key:Fire("OnKeyDown", "F2")
    assert(not key.keyboard and not key.gamepad and not key.mouseWheel and key.clicks[1] == "LeftButtonUp")
    assert(#notices == 1 and notices[1] == "F2 is already bound to action CONFLICT." and writes == 0)
    key:Fire("OnClick", "LeftButton")
    key:Fire("OnKeyDown", "LCTRL")
    assert(key.scripts.OnKeyDown and saves == 0)
    pendingModifiers = "CTRL-"
    key:Fire("OnKeyDown", "K")
    assert(saves == 1 and key.text == "CTRL-K" and controls.nativeKey2.text == "F3")
    pendingModifiers, blocked = "", "F7"
    key:Fire("OnClick", "LeftButton")
    key:Fire("OnKeyDown", "F7")
    assert(saves == 1 and key.text == "CTRL-K" and controls.nativeKey2.text == "F3")
    assert(notices[2] == "The key binding could not be saved.", "partial write failed without restoring keys")
    blocked, set = nil, 2
    key:Fire("OnClick", "RightButton")
    assert(saves == 2 and key.text == "F3" and controls.nativeKey2.text == "Secondary key")

    key:Fire("OnClick", "LeftButton")
    key:Fire("OnKeyDown", "ESCAPE")
    assert(not key.scripts.OnKeyDown and saves == 2)
    key:Fire("OnClick", "LeftButton")
    generation = generation + 1
    refresh()
    assert(not key.scripts.OnKeyDown)
    key:Fire("OnClick", "LeftButton")
    combat = true
    eventOwner:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
    assert(not key.scripts.OnKeyDown and not key.enabled)
    key:Fire("OnClick", "RightButton")
    assert(saves == 2)
    combat = false
    eventOwner:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
    assert(key.enabled)
    controls.bindingDestination:Fire("OnClick", "LeftButton")
    local staleDestination = menu.Default
    eventOwner:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
    staleDestination()
    assert(config.homeTab == "custom23" and not key.enabled, "combat event race let a menu mutate the profile")
    eventOwner:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
    key:Fire("OnClick", "LeftButton")
    key:Fire("OnGamePadButtonDown", "PAD2")
    assert(saves == 3 and key.text == "PAD2")
    key:Fire("OnClick", "LeftButton")
    key:Fire("OnMouseWheel", 1)
    assert(saves == 4 and key.text == "MOUSEWHEELUP")
    key:Fire("OnClick", "LeftButton")
    key:Fire("OnClick", "Button4")
    assert(saves == 5 and key.text == "Button4")
    key:Fire("OnClick", "LeftButton")
    body.visible = false
    body:Fire("OnHide")
    assert(not next(eventOwner.events) and not key.scripts.OnKeyDown and not key.keyboard and not key.gamepad)
    assert(editor.Open(ctx, "gear"))
    eventOwner:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
    body.visible = false
    body:Fire("OnHide")
    assert(editor.Open(ctx, "gear"), "hidden editor retained the old combat event")
end

Run(false)
Run(true)
print("Character Panel binding controls: lazy focus, custom slots, native destinations, conflict and combat")

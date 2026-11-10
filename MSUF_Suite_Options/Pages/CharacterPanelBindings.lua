local _, P = ...
local S, Suite, W, M, T, Tr, HM = P.S, P.Suite, P.W, P.M, P.T, P.Tr, P.HM
local Bindings, Tabs = Suite.CharacterBindings, S.CharacterHeader
local PAGE, ID, SECTION = "suite_hud", "characterPanel", "suite_hud_characterPanel_bindings"
local PLAYER, NATIVE, DIRECT = "tab", "native", "direct"
local BUTTON_HEIGHT, GAP = 28, 8
local KEY_LABELS = { "Primary key", "Secondary key" }
local Editor = {}
P.CharacterPanelBindings = Editor
local active

local function Config()
    return S.Config(ID)
end

local function Blocked(ui)
    return ui.combat or P.Combat()
end

local function Command(ui, group)
    if group == NATIVE then return ui.native.command end
    return Bindings.CommandForTab(Config(), ui.tab)
end

local function Context(command)
    local context = C_KeyBindings.GetBindingContextForAction(command)
    if Suite.Public(context) then return true, context end
end

local function ReadKeys(command, context)
    local first, second, extra = GetBindingKey(command, nil, context)
    if not Suite.Public(first) or not Suite.Public(second) or not Suite.Public(extra) then return end
    return true, first, second, extra
end

local function KeyText(key)
    if not key then return Tr("No shortcut assigned") end
    local text = GetBindingText(key)
    return Suite.Public(text) and text or key
end

local function PaintLabel(button, label)
    if button.bindingLabel == label then return end
    button.bindingLabel = label
    P.SetButtonText(button, label)
end

local function Enable(button, enabled)
    if button.bindingEnabled == enabled then return end
    button.bindingEnabled = enabled
    button:SetEnabled(enabled)
end

local function Cancel(ui)
    if not active or active.ui ~= ui then return end
    local button = active.button
    active = nil
    button:SetScript("OnKeyDown", nil)
    button:SetScript("OnGamePadButtonDown", nil)
    button:SetScript("OnMouseWheel", nil)
    button:EnableKeyboard(false)
    button:EnableGamePadButton(false)
    button:EnableMouseWheel(false)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

local function VisibleTab(config, id)
    for _, tab in ipairs(Tabs.Order(config, PLAYER)) do
        if tab.id == id then return tab end
    end
end

local function Identity(ui, group)
    if group == NATIVE then return ui.native.id end
    return ui.tab
end

local function Current(claim)
    local ui = claim.ui
    if Blocked(ui) or not ui.body:IsVisible() or not claim.guard() or Config() ~= claim.config
        or Identity(ui, claim.group) ~= claim.id or Command(ui, claim.group) ~= claim.command then
        return false
    end
    local set = GetCurrentBindingSet()
    local valid, context = Context(claim.command)
    if not valid or not Suite.Public(set) or set ~= claim.set or context ~= claim.context then return false end
    local readable, first, second, extra = ReadKeys(claim.command, context)
    return readable and not extra and first == claim.first and second == claim.second
end

local function PaintKeys(ui, group)
    local row = ui.keys[group]
    local command = Command(ui, group)
    local readable, first, second, extra
    if command then
        local valid, context = Context(command)
        if valid then readable, first, second, extra = ReadKeys(command, context) end
    end
    local enabled = readable and not extra and not Blocked(ui) or false
    Enable(row[1], enabled)
    Enable(row[2], enabled)
    local capturing = active and active.button
    PaintLabel(row[1], capturing == row[1] and Tr("Press a key. Escape cancels.") or first and KeyText(first) or Tr(KEY_LABELS[1]))
    PaintLabel(row[2], capturing == row[2] and Tr("Press a key. Escape cancels.") or second and KeyText(second) or Tr(KEY_LABELS[2]))
end

local function Paint(ui)
    if active and active.ui == ui and not Current(active) then Cancel(ui) end
    local config = Config()
    local destination = VisibleTab(config, Bindings.NativeTab(config, ui.native.id))
    local tab = VisibleTab(config, ui.tab) or VisibleTab(config, Tabs.HomeTab(config, PLAYER))
    ui.tab = tab and tab.id
    PaintLabel(ui.nativeButton, ui.native.label)
    PaintLabel(ui.destination, destination and destination.label or ui.native.defaultLabel or Tr("Shortcut destination"))
    PaintLabel(ui.directButton, tab and tab.label or Tr("Choose a tab"))
    local slotLabel = Tr("Choose custom shortcut slot")
    if tab and tab.custom then
        for _, slot in ipairs(Bindings.Slots) do
            if config[slot.key] == tab.id then slotLabel = slot.label break end
        end
    end
    PaintLabel(ui.slotButton, slotLabel)
    local enabled = not Blocked(ui)
    Enable(ui.nativeButton, enabled)
    Enable(ui.destination, enabled)
    Enable(ui.directButton, enabled)
    local custom = tab ~= nil and tab.custom == true
    if ui.slotButton:IsShown() ~= custom then ui.slotButton:SetShown(custom) end
    Enable(ui.slotButton, enabled and custom)
    Enable(ui.open, enabled)
    PaintKeys(ui, NATIVE)
    PaintKeys(ui, DIRECT)
end

local function WriteKey(key, command, context)
    if key == nil then return true end
    local changed = Suite.Dispatch(SetBinding, key, command, context)
    return Suite.Public(changed) and not not changed
end

local function UndoKeys(claim, first, second)
    local context, command = claim.context, claim.command
    if first then
        local action = GetBindingAction(first, nil, context)
        if Suite.Public(action) and action == command then WriteKey(first, nil, context) end
    end
    if second then
        local action = GetBindingAction(second, nil, context)
        if Suite.Public(action) and action == command then WriteKey(second, nil, context) end
    end
    WriteKey(claim.first, command, context)
    WriteKey(claim.second, command, context)
end

local function ReplaceKeys(claim, first, second)
    if first == claim.first and second == claim.second then return true end
    local ui, context, command = claim.ui, claim.context, claim.command
    ui.applying = true
    local written = WriteKey(claim.first, nil, context) and WriteKey(claim.second, nil, context)
        and WriteKey(first, command, context) and WriteKey(second, command, context)
    local saved = written and Suite.Dispatch(Suite.Finish, SaveBindings, claim.set)
    saved = Suite.Public(saved) and saved == true
    if not saved then UndoKeys(claim, first, second) end
    ui.applying = nil
    return saved
end

local function Commit(claim, key)
    if not Current(claim) then return end
    if key then
        local action = GetBindingAction(key, nil, claim.context)
        if not Suite.Public(action) then return end
        if action and action ~= "" and action ~= claim.command then
            local name = GetBindingName(action)
            Suite.Print(Tr("%s is already bound to %s."):format(KeyText(key), Suite.Public(name) and name or action))
            return
        end
    end
    local first, second = claim.first, claim.second
    if claim.index == 1 then
        if key and key == second then second = first end
        first = key
    else
        if key and key == first then first = second end
        second = key
    end
    if not first then first, second = second, nil end
    if not ReplaceKeys(claim, first, second) then Suite.Print(Tr("The key binding could not be saved.")) end
end

local function Input(_, raw)
    local claim = active
    if not claim or not Suite.Public(raw) or type(raw) ~= "string" then return end
    local ui = claim.ui
    if not Current(claim) or raw == "ESCAPE" then Cancel(ui) Paint(ui) return end
    local key = GetConvertedKeyOrButton(raw)
    if not Suite.Public(key) or not key or IsKeyPressIgnoredForBinding(key) then return end
    key = CreateKeyChordStringUsingMetaKeyState(key)
    if not Suite.Public(key) or type(key) ~= "string" or key == "" then return end
    Cancel(ui)
    Commit(claim, key)
    Paint(ui)
end

local function MouseWheel(button, delta)
    if Suite.Public(delta) then Input(button, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end
end

local function KeyClick(ui, button, group, index, mouse)
    if not Suite.Public(mouse) then return end
    local prior = active and active.button
    if mouse ~= "LeftButton" and mouse ~= "RightButton" then
        if prior == button then Input(button, mouse) end
        return
    end
    if active then Cancel(active.ui) end
    if prior == button and mouse ~= "RightButton" then Paint(ui) return end
    local command, set = Command(ui, group), GetCurrentBindingSet()
    if not command or not Suite.Public(set) or type(set) ~= "number" or set == Enum.BindingSet.Default then return end
    local valid, context = Context(command)
    if not valid then return end
    local readable, first, second, extra = ReadKeys(command, context)
    if not readable or extra then return end
    local claim = { ui = ui, button = button, group = group, index = index, command = command,
        guard = P.ProfileGuard(), config = Config(), id = Identity(ui, group),
        context = context, set = set, first = first, second = second }
    if mouse == "RightButton" then
        Commit(claim, nil)
    else
        active = claim
        button:SetScript("OnKeyDown", Input)
        button:SetScript("OnGamePadButtonDown", Input)
        button:SetScript("OnMouseWheel", MouseWheel)
        button:SetPropagateKeyboardInput(false)
        button:EnableKeyboard(true)
        button:EnableGamePadButton(true)
        button:EnableMouseWheel(true)
        button:RegisterForClicks("AnyUp")
    end
    Paint(ui)
end

local function Menu(ui, button, entries, select)
    Cancel(ui)
    Paint(ui)
    local guard, config = P.ProfileGuard(), Config()
    P.ContextMenu(button, function(_, menu)
        for _, entry in ipairs(entries) do
            menu:CreateButton(entry.label, function()
                if not Blocked(ui) and guard() and ui.body:IsVisible() and config == Config() then
                    select(entry)
                    Paint(ui)
                end
            end)
        end
    end)
end

local function ChooseDestination(ui, button)
    local native = ui.native
    local entries = { { id = "", label = native.defaultLabel or Tr("Default") } }
    for _, tab in ipairs(Tabs.Order(Config(), PLAYER)) do entries[#entries + 1] = tab end
    Menu(ui, button, entries, function(tab)
        if ui.native ~= native then return end
        local patch = Bindings.SetNativeTab(Config(), native.id, tab.id)
        if patch then P.SetMany(ID, patch) end
    end)
end

local function ChooseSlot(ui, button)
    local config, tab = Config(), ui.tab
    local entries = {}
    local set = GetCurrentBindingSet()
    if not Suite.Public(set) then return end
    for _, slot in ipairs(Bindings.Slots) do
        local id = config[slot.key]
        if id == tab then
            entries[#entries + 1] = { index = slot.index, id = "", key = slot.key,
                label = Tr("Remove shortcut slot") }
        elseif not id or id == "" then
            local valid, context = Context(slot.command)
            local readable, first, second, extra
            if valid then readable, first, second, extra = ReadKeys(slot.command, context) end
            if readable and not extra then
                local keys = KeyText(first)
                if second then keys = keys .. ", " .. KeyText(second) end
                local label = ("%s (%s)"):format(slot.label, keys)
                entries[#entries + 1] = { index = slot.index, id = tab, label = label,
                    command = slot.command, context = context, first = first, second = second }
            end
        end
    end
    Menu(ui, button, entries, function(entry)
        if ui.tab ~= tab or not Tabs.TabVisible(Config(), PLAYER, tab) then return end
        if entry.id == "" then
            if Config()[entry.key] ~= tab then return end
        else
            local valid, context = Context(entry.command)
            local currentSet = GetCurrentBindingSet()
            if not valid or context ~= entry.context or not Suite.Public(currentSet) or currentSet ~= set then return end
            local readable, first, second, extra = ReadKeys(entry.command, context)
            if not readable or extra or first ~= entry.first or second ~= entry.second then return end
        end
        local patch = Bindings.SetSlot(Config(), entry.index, entry.id)
        if patch and P.SetMany(ID, patch) then Bindings.RefreshLabels(Config()) end
    end)
end

local function Button(ui, label, key, x, y, width, click)
    local button = T.Button(ui.body, label, width, BUTTON_HEIGHT, { history = false })
    button:SetPoint("TOPLEFT", x, y)
    button:SetScript("OnClick", function(self, mouse)
        if not Blocked(ui) then click(self, mouse) end
    end)
    local meta = P.Meta(PAGE, ID, key, "action", SECTION)
    ui.entries[#ui.entries + 1] = { widget = button, rule = { key = key, label = label }, meta = meta }
    return button
end

local function KeyRow(ui, group, y, half)
    local row = {}
    ui.keys[group] = row
    for index = 1, 2 do
        local label = KEY_LABELS[index]
        local button = Button(ui, label, group .. "Key" .. index, 16 + (index - 1) * (half + GAP), y, half,
            function(self, mouse) KeyClick(ui, self, group, index, mouse) end)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        M.AddTooltip(button, label, nil, { hook = true })
        row[index] = button
    end
end

local function TrackVisibility(ui)
    local function Show()
        ui.combat = nil
        ui.open:RegisterEvent("UPDATE_BINDINGS")
        ui.open:RegisterEvent("PLAYER_REGEN_DISABLED")
        ui.open:RegisterEvent("PLAYER_REGEN_ENABLED")
        Paint(ui)
    end
    ui.open:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            ui.combat = true
            Cancel(ui)
        elseif event == "PLAYER_REGEN_ENABLED" then
            ui.combat = nil
        end
        if not ui.applying then Paint(ui) end
    end)
    ui.body:HookScript("OnShow", Show)
    ui.body:HookScript("OnHide", function()
        Cancel(ui)
        ui.combat = nil
        ui.open:UnregisterEvent("UPDATE_BINDINGS")
        ui.open:UnregisterEvent("PLAYER_REGEN_DISABLED")
        ui.open:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end)
    if ui.body:IsVisible() then Show() end
end

local function BuildContent(ctx, body, width)
    local ui = { body = body, native = Bindings.Native[1], keys = {}, entries = {}, tab = ctx.characterBindingTab }
    ctx.characterBindingEditor = ui
    local half = math.floor((width - GAP) / 2)
    local right = 16 + half + GAP
    local note = P.Description(body, "Tab destinations use the Suite profile. Keys use Blizzard's current binding set.", 16, -18, width)
    local y = -30 - math.ceil(note:GetStringHeight())
    local combatNote = P.Text(body, "Redirected Blizzard windows use their original shortcut action in combat.", 16, y, width, nil, "supporting")
    y = y - 8 - math.ceil(combatNote:GetStringHeight())
    local help = P.Text(body, "Click a key to change it. Right-click to clear it.", 16, y, width, nil, "supporting")
    y = y - 12 - math.ceil(help:GetStringHeight())
    P.Text(body, "Blizzard shortcuts", 16, y, width, nil, "section")
    y = y - 20
    ui.nativeButton = Button(ui, "Blizzard shortcuts", "nativeBinding", 16, y, half, function(self)
        Menu(ui, self, Bindings.Native, function(entry) ui.native = entry end)
    end)
    ui.destination = Button(ui, "Shortcut destination", "bindingDestination", right, y, half,
        function(self) ChooseDestination(ui, self) end)
    KeyRow(ui, NATIVE, y - BUTTON_HEIGHT - GAP, half)
    y = y - 2 * (BUTTON_HEIGHT + GAP) - 10
    P.Text(body, "Direct tab shortcuts", 16, y, width, nil, "section")
    y = y - 20
    ui.directButton = Button(ui, "Choose a tab", "directBinding", 16, y, half, function(self)
        Menu(ui, self, Tabs.Order(Config(), PLAYER), function(tab) ui.tab = tab.id end)
    end)
    ui.slotButton = Button(ui, "Choose custom shortcut slot", "shortcutSlot", right, y, half,
        function(self) ChooseSlot(ui, self) end)
    KeyRow(ui, DIRECT, y - BUTTON_HEIGHT - GAP, half)
    y = y - 2 * (BUTTON_HEIGHT + GAP) - 8
    ui.open = Button(ui, "Open Blizzard key bindings", "openBlizzardBindings", 16, y, width, function()
        Cancel(ui)
        Bindings.RefreshLabels(Config())
        Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, Suite.Text("Character Panel"))
    end)
    P.HUDMenu.Prepare(body, ui.entries)
    M.TrackRefresh(ctx, function()
        if body:IsVisible() then Paint(ui) end
    end)
    TrackVisibility(ui)
    return y - BUTTON_HEIGHT
end

function Editor.Build(ctx, builder)
    ctx.characterBindingSection = P.LazySection(builder, SECTION, Tr("Key bindings"), false, {
        content = function(body)
            local width = math.max(240, (HM.GetSectionWidth(body) or builder.width or 720) - 32)
            return BuildContent(ctx, body, width)
        end,
        finish = function(body, y) P.FinishBody(builder, body, y) end,
    })
end

function Editor.Open(ctx, tabId)
    local body = ctx.characterBindingSection
    if not body or P.Combat() or not Tabs.TabVisible(Config(), PLAYER, tabId) then return false end
    if ctx.characterBindingEditor and Blocked(ctx.characterBindingEditor) then return false end
    ctx.characterBindingTab = tabId
    P.EnsureSectionContent(body)
    local ui = ctx.characterBindingEditor
    if ui then
        Cancel(ui)
        ui.tab = tabId
        Paint(ui)
    end
    W.FocusCollapsibleSection(body, { persist = true, flash = true })
    return true
end

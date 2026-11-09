local root = assert(arg[1])
local H = dofile(root .. "/tools/tests/suite_minimap_harness.lua")
local ID = "dataTexts"

local function AddBar(Suite, config, bar)
    local values = Suite.DataTextBarCreationValues(config, bar)
    local prefix = "bar" .. bar .. "Slot"
    values[prefix .. 1] = Suite.DataTextSourceIndex.fps
    for slot = 2, Suite.DataTextSlotLimit do values[prefix .. slot] = Suite.DataTextSourceIndex.none end
    return values
end

local function Load(world, file, private)
    setfenv(assert(loadfile(root .. "/" .. file .. ".lua")), world.G)("Suite", private)
end

local function Options(world, client)
    local G, Suite = world.G, world.Suite
    local close, outline, fallback
    local create = G.CreateFrame
    G.CreateFrame = function(kind, name, parent, template)
        local frame = create(kind, name, parent, template)
        frame.EnableKeyboard = function() end
        frame.SetPropagateKeyboardInput = function() end
        if template == "BackdropTemplate" then
            outline = frame
            frame.SetBackdrop = function(self, value) self.backdrop = value end
            frame.SetBackdropBorderColor = function(self, ...) self.border = { ... } end
            frame.SetIgnoreParentAlpha = function(self, value) self.independentAlpha = value end
        end
        return frame
    end
    local theme = { colors = { text = {} } }
    function theme.Font(parent, _, text)
        local label = parent:CreateFontString()
        label:SetText(text)
        if text == "X" then fallback = parent end
        return label
    end
    function theme.Button(parent, text)
        local button = G.CreateFrame("Button", nil, parent)
        button._msuf2Label = theme.Font(button, nil, text)
        return button
    end
    theme.RoleButton = theme.Button
    if client == "Forever" then
        function theme.CloseButton(parent)
            close = theme.Button(parent, "host close glyph")
            return close
        end
    end
    local function ToggleAt(parent)
        local toggle = theme.Button(parent, "")
        toggle._msuf2LabelHit = G.CreateFrame("Button", nil, parent)
        toggle.SetChecked = function(self, checked) self.checked = checked end
        return toggle
    end
    G.MSUF2 = { Theme = theme, Widgets = { ToggleAt = ToggleAt } }
    Load(world, "MSUF_Suite/Core/HostBridgeMenu", Suite)
    local P = {}
    Load(world, "MSUF_Suite_Options/Menu/Bridge", P)
    Load(world, "MSUF_Suite_Options/Pages/DataTextsSourcePicker", P)
    Load(world, "MSUF_Suite_Options/Menu/DeletePicker", P)
    Load(world, "MSUF_Suite_Options/Pages/DataTextsWorkspace", P)
    return P, function() return close or fallback end, function() return outline end
end

for _, client in ipairs({ "Mainline", "Forever" }) do
    local W = H.New(root, client, { clientCombatOrder = true, beforeModules = function(world)
        world.G.GetFramerate = function() return 75 end
        world.G.PlayerHasToy = function() return false end
        world.G.C_Item = { GetItemCount = function() return 0 end }
    end })
    local G, S, Suite = W.G, W.S, W.Suite
    local config = S.Config(ID)
    config.barIds, config.enabled = "0", false
    W.LoadAddon("MSUF_Suite_DataTexts")
    S.Start()
    for bar = 1, 9 do
        assert(S.SetMany(ID, AddBar(Suite, config, bar)))
    end
    assert(S.Set(ID, "enabled", true))
    local runtime = S.instances[ID]
    local first, last = runtime.bars[1].frame, runtime.bars[9].frame
    first:SetAlpha(0)
    local P, Close, Outline = Options(W, client)
    local anchor = G.CreateFrame("Button", nil, G.UIParent)
    local open, picker = P.OpenDeletePicker
    P.OpenDeletePicker = function(...) picker = open(...) end
    P.DataTextPage.OpenBarRemoval(anchor)
    assert(Close() and Close():IsVisible(), "delete picker has no visible close glyph")
    assert(not Outline(), "outline allocated before hover")
    local row = picker.rows[1]
    row.mouseOver = true
    W.Fire(row.toggle._msuf2LabelHit, "OnEnter")
    local outline = assert(Outline(), "hovering the label did not create a runtime outline")
    assert(outline:IsVisible() and outline:GetParent() == first and outline.independentAlpha and not outline.mouse,
        "hover outline must follow the exact bar, including mouseover-only bars, without catching clicks")
    assert(outline.backdrop.edgeSize > 0 and outline.border[4] == 1)
    assert(outline:GetFrameStrata() == "FULLSCREEN" and picker:GetFrameStrata() == "FULLSCREEN_DIALOG",
        "outline must be visible above Menu2 without covering the picker")
    assert(picker.count == 0 and not picker.apply:IsEnabled(), "hover changed the delete selection")
    picker.next:Click()
    assert(Outline() == outline and outline:GetParent() == last and outline:IsVisible(),
        "paging under the cursor retained the outline on a recycled row's old bar")
    row.mouseOver = false
    W.Fire(row.toggle, "OnLeave")
    assert(not outline:IsShown(), "leaving a row retained the outline")
    W.Fire(row, "OnEnter")
    Close():Click()
    assert(not picker:IsShown() and not outline:IsShown(), "close glyph did not dismiss the picker and outline")

    P.DataTextPage.OpenBarRemoval(anchor)
    W.Fire(row.toggle, "OnEnter")
    Suite.Registry.NotifyListeners("profile", "switch")
    assert(not picker:IsShown() and not outline:IsShown(), "profile switch retained the hover")

    P.DataTextPage.OpenBarRemoval(anchor)
    W.Fire(row.toggle, "OnEnter")
    W.SetCombat(true)
    assert(not picker:IsShown() and not outline:IsShown(), "combat entry retained the picker or the outline")
    W.SetCombat(false)

    runtime:SetDeleteHover(9)
    assert(outline:IsVisible() and outline:GetParent() == last)
    assert(S.SetMany(ID, Suite.DataTextBarRemovalValues(config, 9)))
    assert(not outline:IsVisible(), "removing the outlined runtime bar left a floating outline")
    assert(S.SetMany(ID, AddBar(Suite, config, 42)))
    assert(runtime.bars[42].frame == last and not outline:IsShown(), "pooled frame retained a stale outline")
    print("DataTexts delete picker: " .. client .. " PASS")
end

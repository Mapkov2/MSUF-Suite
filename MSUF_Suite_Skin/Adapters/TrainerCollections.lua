local _, NS = ...
if not NS.Client.isForever then return end

local Chrome = {}
NS.TrainerCollections = Chrome
local Kit, Safety = NS.AdapterKit, NS.Safety
local Field = Safety.Field
local windows, hooks = {}, {}
local panel = Kit.SurfaceSpec("panel", 4, 0)
panel.interactive, panel.motion = false, false
local rowSpec = Kit.SurfaceSpec("card", 4, 1, true, true, true, "navigationActive")
rowSpec.selectionEdge, rowSpec.motion, rowSpec.interactive = true, false, false
local tabSpec = Kit.SurfaceSpec("navigation", 6, 1, false, true, true, "navigationActive")
tabSpec.selectionEdge, tabSpec.motion, tabSpec.interactive = true, false, false
local action = { role = "buttonPrimary", motion = false, interactive = false, inset = 1 }
local actionPieces = { "Left", "Middle", "Right" }
local filter = { role = "button", useControlShape = true, inset = 1, motion = false, regions = { "Background" } }
local search = { role = "input", motion = false }
local headerArt = { "LeftPiece", "CenterPiece", "RightPiece" }
local insetArt = {
    "Bg", "BackgroundTile", "ShadowCornerTopLeft", "ShadowCornerTopRight", "ShadowCornerBottomLeft",
    "ShadowCornerBottomRight", "ShadowCornerTop", "ShadowCornerLeft", "ShadowCornerRight", "ShadowCornerBottom",
}

local function Inset(state, frame)
    if Kit.Ensure(state, frame, panel) then
        Kit.FadeFields(state, frame, insetArt)
        Kit.FadeNineSlice(state, Field(frame, "NineSlice"))
    end
end

local function SyncSelection(state, target, texture)
    -- An implicitly protected control keeps its native selection artwork
    -- throughout combat. Existing unprotected surfaces follow every update.
    if state.surfaces[target] then
        local selected = Kit.IsShown(texture)
        if state.selection[target] ~= selected and Safety.CanDecorate(target) then
            NS.Surface.SetActive(target, selected)
            state.selection[target] = selected
        end
    end
end

local function PaintRow(state, row)
    if not Safety.CanCreateRegions(row, not NS.IsCombatLocked()) then return end
    local selected = Field(row, "selectedTex") or Field(row, "selectedTexture")
    if not selected then
        if not state.surfaces[row] and Field(row, "CollapseIcon") and Kit.Ensure(state, row, panel) then
            Kit.FadeFields(state, row, headerArt)
        end
        return
    end
    -- These are decorative backplates. Availability, lock, costs, icon and
    -- native highlight stay under Blizzard control even on recycled rows.
    local background = Field(row, "background")
    if not state.surfaces[row] then
        if not Kit.Ensure(state, row, rowSpec) then return end
        if not background then Kit.Fade(state, Safety.Read(row, "GetNormalTexture")) end
        if Safety.CanDecorate(row) then Kit.Fade(state, selected) end
    end
    if background then
        -- The journal tints this same texture red for an unusable mount/pet.
        local red, green, blue = Safety.ReadColor(background, "GetVertexColor")
        local unavailable = red == 1 and green == 0 and blue == 0
        -- Some native initializers retint the backplate with explicit alpha 1.
        if state.unavailable[row] ~= unavailable or (not unavailable and Safety.Read(background, "GetAlpha") ~= 0) then
            if unavailable then NS.Cosmetics.Restore(background, state.owner) else Kit.Fade(state, background) end
            state.unavailable[row] = unavailable
        end
    end
    SyncSelection(state, row, selected)
end

local function PaintAction(state, button)
    -- The trainer and summon buttons keep their native enabled/disabled font,
    -- highlight, scripts and gamepad binding. Only replace their three slices.
    if Kit.Ensure(state, button, action) then Kit.FadeFields(state, button, actionPieces) end
end

local function PaintScrollBar(state, bar)
    if not bar then return end
    local parts, contract = NS.ScrollBarSkin.PublicParts(bar)
    if parts then NS.ScrollBarSkin.Apply(bar, state.owner, parts, contract) end
end

local function PaintTabs(state)
    local tabs = Kit.Path(state.frame, "TabContainer", "Tabs")
    if type(tabs) ~= "table" then return end
    for _, tab in ipairs(tabs) do
        if not state.surfaces[tab] then
            local painted, surface = Kit.Ensure(state, tab, tabSpec)
            if painted then
                Kit.FitSideTab(tab, surface)
                Kit.Fade(state, Field(tab, "Background"))
                if Safety.CanDecorate(tab) then Kit.Fade(state, Field(tab, "SelectedTexture")) end
                Kit.SuppressVertexAlpha(state, Field(tab, "TabGlow"))
            end
        end
        SyncSelection(state, tab, Field(tab, "SelectedTexture"))
    end
end

-- One post-hook per native initializer. Selection also calls these directly
-- for existing buttons without an OnInitializedFrame notification.
local function Hook(name, root, paint)
    if hooks[name] then return end
    hooks[name] = Kit.HookGlobal(name, Safety.Isolated(function(target)
        local state = windows[root]
        if not state then return end
        if NS.IsCombatLocked() then
            if paint == PaintTabs then
                for _, tab in ipairs(Field(target, "Tabs") or {}) do
                    SyncSelection(state, tab, Field(tab, "SelectedTexture"))
                end
            elseif state.surfaces[target] then
                PaintRow(state, target)
            end
            if not state.pending then
                state.pending = true
                NS.CombatGate.RunOrDefer(state.key, state.refresh)
            end
        else
            paint(state, target)
        end
    end))
end

local function PaintTrainer(state)
    local frame = state.frame
    Hook("ClassTrainerFrame_InitServiceButton", "trainer", PaintRow)
    Hook("ClassTrainerFrame_InitCategoryButton", "trainer", PaintRow)
    Kit.Fade(state, Field(frame, "BG"))
    Kit.Fade(state, _G.ClassTrainerFrameMoneyBg)
    Inset(state, Field(frame, "Inset"))
    Inset(state, Field(frame, "bottomInset"))
    Kit.Ensure(state, Field(frame, "trainingPoints"), panel)
    Kit.SkinControl(state, Field(frame, "FilterDropdown"), filter)
    PaintAction(state, Field(frame, "TrainButton"))
    PaintScrollBar(state, Field(frame, "ScrollBar"))
    PaintRow(state, Field(frame, "skillStepButton"))
    Kit.ForEachRow(Field(frame, "ScrollBox"), state.paintRow)
end

local pages = { "MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame" }
local pageInsets = { "LeftInset", "RightInset", "BottomLeftInset", "iconsFrame", "ItemsCollectionFrame" }
local filters = { "FilterDropdown", "FilterButton", "ClassDropdown" }

local function PaintPage(state, page)
    for _, key in ipairs(pageInsets) do Inset(state, Field(page, key)) end
    for _, key in ipairs(filters) do Kit.SkinControl(state, Field(page, key), filter) end
    local input = Field(page, "searchBox") or Field(page, "SearchBox")
    Kit.SkinControl(state, input, search, "ApplySearchBox")
    local button = Field(page, "MountButton") or Field(page, "SummonButton")
    PaintAction(state, button)
    local preview = Field(page, "MountDisplay") or Field(page, "PetCard")
    if Kit.Ensure(state, preview, panel) then
        Kit.Fade(state, Field(preview, "YesMountsTex") or Field(preview, "PetBackground"))
    end
    PaintScrollBar(state, Field(page, "ScrollBar"))
    Kit.ForEachRow(Field(page, "ScrollBox"), state.paintRow)
end

local function PaintCollections(state)
    Hook("MountJournal_InitMountButton", "collections", PaintRow)
    Hook("MountJournal_ResetMountButton", "collections", PaintRow)
    Hook("PetJournal_InitPetButton", "collections", PaintRow)
    Hook("CollectionsJournal_SetTab_Internal", "collections", PaintTabs)
    PaintTabs(state)
    for _, name in ipairs(pages) do
        local page = _G[name]
        if Kit.ParentIs(page, state.frame) then PaintPage(state, page) end
    end
    if Kit.ParentIs(_G.WardrobeCollectionFrame, state.frame) then
        local sets = Field(_G.WardrobeCollectionFrame, "SetsCollectionFrame")
        Inset(state, Field(sets, "LeftInset"))
        Inset(state, Field(sets, "RightInset"))
    end
end

local painters = { trainer = PaintTrainer, collections = PaintCollections }

function Chrome.Apply(frame, owner, id)
    if NS.IsCombatLocked() then return end
    local state = windows[id]
    if not state then
        state = { frame = frame, owner = owner, key = "trainer-collections:" .. id, surfaces = Kit.WeakSet() }
        state.selection, state.unavailable = Kit.WeakSet(), Kit.WeakSet()
        state.paintRow = function(row) PaintRow(state, row) end
        state.refresh = function()
            state.pending = nil
            if windows[id] == state then painters[id](state) end
        end
        windows[id] = state
    end
    painters[id](state)
    return true
end

function Chrome.Disable(owner)
    for id, state in pairs(windows) do
        if state.owner == owner then
            NS.CombatGate.Cancel(state.key)
            Kit.HideSurfaces(state)
            windows[id] = nil
        end
    end
end

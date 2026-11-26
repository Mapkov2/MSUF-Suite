-- Drive the catalog entry, then reuse the same native row for another skill.
local root = assert(arg[1])
local skin = root .. "/MSUF_Suite_Skin/"
local fixture = assert(loadfile(root .. "/tools/tests/suite_skin_generic_windows_contract.lua"))
local f = fixture("flight-map-fixture", "Forever")
local NS = f.NS
local trainer = NS.BlizzardCatalog.FindByFrame("ClassTrainerFrame")
local journal = NS.BlizzardCatalog.FindByFrame("CollectionsJournal")
assert(trainer.mode and trainer.mode.nativeListChrome and journal.mode and journal.mode.nativeListChrome,
    "Forever trainer and journal still use generic row traversal")
local retail = { Client = { isForever = false } }
assert(loadfile(skin .. "Adapters/TrainerCollections.lua"))("skin", retail)
assert(not retail.TrainerCollections, "Forever adapter initialized on Retail")
assert(loadfile(skin .. "Adapters/Catalog.lua"))("skin", retail)
assert(loadfile(skin .. "Adapters/CatalogGlass.lua"))("skin", retail)
assert(not retail.BlizzardCatalog.FindByFrame("ClassTrainerFrame").mode)
assert(not retail.BlizzardCatalog.FindByFrame("CollectionsJournal").mode)
local function widget(name, parent)
    local w = f.frame(name)
    w.shown, w.alpha = true, 1
    function w:GetParent() return parent end
    function w:IsShown() return self.shown end
    function w:IsVisible() return self.shown end
    function w:GetAlpha() return self.alpha end
    function w:SetAlpha(a) self.alpha = a end
    return w
end
assert(loadfile(skin .. "../MSUF_Suite/Appearance/Cosmetics.lua"))("skin", NS)
assert(loadfile(skin .. "Adapters/TrainerCollections.lua"))("skin", NS)
NS.ControlSkin.ApplyButton = function(button, _, spec) button.controlSpec = spec return true end
NS.ControlSkin.ApplySearchBox = NS.ControlSkin.ApplyButton
NS.ScrollBarSkin.PublicParts = function(bar) return {bar}, bar end
NS.ScrollBarSkin.Apply = function(bar, _, parts, contract)
    assert(contract == bar and parts[1] == bar, "native list registered general scroll motion")
    bar.painted = true
    return true
end
local function nativeRow(parent, trainerRow)
    local row = widget(nil, parent)
    local selected = widget(nil, row)
    selected.shown = false
    if trainerRow then
        row.selectedTex, row.normal = selected, widget(nil, row)
        function row:GetNormalTexture() return self.normal end
    else
        row.selectedTexture, row.background = selected, widget(nil, row)
    end
    row.icon, row.alternateCost, row.lock = widget(nil, row), widget(nil, row), widget(nil, row)
    return row
end
local function list(parent)
    local box = widget(nil, parent)
    box.rows = {}
    function box:ForEachFrame(visit) for _, row in ipairs(self.rows) do visit(row) end end
    function box:RegisterCallback() error("generic callback installed on a native list") end
    return box
end
ClassTrainerFrame = widget("ClassTrainerFrame")
local trainerFrame = ClassTrainerFrame
trainerFrame.ScrollBox, trainerFrame.ScrollBar = list(trainerFrame), widget(nil, trainerFrame)
trainerFrame.TrainButton, trainerFrame.trainingPoints = widget(nil, trainerFrame), widget(nil, trainerFrame)
trainerFrame.FilterDropdown, trainerFrame.BG = widget(nil, trainerFrame), widget(nil, trainerFrame)
local row = nativeRow(trainerFrame.ScrollBox, true)
trainerFrame.ScrollBox.rows[1] = row
trainerFrame.TrainButton.Left = widget(nil, trainerFrame.TrainButton)
trainerFrame.TrainButton.Right = widget(nil, trainerFrame.TrainButton)
trainerFrame.TrainButton.Middle = widget(nil, trainerFrame.TrainButton)
ClassTrainerTrainButton = trainerFrame.TrainButton
local purchases, lastPurchase, current = 0
local function nativeSelect(button, service, available)
    button.selectedTex.shown = true
    current, trainerFrame.TrainButton.enabled = service, available
end
local function nativeTrain()
    if trainerFrame.TrainButton.enabled then purchases, lastPurchase = purchases + 1, current end
end
ClassTrainerFrame_InitServiceButton, trainerFrame.TrainButton.OnClick = nativeSelect, nativeTrain
local owner = "blizzardWindows"
assert(NS.GenericWindows.ApplyEntry(trainer, owner))
assert(row.normal.alpha == 0 and row.surfaceSpec.interactive == false and row.surfaceSpec.motion == false)
assert(trainerFrame.TrainButton.surfaceSpec and trainerFrame.trainingPoints.surfaceSpec and trainerFrame.ScrollBar.painted)
assert(trainerFrame.TrainButton.Left.alpha == 0 and trainerFrame.TrainButton.Middle.alpha == 0)
ClassTrainerFrame_InitServiceButton(row, 4, false)
trainerFrame.TrainButton.OnClick()
assert(row.surfaceActive and purchases == 0 and trainerFrame.TrainButton.OnClick == nativeTrain)
ClassTrainerFrame_InitServiceButton(row, 7, true)
trainerFrame.TrainButton.OnClick()
assert(purchases == 1 and lastPurchase == 7 and row.icon.alpha == 1 and row.alternateCost.alpha == 1 and row.lock.alpha == 1)
local recycled = nativeRow(trainerFrame.ScrollBox, true)
ClassTrainerFrame_InitServiceButton(recycled, 9, true)
assert(recycled.normal.alpha == 0 and recycled.selectedTex.shown and recycled.surfaceActive)

CollectionsJournal = widget("CollectionsJournal")
CollectionsJournal.TabContainer = { Tabs = {} }
local tabs = CollectionsJournal.TabContainer.Tabs
for i, name in ipairs({"MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame"}) do
    local page, tab = widget(name, CollectionsJournal), widget(nil, CollectionsJournal)
    _G[name], tabs[i] = page, tab
    tab.Background, tab.SelectedTexture = widget(nil, tab), widget(nil, tab)
    tab.SelectedTexture.shown = i == 1
    page.FilterDropdown = widget(nil, page)
    if i <= 2 then
        page.ScrollBox, page.LeftInset, page.ScrollBar = list(page), widget(nil, page), widget(nil, page)
        page.ScrollBox.rows[1] = nativeRow(page.ScrollBox)
        local preview = widget(nil, page)
        preview.ModelScene = widget(nil, preview)
        if i == 1 then page.MountDisplay, preview.YesMountsTex = preview, widget(nil, preview)
        else page.PetCard, preview.PetBackground = preview, widget(nil, preview) end
    elseif i <= 4 then page.iconsFrame = widget(nil, page)
    else page.ItemsCollectionFrame = widget(nil, page) end
end
MountJournal_InitMountButton = function(button, selected) button.selectedTexture.shown = selected end
PetJournal_InitPetButton = MountJournal_InitMountButton
CollectionsJournal_SetTab_Internal = function(container, id)
    for i, tab in ipairs(container.Tabs) do tab.SelectedTexture.shown = i == id end
end
assert(NS.GenericWindows.ApplyEntry(journal, owner))
local mount, pet = MountJournal.ScrollBox.rows[1], PetJournal.ScrollBox.rows[1]
assert(mount.background.alpha == 0 and pet.background.alpha == 0 and mount.icon.alpha == 1)
assert(ToyBox.iconsFrame.surfaceSpec and HeirloomsJournal.iconsFrame.surfaceSpec and WardrobeCollectionFrame.ItemsCollectionFrame.surfaceSpec)
MountJournal_InitMountButton(mount, true)
PetJournal_InitPetButton(pet, false)
CollectionsJournal_SetTab_Internal(CollectionsJournal.TabContainer, 2)
assert(mount.surfaceActive and not pet.surfaceActive and tabs[2].surfaceActive and not tabs[1].surfaceActive)
assert(tabs[2].Background.alpha == 0 and tabs[2].SelectedTexture.shown and MountJournal.FilterDropdown.controlSpec)
assert(MountJournal.MountDisplay.YesMountsTex.alpha == 0 and MountJournal.MountDisplay.ModelScene.alpha == 1)
assert(PetJournal.PetCard.PetBackground.alpha == 0)
local paints, fades = 0, 0
local ensure, fade = NS.Surface.Ensure, NS.Cosmetics.Fade
NS.Surface.Ensure = function(...) paints = paints + 1 return ensure(...) end
NS.Cosmetics.Fade = function(...) fades = fades + 1 return fade(...) end
for _ = 1, 30 do MountJournal_InitMountButton(mount, true) end
assert(paints == 0 and fades == 0, "row reuse rebuilt static artwork")
function mount.background:GetVertexColor() return 1, 0, 0, 1 end
MountJournal_InitMountButton(mount, false)
assert(mount.background.alpha == 1, "red unusable mount backplate lost")
function mount.background:GetVertexColor() return 1, 1, 1, 1 end
MountJournal_InitMountButton(mount, true)
assert(mount.background.alpha == 0)
f.setCombat(true)
mount.background:SetAlpha(1)
MountJournal_InitMountButton(mount, false)
assert(mount.background.alpha == 0, "native retint leaked ordinary row art during combat")
function mount.background:GetVertexColor() return 1, 0, 0, 1 end
MountJournal_InitMountButton(mount, false)
assert(mount.background.alpha == 1, "combat update lost the unusable mount cue")
CollectionsJournal_SetTab_Internal(CollectionsJournal.TabContainer, 1)
assert(not mount.surfaceActive and tabs[1].surfaceActive and not tabs[2].surfaceActive)
f.setCombat(false)
NS.GenericWindows.Disable(owner)
assert(row.normal.alpha == 1 and mount.background.alpha == 1 and tabs[2].Background.alpha == 1)
ClassTrainerFrame_InitServiceButton(row, 11, true)
assert(row.surfaceVisible == false and row.normal.alpha == 1)

-- The original grip covered the action's bottom-right corner in both panels.
assert(loadfile(skin .. "Rendering/WindowControlNativeArt.lua"))("skin", NS)
assert(loadfile(skin .. "Rendering/WindowControlChrome.lua"))("skin", NS)
NS.WindowControlPolicy = { ScreenRatio = function() return 1 end }
UIParent = { GetWidth = function() return 1280 end }
for _, frame in ipairs({trainerFrame, CollectionsJournal}) do
    local grip = { ClearAllPoints = function() end }
    function grip:SetPoint(point, target, corner)
        assert(point == "TOPLEFT" and target == frame and corner == "BOTTOMRIGHT", "grip overlaps native footer")
    end
    NS.WindowControlChrome.PlaceGrip(grip, {name = frame.name, frame = frame})
end
f.noErrors()
print("Forever trainer selection, training points, native click, journal pages, recycled rows, grips and restore passed")
